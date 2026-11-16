// Package otp implements one-time-password challenge state (audit DMB-002, DMB-012).
//
// Properties:
//   - No static/master code: only the code generated for the session verifies.
//   - The code is stored as HMAC-SHA256 (keyed), never in plaintext.
//   - Limited attempts (MaxAttempts); the session is destroyed when exceeded.
//   - Short TTL; single use (Consume deletes the session).
//   - Bound to the device that requested it.
//   - State lives in Redis (shared across instances / restarts) with an
//     in-memory fallback for single-instance development.
package otp

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"mbanking-bpr/pkg/redis"

	"github.com/google/uuid"
)

const (
	// DefaultTTL matches the validity stated in the OTP message sent to customers.
	DefaultTTL = 3 * time.Minute
	// VerifiedTTL is the window to finish the flow after a successful verification.
	VerifiedTTL = 10 * time.Minute
	// MaxAttempts is the number of wrong codes tolerated per session.
	MaxAttempts = 5

	PurposeActivation     = "ACTIVATION"
	PurposeForgotPassword = "FORGOT_PASSWORD"

	keyPrefix = "otp:session:"
)

var (
	ErrSessionNotFound = errors.New("sesi verifikasi tidak ditemukan atau telah kedaluwarsa")
	ErrInvalidCode     = errors.New("kode OTP verifikasi salah")
	ErrTooManyAttempts = errors.New("terlalu banyak percobaan OTP salah. Silakan ulangi proses dari awal")
	ErrNotVerified     = errors.New("kode OTP belum diverifikasi")
	ErrPurposeMismatch = errors.New("sesi verifikasi tidak sesuai untuk proses ini")
	ErrDeviceMismatch  = errors.New("sesi verifikasi harus diselesaikan dari perangkat yang sama")
)

// Session is the state of an OTP challenge.
type Session struct {
	ID          string    `json:"id"`
	Purpose     string    `json:"purpose"`
	UserID      string    `json:"user_id"`
	AccountNo   string    `json:"account_no,omitempty"`
	PhoneNumber string    `json:"phone_number"`
	FullName    string    `json:"full_name"`
	DeviceID    string    `json:"device_id"`
	CodeHash    string    `json:"code_hash"`
	Attempts    int       `json:"attempts"`
	Verified    bool      `json:"verified"`
	ExpiresAt   time.Time `json:"expires_at"`
}

// Store persists OTP sessions.
type Store struct {
	kv  *redis.Client
	key []byte
}

// NewStore creates a store. hmacKey must be a server secret (not sent to clients).
func NewStore(kv *redis.Client, hmacKey string) *Store {
	h := hmac.New(sha256.New, []byte(hmacKey))
	h.Write([]byte("dmb-otp-hmac-v1"))
	return &Store{kv: kv, key: h.Sum(nil)}
}

func (s *Store) hash(sessionID, code string) string {
	m := hmac.New(sha256.New, s.key)
	m.Write([]byte(sessionID))
	m.Write([]byte{0})
	m.Write([]byte(strings.TrimSpace(code)))
	return hex.EncodeToString(m.Sum(nil))
}

func (s *Store) save(ctx context.Context, sess *Session, ttl time.Duration) error {
	b, err := json.Marshal(sess)
	if err != nil {
		return err
	}
	return s.kv.Set(ctx, keyPrefix+sess.ID, b, ttl)
}

func (s *Store) load(ctx context.Context, id string) (*Session, error) {
	if strings.TrimSpace(id) == "" {
		return nil, ErrSessionNotFound
	}
	b, err := s.kv.Get(ctx, keyPrefix+id)
	if err != nil {
		return nil, ErrSessionNotFound
	}
	var sess Session
	if err := json.Unmarshal(b, &sess); err != nil {
		return nil, ErrSessionNotFound
	}
	if time.Now().After(sess.ExpiresAt) {
		_ = s.kv.Del(ctx, keyPrefix+id)
		return nil, ErrSessionNotFound
	}
	return &sess, nil
}

// Create stores a new challenge for code and returns the session id.
func (s *Store) Create(ctx context.Context, sess Session, code string) (string, error) {
	sess.ID = uuid.NewString()
	sess.CodeHash = s.hash(sess.ID, code)
	sess.Attempts = 0
	sess.Verified = false
	sess.ExpiresAt = time.Now().Add(DefaultTTL)
	if err := s.save(ctx, &sess, DefaultTTL); err != nil {
		return "", err
	}
	return sess.ID, nil
}

// Verify checks code for the session. Wrong codes consume an attempt; the session
// is destroyed after MaxAttempts failures.
func (s *Store) Verify(ctx context.Context, id, purpose, deviceID, code string) (*Session, error) {
	sess, err := s.load(ctx, id)
	if err != nil {
		return nil, err
	}
	if sess.Purpose != purpose {
		return nil, ErrPurposeMismatch
	}
	if sess.DeviceID != "" && sess.DeviceID != strings.TrimSpace(deviceID) {
		return nil, ErrDeviceMismatch
	}
	if sess.Verified {
		return sess, nil
	}
	candidate := s.hash(sess.ID, code)
	if !hmac.Equal([]byte(candidate), []byte(sess.CodeHash)) {
		sess.Attempts++
		if sess.Attempts >= MaxAttempts {
			_ = s.kv.Del(ctx, keyPrefix+id)
			return nil, ErrTooManyAttempts
		}
		remaining := time.Until(sess.ExpiresAt)
		if remaining <= 0 {
			return nil, ErrSessionNotFound
		}
		if err := s.save(ctx, sess, remaining); err != nil {
			return nil, err
		}
		return nil, ErrInvalidCode
	}
	sess.Verified = true
	sess.ExpiresAt = time.Now().Add(VerifiedTTL)
	if err := s.save(ctx, sess, VerifiedTTL); err != nil {
		return nil, err
	}
	return sess, nil
}

// Consume returns a verified session and deletes it (single use).
func (s *Store) Consume(ctx context.Context, id, purpose, deviceID string) (*Session, error) {
	sess, err := s.load(ctx, id)
	if err != nil {
		return nil, err
	}
	if sess.Purpose != purpose {
		return nil, ErrPurposeMismatch
	}
	if sess.DeviceID != "" && sess.DeviceID != strings.TrimSpace(deviceID) {
		return nil, ErrDeviceMismatch
	}
	if !sess.Verified {
		return nil, ErrNotVerified
	}
	if err := s.kv.Del(ctx, keyPrefix+id); err != nil {
		return nil, err
	}
	return sess, nil
}
