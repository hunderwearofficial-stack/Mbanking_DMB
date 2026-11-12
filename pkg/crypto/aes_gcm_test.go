package crypto

import (
	"strings"
	"testing"
)

func TestAES256GCM_EncryptDecrypt(t *testing.T) {
	// Initialize custom key
	testKey := "super-secret-bank-encryption-key"
	if err := InitEncryptionKey(testKey); err != nil {
		t.Fatalf("InitEncryptionKey failed: %v", err)
	}

	testCases := []string{
		"3173031208940001",                   // NIK
		"001000309659",                       // CIF
		"081234567890",                       // Phone
		"Jl. Pajajaran No. 88, Bogor Tengah", // Address
		"Siti Aminah",                        // Nama Ibu Kandung
		"A",                                  // Single char
		"Very long text with symbols !@#$%^&*()_+{}[]:;\"'<>?,./~` and unicode: 🏦 Bank DMB",
	}

	for _, original := range testCases {
		encrypted, err := EncryptString(original)
		if err != nil {
			t.Fatalf("Encryption failed for '%s': %v", original, err)
		}

		if !strings.HasPrefix(encrypted, CipherPrefix) {
			t.Errorf("Encrypted text missing prefix '%s': %s", CipherPrefix, encrypted)
		}

		// Ensure ciphertext differs from original
		if encrypted == original {
			t.Errorf("Encrypted text equals plaintext!")
		}

		decrypted, err := DecryptString(encrypted)
		if err != nil {
			t.Fatalf("Decryption failed for '%s': %v", original, err)
		}

		if decrypted != original {
			t.Errorf("Mismatch! Got '%s', expected '%s'", decrypted, original)
		}
	}
}

func TestAES256GCM_TamperResistance(t *testing.T) {
	plaintext := "3173031208940001"
	encrypted, err := EncryptString(plaintext)
	if err != nil {
		t.Fatalf("Encrypt failed: %v", err)
	}

	// Tamper with ciphertext by altering last characters
	tampered := encrypted[:len(encrypted)-3] + "XYZ"

	_, err = DecryptString(tampered)
	if err == nil {
		t.Errorf("Expected decryption error on tampered ciphertext, but succeeded!")
	}
}

func TestAES256GCM_BackwardCompatibility(t *testing.T) {
	// If text does not have "enc:v1:" prefix, DecryptString should return it directly
	legacyPlaintext := "3173031208940001"
	result, err := DecryptString(legacyPlaintext)
	if err != nil {
		t.Fatalf("Backward compatibility failed: %v", err)
	}
	if result != legacyPlaintext {
		t.Errorf("Expected '%s', got '%s'", legacyPlaintext, result)
	}
}

func TestEncryptedString_GORMDriver(t *testing.T) {
	nik := EncryptedString("3201015509990002")

	// 1. Test Value() (database write)
	dbVal, err := nik.Value()
	if err != nil {
		t.Fatalf("Value() failed: %v", err)
	}

	strVal, ok := dbVal.(string)
	if !ok {
		t.Fatalf("Value() did not return string")
	}

	if !strings.HasPrefix(strVal, CipherPrefix) {
		t.Errorf("Value() result not encrypted: %s", strVal)
	}

	// 2. Test Scan() (database read)
	var scanned EncryptedString
	if err := scanned.Scan(strVal); err != nil {
		t.Fatalf("Scan() failed: %v", err)
	}

	if string(scanned) != "3201015509990002" {
		t.Errorf("Scan() mismatch: got '%s', want '3201015509990002'", scanned)
	}
}

