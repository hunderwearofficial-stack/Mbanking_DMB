package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/auth/repository"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/internal/session"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/security"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

var (
	ErrDeviceBindingMismatch = errors.New("perangkat tidak sesuai dengan perangkat terdaftar untuk akun ini")
	ErrUserInactive          = errors.New("akun nasabah tidak aktif atau diblokir")
	ErrInvalidCredentials    = errors.New("nomor handphone atau password salah")
	ErrDeviceIDRequired      = errors.New("identitas perangkat tidak ditemukan. Silakan muat ulang aplikasi")
	ErrAccountNotMatch       = errors.New("data nasabah tidak dapat diverifikasi")
	ErrSessionNotFound       = otp.ErrSessionNotFound
	ErrOTPInvalid            = otp.ErrInvalidCode
	ErrOTPNotVerified        = otp.ErrNotVerified
	ErrPasswordTooShort      = security.ErrWeakPassword
	ErrPINInvalidLength      = errors.New("PIN transaksi harus tepat 6 digit angka")
	// SR-7: one generic answer for every login outcome from an unbound device (and for
	// unknown accounts): it neither confirms the account nor the password, and it does not
	// wrongly claim a "new device" to a customer who mistyped the number.
	ErrNewDeviceVerification = errors.New("login tidak dapat diproses. Periksa kembali nomor handphone dan password Anda. Bila Anda memakai perangkat baru atau baru memasang ulang aplikasi, verifikasi perangkat melalui menu Lupa Password (kode OTP dikirim ke nomor handphone terdaftar)")
	ErrDefaultCredential     = errors.New("password Anda adalah password bawaan yang tidak aman dan telah dinonaktifkan. Silakan atur ulang melalui menu Lupa Password")
	ErrSessionBusy           = session.ErrConcurrentRefresh
	ErrServiceUnavailable    = errors.New("layanan sedang tidak tersedia, silakan coba beberapa saat lagi")
)

type ClientInfo struct {
	DeviceID  string
	IP        string
	SessionID string
	UserAgent string
}

type AuthService interface {
	Login(ctx context.Context, req domain.LoginRequest, client ClientInfo) (*domain.LoginResponse, error)
	RefreshToken(ctx context.Context, req domain.RefreshTokenRequest, client ClientInfo) (*domain.LoginResponse, error)
	Logout(ctx context.Context, userID string, client ClientInfo) error
	VerifyActivation(ctx context.Context, req domain.ActivateVerifyRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error)
	VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error)
	CompleteActivation(ctx context.Context, req domain.ActivateSetupRequest, client ClientInfo) (*domain.LoginResponse, error)
	RequestForgotPassword(ctx context.Context, req domain.ForgotPasswordRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error)
	VerifyForgotPasswordOTP(ctx context.Context, req domain.ForgotPasswordVerifyOTPRequest, client ClientInfo) error
	ResetForgotPassword(ctx context.Context, req domain.ForgotPasswordResetRequest, client ClientInfo) error
	ChangePassword(ctx context.Context, userID string, req domain.ChangePasswordRequest, client ClientInfo) error
	ChangePIN(ctx context.Context, userID string, req domain.ChangePINRequest, client ClientInfo) error
	RevealProfile(ctx context.Context, userID, pin string, client ClientInfo) (*domain.CBSNasabahData, error)

	DeviceChallenge(ctx context.Context, req domain.DeviceChallengeRequest, client ClientInfo) (*domain.DeviceChallengeResponse, error)
	SessionDeviceChallenge(ctx context.Context, userID string, req domain.DeviceChallengeRequest, client ClientInfo) (*domain.DeviceChallengeResponse, error)
	EnrollDevice(ctx context.Context, userID string, req domain.EnrollDeviceRequest, client ClientInfo) (*domain.LoginResponse, error)
	RotateDeviceKey(ctx context.Context, userID string, req domain.RotateDeviceKeyRequest, client ClientInfo) (*domain.LoginResponse, error)
	DeviceStatus(ctx context.Context, userID string, client ClientInfo) domain.DeviceBindingStatus
}

type ConsentGate interface {
	EnsureUserConsent(ctx context.Context, userID, deviceID, acceptanceID, channel string, meta legaldoc.ClientMeta) error
	ValidatePreLogin(ctx context.Context, deviceID, acceptanceID string) error
	RequireUserConsent(ctx context.Context, userID string) error
}

type authService struct {
	cfg       *config.Config
	consent   ConsentGate
	repo      repository.AuthRepository
	cbsProv   cbsprovider.CBSProvider
	otpStore  *otp.Store
	sessions  *session.Manager
	binder    *devicebind.Service
	dummyHash string // equalizes timing for unknown identifiers
}

func NewAuthService(cfg *config.Config, repo repository.AuthRepository, cbsProv cbsprovider.CBSProvider, otpStore *otp.Store, sessions *session.Manager, consent ConsentGate, binder *devicebind.Service) AuthService {
	dummy, _ := security.HashPassword(uuid.NewString())
	return &authService{cfg: cfg, consent: consent, repo: repo, cbsProv: cbsProv, otpStore: otpStore, sessions: sessions, binder: binder, dummyHash: dummy}
}

func maskPhoneNumber(phone string) string {
	if len(phone) < 8 {
		return "****"
	}
	return fmt.Sprintf("%s****%s", phone[:4], phone[len(phone)-4:])
}

func normalizePhone(p string) string {
	p = strings.TrimSpace(p)
	p = strings.ReplaceAll(p, "-", "")
	p = strings.ReplaceAll(p, " ", "")
	if strings.HasPrefix(p, "+62") {
		return "0" + p[3:]
	}
	if strings.HasPrefix(p, "62") {
		return "0" + p[2:]
	}
	return p
}

func validDevice(id string) (string, error) {
	id = strings.TrimSpace(id)
	if len(id) < 6 || len(id) > 128 {
		return "", ErrDeviceIDRequired
	}
	for _, r := range id {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("._:-", r)) {
			return "", ErrDeviceIDRequired
		}
	}
	return id, nil
}

func (s *authService) accessTTL() time.Duration {
	return time.Duration(s.cfg.JWTExpiryMinutes) * time.Minute
}

func (s *authService) refreshTTL() time.Duration {
	return time.Duration(s.cfg.RefreshTokenDays) * 24 * time.Hour
}

