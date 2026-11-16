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

// KeyFunc derives the rate-limit subject from a request. Returning "" skips that limiter.
type KeyFunc func(c *gin.Context) string

// ByIP limits per client IP. ClientIP only trusts proxies configured in TRUSTED_PROXIES,
// so X-Forwarded-For cannot be spoofed by clients (audit DMB-018).
func ByIP(c *gin.Context) string { return c.ClientIP() }

// ByUser limits per authenticated customer.
func ByUser(c *gin.Context) string { return c.GetString(CtxUserID) }

// ByJSONField limits per value of a JSON body field (e.g. phone number), so that
// distributed attacks against one account are throttled independently of IP.
// The value is hashed so that no PII is stored in the rate-limit keys.
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
				v = strings.ToLower(strings.TrimSpace(v))
				if v != "" {
					sum := sha256.Sum256([]byte(v))
					return hex.EncodeToString(sum[:16])
				}
			}
		}
		return ""
	}
}

// RateLimiterBy limits requests per subject returned by keyFn. FAIL-CLOSED: if the
// limiter backend errors, the request is rejected (audit DMB-018 / DMB-026).
func RateLimiterBy(redisClient *redis.Client, maxRequests int, windowSeconds int, prefix string, keyFn KeyFunc) gin.HandlerFunc {
	return func(c *gin.Context) {
		subject := keyFn(c)
		if subject == "" {
			c.Next()
			return
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
