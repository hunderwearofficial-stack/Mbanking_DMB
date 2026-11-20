package middleware

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type KeyFunc func(c *gin.Context) string

func ByIP(c *gin.Context) string { return c.ClientIP() }

func ByUser(c *gin.Context) string { return c.GetString(CtxUserID) }

func ByJSONField(fields ...string) KeyFunc {
	return func(c *gin.Context) string {
		if c.Request.Body == nil {
			return ""
		}
		raw, err := io.ReadAll(io.LimitReader(c.Request.Body, 64*1024))
		if err != nil {
			return ""
		}
		c.Request.Body = io.NopCloser(bytes.NewBuffer(raw))
		var m map[string]interface{}
		if json.Unmarshal(raw, &m) != nil {
			return ""
		}
		for _, f := range fields {
			if v, ok := m[f].(string); ok {
				v = canonicalIdentity(v)
				if v != "" {
					sum := sha256.Sum256([]byte(v))
					return hex.EncodeToString(sum[:16])
				}
			}
		}
		return ""
	}
}

// canonicalIdentity maps every spelling of the same identity to one rate-limit key
// (audit E-05): "+62 812-3456", "62812-3456" and "0812 3456" are the same phone number,
// exactly as the login normalises it.
func canonicalIdentity(v string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	compact := strings.NewReplacer(" ", "", "-", "", ".", "", "(", "", ")", "").Replace(v)
	digits := strings.TrimPrefix(compact, "+")
	if digits != "" && strings.Trim(digits, "0123456789") == "" {
		if strings.HasPrefix(digits, "62") {
			digits = "0" + digits[2:]
		}
		return digits
	}
	return v
}

func RateLimiterBy(redisClient *redis.Client, maxRequests int, windowSeconds int, prefix string, keyFn KeyFunc) gin.HandlerFunc {
	return func(c *gin.Context) {
		subject := keyFn(c)
		if subject == "" {
			// SECURITY (audit E-05): a request without the identity field is still limited,
			// keyed by client IP, instead of skipping the limiter.
			subject = "noid:" + c.ClientIP()
		}
		cacheKey := fmt.Sprintf("ratelimit:%s:%s", prefix, subject)
		allowed, remaining, err := redisClient.IncrementAndCheckRateLimit(c.Request.Context(), cacheKey, maxRequests, windowSeconds)
		if err != nil {
			response.Error(c, http.StatusServiceUnavailable, "Layanan sedang sibuk, silakan coba beberapa saat lagi", "99", nil)
			c.Abort()
			return
		}

		c.Header("X-RateLimit-Limit", strconv.Itoa(maxRequests))
		c.Header("X-RateLimit-Remaining", strconv.Itoa(remaining))

		if !allowed {
			response.TooManyRequests(c, fmt.Sprintf("Batas permintaan terlampaui (%d per %d detik). Silakan coba beberapa saat lagi.", maxRequests, windowSeconds))
			c.Abort()
			return
		}
		c.Next()
	}
}
