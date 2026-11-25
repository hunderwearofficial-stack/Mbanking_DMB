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
	ErrWeakPassword     = errors.New("password minimal 6 karakter dan wajib mengandung huruf kapital dan angka (contoh: Indo123)")
	ErrCompromisedCred  = errors.New("password ini termasuk kredensial default yang telah terpublikasi dan tidak boleh digunakan")
)

const PasswordCost = 12

var pinRegex = regexp.MustCompile(`^\d{6}$`)

var compromisedCredentialHashes = map[string]bool{
	"240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9": true,
	"bee5688aea66a47460b19c76f8f199c6b9585eb726f8322b1429793863609ca2": true,
}

func IsCompromisedCredential(candidate string) bool {
	sum := sha256.Sum256([]byte(candidate))
	return compromisedCredentialHashes[hex.EncodeToString(sum[:])]
}

func ValidatePINFormat(pin string) error {
	if !pinRegex.MatchString(pin) {
		return ErrInvalidPINFormat
	}
	return nil
}

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

func ValidateNewPIN(pin string) error {
	if err := ValidatePINFormat(pin); err != nil {
		return err
	}
	if IsWeakPIN(pin) {
		return ErrWeakPIN
	}
	return nil
}

func ValidateNewPassword(pw string) error {
	if IsCompromisedCredential(pw) {
		return ErrCompromisedCred
	}
	if len(strings.TrimSpace(pw)) < 6 || len(pw) > 72 {
		return ErrWeakPassword
	}
	hasUpper, hasDigit := false, false
	for _, r := range pw {
		if unicode.IsUpper(r) {
			hasUpper = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	if !hasUpper || !hasDigit {
		return ErrWeakPassword
	}
	return nil
}

func HashPassword(password string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(password), PasswordCost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func CheckPassword(hashedPassword, password string) bool {
	if hashedPassword == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(password)) == nil
}

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

func CheckPIN(hashedPIN, pin string) bool {
	if hashedPIN == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hashedPIN), []byte(pin)) == nil
}
