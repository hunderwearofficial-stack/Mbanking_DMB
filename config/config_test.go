package config

import (
	"os"
	"strings"
	"testing"
)

const (
	testSecretA = "test-only-customer-secret-0123456789abcdef"
	testSecretB = "test-only-admin-secret-fedcba9876543210zyx"
	testKey     = "0000000000000000000000000000000000000000000000000000000000000001"
)

// validEnv sets a complete, valid local configuration in the PROCESS environment and
// runs the test in an empty directory (no .env) unless the test writes one.
func validEnv(t *testing.T) {
	t.Helper()
	t.Chdir(t.TempDir())
	for k, v := range map[string]string{
		"APP_ENV": "local", "DB_HOST": "127.0.0.1", "DB_USER": "mbanking_app", "DB_NAME": "mbanking_local",
		"DB_SSL": "disable", "JWT_SECRET": testSecretA, "ADMIN_JWT_SECRET": testSecretB,
		"DB_ENCRYPTION_KEY": testKey, "ENABLE_MOCK_CBS": "true", "STANDALONE_CORE": "",
	} {
		t.Setenv(k, v)
	}
}

func writeDotEnv(t *testing.T, content string) {
	t.Helper()
	if err := os.WriteFile(LocalEnvFile, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestValidLocalConfig(t *testing.T) {
	validEnv(t)
	if err := LoadConfig().Validate(); err != nil {
		t.Fatalf("expected valid config, got %v", err)
	}
}

// A malformed value must fail startup instead of silently using a default.
func TestMalformedValuesAreErrors(t *testing.T) {
	for key, bad := range map[string]string{
		"APP_PORT": "abc", "JWT_EXPIRY_MINUTES": "9999", "DB_MAX_OPEN_CONNS": "0",
		"ENABLE_MOCK_CBS": "yes-please", "CBS_TIMEOUT_SEC": "-1", "DB_SSL": "sometimes", "APP_ENV": "prod",
	} {
		t.Run(key, func(t *testing.T) {
			validEnv(t)
			t.Setenv(key, bad)
			err := LoadConfig().Validate()
			if err == nil || !strings.Contains(err.Error(), key) {
				t.Fatalf("%s=%q must be rejected, got %v", key, bad, err)
			}
		})
	}
}

func TestMandatoryValuesHaveNoDefault(t *testing.T) {
	for _, key := range []string{"APP_ENV", "DB_HOST", "DB_USER", "DB_NAME", "DB_SSL", "JWT_SECRET", "ADMIN_JWT_SECRET", "DB_ENCRYPTION_KEY"} {
		t.Run(key, func(t *testing.T) {
			validEnv(t)
			t.Setenv(key, "")
			if err := LoadConfig().Validate(); err == nil || !strings.Contains(err.Error(), key) {
				t.Fatalf("missing %s must be rejected, got %v", key, err)
			}
		})
	}
}

func TestLiveCBSMustBeConfiguredUnlessMockSelected(t *testing.T) {
	validEnv(t)
	t.Setenv("ENABLE_MOCK_CBS", "false")
	err := LoadConfig().Validate()
	if err == nil || !strings.Contains(err.Error(), "CBS_BASE_URL") {
		t.Fatalf("empty CBS_BASE_URL without explicit mock mode must be rejected, got %v", err)
	}
}

func TestProductionLikeRequirements(t *testing.T) {
	for _, env := range []string{"staging", "production"} {
		t.Run(env, func(t *testing.T) {
			validEnv(t)
			t.Setenv("APP_ENV", env)
			err := LoadConfig().Validate()
			if err == nil {
				t.Fatal("mock CBS / no Redis / no DB_PASS must be rejected")
			}
			for _, want := range []string{"ENABLE_MOCK_CBS", "DB_PASS", "REDIS_HOST", "APP_VERSION"} {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("%s error must mention %s: %v", env, want, err)
				}
			}
		})
	}
}

// Owner decision (13-11-2026): STANDALONE_CORE must not activate in any environment.
func TestStandaloneCoreIsRefused(t *testing.T) {
	for _, env := range []string{"local", "development", "staging", "production"} {
		t.Run(env, func(t *testing.T) {
			validEnv(t)
			t.Setenv("APP_ENV", env)
			t.Setenv("STANDALONE_CORE", "true")
			err := LoadConfig().Validate()
			if err == nil || !strings.Contains(err.Error(), "STANDALONE_CORE tidak diizinkan") {
				t.Fatalf("STANDALONE_CORE must be refused in %s, got %v", env, err)
			}
		})
	}
	validEnv(t)
	if cfg := LoadConfig(); cfg.UseLiveCBS() || !cfg.EnableMockCBS {
		t.Fatal("ENABLE_MOCK_CBS must not be coupled to STANDALONE_CORE")
	}
}

// Local: `go run ./cmd/api` with only a .env file (APP_ENV=local inside it).
func TestDotEnvIsLoadedForLocal(t *testing.T) {
	validEnv(t)
	os.Unsetenv("APP_ENV")
	os.Unsetenv("DB_NAME")
	writeDotEnv(t, "APP_ENV=local\nDB_NAME=from_dotenv\n")
	cfg := LoadConfig()
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	if cfg.AppEnv != "local" || cfg.DBName != "from_dotenv" || cfg.EnvFile != ".env" {
		t.Fatalf("got env=%q db=%q file=%q", cfg.AppEnv, cfg.DBName, cfg.EnvFile)
	}
}

func TestProcessEnvironmentWinsOverDotEnv(t *testing.T) {
	validEnv(t)
	writeDotEnv(t, "APP_ENV=local\nDB_NAME=from_file\n")
	t.Setenv("DB_NAME", "from_process")
	if cfg := LoadConfig(); cfg.DBName != "from_process" {
		t.Fatalf("process env must win, got %q", cfg.DBName)
	}
}

// .env may only describe local: a server environment must never pick it up.
func TestDotEnvIsRefusedOutsideLocal(t *testing.T) {
	for _, env := range []string{"development", "staging", "production"} {
		t.Run(env, func(t *testing.T) {
			validEnv(t)
			t.Setenv("APP_ENV", env)
			writeDotEnv(t, "APP_ENV=local\nDB_PASS=local-only\n")
			err := LoadConfig().Validate()
			if err == nil || !strings.Contains(err.Error(), "HANYA untuk local") {
				t.Fatalf("%s must refuse a .env file, got %v", env, err)
			}
		})
	}
}

func TestDotEnvMustDeclareLocal(t *testing.T) {
	validEnv(t)
	os.Unsetenv("APP_ENV")
	writeDotEnv(t, "APP_ENV=development\n")
	if err := LoadConfig().Validate(); err == nil || !strings.Contains(err.Error(), "HANYA untuk local") {
		t.Fatalf(".env with a non-local APP_ENV must be refused, got %v", err)
	}
	t.Setenv("APP_ENV", "local")
	writeDotEnv(t, "APP_ENV=production\n")
	if err := LoadConfig().Validate(); err == nil || !strings.Contains(err.Error(), "APP_ENV=local") {
		t.Fatalf("mixed environment must be refused, got %v", err)
	}
}

func TestSecretsNeverPrinted(t *testing.T) {
	validEnv(t)
	t.Setenv("ADMIN_JWT_SECRET", testSecretA) // same as JWT_SECRET → error
	err := LoadConfig().Validate()
	if err == nil || strings.Contains(err.Error(), testSecretA) {
		t.Fatalf("error must not contain secret values: %v", err)
	}
}