func profile(user *model.User, primaryAccount, deviceID string) domain.UserProfile {
	return domain.UserProfile{
		ID:             user.ID,
		CIF:            user.CIF,
		FullName:       user.FullName,
		Username:       user.Username,
		PhoneNumber:    user.PhoneNumber,
		Email:          string(user.Email),
		KodePos:        user.KodePos,
		JenisKelamin:   user.JenisKelamin,
		Agama:          user.Agama,
		TglLahir:       string(user.TglLahir),
		TempatLahir:    string(user.TempatLahir),
		DeviceID:       deviceID,
		PrimaryAccount: primaryAccount,
		IsActive:       user.IsActive,
		CreatedAt:      user.CreatedAt,
	}
}

func (s *authService) issueSession(ctx context.Context, user *model.User, primaryAccount, deviceID, ip string, exclusive bool, reason string) (*domain.LoginResponse, error) {
	sid := uuid.NewString()
	keyID, err := s.activeKeyID(ctx, user.ID)
	if errors.Is(err, devicebind.ErrAttestationRequired) {
		return nil, err
	}
	if err != nil {
		return nil, ErrServiceUnavailable
	}
	tokens, err := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: user.ID, CIF: user.CIF, PhoneNumber: user.PhoneNumber, AccountNo: primaryAccount,
		DeviceID: deviceID, DeviceKeyID: keyID, SessionID: sid,
	}, s.cfg.JWTSecret, s.accessTTL(), s.refreshTTL())
	if err != nil {
		return nil, err
	}
	if err := s.sessions.Create(ctx, sid, user.ID, deviceID, ip, tokens.RefreshTokenID, tokens.RefreshExpiry); err != nil {
		logger.GetLogger().Error("Gagal membuat sesi nasabah", map[string]interface{}{"error": err.Error()})
		return nil, ErrServiceUnavailable
	}
	if exclusive {
		if err := s.sessions.RevokeAllForUser(ctx, user.ID, reason, sid); err != nil {
			logger.GetLogger().Error("Gagal mencabut sesi lama", map[string]interface{}{"error": err.Error()})
		}
	}
	return &domain.LoginResponse{
		AccessToken:   tokens.AccessToken,
		RefreshToken:  tokens.RefreshToken,
		TokenType:     "Bearer",
		ExpiresIn:     int(s.accessTTL().Seconds()),
		User:          profile(user, primaryAccount, deviceID),
		DeviceBinding: s.bindingStatus(ctx, user.ID, deviceID),
	}, nil
}

func (s *authService) activeKeyID(ctx context.Context, userID string) (string, error) {
	if s.binder == nil {
		return "", nil
	}
	id, applies, err := s.binder.ActiveKeyID(ctx, userID)
	if !applies {
		return "", err
	}
	if errors.Is(err, middleware.ErrDeviceKeyNotAccepted) {
		return "", devicebind.ErrAttestationRequired // SR-2: no session for a non-attested key under enforce
	}
	return id, err
}

func (s *authService) bindingStatus(ctx context.Context, userID, deviceID string) *domain.DeviceBindingStatus {
	if s.binder == nil {
		return nil
	}
	st := s.binder.Status(ctx, userID, deviceID)
	return &st
}

func (s *authService) resolvePrimaryAccount(ctx context.Context, user *model.User) string {
	if acc, err := s.repo.FindPrimaryAccount(ctx, user.ID); err == nil && acc != nil {
		return acc.AccountNumber
	}
	if s.cbsProv != nil && user.CIF != "" {
		if items, err := s.cbsProv.GetSavingsAccountsByCIF(ctx, user.CIF); err == nil && len(items) > 0 {
			return items[0].NomorRekening
		}
	}
	if acc, err := s.repo.EnsurePrimaryAccount(ctx, user, ""); err == nil && acc != nil {
		return acc.AccountNumber
	}
	return ""
}

