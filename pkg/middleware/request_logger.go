package middleware

import (
	"bytes"
	"io"
	"strings"
	"time"

	"mbanking-bpr/pkg/logger"

	"github.com/gin-gonic/gin"
)

// RequestLogger logs incoming HTTP requests with sensitive payload masking
func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		rawQuery := c.Request.URL.RawQuery
		method := c.Request.Method
		clientIP := c.ClientIP()

		var maskedBody string
		// Read and mask request body for POST/PUT/PATCH
		if method == "POST" || method == "PUT" || method == "PATCH" {
			contentType := c.GetHeader("Content-Type")
			if strings.Contains(contentType, "application/json") {
				bodyBytes, err := io.ReadAll(c.Request.Body)
				if err == nil {
					// Restore request body for downstream handlers
					c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
					maskedBody = logger.MaskJSONString(string(bodyBytes))
				}
			}
		}

		c.Next()

		latency := time.Since(start)
		statusCode := c.Writer.Status()

		fields := map[string]interface{}{
			"status":     statusCode,
			"latency_ms": latency.Milliseconds(),
			"client_ip":  clientIP,
			"method":     method,
			"path":       path,
		}

		if rawQuery != "" {
			fields["query"] = rawQuery
		}

		if maskedBody != "" {
			fields["payload"] = maskedBody
		}

		logMsg := "HTTP Request"
		if statusCode >= 500 {
			logger.GetLogger().Error(logMsg, fields)
		} else if statusCode >= 400 {
			logger.GetLogger().Warn(logMsg, fields)
		} else {
			logger.GetLogger().Info(logMsg, fields)
		}
	}
}

