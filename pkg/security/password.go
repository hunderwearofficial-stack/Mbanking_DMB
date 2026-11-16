// Package security berisi kebijakan kredensial (hash bcrypt password/PIN, validasi
// kekuatan, penolakan kredensial default terpublikasi) dan penerbitan/validasi JWT
// nasabah & petugas dengan kunci, audience, dan tipe token terpisah (audit DMB-001,
// DMB-014, DMB-025). Enkripsi data at-rest ada di pkg/crypto.
package security

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidPINFormat = errors.New("PIN harus berupa 6 digit angka")
	ErrWeakPIN          = errors.New("PIN terlalu mudah ditebak (angka berulang/berurutan). Gunakan kombinasi lain")
	ErrWeakPassword     = errors.New("password minimal 8 karakter dan wajib mengandung huruf dan angka")
	ErrCompromisedCred  = errors.New("password ini termasuk kredensial default yang telah terpublikasi dan tidak boleh digunakan")
)

// PasswordCost is the bcrypt cost for login passwords and PINs (audit DMB-025).
const PasswordCost = 12

var pinRegex = regexp.MustCompile(`^\d{6}$`)

// compromisedCredentialHashes holds SHA-256 fingerprints of credentials that were
// hardcoded as defaults in earlier versions and published in the public repository
// (audit DMB-003, DMB-009). Stored as hashes so the literal values are not re-published.
var compromisedCredentialHashes = map[string]bool{
	"240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9": true,
	"bee5688aea66a47460b19c76f8f199c6b9585eb726f8322b1429793863609ca2": true,
}

// IsCompromisedCredential reports whether a candidate equals a published default credential.
func IsCompromisedCredential(candidate string) bool {
	sum := sha256.Sum256([]byte(candidate))
	return compromisedCredentialHashes[hex.EncodeToString(sum[:])]
}

// ValidatePINFormat checks if PIN consists of exactly 6 numeric digits
func ValidatePINFormat(pin string) error {
	if !pinRegex.MatchString(pin) {
		return ErrInvalidPINFormat
	}
	return nil
}

// IsWeakPIN reports PINs that are trivially guessable: all-same digits or
// strictly ascending/descending sequences (e.g. 111111, 123456, 987654).
func IsWeakPIN(pin string) bool {
	if !pinRegex.MatchString(pin) {
		return true
	}
	same, asc, desc := true, true, true
	for i := 1; i < len(pin); i++ {
		d := int(pin[i]) - int(pin[i-1])
		if d != 0 {
			same = false
		}
		if d != 1 {
			asc = false
		}
		if d != -1 {
			desc = false
		}
	}
	return same || asc || desc
}

// ValidateNewPIN validates a PIN chosen by the customer.
func ValidateNewPIN(pin string) error {
	if err := ValidatePINFormat(pin); err != nil {
		return err
	}
	if IsWeakPIN(pin) {
		return ErrWeakPIN
	}
	return nil
}

// ValidateNewPassword enforces the minimum password policy.
func ValidateNewPassword(pw string) error {
	if IsCompromisedCredential(pw) {
		return ErrCompromisedCred
	}
	if len(strings.TrimSpace(pw)) < 8 || len(pw) > 72 {
		return ErrWeakPassword
	}
	hasLetter, hasDigit := false, false
	for _, r := range pw {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	if !hasLetter || !hasDigit {
		return ErrWeakPassword
	}
	return nil
}

// HashPassword hashes a password using bcrypt (cost PasswordCost).
func HashPassword(password string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(password), PasswordCost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// CheckPassword compares bcrypt hashed password with plain password.
// An empty hash (account not yet activated) never matches.
func CheckPassword(hashedPassword, password string) bool {
	if hashedPassword == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(password)) == nil
}

// HashPIN hashes 6-digit PIN using bcrypt
func HashPIN(pin string) (string, error) {
	if err := ValidatePINFormat(pin); err != nil {
		return "", err
	}
	b, err := bcrypt.GenerateFromPassword([]byte(pin), PasswordCost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// CheckPIN compares bcrypt hashed PIN with plain PIN. An empty hash never matches.
func CheckPIN(hashedPIN, pin string) bool {
	if hashedPIN == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hashedPIN), []byte(pin)) == nil
}