func (s *authService) Login(ctx context.Context, req domain.LoginRequest, client ClientInfo) (*domain.LoginResponse, error) {
	identifier := strings.TrimSpace(req.Username)
	if identifier == "" {
		identifier = strings.TrimSpace(req.PhoneNumber)
	}
	if identifier == "" {
		identifier = strings.TrimSpace(req.CIF)
	}
	if identifier == "" || req.Password == "" {
		return nil, ErrInvalidCredentials
	}
	deviceID, err := validDevice(req.DeviceID)
	if err != nil {
		return nil, err
	}

	user, err := s.repo.FindByIdentifier(ctx, identifier)
	if err != nil || user == nil {
		user, err = s.repo.FindByIdentifier(ctx, normalizePhone(identifier))
	}
	if err != nil || user == nil || user.PasswordHash == "" {
		security.CheckPassword(s.dummyHash, req.Password)
		return nil, ErrNewDeviceVerification
	}

	boundDevice := ""
	if user.DeviceID != "" && user.DeviceID == deviceID {
		boundDevice = deviceID
	}
	unbound := boundDevice == ""
	unboundNote := ""
	if unbound {
		unboundNote = " (dari perangkat yang belum terikat)"
	}

	if !security.CheckPassword(user.PasswordHash, req.Password) {
		if !user.IsActive {
			if unbound {
				return nil, ErrNewDeviceVerification
			}
			return nil, ErrInvalidCredentials
		}
		if unbound {
			// SECURITY (audit D-01): a wrong password from a device that is not bound to the
			// account never counts toward the automatic block, otherwise anyone who knows a
			// phone number could lock the customer out. The device can only proceed through
			// OTP anyway; the attempt is audited.
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_FAILED_UNBOUND_DEVICE", user.CIF, "WARNING", deviceID, "Password login salah dari perangkat yang belum terikat (tidak menambah hitungan blokir)")
			return nil, ErrNewDeviceVerification
		}
		maxFailedAttempts := s.repo.MaxLoginAttempts(ctx)
		attempts, blocked, incErr := s.repo.IncrementFailedLogin(ctx, user.ID, maxFailedAttempts)
		if incErr != nil {
			return nil, ErrServiceUnavailable
		}
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "AUTO_BLOCK_PASSWORD", user.CIF, "DANGER", deviceID, fmt.Sprintf("Akun diblokir otomatis karena %dx salah memasukkan password login", maxFailedAttempts))
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Peringatan Keamanan: Akun Terkunci", fmt.Sprintf("Akun Mobile DMB Anda telah dikunci otomatis karena %dx salah memasukkan password. Silakan gunakan Lupa Password atau hubungi CS Bank DMB.", maxFailedAttempts), "SECURITY")
			return nil, fmt.Errorf("akun Anda telah diblokir otomatis karena %dx salah memasukkan password. Silakan gunakan menu Lupa Password atau hubungi CS Bank DMB", maxFailedAttempts)
		}
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_FAILED", user.CIF, "WARNING", deviceID, fmt.Sprintf("Password login salah (Percobaan %d/%d)", attempts, maxFailedAttempts))
		return nil, fmt.Errorf("nomor handphone atau password salah (Percobaan %d/%d)", attempts, maxFailedAttempts)
	}

	if !user.IsActive {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_BLOCKED_ATTEMPT", user.CIF, "DANGER", deviceID, "Percobaan login pada akun yang sedang diblokir"+unboundNote)
		if unbound {
			return nil, ErrNewDeviceVerification
		}
		return nil, errors.New("akun nasabah sedang diblokir/tidak aktif. Silakan gunakan menu Lupa Password atau hubungi Customer Service Bank DMB")
	}

	if security.IsCompromisedCredential(req.Password) {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_DEFAULT_CREDENTIAL_REFUSED", user.CIF, "DANGER", deviceID, "Login dengan password bawaan yang terpublikasi ditolak"+unboundNote)
		if unbound {
			return nil, ErrNewDeviceVerification
		}
		return nil, ErrDefaultCredential
	}

	if unbound {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_NEW_DEVICE_REQUIRES_OTP", user.CIF, "WARNING", deviceID, "Login dari perangkat yang belum terverifikasi ditolak; diperlukan verifikasi OTP")
		return nil, ErrNewDeviceVerification
	}

	if err := s.binder.Require(ctx, devicebind.PurposeLogin, user.ID, boundDevice,
		devicebind.Proof{ChallengeID: req.DeviceChallengeID, Signature: req.DeviceSignature}, ""); err != nil {
		if devicebind.FailureReason(err) != "" {
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Peringatan Keamanan: Login Ditolak",
				"Login Mobile DMB dengan password Anda ditolak karena verifikasi kunci perangkat gagal. Jika ini bukan Anda, segera ganti password atau hubungi CS Bank DMB.", "SECURITY")
		}
		return nil, err
	}

	if err := s.repo.ResetFailedLogin(ctx, user.ID); err != nil {
		return nil, ErrServiceUnavailable
	}

	if err := s.consent.EnsureUserConsent(ctx, user.ID, deviceID, strings.TrimSpace(req.TermsAcceptanceID), legaldoc.ChannelLogin,
		legaldoc.ClientMeta{IP: client.IP, UserAgent: client.UserAgent}); err != nil {
		if errors.Is(err, legaldoc.ErrConsentRequired) || errors.Is(err, legaldoc.ErrInvalidAcceptance) {
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_TERMS_CONSENT_REQUIRED", user.CIF, "WARNING", deviceID, "Login ditahan: persetujuan Syarat dan Ketentuan versi berlaku belum tercatat")
		}
		return nil, err
	}

	if s.cbsProv != nil && user.CIF != "" {
		if nas, nasErr := s.cbsProv.GetCustomerByCIF(ctx, user.CIF); nasErr == nil && nas != nil && nas.Nama != "" {
			user.FullName = nas.Nama
		}
	}
	primary := s.resolvePrimaryAccount(ctx, user)

	resp, err := s.issueSession(ctx, user, primary, boundDevice, client.IP, true, session.ReasonNewLogin)
	if err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_SUCCESS", user.CIF, "SUCCESS", boundDevice, "Login Mobile DMB berhasil")
	return resp, nil
}

func (s *authService) RefreshToken(ctx context.Context, req domain.RefreshTokenRequest, client ClientInfo) (*domain.LoginResponse, error) {
	claims, err := security.ValidateRefreshToken(strings.TrimSpace(req.RefreshToken), s.cfg.JWTSecret)
	if err != nil {
		return nil, errors.New("sesi Anda telah berakhir, silakan login kembali")
	}
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return nil, err
	}
	if claims.DeviceID != deviceID {
		return nil, ErrDeviceBindingMismatch
	}

	user, err := s.repo.FindByID(ctx, claims.UserID)
	if err != nil || user == nil {
		return nil, errors.New("data pengguna tidak ditemukan")
	}
	if !user.IsActive {
		return nil, ErrUserInactive
	}
	if user.DeviceID == "" || user.DeviceID != deviceID {
		return nil, ErrDeviceBindingMismatch
	}
	if err := s.binder.Require(ctx, devicebind.PurposeRefresh, user.ID, deviceID,
		devicebind.Proof{ChallengeID: req.DeviceChallengeID, Signature: req.DeviceSignature}, ""); err != nil {
		return nil, err
	}
	keyID, err := s.activeKeyID(ctx, user.ID)
	if errors.Is(err, devicebind.ErrAttestationRequired) {
		return nil, err
	}
	if err != nil {
		return nil, ErrServiceUnavailable
	}
	if s.binder.Active() && keyID != claims.DeviceKeyID {
		return nil, ErrRefreshExpired
	}
	if err := s.consent.RequireUserConsent(ctx, user.ID); err != nil {
		return nil, err
	}

	primary := s.resolvePrimaryAccount(ctx, user)
	tokens, err := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: user.ID, CIF: user.CIF, PhoneNumber: user.PhoneNumber, AccountNo: primary,
		DeviceID: deviceID, DeviceKeyID: keyID, SessionID: claims.SessionID,
	}, s.cfg.JWTSecret, s.accessTTL(), s.refreshTTL())
	if err != nil {
		return nil, err
	}
	if err := s.sessions.Rotate(ctx, claims.SessionID, user.ID, claims.ID, tokens.RefreshTokenID, tokens.RefreshExpiry); err != nil {
		if errors.Is(err, session.ErrRefreshReused) {
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "REFRESH_TOKEN_REUSE_DETECTED", user.CIF, "DANGER", deviceID, "Refresh token lama digunakan ulang; seluruh sesi dicabut")
		}
		return nil, err
	}
	return &domain.LoginResponse{
		AccessToken:   tokens.AccessToken,
		RefreshToken:  tokens.RefreshToken,
		TokenType:     "Bearer",
		ExpiresIn:     int(s.accessTTL().Seconds()),
		User:          profile(user, primary, deviceID),
		DeviceBinding: s.bindingStatus(ctx, user.ID, deviceID),
	}, nil
}

