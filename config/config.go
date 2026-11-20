package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Nama environment.
const (
	EnvLocal       = "local"
	EnvDevelopment = "development"
	EnvStaging     = "staging"
	EnvProduction  = "production"
	EnvTest        = "test"
)

const LocalEnvFile = ".env"

var knownEnvs = map[string]bool{EnvLocal: true, EnvDevelopment: true, EnvStaging: true, EnvProduction: true, EnvTest: true}

type Config struct {
	AppEnv     string
	EnvFile    string // file yang dimuat ("" = tidak ada) — hanya untuk diagnosis
	AppHost    string // alamat listen; kosong = semua interface (container / HP di LAN)
	AppPort    string
	AppName    string
	AppVersion string

	DBHost         string
	DBPort         string
	DBUser         string
	DBPass         string
	DBName         string
	DBSSL          string
	DBMaxOpenConns int
	DBMaxIdleConns int

	RedisHost string
	RedisPort string
	RedisPass string
	RedisDB   int

	JWTSecret        string
	JWTExpiryMinutes int
	RefreshTokenDays int

	AdminJWTSecret        string
	AdminJWTExpiryMinutes int

	AdminBootstrapUsername string
	AdminBootstrapPassword string

	DBEncryptionKey         string   // kunci AES-256 aktif (64 hex atau base64 32 byte)
	DBEncryptionKeyPrevious string   // opsional: kunci lama, hanya dekripsi (rotasi)
	EnableMockCBS           bool     // ledger PostgreSQL lokal pengganti CBS (local/development/test saja)
	StandaloneCore          bool     // DITOLAK di semua environment — docs/SYSTEM_ARCHITECTURE.md
	TrustedProxies          []string // IP/CIDR reverse proxy yang boleh mengisi X-Forwarded-For
	CORSAllowedOrigins      []string // kosong = tanpa akses cross-origin

	DeviceBindingMode                string   // off | dual | enforced (DEVICE_BINDING_MODE)
	DeviceAttestationMode            string   // off | observe | enforce (DEVICE_ATTESTATION_MODE)
	AndroidAttestationRootsFile      string   // PEM root attestation Google
	AndroidAttestationRevocationFile string   // JSON daftar status attestation Google (opsional)
	AndroidPackageName               string   // applicationId resmi
	AndroidSigningCertSHA256         []string // SHA-256 sertifikat signing resmi (hex)
	AndroidRequireVerifiedBoot       bool     // tolak bootloader terbuka / boot tidak terverifikasi
	AppleAppAttestRootFile           string   // PEM Apple App Attestation Root CA
	AppleAppID                       string   // TeamID.bundleID resmi
	AppleAppAttestEnvironment        string   // production | development

	// SR-4: menonaktifkan proteksi (DEVICE_BINDING_MODE=off atau DEVICE_ATTESTATION_MODE=off)
	// di staging/production wajib beralasan dan berbatas waktu (maks. 72 jam).
	DeviceBindingOffReason string
	DeviceBindingOffUntil  time.Time

	deviceExplicit map[string]bool // variabel device binding yang diisi eksplisit

	CBSBaseURL      string
	CBSClientID     string
	CBSClientSecret string
	CBSTimeoutSec   int

	// OTP policy and the allowlist of OTP gateway hosts (an officer cannot redirect OTPs
	// to an arbitrary server from the backoffice; audit E-03).
	OTPTTLMinutes          int
	OTPMaxAttempts         int
	OTPGatewayAllowedHosts []string

	// Backoffice login hardening (audit E-01): TOTP MFA and per-account lockout.
	AdminMFARequired    bool
	AdminMaxFailedLogin int
	AdminLockoutMinutes int

	// RateLimitMultiplier relaxes every rate limit for local/development testing only.
	RateLimitMultiplier int
	// MaxJSONBodyBytes bounds non-multipart request bodies.
	MaxJSONBodyBytes int64

	loadErrs []string
	envErrs  []string // kesalahan pemilihan environment / file .env (dilaporkan sendiri)
}

var validSSLModes = map[string]bool{"disable": true, "require": true, "verify-ca": true, "verify-full": true}

