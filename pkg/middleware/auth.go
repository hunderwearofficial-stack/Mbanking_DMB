package middleware

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/reqctx"
	"mbanking-bpr/pkg/response"
	"mbanking-bpr/pkg/security"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	HeaderDeviceID = "X-Device-ID"
	CtxUserID      = "user_id"
	CtxCIF         = "cif"
	CtxPhoneNumber = "phone_number"
	CtxAccountNo   = "account_no"
	CtxDeviceID    = "device_id"
	CtxSessionID   = "session_id"

	CtxAdminID       = "admin_id"
	CtxAdminUsername = "admin_username"
	CtxAdminRole     = "admin_role"
)

// ErrDeviceKeyNotAccepted: the active device key does not satisfy the attestation policy
// (DEVICE_ATTESTATION_MODE=enforce, SR-2). The session is refused; the customer re-binds.
var ErrDeviceKeyNotAccepted = errors.New("kunci keamanan perangkat tidak memenuhi kebijakan verifikasi keamanan Bank DMB. Silakan verifikasi ulang perangkat melalui menu Lupa Password")

var deviceIDPattern = regexp.MustCompile(`^[A-Za-z0-9._:\-]{6,128}$`)

func ValidDeviceID(id string) bool {
	return deviceIDPattern.MatchString(strings.TrimSpace(id))
}

type SessionChecker interface {
	IsActive(ctx context.Context, sessionID, userID string) (bool, error)
}

type AuthConfig struct {
	Secret     string
	DB         *gorm.DB
	Sessions   SessionChecker
	DeviceKeys DeviceKeyChecker
}

type DeviceKeyChecker interface {
	ActiveKeyID(ctx context.Context, userID string) (keyID string, applies bool, err error)
}

func bearerToken(c *gin.Context) (string, bool) {
	parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		return "", false
	}
	return strings.TrimSpace(parts[1]), true
}

func AuthMiddleware(cfg AuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		deny := func(msg string) {
			response.Unauthorized(c, response.CodeUnauthorized, msg)
			c.Abort()
		}

		tokenString, ok := bearerToken(c)
		if !ok {
			deny("Sesi masuk diperlukan. Silakan login kembali.")
			return
		}
		claims, err := security.ValidateAccessToken(tokenString, cfg.Secret)
		if err != nil {
			deny("Sesi Anda telah berakhir. Silakan login kembali.")
			return
		}

		if cfg.DB == nil || cfg.Sessions == nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan sedang tidak tersedia. Silakan coba beberapa saat lagi.", "99", nil)
			c.Abort()
			return
		}

		active, err := cfg.Sessions.IsActive(c.Request.Context(), claims.SessionID, claims.UserID)
		if err != nil || !active {
			deny("Sesi Anda telah berakhir. Silakan login kembali.")
			return
		}

		headerDeviceID := strings.TrimSpace(c.GetHeader(HeaderDeviceID))
		if !ValidDeviceID(headerDeviceID) {
			deny("Identitas perangkat tidak ditemukan. Silakan muat ulang aplikasi.")
			return
		}
		if claims.DeviceID == "" || claims.DeviceID != headerDeviceID {
			deny("Perangkat tidak sesuai dengan sesi aktif Anda. Silakan login kembali.")
			return
		}

		var user model.User
		if err := cfg.DB.WithContext(c.Request.Context()).Select("id", "device_id", "is_active").
			First(&user, "id = ?", claims.UserID).Error; err != nil {
			deny("Data pengguna tidak ditemukan")
			return
		}
		if !user.IsActive {
			deny("Akun Anda sedang dinonaktifkan. Silakan hubungi Customer Service Bank DMB.")
			return
		}
		if user.DeviceID == "" || user.DeviceID != headerDeviceID {
			deny("Akun Anda telah login di perangkat lain. Sesi di perangkat ini otomatis berakhir.")
			return
		}
		if cfg.DeviceKeys != nil {
			activeKey, applies, kerr := cfg.DeviceKeys.ActiveKeyID(c.Request.Context(), claims.UserID)
			if errors.Is(kerr, ErrDeviceKeyNotAccepted) {
				response.Error(c, http.StatusForbidden, ErrDeviceKeyNotAccepted.Error(), "13", gin.H{"action": "VERIFY_DEVICE_VIA_FORGOT_PASSWORD"})
				c.Abort()
				return
			}
			if kerr != nil {
				response.Error(c, http.StatusServiceUnavailable, "Layanan verifikasi perangkat sedang tidak tersedia", "99", nil)
				c.Abort()
				return
			}
			if applies && activeKey != claims.DeviceKeyID {
				deny("Sesi tidak lagi sesuai dengan kunci keamanan perangkat. Silakan login kembali.")
				return
			}
		}

		c.Set(CtxUserID, claims.UserID)
		c.Set(CtxCIF, claims.CIF)
		c.Set(CtxPhoneNumber, claims.PhoneNumber)
		c.Set(CtxAccountNo, claims.AccountNo)
		c.Set(CtxDeviceID, headerDeviceID)
		c.Set(CtxSessionID, claims.SessionID)
		c.Next()
	}
}

