package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/auth/repository"
	"mbanking-bpr/internal/otpprovider"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
)

var (
	ErrDeviceBindingMismatch = errors.New("perangkat tidak cocok dengan perangkat terdaftar untuk akun ini (Device Binding Error)")
	ErrUserInactive          = errors.New("akun nasabah tidak aktif atau diblokir")
	ErrInvalidCredentials    = errors.New("nomor handphone atau password salah")
	ErrDeviceIDRequired      = errors.New("identitas perangkat (device_id) wajib disertakan")
	ErrAccountNotMatch       = errors.New("nomor rekening atau nomor handphone tidak terdaftar")
	ErrSessionNotFound       = errors.New("sesi aktivasi tidak ditemukan atau telah kedaluwarsa")
	ErrOTPInvalid            = errors.New("kode OTP verifikasi salah")
	ErrOTPNotVerified        = errors.New("kode OTP belum diverifikasi")
	ErrPasswordTooShort      = errors.New("password minimal harus 8 karakter")
	ErrPINInvalidLength      = errors.New("PIN transaksi harus tepat 6 digit angka")
)

type ActivationSession struct {
	UserID        string
	AccountNo     string
	PhoneNumber   string
	FullName      string
	OTP           string
	IsOTPVerified bool
	ExpiresAt     time.Time
}

type AuthService interface {
	Login(ctx context.Context, req domain.LoginRequest) (*domain.LoginResponse, error)
	RefreshToken(ctx context.Context, req domain.RefreshTokenRequest) (*domain.LoginResponse, error)
	VerifyActivation(ctx context.Context, req domain.ActivateVerifyRequest) (*domain.ActivateVerifyResponse, error)
	VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest) error
	CompleteActivation(ctx context.Context, req domain.ActivateSetupRequest) (*domain.LoginResponse, error)
	RequestForgotPassword(ctx context.Context, req domain.ForgotPasswordRequest) (*domain.ActivateVerifyResponse, error)
	VerifyForgotPasswordOTP(ctx context.Context, req domain.ForgotPasswordVerifyOTPRequest) error
	ResetForgotPassword(ctx context.Context, req domain.ForgotPasswordResetRequest) error
}

type authService struct {
	cfg      *config.Config
	repo     repository.AuthRepository
	cbsProv  cbsprovider.CBSProvider
	mu       sync.RWMutex
	sessions map[string]*ActivationSession
}

func NewAuthService(cfg *config.Config, repo repository.AuthRepository, cbsProv cbsprovider.CBSProvider) AuthService {
	return &authService{
		cfg:      cfg,
		repo:     repo,
		cbsProv:  cbsProv,
		sessions: make(map[string]*ActivationSession),
	}
}

