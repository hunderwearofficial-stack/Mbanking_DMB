package integration

import (
	"bytes"
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/otp"
)

func code(r apiResp) string { s, _ := r.Body["response_code"].(string); return s }

// rawGet returns status, headers and body bytes (for PDF downloads).
func (e *itEnv) rawGet(path string, headers map[string]string) (int, map[string]string, []byte) {
	req := httptest.NewRequest("GET", path, nil)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	e.router.ServeHTTP(w, req)
	h := map[string]string{}
	for k := range w.Header() {
		h[k] = w.Header().Get(k)
	}
	return w.Code, h, w.Body.Bytes()
}

func TestIntegration_TermsUnavailableBlocksLogin(t *testing.T) {
	e := setupITNoTerms(t)
	e.seedCustomer("001000000301", "081200000301", devA, "9900000000301", 100000)
	if r := e.call("GET", "/api/v1/terms/active", nil, nil); r.Status != 503 || code(r) != legaldoc.CodeTermsUnavailable {
		t.Fatalf("tanpa SK terbit harus 503/11, dapat %d %v", r.Status, r.Body)
	}
	r := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000301", "password": itPassword, "device_id": devA}, map[string]string{"X-Device-ID": devA})
	if r.Status != 503 || code(r) != legaldoc.CodeTermsUnavailable {
		t.Fatalf("login tanpa SK berlaku harus ditolak (fail-closed), dapat %d %v", r.Status, r.Body)
	}
	var sessions int64
	e.db.Model(&model.UserSession{}).Count(&sessions)
	if sessions != 0 {
		t.Fatal("tidak boleh ada sesi dibuat")
	}
	// A draft can not be accepted nor downloaded publicly.
	var draftID string
	e.db.Raw("SELECT id FROM legal_document_versions WHERE status = 'DRAFT'").Scan(&draftID)
	if r := e.call("POST", "/api/v1/terms/acceptances", map[string]interface{}{"version_id": draftID, "accepted": true}, map[string]string{"X-Device-ID": devA}); r.Status == 201 {
		t.Fatal("draf tidak boleh dapat disetujui")
	}
	if st, _, _ := e.rawGet("/api/v1/terms/versions/"+draftID+"/pdf", nil); st != 404 {
		t.Fatalf("PDF draf tidak boleh tersedia untuk publik, dapat %d", st)
	}
}

