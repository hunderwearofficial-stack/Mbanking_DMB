package middleware

import (
	"context"
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

var deviceIDPattern = regexp.MustCompile(`^[A-Za-z0-9._:\-]{6,100}$`)

// ValidDeviceID reports whether a device identifier is well-formed.
func ValidDeviceID(id string) bool {
	return deviceIDPattern.MatchString(strings.TrimSpace(id))
}

// SessionChecker verifies server-side session state.
type SessionChecker interface {
	IsActive(ctx context.Context, sessionID, userID string) (bool, error)
}

// AuthConfig configures the customer authentication middleware.
type AuthConfig struct {
	Secret   string
	DB       *gorm.DB
	Sessions SessionChecker
}

func bearerToken(c *gin.Context) (string, bool) {
	parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		return "", false
	}
	return strings.TrimSpace(parts[1]), true
}

// AuthMiddleware authenticates customers (mobile app):
//   - valid access token signed with the customer key (audience dmb-mobile);
//   - active server-side session (revocable via logout / password change);
//   - X-Device-ID must match both the token and the device bound to the account
//     (no automatic re-binding here: binding happens only after OTP verification);
//   - account must be active.
//
// Fail-closed: any lookup error denies the request.
func AuthMiddleware(cfg AuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		deny := func(msg string) {
			response.Unauthorized(c, response.CodeUnauthorized, msg)
			c.Abort()
		}

		tokenString, ok := bearerToken(c)
		if !ok {
			deny("Header Authorization (Bearer token) dibutuhkan")
			return
		}
		claims, err := security.ValidateAccessToken(tokenString, cfg.Secret)
		if err != nil {
			deny("Token autentikasi tidak valid atau telah kadaluarsa")
			return
		}

		if cfg.DB == nil || cfg.Sessions == nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan autentikasi tidak tersedia", "99", nil)
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
			deny("Header " + HeaderDeviceID + " wajib disertakan untuk validasi perangkat (Device Binding)")
			return
		}
		if claims.DeviceID == "" || claims.DeviceID != headerDeviceID {
			deny("Device ID tidak sesuai dengan token sesi (Device Binding Mismatch)")
			return
		}

		var user model.User
		if err := cfg.DB.WithContext(c.Request.Context()).Select("id", "device_id", "is_active").
			First(&user, "id = ?", claims.UserID).Error; err != nil {
			deny("Data pengguna tidak ditemukan pada sistem")
			return
		}
		if !user.IsActive {
			deny("Akun pengguna dinonaktifkan")
			return
		}
		if user.DeviceID == "" || user.DeviceID != headerDeviceID {
			deny("Akun Anda telah login di perangkat lain. Sesi di perangkat ini otomatis berakhir.")
			return
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

// AdminAuth authenticates backoffice users with the dedicated admin key and
// re-checks the account (active flag, current role) on every request, so that
// disabling an officer or changing their role takes effect immediately.
func AdminAuth(secret string, db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, ok := bearerToken(c)
		if !ok {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas tidak ditemukan")
			c.Abort()
			return
		}
		claims, err := security.ValidateAdminToken(tokenString, secret)
		if err != nil {
			response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas tidak valid atau telah kadaluarsa")
			c.Abort()
			return
		}
		if db == nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan autentikasi tidak tersedia", "99", nil)
			c.Abort()
			return
		}
		var admin model.AdminUser
		if err := db.WithContext(c.Request.Context()).Select("id", "username", "role", "is_active").
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
		c.Request = c.Request.WithContext(reqctx.WithAdmin(c.Request.Context(), reqctx.Admin{
			ID: admin.ID, Username: admin.Username, Role: admin.Role,
		}))
		c.Next()
	}
}

// RequireRoles allows the request only for the listed backoffice roles.
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