func (s *authService) Logout(ctx context.Context, userID string, client ClientInfo) error {
	if client.SessionID == "" {
		return nil
	}
	if err := s.sessions.Revoke(ctx, client.SessionID, session.ReasonLogout); err != nil {
		return ErrServiceUnavailable
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", userID, "", "LOGOUT", "", "SUCCESS", client.DeviceID, "Logout dan pencabutan sesi")
	return nil
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func (s *authService) VerifyActivation(ctx context.Context, req domain.ActivateVerifyRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error) {
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return nil, err
	}
	normInputPhone := normalizePhone(req.PhoneNumber)
	identifier := strings.TrimSpace(req.AccountNumber)
	if identifier == "" {
		identifier = strings.TrimSpace(req.CIFNumber)
	}
	if identifier == "" {
		return nil, errors.New("nomor rekening atau CIF wajib diisi")
	}
	if len(normInputPhone) < 9 {
		return nil, errors.New("nomor handphone tidak valid")
	}

	const (
		errAccountNotFound   = "nomor rekening tidak ditemukan. Pastikan nomor rekening tabungan Anda benar"
		errAlreadyRegistered = "rekening ini sudah terdaftar di layanan Mobile Banking. Silakan langsung masuk atau gunakan menu Lupa Password"
		errNoPhoneOnFile     = "nomor handphone belum terdaftar pada rekening ini di bank. Silakan hubungi kantor cabang Bank DMB terdekat"
		errPhoneMismatch     = "nomor handphone tidak sesuai dengan data rekening yang terdaftar di bank"
	)

	var targetUserID string
	var targetCIF string
	var targetFullName string
	targetAccountNo := ""

	if s.cfg.UseLiveCBS() {
		regCheck, regErr := s.cbsProv.RegistrationCheck(ctx, identifier)
		if regErr != nil || regCheck == nil || strings.TrimSpace(regCheck.CIF) == "" {
			audit.Record(ctx, s.repo.DB(), "NASABAH", identifier, "", "ACTIVATION_ACCOUNT_NOT_FOUND", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ditolak: rekening tidak ditemukan di CBS")
			return nil, errors.New(errAccountNotFound)
		}
		if regCheck.Terdaftar {
			audit.Record(ctx, s.repo.DB(), "NASABAH", regCheck.CIF, "", "ACTIVATION_ALREADY_REGISTERED", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ditolak: rekening sudah terdaftar di CBS")
			return nil, errors.New(errAlreadyRegistered)
		}
		// L-02: ensure local account is not already active even if CBS flag is out of sync.
		if existing, fErr := s.repo.FindByCIF(ctx, regCheck.CIF); fErr == nil && existing != nil && existing.PasswordHash != "" {
			audit.Record(ctx, s.repo.DB(), "NASABAH", existing.ID, existing.FullName, "ACTIVATION_LOCAL_ALREADY_ACTIVE", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ulang ditolak: akun lokal sudah aktif")
			return nil, errors.New(errAlreadyRegistered)
		}
		cbsPhone := normalizePhone(regCheck.NoHP)
		if cbsPhone == "" || cbsPhone == "0" {
			audit.Record(ctx, s.repo.DB(), "NASABAH", regCheck.CIF, "", "ACTIVATION_NO_PHONE_ON_FILE", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ditolak: nomor HP tidak tercatat di CBS")
			return nil, errors.New(errNoPhoneOnFile)
		}
		if cbsPhone != normInputPhone {
			audit.Record(ctx, s.repo.DB(), "NASABAH", regCheck.CIF, "", "ACTIVATION_PHONE_MISMATCH", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Nomor HP input tidak cocok dengan nomor HP rekening")
			return nil, errors.New(errPhoneMismatch)
		}
		// L-03: do NOT upsert nasabah/rekening into DB before OTP verification.
		targetCIF = strings.TrimSpace(regCheck.CIF)
		targetAccountNo = identifier
		if existing, fErr := s.repo.FindByCIF(ctx, targetCIF); fErr == nil && existing != nil {
			targetUserID = existing.ID
			targetFullName = existing.FullName
		}
	} else {
		u, findErr := s.repo.FindByCIF(ctx, identifier)
		if findErr != nil || u == nil {
			acc, accUser, accErr := s.repo.FindAccountWithUser(ctx, identifier)
			if accErr == nil && accUser != nil {
				u = accUser
				if acc != nil {
					targetAccountNo = acc.AccountNumber
				}
			}
		}
		if u == nil {
			audit.Record(ctx, s.repo.DB(), "NASABAH", identifier, "", "ACTIVATION_ACCOUNT_NOT_FOUND", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ditolak: rekening/CIF tidak ditemukan di DB lokal")
			return nil, errors.New(errAccountNotFound)
		}
		if u.PasswordHash != "" {
			audit.Record(ctx, s.repo.DB(), "NASABAH", u.ID, u.FullName, "ACTIVATION_LOCAL_ALREADY_ACTIVE", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ulang ditolak: akun lokal sudah aktif")
			return nil, errors.New(errAlreadyRegistered)
		}
		dbPhone := normalizePhone(u.PhoneNumber)
		if repository.IsPendingPhone(u.PhoneNumber) || dbPhone == "" || dbPhone != normInputPhone {
			audit.Record(ctx, s.repo.DB(), "NASABAH", u.ID, u.FullName, "ACTIVATION_PHONE_MISMATCH", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Nomor HP tidak sesuai dengan data lokal")
			return nil, errors.New(errPhoneMismatch)
		}
		targetUserID = u.ID
		targetCIF = u.CIF
		targetFullName = u.FullName
		if targetAccountNo == "" {
			if acc, accErr := s.repo.FindPrimaryAccount(ctx, u.ID); accErr == nil && acc != nil {
				targetAccountNo = acc.AccountNumber
			}
		}
	}

	if targetUserID != "" {
		if inUse, err := s.repo.PhoneUsedByOtherUser(ctx, normInputPhone, targetUserID); err != nil {
			return nil, ErrServiceUnavailable
		} else if inUse {
			audit.Record(ctx, s.repo.DB(), "NASABAH", targetUserID, targetFullName, "ACTIVATION_PHONE_CONFLICT", maskPhoneNumber(normInputPhone), "DANGER", deviceID, "Nomor HP sudah terikat pada nasabah lain")
			return nil, errors.New("nomor handphone sudah terdaftar pada akun nasabah lain")
		}
	} else if existingPhoneUser, err := s.repo.FindByIdentifier(ctx, normInputPhone); err == nil && existingPhoneUser != nil {
		audit.Record(ctx, s.repo.DB(), "NASABAH", targetCIF, "", "ACTIVATION_PHONE_CONFLICT", maskPhoneNumber(normInputPhone), "DANGER", deviceID, "Nomor HP sudah terikat pada nasabah lain")
		return nil, errors.New("nomor handphone sudah terdaftar pada akun nasabah lain")
	}

	otpRecipientName := targetFullName
	if otpRecipientName == "" {
		otpRecipientName = "Nasabah"
	}
	code, err := otp.Send(ctx, s.repo.DB(), normInputPhone, otpRecipientName, "Aktivasi M-Banking")
	if err != nil {
		return nil, err
	}
	sessionID, err := s.otpStore.Create(ctx, otp.Session{
		Purpose: otp.PurposeActivation, UserID: targetUserID, CIF: targetCIF, AccountNo: targetAccountNo,
		PhoneNumber: normInputPhone, FullName: targetFullName, DeviceID: deviceID,
	}, code)
	if err != nil {
		return nil, ErrServiceUnavailable
	}

	auditTarget := targetUserID
	if auditTarget == "" {
		auditTarget = targetCIF
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", auditTarget, otpRecipientName, "ACTIVATION_OTP_SENT", maskPhoneNumber(normInputPhone), "SUCCESS", deviceID, "Kode OTP aktivasi dikirim")
	// SECURITY (audit E-04): customer data is only returned after the OTP is verified
	// (VerifyActivationOTP); knowing a CIF/account and a phone number reveals nothing.
	return &domain.ActivateVerifyResponse{
		SessionID:   sessionID,
		MaskedPhone: maskPhoneNumber(normInputPhone),
	}, nil
}

func (s *authService) VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error) {
	sess, err := s.otpStore.Verify(ctx, req.SessionID, otp.PurposeActivation, client.DeviceID, req.OTPCode)
	if err != nil {
		return nil, err
	}
	res := &domain.ActivateVerifyResponse{
		SessionID:   sess.ID,
		MaskedPhone: maskPhoneNumber(sess.PhoneNumber),
		FullName:    sess.FullName,
		CIFNumber:   sess.CIF,
		AccountNo:   sess.AccountNo,
	}
	if sess.UserID != "" {
		if user, uErr := s.repo.FindByID(ctx, sess.UserID); uErr == nil && user != nil {
			res.CIFNumber = user.CIF
			res.FullName = user.FullName
			res.SuggestedUsername = s.generateSuggestedUsername(ctx, user.FullName)
		}
	} else if s.cfg.UseLiveCBS() && sess.CIF != "" {
		if nas, nErr := s.cbsProv.GetCustomerByCIF(ctx, sess.CIF); nErr == nil && nas != nil && strings.TrimSpace(nas.Nama) != "" {
			res.FullName = strings.TrimSpace(nas.Nama)
			res.SuggestedUsername = s.generateSuggestedUsername(ctx, res.FullName)
		} else if strings.TrimSpace(sess.FullName) != "" {
			res.SuggestedUsername = s.generateSuggestedUsername(ctx, sess.FullName)
		}
	} else if strings.TrimSpace(sess.FullName) != "" {
		res.SuggestedUsername = s.generateSuggestedUsername(ctx, sess.FullName)
	}
	return res, nil
}

func (s *authService) CompleteActivation(ctx context.Context, req domain.ActivateSetupRequest, client ClientInfo) (*domain.LoginResponse, error) {
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return nil, err
	}
	if err := security.ValidateNewPassword(req.Password); err != nil {
		return nil, err
	}
	pin := strings.TrimSpace(req.PIN)
	if err := security.ValidateNewPIN(pin); err != nil {
		return nil, err
	}
	acceptanceID := strings.TrimSpace(req.TermsAcceptanceID)
	if err := s.consent.ValidatePreLogin(ctx, deviceID, acceptanceID); err != nil {
		return nil, err
	}
	sess, err := s.otpStore.Consume(ctx, req.SessionID, otp.PurposeActivation, deviceID)
	if err != nil {
		return nil, err
	}

	// L-03: synchronize CBS customer & account after OTP verification, not before.
	userID := sess.UserID
	primary := sess.AccountNo
	if userID == "" && s.cfg.UseLiveCBS() {
		if sess.CIF == "" {
			return nil, ErrAccountNotMatch
		}
		nas, nasErr := s.cbsProv.GetCustomerByCIF(ctx, sess.CIF)
		if nasErr != nil || nas == nil || strings.TrimSpace(nas.CIF) == "" {
			logger.GetLogger().Error("Gagal mengambil profil nasabah dari CBS saat aktivasi", map[string]interface{}{"error": fmt.Sprint(nasErr), "cif": maskPhoneNumber(sess.CIF)})
			return nil, ErrServiceUnavailable
		}
		bal, balErr := s.cbsProv.GetBalance(ctx, primary)
		if balErr != nil || bal == nil {
			logger.GetLogger().Error("Gagal mengambil saldo rekening dari CBS saat aktivasi", map[string]interface{}{"error": fmt.Sprint(balErr), "account": maskPhoneNumber(primary)})
			return nil, ErrServiceUnavailable
		}
		u, acc, upErr := s.repo.UpsertCBSUserAndAccount(ctx, nas, bal)
		if upErr != nil || u == nil {
			logger.GetLogger().Error("Gagal sinkronisasi nasabah untuk aktivasi", map[string]interface{}{"error": fmt.Sprint(upErr)})
			return nil, ErrAccountNotMatch
		}
		userID = u.ID
		if acc != nil {
			primary = acc.AccountNumber
		}
	}

	if inUse, err := s.repo.PhoneUsedByOtherUser(ctx, sess.PhoneNumber, userID); err != nil || inUse {
		return nil, errors.New("nomor handphone sudah terdaftar pada akun lain. Silakan hubungi CS Bank DMB")
	}

	username := strings.ToLower(strings.TrimSpace(req.Username))
	if username != "" {
		if err := validateUsername(username); err != nil {
			return nil, err
		}
		if taken, err := s.repo.IsUsernameTaken(ctx, username, userID); err != nil {
			return nil, ErrServiceUnavailable
		} else if taken {
			return nil, errors.New("username sudah digunakan nasabah lain. Silakan pilih username yang berbeda")
		}
	} else {
		targetUser, _ := s.repo.FindByID(ctx, userID)
		if targetUser != nil {
			username = s.generateSuggestedUsername(ctx, targetUser.FullName)
		}
	}

	pwHash, err := security.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}
	pinHash, err := security.HashPIN(pin)
	if err != nil {
		return nil, err
	}

	// D-1: call idempotent CBS RegistrationComplete BEFORE opening the DB transaction so
	// database connections and row locks are not held during the external HTTP call.
	cbsCompleted := false
	if s.cfg.UseLiveCBS() && s.cbsProv != nil && primary != "" {
		if _, regErr := s.cbsProv.RegistrationComplete(ctx, primary); regErr != nil {
			logger.GetLogger().Error("Gagal mencatat registrasi selesai ke CBS", map[string]interface{}{"error": regErr.Error(), "account": maskPhoneNumber(primary)})
			return nil, ErrServiceUnavailable
		}
		cbsCompleted = true
	}

	var user *model.User
	if db := s.repo.DB(); db != nil {
		txErr := db.Transaction(func(tx *gorm.DB) error {
			txRepo := repository.NewAuthRepository(tx)
			txConsent := legaldoc.NewService(tx, nil, nil)
			if err := txRepo.SetActivationCredentials(ctx, userID, username, pwHash, pinHash, sess.PhoneNumber, deviceID); err != nil {
				logger.GetLogger().Error("Gagal menyimpan kredensial aktivasi", map[string]interface{}{"error": err.Error()})
				return ErrServiceUnavailable
			}
			u, findErr := txRepo.FindByID(ctx, userID)
			if findErr != nil || u == nil {
				return ErrAccountNotMatch
			}
			user = u
			if acc, ensErr := txRepo.EnsurePrimaryAccount(ctx, user, primary); ensErr == nil && acc != nil {
				primary = acc.AccountNumber
			}
			if err := txConsent.EnsureUserConsent(ctx, user.ID, deviceID, acceptanceID, legaldoc.ChannelActivation,
				legaldoc.ClientMeta{IP: client.IP, UserAgent: client.UserAgent}); err != nil {
				logger.GetLogger().Warn("Aktivasi dibatalkan: persetujuan SK gagal dicatat", map[string]interface{}{"error": err.Error()})
				return err
			}
			return nil
		})
		if txErr != nil {
			if cbsCompleted {
				logger.GetLogger().Error("RECONCILE_REQUIRED: CBS RegistrationComplete sukses tetapi commit lokal gagal",
					map[string]interface{}{"error": txErr.Error(), "account": maskPhoneNumber(primary), "cif": maskPhoneNumber(sess.CIF)})
				audit.Record(ctx, db, "SYSTEM", userID, "ACTIVATION", "ACTIVATION_RECONCILE_REQUIRED", maskPhoneNumber(sess.CIF), "DANGER", deviceID,
					"CBS RegistrationComplete sukses tetapi penyimpanan lokal gagal; perlu rekonsiliasi manual")
			}
			return nil, txErr
		}
	} else {
		if err := s.repo.SetActivationCredentials(ctx, userID, username, pwHash, pinHash, sess.PhoneNumber, deviceID); err != nil {
			logger.GetLogger().Error("Gagal menyimpan kredensial aktivasi", map[string]interface{}{"error": err.Error()})
			return nil, ErrServiceUnavailable
		}
		var findErr error
		user, findErr = s.repo.FindByID(ctx, userID)
		if findErr != nil || user == nil {
			return nil, ErrAccountNotMatch
		}
		if acc, ensErr := s.repo.EnsurePrimaryAccount(ctx, user, primary); ensErr == nil && acc != nil {
			primary = acc.AccountNumber
		}
		if err := s.consent.EnsureUserConsent(ctx, user.ID, deviceID, acceptanceID, legaldoc.ChannelActivation,
			legaldoc.ClientMeta{IP: client.IP, UserAgent: client.UserAgent}); err != nil {
			logger.GetLogger().Warn("Aktivasi selesai tanpa sesi: persetujuan SK gagal dicatat", map[string]interface{}{"error": err.Error()})
			return nil, err
		}
	}

	resp, err := s.issueSession(ctx, user, primary, deviceID, client.IP, true, session.ReasonActivation)
	if err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "ACTIVATION_COMPLETE", user.CIF, "SUCCESS", deviceID, "Aktivasi M-Banking berhasil dan perangkat terikat")
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Selamat Datang di Mobile DMB!",
		fmt.Sprintf("Halo %s, akun M-Banking Anda telah aktif dan terikat pada perangkat ini.", user.FullName), "SECURITY")
	return resp, nil
}

func (s *authService) RequestForgotPassword(ctx context.Context, req domain.ForgotPasswordRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error) {
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return nil, err
	}
	normPhone := normalizePhone(req.PhoneNumber)
	if len(normPhone) < 9 {
		return nil, errors.New("nomor handphone tidak valid")
	}

	user, err := s.repo.FindByIdentifier(ctx, normPhone)
	if err != nil || user == nil || user.PasswordHash == "" || repository.IsPendingPhone(user.PhoneNumber) {
		decoy, genErr := otp.Generate()
		if genErr != nil {
			return nil, ErrServiceUnavailable
		}
		sid, cErr := s.otpStore.Create(ctx, otp.Session{Purpose: otp.PurposeForgotPassword, PhoneNumber: normPhone, DeviceID: deviceID}, decoy)
		if cErr != nil {
			return nil, ErrServiceUnavailable
		}
		return &domain.ActivateVerifyResponse{SessionID: sid, MaskedPhone: maskPhoneNumber(normPhone)}, nil
	}

	code, err := otp.Send(ctx, s.repo.DB(), normPhone, user.FullName, "Reset Password M-Banking")
	if err != nil {
		return nil, err
	}
	sid, err := s.otpStore.Create(ctx, otp.Session{
		Purpose: otp.PurposeForgotPassword, UserID: user.ID, PhoneNumber: normPhone, FullName: user.FullName, DeviceID: deviceID,
	}, code)
	if err != nil {
		return nil, ErrServiceUnavailable
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "FORGOT_PASSWORD_OTP_SENT", maskPhoneNumber(normPhone), "WARNING", deviceID, "Permintaan kode OTP untuk Lupa Password")
	return &domain.ActivateVerifyResponse{SessionID: sid, MaskedPhone: maskPhoneNumber(normPhone)}, nil
}

func (s *authService) VerifyForgotPasswordOTP(ctx context.Context, req domain.ForgotPasswordVerifyOTPRequest, client ClientInfo) error {
	_, err := s.otpStore.Verify(ctx, req.SessionID, otp.PurposeForgotPassword, client.DeviceID, req.OTPCode)
	return err
}

func (s *authService) ResetForgotPassword(ctx context.Context, req domain.ForgotPasswordResetRequest, client ClientInfo) error {
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return err
	}
	if err := security.ValidateNewPassword(req.NewPassword); err != nil {
		return err
	}
	sess, err := s.otpStore.Consume(ctx, req.SessionID, otp.PurposeForgotPassword, deviceID)
	if err != nil {
		return err
	}
	if sess.UserID == "" {
		return ErrSessionNotFound
	}
	pwHash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}
	if err := s.repo.UpdatePasswordHash(ctx, sess.UserID, pwHash, deviceID); err != nil {
		return ErrServiceUnavailable
	}
	_ = s.sessions.RevokeAllForUser(ctx, sess.UserID, session.ReasonPasswordReset, "")
	audit.Record(ctx, s.repo.DB(), "NASABAH", sess.UserID, sess.FullName, "RESET_PASSWORD_SUCCESS", maskPhoneNumber(sess.PhoneNumber), "SUCCESS", deviceID, "Password di-reset melalui verifikasi OTP; perangkat terikat diperbarui; kunci perangkat lama dicabut; seluruh sesi lama dicabut")
	notification.CreateAndPush(ctx, s.repo.DB(), sess.UserID, "Password Berhasil Diperbarui",
		"Password login Mobile DMB Anda baru saja diperbarui dan perangkat terdaftar diperbarui. Jika Anda tidak merasa melakukan perubahan ini, segera hubungi CS Bank DMB.", "SECURITY")
	return nil
}

func (s *authService) ChangePassword(ctx context.Context, userID string, req domain.ChangePasswordRequest, client ClientInfo) error {
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil || user == nil {
		return errors.New("data akun nasabah tidak ditemukan")
	}
	if err := s.binder.Require(ctx, devicebind.PurposeChangePassword, user.ID, client.DeviceID,
		devicebind.Proof{ChallengeID: req.DeviceChallengeID, Signature: req.DeviceSignature},
		devicebind.OperationContext(devicebind.PurposeChangePassword)); err != nil {
		return err
	}
	if !security.CheckPassword(user.PasswordHash, req.OldPassword) {
		maxFailedAttempts := s.repo.MaxLoginAttempts(ctx)
		_, blocked, _ := s.repo.IncrementFailedLogin(ctx, user.ID, maxFailedAttempts)
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PASSWORD_FAILED", user.CIF, "WARNING", client.DeviceID, "Gagal ganti password: password lama tidak sesuai")
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			return fmt.Errorf("akun Anda diblokir karena %dx salah memasukkan password. Silakan gunakan menu Lupa Password", maxFailedAttempts)
		}
		return errors.New("password lama yang Anda masukkan salah")
	}
	if err := security.ValidateNewPassword(req.NewPassword); err != nil {
		return err
	}
	if req.OldPassword == req.NewPassword {
		return errors.New("password baru tidak boleh sama dengan password lama")
	}
	pwHash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}
	if err := s.repo.UpdatePasswordHash(ctx, user.ID, pwHash, ""); err != nil {
		return ErrServiceUnavailable
	}
	_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonPasswordChange, client.SessionID)
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PASSWORD_SUCCESS", user.CIF, "SUCCESS", client.DeviceID, "Nasabah berhasil mengganti password login; sesi lain dicabut")
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Password Login Diperbarui", "Password login Mobile DMB Anda telah berhasil diganti melalui menu Pengaturan Keamanan.", "SECURITY")
	return nil
}

