// Package session implements server-side customer sessions (audit DMB-014):
// logout & revocation, refresh-token rotation and refresh-token reuse detection.
package session

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// ConcurrentRefreshGrace tolerates a client that refreshes twice with the same
// token in a short window (parallel requests) without treating it as theft.
const ConcurrentRefreshGrace = 30 * time.Second

var (
	ErrSessionInvalid    = errors.New("sesi tidak valid atau telah berakhir, silakan login kembali")
	ErrRefreshReused     = errors.New("refresh token telah digunakan sebelumnya; seluruh sesi dicabut demi keamanan")
	ErrConcurrentRefresh = errors.New("sesi sedang diperbarui, silakan ulangi permintaan")
	ErrUnavailable       = errors.New("layanan sesi tidak tersedia")
)

// Revocation reasons
const (
	ReasonLogout         = "LOGOUT"
	ReasonNewLogin       = "NEW_LOGIN"
	ReasonPasswordChange = "PASSWORD_CHANGE"
	ReasonPINChange      = "PIN_CHANGE"
	ReasonPasswordReset  = "PASSWORD_RESET"
	ReasonActivation     = "ACTIVATION"
	ReasonReuseDetected  = "REFRESH_REUSE_DETECTED"
	ReasonAdminAction    = "ADMIN_ACTION"
	ReasonAccountBlocked = "ACCOUNT_BLOCKED"
)

// HashJTI returns the stored fingerprint of a refresh-token id.
func HashJTI(jti string) string {
	s := sha256.Sum256([]byte(jti))
	return hex.EncodeToString(s[:])
}

// Manager persists sessions in PostgreSQL.
type Manager struct {
	db *gorm.DB
}

func NewManager(db *gorm.DB) *Manager { return &Manager{db: db} }

// Create stores a new session.
func (m *Manager) Create(ctx context.Context, sessionID, userID, deviceID, ip, refreshJTI string, expiresAt time.Time) error {
	if m.db == nil {
		return ErrUnavailable
	}
	return m.db.WithContext(ctx).Create(&model.UserSession{
		ID:               sessionID,
		UserID:           userID,
		DeviceID:         deviceID,
		RefreshTokenHash: HashJTI(refreshJTI),
		ExpiresAt:        expiresAt,
		IPAddress:        ip,
	}).Error
}

// IsActive reports whether the session exists, belongs to userID, is not revoked and not expired.
func (m *Manager) IsActive(ctx context.Context, sessionID, userID string) (bool, error) {
	if m.db == nil {
		return false, ErrUnavailable
	}
	var s model.UserSession
	err := m.db.WithContext(ctx).Select("id", "user_id", "expires_at", "revoked_at").
		Where("id = ?", sessionID).First(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return s.UserID == userID && s.RevokedAt == nil && time.Now().Before(s.ExpiresAt), nil
}

// Rotate replaces the session's refresh token. presentedJTI must be the current
// refresh token; if it is the previous one beyond the grace window (or unknown),
// the token is considered stolen and ALL sessions of the user are revoked.
func (m *Manager) Rotate(ctx context.Context, sessionID, userID, presentedJTI, newJTI string, newExpiry time.Time) error {
	if m.db == nil {
		return ErrUnavailable
	}
	presented := HashJTI(presentedJTI)
	var reuse bool
	err := m.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var s model.UserSession
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", sessionID).First(&s).Error; err != nil {
			return ErrSessionInvalid
		}
		if s.UserID != userID || s.RevokedAt != nil || time.Now().After(s.ExpiresAt) {
			return ErrSessionInvalid
		}
		switch {
		case presented == s.RefreshTokenHash:
			now := time.Now()
			return tx.Model(&model.UserSession{}).Where("id = ?", s.ID).Updates(map[string]interface{}{
				"prev_refresh_hash":  s.RefreshTokenHash,
				"refresh_token_hash": HashJTI(newJTI),
				"rotated_at":         now,
				"expires_at":         newExpiry,
			}).Error
		case presented == s.PrevRefreshHash && s.RotatedAt != nil && time.Since(*s.RotatedAt) <= ConcurrentRefreshGrace:
			return ErrConcurrentRefresh
		default:
			reuse = true
			return ErrRefreshReused
		}
	})
	if reuse {
		_ = m.RevokeAllForUser(ctx, userID, ReasonReuseDetected, "")
	}
	return err
}

// Revoke revokes a single session.
func (m *Manager) Revoke(ctx context.Context, sessionID, reason string) error {
	if m.db == nil {
		return ErrUnavailable
	}
	now := time.Now()
	return m.db.WithContext(ctx).Model(&model.UserSession{}).
		Where("id = ? AND revoked_at IS NULL", sessionID).
		Updates(map[string]interface{}{"revoked_at": now, "revoked_reason": reason}).Error
}

// RevokeAllForUser revokes every active session of the user except exceptSessionID (if not empty).
func (m *Manager) RevokeAllForUser(ctx context.Context, userID, reason, exceptSessionID string) error {
	if m.db == nil {
		return ErrUnavailable
	}
	now := time.Now()
	q := m.db.WithContext(ctx).Model(&model.UserSession{}).Where("user_id = ? AND revoked_at IS NULL", userID)
	if exceptSessionID != "" {
		q = q.Where("id <> ?", exceptSessionID)
	}
	return q.Updates(map[string]interface{}{"revoked_at": now, "revoked_reason": reason}).Error
}
