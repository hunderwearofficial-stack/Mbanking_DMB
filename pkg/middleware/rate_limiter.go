package middleware

import (
	"fmt"
	"strconv"

	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

// RateLimiter creates a middleware to limit requests per IP or identifier
func RateLimiter(redisClient *redis.Client, maxRequests int, windowSeconds int, prefix string) gin.HandlerFunc {
	return func(c *gin.Context) {
		clientIP := c.ClientIP()
		cacheKey := fmt.Sprintf("ratelimit:%s:%s", prefix, clientIP)

		allowed, remaining, err := redisClient.IncrementAndCheckRateLimit(c.Request.Context(), cacheKey, maxRequests, windowSeconds)
		if err != nil {
			// On rate limiter internal error, fail open or log warning
			c.Next()
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