type envReader struct{ errs []string }

func (r *envReader) fail(format string, args ...interface{}) {
	r.errs = append(r.errs, fmt.Sprintf(format, args...))
}

func (r *envReader) str(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func (r *envReader) required(key, hint string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		r.fail("%s wajib diisi (%s)", key, hint)
	}
	return v
}

func (r *envReader) secret(key string) string { return os.Getenv(key) }

func (r *envReader) int(key string, def, min, max int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < min || v > max {
		r.fail("%s tidak valid: harus bilangan bulat %d..%d", key, min, max)
		return def
	}
	return v
}

func (r *envReader) timestamp(key string) time.Time {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		r.fail("%s tidak valid: gunakan format RFC3339, mis. 2026-11-20T08:00:00+07:00", key)
		return time.Time{}
	}
	return t
}

func (r *envReader) bool(key string, def bool) bool {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		r.fail("%s tidak valid: gunakan true atau false", key)
		return def
	}
	return v
}

func (r *envReader) list(key string) []string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}

func resolveEnvironment(r *envReader) (appEnv, envFile string) {
	var fileVals map[string]string
	if _, err := os.Stat(LocalEnvFile); err == nil {
		vals, err := godotenv.Read(LocalEnvFile)
		if err != nil {
			r.fail("file %s tidak dapat dibaca: %v", LocalEnvFile, err)
		} else {
			fileVals = vals
		}
	}
	fileEnv := ""
	if fileVals != nil {
		fileEnv = strings.ToLower(strings.TrimSpace(fileVals["APP_ENV"]))
	}

	appEnv = strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	if appEnv == "" {
		appEnv = fileEnv
	}
	switch {
	case appEnv == "":
		r.fail("APP_ENV wajib diisi: untuk komputer sendiri isi APP_ENV=local di file .env (salin dari .env.example); di server set APP_ENV di environment server")
		return "", ""
	case !knownEnvs[appEnv]:
		r.fail("APP_ENV=%q tidak dikenal: gunakan local, development, staging, atau production", appEnv)
		return appEnv, ""
	}

	if fileVals == nil || appEnv == EnvTest {
		return appEnv, ""
	}
	if appEnv != EnvLocal {
		r.fail("file .env ditemukan tetapi APP_ENV=%s: file .env HANYA untuk local. Di server, berikan konfigurasi melalui environment server / Secret Manager dan hapus .env dari server. Untuk komputer sendiri isi APP_ENV=local di .env", appEnv)
		return appEnv, ""
	}
	if fileEnv != EnvLocal {
		r.fail("file .env harus berisi APP_ENV=local (ditemukan %q): .env hanya untuk komputer developer", fileEnv)
		return appEnv, LocalEnvFile
	}
	for k, v := range fileVals {
		if _, exists := os.LookupEnv(k); !exists {
			_ = os.Setenv(k, v)
		}
	}
	return appEnv, LocalEnvFile
}