// Backoffice session transport (audit E-02). The session token travels in an HttpOnly,
// SameSite=Strict cookie that page scripts cannot read; a Bearer header is still accepted
// for non-browser API clients. Cookie-authenticated state-changing requests must carry the
// AdminCSRFHeader: a cross-site page cannot set it without a CORS preflight (no origin is
// allowed), so a forged form or link cannot act with the officer's cookie.
const (
	AdminSessionCookie = "dmb_admin_session"
	AdminCookiePath    = "/api/v1/admin"
	AdminCSRFHeader    = "X-Requested-With"
	AdminCSRFValue     = "dmb-admin"
	CtxAdminTokenID    = "admin_token_id"
	CtxAdminTokenExp   = "admin_token_exp"
)

// AdminAuthConfig configures AdminAuth. Revoked reports a token id revoked by logout.
type AdminAuthConfig struct {
	Secret  string
	DB      *gorm.DB
	Revoked func(ctx context.Context, tokenID string) bool
}

func adminToken(c *gin.Context) (token string, fromCookie bool) {
	if v, err := c.Cookie(AdminSessionCookie); err == nil && strings.TrimSpace(v) != "" {
		return strings.TrimSpace(v), true
	}
	if v, ok := bearerToken(c); ok {
		return v, false
	}
	return "", false
}

func safeMethod(m string) bool {
	return m == http.MethodGet || m == http.MethodHead || m == http.MethodOptions
}

func AdminAuth(cfg AdminAuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, fromCookie := adminToken(c)
		if tokenString == "" {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas tidak ditemukan")
			c.Abort()
			return
		}
		if fromCookie && !safeMethod(c.Request.Method) && c.GetHeader(AdminCSRFHeader) != AdminCSRFValue {
			response.Error(c, http.StatusForbidden, "Permintaan ditolak: tanda keamanan konsol tidak ditemukan", "01", nil)
			c.Abort()
			return
		}
		claims, err := security.ValidateAdminToken(tokenString, cfg.Secret)
		if err != nil {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas tidak valid atau telah kadaluarsa")
			c.Abort()
			return
		}
		if cfg.Revoked != nil && cfg.Revoked(c.Request.Context(), claims.ID) {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas telah diakhiri")
			c.Abort()
			return
		}
		if cfg.DB == nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan autentikasi tidak tersedia", "99", nil)
			c.Abort()
			return
		}
		var admin model.AdminUser
		if err := cfg.DB.WithContext(c.Request.Context()).Select("id", "username", "role", "is_active").
			First(&admin, "id = ?", claims.AdminID).Error; err != nil || !admin.IsActive {
			response.Unauthorized(c, response.CodeUnauthorized, "Akun petugas tidak aktif")
			c.Abort()
			return
		}
		if !model.IsValidAdminRole(admin.Role) {
			response.Error(c, http.StatusForbidden, "Role petugas tidak valid", "01", nil)
			c.Abort()
			return
		}

		c.Set(CtxAdminID, admin.ID)
		c.Set(CtxAdminUsername, admin.Username)
		c.Set(CtxAdminRole, admin.Role)
		c.Set(CtxAdminTokenID, claims.ID)
		if claims.ExpiresAt != nil {
			c.Set(CtxAdminTokenExp, claims.ExpiresAt.Time)
		}
		c.Request = c.Request.WithContext(reqctx.WithAdmin(c.Request.Context(), reqctx.Admin{
			ID: admin.ID, Username: admin.Username, Role: admin.Role,
		}))
		c.Next()
	}
}

// AdminMFASetupAuth accepts only the short-lived MFA-enrolment token issued at login to an
// officer without TOTP (audit E-01). It grants nothing but the officer's own enrolment.
func AdminMFASetupAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, ok := bearerToken(c)
		if !ok {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi pendaftaran MFA tidak ditemukan")
			c.Abort()
			return
		}
		claims, err := security.ValidateAdminTokenOfType(tokenString, secret, security.TokenTypeAdminMFASetup)
		if err != nil {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi pendaftaran MFA tidak valid atau telah kadaluarsa. Silakan login ulang")
			c.Abort()
			return
		}
		c.Set(CtxAdminID, claims.AdminID)
		c.Set(CtxAdminUsername, claims.Username)
		c.Set(CtxAdminRole, claims.Role)
		c.Request = c.Request.WithContext(reqctx.WithAdmin(c.Request.Context(), reqctx.Admin{
			ID: claims.AdminID, Username: claims.Username, Role: claims.Role,
		}))
		c.Next()
	}
}

func RequireRoles(roles ...string) gin.HandlerFunc {
	allowed := map[string]bool{}
	for _, r := range roles {
		allowed[r] = true
	}
	return func(c *gin.Context) {
		if !allowed[c.GetString(CtxAdminRole)] {
			response.Error(c, http.StatusForbidden, "Anda tidak memiliki hak akses untuk fungsi ini", "01", nil)
			c.Abort()
			return
		}
		c.Next()
	}
}