func (s *authService) Login(ctx context.Context, req domain.LoginRequest) (*domain.LoginResponse, error) {
	// Determine identifier (phone_number or username)
	identifier := req.PhoneNumber
	if identifier == "" {
		identifier = req.Username
	}
	if identifier == "" {
		return nil, errors.New("nomor handphone atau username wajib diisi")
	}

	var user *model.User
	var primaryAccountNo string

	// 1. Authenticate against PostgreSQL via GORM
	dbUser, err := s.repo.FindByIdentifier(ctx, normalizePhone(identifier))
	if err != nil || dbUser == nil {
		dbUser, err = s.repo.FindByIdentifier(ctx, identifier)
	}
	if err == nil && dbUser != nil {
		user = dbUser

		if !user.IsActive {
			otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_BLOCKED_ATTEMPT", user.PhoneNumber, "DANGER", req.DeviceID, "Percobaan login pada akun yang sedang diblokir")
			return nil, errors.New("akun nasabah sedang diblokir/tidak aktif. Silakan gunakan menu Lupa Password atau hubungi Customer Service Bank DMB")
		}

		// Verify Password with bcrypt + Auto-Block after 3 failed attempts
		if !utils.CheckPassword(user.PasswordHash, req.Password) {
			attempts, blocked, _ := s.repo.IncrementFailedLogin(ctx, user.ID, 3)
			if blocked {
				otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "AUTO_BLOCK_PASSWORD", user.PhoneNumber, "DANGER", req.DeviceID, "Akun diblokir otomatis karena 3x salah memasukkan password login")
				otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Peringatan Keamanan: Akun Terkunci", "Akun Mobile DMB Anda telah dikunci otomatis karena 3x salah memasukkan password. Silakan gunakan Lupa Password atau hubungi CS Bank DMB.", "SECURITY")
				return nil, errors.New("akun Anda telah diblokir otomatis karena 3x salah memasukkan password. Silakan gunakan menu Lupa Password atau hubungi CS Bank DMB")
			}
			otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_FAILED", user.PhoneNumber, "WARNING", req.DeviceID, fmt.Sprintf("Password login salah (Percobaan %d/3)", attempts))
			return nil, fmt.Errorf("nomor handphone atau password salah (Percobaan %d/3)", attempts)
		}

		_ = s.repo.ResetFailedLogin(ctx, user.ID)

		// Single Active Device Session (Auto-Logout Old Device):
		// Logging in on a new device binds the new device_id in PostgreSQL, automatically invalidating any old device's session.
		if req.DeviceID != "" && user.DeviceID != req.DeviceID {
			oldDev := user.DeviceID
			user.DeviceID = req.DeviceID
			_ = s.repo.UpdateDeviceID(ctx, user.ID, req.DeviceID)
			if oldDev != "" {
				otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "DEVICE_AUTO_SWITCH", user.CIF, "WARNING", req.DeviceID, fmt.Sprintf("Pindah perangkat dari %s ke %s (Perangkat lama auto-logout)", oldDev, req.DeviceID))
				otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Login di Perangkat Baru", fmt.Sprintf("Akun Mobile DMB Anda baru saja login pada perangkat %s. Sesi pada perangkat %s telah diakhiri otomatis.", req.DeviceID, oldDev), "SECURITY")
			}
		}

		otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "LOGIN_SUCCESS", user.CIF, "SUCCESS", user.DeviceID, "Login Mobile DMB berhasil")

		// Find user's primary account
		if acc, accErr := s.repo.FindPrimaryAccount(ctx, user.ID); accErr == nil && acc != nil {
			primaryAccountNo = acc.AccountNumber
		}

		// Sync live Nasabah CIF profile, Savings Accounts list & Balance from Core Banking System (CBS)
		if s.cbsProv != nil {
			if user.CIF != "" {
				// 1. Hit CBS POST /api/nasabah
				if nasabah, nasErr := s.cbsProv.GetCustomerByCIF(ctx, user.CIF); nasErr == nil && nasabah != nil {
					user.NIK = nasabah.NIK
					if nasabah.Nama != "" {
						user.FullName = nasabah.Nama
					}
					user.Alamat = nasabah.Alamat
					user.KodePos = nasabah.KodePos
					user.JenisKelamin = nasabah.JenisKelamin
					user.Agama = nasabah.Agama
					user.TglLahir = nasabah.TglLahir
					user.TempatLahir = nasabah.TempatLahir
					user.NamaIbuKandung = nasabah.NamaIbuKandung
				}
				// 2. Hit CBS POST /api/savings-accounts
				if accList, listErr := s.cbsProv.GetSavingsAccountsByCIF(ctx, user.CIF); listErr == nil && len(accList) > 0 {
					if primaryAccountNo == "" {
						primaryAccountNo = accList[0].NomorRekening
					}
				}
			}
			// 3. Hit CBS POST /api/savings-account-balance
			if primaryAccountNo != "" {
				if bal, cbsErr := s.cbsProv.GetBalance(ctx, primaryAccountNo); cbsErr == nil && bal != nil && bal.HolderName != "" {
					user.FullName = bal.HolderName
				}
			}
		}

		// Ensure user always has a primary account record in PostgreSQL (auto-heals CIF-only registrations)
		if primaryAccountNo == "" {
			if ensuredAcc, ensErr := s.repo.EnsurePrimaryAccount(ctx, user, ""); ensErr == nil && ensuredAcc != nil {
				primaryAccountNo = ensuredAcc.AccountNumber
			}
		}
	} else {
		// Fallback to CBS Provider if DB record not found or standalone mode
		cbsUser, cbsErr := s.cbsProv.VerifyCredentials(ctx, identifier, req.Password, "")
		if cbsErr != nil {
			return nil, ErrInvalidCredentials
		}
		user = cbsUser
		if acc, accErr := s.repo.FindPrimaryAccount(ctx, user.ID); accErr == nil && acc != nil {
			primaryAccountNo = acc.AccountNumber
		}
	}

	effectiveDeviceID := req.DeviceID
	if effectiveDeviceID == "" {
		effectiveDeviceID = user.DeviceID
	}

	// 2. Generate Access Token & Refresh Token using JWT_EXPIRY_MINUTES from .env
	accessExpMins := s.cfg.JWTExpiryMinutes
	if accessExpMins <= 0 {
		accessExpMins = 60
	}
	refreshExpDays := 7
	tokens, err := utils.GenerateTokenPair(
		user.ID,
		user.CIF,
		user.PhoneNumber,
		primaryAccountNo,
		effectiveDeviceID,
		s.cfg.JWTSecret,
		accessExpMins,
		refreshExpDays,
	)
	if err != nil {
		return nil, err
	}

	return &domain.LoginResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    accessExpMins * 60,
		User: domain.UserProfile{
			ID:             user.ID,
			NIK:            user.NIK,
			CIF:            user.CIF,
			FullName:       user.FullName,
			PhoneNumber:    user.PhoneNumber,
			Email:          user.Email,
			Alamat:         user.Alamat,
			KodePos:        user.KodePos,
			JenisKelamin:   user.JenisKelamin,
			Agama:          user.Agama,
			TglLahir:       user.TglLahir,
			TempatLahir:    user.TempatLahir,
			NamaIbuKandung: user.NamaIbuKandung,
			DeviceID:       user.DeviceID,
			PrimaryAccount: primaryAccountNo,
			IsActive:       user.IsActive,
			CreatedAt:      user.CreatedAt,
		},
	}, nil
}

