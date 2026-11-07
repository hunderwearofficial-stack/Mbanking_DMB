package utils

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrInvalidToken      = errors.New("token tidak valid atau telah kadaluarsa")
	ErrInvalidTokenType = errors.New("tipe token tidak sesuai")
)

const (
	TokenTypeAccess  = "ACCESS"
	TokenTypeRefresh = "REFRESH"
)

// JWTClaims holds standard & custom claims for access token
type JWTClaims struct {
	UserID      string `json:"user_id"`
	CIF         string `json:"cif"`
	PhoneNumber string `json:"phone_number"`
	AccountNo   string `json:"account_no"`
	DeviceID    string `json:"device_id"`
	TokenType   string `json:"token_type"`
	jwt.RegisteredClaims
}

// TokenPair contains generated access and refresh tokens
type TokenPair struct {
	AccessToken   string    `json:"access_token"`
	RefreshToken  string    `json:"refresh_token"`
	AccessExpiry  time.Time `json:"access_expiry"`
	RefreshExpiry time.Time `json:"refresh_expiry"`
}

// GenerateTokenPair generates both short-lived Access Token (e.g. 15m) and long-lived Refresh Token (e.g. 7d)
func GenerateTokenPair(userID, cif, phoneNumber, accountNo, deviceID, secret string, accessExpMinutes, refreshExpDays int) (*TokenPair, error) {
	if accessExpMinutes <= 0 {
		accessExpMinutes = 15 // default 15 minutes
	}
	if refreshExpDays <= 0 {
		refreshExpDays = 7 // default 7 days
	}

	now := time.Now()
	accessExpiry := now.Add(time.Duration(accessExpMinutes) * time.Minute)
	refreshExpiry := now.Add(time.Duration(refreshExpDays) * 24 * time.Hour)

	// 1. Generate Access Token
	accessClaims := &JWTClaims{
		UserID:      userID,
		CIF:         cif,
		PhoneNumber: phoneNumber,
		AccountNo:   accountNo,
		DeviceID:    deviceID,
		TokenType:   TokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.NewString(),
			Subject:   userID,
			Issuer:    "mbanking-bpr-middleware",
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(accessExpiry),
		},
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims).SignedString([]byte(secret))
	if err != nil {
		return nil, err
	}

	// 2. Generate Refresh Token
	refreshClaims := &JWTClaims{
		UserID:      userID,
		CIF:         cif,
		PhoneNumber: phoneNumber,
		AccountNo:   accountNo,
		DeviceID:    deviceID,
		TokenType:   TokenTypeRefresh,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.NewString(),
			Subject:   userID,
			Issuer:    "mbanking-bpr-middleware",
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(refreshExpiry),
		},
	}
	refreshToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims).SignedString([]byte(secret))
	if err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:   accessToken,
		RefreshToken:  refreshToken,
		AccessExpiry:  accessExpiry,
		RefreshExpiry: refreshExpiry,
	}, nil
}

// ValidateAccessToken parses and verifies JWT Access Token
func ValidateAccessToken(tokenString, secret string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return []byte(secret), nil
	})

	if err != nil {
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*JWTClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	if claims.TokenType != TokenTypeAccess {
		return nil, ErrInvalidTokenType
	}

	return claims, nil
}

// ValidateRefreshToken parses and verifies JWT Refresh Token
func ValidateRefreshToken(tokenString, secret string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return []byte(secret), nil
	})

	if err != nil {
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*JWTClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	if claims.TokenType != TokenTypeRefresh {
		return nil, ErrInvalidTokenType
	}

	return claims, nil
}

// Deprecated alias for backward compatibility
func ValidateToken(tokenString, secret string) (*JWTClaims, error) {
	return ValidateAccessToken(tokenString, secret)
}
