package pdfdoc

import (
	"os"
	"regexp"
	"strings"
	"testing"
	"time"
)

func TestCompareWithLegacyScreen(t *testing.T) {
	dartPath, contactPath := os.Getenv("LEGACY_SK_DART"), os.Getenv("LEGACY_BANK_CONTACT_DART")
	if dartPath == "" || contactPath == "" {
		t.Skip("LEGACY_SK_DART / LEGACY_BANK_CONTACT_DART tidak diisi")
	}
	dart, err := os.ReadFile(dartPath)
	if err != nil {
		t.Fatal(err)
	}
	contact, err := os.ReadFile(contactPath)
	if err != nil {
		t.Fatal(err)
	}
	constVal := func(name string) string {
		m := regexp.MustCompile(`static const String ` + name + ` = '([^']*)'`).FindSubmatch(contact)
		if m == nil {
			t.Fatalf("konstanta %s tidak ditemukan", name)
		}
		return string(m[1])
	}
	subst := strings.NewReplacer("${BankContact.callCenterDisplay}", constVal("callCenterDisplay"),
		"${BankContact.whatsAppDisplay}", constVal("whatsAppDisplay"))

	body := dart
	if i := strings.Index(string(dart), "Widget build(BuildContext context)"); i > 0 {
		body = dart[i:]
	}
	lits := regexp.MustCompile(`'((?:[^'\\]|\\.)*)'`).FindAllSubmatch(body, -1)
	c := seedContent(t)
	segments := c.PlainTextSegments()
	inSeed := map[string]bool{}
	for _, s := range segments {
		inSeed[norm(s)] = true
	}
	res, err := Render(c, Meta{VersionNumber: 1, Draft: true, GeneratedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	pdfText := norm(strings.Join(res.Text, " "))

	var migrated, notMigrated []string
	lastPos := -1
	for _, m := range lits {
		s := norm(subst.Replace(string(m[1])))
		if s == "" || strings.HasPrefix(s, "package:") || strings.HasSuffix(s, ".dart") {
			continue
		}
		if !inSeed[s] {
			notMigrated = append(notMigrated, s)
			continue
		}
		migrated = append(migrated, s)
		idx := indexOf(segments, s)
		if idx < lastPos {
			t.Errorf("urutan berubah: %q", s)
		}
		lastPos = idx
		if !strings.Contains(pdfText, s) {
			t.Errorf("teks tidak ada / terpotong di PDF: %q", s)
		}
	}
	fromScreen := map[string]bool{}
	for _, s := range migrated {
		fromScreen[s] = true
	}
	for _, s := range segments {
		if !fromScreen[norm(s)] {
			t.Errorf("teks baru yang tidak ada di layar lama: %q", s)
		}
	}
	t.Logf("LITERAL ISI SK DI LAYAR LAMA: %d; SEGMEN UNIK DIMIGRASIKAN: %d dari %d; HALAMAN PDF: %d", len(migrated), len(fromScreen), len(segments), res.Pages)
	for _, s := range notMigrated {
		t.Logf("BUKAN ISI SK (elemen tampilan layar lama): %q", s)
	}
}

func indexOf(xs []string, s string) int {
	for i, x := range xs {
		if norm(x) == s {
			return i
		}
	}
	return -1
}
