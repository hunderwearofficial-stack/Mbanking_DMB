package middleware

import (
	"bytes"
	"io"
	"strings"
	"time"

	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/reqctx"

	"github.com/gin-gonic/gin"
)

var noBodyLogPrefixes = []string{
	"/api/v1/auth/",
	"/api/v1/admin/login",
	"/api/v1/admin/users",
	"/api/v1/admin/config",
	"/api/v1/notifications/fcm-token",
}

func bodyLoggable(path string) bool {
	for _, p := range noBodyLogPrefixes {
		if strings.HasPrefix(path, p) {
			return false
		}
	}
	return true
}

func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		var maskedBody string
		if (method == "POST" || method == "PUT" || method == "PATCH") &&
			strings.Contains(c.GetHeader("Content-Type"), "application/json") && bodyLoggable(path) {
			bodyBytes, err := io.ReadAll(io.LimitReader(c.Request.Body, 64*1024))
			if err == nil {
				c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
				maskedBody = logger.MaskJSONString(string(bodyBytes))
			}
		}

		c.Next()

		statusCode := c.Writer.Status()
		meta := reqctx.MetaFrom(c.Request.Context())
		fields := map[string]interface{}{
			"status":     statusCode,
			"latency_ms": time.Since(start).Milliseconds(),
			"client_ip":  c.ClientIP(),
			"method":     method,
			"path":       path,
			"request_id": meta.RequestID,
		}
		if q := logger.MaskQuery(c.Request.URL.RawQuery); q != "" {
			fields["query"] = q
		}
		if maskedBody != "" {
			fields["payload"] = maskedBody
		}

		switch {
		case statusCode >= 500:
			logger.GetLogger().Error("HTTP Request", fields)
		case statusCode >= 400:
			logger.GetLogger().Warn("HTTP Request", fields)
		default:
			logger.GetLogger().Info("HTTP Request", fields)
		}
	}
}
