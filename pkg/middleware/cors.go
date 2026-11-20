package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func CORS(allowedOrigins []string) gin.HandlerFunc {
	allowed := map[string]bool{}
	for _, o := range allowedOrigins {
		allowed[strings.TrimRight(strings.TrimSpace(o), "/")] = true
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != "" && allowed[origin] {
			h := c.Writer.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Vary", "Origin")
			h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Device-ID, X-Request-ID")
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			h.Set("Access-Control-Max-Age", "600")
		}
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func SecurityHeaders() gin.HandlerFunc {
	const adminCSP = "default-src 'self'; " +
		"script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com https://unpkg.com; " +
		"style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
		"font-src 'self' https://fonts.gstatic.com; " +
		"img-src 'self' data:; connect-src 'self'; " +
		"object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		if strings.HasPrefix(c.Request.URL.Path, "/admin") {
			h.Set("Content-Security-Policy", adminCSP)
		} else {
			h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
			h.Set("Cache-Control", "no-store")
		}
		c.Next()
	}
}
