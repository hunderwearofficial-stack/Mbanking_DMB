package integration

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/rekey"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"

	"github.com/google/uuid"
)

// TestIntegration_UpgradeFromLegacySchema verifies that the versioned migrations adopt
// a database created by the former GORM AutoMigrate (no schema_migrations table,
// audit_logs without seq/hash columns, admin_users.role defaulting to SUPER_ADMIN)
// without data loss, and that the audit hash chain starts cleanly after legacy rows.
func TestIntegration_UpgradeFromLegacySchema(t *testing.T) {
	e := setupIT(t)
	db := e.db
	legacy := []string{
		`DROP SCHEMA public CASCADE`, `CREATE SCHEMA public`,
		`CREATE TABLE audit_logs (
			id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
			actor_type varchar(20) NOT NULL, actor_id varchar(60), actor_name varchar(100),
			action varchar(60) NOT NULL, target varchar(100), status varchar(20) DEFAULT 'SUCCESS',
			ip_address varchar(50), device_id varchar(120), details text, created_at timestamptz)`,
		`INSERT INTO audit_logs (actor_type, actor_id, action, created_at) VALUES ('NASABAH','u1','LOGIN_SUCCESS', now() - interval '2 day')`,
		`INSERT INTO audit_logs (actor_type, actor_id, action, created_at) VALUES ('ADMIN','BACKOFFICE','ADMIN_LOGIN', now() - interval '1 day')`,
		`CREATE TABLE admin_users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), username varchar(50) NOT NULL,
			full_name varchar(100) NOT NULL, password_hash varchar(255) NOT NULL, role varchar(30) NOT NULL DEFAULT 'SUPER_ADMIN',
			is_active boolean DEFAULT true, created_at timestamptz, updated_at timestamptz)`,
		`INSERT INTO admin_users (username, full_name, password_hash) VALUES ('legacy', 'Legacy Officer', 'x')`,
	}
	for _, s := range legacy {
		if err := db.Exec(s).Error; err != nil {
			t.Fatalf("legacy setup %q: %v", s, err)
		}
	}
	if err := database.EnsureSchemaCurrent(context.Background(), db); err == nil {
		t.Fatal("server start must be refused on an unmigrated legacy database")
	}
	if _, err := database.MigrateUp(context.Background(), db); err != nil {
		t.Fatalf("upgrade migrate failed: %v", err)
	}
	if err := database.EnsureSchemaCurrent(context.Background(), db); err != nil {
		t.Fatalf("schema must be current after migrate up: %v", err)
	}

	var n, withSeq, admins int64
	db.Model(&model.AuditLog{}).Count(&n)
	db.Model(&model.AuditLog{}).Where("seq IS NOT NULL AND seq > 0").Count(&withSeq)
	db.Model(&model.AdminUser{}).Count(&admins)
	if n != 2 || withSeq != 2 || admins != 1 {
		t.Fatalf("legacy data lost or not upgraded: audit=%d seq=%d admins=%d", n, withSeq, admins)
	}
	var roleDefault *string
	db.Raw(`SELECT column_default FROM information_schema.columns WHERE table_name='admin_users' AND column_name='role'`).Scan(&roleDefault)
	if roleDefault != nil && *roleDefault != "" {
		t.Fatalf("admin_users.role must have no default after upgrade, got %q", *roleDefault)
	}
	if err := db.Exec("UPDATE audit_logs SET details = 'x'").Error; err == nil {
		t.Fatal("append-only trigger must be installed by the migrations")
	}

	audit.Record(context.Background(), db, "SYSTEM", "upgrade", "upgrade-test", "UPGRADE_CHECK", "", "SUCCESS", "", "after upgrade")
	broken, err := audit.VerifyChain(context.Background(), db)
	if err != nil || broken != 0 {
		t.Fatalf("chain after upgrade broken at %d (%v)", broken, err)
	}
}