func (s *authService) ChangePIN(ctx context.Context, userID string, req domain.ChangePINRequest, client ClientInfo) error {
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil || user == nil {
		return errors.New("data akun nasabah tidak ditemukan")
	}
	if err := s.binder.Require(ctx, devicebind.PurposeChangePIN, user.ID, client.DeviceID,
		devicebind.Proof{ChallengeID: req.DeviceChallengeID, Signature: req.DeviceSignature},
		devicebind.OperationContext(devicebind.PurposeChangePIN)); err != nil {
		return err
	}
	if !security.CheckPIN(user.PINHash, req.OldPIN) {
		maxFailedAttempts := s.repo.MaxLoginAttempts(ctx)
		attempts, blocked, _ := s.repo.IncrementFailedPIN(ctx, user.ID, maxFailedAttempts)
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PIN_FAILED", user.CIF, "WARNING", client.DeviceID, fmt.Sprintf("Gagal ganti PIN: PIN lama tidak sesuai (Percobaan %d/%d)", attempts, maxFailedAttempts))
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, fmt.Sprintf("Akun Diblokir: %dx Salah PIN", maxFailedAttempts), fmt.Sprintf("Demi keamanan akun Anda, akun Mobile DMB telah dikunci karena %dx salah memasukkan PIN. Hubungi CS Bank DMB.", maxFailedAttempts), "SECURITY")
			return fmt.Errorf("akun Anda diblokir karena %dx salah memasukkan PIN. Silakan hubungi CS Bank DMB", maxFailedAttempts)
		}
		return fmt.Errorf("PIN transaksi lama yang Anda masukkan salah (Percobaan %d/%d)", attempts, maxFailedAttempts)
	}
	newPin := strings.TrimSpace(req.NewPIN)
	if err := security.ValidateNewPIN(newPin); err != nil {
		return err
	}
	if req.OldPIN == newPin {
		return errors.New("PIN baru tidak boleh sama dengan PIN lama")
	}
	pinHash, err := security.HashPIN(newPin)
	if err != nil {
		return err
	}
	if err := s.repo.UpdateOnlyPINHash(ctx, user.ID, pinHash); err != nil {
		return ErrServiceUnavailable
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PIN_SUCCESS", user.CIF, "SUCCESS", client.DeviceID, "Nasabah berhasil mengganti PIN Transaksi")
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "PIN Transaksi Diperbarui", "PIN Transaksi Mobile DMB Anda telah berhasil diganti melalui menu Pengaturan Keamanan.", "SECURITY")
	return nil
}

