package devicebind

import (
	"net/http"
	"strings"

	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

const (
	CodeDeviceVerification  = "10" // signature missing / invalid / expired / replayed
	CodeEnrollmentRequired  = "11" // enforced mode: no active key yet
	CodeAttestationRequired = "13" // attestation enforce: the device cannot prove a genuine hardware key
)

func (s *Service) RequireEnrolled(exemptPrefixes ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if s == nil || s.opt.Mode != ModeEnforced {
			c.Next()
			return
		}
		path := c.Request.URL.Path
		for _, p := range exemptPrefixes {
			if strings.HasPrefix(path, p) {
				c.Next()
				return
			}
		}
		key, err := s.ActiveKey(c.Request.Context(), c.GetString(middleware.CtxUserID))
		if err != nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan verifikasi perangkat tidak tersedia", "99", nil)
			c.Abort()
			return
		}
		if key == nil {
			response.Error(c, http.StatusForbidden, ErrEnrollmentRequired.Error(), CodeEnrollmentRequired, gin.H{"action": "ENROLL_DEVICE_KEY"})
			c.Abort()
			return
		}
		c.Next()
	}
}

func (s *Service) SummaryHandler(c *gin.Context) {
	sum, err := s.Summary(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusServiceUnavailable, "Ringkasan device binding tidak tersedia", "99", nil)
		return
	}
	response.Success(c, "Ringkasan device binding", sum)
}