// TestIntegration_MigrationsAreVersionedAndTamperEvident checks idempotency, the
// startup guard and checksum verification of applied migrations.
func TestIntegration_MigrationsAreVersionedAndTamperEvident(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	if done, err := database.MigrateUp(ctx, e.db); err != nil || len(done) != 0 {
		t.Fatalf("second run must be a no-op, got %d (%v)", len(done), err)
	}
	if err := database.EnsureSchemaCurrent(ctx, e.db); err != nil {
		t.Fatal(err)
	}
	var cfgRows int64
	e.db.Model(&model.AppConfig{}).Count(&cfgRows)
	var callCenter string
	e.db.Raw("SELECT COALESCE(call_center, '') FROM app_configs WHERE id = 'DEFAULT'").Scan(&callCenter)
	if cfgRows != 1 || callCenter != "" {
		t.Fatalf("default config must exist without fabricated contact data: rows=%d call_center=%q", cfgRows, callCenter)
	}
	// An applied migration whose recorded checksum differs must be detected.
	e.db.Exec("UPDATE schema_migrations SET checksum = repeat('0', 64) WHERE version = 2")
	if err := database.EnsureSchemaCurrent(ctx, e.db); err == nil || !strings.Contains(err.Error(), "checksum") {
		t.Fatalf("checksum mismatch must be reported, got %v", err)
	}
	// A database newer than the binary must be refused.
	e.db.Exec("UPDATE schema_migrations SET checksum = (SELECT checksum FROM schema_migrations WHERE version = 1) WHERE version = 2")
	e.db.Exec("INSERT INTO schema_migrations (version, name, checksum) VALUES (9999, 'future', repeat('0', 64))")
	if _, err := database.MigrateUp(ctx, e.db); err == nil {
		t.Fatal("unknown future migration must be refused")
	}
}

// TestIntegration_RekeyLegacyPII verifies the key-rotation tool converts plaintext
// and enc:v1 (previous key) values to enc:v2 without changing the plaintext.
func TestIntegration_RekeyLegacyPII(t *testing.T) {
	e := setupIT(t)
	const prevKey = "a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0"
	if err := crypto.InitKeys(itEncKeyHex, prevKey); err != nil {
		t.Fatal(err)
	}
	// Produce a v1 value with the previous key by temporarily making it the active key.
	if err := crypto.InitKeys(prevKey, ""); err != nil {
		t.Fatal(err)
	}
	v2prev, _ := crypto.EncryptString("Ibu Lama")
	legacyV1 := crypto.LegacyCipherPrefix + strings.TrimPrefix(v2prev, crypto.CipherPrefix)
	if err := crypto.InitKeys(itEncKeyHex, prevKey); err != nil {
		t.Fatal(err)
	}

	id := uuid.NewString()
	if err := e.db.Exec(`INSERT INTO users (id, cif, full_name, phone_number, password_hash, pin_hash, email, nama_ibu_kandung, is_active)
		VALUES (?, '009900000001', 'Legacy', 'P-009900000001', '', '', 'legacy@example.co.id', ?, true)`, id, legacyV1).Error; err != nil {
		t.Fatal(err)
	}

	dry, err := rekey.Run(context.Background(), e.db, false, 100)
	if err != nil || dry.NeedsRekey != 1 || dry.Updated != 0 {
		t.Fatalf("dry run unexpected: %+v %v", dry, err)
	}
	st, err := rekey.Run(context.Background(), e.db, true, 100)
	if err != nil || st.Updated != 1 || st.DecryptErrors != 0 {
		t.Fatalf("apply unexpected: %+v %v", st, err)
	}
	var u model.User
	if err := e.db.Where("id = ?", id).First(&u).Error; err != nil {
		t.Fatal(err)
	}
	if string(u.Email) != "legacy@example.co.id" || string(u.NamaIbuKandung) != "Ibu Lama" {
		t.Fatal("plaintext changed by rekey")
	}
	var rawEmail, rawIbu string
	e.db.Raw("SELECT email FROM users WHERE id = ?", id).Scan(&rawEmail)
	e.db.Raw("SELECT nama_ibu_kandung FROM users WHERE id = ?", id).Scan(&rawIbu)
	if !strings.HasPrefix(rawEmail, crypto.CipherPrefix) || !strings.HasPrefix(rawIbu, crypto.CipherPrefix) {
		t.Fatal("values not re-encrypted to v2")
	}
	if again, _ := rekey.Run(context.Background(), e.db, false, 100); again.NeedsRekey != 0 {
		t.Fatal("rekey must be idempotent")
	}
	_ = crypto.InitKeys(itEncKeyHex, "")
}

