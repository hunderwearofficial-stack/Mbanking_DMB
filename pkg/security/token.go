package security

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrInvalidToken     = errors.New("token tidak valid atau telah kadaluarsa")
	ErrInvalidTokenType = errors.New("tipe token tidak sesuai")
)

const (
	TokenTypeAccess  = "ACCESS"
	TokenTypeRefresh = "REFRESH"
	TokenTypeAdmin   = "ADMIN"
	// TokenTypeAdminMFASetup authorises only the officer's own TOTP enrolment (audit E-01).
	TokenTypeAdminMFASetup = "ADMIN_MFA_SETUP"

	TokenIssuer        = "mbanking-bpr-middleware"
	AudienceMobile     = "dmb-mobile"
	AudienceBackoffice = "dmb-backoffice"
)

type JWTClaims struct {
	UserID      string `json:"user_id"`
	CIF         string `json:"cif"`
	PhoneNumber string `json:"phone_number"`
	AccountNo   string `json:"account_no"`
	DeviceID    string `json:"device_id"`
	DeviceKeyID string `json:"dk,omitempty"`
	SessionID   string `json:"sid"`
	TokenType   string `json:"token_type"`
	jwt.RegisteredClaims
}

type AdminClaims struct {
	AdminID   string `json:"admin_id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	TokenType string `json:"token_type"`
	jwt.RegisteredClaims
}

type TokenPair struct {
	AccessToken    string    `json:"access_token"`
	RefreshToken   string    `json:"refresh_token"`
	AccessExpiry   time.Time `json:"access_expiry"`
	RefreshExpiry  time.Time `json:"refresh_expiry"`
	RefreshTokenID string    `json:"-"` // jti of the refresh token (stored server-side)
}

type CustomerTokenInput struct {
	UserID      string
	CIF         string
	PhoneNumber string
	AccountNo   string
	DeviceID    string
	DeviceKeyID string
	SessionID   string
}

func GenerateTokenPair(in CustomerTokenInput, secret string, accessExp time.Duration, refreshExp time.Duration) (*TokenPair, error) {
	if secret == "" || in.SessionID == "" || in.UserID == "" {
		return nil, ErrInvalidToken
	}
	now := time.Now()
	accessExpiry := now.Add(accessExp)
	refreshExpiry := now.Add(refreshExp)

	mk := func(tokenType string, exp time.Time) (string, string, error) {
		jti := uuid.NewString()
		claims := &JWTClaims{
			UserID:      in.UserID,
			CIF:         in.CIF,
			PhoneNumber: in.PhoneNumber,
			AccountNo:   in.AccountNo,
			DeviceID:    in.DeviceID,
			DeviceKeyID: in.DeviceKeyID,
			SessionID:   in.SessionID,
			TokenType:   tokenType,
			RegisteredClaims: jwt.RegisteredClaims{
				ID:        jti,
				Subject:   in.UserID,
				Issuer:    TokenIssuer,
				Audience:  jwt.ClaimStrings{AudienceMobile},
				IssuedAt:  jwt.NewNumericDate(now),
				NotBefore: jwt.NewNumericDate(now),
				ExpiresAt: jwt.NewNumericDate(exp),
			},
		}
		s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
		return s, jti, err
	}

	access, _, err := mk(TokenTypeAccess, accessExpiry)
	if err != nil {
		return nil, err
	}
	refresh, refreshJTI, err := mk(TokenTypeRefresh, refreshExpiry)
	if err != nil {
		return nil, err
	}
	return &TokenPair{
		AccessToken:    access,
		RefreshToken:   refresh,
		AccessExpiry:   accessExpiry,
		RefreshExpiry:  refreshExpiry,
		RefreshTokenID: refreshJTI,
	}, nil
}

func parseCustomer(tokenString, secret, expectedType string) (*JWTClaims, error) {
	if secret == "" {
		return nil, ErrInvalidToken
	}
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(TokenIssuer),
		jwt.WithAudience(AudienceMobile),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, ErrInvalidToken
	}
	claims, ok := token.Claims.(*JWTClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}
	if claims.TokenType != expectedType {
		return nil, ErrInvalidTokenType
	}
	if claims.SessionID == "" || claims.UserID == "" {
		return nil, ErrInvalidToken
	}
	return claims, nil
}

func ValidateAccessToken(tokenString, secret string) (*JWTClaims, error) {
	return parseCustomer(tokenString, secret, TokenTypeAccess)
}

func ValidateRefreshToken(tokenString, secret string) (*JWTClaims, error) {
	return parseCustomer(tokenString, secret, TokenTypeRefresh)
}

func GenerateAdminToken(adminID, username, role, secret string, ttl time.Duration) (string, time.Time, error) {
	return GenerateAdminTokenOfType(TokenTypeAdmin, adminID, username, role, secret, ttl)
}

// GenerateAdminTokenOfType issues a backoffice token of the given type (full session or
// MFA-enrolment only).
func GenerateAdminTokenOfType(tokenType, adminID, username, role, secret string, ttl time.Duration) (string, time.Time, error) {
	if secret == "" || adminID == "" || role == "" {
		return "", time.Time{}, ErrInvalidToken
	}
	now := time.Now()
	exp := now.Add(ttl)
	claims := &AdminClaims{
		AdminID:   adminID,
		Username:  username,
		Role:      role,
		TokenType: tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.NewString(),
			Subject:   adminID,
			Issuer:    TokenIssuer,
			Audience:  jwt.ClaimStrings{AudienceBackoffice},
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
		},
	}
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
	return s, exp, err
}

func ValidateAdminToken(tokenString, secret string) (*AdminClaims, error) {
	return ValidateAdminTokenOfType(tokenString, secret, TokenTypeAdmin)
}

// ValidateAdminTokenOfType validates a backoffice token and requires the given type.
func ValidateAdminTokenOfType(tokenString, secret, tokenType string) (*AdminClaims, error) {
	if secret == "" {
		return nil, ErrInvalidToken
	}
	token, err := jwt.ParseWithClaims(tokenString, &AdminClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(TokenIssuer),
		jwt.WithAudience(AudienceBackoffice),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, ErrInvalidToken
	}
	claims, ok := token.Claims.(*AdminClaims)
	if !ok || !token.Valid || claims.TokenType != tokenType || claims.AdminID == "" || claims.Role == "" {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