func TestIntegration_TermsMakerCheckerAndImmutability(t *testing.T) {
	e := setupITNoTerms(t)
	e.seedAdmin("it-compliance", model.AdminRoleCompliance)
	e.seedAdmin("it-superadmin", model.AdminRoleSuperAdmin)
	e.seedAdmin("it-cs", model.AdminRoleCS)
	co := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-compliance")}
	sa := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-superadmin")}
	cs := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-cs")}

	list := e.call("GET", "/api/v1/admin/terms/versions", nil, co)
	items, _ := list.Body["data"].([]interface{})
	if list.Status != 200 || len(items) != 1 {
		t.Fatalf("daftar versi: %d %v", list.Status, list.Body)
	}
	id := items[0].(map[string]interface{})["id"].(string)

	// Content of the migrated draft = the text that was hard-coded in the app.
	detail := e.call("GET", "/api/v1/admin/terms/versions/"+id, nil, cs)
	content, _ := detail.data()["content"].(map[string]interface{})
	if detail.Status != 200 || content["title"] != "Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor" {
		t.Fatalf("isi SK migrasi: %d %v", detail.Status, detail.Body)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/pdf", nil, cs); r.Status != 403 {
		t.Fatalf("CS tidak boleh membuat PDF/mengubah SK, dapat %d", r.Status)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/submit", map[string]string{}, co); r.Status != 409 {
		t.Fatalf("pengajuan tanpa PDF draf harus ditolak, dapat %d %v", r.Status, r.Body)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/pdf", nil, co); r.Status != 200 {
		t.Fatalf("generate PDF draf: %d %v", r.Status, r.Body)
	}
	st, hdr, body := e.rawGet("/api/v1/admin/terms/versions/"+id+"/pdf?type=draft", co)
	if st != 200 || hdr["Content-Type"] != "application/pdf" || !bytes.HasPrefix(body, []byte("%PDF-")) || hdr["Cache-Control"] != "no-store" {
		t.Fatalf("unduh PDF draf: %d %v", st, hdr)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/submit", map[string]string{}, co); r.Status != 200 {
		t.Fatalf("submit: %d %v", r.Status, r.Body)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/approve", nil, co); r.Status != 403 {
		t.Fatalf("pengaju tidak boleh menyetujui sendiri (maker-checker), dapat %d %v", r.Status, r.Body)
	}
	if r := e.call("PUT", "/api/v1/admin/terms/versions/"+id, map[string]interface{}{"content": content}, co); r.Status != 409 {
		t.Fatalf("versi yang diajukan tidak boleh diubah, dapat %d", r.Status)
	}
	ap := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/approve", nil, sa)
	if ap.Status != 200 || ap.data()["status"] != legaldoc.StatusPublished {
		t.Fatalf("approve oleh petugas kedua: %d %v", ap.Status, ap.Body)
	}

	// Public metadata + final PDF with integrity headers and version caching.
	act := e.call("GET", "/api/v1/terms/active", nil, nil)
	if act.Status != 200 || act.data()["version_id"] != id || act.data()["version_number"].(float64) != 1 {
		t.Fatalf("SK aktif: %d %v", act.Status, act.Body)
	}
	if st := act.data()["consent_statements"].([]interface{}); len(st) != 3 {
		t.Fatalf("3 pernyataan persetujuan lama harus tetap ada, dapat %d", len(st))
	}
	sha := act.data()["pdf_sha256"].(string)
	st, hdr, body = e.rawGet("/api/v1/terms/versions/"+id+"/pdf", nil)
	if st != 200 || !strings.Contains(hdr["Etag"]+hdr["ETag"], sha) || !strings.Contains(hdr["Cache-Control"], "immutable") || !bytes.HasPrefix(body, []byte("%PDF-")) {
		t.Fatalf("PDF publik: %d %v", st, hdr)
	}
	if st, _, _ := e.rawGet("/api/v1/terms/versions/"+id+"/pdf", map[string]string{"If-None-Match": `"` + sha + `"`}); st != 304 {
		t.Fatalf("cache berdasarkan versi/hash harus 304, dapat %d", st)
	}
	var published struct{ PdfSha256, DraftPdfSha256 string }
	e.db.Raw("SELECT pdf_sha256, draft_pdf_sha256 FROM legal_document_versions WHERE id = ?", id).Scan(&published)
	if published.PdfSha256 == "" || published.PdfSha256 == published.DraftPdfSha256 {
		t.Fatal("PDF final (dengan tanggal terbit) harus disimpan terpisah dari PDF draf")
	}

	// Immutability: database refuses silent edits of a published version / stored files.
	for _, stmt := range []string{
		"UPDATE legal_document_versions SET content = '{}'::jsonb WHERE id = '" + id + "'",
		"UPDATE legal_document_versions SET effective_from = now() + interval '1 day' WHERE id = '" + id + "'",
		"DELETE FROM legal_document_versions WHERE id = '" + id + "'",
		"UPDATE stored_files SET content = 'x'",
		"DELETE FROM stored_files",
	} {
		if err := e.db.Exec(stmt).Error; err == nil {
			t.Errorf("harus ditolak database: %s", stmt)
		}
	}
	if r := e.call("PUT", "/api/v1/admin/terms/versions/"+id, map[string]interface{}{"content": content}, co); r.Status != 409 {
		t.Fatalf("versi terbit tidak boleh diubah lewat API, dapat %d", r.Status)
	}
	if r := e.call("POST", "/api/v1/admin/terms/versions/"+id+"/archive", nil, sa); r.Status != 409 {
		t.Fatalf("versi yang sedang berlaku tidak boleh diarsipkan, dapat %d %v", r.Status, r.Body)
	}

	// Audit trail records every step.
	var steps int64
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE action IN ('TERMS_DRAFT_PDF_GENERATED','TERMS_SUBMITTED','TERMS_PUBLISHED')").Scan(&steps)
	if steps != 3 {
		t.Fatalf("audit trail SK harus 3 langkah, dapat %d", steps)
	}
}

