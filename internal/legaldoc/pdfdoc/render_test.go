package pdfdoc

import (
	"bytes"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/pkg/database"
)

// seedContent extracts the Terms text migrated by 0008 (the text that was hard-coded in
// the mobile app) so the tests run against the real document.
func seedContent(t *testing.T) *legaldoc.Content {
	t.Helper()
	migs, err := database.LoadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range migs {
		if m.Name != "legal_documents_and_content_revisions" {
			continue
		}
		parts := strings.Split(m.SQL, "$sk$")
		if len(parts) != 3 {
			t.Fatalf("seed SK tidak ditemukan di migrasi (%d bagian)", len(parts))
		}
		c, err := legaldoc.ParseContent([]byte(parts[1]))
		if err != nil {
			t.Fatalf("seed SK tidak valid: %v", err)
		}
		return c
	}
	t.Fatal("migrasi 0008 tidak ditemukan")
	return nil
}

func norm(s string) string { return strings.Join(strings.Fields(s), " ") }

// assertAllTextRendered checks that every content segment appears, in order, in the
// laid-out text — no clause lost, truncated or reordered.
func assertAllTextRendered(t *testing.T, c *legaldoc.Content, res *Result) {
	t.Helper()
	joined := norm(strings.Join(res.Text, " "))
	pos := 0
	for i, seg := range c.PlainTextSegments() {
		s := norm(seg)
		idx := strings.Index(joined[pos:], s)
		if idx < 0 {
			t.Fatalf("segmen %d tidak ditemukan / urutan salah: %q", i, s)
		}
		pos += idx + len(s)
	}
}

var mediaBoxA4 = regexp.MustCompile(`/MediaBox\s*\[\s*0(\.0+)?\s+0(\.0+)?\s+595(\.0+)?\s+842(\.0+)?\s*\]`)

func TestSeedTermsRenderDraftAndPublished(t *testing.T) {
	c := seedContent(t)
	now := time.Date(2026, 11, 14, 3, 0, 0, 0, time.UTC)

	draft, err := Render(c, Meta{VersionNumber: 1, Draft: true, GeneratedAt: now})
	if err != nil {
		t.Fatalf("render draf: %v", err)
	}
	if !bytes.HasPrefix(draft.PDF, []byte("%PDF-")) || !bytes.Contains(draft.PDF, []byte("%%EOF")) {
		t.Fatal("hasil bukan PDF lengkap")
	}
	if !mediaBoxA4.Match(draft.PDF) {
		t.Fatal("ukuran halaman bukan A4 portrait")
	}
	assertAllTextRendered(t, c, draft)

	eff := now.Add(24 * time.Hour)
	pub, err := Render(c, Meta{VersionNumber: 1, PublishedAt: &now, EffectiveFrom: &eff, GeneratedAt: now, DocumentNumber: ""})
	if err != nil {
		t.Fatalf("render terbit: %v", err)
	}
	assertAllTextRendered(t, c, pub)
	if pub.Pages < 2 {
		t.Fatalf("SK lama seharusnya lebih dari satu halaman, dapat %d", pub.Pages)
	}
	joined := strings.Join(pub.Text, " ")
	for _, want := range []string{DocumentTitle, "Versi Dokumen", "Tanggal Penerbitan", "14 November 2026", "Tanggal Mulai Berlaku", "15 November 2026"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("metadata %q tidak tercetak", want)
		}
	}
	if strings.Contains(joined, "Nomor Dokumen") {
		t.Fatal("nomor dokumen tidak boleh dicetak bila tidak ada nomor resmi")
	}
}

func TestSinglePageAndMultipage(t *testing.T) {
	small := &legaldoc.Content{
		Title:             "Dokumen Uji",
		Sections:          []legaldoc.Section{{Heading: "I. Bagian", Blocks: []legaldoc.Block{{Text: "1. Butir satu."}}}},
		ConsentHeading:    "Persetujuan",
		ConsentStatements: []string{"Saya setuju."},
	}
	res, err := Render(small, Meta{VersionNumber: 2, GeneratedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	if res.Pages != 1 {
		t.Fatalf("dokumen pendek harus 1 halaman, dapat %d", res.Pages)
	}
	assertAllTextRendered(t, small, res)

	big := *small
	big.Sections = nil
	for s := 1; s <= 12; s++ {
		sec := legaldoc.Section{Heading: fmt.Sprintf("Pasal %d", s)}
		for b := 1; b <= 6; b++ {
			sec.Blocks = append(sec.Blocks, legaldoc.Block{
				Text:  fmt.Sprintf("(%d) Ketentuan nomor %d pada pasal %d berlaku bagi seluruh Nasabah pengguna layanan, termasuk perubahan yang diumumkan Bank sesuai ketentuan peraturan perundang-undangan yang berlaku.", b, b, s),
				Items: []string{"a. butir pertama", "b. butir kedua"},
			})
		}
		big.Sections = append(big.Sections, sec)
	}
	res, err = Render(&big, Meta{VersionNumber: 3, GeneratedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	if res.Pages < 3 {
		t.Fatalf("dokumen panjang harus multipage, dapat %d halaman", res.Pages)
	}
	assertAllTextRendered(t, &big, res)
}

func TestIndonesianAndPunctuationCharacters(t *testing.T) {
	c := &legaldoc.Content{
		Title:             "Ketentuan “Khusus” — Nasabah",
		Intro:             "Biaya Rp 1.000,00 ± 2%; café, naïve, Ü… ‘kutip’ – €5",
		Sections:          []legaldoc.Section{{Heading: "Pasal 1", Blocks: []legaldoc.Block{{Text: "Kata-sangat-panjang-tanpa-spasi-" + strings.Repeat("x", 300)}}}},
		ConsentHeading:    "Persetujuan",
		ConsentStatements: []string{"Saya setuju."},
	}
	res, err := Render(c, Meta{VersionNumber: 1, GeneratedAt: time.Now()})
	if err != nil {
		t.Fatalf("karakter Indonesia/tanda baca harus didukung: %v", err)
	}
	if !strings.Contains(strings.Join(res.Text, ""), "café") {
		t.Fatal("karakter beraksen hilang")
	}

	emoji := *c
	emoji.Intro = "Promo 🎉"
	if _, err := Render(&emoji, Meta{VersionNumber: 1, GeneratedAt: time.Now()}); !errors.Is(err, legaldoc.ErrInvalidContent) {
		t.Fatalf("karakter yang tidak didukung font harus ditolak, dapat %v", err)
	}
}

func TestRenderRejectsInvalidInput(t *testing.T) {
	if _, err := Render(nil, Meta{VersionNumber: 1}); err == nil {
		t.Fatal("isi kosong harus ditolak")
	}
	c := &legaldoc.Content{Title: "x", Sections: []legaldoc.Section{{Heading: "h", Blocks: []legaldoc.Block{{Text: "t"}}}}, ConsentHeading: "p", ConsentStatements: []string{"s"}}
	if _, err := Render(c, Meta{VersionNumber: 0}); err == nil {
		t.Fatal("nomor versi 0 harus ditolak")
	}
}
