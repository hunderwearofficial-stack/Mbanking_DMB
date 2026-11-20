package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/security"

	"github.com/gin-gonic/gin"
)

const (
	rtCustomerSecret = "router-test-customer-secret-0123456789abcdef"
	rtAdminSecret    = "router-test-admin-secret-fedcba9876543210zyxw"
)

func newTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	cfg := &config.Config{
		AppEnv: "test", JWTSecret: rtCustomerSecret, AdminJWTSecret: rtAdminSecret,
		JWTExpiryMinutes: 15, RefreshTokenDays: 7, AdminJWTExpiryMinutes: 60,
	}
	r, _, err := NewRouter(cfg, nil, redis.NewMemoryClient(), cbsprovider.NewDatabaseCBSProvider(nil))
	if err != nil {
		t.Fatalf("NewRouter: %v", err)
	}
	return r
}

func do(r *gin.Engine, method, path, bearer string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader("{}"))
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
		req.Header.Set("X-Device-ID", "ROUTER-TEST-DEVICE-01")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestHealthIsMinimal(t *testing.T) {
	w := do(newTestRouter(t), http.MethodGet, "/health", "")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var body map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	data, _ := body["data"].(map[string]interface{})
	if data["status"] != "UP" {
		t.Fatalf("unexpected health payload: %s", w.Body.String())
	}
	for _, leak := range []string{"cbs", "database", "postgres", "redis", "version"} {
		if strings.Contains(strings.ToLower(w.Body.String()), leak) {
			t.Fatalf("health response discloses %q: %s", leak, w.Body.String())
		}
	}
}

func TestSecurityHeaders(t *testing.T) {
	w := do(newTestRouter(t), http.MethodGet, "/health", "")
	want := map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "no-referrer",
	}
	for k, v := range want {
		if got := w.Header().Get(k); got != v {
			t.Errorf("header %s = %q, want %q", k, got, v)
		}
	}
}

func TestCustomerRoutesRequireAuthentication(t *testing.T) {
	r := newTestRouter(t)
	routes := [][2]string{
		{"POST", "/api/v1/auth/logout"},
		{"POST", "/api/v1/auth/change-password"},
		{"POST", "/api/v1/auth/change-pin"},
		{"GET", "/api/v1/account/balance"},
		{"GET", "/api/v1/account/mutations"},
		{"GET", "/api/v1/account/profile"},
		{"GET", "/api/v1/account/list"},
		{"GET", "/api/v1/account/loans"},
		{"GET", "/api/v1/account/deposits"},
		{"GET", "/api/v1/account/products"},
		{"GET", "/api/v1/applications"},
		{"POST", "/api/v1/applications"},
		{"GET", "/api/v1/notifications"},
		{"POST", "/api/v1/notifications/read"},
		{"POST", "/api/v1/notifications/fcm-token"},
		{"GET", "/api/v1/device/status"},
		{"POST", "/api/v1/device/challenge"},
		{"POST", "/api/v1/device/enroll"},
		{"POST", "/api/v1/device/keys/rotate"},
	}
	for _, rt := range routes {
		if w := do(r, rt[0], rt[1], ""); w.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without token: got %d, want 401", rt[0], rt[1], w.Code)
		}
	}
}

func TestAdminRoutesRequireAuthentication(t *testing.T) {
	r := newTestRouter(t)
	routes := [][2]string{
		{"GET", "/api/v1/admin/stats"},
		{"GET", "/api/v1/admin/customers"},
		{"POST", "/api/v1/admin/customers/x/reset-device"},
		{"GET", "/api/v1/admin/audit-logs"},
		{"GET", "/api/v1/admin/config"},
		{"PUT", "/api/v1/admin/config"},
		{"POST", "/api/v1/admin/upload"},
		{"GET", "/api/v1/admin/users"},
		{"POST", "/api/v1/admin/push/campaigns"},
		{"POST", "/api/v1/admin/push/credential"},
		{"GET", "/api/v1/admin/device-binding/summary"},
		{"GET", "/api/v1/admin/cbs/health"},
		{"POST", "/api/v1/admin/cbs/refresh-token"},
	}
	for _, rt := range routes {
		if w := do(r, rt[0], rt[1], ""); w.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without token: got %d, want 401", rt[0], rt[1], w.Code)
		}
	}
}

