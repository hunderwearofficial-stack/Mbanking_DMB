package otp

import (
	"context"
	"errors"
	"testing"

	"mbanking-bpr/pkg/redis"
)

func newTestStore() *Store {
	return NewStore(redis.NewMemoryClient(), "test-only-hmac-key-0123456789abcdef")
}

func create(t *testing.T, s *Store, code string) string {
	t.Helper()
	id, err := s.Create(context.Background(), Session{Purpose: PurposeActivation, UserID: "u1", DeviceID: "DEV-1"}, code)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	return id
}

func TestCorrectCodeVerifiesAndConsumesOnce(t *testing.T) {
	s := newTestStore()
	ctx := context.Background()
	id := create(t, s, "482913")
	if _, err := s.Consume(ctx, id, PurposeActivation, "DEV-1"); !errors.Is(err, ErrNotVerified) {
		t.Fatalf("consume before verify must fail, got %v", err)
	}
	if _, err := s.Verify(ctx, id, PurposeActivation, "DEV-1", "482913"); err != nil {
		t.Fatalf("verify: %v", err)
	}
	if _, err := s.Consume(ctx, id, PurposeActivation, "DEV-1"); err != nil {
		t.Fatalf("consume: %v", err)
	}
	if _, err := s.Consume(ctx, id, PurposeActivation, "DEV-1"); !errors.Is(err, ErrSessionNotFound) {
		t.Fatal("session must be single-use")
	}
}

func TestNoMasterCode(t *testing.T) {
	s := newTestStore()
	id := create(t, s, "482913")
	for _, guess := range []string{"123456", "000000", "111111", ""} {
		if _, err := s.Verify(context.Background(), id, PurposeActivation, "DEV-1", guess); err == nil {
			t.Fatalf("static code %q accepted", guess)
		}
	}
}

func TestAttemptLimit(t *testing.T) {
	s := newTestStore()
	ctx := context.Background()
	id := create(t, s, "482913")
	var err error
	for i := 0; i < MaxAttempts; i++ {
		_, err = s.Verify(ctx, id, PurposeActivation, "DEV-1", "000001")
	}
	if !errors.Is(err, ErrTooManyAttempts) {
		t.Fatalf("expected ErrTooManyAttempts, got %v", err)
	}
	if _, err := s.Verify(ctx, id, PurposeActivation, "DEV-1", "482913"); !errors.Is(err, ErrSessionNotFound) {
		t.Fatal("correct code must not work after lockout")
	}
}

func TestDeviceAndPurposeBinding(t *testing.T) {
	s := newTestStore()
	ctx := context.Background()
	id := create(t, s, "482913")
	if _, err := s.Verify(ctx, id, PurposeActivation, "OTHER-DEVICE", "482913"); !errors.Is(err, ErrDeviceMismatch) {
		t.Fatalf("expected device mismatch, got %v", err)
	}
	if _, err := s.Verify(ctx, id, PurposeForgotPassword, "DEV-1", "482913"); !errors.Is(err, ErrPurposeMismatch) {
		t.Fatalf("expected purpose mismatch, got %v", err)
	}
}

func TestCodeNotStoredInPlaintext(t *testing.T) {
	kv := redis.NewMemoryClient()
	s := NewStore(kv, "test-only-hmac-key-0123456789abcdef")
	id, _ := s.Create(context.Background(), Session{Purpose: PurposeActivation}, "482913")
	raw, _ := kv.Get(context.Background(), keyPrefix+id)
	if string(raw) == "" || containsSubstr(string(raw), "482913") {
		t.Fatal("OTP must not be stored in plaintext")
	}
}

func containsSubstr(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