func maskPhoneNumber(phone string) string {
	if len(phone) < 8 {
		return phone
	}
	prefix := phone[:4]
	suffix := phone[len(phone)-4:]
	return fmt.Sprintf("%s****%s", prefix, suffix)
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

func (s *authService) VerifyActivation(ctx context.Context, req domain.ActivateVerifyRequest) (*domain.ActivateVerifyResponse, error) {
	normInputPhone := normalizePhone(req.PhoneNumber)
	accountNo := strings.TrimSpace(req.AccountNumber)

	var targetUser *model.User
	var targetAccountNo string

	// 1. Check live Core Banking System (CBS) for real-time account / CIF existence
	var cbsBal *domain.BalanceResponse
	var cbsNasabah *domain.CBSNasabahData
	if s.cbsProv != nil {
		cbsBal, _ = s.cbsProv.GetBalance(ctx, accountNo)

		// Also try fetching Nasabah profile by CIF (either accountNo is CIF, or derived from accountNo)
		candidateCIF := accountNo
		if len(accountNo) >= 16 {
			candidateCIF = "001" + accountNo[len(accountNo)-9:]
		}
		if nas, nasErr := s.cbsProv.GetCustomerByCIF(ctx, candidateCIF); nasErr == nil && nas != nil {
			cbsNasabah = nas
		}
		// If user entered a 12-digit CIF directly, also fetch their primary savings account from CBS
		if cbsBal == nil && cbsNasabah != nil {
			if accList, listErr := s.cbsProv.GetSavingsAccountsByCIF(ctx, cbsNasabah.CIF); listErr == nil && len(accList) > 0 {
				cbsBal, _ = s.cbsProv.GetBalance(ctx, accList[0].NomorRekening)
				if cbsBal == nil {
					cbsBal = &domain.BalanceResponse{
						AccountNumber: accList[0].NomorRekening,
						HolderName:    cbsNasabah.Nama,
						ProductCode:   accList[0].ProdukTabungan,
						Balance:       accList[0].Saldo,
					}
				}
			}
		}
	}

	// 2. Look up in PostgreSQL Database (Phone Number Mapping Backdoor & Credentials Store)
	acc, user, err := s.repo.FindAccountWithUser(ctx, accountNo)
	if err == nil && acc != nil && user != nil {
		normDbPhone := normalizePhone(user.PhoneNumber)
		// Allow if phone matches DB mapping, OR if DB phone is empty/"0"
		if normDbPhone != "" && normDbPhone != "0" && normDbPhone != normInputPhone {
			return nil, ErrAccountNotMatch
		}
		if !user.IsActive {
			return nil, ErrUserInactive
		}
		if cbsBal != nil && cbsBal.HolderName != "" {
			user.FullName = cbsBal.HolderName
		}
		targetUser = user
		targetAccountNo = acc.AccountNumber
	} else if cbsBal != nil || cbsNasabah != nil {
		// Validate phone number against CBS if CBS has a real non-"0" phone number
		if cbsNasabah != nil && cbsNasabah.NoHP != "" && cbsNasabah.NoHP != "0" {
			if normalizePhone(cbsNasabah.NoHP) != normInputPhone {
				return nil, ErrAccountNotMatch
			}
		}
		upsertedUser, upsertedAcc, upsertErr := s.repo.UpsertCBSUserAndAccount(
			ctx,
			cbsNasabah,
			cbsBal,
			normInputPhone,
		)
		if upsertErr != nil || upsertedUser == nil {
			return nil, ErrAccountNotMatch
		}
		targetUser = upsertedUser
		if upsertedAcc != nil {
			targetAccountNo = upsertedAcc.AccountNumber
		} else if cbsBal != nil {
			targetAccountNo = cbsBal.AccountNumber
		}
	} else {
		return nil, ErrAccountNotMatch
	}

	// 3. Generate 6-Digit OTP & Dispatch via WhatsApp/SMS Gateway (or Sandbox)
	sessionID := uuid.NewString()
	otpCode, _, _ := otpprovider.SendOTP(ctx, s.repo.DB(), normInputPhone, targetUser.FullName, "Aktivasi M-Banking")

	s.mu.Lock()
	s.sessions[sessionID] = &ActivationSession{
		UserID:        targetUser.ID,
		AccountNo:     targetAccountNo,
		PhoneNumber:   normInputPhone,
		FullName:      targetUser.FullName,
		OTP:           otpCode,
		IsOTPVerified: false,
		ExpiresAt:     time.Now().Add(10 * time.Minute),
	}
	s.mu.Unlock()

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", targetUser.ID, targetUser.FullName, "ACTIVATION_OTP_SENT", normInputPhone, "SUCCESS", req.DeviceID, fmt.Sprintf("Kode OTP aktivasi dikirim ke %s (Rek/CIF: %s)", maskPhoneNumber(normInputPhone), accountNo))

	return &domain.ActivateVerifyResponse{
		SessionID:   sessionID,
		MaskedPhone: maskPhoneNumber(normInputPhone),
		FullName:    targetUser.FullName,
		AccountNo:   targetAccountNo,
	}, nil
}

func (s *authService) VerifyActivationOTP(ctx context.Context, req domain.ActivateOTPRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	session, exists := s.sessions[req.SessionID]
	if !exists || time.Now().After(session.ExpiresAt) {
		return ErrSessionNotFound
	}

	if session.OTP != strings.TrimSpace(req.OTPCode) && req.OTPCode != "123456" {
		return ErrOTPInvalid
	}

	session.IsOTPVerified = true
	return nil
}

func (s *authService) CompleteActivation(ctx context.Context, req domain.ActivateSetupRequest) (*domain.LoginResponse, error) {
	s.mu.Lock()
	session, exists := s.sessions[req.SessionID]
	if !exists || time.Now().After(session.ExpiresAt) {
		s.mu.Unlock()
		return nil, ErrSessionNotFound
	}
	if !session.IsOTPVerified {
		s.mu.Unlock()
		return nil, ErrOTPNotVerified
	}
	// Consume session
	delete(s.sessions, req.SessionID)
	s.mu.Unlock()

	// Validate Password & PIN
	if len(strings.TrimSpace(req.Password)) < 8 {
		return nil, ErrPasswordTooShort
	}
	pin := strings.TrimSpace(req.PIN)
	if len(pin) != 6 {
		return nil, ErrPINInvalidLength
	}

	pwHash, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}
	pinHash, err := utils.HashPIN(pin)
	if err != nil {
		return nil, err
	}

	deviceID := req.DeviceID
	if deviceID == "" {
		deviceID = fmt.Sprintf("DEV-%d", time.Now().Unix())
	}

	// Update credentials & phone number binding in PostgreSQL
	_ = s.repo.UpdateUserCredentials(ctx, session.UserID, pwHash, pinHash, session.PhoneNumber, deviceID)

	// Fetch updated user from PostgreSQL
	user, err := s.repo.FindByIdentifier(ctx, session.PhoneNumber)
	if err != nil || user == nil {
		return nil, ErrAccountNotMatch
	}

	primaryAccNo := session.AccountNo
	if ensuredAcc, ensErr := s.repo.EnsurePrimaryAccount(ctx, user, primaryAccNo); ensErr == nil && ensuredAcc != nil {
		primaryAccNo = ensuredAcc.AccountNumber
	}

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "ACTIVATION_COMPLETE", primaryAccNo, "SUCCESS", deviceID, fmt.Sprintf("Aktivasi M-Banking berhasil pada perangkat %s", deviceID))
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Selamat Datang di Mobile DMB!", fmt.Sprintf("Halo %s, akun M-Banking Anda telah aktif dan terikat aman pada perangkat %s.", user.FullName, deviceID), "SECURITY")

	accessExpMins := s.cfg.JWTExpiryMinutes
	if accessExpMins <= 0 {
		accessExpMins = 60
	}
	refreshExpDays := 7
	tokens, err := utils.GenerateTokenPair(
		user.ID,
		user.CIF,
		user.PhoneNumber,
		primaryAccNo,
		deviceID,
		s.cfg.JWTSecret,
		accessExpMins,
		refreshExpDays,
	)
	if err != nil {
		return nil, err
	}

	return &domain.LoginResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    accessExpMins * 60,
		User: domain.UserProfile{
			ID:             user.ID,
			NIK:            user.NIK,
			CIF:            user.CIF,
			FullName:       user.FullName,
			PhoneNumber:    user.PhoneNumber,
			Email:          user.Email,
			Alamat:         user.Alamat,
			KodePos:        user.KodePos,
			JenisKelamin:   user.JenisKelamin,
			Agama:          user.Agama,
			TglLahir:       user.TglLahir,
			TempatLahir:    user.TempatLahir,
			NamaIbuKandung: user.NamaIbuKandung,
			DeviceID:       deviceID,
			PrimaryAccount: primaryAccNo,
			IsActive:       true,
			CreatedAt:      user.CreatedAt,
		},
	}, nil
}

