package integration

import (
	"testing"

	"mbanking-bpr/internal/mobilecontent"
	"mbanking-bpr/internal/model"
)

// TestIntegration_MobileContentWorkflow: admin edits → draft → submit → approval by a
// different officer → new version served to the app (GET /api/v1/content), with history,
// rollback, validation, RBAC and audit.
func TestIntegration_MobileContentWorkflow(t *testing.T) {
	e := setupIT(t)
	e.seedAdmin("it-marketing", model.AdminRoleMarketing)
	e.seedAdmin("it-compliance2", model.AdminRoleCompliance)
	e.seedAdmin("it-cs2", model.AdminRoleCS)
	e.seedAdmin("it-sa2", model.AdminRoleSuperAdmin)
	mk := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-marketing")}
	co := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-compliance2")}
	cs := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-cs2")}
	sa := map[string]string{"Authorization": "Bearer " + e.adminLogin("it-sa2")}

	app := func() (int, map[string]interface{}) {
		r := e.call("GET", "/api/v1/content", nil, nil)
		if r.Status != 200 {
			t.Fatalf("GET /content: %d %v", r.Status, r.Body)
		}
		items, _ := r.data()["items"].(map[string]interface{})
		return int(r.data()["version"].(float64)), items
	}
	call := func(method, path string, body interface{}, h map[string]string) apiResp {
		return e.call(method, "/api/v1/admin/content"+path, body, h)
	}

	// Version 0 = what the app showed before (registry defaults / legacy configuration).
	ver, items := app()
	if ver != 0 || items["onboarding.slide1_title"] != "Jadi bestie di dunia finansial anak dengan DMB Mobile" ||
		items["contact.call_center_display"] != "(0251) 832-1234" {
		t.Fatalf("baseline: v%d %v", ver, items)
	}
	if len(items) != len(mobilecontent.Fields) {
		t.Fatalf("semua elemen registri harus dikirim: %d vs %d", len(items), len(mobilecontent.Fields))
	}
	schema := call("GET", "/schema", nil, co)
	if pages, _ := schema.data()["pages"].([]interface{}); schema.Status != 200 || len(pages) != len(mobilecontent.Pages) {
		t.Fatalf("schema: %d %v", schema.Status, schema.Body)
	}

	edit := map[string]interface{}{"values": map[string]string{
		"onboarding.slide1_title": "Judul Onboarding Uji", "home.banner2_visible": "false",
		"contact.call_center_display": "(0251) 000-1111", "contact.call_center_dial": "02510001111",
	}}
	if r := call("PUT", "/draft", edit, cs); r.Status != 403 {
		t.Fatalf("CS tidak boleh mengubah konten, dapat %d", r.Status)
	}
	for name, bad := range map[string]map[string]string{
		"unknown key":   {"login.pin_rules": "x"},
		"script image":  {"app.logo": "javascript:alert(1)"},
		"markup":        {"login.title": "<b>x</b>"},
		"empty req":     {"login.title": "  "},
		"enum":          {"home.banner1_action": "transfer"},
		"bool":          {"home.banner1_visible": "ya"},
		"bad email":     {"contact.email": "bukan-email"},
		"bad phone":     {"contact.whatsapp_dial": "08abc"},
		"path traverse": {"login.background": "/admin/uploads/../../etc/passwd"},
	} {
		if r := call("PUT", "/draft", map[string]interface{}{"values": bad}, mk); r.Status != 422 {
			t.Errorf("%s harus ditolak (422), dapat %d", name, r.Status)
		}
	}
	d := call("PUT", "/draft", edit, mk)
	if d.Status != 200 || d.data()["status"] != "DRAFT" {
		t.Fatalf("simpan draf: %d %v", d.Status, d.Body)
	}
	id := d.data()["id"].(string)
	if v, it := app(); v != 0 || it["onboarding.slide1_title"] == "Judul Onboarding Uji" {
		t.Fatal("draf tidak boleh tampil di aplikasi")
	}
	if r := call("POST", "/revisions/"+id+"/approve", nil, co); r.Status != 409 {
		t.Fatalf("draf belum diajukan tidak boleh dipublikasikan, dapat %d", r.Status)
	}
	if r := call("POST", "/revisions/"+id+"/submit", nil, mk); r.Status != 200 || r.data()["status"] != "PENDING_APPROVAL" {
		t.Fatalf("ajukan: %d %v", r.Status, r.Body)
	}
	if r := call("PUT", "/draft", edit, mk); r.Status != 409 {
		t.Fatalf("revisi yang menunggu persetujuan tidak boleh diubah, dapat %d", r.Status)
	}
	if r := call("POST", "/revisions/"+id+"/approve", nil, mk); r.Status != 403 {
		t.Fatalf("pembuat tidak boleh menyetujui sendiri, dapat %d", r.Status)
	}
	if r := call("POST", "/revisions/"+id+"/approve", nil, co); r.Status != 200 || r.data()["status"] != "PUBLISHED" {
		t.Fatalf("persetujuan petugas lain: %d %v", r.Status, r.Body)
	}
	ver, items = app()
	if ver != 1 || items["onboarding.slide1_title"] != "Judul Onboarding Uji" || items["home.banner2_visible"] != "false" ||
		items["contact.call_center_display"] != "(0251) 000-1111" {
		t.Fatalf("versi baru harus diterima aplikasi: v%d %v", ver, items)
	}
	if r := e.call("GET", "/api/v1/content", nil, map[string]string{"If-None-Match": `"content-v1"`}); r.Status != 304 {
		t.Fatalf("cache berbasis versi harus 304, dapat %d", r.Status)
	}
	if c := e.call("GET", "/api/v1/config", nil, nil).data(); c["call_center"] != "(0251) 000-1111" || c["content_version"].(float64) != 1 {
		t.Fatalf("konfigurasi lama tidak sinkron: %v", c)
	}

	// Version 2 (rejected once), then rollback to version 1 through the same approval flow.
	d2 := call("PUT", "/draft", map[string]interface{}{"values": map[string]string{"onboarding.slide1_title": "Judul Versi Dua"}}, mk)
	id2 := d2.data()["id"].(string)
	call("POST", "/revisions/"+id2+"/submit", nil, mk)
	if r := call("POST", "/revisions/"+id2+"/reject", map[string]string{"reason": "perbaiki redaksi"}, co); r.Status != 200 || r.data()["status"] != "DRAFT" {
		t.Fatalf("kembalikan ke draf: %d %v", r.Status, r.Body)
	}
	call("POST", "/revisions/"+id2+"/submit", nil, mk)
	if r := call("POST", "/revisions/"+id2+"/approve", nil, sa); r.Status != 200 {
		t.Fatalf("approve v2: %d %v", r.Status, r.Body)
	}
	if v, it := app(); v != 2 || it["onboarding.slide1_title"] != "Judul Versi Dua" || it["home.banner2_visible"] != "false" {
		t.Fatalf("versi 2 (nilai lain tetap): v%d %v", v, it)
	}
	rb := call("POST", "/revisions/"+id+"/rollback", nil, mk)
	if rb.Status != 200 {
		t.Fatalf("rollback: %d %v", rb.Status, rb.Body)
	}
	rbID := rb.data()["id"].(string)
	call("POST", "/revisions/"+rbID+"/submit", nil, mk)
	call("POST", "/revisions/"+rbID+"/approve", nil, co)
	if v, it := app(); v != 3 || it["onboarding.slide1_title"] != "Judul Onboarding Uji" {
		t.Fatalf("rollback harus menjadi versi baru (3) berisi nilai versi 1: v%d %v", v, it)
	}
	h := call("GET", "/revisions", nil, co)
	revs, _ := h.Body["data"].([]interface{})
	if len(revs) != 3 {
		t.Fatalf("riwayat 3 revisi, dapat %d", len(revs))
	}
	first := revs[2].(map[string]interface{})
	if first["status"] != "ARCHIVED" || first["created_by_name"] == "" || first["published_by_name"] == nil || first["submitted_by_name"] == nil {
		t.Fatalf("riwayat harus mencatat pembuat, pengaju, penerbit: %v", first)
	}
	if err := e.db.Exec("UPDATE mobile_content_revisions SET content = '{}'::jsonb WHERE id = ?", id).Error; err == nil {
		t.Fatal("revisi terbit tidak boleh diubah")
	}
	var n int64
	e.db.Raw("SELECT count(*) FROM audit_logs WHERE action IN ('MOBILE_CONTENT_DRAFT_SAVED','MOBILE_CONTENT_SUBMITTED','MOBILE_CONTENT_PUBLISHED','MOBILE_CONTENT_REJECTED')").Scan(&n)
	if n < 10 {
		t.Fatalf("setiap langkah harus tercatat di audit trail, dapat %d", n)
	}
}
