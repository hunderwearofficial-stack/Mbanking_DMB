package middleware

import (
	"strings"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/response"
	"mbanking-bpr/pkg/utils"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	HeaderDeviceID   = "X-Device-ID"
	CtxUserID        = "user_id"
	CtxCIF           = "cif"
	CtxPhoneNumber   = "phone_number"
	CtxAccountNo     = "account_no"
	CtxDeviceID      = "device_id"
)

// AuthOption configures AuthMiddleware behavior
type AuthConfig struct {
	Secret        string
	DB            *gorm.DB // Optional: for live DB validation of device_id & is_active
	EnforceDevice bool
}

// AuthMiddleware creates a middleware that verifies JWT Access Token and validates Device Binding
func AuthMiddleware(cfg AuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Extract Bearer Token
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, response.CodeUnauthorized, "Header Authorization (Bearer token) dibutuhkan")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			response.Unauthorized(c, response.CodeUnauthorized, "Format Authorization harus 'Bearer <token>'")
			c.Abort()
			return
		}

		tokenString := parts[1]
		claims, err := utils.ValidateAccessToken(tokenString, cfg.Secret)
		if err != nil {
			response.Unauthorized(c, response.CodeUnauthorized, "Token autentikasi tidak valid atau telah kadaluarsa")
			c.Abort()
			return
		}

		// 2. Device Binding Validation
		headerDeviceID := c.GetHeader(HeaderDeviceID)
		if cfg.EnforceDevice {
			if headerDeviceID == "" {
				response.Unauthorized(c, response.CodeUnauthorized, "Header "+HeaderDeviceID+" wajib disertakan untuk validasi perangkat (Device Binding)")
				c.Abort()
				return
			}

			// Validate with token claims (allow seamless upgrade from legacy DEVICE-DEMO-001)
			if claims.DeviceID != "" && claims.DeviceID != "DEVICE-DEMO-001" && claims.DeviceID != headerDeviceID {
				response.Unauthorized(c, response.CodeUnauthorized, "Device ID tidak sesuai dengan token sesi (Device Binding Mismatch)")
				c.Abort()
				return
			}

			// Validate with PostgreSQL User record if DB is connected
			if cfg.DB != nil {
				var user model.User
				if err := cfg.DB.WithContext(c.Request.Context()).Select("id", "device_id", "is_active").First(&user, "id = ?", claims.UserID).Error; err != nil {
					response.Unauthorized(c, response.CodeUnauthorized, "Data pengguna tidak ditemukan pada sistem")
					c.Abort()
					return
				}

				if !user.IsActive {
					response.Unauthorized(c, response.CodeUnauthorized, "Akun pengguna dinonaktifkan")
					c.Abort()
					return
				}

				if (user.DeviceID == "" || user.DeviceID == "DEVICE-DEMO-001") && headerDeviceID != "" && headerDeviceID != "DEVICE-DEMO-001" {
					_ = cfg.DB.WithContext(c.Request.Context()).Model(&model.User{}).Where("id = ?", user.ID).Update("device_id", headerDeviceID).Error
					user.DeviceID = headerDeviceID
				} else if user.DeviceID != "" && user.DeviceID != headerDeviceID {
					response.Unauthorized(c, response.CodeUnauthorized, "Perangkat ini tidak terdaftar untuk akun Anda (Device Binding Terkunci)")
					c.Abort()
					return
				}
			}
		}

		// 3. Inject verified claims into Gin Context
		c.Set(CtxUserID, claims.UserID)
		c.Set(CtxCIF, claims.CIF)
		c.Set(CtxPhoneNumber, claims.PhoneNumber)
		c.Set(CtxAccountNo, claims.AccountNo)
		c.Set(CtxDeviceID, headerDeviceID)

		c.Next()
	}
}

// JWTAuth provides backward compatible helper
func JWTAuth(secret string) gin.HandlerFunc {
	return AuthMiddleware(AuthConfig{
		Secret:        secret,
		EnforceDevice: false,
	})
}

