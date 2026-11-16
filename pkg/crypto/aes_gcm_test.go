package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"strings"
	"testing"
)

// Test-only random keys (NOT production keys).
const (
	testActiveKeyHex   = "0f1e2d3c4b5a69788796a5b4c3d2e1f00112233445566778899aabbccddeeff0"
	testPreviousKeyHex = "a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0"
)

func setupKeys(t *testing.T, previous string) {
	t.Helper()
	resetKeysForTest()
	if err := InitKeys(testActiveKeyHex, previous); err != nil {
		t.Fatalf("InitKeys failed: %v", err)
	}
	t.Cleanup(resetKeysForTest)
}

func TestEncryptDecrypt_RoundTrip(t *testing.T) {
	setupKeys(t, "")
	cases := []string{
		"3173031208940001",
		"Jl. Pajajaran No. 88, Bogor Tengah",
		"A",
		"Very long text with symbols !@#$%^&*()_+{}[]:;\"'<>?,./~` and unicode: 🏦",
	}
	for _, original := range cases {
		enc, err := EncryptString(original)
		if err != nil {
			t.Fatalf("encrypt: %v", err)
		}
		if !strings.HasPrefix(enc, CipherPrefix) {
			t.Fatalf("missing v2 prefix: %s", enc)
		}
		dec, err := DecryptString(enc)
		if err != nil || dec != original {
			t.Fatalf("roundtrip mismatch: %q vs %q (%v)", dec, original, err)
		}
	}
}

func TestNonceIsRandom(t *testing.T) {
	setupKeys(t, "")
	a, _ := EncryptString("same")
	b, _ := EncryptString("same")
	if a == b {
		t.Fatal("ciphertexts must differ (random nonce)")
	}
}

func TestNoDefaultKey_FailsClosed(t *testing.T) {
	resetKeysForTest()
	if _, err := EncryptString("x"); err == nil {
		t.Fatal("encryption must fail when no key is configured")
	}
	if _, err := DecryptString(CipherPrefix + base64.StdEncoding.EncodeToString(make([]byte, 40))); err == nil {
		t.Fatal("decryption must fail when no key is configured")
	}
}

func TestInitKeys_RejectsWeakKeys(t *testing.T) {
	resetKeysForTest()
	for _, k := range []string{"", "short", "a-32-character-passphrase-string"} {
		if err := InitKeys(k, ""); err == nil {
			t.Fatalf("expected rejection for key %q", k)
		}
	}
}

func TestTamperedCiphertextRejected(t *testing.T) {
	setupKeys(t, "")
	enc, _ := EncryptString("sensitive")
	raw, _ := base64.StdEncoding.DecodeString(strings.TrimPrefix(enc, CipherPrefix))
	raw[len(raw)-1] ^= 0xFF
	tampered := CipherPrefix + base64.StdEncoding.EncodeToString(raw)
	if _, err := DecryptString(tampered); err == nil {
		t.Fatal("tampered ciphertext must be rejected")
	}
	var s EncryptedString
	if err := s.Scan(tampered); err == nil {
		t.Fatal("Scan must fail closed on tampered ciphertext")
	}
}

// legacyEncrypt reproduces the old enc:v1 format with a given raw key.
func legacyEncrypt(t *testing.T, key []byte, plaintext string) string {
	t.Helper()
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	nonce := make([]byte, GCMNonceLength)
	sealed := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return LegacyCipherPrefix + base64.StdEncoding.EncodeToString(sealed)
}

func TestLegacyV1_DecryptWithPreviousKey_AndReencryptToV2(t *testing.T) {
	setupKeys(t, testPreviousKeyHex)
	prev, _ := ParseKey(testPreviousKeyHex)
	v1 := legacyEncrypt(t, prev, "Siti")

	pt, err := DecryptString(v1)
	if err != nil || pt != "Siti" {
		t.Fatalf("legacy decrypt failed: %v", err)
	}
	if !NeedsReencryption(v1) {
		t.Fatal("v1 must be flagged for re-encryption")
	}

	var s EncryptedString
	if err := s.Scan(v1); err != nil || string(s) != "Siti" {
		t.Fatalf("scan legacy failed: %v", err)
	}
	val, err := EncryptedString(v1).Value()
	if err != nil || !strings.HasPrefix(val.(string), CipherPrefix) {
		t.Fatalf("Value() must re-encrypt legacy data to v2, got %v (%v)", val, err)
	}
}

func TestPlaintextLegacyFlagged(t *testing.T) {
	setupKeys(t, "")
	if !NeedsReencryption("3173031208940001") {
		t.Fatal("plaintext must be flagged")
	}
	if NeedsReencryption("") {
		t.Fatal("empty must not be flagged")
	}
}