// TestIntegration_DeviceBindingRollback runs the manual rollback scripts (0015, then
// 0013/0014): customer bindings survive, 0015 revokes App Attest keys without deleting
// any key row, and migrating up again restores the schema (re-runnable after rollback).
func TestIntegration_DeviceBindingRollback(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	u := e.seedCustomer("001000000401", "081200000401", "SAMSUNG-SM-A515F-0000ABCD", "0010100000401", 1000)
	sqlDB, _ := e.db.DB()
	run := func(name string) {
		script, err := os.ReadFile("../../pkg/database/rollback/" + name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := sqlDB.ExecContext(ctx, string(script)); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	// An App Attest key and an ES256 key exist before the rollback of 0015.
	e.db.Exec(`INSERT INTO device_keys (user_id, device_id, platform, algorithm, public_key, key_fingerprint, security_level, enrolled_via, app_attest_key_id, attestation_status)
		VALUES (?, 'ios-x', 'ios', 'APPATTEST', 'pk', repeat('a', 64), 'SECURE_ENCLAVE', 'OTP_ENROLLMENT', 'kid', 'HARDWARE_VERIFIED')`, u.ID)
	run("0015_device_attestation_down.sql")
	var keys, active, maxVersion int64
	e.db.Raw("SELECT count(*) FROM device_keys").Scan(&keys)
	e.db.Raw("SELECT count(*) FROM device_keys WHERE status = 'ACTIVE'").Scan(&active)
	e.db.Raw("SELECT max(version) FROM schema_migrations").Scan(&maxVersion)
	if keys != 1 || active != 0 || maxVersion != 14 {
		t.Fatalf("after 0015 rollback: keys=%d active=%d max_version=%d", keys, active, maxVersion)
	}
	e.db.Exec("DELETE FROM device_keys") // test fixture cleanup before dropping the tables
	run("0013_0014_device_key_binding_down.sql")
	var tables int64
	e.db.Raw("SELECT count(*) FROM information_schema.tables WHERE table_name IN ('device_keys','device_challenges')").Scan(&tables)
	e.db.Raw("SELECT max(version) FROM schema_migrations").Scan(&maxVersion)
	var dev string
	e.db.Raw("SELECT device_id FROM users WHERE id = ?", u.ID).Scan(&dev)
	if tables != 0 || maxVersion != 12 || dev != "SAMSUNG-SM-A515F-0000ABCD" {
		t.Fatalf("after rollback: tables=%d max_version=%d binding=%q", tables, maxVersion, dev)
	}
	done, err := database.MigrateUp(ctx, e.db)
	if err != nil || len(done) != 3 {
		t.Fatalf("migrate up after rollback: %v (%d applied)", err, len(done))
	}
	if err := database.EnsureSchemaCurrent(ctx, e.db); err != nil {
		t.Fatal(err)
	}
	e.db.Raw("SELECT device_id FROM users WHERE id = ?", u.ID).Scan(&dev)
	if dev != "SAMSUNG-SM-A515F-0000ABCD" {
		t.Fatal("existing binding must survive migrate up/down/up")
	}
}

// TestIntegration_PurgeDeviceChallenges (DB-M3): only challenges expired longer than the
// retention period are deleted, the retention cannot be shorter than 24 hours, and the
// application role cannot delete challenges itself (see db_roles_test).
func TestIntegration_PurgeDeviceChallenges(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	for _, age := range []string{"40 days", "31 days", "2 days", "0 days"} {
		if err := e.db.Exec(`INSERT INTO device_challenges (id, purpose, device_id, nonce, expires_at)
			VALUES (gen_random_uuid(), 'LOGIN', 'and-0000000000000001', 'n', now() - ?::interval)`, age).Error; err != nil {
			t.Fatal(err)
		}
	}
	if _, err := devicebind.PurgeChallenges(ctx, e.db, time.Hour); err == nil {
		t.Fatal("retention below 24 hours must be refused")
	}
	n, err := devicebind.PurgeChallenges(ctx, e.db, 30*24*time.Hour)
	if err != nil || n != 2 {
		t.Fatalf("purge: deleted=%d err=%v", n, err)
	}
	var left int64
	e.db.Raw("SELECT count(*) FROM device_challenges").Scan(&left)
	if left != 2 {
		t.Fatalf("recent challenges must remain, got %d", left)
	}
}
