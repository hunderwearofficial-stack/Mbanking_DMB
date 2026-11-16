package middleware

import (
	"mbanking-bpr/pkg/reqctx"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RequestMeta attaches request id, client IP and user agent to the request
// context for audit attribution (audit DMB-016). ClientIP honours only the
// proxies configured via TRUSTED_PROXIES (see main.go).
func RequestMeta() gin.HandlerFunc {
	return func(c *gin.Context) {
		rid := c.GetHeader("X-Request-ID")
		if len(rid) < 8 || len(rid) > 64 {
			rid = uuid.NewString()
		}
		ua := c.GetHeader("User-Agent")
		if len(ua) > 255 {
			ua = ua[:255]
		}
		c.Header("X-Request-ID", rid)
		c.Request = c.Request.WithContext(reqctx.WithMeta(c.Request.Context(), reqctx.Meta{
			RequestID: rid,
			ClientIP:  c.ClientIP(),
			UserAgent: ua,
		}))
		c.Next()
	}
}
