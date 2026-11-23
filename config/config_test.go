package config

import (
	"os"
	"strings"
	"testing"
	"time"
)

const (
	testSecretA = "test-only-customer-secret-0123456789abcdef"
	testSecretB = "test-only-admin-secret-fedcba9876543210zyx"
	testKey     = "0000000000000000000000000000000000000000000000000000000000000001"
)

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
	t.Setenv("ADMIN_JWT_SECRET", testSecretA)
	err := LoadConfig().Validate()
	if err == nil || strings.Contains(err.Error(), testSecretA) {
		t.Fatalf("error must not contain secret values: %v", err)
	}
}

func TestDeviceBindingProductionConfig(t *testing.T) {
	for _, env := range []string{"staging", "production"} {
		t.Run(env, func(t *testing.T) {
			validEnv(t)
			t.Setenv("APP_ENV", env)
			err := LoadConfig().Validate()
			if err == nil {
				t.Fatal("expected errors")
			}
			for _, want := range []string{"DEVICE_BINDING_MODE wajib diisi eksplisit", "DEVICE_ATTESTATION_MODE wajib diisi eksplisit",
				"DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT wajib diisi eksplisit",
				"DEVICE_ATTESTATION_ANDROID_ROOTS_FILE", "DEVICE_ATTESTATION_APPLE_APP_ID", "DEVICE_ATTESTATION_ANDROID_CERT_SHA256"} {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("must mention %q: %v", want, err)
				}
			}

			t.Setenv("DEVICE_BINDING_MODE", "enforced")
			t.Setenv("DEVICE_ATTESTATION_MODE", "enforce")
			t.Setenv("DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT", "true")
			t.Setenv("DEVICE_ATTESTATION_ANDROID_PACKAGE", "com.example.m_banking_bpr")
			t.Setenv("DEVICE_ATTESTATION_APPLE_APP_ID", "TEAM.com.example.mBankingBpr")
			t.Setenv("DEVICE_ATTESTATION_APPLE_ENVIRONMENT", "development")
			err = LoadConfig().Validate()
			for _, want := range []string{"com.example", "production di"} {
				if err == nil || !strings.Contains(err.Error(), want) {
					t.Errorf("must refuse %q: %v", want, err)
				}
			}
			if strings.Contains(err.Error(), "wajib diisi eksplisit") {
				t.Errorf("explicit values must be accepted: %v", err)
			}
		})
	}
}

func TestDeviceBindingValuesAreValidated(t *testing.T) {
	for key, bad := range map[string]string{"DEVICE_BINDING_MODE": "strict", "DEVICE_ATTESTATION_MODE": "on",
		"DEVICE_ATTESTATION_APPLE_ENVIRONMENT": "sandbox", "DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT": "maybe"} {
		t.Run(key, func(t *testing.T) {
			validEnv(t)
			t.Setenv(key, bad)
			if err := LoadConfig().Validate(); err == nil || !strings.Contains(err.Error(), key) {
				t.Fatalf("invalid %s must be rejected: %v", key, err)
			}
		})
	}
	validEnv(t)
	c := LoadConfig()
	if err := c.Validate(); err != nil || c.DeviceBindingMode != "dual" || c.DeviceAttestationMode != "observe" || !c.AndroidRequireVerifiedBoot {
		t.Fatalf("local defaults: %v %+v", err, c)
	}
}

// SR-4: switching device protection off in staging/production needs a reason and a
// deadline of at most 72 hours.
func TestDeviceProtectionOffIsTimeBoxed(t *testing.T) {
	prod := func(t *testing.T) {
		validEnv(t)
		t.Setenv("APP_ENV", "production")
		t.Setenv("DEVICE_BINDING_MODE", "off")
		t.Setenv("DEVICE_ATTESTATION_MODE", "enforce")
		t.Setenv("DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT", "true")
	}
	cases := map[string]struct{ reason, until, want string }{
		"no reason":     {"", time.Now().Add(time.Hour).Format(time.RFC3339), "DEVICE_BINDING_OFF_REASON"},
		"no deadline":   {"INC-2026-001 rollback", "", "DEVICE_BINDING_OFF_UNTIL wajib"},
		"past deadline": {"INC-2026-001 rollback", time.Now().Add(-time.Hour).Format(time.RFC3339), "sudah lewat"},
		"too long":      {"INC-2026-001 rollback", time.Now().Add(100 * time.Hour).Format(time.RFC3339), "maksimal 72 jam"},
		"bad format":    {"INC-2026-001 rollback", "besok", "RFC3339"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			prod(t)
			t.Setenv("DEVICE_BINDING_OFF_REASON", c.reason)
			t.Setenv("DEVICE_BINDING_OFF_UNTIL", c.until)
			err := LoadConfig().Validate()
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("expected %q, got %v", c.want, err)
			}
		})
	}
	t.Run("valid time-boxed switch", func(t *testing.T) {
		prod(t)
		t.Setenv("DEVICE_BINDING_OFF_REASON", "INC-2026-001 rollback")
		t.Setenv("DEVICE_BINDING_OFF_UNTIL", time.Now().Add(24*time.Hour).Format(time.RFC3339))
		err := LoadConfig().Validate()
		if err != nil && strings.Contains(err.Error(), "DEVICE_BINDING_OFF") {
			t.Fatalf("valid switch refused: %v", err)
		}
	})
}
