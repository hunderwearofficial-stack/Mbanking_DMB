package middleware

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestAdminTokenPredatesPasswordChange(t *testing.T) {
	changed := time.Date(2026, 11, 20, 10, 0, 0, 500_000_000, time.UTC) // 10:00:00.5

	if adminTokenPredatesPasswordChange(jwt.NewNumericDate(changed.Add(-time.Hour)), nil) {
		t.Fatal("tanpa riwayat ganti sandi, token tidak boleh ditolak")
	}
	if !adminTokenPredatesPasswordChange(jwt.NewNumericDate(changed.Add(-2*time.Second)), &changed) {
		t.Fatal("token yang terbit sebelum ganti sandi harus ditolak")
	}
	// The session issued in the same second as the change (JWT iat has second precision)
	// must stay valid, otherwise the officer is logged out right after changing it.
	if adminTokenPredatesPasswordChange(jwt.NewNumericDate(changed), &changed) {
		t.Fatal("token yang terbit pada detik yang sama harus tetap berlaku")
	}
	if adminTokenPredatesPasswordChange(jwt.NewNumericDate(changed.Add(time.Minute)), &changed) {
		t.Fatal("token setelah ganti sandi harus berlaku")
	}
	if !adminTokenPredatesPasswordChange(nil, &changed) {
		t.Fatal("token tanpa iat harus ditolak bila sandi pernah diganti")
	}
}