func LoadConfig() *Config {
	r := &envReader{}
	appEnv, envFile := resolveEnvironment(r)
	envErrs := append([]string{}, r.errs...)

	cfg := &Config{
		AppEnv:     appEnv,
		EnvFile:    envFile,
		AppHost:    r.str("APP_HOST", ""),
		AppPort:    strconv.Itoa(r.int("APP_PORT", 8080, 1, 65535)),
		AppName:    r.str("APP_NAME", "MBanking-BPR-Backend"),
		AppVersion: r.str("APP_VERSION", "unversioned"),

		DBHost:         r.required("DB_HOST", "host PostgreSQL"),
		DBPort:         strconv.Itoa(r.int("DB_PORT", 5432, 1, 65535)),
		DBUser:         r.required("DB_USER", "role aplikasi PostgreSQL, mis. mbanking_app"),
		DBPass:         r.secret("DB_PASS"),
		DBName:         r.required("DB_NAME", "nama database"),
		DBSSL:          strings.ToLower(r.required("DB_SSL", "disable | require | verify-ca | verify-full")),
		DBMaxOpenConns: r.int("DB_MAX_OPEN_CONNS", 25, 1, 500),
		DBMaxIdleConns: r.int("DB_MAX_IDLE_CONNS", 10, 0, 500),

		RedisHost: r.str("REDIS_HOST", ""),
		RedisPort: strconv.Itoa(r.int("REDIS_PORT", 6379, 1, 65535)),
		RedisPass: r.secret("REDIS_PASS"),
		RedisDB:   r.int("REDIS_DB", 0, 0, 15),

		JWTSecret:        r.secret("JWT_SECRET"),
		JWTExpiryMinutes: r.int("JWT_EXPIRY_MINUTES", 15, 1, 60),
		RefreshTokenDays: r.int("REFRESH_TOKEN_DAYS", 7, 1, 30),

		AdminJWTSecret:        r.secret("ADMIN_JWT_SECRET"),
		AdminJWTExpiryMinutes: r.int("ADMIN_JWT_EXPIRY_MINUTES", 60, 1, 480),

		AdminBootstrapUsername: r.str("ADMIN_BOOTSTRAP_USERNAME", ""),
		AdminBootstrapPassword: r.secret("ADMIN_BOOTSTRAP_PASSWORD"),

		DBEncryptionKey:         r.secret("DB_ENCRYPTION_KEY"),
		DBEncryptionKeyPrevious: r.secret("DB_ENCRYPTION_KEY_PREVIOUS"),
		EnableMockCBS:           r.bool("ENABLE_MOCK_CBS", false),
		StandaloneCore:          r.bool("STANDALONE_CORE", false),
		TrustedProxies:          r.list("TRUSTED_PROXIES"),
		CORSAllowedOrigins:      r.list("CORS_ALLOWED_ORIGINS"),

		DeviceBindingMode:                strings.ToLower(r.str("DEVICE_BINDING_MODE", "dual")),
		DeviceAttestationMode:            strings.ToLower(r.str("DEVICE_ATTESTATION_MODE", "observe")),
		AndroidAttestationRootsFile:      r.str("DEVICE_ATTESTATION_ANDROID_ROOTS_FILE", ""),
		AndroidAttestationRevocationFile: r.str("DEVICE_ATTESTATION_ANDROID_REVOCATION_FILE", ""),
		AndroidPackageName:               r.str("DEVICE_ATTESTATION_ANDROID_PACKAGE", ""),
		AndroidSigningCertSHA256:         r.list("DEVICE_ATTESTATION_ANDROID_CERT_SHA256"),
		AndroidRequireVerifiedBoot:       r.bool("DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT", true),
		AppleAppAttestRootFile:           r.str("DEVICE_ATTESTATION_APPLE_ROOT_FILE", ""),
		AppleAppID:                       r.str("DEVICE_ATTESTATION_APPLE_APP_ID", ""),
		AppleAppAttestEnvironment:        strings.ToLower(r.str("DEVICE_ATTESTATION_APPLE_ENVIRONMENT", "production")),
		DeviceBindingOffReason:           r.str("DEVICE_BINDING_OFF_REASON", ""),
		DeviceBindingOffUntil:            r.timestamp("DEVICE_BINDING_OFF_UNTIL"),
		deviceExplicit:                   explicitVars(deviceSecurityVars),

		CBSBaseURL:      r.str("CBS_BASE_URL", ""),
		CBSClientID:     r.str("CBS_CLIENT_ID", ""),
		CBSClientSecret: r.secret("CBS_CLIENT_SECRET"),
		CBSTimeoutSec:   r.int("CBS_TIMEOUT_SEC", 15, 1, 60),

		OTPTTLMinutes:          r.int("OTP_TTL_MINUTES", 3, 1, 10),
		OTPMaxAttempts:         r.int("OTP_MAX_ATTEMPTS", 5, 3, 10),
		OTPGatewayAllowedHosts: lowerAll(r.list("OTP_GATEWAY_ALLOWED_HOSTS")),
		AdminMaxFailedLogin:    r.int("ADMIN_MAX_FAILED_LOGIN", 5, 3, 10),
		AdminLockoutMinutes:    r.int("ADMIN_LOCKOUT_MINUTES", 15, 5, 1440),
		MaxJSONBodyBytes:       int64(r.int("MAX_JSON_BODY_BYTES", 1<<20, 16<<10, 8<<20)),
	}
	// Defaults follow the environment; staging/production cannot weaken them (Validate).
	prodLike := appEnv == EnvProduction || appEnv == EnvStaging
	cfg.AdminMFARequired = r.bool("ADMIN_MFA_REQUIRED", prodLike)
	defMultiplier := 1
	if appEnv == EnvLocal || appEnv == EnvDevelopment {
		defMultiplier = 50
	}
	cfg.RateLimitMultiplier = r.int("RATE_LIMIT_MULTIPLIER", defMultiplier, 1, 100)
	cfg.loadErrs = r.errs
	cfg.envErrs = envErrs
	return cfg
}

