package security

import (
	"encoding/base32"
	"strings"
	"testing"
	"time"
)

// RFC 6238 appendix B test vector (SHA1, secret "12345678901234567890", 8 digits); the
// 6-digit code is the last 6 digits of the published 8-digit value.
func TestTOTPRFC6238Vector(t *testing.T) {
	secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString([]byte("12345678901234567890"))
	cases := map[int64]string{59: "287082", 1111111109: "081804", 1234567890: "005924", 2000000000: "279037"}
	for unix, want := range cases {
		step, ok := VerifyTOTP(secret, want, time.Unix(unix, 0), 0)
		if !ok || step != unix/30 {
			t.Errorf("t=%d: code %s refused (step %d)", unix, want, step)
		}
	}
}

func TestTOTPReplayAndSkew(t *testing.T) {
	secret, err := NewTOTPSecret()
	if err != nil {
		t.Fatal(err)
	}
	key, _ := totpEncoding.DecodeString(secret)
	now := time.Unix(1_700_000_000, 0)
	code := totpCode(key, now.Unix()/30)
	step, ok := VerifyTOTP(secret, code, now, 0)
	if !ok {
		t.Fatal("valid code refused")
	}
	if _, ok := VerifyTOTP(secret, code, now, step); ok {
		t.Fatal("replayed code accepted")
	}
	if _, ok := VerifyTOTP(secret, code, now.Add(90*time.Second), 0); ok {
		t.Fatal("code accepted outside the +-1 step window")
	}
	if _, ok := VerifyTOTP(secret, "12345", now, 0); ok {
		t.Fatal("short code accepted")
	}
	uri := TOTPProvisioningURI("Bank DMB Backoffice", "petugas", secret)
	if !strings.HasPrefix(uri, "otpauth://totp/") || !strings.Contains(uri, "secret="+secret) {
		t.Fatalf("unexpected provisioning URI %s", uri)
	}
}
