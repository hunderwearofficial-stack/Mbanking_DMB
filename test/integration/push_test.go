package integration

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/push"
)

// fakeGoogle imitates the Google OAuth token endpoint and FCM HTTP v1 (test double only).
type fakeGoogle struct {
	mu       sync.Mutex
	rejectSA bool
	sent     []map[string]interface{} // accepted, non-validate-only messages
	flaky    map[string]int
	srv      *httptest.Server
}

func newFakeGoogle(t *testing.T) *fakeGoogle {
	f := &fakeGoogle{flaky: map[string]int{}}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/token" {
			if f.rejectSA {
				w.WriteHeader(400)
				_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"Invalid JWT Signature."}`))
				return
			}
			_, _ = w.Write([]byte(`{"access_token":"test-access-token","expires_in":3600}`))
			return
		}
		if !strings.HasPrefix(r.URL.Path, "/v1/projects/it-project/messages:send") || r.Header.Get("Authorization") != "Bearer test-access-token" {
			w.WriteHeader(403)
			_, _ = w.Write([]byte(`{"error":{"status":"PERMISSION_DENIED","message":"denied"}}`))
			return
		}
		raw, _ := io.ReadAll(r.Body)
		var req struct {
			ValidateOnly bool                   `json:"validate_only"`
			Message      map[string]interface{} `json:"message"`
		}
		_ = json.Unmarshal(raw, &req)
		tok, _ := req.Message["token"].(string)
		fail := func(status int, code string) {
			w.WriteHeader(status)
			_, _ = w.Write([]byte(`{"error":{"status":"` + code + `","message":"simulated","details":[{"errorCode":"` + code + `"}]}}`))
		}
		switch {
		case strings.Contains(tok, "placeholder"):
			fail(400, "INVALID_ARGUMENT")
		case strings.Contains(tok, "dead"):
			fail(404, "UNREGISTERED")
		case strings.Contains(tok, "down"):
			fail(503, "UNAVAILABLE")
		case strings.Contains(tok, "flaky") && f.flaky[tok] < 2:
			f.flaky[tok]++
			fail(503, "UNAVAILABLE")
		default:
			if !req.ValidateOnly {
				f.sent = append(f.sent, req.Message)
			}
			_, _ = w.Write([]byte(`{"name":"projects/it-project/messages/0:fake"}`))
		}
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func testServiceAccount(t *testing.T) []byte {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	raw, _ := json.Marshal(map[string]string{
		"type": "service_account", "project_id": "it-project", "private_key_id": "it-key-1",
		"private_key": string(pemKey), "client_email": "firebase-adminsdk@it-project.iam.gserviceaccount.com",
	})
	return raw
}

func (e *itEnv) upload(path, token string, file []byte) apiResp {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, _ := mw.CreateFormFile("file", "service-account.json")
	_, _ = fw.Write(file)
	mw.Close()
	req := httptest.NewRequest("POST", path, &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	e.router.ServeHTTP(w, req)
	var m map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &m)
	return apiResp{Status: w.Code, Body: m}
}

func TestIntegration_PushNotificationsFCM(t *testing.T) {
	e := setupIT(t)
	google := newFakeGoogle(t)
	e.deps.Push.SetEndpoints(google.srv.URL+"/token", google.srv.URL, func(int) time.Duration { return time.Millisecond })
	e.seedAdmin("push-sa", model.AdminRoleSuperAdmin)
	e.seedAdmin("push-mk", model.AdminRoleMarketing)
	e.seedAdmin("push-co", model.AdminRoleCompliance)
	e.seedAdmin("push-cs", model.AdminRoleCS)
	saTok, mkTok, coTok, csTok := e.adminLogin("push-sa"), e.adminLogin("push-mk"), e.adminLogin("push-co"), e.adminLogin("push-cs")
	hdr := func(tok string) map[string]string { return map[string]string{"Authorization": "Bearer " + tok} }
	admin := func(method, path string, body interface{}, tok string) apiResp {
		return e.call(method, "/api/v1/admin/push"+path, body, hdr(tok))
	}
	sa := testServiceAccount(t)

	// ---- Firebase integration: RBAC, validation, encrypted storage, enable rules ----
	if r := admin("GET", "/settings", nil, csTok); r.Status != 403 {
		t.Fatalf("CS tidak boleh melihat pengaturan Firebase, dapat %d", r.Status)
	}
	if r := e.upload("/api/v1/admin/push/credential", mkTok, sa); r.Status != 403 {
		t.Fatalf("hanya SUPER_ADMIN yang boleh mengganti credential, dapat %d", r.Status)
	}
	if r := admin("PUT", "/settings", map[string]bool{"enabled": true}, saTok); r.Status != 409 {
		t.Fatalf("mengaktifkan tanpa credential harus ditolak, dapat %d", r.Status)
	}
	if r := e.upload("/api/v1/admin/push/credential", saTok, []byte(`{"type":"authorized_user"}`)); r.Status != 422 {
		t.Fatalf("berkas bukan service account harus ditolak, dapat %d", r.Status)
	}
	google.rejectSA = true
	if r := e.upload("/api/v1/admin/push/credential", saTok, sa); r.Status != 422 {
		t.Fatalf("credential yang ditolak Google tidak boleh disimpan, dapat %d %v", r.Status, r.Body)
	}
	google.rejectSA = false
	up := e.upload("/api/v1/admin/push/credential", saTok, sa)
	if up.Status != 200 || up.data()["credential_configured"] != true || up.data()["enabled"] != false || up.data()["project_id"] != "it-project" {
		t.Fatalf("unggah credential valid: %d %v", up.Status, up.Body)
	}
	if raw, _ := json.Marshal(up.Body); bytes.Contains(raw, []byte("PRIVATE KEY")) || bytes.Contains(raw, []byte("credential_enc")) {
		t.Fatal("respons backoffice tidak boleh memuat credential")
	}
	var stored string
	e.db.Raw("SELECT credential_enc FROM push_settings WHERE id = 'DEFAULT'").Scan(&stored)
	if !strings.HasPrefix(stored, "enc:") || strings.Contains(stored, "PRIVATE KEY") || strings.Contains(stored, "it-project") {
		t.Fatal("credential harus tersimpan terenkripsi, bukan plaintext")
	}
	e.seedCustomer("001000000501", "081200000501", devA, "9900000000501", 100000)
	u2 := e.seedCustomer("001000000502", "081200000502", devB, "9900000000502", 0)
	// A campaign can not be sent while the integration is disabled.
	mk := func(body map[string]string) string {
		r := admin("POST", "/campaigns", body, mkTok)
		if r.Status != 200 {
			t.Fatalf("buat notifikasi: %d %v", r.Status, r.Body)
		}
		id := r.data()["id"].(string)
		if s := admin("POST", "/campaigns/"+id+"/submit", nil, mkTok); s.Status != 200 {
			t.Fatalf("ajukan: %d %v", s.Status, s.Body)
		}
		return id
	}
	c0 := mk(map[string]string{"title": "Info Layanan", "body": "Jam layanan berubah.", "category": "INFO", "target_type": "ALL"})
	if r := admin("POST", "/campaigns/"+c0+"/approve", nil, coTok); r.Status != 409 {
		t.Fatalf("pengiriman saat integrasi nonaktif harus ditolak dengan jelas, dapat %d %v", r.Status, r.Body)
	}
	if r := admin("PUT", "/settings", map[string]bool{"enabled": true}, saTok); r.Status != 200 || r.data()["enabled"] != true {
		t.Fatalf("aktifkan integrasi: %d %v", r.Status, r.Body)
	}
	if r := admin("POST", "/test", nil, saTok); r.Status != 200 || r.data()["last_test_ok"] != true {
		t.Fatalf("uji koneksi: %d %v", r.Status, r.Body)
	}

	// ---- Device tokens: authenticated, several devices per customer ----
	if r := e.call("POST", "/api/v1/notifications/fcm-token", map[string]string{"fcm_token": strings.Repeat("x", 40)}, map[string]string{"X-Device-ID": devA}); r.Status != 401 {
		t.Fatalf("registrasi token tanpa login harus 401, dapat %d", r.Status)
	}
	tokA, _ := e.login("081200000501", devA)
	tokB, _ := e.login("081200000502", devB)
	reg := func(tok, dev, fcm string) {
		if r := e.call("POST", "/api/v1/notifications/fcm-token", map[string]string{"fcm_token": fcm, "platform": "android"}, auth(tok, dev)); r.Status != 200 {
			t.Fatalf("registrasi token: %d %v", r.Status, r.Body)
		}
	}
	good1 := "good-token-device-A-" + strings.Repeat("a", 40)
	reg(tokA, devA, "old-token-device-A-"+strings.Repeat("o", 40))
	reg(tokA, devA, good1) // token refresh on the same device retires the old one
	reg(tokA, devA, good1) // repeated registration does not duplicate
	reg(tokB, devB, "dead-token-device-B-"+strings.Repeat("d", 40))
	// second phone of customer B (inserted directly: a login from a second device needs OTP rebinding)
	if err := e.deps.Push.RegisterDevice(context.Background(), u2.ID, "TEST-DEVICE-CCCC03", "flaky-token-device-C-"+strings.Repeat("f", 40), "android"); err != nil {
		t.Fatal(err)
	}
	if err := e.deps.Push.RegisterDevice(context.Background(), u2.ID, "TEST-DEVICE-DDDD04", "down-token-device-D-"+strings.Repeat("n", 40), "android"); err != nil {
		t.Fatal(err)
	}
	var active, plain int64
	e.db.Raw("SELECT count(*) FROM push_devices WHERE is_active").Scan(&active)
	e.db.Raw("SELECT count(*) FROM push_devices WHERE token_enc NOT LIKE 'enc:%' OR token_enc LIKE '%token-device%'").Scan(&plain)
	if active != 4 || plain != 0 {
		t.Fatalf("perangkat aktif=%d (harap 4), token plaintext=%d (harap 0)", active, plain)
	}

	// ---- Campaign: maker-checker, send, statuses ----
	if r := admin("POST", "/campaigns", map[string]string{"title": "x", "body": "<b>x</b>", "category": "INFO", "target_type": "ALL"}, mkTok); r.Status != 422 {
		t.Fatalf("isi dengan markup harus ditolak, dapat %d", r.Status)
	}
	if r := admin("POST", "/campaigns", map[string]string{"title": "x", "body": "y", "category": "SECURITY", "target_type": "ALL"}, mkTok); r.Status != 422 {
		t.Fatalf("kategori sistem tidak boleh dibuat petugas, dapat %d", r.Status)
	}
	if r := admin("POST", "/campaigns", map[string]string{"title": "x", "body": "y", "category": "INFO", "target_type": "ALL"}, coTok); r.Status != 403 {
		t.Fatalf("COMPLIANCE tidak boleh membuat notifikasi, dapat %d", r.Status)
	}
	if r := admin("POST", "/campaigns/"+c0+"/approve", nil, mkTok); r.Status != 403 {
		t.Fatalf("pembuat tidak boleh menyetujui sendiri, dapat %d", r.Status)
	}
	if r := admin("POST", "/campaigns/"+c0+"/approve", nil, coTok); r.Status != 200 {
		t.Fatalf("persetujuan petugas lain: %d %v", r.Status, r.Body)
	}
	if r := admin("POST", "/campaigns/"+c0+"/approve", nil, saTok); r.Status != 409 {
		t.Fatalf("notifikasi tidak boleh dikirim dua kali, dapat %d", r.Status)
	}
	e.deps.Push.Wait()
	var c push.Campaign
	e.db.Where("id = ?", c0).First(&c)
	if c.Status != push.CampaignPartial || c.TargetDevices != 4 || c.AcceptedCount != 2 || c.FailedCount != 1 || c.InvalidTokenCount != 1 {
		t.Fatalf("hasil pengiriman: %+v", c)
	}
	dl := admin("GET", "/campaigns/"+c0+"/deliveries", nil, coTok)
	rows, _ := dl.Body["data"].([]interface{})
	byStatus := map[string]int{}
	for _, r := range rows {
		m := r.(map[string]interface{})
		byStatus[m["status"].(string)]++
		if _, has := m["token_enc"]; has {
			t.Fatal("detail pengiriman tidak boleh memuat token")
		}
		if m["status"] == "ACCEPTED" && m["opened_at"] != nil {
			t.Fatal("diterima FCM tidak boleh dianggap sudah dibuka di HP")
		}
	}
	if byStatus["ACCEPTED"] != 2 || byStatus["FAILED"] != 1 || byStatus["INVALID_TOKEN"] != 1 {
		t.Fatalf("status per perangkat: %v", byStatus)
	}
	var retried int
	e.db.Raw("SELECT attempts FROM push_deliveries d JOIN push_devices p ON p.id = d.device_id WHERE p.device_id = 'TEST-DEVICE-CCCC03' AND d.campaign_id = ?", c0).Scan(&retried)
	e.db.Raw("SELECT count(*) FROM push_devices WHERE is_active").Scan(&active)
	if retried != 3 || active != 3 {
		t.Fatalf("retry terkontrol=%d (harap 3), perangkat aktif setelah token tidak valid=%d (harap 3)", retried, active)
	}
	var inbox int64
	e.db.Model(&model.Notification{}).Where("user_id = 'ALL' AND title = ?", "Info Layanan").Count(&inbox)
	if inbox != 1 {
		t.Fatal("notifikasi juga harus masuk kotak masuk aplikasi")
	}

	// ---- Targeted campaign, opened report, logout detaches the device ----
	c1 := mk(map[string]string{"title": "Untuk Anda", "body": "Pesan khusus.", "category": "INFO", "target_type": "USER", "target_user_id": tokUser(e, "001000000501")})
	before := len(google.sent)
	admin("POST", "/campaigns/"+c1+"/approve", nil, saTok)
	e.deps.Push.Wait()
	if len(google.sent)-before != 1 {
		t.Fatalf("notifikasi per nasabah harus hanya ke perangkat nasabah itu, terkirim %d", len(google.sent)-before)
	}
	last := google.sent[len(google.sent)-1]
	data := last["data"].(map[string]interface{})
	ref := data["ref"].(string)
	if last["token"] != good1 || data["route"] != "notifications" || last["android"].(map[string]interface{})["notification"].(map[string]interface{})["channel_id"] != push.AndroidChannelID {
		t.Fatalf("payload FCM: %v", last)
	}
	if r := e.call("POST", "/api/v1/notifications/opened", map[string]string{"ref": ref}, auth(tokB, devB)); r.Status != 200 {
		t.Fatal("laporan dibuka dari nasabah lain tidak boleh error")
	}
	var opened int64
	e.db.Model(&push.Delivery{}).Where("id = ? AND opened_at IS NOT NULL", ref).Count(&opened)
	if opened != 0 {
		t.Fatal("nasabah lain tidak boleh menandai notifikasi dibuka")
	}
	e.call("POST", "/api/v1/notifications/opened", map[string]string{"ref": ref}, auth(tokA, devA))
	e.db.Model(&push.Delivery{}).Where("id = ? AND opened_at IS NOT NULL", ref).Count(&opened)
	if opened != 1 {
		t.Fatal("pemilik harus dapat melaporkan notifikasi dibuka")
	}

	// ---- System event push: generic text only (no amounts / account numbers) ----
	uA := tokUser(e, "001000000501")
	notification.CreateAndPush(context.Background(), e.db, uA, "Mutasi Rekening", "Dana masuk Rp 150.000 dari 9900000000502. Saldo Rp 850.000", notification.CategoryTransaction)
	e.deps.Push.Wait()
	sys := google.sent[len(google.sent)-1]["notification"].(map[string]interface{})["body"].(string)
	if strings.Contains(sys, "150.000") || strings.Contains(sys, "9900000000502") || strings.Contains(sys, "850.000") {
		t.Fatalf("push transaksi tidak boleh memuat nominal/rekening/saldo: %q", sys)
	}

	if r := e.call("POST", "/api/v1/auth/logout", nil, auth(tokA, devA)); r.Status != 200 {
		t.Fatalf("logout: %d", r.Status)
	}
	before = len(google.sent)
	notification.CreateAndPush(context.Background(), e.db, uA, "Info", "Setelah logout", notification.CategoryInfo)
	e.deps.Push.Wait()
	if len(google.sent) != before {
		t.Fatal("perangkat yang sudah logout tidak boleh menerima push")
	}

	// ---- Disabling stops sending; every step is audited; no secret in the audit trail ----
	admin("PUT", "/settings", map[string]bool{"enabled": false}, saTok)
	c2 := mk(map[string]string{"title": "Nonaktif", "body": "Tidak terkirim.", "category": "PROMO", "target_type": "ALL"})
	if r := admin("POST", "/campaigns/"+c2+"/approve", nil, coTok); r.Status != 409 {
		t.Fatalf("integrasi nonaktif: kirim harus ditolak, dapat %d", r.Status)
	}
	var audits, leaked int64
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE action LIKE 'FIREBASE_%' OR action LIKE 'NOTIFICATION_%'").Scan(&audits)
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE details LIKE '%PRIVATE KEY%' OR details LIKE '%token-device%'").Scan(&leaked)
	if audits < 12 || leaked != 0 {
		t.Fatalf("audit trail: %d entri (harap ≥12), kebocoran=%d", audits, leaked)
	}
}

func tokUser(e *itEnv, cif string) string {
	var u model.User
	e.db.Where("cif = ?", cif).First(&u)
	return u.ID
}