// IsProduction: berjalan di production.
func (c *Config) IsProduction() bool { return c.AppEnv == EnvProduction }

// IsProductionLike: staging atau production (aturan keamanan yang sama).
func (c *Config) IsProductionLike() bool {
	return c.AppEnv == EnvProduction || c.AppEnv == EnvStaging
}

// UseLiveCBS: provider CBS OpenAPI live yang dipakai.
func (c *Config) UseLiveCBS() bool { return !c.EnableMockCBS && c.CBSBaseURL != "" }

// UseInMemoryRedis: Redis sengaja tidak dikonfigurasi (local/development/test saja).
func (c *Config) UseInMemoryRedis() bool { return c.RedisHost == "" }

func (c *Config) databaseErrors() []string {
	if len(c.envErrs) > 0 {
		// Environment tidak dapat ditentukan: kesalahan nilai lain hanyalah akibatnya.
		return append([]string{}, c.envErrs...)
	}
	errs := append([]string{}, c.loadErrs...)
	if c.DBSSL != "" && !validSSLModes[c.DBSSL] {
		errs = append(errs, "DB_SSL harus salah satu dari disable, require, verify-ca, verify-full")
	}
	if c.DBMaxIdleConns > c.DBMaxOpenConns {
		errs = append(errs, "DB_MAX_IDLE_CONNS tidak boleh melebihi DB_MAX_OPEN_CONNS")
	}
	if strings.TrimSpace(c.DBEncryptionKey) == "" {
		errs = append(errs, "DB_ENCRYPTION_KEY wajib diisi (32 byte: 64 karakter hex atau base64)")
	}
	return errs
}

func (c *Config) wrap(errs []string) error {
	if len(errs) == 0 {
		return nil
	}
	src := "environment proses"
	if c.EnvFile != "" {
		src = "environment proses + " + c.EnvFile
	}
	return fmt.Errorf("konfigurasi tidak valid (APP_ENV=%s, sumber: %s):\n  - %s", c.AppEnv, src, strings.Join(errs, "\n  - "))
}

// ValidateDatabase memvalidasi kebutuhan CLI operasional (migrate, rekey, auditverify):
// environment, koneksi database, dan kunci enkripsi.
func (c *Config) ValidateDatabase() error { return c.wrap(c.databaseErrors()) }