// generateSuggestedUsername proposes "<3 first letters of name><3 random unused digits>".
// SECURITY (audit E-04): it is never derived from birth date or CIF, so it reveals no personal data.
func (s *authService) generateSuggestedUsername(ctx context.Context, fullName string) string {
	nameLower := strings.ToLower(fullName)
	titles := []string{"dr.", "dra.", "drs.", "ir.", "h.", "hj.", "s.e.", "s.kom.", "s.h.", "s.t.", "m.m.", "m.si.", "prof."}
	for _, t := range titles {
		nameLower = strings.ReplaceAll(nameLower, t, "")
	}

	var sb strings.Builder
	for _, r := range nameLower {
		if r >= 'a' && r <= 'z' {
			sb.WriteRune(r)
			if sb.Len() == 3 {
				break
			}
		}
	}
	baseName := sb.String()
	if baseName == "" {
		baseName = "usr"
	}
	for len(baseName) < 3 {
		baseName += "x"
	}

	candidate := ""
	for i := 0; i < 30; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(1000))
		if err != nil {
			break
		}
		candidate = fmt.Sprintf("%s%03d", baseName, n.Int64())
		if taken, err := s.repo.IsUsernameTaken(ctx, candidate, ""); err == nil && !taken {
			return candidate
		}
	}
	// If random picks collided, scan from a random starting point for any unused 3-digit suffix.
	start := 0
	if n, err := rand.Int(rand.Reader, big.NewInt(1000)); err == nil {
		start = int(n.Int64())
	}
	for offset := 0; offset < 1000; offset++ {
		num := (start + offset) % 1000
		candidate = fmt.Sprintf("%s%03d", baseName, num)
		if taken, err := s.repo.IsUsernameTaken(ctx, candidate, ""); err == nil && !taken {
			return candidate
		}
	}
	return candidate
}

