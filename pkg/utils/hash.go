package utils

import (
	"errors"
	"regexp"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidPINFormat = errors.New("PIN harus berupa 6 digit angka")
)

var pinRegex = regexp.MustCompile(`^\d{6}$`)

// ValidatePINFormat checks if PIN consists of exactly 6 numeric digits
func ValidatePINFormat(pin string) error {
	if !pinRegex.MatchString(pin) {
		return ErrInvalidPINFormat
	}
	return nil
}

// HashPassword hashes plain text password using bcrypt with standard cost 10
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// CheckPassword compares bcrypt hashed password with plain password
func CheckPassword(hashedPassword, password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(password))
	return err == nil
}

// HashPIN hashes 6-digit PIN using bcrypt
func HashPIN(pin string) (string, error) {
	if err := ValidatePINFormat(pin); err != nil {
		return "", err
	}
	bytes, err := bcrypt.GenerateFromPassword([]byte(pin), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// CheckPIN compares bcrypt hashed PIN with plain PIN
func CheckPIN(hashedPIN, pin string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hashedPIN), []byte(pin))
	return err == nil
}

