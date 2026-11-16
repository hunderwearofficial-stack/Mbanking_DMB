package mobilecontent

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRegistryDefaultsAreValidAndKeysUnique(t *testing.T) {
	seen := map[string]bool{}
	pages := map[string]bool{}
	for _, p := range Pages {
		pages[p.ID] = true
	}
	for _, f := range Fields {
		if seen[f.Key] {
			t.Fatalf("kunci ganda %s", f.Key)
		}
		seen[f.Key] = true
		if !pages[f.Page] {
			t.Fatalf("%s: halaman %s tidak terdaftar", f.Key, f.Page)
		}
		if err := ValidateValue(&f, f.Default); err != nil {
			t.Fatalf("nilai bawaan %s tidak valid: %v", f.Key, err)
		}
	}
	for k := range legacyColumns {
		if !seen[k] {
			t.Fatalf("kolom lama memetakan kunci tak dikenal %s", k)
		}
	}
}

func TestNormalizeRejectsInvalid(t *testing.T) {
	base := Values{}
	for _, f := range Fields {
		base[f.Key] = f.Default
	}
	out, err := Normalize(Values{"login.title": "  Halo  "}, base)
	if err != nil || out["login.title"] != "Halo" || out["splash.tagline"] != base["splash.tagline"] {
		t.Fatalf("normalisasi: %v %v", err, out["login.title"])
	}
	for _, in := range []Values{
		{"x.unknown": "a"}, {"app.logo": "http://insecure.example/a.png"}, {"login.title": strings.Repeat("a", 81)},
		{"home.banner1_action": "app://transfer"}, {"splash.tagline": "<script>"},
	} {
		if _, err := Normalize(in, base); !errors.Is(err, ErrInvalid) {
			t.Fatalf("%v harus ditolak, dapat %v", in, err)
		}
	}
	for _, ok := range []string{"", "/admin/uploads/logo_ab12.png", "https://cdn.example.co.id/a.jpg"} {
		if !ValidImage(ok) {
			t.Fatalf("%q harus valid", ok)
		}
	}
	for _, bad := range []string{"/admin/uploads/../x.png", "file:///etc/passwd", "/etc/passwd", "data:image/png;base64,AAA"} {
		if ValidImage(bad) {
			t.Fatalf("%q harus ditolak", bad)
		}
	}
}

// The Flutter app ships the same keys and built-in values (lib/core/content/app_content.dart):
// a key the app does not know would be editable in the back office without any effect.
func TestFlutterAppKnowsEveryRegistryElement(t *testing.T) {
	src, err := os.ReadFile(filepath.Join("..", "..", "m_banking_bpr", "lib", "core", "content", "app_content.dart"))
	if err != nil {
		t.Skip("sumber Flutter tidak tersedia: ", err)
	}
	dart := strings.Join(strings.Fields(string(src)), " ")
	for _, f := range Fields {
		if !strings.Contains(dart, "'"+f.Key+"': ContentSpec(") {
			t.Errorf("aplikasi tidak mengenal elemen %s", f.Key)
		}
		def := strings.Join(strings.Fields(strings.ReplaceAll(f.Default, "\n", `\n`)), " ")
		if !strings.Contains(dart, "'"+def+"')") {
			t.Errorf("nilai bawaan %s berbeda dengan aplikasi: %q", f.Key, f.Default)
		}
	}
}