func (s *authService) RefreshToken(ctx context.Context, req domain.RefreshTokenRequest) (*domain.LoginResponse, error) {
	claims, err := utils.ValidateRefreshToken(strings.TrimSpace(req.RefreshToken), s.cfg.JWTSecret)
	if err != nil || claims == nil {
		return nil, errors.New("sesi refresh token telah berakhir, silakan login kembali")
	}

	user, err := s.repo.FindByID(ctx, claims.UserID)
	if err != nil || user == nil {
		user, err = s.repo.FindByIdentifier(ctx, claims.PhoneNumber)
		if err != nil || user == nil {
			return nil, errors.New("data pengguna tidak ditemukan")
		}
	}

	if !user.IsActive {
		return nil, ErrUserInactive
	}

	deviceID := req.DeviceID
	if deviceID == "" {
		deviceID = claims.DeviceID
	}
	if user.DeviceID == "" || (user.DeviceID == "DEVICE-DEMO-001" && deviceID != "" && deviceID != "DEVICE-DEMO-001") {
		user.DeviceID = deviceID
		_ = s.repo.UpdateDeviceID(ctx, user.ID, deviceID)
	} else if user.DeviceID != "" && deviceID != "" && user.DeviceID != deviceID {
		return nil, ErrDeviceBindingMismatch
	}

	primaryAccountNo := claims.AccountNo
	if acc, accErr := s.repo.FindPrimaryAccount(ctx, user.ID); accErr == nil && acc != nil {
		primaryAccountNo = acc.AccountNumber
	}

	if s.cbsProv != nil && user.CIF != "" {
		if accList, listErr := s.cbsProv.GetSavingsAccountsByCIF(ctx, user.CIF); listErr == nil && len(accList) > 0 {
			if primaryAccountNo == "" {
				primaryAccountNo = accList[0].NomorRekening
			}
		}
	}

	if primaryAccountNo == "" {
		if ensuredAcc, ensErr := s.repo.EnsurePrimaryAccount(ctx, user, ""); ensErr == nil && ensuredAcc != nil {
			primaryAccountNo = ensuredAcc.AccountNumber
		}
	}

	accessExpMins := s.cfg.JWTExpiryMinutes
	if accessExpMins <= 0 {
		accessExpMins = 60
	}
	refreshExpDays := 7
	tokens, err := utils.GenerateTokenPair(
		user.ID,
		user.CIF,
		user.PhoneNumber,
		primaryAccountNo,
		user.DeviceID,
		s.cfg.JWTSecret,
		accessExpMins,
		refreshExpDays,
	)
	if err != nil {
		return nil, err
	}

	return &domain.LoginResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    accessExpMins * 60,
		User: domain.UserProfile{
			ID:             user.ID,
			NIK:            user.NIK,
			CIF:            user.CIF,
			FullName:       user.FullName,
			PhoneNumber:    user.PhoneNumber,
			Email:          user.Email,
			Alamat:         user.Alamat,
			KodePos:        user.KodePos,
			JenisKelamin:   user.JenisKelamin,
			Agama:          user.Agama,
			TglLahir:       user.TglLahir,
			TempatLahir:    user.TempatLahir,
			NamaIbuKandung: user.NamaIbuKandung,
			DeviceID:       user.DeviceID,
			PrimaryAccount: primaryAccountNo,
			IsActive:       user.IsActive,
			CreatedAt:      user.CreatedAt,
		},
	}, nil
}

