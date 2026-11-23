package service

import (
	"context"
	"errors"
	"strings"

	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/pkg/security"
)

const (
	ReasonDeviceKeyEnrolled = "DEVICE_KEY_ENROLLED"
	ReasonDeviceKeyRotated  = "DEVICE_KEY_ROTATED"
)

var ErrRefreshExpired = errors.New("sesi Anda telah berakhir, silakan login kembali")

func (s *authService) DeviceChallenge(ctx context.Context, req domain.DeviceChallengeRequest, client ClientInfo) (*domain.DeviceChallengeResponse, error) {
	if !s.binder.Active() {
		return nil, devicebind.ErrBindingDisabled
	}
	deviceID, err := validDevice(firstNonEmpty(req.DeviceID, client.DeviceID))
	if err != nil {
		return nil, err
	}
	purpose := strings.ToUpper(strings.TrimSpace(req.Purpose))
	spec := devicebind.ChallengeSpec{Purpose: purpose, DeviceID: deviceID, IP: client.IP}
	var userID string
	switch purpose {
	case devicebind.PurposeLogin:
		identifier := firstNonEmpty(req.PhoneNumber, req.CIF)
		if identifier == "" {
			return nil, ErrInvalidCredentials
		}
		user, ferr := s.repo.FindByIdentifier(ctx, normalizePhone(identifier))
		if ferr != nil || user == nil {
			user, _ = s.repo.FindByIdentifier(ctx, identifier)
		}
		if user != nil && user.PasswordHash != "" {
			userID = user.ID
		}
	case devicebind.PurposeRefresh:
		claims, verr := security.ValidateRefreshToken(strings.TrimSpace(req.RefreshToken), s.cfg.JWTSecret)
		if verr != nil {
			return nil, ErrRefreshExpired
		}
		if claims.DeviceID != deviceID {
			return nil, ErrDeviceBindingMismatch
		}
		userID = claims.UserID
	default:
		return nil, devicebind.ErrInvalidPurpose
	}
	key, kerr := s.binder.ActiveKey(ctx, userID) // also runs for decoys
	if kerr != nil {
		return nil, ErrServiceUnavailable
	}
	if userID != "" && key != nil && key.DeviceID == deviceID {
		spec.UserID, spec.KeyID = userID, key.ID
	}
	ch, err := s.binder.IssueChallenge(ctx, spec)
	if err != nil {
		return nil, ErrServiceUnavailable
	}
	return ch, nil
}

func (s *authService) SessionDeviceChallenge(ctx context.Context, userID string, req domain.DeviceChallengeRequest, client ClientInfo) (*domain.DeviceChallengeResponse, error) {
	if !s.binder.Active() {
		return nil, devicebind.ErrBindingDisabled
	}
	purpose := strings.ToUpper(strings.TrimSpace(req.Purpose))
	spec := devicebind.ChallengeSpec{Purpose: purpose, UserID: userID, DeviceID: client.DeviceID, IP: client.IP}
	fp := strings.ToLower(strings.TrimSpace(req.PublicKeySHA256))
	switch purpose {
	case devicebind.PurposeEnroll:
		if fp != "" {
			if !devicebind.ValidFingerprint(fp) {
				return nil, devicebind.ErrInvalidKey
			}
			spec.KeyFingerprint = fp
		}
	case devicebind.PurposeRotate, devicebind.PurposeChangePIN, devicebind.PurposeChangePassword:
		key, err := s.binder.ActiveKey(ctx, userID)
		if err != nil {
			return nil, ErrServiceUnavailable
		}
		if key == nil {
			return nil, devicebind.ErrNoActiveKey
		}
		spec.KeyID = key.ID
		if purpose == devicebind.PurposeRotate {
			if !devicebind.ValidFingerprint(fp) {
				return nil, devicebind.ErrInvalidKey
			}
			spec.KeyFingerprint = fp
		}
	default:
		return nil, devicebind.ErrInvalidPurpose
	}
	ch, err := s.binder.IssueChallenge(ctx, spec)
	if err != nil {
		return nil, ErrServiceUnavailable
	}
	return ch, nil
}

func (s *authService) EnrollDevice(ctx context.Context, userID string, req domain.EnrollDeviceRequest, client ClientInfo) (*domain.LoginResponse, error) {
	res, err := s.binder.Enroll(ctx, devicebind.EnrollInput{
		UserID: userID, SessionDeviceID: client.DeviceID, DeviceID: strings.TrimSpace(req.DeviceID),
		Platform: req.Platform, Format: req.AttestationFormat, PublicKey: req.PublicKey, SecurityLevel: req.SecurityLevel,
		AttestationChain: req.AttestationChain, AppAttestKeyID: req.AppAttestKeyID, AttestationObject: req.AttestationObject,
		Proof: devicebind.Proof{ChallengeID: req.ChallengeID, Signature: req.Signature},
	})
	if err != nil {
		return nil, err
	}
	return s.reissueForKey(ctx, userID, res.Key.DeviceID, client, ReasonDeviceKeyEnrolled,
		"Kunci Keamanan Perangkat Aktif",
		"Perangkat ini kini dilindungi kunci keamanan untuk login dan transaksi Mobile DMB. Jika Anda tidak melakukannya, segera hubungi CS Bank DMB.")
}

func (s *authService) RotateDeviceKey(ctx context.Context, userID string, req domain.RotateDeviceKeyRequest, client ClientInfo) (*domain.LoginResponse, error) {
	k, err := s.binder.Rotate(ctx, devicebind.RotateInput{
		UserID: userID, DeviceID: client.DeviceID, NewPublicKey: req.NewPublicKey, NewSecurityLevel: req.NewSecurityLevel,
		AttestationChain: req.AttestationChain,
		Proof:            devicebind.Proof{ChallengeID: req.ChallengeID, Signature: req.Signature}, NewKeySignature: req.NewKeySignature,
	})
	if err != nil {
		return nil, err
	}
	return s.reissueForKey(ctx, userID, k.DeviceID, client, ReasonDeviceKeyRotated,
		"Kunci Keamanan Perangkat Diperbarui",
		"Kunci keamanan perangkat Mobile DMB Anda telah diperbarui. Jika Anda tidak melakukannya, segera hubungi CS Bank DMB.")
}

func (s *authService) reissueForKey(ctx context.Context, userID, deviceID string, client ClientInfo, reason, title, body string) (*domain.LoginResponse, error) {
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil || user == nil {
		return nil, ErrServiceUnavailable
	}
	primary := s.resolvePrimaryAccount(ctx, user)
	resp, err := s.issueSession(ctx, user, primary, deviceID, client.IP, true, reason)
	if err != nil {
		return nil, err
	}
	notification.CreateAndPush(ctx, s.repo.DB(), userID, title, body, "SECURITY")
	return resp, nil
}

func (s *authService) DeviceStatus(ctx context.Context, userID string, client ClientInfo) domain.DeviceBindingStatus {
	if s.binder == nil {
		return domain.DeviceBindingStatus{Mode: devicebind.ModeOff, SessionDeviceID: client.DeviceID, Enrollment: "NOT_AVAILABLE"}
	}
	return s.binder.Status(ctx, userID, client.DeviceID)
}