func validateUsername(u string) error {
	if len(u) < 4 || len(u) > 30 {
		return errors.New("username harus antara 4 sampai 30 karakter")
	}
	hasLetter := false
	for _, r := range u {
		if r >= 'a' && r <= 'z' {
			hasLetter = true
		}
	}
	// SECURITY (audit D-02): a username without letters could equal another customer's
	// phone number or CIF and make the login identifier ambiguous.
	if !hasLetter {
		return errors.New("username wajib mengandung minimal satu huruf (tidak boleh hanya angka)")
	}
	for i, r := range u {
		isAlphaNum := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		isAllowedSpecial := r == '.' || r == '_'
		if !isAlphaNum && !isAllowedSpecial {
			return errors.New("username hanya boleh berisi huruf kecil, angka, titik (.), dan garis bawah (_)")
		}
		if (i == 0 || i == len(u)-1) && !isAlphaNum {
			return errors.New("username tidak boleh diawali atau diakhiri tanda baca")
		}
	}
	return nil
}

// ErrPINRequired: the profile reveal needs the 6-digit transaction PIN.
var ErrPINRequired = errors.New("PIN transaksi 6 digit wajib diisi")

// RevealProfile returns the unmasked customer identity after a server-side PIN check
// (audit D-09). A wrong PIN counts toward the automatic block like Ganti PIN; the reveal
// itself is audited.
func (s *authService) RevealProfile(ctx context.Context, userID, pin string, client ClientInfo) (*domain.CBSNasabahData, error) {
	pin = strings.TrimSpace(pin)
	if len(pin) != 6 {
		return nil, ErrPINRequired
	}
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil || user == nil {
		return nil, errors.New("data akun nasabah tidak ditemukan")
	}
	if !user.IsActive {
		return nil, errors.New("akun nasabah sedang diblokir. Hubungi CS Bank DMB")
	}
	if user.PINHash == "" || !security.CheckPIN(user.PINHash, pin) {
		maxFailedAttempts := s.repo.MaxLoginAttempts(ctx)
		attempts, blocked, incErr := s.repo.IncrementFailedPIN(ctx, user.ID, maxFailedAttempts)
		if incErr != nil {
			return nil, ErrServiceUnavailable
		}
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "PROFILE_REVEAL_PIN_FAILED", user.CIF, "WARNING", client.DeviceID,
			fmt.Sprintf("PIN salah saat membuka data identitas (Percobaan %d/%d)", attempts, maxFailedAttempts))
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, fmt.Sprintf("Akun Diblokir: %dx Salah PIN", maxFailedAttempts),
				fmt.Sprintf("Demi keamanan akun Anda, akun Mobile DMB telah dikunci karena %dx salah memasukkan PIN. Hubungi CS Bank DMB.", maxFailedAttempts), "SECURITY")
			return nil, fmt.Errorf("akun Anda diblokir karena %dx salah memasukkan PIN. Silakan hubungi CS Bank DMB", maxFailedAttempts)
		}
		return nil, fmt.Errorf("PIN transaksi salah (Percobaan %d/%d)", attempts, maxFailedAttempts)
	}
	if err := s.repo.ResetFailedPIN(ctx, user.ID); err != nil {
		return nil, ErrServiceUnavailable
	}
	data, err := s.cbsProv.GetCustomerByCIF(ctx, user.CIF)
	if err != nil || data == nil {
		return nil, ErrServiceUnavailable
	}
	out := *data
	out.NamaIbuKandung = "" // verification secret: never sent to clients (audit DMB-022)
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "PROFILE_REVEALED", user.CIF, "SUCCESS", client.DeviceID, "Data identitas dibuka dengan verifikasi PIN")
	return &out, nil
}