// Validate memvalidasi konfigurasi lengkap untuk menjalankan API server.
// Nilai secret tidak pernah dicetak.
func (c *Config) Validate() error {
	errs := c.databaseErrors()
	if len(c.envErrs) > 0 {
		return c.wrap(errs)
	}

	if len(c.JWTSecret) < 32 {
		errs = append(errs, "JWT_SECRET wajib diisi (minimal 32 karakter acak)")
	}
	if len(c.AdminJWTSecret) < 32 {
		errs = append(errs, "ADMIN_JWT_SECRET wajib diisi (minimal 32 karakter acak)")
	}
	if c.JWTSecret != "" && c.JWTSecret == c.AdminJWTSecret {
		errs = append(errs, "ADMIN_JWT_SECRET tidak boleh sama dengan JWT_SECRET")
	}
	if c.AdminBootstrapUsername != "" || c.AdminBootstrapPassword != "" {
		if c.AdminBootstrapUsername == "" || len(c.AdminBootstrapPassword) < 12 {
			errs = append(errs, "ADMIN_BOOTSTRAP_USERNAME dan ADMIN_BOOTSTRAP_PASSWORD (minimal 12 karakter) harus diisi bersamaan")
		}
	}
	errs = append(errs, c.deviceBindingErrors()...)
	if c.StandaloneCore {
		errs = append(errs, "STANDALONE_CORE tidak diizinkan: ledger lokal bukan core banking dan tidak boleh menggantikan CBS (lihat docs/SYSTEM_ARCHITECTURE.md). Untuk pengujian lokal gunakan ENABLE_MOCK_CBS=true dengan APP_ENV=local")
	}
	if !c.EnableMockCBS {
		if c.CBSBaseURL == "" {
			errs = append(errs, "CBS_BASE_URL wajib diisi (atau ENABLE_MOCK_CBS=true khusus local/development)")
		} else if !strings.HasPrefix(strings.ToLower(c.CBSBaseURL), "https://") {
			errs = append(errs, "CBS_BASE_URL wajib menggunakan https://")
		}
		if c.CBSClientID == "" || c.CBSClientSecret == "" {
			errs = append(errs, "CBS_CLIENT_ID dan CBS_CLIENT_SECRET wajib diisi")
		}
	}
	if c.IsProductionLike() {
		if c.EnableMockCBS {
			errs = append(errs, "ENABLE_MOCK_CBS tidak boleh aktif di "+c.AppEnv)
		}
		if c.DBPass == "" {
			errs = append(errs, "DB_PASS wajib diisi di "+c.AppEnv)
		}
		if c.RedisHost == "" || c.RedisPass == "" {
			errs = append(errs, "REDIS_HOST dan REDIS_PASS wajib diisi di "+c.AppEnv+" (OTP & rate limit lintas instance)")
		}
		if c.AppVersion == "unversioned" {
			errs = append(errs, "APP_VERSION wajib diisi di "+c.AppEnv+" (jejak audit rilis)")
		}
		if !c.AdminMFARequired {
			errs = append(errs, "ADMIN_MFA_REQUIRED tidak boleh false di "+c.AppEnv+" (login backoffice wajib MFA)")
		}
		if c.RateLimitMultiplier != 1 {
			errs = append(errs, "RATE_LIMIT_MULTIPLIER harus 1 di "+c.AppEnv)
		}
	}
	if c.IsProduction() && len(c.OTPGatewayAllowedHosts) == 0 {
		errs = append(errs, "OTP_GATEWAY_ALLOWED_HOSTS wajib diisi di production (host gateway OTP resmi)")
	}
	for _, h := range c.OTPGatewayAllowedHosts {
		if strings.ContainsAny(h, "/:@ ") {
			errs = append(errs, "OTP_GATEWAY_ALLOWED_HOSTS hanya berisi nama host (tanpa skema, port, atau path)")
			break
		}
	}
	return c.wrap(errs)
}

func lowerAll(in []string) []string {
	for i := range in {
		in[i] = strings.ToLower(in[i])
	}
	return in
}

// OTPGatewayHostAllowed reports whether an OTP gateway URL host is allowlisted. An empty
// allowlist (non-production only) allows any https host.
func (c *Config) OTPGatewayHostAllowed(host string) bool {
	if len(c.OTPGatewayAllowedHosts) == 0 {
		return !c.IsProduction()
	}
	host = strings.ToLower(strings.TrimSpace(host))
	for _, h := range c.OTPGatewayAllowedHosts {
		if host == h {
			return true
		}
	}
	return false
}

// deviceSecurityVars wajib diisi eksplisit di staging/production (DB-M2): keamanan
// device binding tidak boleh bergantung pada nilai default yang diam-diam aktif.
var deviceSecurityVars = []string{"DEVICE_BINDING_MODE", "DEVICE_ATTESTATION_MODE", "DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT"}

func explicitVars(keys []string) map[string]bool {
	out := map[string]bool{}
	for _, k := range keys {
		out[k] = strings.TrimSpace(os.Getenv(k)) != ""
	}
	return out
}

