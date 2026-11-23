package otp

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"mbanking-bpr/pkg/redis"

	"github.com/google/uuid"
)

const (
	DefaultTTL  = 3 * time.Minute
	VerifiedTTL = 10 * time.Minute
	MaxAttempts = 5

	attemptsPrefix = "otp:attempts:"

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

type Session struct {
	ID          string    `json:"id"`
	Purpose     string    `json:"purpose"`
	UserID      string    `json:"user_id"`
	CIF         string    `json:"cif,omitempty"`
	AccountNo   string    `json:"account_no,omitempty"`
	PhoneNumber string    `json:"phone_number"`
	FullName    string    `json:"full_name"`
	DeviceID    string    `json:"device_id"`
	CodeHash    string    `json:"code_hash"`
	Attempts    int       `json:"attempts"`
	Verified    bool      `json:"verified"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type Store struct {
	kv  *redis.Client
	key []byte
}

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

func (s *Store) Create(ctx context.Context, sess Session, code string) (string, error) {
	ttl := SessionTTL()
	sess.ID = uuid.NewString()
	sess.CodeHash = s.hash(sess.ID, code)
	sess.Attempts = 0
	sess.Verified = false
	sess.ExpiresAt = time.Now().Add(ttl)
	if err := s.save(ctx, &sess, ttl); err != nil {
		return "", err
	}
	return sess.ID, nil
}

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
		remaining := time.Until(sess.ExpiresAt)
		if remaining <= 0 {
			return nil, ErrSessionNotFound
		}
		// SECURITY (audit D-06): the wrong-guess counter is an atomic INCR on its own key, so
		// parallel guesses cannot each read the same count and exceed the attempt limit.
		n, err := s.kv.IncrWithTTL(ctx, attemptsPrefix+id, remaining)
		if err != nil {
			return nil, err
		}
		if n >= int64(MaxAttemptsPolicy()) {
			_ = s.kv.Del(ctx, keyPrefix+id, attemptsPrefix+id)
			return nil, ErrTooManyAttempts
		}
		return nil, ErrInvalidCode
	}
	if n, err := s.kv.Get(ctx, attemptsPrefix+id); err == nil && attemptsExhausted(n) {
		// A correct code racing with the last wrong guesses is still refused.
		_ = s.kv.Del(ctx, keyPrefix+id, attemptsPrefix+id)
		return nil, ErrTooManyAttempts
	}
	sess.Verified = true
	sess.ExpiresAt = time.Now().Add(VerifiedTTL)
	if err := s.save(ctx, sess, VerifiedTTL); err != nil {
		return nil, err
	}
	return sess, nil
}

// Consume atomically takes a verified session (GETDEL): a session can be used once even
// under concurrent requests (audit D-06).
func (s *Store) Consume(ctx context.Context, id, purpose, deviceID string) (*Session, error) {
	sess, err := s.load(ctx, id)
	if err != nil {
		return nil, ErrSessionNotFound
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
	b, err := s.kv.GetDel(ctx, keyPrefix+id)
	if err != nil {
		return nil, ErrSessionNotFound
	}
	_ = s.kv.Del(ctx, attemptsPrefix+id)
	var consumed Session
	if err := json.Unmarshal(b, &consumed); err != nil || time.Now().After(consumed.ExpiresAt) {
		return nil, ErrSessionNotFound
	}
	if !consumed.Verified {
		return nil, ErrNotVerified
	}
	return &consumed, nil
}

// OTP policy (OTP_TTL_MINUTES / OTP_MAX_ATTEMPTS). Defaults are the previous constants.
var (
	policyTTL      atomic.Int64
	policyAttempts atomic.Int64
)

// SetPolicy configures the OTP lifetime and wrong-guess limit (called once at startup).
func SetPolicy(ttl time.Duration, maxAttempts int) {
	if ttl > 0 {
		policyTTL.Store(int64(ttl))
	}
	if maxAttempts > 0 {
		policyAttempts.Store(int64(maxAttempts))
	}
}

// SessionTTL is the validity of a freshly sent OTP.
func SessionTTL() time.Duration {
	if v := policyTTL.Load(); v > 0 {
		return time.Duration(v)
	}
	return DefaultTTL
}

// MaxAttemptsPolicy is the number of wrong codes after which the session is destroyed.
func MaxAttemptsPolicy() int {
	if v := policyAttempts.Load(); v > 0 {
		return int(v)
	}
	return MaxAttempts
}

func attemptsExhausted(raw []byte) bool {
	n, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	return err == nil && n >= MaxAttemptsPolicy()
}
