package integration

// End-to-end security regression tests against a real PostgreSQL instance.
//
// They run only when DMB_IT_DB_HOST/PORT/USER/PASS/NAME are set, and refuse to
// run unless the database name ends with "_test" (the schema is dropped!).
// Example (throwaway container):
//   docker run -d --name dmb_it_pg -e POSTGRES_PASSWORD=<random> -e POSTGRES_DB=dmb_it_test \
//     -p 127.0.0.1:15433:5432 postgres:16-alpine

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/app"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"
	"mbanking-bpr/pkg/money"
	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/security"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	itCustomerSecret = "it-only-customer-secret-0123456789abcdefghij"
	itAdminSecret    = "it-only-admin-secret-zyxwvutsrqponmlkjihgfedc"
	itEncKeyHex      = "4c1d2e3f405162738495a6b7c8d9eafb0c1d2e3f405162738495a6b7c8d9eafb"
	itPassword       = "Rahasia-Uji-2026"
	itPIN            = "582913"
	devA             = "TEST-DEVICE-AAAA01"
	devB             = "TEST-DEVICE-BBBB02"
)

type itEnv struct {
	t      *testing.T
	db     *gorm.DB
	router *gin.Engine
	deps   *app.Deps
	cfg    *config.Config
}

type apiResp struct {
	Status int
	Body   map[string]interface{}
}

func (r apiResp) data() map[string]interface{} {
	d, _ := r.Body["data"].(map[string]interface{})
	return d
}

// setupIT prepares a fresh schema with the migrated Terms (version 1) published through
// the maker-checker workflow, as a bank would do before go-live.
func setupIT(t *testing.T) *itEnv {
	t.Helper()
	e := setupITNoTerms(t)
	e.publishInitialTerms()
	return e
}

// setupITNoTerms prepares a fresh schema where no Terms version is published yet.
func setupITNoTerms(t *testing.T) *itEnv {
	t.Helper()
	host := os.Getenv("DMB_IT_DB_HOST")
	name := os.Getenv("DMB_IT_DB_NAME")
	if host == "" || name == "" {
		t.Skip("integration test dilewati: DMB_IT_DB_* tidak diset")
	}
	if !strings.HasSuffix(name, "_test") {
		t.Fatalf("menolak berjalan: nama database harus berakhiran _test (got %q)", name)
	}
	gin.SetMode(gin.TestMode)
	cfg := &config.Config{
		AppEnv: "test", JWTSecret: itCustomerSecret, AdminJWTSecret: itAdminSecret,
		JWTExpiryMinutes: 15, RefreshTokenDays: 7, AdminJWTExpiryMinutes: 60,
		DBEncryptionKey: itEncKeyHex, EnableMockCBS: true,
		DBHost: host, DBPort: os.Getenv("DMB_IT_DB_PORT"), DBUser: os.Getenv("DMB_IT_DB_USER"),
		DBPass: os.Getenv("DMB_IT_DB_PASS"), DBName: name, DBSSL: "disable",
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("config: %v", err)
	}
	if err := crypto.InitKeys(cfg.DBEncryptionKey, ""); err != nil {
		t.Fatal(err)
	}
	otp.Configure(false)
	db, err := database.InitPostgres(cfg)
	if err != nil {
		t.Fatalf("db: %v", err)
	}
	for _, s := range []string{"DROP SCHEMA public CASCADE", "CREATE SCHEMA public"} {
		if err := db.Exec(s).Error; err != nil {
			t.Fatal(err)
		}
	}
	if _, err := database.MigrateUp(context.Background(), db); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	r, deps, err := app.NewRouter(cfg, db, redis.NewMemoryClient(), cbsprovider.NewDatabaseCBSProvider(db))
	if err != nil {
		t.Fatal(err)
	}
	return &itEnv{t: t, db: db, router: r, deps: deps, cfg: cfg}
}

func (e *itEnv) call(method, path string, body interface{}, headers map[string]string) apiResp {
	e.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	e.router.ServeHTTP(w, req)
	var m map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &m)
	return apiResp{Status: w.Code, Body: m}
}

