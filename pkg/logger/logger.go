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

// sensitiveKeyPattern matches any key that may carry credentials, secrets or
// personal data (audit DMB-011). Matching is by substring on the normalized key,
// so variants such as new_password, otp_code, refresh_token, fcm_token,
// nama_ibu_kandung or client_secret are all covered.
var sensitiveKeyPattern = regexp.MustCompile(`(?i)(pass|pin|otp|token|secret|session|authorization|cookie|cvv|card|pan|nik|ibu|mother|signature|key)`)

// IsSensitiveKey reports whether a field name must be masked in logs.
func IsSensitiveKey(k string) bool {
	return sensitiveKeyPattern.MatchString(k)
}

const maskValue = "******"

func maskValueRec(v interface{}) interface{} {
	switch t := v.(type) {
	case map[string]interface{}:
		return MaskSensitiveData(t)
	case []interface{}:
		out := make([]interface{}, len(t))
		for i := range t {
			out[i] = maskValueRec(t[i])
		}
		return out
	default:
		return v
	}
}

// MaskSensitiveData returns a copy of data with sensitive keys masked (recursive).
func MaskSensitiveData(data map[string]interface{}) map[string]interface{} {
	if data == nil {
		return nil
	}
	masked := make(map[string]interface{}, len(data))
	for k, v := range data {
		if IsSensitiveKey(k) {
			masked[k] = maskValue
			continue
		}
		masked[k] = maskValueRec(v)
	}
	return masked
}

// MaskJSONString parses a JSON document and masks sensitive keys. Anything that
// is not valid JSON is not logged at all (returns a placeholder).
func MaskJSONString(rawJSON string) string {
	if strings.TrimSpace(rawJSON) == "" {
		return ""
	}
	var v interface{}
	if err := json.Unmarshal([]byte(rawJSON), &v); err != nil {
		return "[non-json body omitted]"
	}
	out, err := json.Marshal(maskValueRec(v))
	if err != nil {
		return "[body omitted]"
	}
	return string(out)
}

// MaskQuery masks sensitive and identifying query parameters (account / CIF numbers).
func MaskQuery(rawQuery string) string {
	if rawQuery == "" {
		return ""
	}
	parts := strings.Split(rawQuery, "&")
	for i, p := range parts {
		kv := strings.SplitN(p, "=", 2)
		if len(kv) == 2 && (IsSensitiveKey(kv[0]) || strings.Contains(strings.ToLower(kv[0]), "account") || strings.Contains(strings.ToLower(kv[0]), "cif")) {
			parts[i] = kv[0] + "=" + maskValue
		}
	}
	return strings.Join(parts, "&")
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
