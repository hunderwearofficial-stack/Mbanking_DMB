package devicebind

import (
	"fmt"
	"strings"

	"mbanking-bpr/config"
)

func LoadOptions(cfg *config.Config) (Options, error) {
	opt := Options{Mode: cfg.DeviceBindingMode, AttestationMode: cfg.DeviceAttestationMode,
		OffReason: cfg.DeviceBindingOffReason, OffUntil: cfg.DeviceBindingOffUntil}
	if strings.ToLower(strings.TrimSpace(cfg.DeviceAttestationMode)) == AttestOff {
		return opt, nil
	}

	android := &AndroidAttestationConfig{
		PackageName:         strings.TrimSpace(cfg.AndroidPackageName),
		RequireVerifiedBoot: cfg.AndroidRequireVerifiedBoot,
	}
	if f := strings.TrimSpace(cfg.AndroidAttestationRootsFile); f != "" {
		pool, n, err := LoadCertPool(f)
		if err != nil {
			return opt, fmt.Errorf("DEVICE_ATTESTATION_ANDROID_ROOTS_FILE: %w", err)
		}
		android.Roots = pool
		_ = n
	}
	digests, err := ParseHexDigests(cfg.AndroidSigningCertSHA256)
	if err != nil {
		return opt, fmt.Errorf("DEVICE_ATTESTATION_ANDROID_CERT_SHA256: %w", err)
	}
	android.SigningCertSHA256 = digests
	if f := strings.TrimSpace(cfg.AndroidAttestationRevocationFile); f != "" {
		revoked, err := LoadRevocationList(f)
		if err != nil {
			return opt, fmt.Errorf("DEVICE_ATTESTATION_ANDROID_REVOCATION_FILE: %w", err)
		}
		android.Revoked, android.RevocationLoaded = revoked, true
	}
	opt.Android = android

	apple := &AppleAttestationConfig{AppID: strings.TrimSpace(cfg.AppleAppID), Environment: cfg.AppleAppAttestEnvironment}
	if apple.Environment == "" {
		apple.Environment = "production"
	}
	if f := strings.TrimSpace(cfg.AppleAppAttestRootFile); f != "" {
		pool, _, err := LoadCertPool(f)
		if err != nil {
			return opt, fmt.Errorf("DEVICE_ATTESTATION_APPLE_ROOT_FILE: %w", err)
		}
		apple.Roots = pool
	}
	opt.Apple = apple
	return opt, nil
}