func TestTokensAreNotInterchangeable(t *testing.T) {
	r := newTestRouter(t)
	pair, err := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: "u-1", CIF: "000000000001", DeviceID: "ROUTER-TEST-DEVICE-01", SessionID: "s-1",
	}, rtCustomerSecret, 15*time.Minute, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if w := do(r, http.MethodGet, "/api/v1/admin/stats", pair.AccessToken); w.Code != http.StatusUnauthorized {
		t.Errorf("customer token on admin route: got %d, want 401", w.Code)
	}
	adminTok, _, err := security.GenerateAdminToken("a-1", "officer", "SUPER_ADMIN", rtAdminSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if w := do(r, http.MethodGet, "/api/v1/account/balance", adminTok); w.Code != http.StatusUnauthorized {
		t.Errorf("admin token on customer route: got %d, want 401", w.Code)
	}
}

func TestAuthFailsClosedWithoutDatabase(t *testing.T) {
	r := newTestRouter(t)
	pair, _ := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: "u-1", CIF: "000000000001", DeviceID: "ROUTER-TEST-DEVICE-01", SessionID: "s-1",
	}, rtCustomerSecret, 15*time.Minute, time.Hour)
	if w := do(r, http.MethodGet, "/api/v1/account/balance", pair.AccessToken); w.Code != http.StatusServiceUnavailable {
		t.Errorf("customer route without DB: got %d, want 503", w.Code)
	}
	adminTok, _, _ := security.GenerateAdminToken("a-1", "officer", "SUPER_ADMIN", rtAdminSecret, time.Hour)
	if w := do(r, http.MethodGet, "/api/v1/admin/stats", adminTok); w.Code != http.StatusServiceUnavailable {
		t.Errorf("admin route without DB: got %d, want 503", w.Code)
	}
}

func TestLegacyPublicCBSEndpointsRemoved(t *testing.T) {
	r := newTestRouter(t)
	for _, rt := range [][2]string{{"GET", "/api/v1/cbs/health"}, {"POST", "/api/v1/cbs/refresh-token"}} {
		if w := do(r, rt[0], rt[1], ""); w.Code != http.StatusNotFound {
			t.Errorf("%s %s: got %d, want 404", rt[0], rt[1], w.Code)
		}
	}
}

// Fund transfer is not a feature of Mobile DMB: none of its endpoints may be routable.
func TestFundTransferEndpointsRemoved(t *testing.T) {
	r := newTestRouter(t)
	for _, rt := range [][2]string{
		{"POST", "/api/v1/transaction/transfer"},
		{"GET", "/api/v1/beneficiaries"},
		{"POST", "/api/v1/beneficiaries"},
		{"DELETE", "/api/v1/beneficiaries/x"},
		{"GET", "/api/v1/account/inquiry"},
		{"GET", "/api/v1/admin/transactions"},
	} {
		if w := do(r, rt[0], rt[1], ""); w.Code != http.StatusNotFound {
			t.Errorf("%s %s: got %d, want 404", rt[0], rt[1], w.Code)
		}
	}
}

func TestTermsEndpointsFailClosedWithoutDatabase(t *testing.T) {
	r := newTestRouter(t)
	for _, rt := range [][2]string{
		{http.MethodGet, "/api/v1/terms/active"},
		{http.MethodGet, "/api/v1/terms/versions/00000000-0000-0000-0000-000000000001/pdf"},
	} {
		if w := do(r, rt[0], rt[1], ""); w.Code != http.StatusServiceUnavailable {
			t.Errorf("%s %s without DB: got %d, want 503", rt[0], rt[1], w.Code)
		}
	}
	if w := do(r, http.MethodGet, "/api/v1/admin/terms/versions", ""); w.Code != http.StatusUnauthorized && w.Code != http.StatusServiceUnavailable {
		t.Errorf("admin terms without token: got %d", w.Code)
	}
}