func TestIntegration_TermsConsentLoginAndReconsent(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	u := e.seedCustomer("001000000311", "081200000311", devA, "9900000000311", 100000)
	loginBody := func(acc string) map[string]string {
		return map[string]string{"phone_number": "081200000311", "password": itPassword, "device_id": devA, "terms_acceptance_id": acc}
	}
	hdr := map[string]string{"X-Device-ID": devA}

	// 1. Not accepted yet → login refused with a precise code, no session.
	r := e.call("POST", "/api/v1/auth/login", loginBody(""), hdr)
	if r.Status != 403 || code(r) != legaldoc.CodeConsentRequired {
		t.Fatalf("login tanpa persetujuan harus 403/10, dapat %d %v", r.Status, r.Body)
	}
	// 2. Explicit acceptance is required; duplicates return the same record.
	v1 := e.activeTermsID()
	if r := e.call("POST", "/api/v1/terms/acceptances", map[string]interface{}{"version_id": v1, "accepted": false}, hdr); r.Status != 400 {
		t.Fatalf("checkbox tidak dipercaya: accepted=false harus ditolak, dapat %d", r.Status)
	}
	if r := e.call("POST", "/api/v1/terms/acceptances", map[string]interface{}{"version_id": v1, "accepted": true}, nil); r.Status == 201 {
		t.Fatal("persetujuan tanpa identitas perangkat harus ditolak")
	}
	acc1 := e.acceptTerms(devA)
	if again := e.acceptTerms(devA); again != acc1 {
		t.Fatal("permintaan ganda harus menghasilkan catatan yang sama")
	}
	// 3. Consent of another device can not be used.
	other := e.acceptTerms("OTHER-DEVICE-777")
	if r := e.call("POST", "/api/v1/auth/login", loginBody(other), hdr); r.Status != 403 {
		t.Fatalf("persetujuan perangkat lain harus ditolak, dapat %d", r.Status)
	}
	// 4. Login with the device consent → linked to the customer.
	r = e.call("POST", "/api/v1/auth/login", loginBody(acc1), hdr)
	if r.Status != 200 {
		t.Fatalf("login dengan persetujuan: %d %v", r.Status, r.Body)
	}
	refresh := r.data()["refresh_token"].(string)
	token := r.data()["access_token"].(string)
	var n int64
	e.db.Model(&legaldoc.Acceptance{}).Where("user_id = ? AND version_id = ? AND channel = ? AND pre_login_acceptance_id = ?", u.ID, v1, legaldoc.ChannelLogin, acc1).Count(&n)
	if n != 1 {
		t.Fatalf("persetujuan harus tercatat untuk nasabah, dapat %d", n)
	}
	st := e.call("GET", "/api/v1/terms/status", nil, auth(token, devA))
	if st.Status != 200 || st.data()["accepted"] != true {
		t.Fatalf("status persetujuan: %d %v", st.Status, st.Body)
	}
	// 5. Already accepted → later logins do not need a new consent; the same device
	//    consent can not be linked to a second customer.
	if r := e.call("POST", "/api/v1/auth/login", loginBody(""), hdr); r.Status != 200 {
		t.Fatalf("nasabah yang sudah setuju harus bisa login: %d %v", r.Status, r.Body)
	} else {
		// a new login revokes the previous session (exclusive session): keep the new token
		refresh = r.data()["refresh_token"].(string)
	}
	e.seedCustomer("001000000312", "081200000312", devA, "9900000000312", 0)
	r2 := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000312", "password": itPassword, "device_id": devA, "terms_acceptance_id": acc1}, hdr)
	if r2.Status != 403 {
		t.Fatalf("satu persetujuan perangkat hanya untuk satu nasabah, dapat %d %v", r2.Status, r2.Body)
	}
	if fresh := e.acceptTerms(devA); fresh == acc1 {
		t.Fatal("persetujuan yang sudah terikat ke nasabah lain tidak boleh dipakai ulang untuk nasabah berikutnya")
	}

	// 6. New version with a FUTURE effective date: v1 remains in force, no re-consent yet.
	svc := e.termsService()
	v1view, _ := svc.GetVersion(ctx, v1)
	d2, err := svc.CreateDraft(ctx, itMaker, legaldoc.DraftInput{BaseVersionID: v1, ChangeSummary: "uji versi 2"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.CreateDraft(ctx, itMaker, legaldoc.DraftInput{BaseVersionID: v1}); err == nil {
		t.Fatal("hanya boleh satu draf terbuka")
	}
	c2 := *v1view.Content
	c2.Intro = c2.Intro + " (versi uji 2)"
	if _, err := svc.UpdateDraft(ctx, itMaker, d2.ID, legaldoc.DraftInput{Content: &c2, ChangeSummary: "uji versi 2"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.GenerateDraftPDF(ctx, itMaker, d2.ID); err != nil {
		t.Fatal(err)
	}
	future := time.Now().Add(48 * time.Hour)
	if _, err := svc.Submit(ctx, itMaker, d2.ID, &future); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Approve(ctx, itChecker, d2.ID); err != nil {
		t.Fatal(err)
	}
	if e.activeTermsID() != v1 {
		t.Fatal("versi dengan tanggal berlaku di masa depan belum boleh aktif")
	}
	if r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh, "device_id": devA}, hdr); r.Status != 200 {
		t.Fatalf("sebelum tanggal berlaku tidak boleh meminta persetujuan ulang: %d %v", r.Status, r.Body)
	} else {
		refresh = r.data()["refresh_token"].(string)
	}
	// The scheduled version is cancelled (archived) and a version effective NOW published.
	if _, err := svc.Archive(ctx, itChecker, d2.ID); err != nil {
		t.Fatalf("versi terjadwal boleh diarsipkan: %v", err)
	}
	d3, err := svc.CreateDraft(ctx, itMaker, legaldoc.DraftInput{Content: &c2, ChangeSummary: "uji versi 3"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.GenerateDraftPDF(ctx, itMaker, d3.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Submit(ctx, itMaker, d3.ID, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Approve(ctx, itMaker, d3.ID); err == nil {
		t.Fatal("pengaju tidak boleh menyetujui")
	}
	if _, err := svc.Approve(ctx, itChecker, d3.ID); err != nil {
		t.Fatal(err)
	}
	v3 := e.activeTermsID()
	if v3 != d3.ID {
		t.Fatal("versi 3 harus berlaku")
	}
	// 7. Re-consent: refresh (incl. biometric unlock) and login are blocked until v3 is accepted.
	e.freshRateLimits()
	if r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh, "device_id": devA}, hdr); r.Status != 403 || code(r) != legaldoc.CodeConsentRequired {
		t.Fatalf("refresh setelah versi baru berlaku harus 403/10, dapat %d %v", r.Status, r.Body)
	}
	if r := e.call("POST", "/api/v1/auth/login", loginBody(acc1), hdr); r.Status != 403 {
		t.Fatalf("persetujuan versi lama tidak berlaku untuk versi baru, dapat %d", r.Status)
	}
	if r := e.call("POST", "/api/v1/terms/acceptances", map[string]interface{}{"version_id": v1, "accepted": true}, hdr); r.Status != 409 || code(r) != legaldoc.CodeVersionNotActive {
		t.Fatalf("menyetujui versi lama harus 409/12, dapat %d %v", r.Status, r.Body)
	}
	acc3 := e.acceptTerms(devA)
	if r := e.call("POST", "/api/v1/auth/login", loginBody(acc3), hdr); r.Status != 200 {
		t.Fatalf("login setelah menyetujui versi baru: %d %v", r.Status, r.Body)
	}
	var history []legaldoc.Acceptance
	e.db.Where("user_id = ?", u.ID).Order("accepted_at").Find(&history)
	if len(history) != 2 || history[0].VersionNumber != 1 || history[1].VersionNumber != 3 {
		t.Fatalf("riwayat persetujuan v1 dan v3 harus tersimpan terpisah: %+v", history)
	}
	// 8. Old version archived, still available for evidence; consent rows are append-only.
	if _, err := svc.Archive(ctx, itChecker, v1); err != nil {
		t.Fatalf("arsip versi lama: %v", err)
	}
	if st, _, _ := e.rawGet("/api/v1/terms/versions/"+v1+"/pdf", nil); st != 200 {
		t.Fatalf("PDF versi arsip harus tetap tersedia sebagai bukti, dapat %d", st)
	}
	for _, stmt := range []string{"UPDATE legal_acceptances SET status = 'ACCEPTED'", "DELETE FROM legal_acceptances", "TRUNCATE legal_acceptances CASCADE"} {
		if err := e.db.Exec(stmt).Error; err == nil {
			t.Errorf("riwayat persetujuan harus append-only: %s", stmt)
		}
	}
	var audited int64
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE action = 'TERMS_ACCEPTED' AND actor_id = ?", u.ID).Scan(&audited)
	if audited != 2 {
		t.Fatalf("persetujuan harus tercatat di audit trail, dapat %d", audited)
	}
}

func TestIntegration_TermsConsentAtActivation(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	// A customer known to the core but not yet activated in the app.
	u := e.seedCustomer("001000000321", "081200000321", "", "9900000000321", 0)
	e.db.Model(&model.User{}).Where("id = ?", u.ID).Updates(map[string]interface{}{"password_hash": "", "pin_hash": "", "device_id": ""})
	newSession := func() string {
		sid, err := e.deps.OTPStore.Create(ctx, otp.Session{Purpose: otp.PurposeActivation, UserID: u.ID, PhoneNumber: "081200000321", DeviceID: devB, AccountNo: "9900000000321", FullName: u.FullName}, "730164")
		if err != nil {
			t.Fatal(err)
		}
		if r := e.call("POST", "/api/v1/auth/activate/otp", map[string]string{"session_id": sid, "otp_code": "730164"}, map[string]string{"X-Device-ID": devB}); r.Status != 200 {
			t.Fatalf("otp: %d %v", r.Status, r.Body)
		}
		return sid
	}
	sid := newSession()
	setup := map[string]string{"session_id": sid, "password": "Baru-Aman-2026", "pin": "604913"}
	r := e.call("POST", "/api/v1/auth/activate/setup", setup, map[string]string{"X-Device-ID": devB})
	if r.Status != 403 || code(r) != legaldoc.CodeConsentRequired {
		t.Fatalf("aktivasi tanpa persetujuan harus 403/10, dapat %d %v", r.Status, r.Body)
	}
	var stillInactive model.User
	e.db.Where("id = ?", u.ID).First(&stillInactive)
	if stillInactive.PasswordHash != "" {
		t.Fatal("kredensial tidak boleh tersimpan bila persetujuan belum ada")
	}
	// The OTP session was not consumed: the customer accepts and completes activation.
	setup["terms_acceptance_id"] = e.acceptTerms(devB)
	if r := e.call("POST", "/api/v1/auth/activate/setup", setup, map[string]string{"X-Device-ID": devB}); r.Status != 200 {
		t.Fatalf("aktivasi dengan persetujuan: %d %v", r.Status, r.Body)
	}
	var n int64
	e.db.Model(&legaldoc.Acceptance{}).Where("user_id = ? AND channel = ?", u.ID, legaldoc.ChannelActivation).Count(&n)
	if n != 1 {
		t.Fatalf("persetujuan aktivasi harus tercatat, dapat %d", n)
	}
}
