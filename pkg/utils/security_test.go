package utils

import (
	"testing"
)

func TestPasswordHashing(t *testing.T) {
	rawPassword := "rahasia123"
	hash, err := HashPassword(rawPassword)
	if err != nil {
		t.Fatalf("Gagal hash password: %v", err)
	}

	if !CheckPassword(hash, rawPassword) {
		t.Errorf("Password cocok harus mengembalikan true")
	}

	if CheckPassword(hash, "wrongpassword") {
		t.Errorf("Password salah harus mengembalikan false")
	}
}

func TestPINValidationAndHashing(t *testing.T) {
	validPIN := "123456"
	hash, err := HashPIN(validPIN)
	if err != nil {
		t.Fatalf("Gagal hash PIN: %v", err)
	}

	if !CheckPIN(hash, validPIN) {
		t.Errorf("PIN cocok harus mengembalikan true")
	}

	if CheckPIN(hash, "654321") {
		t.Errorf("PIN salah harus mengembalikan false")
	}

	// Invalid PIN formats
	invalidPINs := []string{"12345", "1234567", "12a456", "abcdef", ""}
	for _, pin := range invalidPINs {
		if err := ValidatePINFormat(pin); err == nil {
			t.Errorf("PIN format '%s' harusnya invalid tapi lolos", pin)
		}
	}
}

func TestJWTTokenPairAndClaims(t *testing.T) {
	secret := "test-secret-key-123"
	userID := "usr-uuid-001"
	cif := "CIF998877"
	phone := "081234567890"
	accountNo := "1001002003"
	deviceID := "DEVICE-TEST-001"

	tokens, err := GenerateTokenPair(userID, cif, phone, accountNo, deviceID, secret, 15, 7)
	if err != nil {
		t.Fatalf("Gagal generate token pair: %v", err)
	}

	if tokens.AccessToken == "" || tokens.RefreshToken == "" {
		t.Fatalf("Token tidak boleh kosong")
	}

	// Validate Access Token
	claims, err := ValidateAccessToken(tokens.AccessToken, secret)
	if err != nil {
		t.Fatalf("Gagal validasi access token: %v", err)
	}

	if claims.UserID != userID || claims.DeviceID != deviceID || claims.TokenType != TokenTypeAccess {
		t.Errorf("Claims access token tidak sesuai: %+v", claims)
	}

	// Validate Refresh Token
	refreshClaims, err := ValidateRefreshToken(tokens.RefreshToken, secret)
	if err != nil {
		t.Fatalf("Gagal validasi refresh token: %v", err)
	}

	if refreshClaims.TokenType != TokenTypeRefresh || refreshClaims.UserID != userID {
		t.Errorf("Claims refresh token tidak sesuai: %+v", refreshClaims)
	}

	// Cross validation: Access Token should not pass as Refresh Token
	if _, err := ValidateRefreshToken(tokens.AccessToken, secret); err == nil {
		t.Errorf("Access token tidak boleh valid saat divalidasi sebagai refresh token")
	}
}