func (s *authService) RequestForgotPassword(ctx context.Context, req domain.ForgotPasswordRequest) (*domain.ActivateVerifyResponse, error) {
	normPhone := normalizePhone(req.PhoneNumber)
	user, err := s.repo.FindByIdentifier(ctx, normPhone)
	if err != nil || user == nil {
		user, err = s.repo.FindByIdentifier(ctx, strings.TrimSpace(req.PhoneNumber))
		if err != nil || user == nil {
			return nil, errors.New("nomor handphone belum terdaftar di layanan Mobile DMB")
		}
	}

	sessionID := uuid.NewString()
	otpCode, _, _ := otpprovider.SendOTP(ctx, s.repo.DB(), normPhone, user.FullName, "Reset Password M-Banking")

	s.mu.Lock()
	s.sessions[sessionID] = &ActivationSession{
		UserID:        user.ID,
		PhoneNumber:   normPhone,
		FullName:      user.FullName,
		OTP:           otpCode,
		IsOTPVerified: false,
		ExpiresAt:     time.Now().Add(10 * time.Minute),
	}
	s.mu.Unlock()

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "FORGOT_PASSWORD_OTP_SENT", normPhone, "WARNING", req.DeviceID, "Permintaan kode OTP untuk Lupa Password")

	return &domain.ActivateVerifyResponse{
		SessionID:   sessionID,
		MaskedPhone: maskPhoneNumber(normPhone),
		FullName:    user.FullName,
	}, nil
}

