package middleware

import (
	"net/http"
	"strings"

	"mbanking-bpr/pkg/reqctx"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func MaxBodyBytes(maxBytes int64) gin.HandlerFunc {
	if maxBytes <= 0 {
		maxBytes = 1 << 20
	}
	return func(c *gin.Context) {
		ct := strings.ToLower(c.GetHeader("Content-Type"))
		if c.Request.Body != nil && !strings.HasPrefix(ct, "multipart/form-data") {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		}
		c.Next()
	}
}

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
