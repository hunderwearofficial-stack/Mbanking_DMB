package security

import (
	"strings"
	"testing"
)

func TestGenerateTemporaryPassword(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		pw, err := GenerateTemporaryPassword()
		if err != nil {
			t.Fatal(err)
		}
		if len(pw) != 16 || ValidateNewPassword(pw) != nil {
			t.Fatalf("password sementara tidak memenuhi kebijakan: %q", pw)
		}
		if !strings.ContainsAny(pw, tempLower) || !strings.ContainsAny(pw, tempUpper) || !strings.ContainsAny(pw, tempDigits) {
			t.Fatalf("password sementara harus memuat huruf kecil, huruf besar, dan angka: %q", pw)
		}
		if strings.ContainsAny(pw, "0O1lI") {
			t.Fatalf("password sementara memuat karakter mirip: %q", pw)
		}
		if seen[pw] {
			t.Fatal("password sementara berulang")
		}
		seen[pw] = true
	}
}