func auth(token, device string) map[string]string {
	return map[string]string{"Authorization": "Bearer " + token, "X-Device-ID": device}
}

// seedCustomer creates an activated customer with one account in the local "CBS".
func (e *itEnv) seedCustomer(cif, phone, device, accountNo string, balanceRupiah int64) *model.User {
	e.t.Helper()
	pw, _ := security.HashPassword(itPassword)
	pin, _ := security.HashPIN(itPIN)
	u := &model.User{ID: uuid.NewString(), CIF: cif, FullName: "Nasabah " + cif, PhoneNumber: phone,
		Email: crypto.EncryptedString("nasabah." + cif + "@example.co.id"), NamaIbuKandung: crypto.EncryptedString("Ibu " + cif),
		PasswordHash: pw, PINHash: pin, DeviceID: device, IsActive: true}
	if err := e.db.Create(u).Error; err != nil {
		e.t.Fatal(err)
	}
	if err := e.db.Create(&model.Account{ID: uuid.NewString(), UserID: u.ID, AccountNumber: accountNo, HolderName: u.FullName,
		Balance: money.Rupiah(balanceRupiah), EffectiveBalance: money.Rupiah(balanceRupiah), Status: model.AccountStatusActive}).Error; err != nil {
		e.t.Fatal(err)
	}
	return u
}

func (e *itEnv) seedAdmin(username, role string) {
	e.t.Helper()
	pw, _ := security.HashPassword(itPassword + "-admin")
	if err := e.db.Create(&model.AdminUser{ID: uuid.NewString(), Username: username, FullName: username,
		PasswordHash: pw, Role: role, IsActive: true}).Error; err != nil {
		e.t.Fatal(err)
	}
}

func (e *itEnv) login(phone, device string) (string, string) {
	e.t.Helper()
	acc := e.acceptTerms(device)
	r := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": phone, "password": itPassword, "device_id": device, "terms_acceptance_id": acc}, map[string]string{"X-Device-ID": device})
	if r.Status != 200 {
		e.t.Fatalf("login %s failed: %d %v", phone, r.Status, r.Body)
	}
	return r.data()["access_token"].(string), r.data()["refresh_token"].(string)
}

func (e *itEnv) adminLogin(username string) string {
	e.t.Helper()
	r := e.call("POST", "/api/v1/admin/login", map[string]string{"username": username, "password": itPassword + "-admin"}, nil)
	if r.Status != 200 {
		e.t.Fatalf("admin login failed: %d %v", r.Status, r.Body)
	}
	return r.data()["token"].(string)
}

