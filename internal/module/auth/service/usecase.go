package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/auth/repository"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/internal/session"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/security"

	"github.com/google/uuid"
)

const maxFailedAttempts = 3

var (
	ErrDeviceBindingMismatch = errors.New("perangkat tidak cocok dengan perangkat terdaftar untuk akun ini (Device Binding Error)")
	ErrUserInactive          = errors.New("akun nasabah tidak aktif atau diblokir")
	ErrInvalidCredentials    = errors.New("nomor handphone atau password salah")
	ErrDeviceIDRequired      = errors.New("identitas perangkat (device_id) wajib disertakan")
	ErrAccountNotMatch       = errors.New("data nasabah tidak dapat diverifikasi")
	ErrSessionNotFound       = otp.ErrSessionNotFound
	ErrOTPInvalid            = otp.ErrInvalidCode
	ErrOTPNotVerified        = otp.ErrNotVerified
	ErrPasswordTooShort      = security.ErrWeakPassword
	ErrPINInvalidLength      = errors.New("PIN transaksi harus tepat 6 digit angka")
	// ErrNewDeviceVerification is returned when a password login comes from a device
	// other than the bound one: binding a new device requires OTP (audit DMB-013).
	ErrNewDeviceVerification = errors.New("perangkat baru terdeteksi. Demi keamanan, verifikasi perangkat ini melalui menu Lupa Password (kode OTP dikirim ke nomor handphone terdaftar)")
	ErrDefaultCredential     = errors.New("password Anda adalah password bawaan yang tidak aman dan telah dinonaktifkan. Silakan atur ulang melalui menu Lupa Password")
	ErrSessionBusy           = session.ErrConcurrentRefresh
	ErrServiceUnavailable    = errors.New("layanan sedang tidak tersedia, silakan coba beberapa saat lagi")
)

// ClientInfo describes the calling device/session (from verified headers & token).
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
	VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest, client ClientInfo) error
	CompleteActivation(ctx context.Context, req domain.ActivateSetupRequest, client ClientInfo) (*domain.LoginResponse, error)
	RequestForgotPassword(ctx context.Context, req domain.ForgotPasswordRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error)
	VerifyForgotPasswordOTP(ctx context.Context, req domain.ForgotPasswordVerifyOTPRequest, client ClientInfo) error
	ResetForgotPassword(ctx context.Context, req domain.ForgotPasswordResetRequest, client ClientInfo) error
	ChangePassword(ctx context.Context, userID string, req domain.ChangePasswordRequest, client ClientInfo) error
	ChangePIN(ctx context.Context, userID string, req domain.ChangePINRequest, client ClientInfo) error
}

// ConsentGate decides whether the customer has accepted the Terms and Conditions in
// force (internal/legaldoc). The backend, not the app, is the source of truth.
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
	dummyHash string // equalizes timing for unknown identifiers
}

func NewAuthService(cfg *config.Config, repo repository.AuthRepository, cbsProv cbsprovider.CBSProvider, otpStore *otp.Store, sessions *session.Manager, consent ConsentGate) AuthService {
	dummy, _ := security.HashPassword(uuid.NewString())
	return &authService{cfg: cfg, consent: consent, repo: repo, cbsProv: cbsProv, otpStore: otpStore, sessions: sessions, dummyHash: dummy}
}

func maskPhoneNumber(phone string) string {
	if len(phone) < 8 {
		return "****"
	}
	return fmt.Sprintf("%s****%s", phone[:4], phone[len(phone)-4:])
}