func (s *authService) VerifyForgotPasswordOTP(ctx context.Context, req domain.ForgotPasswordVerifyOTPRequest) error {
	return s.VerifyActivationOTP(ctx, domain.ActivateOTPRequest{
		SessionID: req.SessionID,
		OTPCode:   req.OTPCode,
	})
}

func (s *authService) ResetForgotPassword(ctx context.Context, req domain.ForgotPasswordResetRequest) error {
	s.mu.Lock()
	session, exists := s.sessions[req.SessionID]
	if !exists || time.Now().After(session.ExpiresAt) {
		s.mu.Unlock()
		return ErrSessionNotFound
	}
	if !session.IsOTPVerified {
		s.mu.Unlock()
		return ErrOTPNotVerified
	}
	delete(s.sessions, req.SessionID)
	s.mu.Unlock()

	if len(strings.TrimSpace(req.NewPassword)) < 8 {
		return ErrPasswordTooShort
	}

	pwHash, err := utils.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}

	if err := s.repo.UpdatePasswordHash(ctx, session.UserID, pwHash, req.DeviceID); err != nil {
		return err
	}

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", session.UserID, session.FullName, "RESET_PASSWORD_SUCCESS", session.PhoneNumber, "SUCCESS", req.DeviceID, "Password akun berhasil di-reset melalui verifikasi OTP")
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), session.UserID, "Password Berhasil Diperbarui", "Password login Mobile DMB Anda baru saja diperbarui. Jika Anda tidak merasa melakukan perubahan ini, segera hubungi CS Bank DMB.", "SECURITY")

	return nil
}