func TestIntegration_SecurityRegressions(t *testing.T) {
	e := setupIT(t)
	const accA, accB = "0010100000001", "0010100000002"
	a := e.seedCustomer("001000000101", "081200000101", devA, accA, 1_000_000)
	e.seedCustomer("001000000102", "081200000102", devB, accB, 1_000_000)
	e.seedAdmin("petugas_sa", model.AdminRoleSuperAdmin)
	e.seedAdmin("petugas_mkt", model.AdminRoleMarketing)

	tokA, refreshA := e.login("081200000101", devA)
	hA := auth(tokA, devA)

	t.Run("DMB-001 customer token rejected on admin API", func(t *testing.T) {
		for _, p := range []string{"/api/v1/admin/customers", "/api/v1/admin/users", "/api/v1/admin/config"} {
			if r := e.call("GET", p, nil, hA); r.Status != http.StatusUnauthorized {
				t.Fatalf("%s: expected 401, got %d", p, r.Status)
			}
		}
	})

	t.Run("DMB-021 RBAC enforced per role", func(t *testing.T) {
		mk := e.adminLogin("petugas_mkt")
		if r := e.call("GET", "/api/v1/admin/users", nil, map[string]string{"Authorization": "Bearer " + mk}); r.Status != http.StatusForbidden {
			t.Fatalf("marketing on /users: expected 403, got %d", r.Status)
		}
		if r := e.call("GET", "/api/v1/admin/banners", nil, map[string]string{"Authorization": "Bearer " + mk}); r.Status != 200 {
			t.Fatalf("marketing on /banners: expected 200, got %d", r.Status)
		}
		sa := e.adminLogin("petugas_sa")
		r := e.call("GET", "/api/v1/admin/customers", nil, map[string]string{"Authorization": "Bearer " + sa})
		if r.Status != 200 {
			t.Fatalf("super admin on /customers: %d", r.Status)
		}
		raw, _ := json.Marshal(r.Body)
		if strings.Contains(string(raw), "nama_ibu_kandung") || strings.Contains(string(raw), "\"nik\"") {
			t.Fatal("customer list must not expose NIK / mother's maiden name")
		}
		// Admin token must not work on the customer API.
		if r := e.call("GET", "/api/v1/account/balance", nil, map[string]string{"Authorization": "Bearer " + sa, "X-Device-ID": devA}); r.Status != http.StatusUnauthorized {
			t.Fatalf("admin token on customer API: expected 401, got %d", r.Status)
		}
	})

	t.Run("DMB-006 public config exposes no secrets", func(t *testing.T) {
		e.db.Model(&model.AppConfig{}).Where("id = ?", "DEFAULT").Updates(map[string]interface{}{"otp_gateway_token": "it-secret-token-value"})
		r := e.call("GET", "/api/v1/config", nil, nil)
		raw, _ := json.Marshal(r.Body)
		if r.Status != 200 || strings.Contains(string(raw), "it-secret") || strings.Contains(string(raw), "otp_gateway_token") {
			t.Fatalf("public config leaks secrets: %s", raw)
		}
	})

	t.Run("DMB-005 BOLA on account endpoints", func(t *testing.T) {
		if r := e.call("GET", "/api/v1/account/balance?account_number="+accB, nil, hA); r.Status != http.StatusForbidden {
			t.Fatalf("foreign balance: expected 403, got %d", r.Status)
		}
		if r := e.call("GET", "/api/v1/account/mutations?account_number="+accB, nil, hA); r.Status != http.StatusForbidden {
			t.Fatalf("foreign mutations: expected 403, got %d", r.Status)
		}
		r := e.call("GET", "/api/v1/account/balance", nil, hA)
		if r.Status != 200 || r.data()["account_number"] != accA {
			t.Fatalf("own balance: %d %v", r.Status, r.Body)
		}
		p := e.call("GET", "/api/v1/account/profile?cif_number=001000000102", nil, hA)
		if p.Status != 200 || p.data()["cif"] == "001000000102" {
			t.Fatalf("profile must ignore client CIF: %v", p.Body)
		}
		if v, _ := p.data()["nama_ibu_kandung"].(string); v != "" {
			t.Fatal("profile must not return mother's maiden name")
		}
	})

	t.Run("DMB-013 password login from a new device requires OTP", func(t *testing.T) {
		r := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000102", "password": itPassword, "device_id": "ATTACKER-DEVICE-1"}, nil)
		if r.Status != http.StatusForbidden || r.Body["response_code"] != "08" {
			t.Fatalf("new device login: expected 403/08, got %d %v", r.Status, r.Body)
		}
	})

	t.Run("DMB-014 refresh rotation and reuse detection", func(t *testing.T) {
		r1 := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refreshA}, map[string]string{"X-Device-ID": devA})
		if r1.Status != 200 {
			t.Fatalf("refresh: %d %v", r1.Status, r1.Body)
		}
		newRefresh := r1.data()["refresh_token"].(string)
		// Simulate reuse of the old token after the concurrency grace window.
		e.db.Model(&model.UserSession{}).Where("user_id = ?", a.ID).Update("rotated_at", time.Now().Add(-time.Hour))
		if r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refreshA}, map[string]string{"X-Device-ID": devA}); r.Status != http.StatusUnauthorized {
			t.Fatalf("reused refresh token: expected 401, got %d", r.Status)
		}
		if r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": newRefresh}, map[string]string{"X-Device-ID": devA}); r.Status == 200 {
			t.Fatal("after reuse detection the whole session family must be revoked")
		}
	})

	t.Run("DMB-014 logout revokes the session", func(t *testing.T) {
		tok, _ := e.login("081200000101", devA)
		h := auth(tok, devA)
		if r := e.call("GET", "/api/v1/account/balance", nil, h); r.Status != 200 {
			t.Fatalf("pre-logout: %d", r.Status)
		}
		if r := e.call("POST", "/api/v1/auth/logout", nil, h); r.Status != 200 {
			t.Fatalf("logout: %d", r.Status)
		}
		if r := e.call("GET", "/api/v1/account/balance", nil, h); r.Status != http.StatusUnauthorized {
			t.Fatalf("token still valid after logout: %d", r.Status)
		}
	})

	t.Run("DMB-002/012 OTP: no master code, attempt limit, device binding", func(t *testing.T) {
		ctx := context.Background()
		sid, err := e.deps.OTPStore.Create(ctx, otp.Session{Purpose: otp.PurposeActivation, UserID: a.ID, PhoneNumber: "081200000101", DeviceID: devA}, "640219")
		if err != nil {
			t.Fatal(err)
		}
		if r := e.call("POST", "/api/v1/auth/activate/otp", map[string]string{"session_id": sid, "otp_code": "123456"}, map[string]string{"X-Device-ID": devA}); r.Status == 200 {
			t.Fatal("static code accepted")
		}
		if r := e.call("POST", "/api/v1/auth/activate/otp", map[string]string{"session_id": sid, "otp_code": "640219"}, map[string]string{"X-Device-ID": "OTHER-DEVICE-99"}); r.Status == 200 {
			t.Fatal("OTP accepted from a different device")
		}
		if r := e.call("POST", "/api/v1/auth/activate/otp", map[string]string{"session_id": sid, "otp_code": "640219"}, map[string]string{"X-Device-ID": devA}); r.Status != 200 {
			t.Fatalf("correct OTP rejected: %d %v", r.Status, r.Body)
		}
		weak := e.call("POST", "/api/v1/auth/activate/setup", map[string]string{"session_id": sid, "password": "Baru-Aman-2026", "pin": "111111"}, map[string]string{"X-Device-ID": devA})
		if weak.Status == 200 {
			t.Fatal("weak PIN accepted at activation")
		}
	})

	t.Run("DMB-018 change-PIN is not a PIN oracle", func(t *testing.T) {
		tok, _ := e.login("081200000102", devB)
		h := auth(tok, devB)
		var last apiResp
		for i := 0; i < 3; i++ {
			last = e.call("POST", "/api/v1/auth/change-pin", map[string]string{"old_pin": fmt.Sprintf("90817%d", i), "new_pin": "604913"}, h)
		}
		var u model.User
		e.db.Where("cif = ?", "001000000102").First(&u)
		if u.IsActive {
			t.Fatalf("account must be blocked after 3 wrong PINs (last=%d %v)", last.Status, last.Body)
		}
	})

	t.Run("DMB-016 audit trail is hash-chained and append-only", func(t *testing.T) {
		var n int64
		e.db.Model(&model.AuditLog{}).Count(&n)
		if n == 0 {
			t.Fatal("no audit records written")
		}
		broken, err := audit.VerifyChain(context.Background(), e.db)
		if err != nil || broken != 0 {
			t.Fatalf("hash chain broken at seq %d (%v)", broken, err)
		}
		if err := e.db.Exec("UPDATE audit_logs SET details = 'tampered'").Error; err == nil {
			t.Fatal("UPDATE on audit_logs must be rejected")
		}
		if err := e.db.Exec("DELETE FROM audit_logs").Error; err == nil {
			t.Fatal("DELETE on audit_logs must be rejected")
		}
		var withIP int64
		e.db.Model(&model.AuditLog{}).Where("ip_address <> ''").Count(&withIP)
		if withIP == 0 {
			t.Fatal("audit records must carry the client IP")
		}
	})

	t.Run("DMB-008 PII is encrypted at rest with the v2 key", func(t *testing.T) {
		var raw string
		e.db.Raw("SELECT email FROM users WHERE cif = ?", "001000000101").Scan(&raw)
		if !strings.HasPrefix(raw, crypto.CipherPrefix) {
			t.Fatalf("Email not encrypted with current key format: %.12s...", raw)
		}
	})
}
