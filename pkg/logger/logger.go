package logger

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

type Level string

const (
	LevelInfo  Level = "INFO"
	LevelWarn  Level = "WARN"
	LevelError Level = "ERROR"
	LevelDebug Level = "DEBUG"
)

type Logger struct {
	env string
}

var AppLogger *Logger

func InitLogger(env string) *Logger {
	AppLogger = &Logger{env: env}
	return AppLogger
}

func GetLogger() *Logger {
	if AppLogger == nil {
		AppLogger = &Logger{env: "development"}
	}
	return AppLogger
}

// LogEntry represents structured log record
type LogEntry struct {
	Timestamp string                 `json:"timestamp"`
	Level     Level                  `json:"level"`
	Message   string                 `json:"message"`
	Fields    map[string]interface{} `json:"fields,omitempty"`
}

// Sensitive field names to automatically mask
var sensitiveKeys = map[string]bool{
	"pin":          true,
	"password":     true,
	"old_pin":      true,
	"new_pin":      true,
	"confirm_pin":  true,
	"cvv":          true,
	"token":        true,
	"access_token": true,
	"secret":       true,
	"otp":          true,
	"pan":          true,
	"card_number":  true,
}

// MaskSensitiveData scans maps or structs and replaces sensitive keys with masked string
func MaskSensitiveData(data map[string]interface{}) map[string]interface{} {
	if data == nil {
		return nil
	}
	masked := make(map[string]interface{})
	for k, v := range data {
		lowerKey := strings.ToLower(k)
		if sensitiveKeys[lowerKey] {
			masked[k] = "******"
		} else if nestedMap, ok := v.(map[string]interface{}); ok {
			masked[k] = MaskSensitiveData(nestedMap)
		} else {
			masked[k] = v
		}
	}
	return masked
}

// MaskJSONString masks sensitive JSON keys in raw string
func MaskJSONString(rawJSON string) string {
	if rawJSON == "" {
		return ""
	}
	// Regex pattern to replace JSON values for sensitive fields
	// e.g. "pin": "123456" -> "pin": "******"
	re := regexp.MustCompile(`(?i)"(pin|password|old_pin|new_pin|cvv|token|access_token|otp|secret)"\s*:\s*"[^"]*"`)
	masked := re.ReplaceAllStringFunc(rawJSON, func(match string) string {
		parts := strings.Split(match, ":")
		if len(parts) >= 2 {
			return fmt.Sprintf(`%s: "******"`, parts[0])
		}
		return match
	})

	// Also handle numeric values: "pin": 123456 -> "pin": "******"
	reNum := regexp.MustCompile(`(?i)"(pin|password|old_pin|new_pin|cvv|otp)"\s*:\s*\d+`)
	masked = reNum.ReplaceAllStringFunc(masked, func(match string) string {
		parts := strings.Split(match, ":")
		if len(parts) >= 2 {
			return fmt.Sprintf(`%s: "******"`, parts[0])
		}
		return match
	})

	return masked
}

func (l *Logger) log(level Level, msg string, fields map[string]interface{}) {
	entry := LogEntry{
		Timestamp: time.Now().Format("2006-01-02 15:04:05.000"),
		Level:     level,
		Message:   msg,
		Fields:    MaskSensitiveData(fields),
	}

	if l.env == "production" {
		bytes, err := json.Marshal(entry)
		if err == nil {
			fmt.Println(string(bytes))
			return
		}
	}

	// Development format
	fieldStr := ""
	if len(entry.Fields) > 0 {
		fBytes, _ := json.Marshal(entry.Fields)
		fieldStr = fmt.Sprintf(" | data=%s", string(fBytes))
	}
	log.Printf("[%s] %s: %s%s\n", entry.Level, entry.Timestamp, msg, fieldStr)
}

func (l *Logger) Info(msg string, fields ...map[string]interface{}) {
	var f map[string]interface{}
	if len(fields) > 0 {
		f = fields[0]
	}
	l.log(LevelInfo, msg, f)
}

func (l *Logger) Warn(msg string, fields ...map[string]interface{}) {
	var f map[string]interface{}
	if len(fields) > 0 {
		f = fields[0]
	}
	l.log(LevelWarn, msg, f)
}

func (l *Logger) Error(msg string, fields ...map[string]interface{}) {
	var f map[string]interface{}
	if len(fields) > 0 {
		f = fields[0]
	}
	l.log(LevelError, msg, f)
}

func (l *Logger) Fatal(msg string, fields ...map[string]interface{}) {
	var f map[string]interface{}
	if len(fields) > 0 {
		f = fields[0]
	}
	l.log(LevelError, msg, f)
	os.Exit(1)
}

