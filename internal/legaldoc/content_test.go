package legaldoc

import (
	"errors"
	"strings"
	"testing"
)

func validJSON() string {
	return `{"title":"Judul","sections":[{"heading":"I. Bagian","blocks":[{"text":"1. Butir","items":["a. satu"]}]}],
	"consent_heading":"Persetujuan","consent_statements":["Saya setuju."]}`
}

func TestParseContentValid(t *testing.T) {
	c, err := ParseContent([]byte(validJSON()))
	if err != nil {
		t.Fatal(err)
	}
	sha1, _ := c.SHA256()
	c2, _ := ParseContent([]byte(validJSON()))
	sha2, _ := c2.SHA256()
	if sha1 != sha2 || len(sha1) != 64 {
		t.Fatal("hash isi harus deterministik")
	}
	segs := c.PlainTextSegments()
	if len(segs) != 6 || segs[0] != "Judul" || segs[len(segs)-1] != "Saya setuju." {
		t.Fatalf("segmen teks: %v", segs)
	}
}

func TestParseContentRejects(t *testing.T) {
	cases := map[string]string{
		"unknown field":  strings.Replace(validJSON(), `"title"`, `"script":"x","title"`, 1),
		"empty title":    strings.Replace(validJSON(), `"Judul"`, `""`, 1),
		"no sections":    `{"title":"x","sections":[],"consent_heading":"p","consent_statements":["s"]}`,
		"no statements":  `{"title":"x","sections":[{"heading":"h","blocks":[{"text":"t"}]}],"consent_heading":"p","consent_statements":[]}`,
		"control char":   strings.Replace(validJSON(), `"Judul"`, `"Ju\u0007dul"`, 1),
		"emoji":          strings.Replace(validJSON(), `"Judul"`, `"Judul 🎉"`, 1),
		"empty section":  `{"title":"x","sections":[{"heading":"h"}],"consent_heading":"p","consent_statements":["s"]}`,
		"not json":       `<html>`,
		"too long":       `{"title":"` + strings.Repeat("a", 301) + `","sections":[{"heading":"h","blocks":[{"text":"t"}]}],"consent_heading":"p","consent_statements":["s"]}`,
		"six statements": `{"title":"x","sections":[{"heading":"h","blocks":[{"text":"t"}]}],"consent_heading":"p","consent_statements":["1","2","3","4","5","6"]}`,
	}
	for name, raw := range cases {
		if _, err := ParseContent([]byte(raw)); !errors.Is(err, ErrInvalidContent) {
			t.Errorf("%s: harus ditolak, dapat %v", name, err)
		}
	}
}

func TestSupportedRune(t *testing.T) {
	for _, r := range "AZaz09 .,;:!?()-/&%@é–—“”‘’…•€\n" {
		if !SupportedRune(r) {
			t.Errorf("U+%04X harus didukung", r)
		}
	}
	for _, r := range []rune{0x07, 0x1F600, 0x4E2D, 0x200B} {
		if SupportedRune(r) {
			t.Errorf("U+%04X tidak boleh didukung", r)
		}
	}
}

func TestValidUUID(t *testing.T) {
	if !validUUID("8f14e45f-ceea-467a-9575-8d1e6b0f3c2a") || validUUID("../../etc/passwd") || validUUID("") {
		t.Fatal("validasi id dokumen salah")
	}
}
