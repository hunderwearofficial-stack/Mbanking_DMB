package integration

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"os"
	"strings"
	"testing"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/legaldoc/pdfdoc"
	"mbanking-bpr/pkg/database"
)

// TestIntegration_ApplicationRoleCannotTamperWithAuditTrail creates the separated
// roles (as deploy/sql/create_roles.sql does), applies the privilege migration and
// connects as the application role: it can write audit entries and use business
// tables, but cannot modify, delete, truncate or un-protect the audit trail.
func TestIntegration_ApplicationRoleCannotTamperWithAuditTrail(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	appPass := hex.EncodeToString(buf)

	for _, s := range []string{
		`DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='mbanking_app') THEN CREATE ROLE mbanking_app LOGIN; END IF; END $$`,
		`DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='mbanking_audit_reader') THEN CREATE ROLE mbanking_audit_reader LOGIN; END IF; END $$`,
		`ALTER ROLE mbanking_app PASSWORD '` + appPass + `'`,
	} {
		if err := e.db.Exec(s).Error; err != nil {
			t.Fatal(err)
		}
	}
	if err := database.ApplyRolePrivileges(ctx, e.db); err != nil {
		t.Fatalf("grants: %v", err)
	}

	appCfg := &config.Config{DBHost: os.Getenv("DMB_IT_DB_HOST"), DBPort: os.Getenv("DMB_IT_DB_PORT"), DBUser: "mbanking_app",
		DBPass: appPass, DBName: os.Getenv("DMB_IT_DB_NAME"), DBSSL: "disable", DBMaxOpenConns: 2, DBMaxIdleConns: 1}
	appDB, err := database.InitPostgres(appCfg)
	if err != nil {
		t.Fatalf("connect as app role: %v", err)
	}
	defer func() {
		if sqlDB, err := appDB.DB(); err == nil {
			sqlDB.Close()
		}
	}()
	if err := database.EnsureSchemaCurrent(ctx, appDB); err != nil {
		t.Fatalf("app role must be able to verify the schema: %v", err)
	}
	if err := appDB.Exec("SELECT count(*) FROM users").Error; err != nil {
		t.Fatalf("app role must read business tables: %v", err)
	}
	audit.Record(ctx, appDB, "SYSTEM", "it", "role-test", "ROLE_TEST", "", "SUCCESS", "", "ditulis oleh role aplikasi")
	var written int64
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE action = 'ROLE_TEST'").Scan(&written)
	if written != 1 {
		t.Fatal("app role must be able to append audit entries")
	}
	for _, stmt := range []string{
		"UPDATE audit_logs SET details = 'x'",
		"DELETE FROM audit_logs",
		"TRUNCATE audit_logs",
		"ALTER TABLE audit_logs DISABLE TRIGGER USER",
		"DROP TRIGGER trg_audit_logs_append_only ON audit_logs",
		"CREATE TABLE should_not_exist (id int)",
		// Device keys and challenges are revoked/consumed by status, never deleted.
		"DELETE FROM device_keys",
		"DELETE FROM device_challenges",
		"TRUNCATE device_keys",
	} {
		err := appDB.Exec(stmt).Error
		if err == nil {
			t.Errorf("app role must not be allowed: %s", stmt)
			continue
		}
		msg := err.Error()
		if !strings.Contains(msg, "permission denied") && !strings.Contains(msg, "must be owner") && !strings.Contains(msg, "append-only") {
			t.Errorf("%s: unexpected error %v", stmt, err)
		}
	}
	if seq, err := audit.VerifyChain(ctx, appDB); err != nil {
		t.Fatalf("chain must remain intact (seq %d): %v", seq, err)
	}

	// The Terms workflow and consent recording work with the application role only
	// (grants 0009), while consent records and stored PDFs stay immutable for it.
	u := e.seedCustomer("001000000401", "081200000401", devA, "9900000000401", 0)
	svc := legaldoc.NewService(appDB, legaldoc.NewDBFileStore(appDB), pdfdoc.RenderPDF)
	active, content, err := svc.Active(ctx)
	if err != nil {
		t.Fatalf("app role must read the Terms in force: %v", err)
	}
	d, err := svc.CreateDraft(ctx, itMaker, legaldoc.DraftInput{Content: content, ChangeSummary: "uji role aplikasi"})
	if err != nil {
		t.Fatalf("draft as app role: %v", err)
	}
	if _, err := svc.GenerateDraftPDF(ctx, itMaker, d.ID); err != nil {
		t.Fatalf("pdf as app role: %v", err)
	}
	if _, err := svc.Submit(ctx, itMaker, d.ID, nil); err != nil {
		t.Fatalf("submit as app role: %v", err)
	}
	if _, err := svc.Approve(ctx, itChecker, d.ID); err != nil {
		t.Fatalf("approve as app role: %v", err)
	}
	if _, err := svc.Archive(ctx, itChecker, active.ID); err != nil {
		t.Fatalf("archive superseded version as app role: %v", err)
	}
	pre, err := svc.AcceptPreLogin(ctx, d.ID, devA, legaldoc.ClientMeta{IP: "198.51.100.7", UserAgent: "it"})
	if err != nil {
		t.Fatalf("pre-login consent as app role: %v", err)
	}
	if err := svc.EnsureUserConsent(ctx, u.ID, devA, pre.ID, legaldoc.ChannelLogin, legaldoc.ClientMeta{}); err != nil {
		t.Fatalf("link consent as app role: %v", err)
	}
	for _, stmt := range []string{
		"UPDATE legal_acceptances SET status = 'ACCEPTED'",
		"DELETE FROM legal_acceptances",
		"UPDATE stored_files SET content_type = 'x'",
		"DELETE FROM stored_files",
		"DELETE FROM legal_document_versions",
		"UPDATE legal_document_versions SET content = '{}'::jsonb WHERE status = 'PUBLISHED'",
		"ALTER TABLE legal_acceptances DISABLE TRIGGER USER",
	} {
		if err := appDB.Exec(stmt).Error; err == nil {
			t.Errorf("app role must not be allowed: %s", stmt)
		}
	}
}
