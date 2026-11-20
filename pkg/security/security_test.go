package security

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	testCustomerSecret = "test-only-customer-secret-0123456789abcdef"
	testAdminSecret    = "test-only-admin-secret-fedcba9876543210xyz"
)

func TestPasswordHashing(t *testing.T) {
	raw := "Contoh-Pw-2026"
	hash, err := HashPassword(raw)
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if !CheckPassword(hash, raw) {
		t.Error("matching password must return true")
	}
	if CheckPassword(hash, "wrongpassword1") {
		t.Error("wrong password must return false")
	}
	if CheckPassword("", raw) {
		t.Error("empty hash (not activated) must never match")
	}
}

func TestPasswordPolicy(t *testing.T) {
	for _, pw := range []string{"short1", "onlyletters", "1234567890"} {
		if ValidateNewPassword(pw) == nil {
			t.Errorf("weak password %q accepted", pw)
		}
	}
	if err := ValidateNewPassword("Kuat-Sekali-99"); err != nil {
		t.Errorf("strong password rejected: %v", err)
	}
}

func TestCompromisedCredentialFingerprints(t *testing.T) {
	if len(compromisedCredentialHashes) == 0 {
		t.Fatal("compromised credential list empty")
	}
	if IsCompromisedCredential("Kuat-Sekali-99") {
		t.Fatal("ordinary password flagged as compromised")
	}
}

func TestPINValidationAndHashing(t *testing.T) {
	pin := "583920"
	hash, err := HashPIN(pin)
	if err != nil {
		t.Fatalf("hash PIN: %v", err)
	}
	if !CheckPIN(hash, pin) || CheckPIN(hash, "583921") {
		t.Error("PIN comparison incorrect")
	}
	if CheckPIN("", pin) {
		t.Error("empty PIN hash must never match")
	}
	for _, bad := range []string{"12345", "1234567", "12a456", "abcdef", ""} {
		if ValidatePINFormat(bad) == nil {
			t.Errorf("invalid PIN format %q accepted", bad)
		}
	}
}

func TestWeakPIN(t *testing.T) {
	for _, p := range []string{"111111", "000000", "123456", "456789", "987654", "654321"} {
		if !IsWeakPIN(p) || ValidateNewPIN(p) == nil {
			t.Errorf("weak PIN %q not detected", p)
		}
	}
	for _, p := range []string{"583920", "102938", "112233"} {
		if IsWeakPIN(p) {
			t.Errorf("PIN %q wrongly flagged weak", p)
		}
	}
}

func testInput() CustomerTokenInput {
	return CustomerTokenInput{
		UserID: "usr-uuid-001", CIF: "000000000000", PhoneNumber: "080000000000",
		AccountNo: "0000000000000000", DeviceID: "TEST-DEVICE-1", SessionID: "sess-1",
	}
}

func TestCustomerTokenPair(t *testing.T) {
	tokens, err := GenerateTokenPair(testInput(), testCustomerSecret, 15*time.Minute, 7*24*time.Hour)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	if tokens.RefreshTokenID == "" {
		t.Fatal("refresh jti must be returned for server-side storage")
	}
	claims, err := ValidateAccessToken(tokens.AccessToken, testCustomerSecret)
	if err != nil || claims.SessionID != "sess-1" || claims.TokenType != TokenTypeAccess {
		t.Fatalf("access claims invalid: %+v %v", claims, err)
	}
	rc, err := ValidateRefreshToken(tokens.RefreshToken, testCustomerSecret)
	if err != nil || rc.ID != tokens.RefreshTokenID {
		t.Fatalf("refresh claims invalid: %v", err)
	}
	if _, err := ValidateRefreshToken(tokens.AccessToken, testCustomerSecret); err == nil {
		t.Error("access token must not validate as refresh token")
	}
	if _, err := ValidateAccessToken(tokens.AccessToken, testAdminSecret); err == nil {
		t.Error("token must not validate with another key")
	}
}

func TestCustomerAndAdminTokensAreNotInterchangeable(t *testing.T) {
	tokens, _ := GenerateTokenPair(testInput(), testCustomerSecret, 15*time.Minute, time.Hour)
	if _, err := ValidateAdminToken(tokens.AccessToken, testAdminSecret); err == nil {
		t.Fatal("customer token accepted as admin token (wrong key)")
	}
	if _, err := ValidateAdminToken(tokens.AccessToken, testCustomerSecret); err == nil {
		t.Fatal("customer token accepted as admin token (same key, wrong audience/type)")
	}
	adminTok, _, err := GenerateAdminToken("adm-1", "petugas", "CS", testAdminSecret, time.Hour)
	if err != nil {
		t.Fatalf("admin token: %v", err)
	}
	if _, err := ValidateAccessToken(adminTok, testAdminSecret); err == nil {
		t.Fatal("admin token accepted as customer token")
	}
	ac, err := ValidateAdminToken(adminTok, testAdminSecret)
	if err != nil || ac.Role != "CS" {
		t.Fatalf("admin token invalid: %v", err)
	}
}

func TestRejectsAlgNoneAndOtherAlgorithms(t *testing.T) {
	claims := &JWTClaims{UserID: "u", SessionID: "s", TokenType: TokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{Issuer: TokenIssuer, Audience: jwt.ClaimStrings{AudienceMobile},
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}}
	none, _ := jwt.NewWithClaims(jwt.SigningMethodNone, claims).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if _, err := ValidateAccessToken(none, testCustomerSecret); err == nil {
		t.Fatal("alg=none accepted")
	}
	hs512, _ := jwt.NewWithClaims(jwt.SigningMethodHS512, claims).SignedString([]byte(testCustomerSecret))
	if _, err := ValidateAccessToken(hs512, testCustomerSecret); err == nil {
		t.Fatal("non-allowlisted algorithm accepted")
	}
}

func TestExpiredTokenRejected(t *testing.T) {
	tokens, _ := GenerateTokenPair(testInput(), testCustomerSecret, -time.Minute, time.Hour)
	if _, err := ValidateAccessToken(tokens.AccessToken, testCustomerSecret); err == nil {
		t.Fatal("expired token accepted")
	}
}
