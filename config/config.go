package config

import (
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	AppEnv     string
	AppPort    string
	AppName    string
	AppVersion string

	// Database
	DBHost string
	DBPort string
	DBUser string
	DBPass string
	DBName string
	DBSSL  string

	// Redis
	RedisHost string
	RedisPort string
	RedisPass string
	RedisDB   int

	// JWT
	JWTSecret        string
	JWTExpiryMinutes int

	// Security & Rate Limit
	RateLimitMax    int // Max requests
	RateLimitWindow int // in seconds
	EnableMockCBS   bool

	// Core Banking System (CBS) OpenAPI Configuration
	CBSBaseURL      string
	CBSClientID     string
	CBSClientSecret string
	CBSTimeoutSec   int
}

func LoadConfig() *Config {
	// Load .env if exists (ignore error if file not present)
	_ = godotenv.Load()

	return &Config{
		AppEnv:           getEnv("APP_ENV", "development"),
		AppPort:          getEnv("APP_PORT", "8080"),
		AppName:          getEnv("APP_NAME", "MBanking-BPR-Backend"),
		AppVersion:       getEnv("APP_VERSION", "v1.0.0"),
		DBHost:           getEnv("DB_HOST", "localhost"),
		DBPort:           getEnv("DB_PORT", "5432"),
		DBUser:           getEnv("DB_USER", "postgres"),
		DBPass:           getEnv("DB_PASS", "postgres"),
		DBName:           getEnv("DB_NAME", "mbanking_bpr"),
		DBSSL:            getEnv("DB_SSL", "disable"),
		RedisHost:        getEnv("REDIS_HOST", "localhost"),
		RedisPort:        getEnv("REDIS_PORT", "6379"),
		RedisPass:        getEnv("REDIS_PASS", ""),
		RedisDB:          getEnvAsInt("REDIS_DB", 0),
		JWTSecret:        getEnv("JWT_SECRET", "super-secret-bpr-jwt-key-2026!"),
		JWTExpiryMinutes: getEnvAsInt("JWT_EXPIRY_MINUTES", 60),
		RateLimitMax:     getEnvAsInt("RATE_LIMIT_MAX", 10),
		RateLimitWindow:  getEnvAsInt("RATE_LIMIT_WINDOW_SEC", 60),
		EnableMockCBS:    getEnvAsBool("ENABLE_MOCK_CBS", false),
		CBSBaseURL:       getEnv("CBS_BASE_URL", "https://cbs-openapi-dev.bprdmb.id"),
		CBSClientID:      getEnv("CBS_CLIENT_ID", "DEMO-CLIENT-001"),
		CBSClientSecret:  getEnv("CBS_CLIENT_SECRET", "s3cr3tK3yD3m0BNI2024#!"),
		CBSTimeoutSec:    getEnvAsInt("CBS_TIMEOUT_SEC", 15),
	}
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvAsInt(key string, defaultVal int) int {
	valStr := os.Getenv(key)
	if valStr == "" {
		return defaultVal
	}
	val, err := strconv.Atoi(valStr)
	if err != nil {
		return defaultVal
	}
	return val
}

func getEnvAsBool(key string, defaultVal bool) bool {
	valStr := os.Getenv(key)
	if valStr == "" {
		return defaultVal
	}
	val, err := strconv.ParseBool(valStr)
	if err != nil {
		return defaultVal
	}
	return val
}