func (c *Config) deviceBindingErrors() []string {
	var errs []string
	switch c.DeviceBindingMode {
	case "", "off", "dual", "enforced":
	default:
		errs = append(errs, "DEVICE_BINDING_MODE harus off | dual | enforced")
	}
	switch c.DeviceAttestationMode {
	case "", "off", "observe", "enforce":
	default:
		errs = append(errs, "DEVICE_ATTESTATION_MODE harus off | observe | enforce")
	}
	switch c.AppleAppAttestEnvironment {
	case "", "production", "development":
	default:
		errs = append(errs, "DEVICE_ATTESTATION_APPLE_ENVIRONMENT harus production | development")
	}
	if !c.IsProductionLike() {
		return errs
	}
	if c.DeviceBindingMode == "off" || c.DeviceAttestationMode == "off" {
		if len(strings.TrimSpace(c.DeviceBindingOffReason)) < 10 {
			errs = append(errs, "DEVICE_BINDING_OFF_REASON wajib diisi (min. 10 karakter, mis. nomor tiket insiden) bila proteksi perangkat dimatikan di "+c.AppEnv)
		}
		switch now := time.Now(); {
		case c.DeviceBindingOffUntil.IsZero():
			errs = append(errs, "DEVICE_BINDING_OFF_UNTIL wajib diisi (RFC3339) bila proteksi perangkat dimatikan di "+c.AppEnv)
		case !c.DeviceBindingOffUntil.After(now):
			errs = append(errs, "DEVICE_BINDING_OFF_UNTIL sudah lewat: proteksi perangkat tidak boleh dimatikan lagi tanpa batas baru")
		case c.DeviceBindingOffUntil.After(now.Add(72 * time.Hour)):
			errs = append(errs, "DEVICE_BINDING_OFF_UNTIL maksimal 72 jam dari sekarang")
		}
	}
	// Stolen access tokens: keep their lifetime short in production (refresh is signed).
	if c.JWTExpiryMinutes > 10 {
		errs = append(errs, "JWT_EXPIRY_MINUTES maksimal 10 di "+c.AppEnv+" (masa pakai token akses yang dicuri dibatasi)")
	}
	for _, k := range deviceSecurityVars {
		if !c.deviceExplicit[k] {
			errs = append(errs, k+" wajib diisi eksplisit di "+c.AppEnv+" (tidak ada nilai default keamanan)")
		}
	}
	if c.DeviceAttestationMode != "off" {
		need := map[string]string{
			"DEVICE_ATTESTATION_ANDROID_ROOTS_FILE": c.AndroidAttestationRootsFile,
			"DEVICE_ATTESTATION_ANDROID_PACKAGE":    c.AndroidPackageName,
			"DEVICE_ATTESTATION_APPLE_ROOT_FILE":    c.AppleAppAttestRootFile,
			"DEVICE_ATTESTATION_APPLE_APP_ID":       c.AppleAppID,
		}
		for _, k := range []string{"DEVICE_ATTESTATION_ANDROID_ROOTS_FILE", "DEVICE_ATTESTATION_ANDROID_PACKAGE", "DEVICE_ATTESTATION_APPLE_ROOT_FILE", "DEVICE_ATTESTATION_APPLE_APP_ID"} {
			if strings.TrimSpace(need[k]) == "" {
				errs = append(errs, k+" wajib diisi bila DEVICE_ATTESTATION_MODE bukan off")
			}
		}
		if len(c.AndroidSigningCertSHA256) == 0 {
			errs = append(errs, "DEVICE_ATTESTATION_ANDROID_CERT_SHA256 wajib diisi bila DEVICE_ATTESTATION_MODE bukan off")
		}
		if strings.HasPrefix(c.AndroidPackageName, "com.example") || strings.HasPrefix(c.AppleAppID, "com.example") || strings.Contains(c.AppleAppID, ".com.example.") {
			errs = append(errs, "identitas aplikasi template (com.example) tidak boleh dipakai untuk attestation di "+c.AppEnv)
		}
		if c.AppleAppAttestEnvironment != "production" {
			errs = append(errs, "DEVICE_ATTESTATION_APPLE_ENVIRONMENT harus production di "+c.AppEnv)
		}
	}
	return errs
}
