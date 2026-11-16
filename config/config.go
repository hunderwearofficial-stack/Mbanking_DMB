// Package config adalah SATU-SATUNYA tempat backend membaca konfigurasi.
//
// Sumber konfigurasi (sederhana dan eksplisit):
//
//	LOCAL (komputer developer)
//	  - Isi file `.env` di root repository (salin dari `.env.example`).
//	  - `.env` WAJIB berisi APP_ENV=local. File `.env` hanya boleh dipakai untuk local.
//	  - Nilai yang sudah ada di environment proses mengalahkan isi `.env`.
//
//	DEVELOPMENT / STAGING / PRODUCTION (server)
//	  - Semua nilai berasal dari environment server atau Secret Manager.
//	  - Tidak ada file yang dibaca. Bila ada file `.env` di working directory server,
//	    backend MENOLAK start (mencegah konfigurasi local terbawa ke server).
//
//	TEST (pengujian otomatis) — tidak membaca file apa pun.
//
// Aturan validasi:
//   - Tidak ada nilai default untuk secret atau konfigurasi wajib (database, JWT,
//     kunci enkripsi, CBS).
//   - Nilai yang ada tetapi formatnya salah adalah ERROR (tidak diganti default).
//   - Pengaturan opsional (port, umur token, timeout, ukuran pool) memiliki default
//     tertulis yang tetap diperiksa rentangnya.
//   - staging & production berlaku aturan ketat: CBS lokal ditolak, Redis wajib.
//   - Semua kesalahan dikumpulkan dan dilaporkan sekaligus; secret tidak pernah dicetak.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

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

// LocalEnvFile adalah file konfigurasi local (hanya untuk APP_ENV=local).
const LocalEnvFile = ".env"

var knownEnvs = map[string]bool{EnvLocal: true, EnvDevelopment: true, EnvStaging: true, EnvProduction: true, EnvTest: true}

// Config menampung seluruh konfigurasi runtime.
type Config struct {
	AppEnv     string
	EnvFile    string // file yang dimuat ("" = tidak ada) — hanya untuk diagnosis
	AppHost    string // alamat listen; kosong = semua interface (container / HP di LAN)
	AppPort    string
	AppName    string
	AppVersion string

	// Database (role aplikasi; migrasi memakai MIGRATION_DB_USER/PASS di cmd/migrate)
	DBHost         string
	DBPort         string
	DBUser         string
	DBPass         string
	DBName         string
	DBSSL          string
	DBMaxOpenConns int
	DBMaxIdleConns int

	// Redis (RedisHost kosong = memori proses, hanya local/development/test)
	RedisHost string
	RedisPort string
	RedisPass string
	RedisDB   int

	// Token nasabah (mobile)
	JWTSecret        string
	JWTExpiryMinutes int
	RefreshTokenDays int

	// Token petugas backoffice — kunci & audience terpisah (audit DMB-001)
	AdminJWTSecret        string
	AdminJWTExpiryMinutes int

	// Bootstrap SUPER_ADMIN sekali pakai (audit DMB-009)
	AdminBootstrapUsername string
	AdminBootstrapPassword string

	// Keamanan & enkripsi
	DBEncryptionKey         string   // kunci AES-256 aktif (64 hex atau base64 32 byte)
	DBEncryptionKeyPrevious string   // opsional: kunci lama, hanya dekripsi (rotasi)
	EnableMockCBS           bool     // ledger PostgreSQL lokal pengganti CBS (local/development/test saja)
	StandaloneCore          bool     // DITOLAK di semua environment — docs/SYSTEM_ARCHITECTURE.md
	TrustedProxies          []string // IP/CIDR reverse proxy yang boleh mengisi X-Forwarded-For
	CORSAllowedOrigins      []string // kosong = tanpa akses cross-origin
	AllowedBankCodes        []string // kode bank yang dianggap transfer internal (overbooking)

	// Core Banking System (CBS) OpenAPI
	CBSBaseURL      string
	CBSClientID     string
	CBSClientSecret string
	CBSTimeoutSec   int

	loadErrs []string
	envErrs  []string // kesalahan pemilihan environment / file .env (dilaporkan sendiri)
}

var validSSLModes = map[string]bool{"disable": true, "require": true, "verify-ca": true, "verify-full": true}

// envReader membaca variabel dan mencatat setiap nilai yang formatnya salah.
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

// secret membaca nilai apa adanya (tanpa trim) dan tidak pernah dicetak.
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

// resolveEnvironment menentukan APP_ENV dan memuat `.env` HANYA untuk local.
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
		if _, exists := os.LookupEnv(k); !exists { // environment proses menang
			_ = os.Setenv(k, v)
		}
	}
	return appEnv, LocalEnvFile
}

// LoadConfig menentukan environment, membaca nilai, dan mencatat kesalahan format.
// Pemanggil WAJIB memanggil Validate (server) atau ValidateDatabase (CLI).
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
		AllowedBankCodes:        r.list("INTERNAL_BANK_CODES"),

		CBSBaseURL:      r.str("CBS_BASE_URL", ""),
		CBSClientID:     r.str("CBS_CLIENT_ID", ""),
		CBSClientSecret: r.secret("CBS_CLIENT_SECRET"),
		CBSTimeoutSec:   r.int("CBS_TIMEOUT_SEC", 15, 1, 60),
	}
	if len(cfg.AllowedBankCodes) == 0 {
		// Kode bank internal untuk overbooking (konstanta bisnis, bukan secret).
		cfg.AllowedBankCodes = []string{"", "BPR", "DMB", "BPR_DMB", "000"}
	}
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
	}
	return c.wrap(errs)
}