// MaskNIK keeps only the last 4 digits of the national ID (data minimisation).
func MaskNIK(nik string) string {
	n := strings.TrimSpace(nik)
	if len(n) <= 4 {
		return n
	}
	return strings.Repeat("*", len(n)-4) + n[len(n)-4:]
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
	if len(id) < 6 || len(id) > 100 {
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

// profile builds the minimised customer profile returned to the app (audit DMB-022):
// the mother's maiden name is never returned and the NIK is masked.
func profile(user *model.User, primaryAccount, deviceID string) domain.UserProfile {
	return domain.UserProfile{
		ID:             user.ID,
		NIK:            MaskNIK(string(user.NIK)),
		CIF:            user.CIF,
		FullName:       user.FullName,
		PhoneNumber:    user.PhoneNumber,
		Email:          string(user.Email),
		Alamat:         string(user.Alamat),
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

// issueSession creates a new server-side session and token pair. When exclusive is
// true, every other session of the user is revoked (single active device).
func (s *authService) issueSession(ctx context.Context, user *model.User, primaryAccount, deviceID, ip string, exclusive bool, reason string) (*domain.LoginResponse, error) {
	sid := uuid.NewString()
	tokens, err := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: user.ID, CIF: user.CIF, PhoneNumber: user.PhoneNumber, AccountNo: primaryAccount,
		DeviceID: deviceID, SessionID: sid,
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
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int(s.accessTTL().Seconds()),
		User:         profile(user, primaryAccount, deviceID),
	}, nil
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
	identifier := strings.TrimSpace(req.PhoneNumber)
	if identifier == "" {
		identifier = strings.TrimSpace(req.CIF)
	}
	if identifier == "" {
		identifier = strings.TrimSpace(req.Username)
	}
	if identifier == "" || req.Password == "" {
		return nil, ErrInvalidCredentials
	}
	deviceID, err := validDevice(req.DeviceID)
	if err != nil {
		return nil, err
	}

	user, err := s.repo.FindByIdentifier(ctx, normalizePhone(identifier))
	if err != nil || user == nil {
		user, err = s.repo.FindByIdentifier(ctx, identifier)
	}
	if err != nil || user == nil || user.PasswordHash == "" {
		// Unknown or not-yet-activated account: same response and similar timing as a wrong password.
		security.CheckPassword(s.dummyHash, req.Password)
		return nil, ErrInvalidCredentials
	}

	if !security.CheckPassword(user.PasswordHash, req.Password) {
		if !user.IsActive {
			return nil, ErrInvalidCredentials
		}
		attempts, blocked, incErr := s.repo.IncrementFailedLogin(ctx, user.ID, maxFailedAttempts)
		if incErr != nil {
			return nil, ErrServiceUnavailable
		}
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "AUTO_BLOCK_PASSWORD", user.CIF, "DANGER", deviceID, "Akun diblokir otomatis karena 3x salah memasukkan password login")
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Peringatan Keamanan: Akun Terkunci", "Akun Mobile DMB Anda telah dikunci otomatis karena 3x salah memasukkan password. Silakan gunakan Lupa Password atau hubungi CS Bank DMB.", "SECURITY")
			return nil, errors.New("akun Anda telah diblokir otomatis karena 3x salah memasukkan password. Silakan gunakan menu Lupa Password atau hubungi CS Bank DMB")
		}
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_FAILED", user.CIF, "WARNING", deviceID, fmt.Sprintf("Password login salah (Percobaan %d/%d)", attempts, maxFailedAttempts))
		return nil, fmt.Errorf("nomor handphone atau password salah (Percobaan %d/%d)", attempts, maxFailedAttempts)
	}

	if !user.IsActive {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_BLOCKED_ATTEMPT", user.CIF, "DANGER", deviceID, "Percobaan login pada akun yang sedang diblokir")
		return nil, errors.New("akun nasabah sedang diblokir/tidak aktif. Silakan gunakan menu Lupa Password atau hubungi Customer Service Bank DMB")
	}

	// Credentials that were published as hardcoded defaults are refused (audit DMB-003).
	if security.IsCompromisedCredential(req.Password) {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_DEFAULT_CREDENTIAL_REFUSED", user.CIF, "DANGER", deviceID, "Login dengan password bawaan yang terpublikasi ditolak")
		return nil, ErrDefaultCredential
	}

	// Device binding: a new device can only be bound through an OTP flow (audit DMB-013).
	if user.DeviceID == "" || user.DeviceID != deviceID {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_NEW_DEVICE_REQUIRES_OTP", user.CIF, "WARNING", deviceID, "Login dari perangkat yang belum terverifikasi ditolak; diperlukan verifikasi OTP")
		return nil, ErrNewDeviceVerification
	}

	if err := s.repo.ResetFailedLogin(ctx, user.ID); err != nil {
		return nil, ErrServiceUnavailable
	}

	// Terms and Conditions: the customer must have accepted the version in force (the
	// device consent given before login is linked here). Checked after authentication
	// so that it reveals nothing about unknown accounts, and before any session exists.
	if err := s.consent.EnsureUserConsent(ctx, user.ID, deviceID, strings.TrimSpace(req.TermsAcceptanceID), legaldoc.ChannelLogin,
		legaldoc.ClientMeta{IP: client.IP, UserAgent: client.UserAgent}); err != nil {
		if errors.Is(err, legaldoc.ErrConsentRequired) || errors.Is(err, legaldoc.ErrInvalidAcceptance) {
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_TERMS_CONSENT_REQUIRED", user.CIF, "WARNING", deviceID, "Login ditahan: persetujuan Syarat dan Ketentuan versi berlaku belum tercatat")
		}
		return nil, err
	}

	// Refresh display data from CBS (best effort; the OpenAPI provider syncs encrypted PII).
	if s.cbsProv != nil && user.CIF != "" {
		if nas, nasErr := s.cbsProv.GetCustomerByCIF(ctx, user.CIF); nasErr == nil && nas != nil && nas.Nama != "" {
			user.FullName = nas.Nama
		}
	}
	primary := s.resolvePrimaryAccount(ctx, user)

	resp, err := s.issueSession(ctx, user, primary, deviceID, client.IP, true, session.ReasonNewLogin)
	if err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_SUCCESS", user.CIF, "SUCCESS", deviceID, "Login Mobile DMB berhasil")
	return resp, nil
}

func (s *authService) RefreshToken(ctx context.Context, req domain.RefreshTokenRequest, client ClientInfo) (*domain.LoginResponse, error) {
	claims, err := security.ValidateRefreshToken(strings.TrimSpace(req.RefreshToken), s.cfg.JWTSecret)
	if err != nil {
		return nil, errors.New("sesi refresh token telah berakhir, silakan login kembali")
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
	// A new Terms version that has come into force must be accepted before the session
	// is extended (also covers biometric unlock, which uses this endpoint).
	if err := s.consent.RequireUserConsent(ctx, user.ID); err != nil {
		return nil, err
	}

	primary := s.resolvePrimaryAccount(ctx, user)
	tokens, err := security.GenerateTokenPair(security.CustomerTokenInput{
		UserID: user.ID, CIF: user.CIF, PhoneNumber: user.PhoneNumber, AccountNo: primary,
		DeviceID: deviceID, SessionID: claims.SessionID,
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
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int(s.accessTTL().Seconds()),
		User:         profile(user, primary, deviceID),
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

// VerifyActivation validates CIF + phone against CBS and sends an OTP to the phone
// registered in CBS. The account is not usable until CompleteActivation (audit DMB-003).
func (s *authService) VerifyActivation(ctx context.Context, req domain.ActivateVerifyRequest, client ClientInfo) (*domain.ActivateVerifyResponse, error) {
	deviceID, err := validDevice(firstNonEmpty(client.DeviceID, req.DeviceID))
	if err != nil {
		return nil, err
	}
	normInputPhone := normalizePhone(req.PhoneNumber)
	cifNo := strings.TrimSpace(req.CIFNumber)
	if cifNo == "" {
		return nil, errors.New("nomor CIF wajib diisi (aktivasi menggunakan nomor rekening tidak lagi didukung)")
	}
	if len(normInputPhone) < 9 {
		return nil, errors.New("nomor handphone tidak valid")
	}

	var targetUser *model.User
	targetAccountNo := ""

	if s.cfg.UseLiveCBS() {
		nas, nasErr := s.cbsProv.GetCustomerByCIF(ctx, cifNo)
		if nasErr != nil || nas == nil || strings.TrimSpace(nas.CIF) == "" {
			return nil, errors.New("nomor CIF tidak ditemukan. Pastikan nomor CIF Anda sudah benar atau hubungi CS Bank DMB")
		}
		cbsPhone := normalizePhone(nas.NoHP)
		if cbsPhone == "" || cbsPhone == "0" {
			audit.Record(ctx, s.repo.DB(), "NASABAH", cifNo, nas.Nama, "ACTIVATION_NO_PHONE_ON_FILE", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Aktivasi ditolak: nomor HP tidak tercatat di CBS")
			return nil, errors.New("nomor handphone Anda belum tercatat di data nasabah Bank DMB. Silakan perbarui data di kantor cabang terdekat")
		}
		if cbsPhone != normInputPhone {
			audit.Record(ctx, s.repo.DB(), "NASABAH", cifNo, nas.Nama, "ACTIVATION_PHONE_MISMATCH", maskPhoneNumber(normInputPhone), "WARNING", deviceID, "Nomor HP input tidak cocok dengan nomor HP CIF")
			return nil, errors.New("nomor handphone tidak sesuai dengan data CIF terdaftar di Bank DMB")
		}

		var bal *domain.BalanceResponse
		if accList, listErr := s.cbsProv.GetSavingsAccountsByCIF(ctx, cifNo); listErr == nil && len(accList) > 0 {
			primary := accList[0]
			targetAccountNo = primary.NomorRekening
			bal, _ = s.cbsProv.GetBalance(ctx, primary.NomorRekening)
			if bal == nil {
				bal = &domain.BalanceResponse{AccountNumber: primary.NomorRekening, HolderName: primary.Nama,
					ProductCode: primary.ProdukTabungan, Balance: primary.Saldo}
			}
		}
		u, acc, upErr := s.repo.UpsertCBSUserAndAccount(ctx, nas, bal)
		if upErr != nil || u == nil {
			logger.GetLogger().Error("Gagal sinkronisasi nasabah untuk aktivasi", map[string]interface{}{"error": fmt.Sprint(upErr)})
			return nil, ErrAccountNotMatch
		}
		targetUser = u
		if acc != nil {
			targetAccountNo = acc.AccountNumber
		}
	} else {
		// Mock / local-database mode (non-production only, enforced by config.Validate).
		u, findErr := s.repo.FindByCIF(ctx, cifNo)
		if findErr != nil || u == nil {
			return nil, errors.New("nomor CIF tidak ditemukan. Pastikan nomor CIF Anda sudah benar atau hubungi CS Bank DMB")
		}
		dbPhone := normalizePhone(u.PhoneNumber)
		if repository.IsPendingPhone(u.PhoneNumber) || dbPhone == "" || dbPhone != normInputPhone {
			return nil, errors.New("nomor handphone tidak sesuai dengan nomor CIF terdaftar")
		}
		targetUser = u
		if acc, accErr := s.repo.FindPrimaryAccount(ctx, u.ID); accErr == nil && acc != nil {
			targetAccountNo = acc.AccountNumber
		}
	}

	if inUse, err := s.repo.PhoneUsedByOtherUser(ctx, normInputPhone, targetUser.ID); err != nil {
		return nil, ErrServiceUnavailable
	} else if inUse {
		audit.Record(ctx, s.repo.DB(), "NASABAH", targetUser.ID, targetUser.FullName, "ACTIVATION_PHONE_CONFLICT", maskPhoneNumber(normInputPhone), "DANGER", deviceID, "Nomor HP sudah terikat pada nasabah lain")
		return nil, errors.New("nomor handphone sudah terdaftar pada akun lain. Silakan hubungi CS Bank DMB")
	}

	code, err := otp.Send(ctx, s.repo.DB(), normInputPhone, targetUser.FullName, "Aktivasi M-Banking")
	if err != nil {
		return nil, err
	}
	sessionID, err := s.otpStore.Create(ctx, otp.Session{
		Purpose: otp.PurposeActivation, UserID: targetUser.ID, AccountNo: targetAccountNo,
		PhoneNumber: normInputPhone, FullName: targetUser.FullName, DeviceID: deviceID,
	}, code)
	if err != nil {
		return nil, ErrServiceUnavailable
	}

	audit.Record(ctx, s.repo.DB(), "NASABAH", targetUser.ID, targetUser.FullName, "ACTIVATION_OTP_SENT", maskPhoneNumber(normInputPhone), "SUCCESS", deviceID, "Kode OTP aktivasi dikirim")
	return &domain.ActivateVerifyResponse{
		SessionID:   sessionID,
		MaskedPhone: maskPhoneNumber(normInputPhone),
		FullName:    targetUser.FullName,
		CIFNumber:   targetUser.CIF,
		AccountNo:   targetAccountNo,
	}, nil
}

func (s *authService) VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest, client ClientInfo) error {
	_, err := s.otpStore.Verify(ctx, req.SessionID, otp.PurposeActivation, client.DeviceID, req.OTPCode)
	return err
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
	// Consent must be valid before the one-time activation session is consumed.
	acceptanceID := strings.TrimSpace(req.TermsAcceptanceID)
	if err := s.consent.ValidatePreLogin(ctx, deviceID, acceptanceID); err != nil {
		return nil, err
	}
	sess, err := s.otpStore.Consume(ctx, req.SessionID, otp.PurposeActivation, deviceID)
	if err != nil {
		return nil, err
	}

	if inUse, err := s.repo.PhoneUsedByOtherUser(ctx, sess.PhoneNumber, sess.UserID); err != nil || inUse {
		return nil, errors.New("nomor handphone sudah terdaftar pada akun lain. Silakan hubungi CS Bank DMB")
	}

	pwHash, err := security.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}
	pinHash, err := security.HashPIN(pin)
	if err != nil {
		return nil, err
	}
	if err := s.repo.SetActivationCredentials(ctx, sess.UserID, pwHash, pinHash, sess.PhoneNumber, deviceID); err != nil {
		logger.GetLogger().Error("Gagal menyimpan kredensial aktivasi", map[string]interface{}{"error": err.Error()})
		return nil, ErrServiceUnavailable
	}

	user, err := s.repo.FindByID(ctx, sess.UserID)
	if err != nil || user == nil {
		return nil, ErrAccountNotMatch
	}
	primary := sess.AccountNo
	if acc, ensErr := s.repo.EnsurePrimaryAccount(ctx, user, primary); ensErr == nil && acc != nil {
		primary = acc.AccountNumber
	}
	if err := s.consent.EnsureUserConsent(ctx, user.ID, deviceID, acceptanceID, legaldoc.ChannelActivation,
		legaldoc.ClientMeta{IP: client.IP, UserAgent: client.UserAgent}); err != nil {
		// Credentials are set but no session is issued: the customer accepts the Terms
		// in force and logs in (the login links the consent).
		logger.GetLogger().Warn("Aktivasi selesai tanpa sesi: persetujuan SK gagal dicatat", map[string]interface{}{"error": err.Error()})
		return nil, err
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

// RequestForgotPassword always answers the same way whether or not the phone is
// registered (anti-enumeration); a decoy session is created for unknown numbers.
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

// ResetForgotPassword sets a new password after OTP verification. The verified
// device becomes the bound device (this is the OTP-protected device change path).
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
	audit.Record(ctx, s.repo.DB(), "NASABAH", sess.UserID, sess.FullName, "RESET_PASSWORD_SUCCESS", maskPhoneNumber(sess.PhoneNumber), "SUCCESS", deviceID, "Password di-reset melalui verifikasi OTP; perangkat terikat diperbarui; seluruh sesi lama dicabut")
	notification.CreateAndPush(ctx, s.repo.DB(), sess.UserID, "Password Berhasil Diperbarui",
		"Password login Mobile DMB Anda baru saja diperbarui dan perangkat terdaftar diperbarui. Jika Anda tidak merasa melakukan perubahan ini, segera hubungi CS Bank DMB.", "SECURITY")
	return nil
}

func (s *authService) ChangePassword(ctx context.Context, userID string, req domain.ChangePasswordRequest, client ClientInfo) error {
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil || user == nil {
		return errors.New("data akun nasabah tidak ditemukan")
	}
	if !security.CheckPassword(user.PasswordHash, req.OldPassword) {
		_, blocked, _ := s.repo.IncrementFailedLogin(ctx, user.ID, maxFailedAttempts)
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PASSWORD_FAILED", user.CIF, "WARNING", client.DeviceID, "Gagal ganti password: password lama tidak sesuai")
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			return errors.New("akun Anda diblokir karena 3x salah memasukkan password. Silakan gunakan menu Lupa Password")
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
	// Failed attempts are counted here too, so this endpoint cannot be used as a PIN oracle (audit DMB-018).
	if !security.CheckPIN(user.PINHash, req.OldPIN) {
		attempts, blocked, _ := s.repo.IncrementFailedPIN(ctx, user.ID, maxFailedAttempts)
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "CHANGE_PIN_FAILED", user.CIF, "WARNING", client.DeviceID, fmt.Sprintf("Gagal ganti PIN: PIN lama tidak sesuai (Percobaan %d/%d)", attempts, maxFailedAttempts))
		if blocked {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Akun Diblokir: 3x Salah PIN", "Demi keamanan dana Anda, akun Mobile DMB telah dikunci karena 3x salah memasukkan PIN. Hubungi CS Bank DMB.", "SECURITY")
			return errors.New("akun Anda diblokir karena 3x salah memasukkan PIN. Silakan hubungi CS Bank DMB")
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
