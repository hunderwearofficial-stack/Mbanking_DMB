package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"mbanking-bpr/pkg/money"
	"net/url"
	"regexp"
	"strings"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/admin/repository"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/session"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/reqctx"
	"mbanking-bpr/pkg/security"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrAdminInvalidCredentials = errors.New("username atau password petugas salah")
	ErrAdminAccountDisabled    = errors.New("akun petugas telah dinonaktifkan")
	ErrAdminAccountLocked      = errors.New("Akun petugas sedang terkunci sementara karena terlalu banyak percobaan gagal. Silakan coba kembali beberapa saat lagi.")
	ErrAdminDefaultPassword    = errors.New("password petugas adalah password bawaan yang terpublikasi dan telah dinonaktifkan. Reset melalui prosedur bootstrap (ADMIN_BOOTSTRAP_*)")
	ErrBannerNotFound          = errors.New("data banner tidak ditemukan")
	ErrCustomerNotFound        = errors.New("data nasabah tidak ditemukan")
	ErrInvalidRole             = errors.New("role petugas tidak valid (SUPER_ADMIN, CS, MARKETING, COMPLIANCE)")
	ErrSelfModification        = errors.New("petugas tidak dapat menonaktifkan atau menghapus akunnya sendiri")
	ErrLastSuperAdmin          = errors.New("tidak dapat menonaktifkan/menghapus SUPER_ADMIN aktif terakhir")
	ErrValidation              = errors.New("data tidak valid")
	ErrAdminMFARequired        = errors.New("kode autentikator (MFA 6 digit) wajib diisi")
	ErrAdminMFACodeInvalid     = errors.New("kode autentikator (MFA) tidak valid atau sudah digunakan")
	ErrApprovalNotFound        = errors.New("permintaan persetujuan tidak ditemukan")
	ErrMakerChecker            = errors.New("pembuat permintaan tidak dapat menyetujui atau menolak permintaannya sendiri")
)

type AdminLoginResult struct {
	Token                  string
	MFASetupRequired       bool
	PasswordChangeRequired bool
	MFASetupToken          string
	ExpiresAt              time.Time
	Admin                  *model.AdminUser
}

type MFASetupInfo struct {
	Secret          string `json:"secret"`
	ProvisioningURI string `json:"provisioning_uri"`
	Issuer          string `json:"issuer"`
	Account         string `json:"account"`
}

type ConfigUpdateResult struct {
	Config          *model.AppConfig       `json:"config"`
	ApprovalRequest *model.ApprovalRequest `json:"approval_request,omitempty"`
}

type AppConfigUpdate struct {
	BankName             string  `json:"bank_name"`
	BankShortName        string  `json:"bank_short_name"`
	Tagline              string  `json:"tagline"`
	LogoURL              string  `json:"logo_url"`
	LoginBgURL           string  `json:"login_bg_url"`
	SplashBgURL          string  `json:"splash_bg_url"`
	OnboardingBgURL      string  `json:"onboarding_bg_url"`
	WelcomeTitle         string  `json:"welcome_title"`
	WelcomeSubtitle      string  `json:"welcome_subtitle"`
	LoginTitle           string  `json:"login_title"`
	LoginSubtitle        string  `json:"login_subtitle"`
	TermsVersion         string  `json:"terms_version"`
	HomeGreeting         string  `json:"home_greeting"`
	AnnouncementText     string  `json:"announcement_text"`
	TermsPdfURL          string  `json:"terms_pdf_url"`
	PrivacyPdfURL        string  `json:"privacy_pdf_url"`
	QuickMenuConfig      string  `json:"quick_menu_config"`
	CallCenter           string  `json:"call_center"`
	WhatsAppCS           string  `json:"whatsapp_cs"`
	EmailCS              string  `json:"email_cs"`
	WebsiteURL           string  `json:"website_url"`
	HeadOfficeAddress    string  `json:"head_office_address"`
	MaintenanceMode      bool    `json:"maintenance_mode"`
	MaintenanceMessage   string  `json:"maintenance_message"`
	EnforceDeviceBinding *bool   `json:"enforce_device_binding"`
	MaxLoginAttempts     int     `json:"max_login_attempts"`
	OTPProvider          string  `json:"otp_provider"`
	OTPGatewayURL        string  `json:"otp_gateway_url"`
	OTPGatewayToken      *string `json:"otp_gateway_token"` // write-only
	ClearOTPGatewayToken bool    `json:"clear_otp_gateway_token"`
}

type BannerInput struct {
	Title        string `json:"title"`
	ImageURL     string `json:"image_url"`
	TargetUrl    string `json:"target_url"`
	DisplayOrder int    `json:"display_order"`
	IsActive     bool   `json:"is_active"`
	Tag          string `json:"tag"`
	Highlight    string `json:"highlight"`
	BadgeText    string `json:"badge_text"`
	BgColor      string `json:"bg_color"`
	AccentColor  string `json:"accent_color"`
	IconName     string `json:"icon_name"`
}

type AdminService interface {
	Login(ctx context.Context, username, password, totpCode string) (*AdminLoginResult, error)
	SetupMFA(ctx context.Context, adminID string) (*MFASetupInfo, error)
	ConfirmMFA(ctx context.Context, adminID, code string) (*AdminLoginResult, error)
	SetInitialPassword(ctx context.Context, adminID, newPassword string) (*AdminLoginResult, error)
	ResetAdminMFA(ctx context.Context, targetID string) (*model.ApprovalRequest, error)
	Logout(ctx context.Context)
	IsProductionLike() bool
	DB() *gorm.DB
	GetDashboardStats(ctx context.Context) (map[string]interface{}, error)

	ListCustomers(ctx context.Context, search string, page, limit int) ([]repository.CustomerSummary, int64, error)
	ResetCustomerDevice(ctx context.Context, userID string) error
	ToggleCustomerActive(ctx context.Context, userID string, isActive bool) error
	RequestResetCustomerDevice(ctx context.Context, userID string) (*model.ApprovalRequest, error)
	RequestCustomerUnblock(ctx context.Context, userID string) (*model.ApprovalRequest, error)

	ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error)
	CreateBanner(ctx context.Context, in BannerInput) (*model.Banner, *model.ApprovalRequest, error)
	UpdateBanner(ctx context.Context, id string, in BannerInput) (*model.Banner, *model.ApprovalRequest, error)
	DeleteBanner(ctx context.Context, id string) error

	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, *model.ApprovalRequest, error)
	UpdateAdminUser(ctx context.Context, id, fullName, email, role, password string) (*model.AdminUser, *model.ApprovalRequest, error)
	// ChangeOwnPassword returns a fresh session: the change ends every earlier session (MA-12).
	ChangeOwnPassword(ctx context.Context, oldPassword, newPassword string) (*AdminLoginResult, error)
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) (*model.ApprovalRequest, error)
	DeleteAdminUser(ctx context.Context, id string) error

	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, in AppConfigUpdate) (*ConfigUpdateResult, error)

	ListApprovals(ctx context.Context, status string, limit int) ([]model.ApprovalRequest, error)
	ApproveRequest(ctx context.Context, id, note string) (*model.ApprovalRequest, error)
	RejectRequest(ctx context.Context, id, note string) (*model.ApprovalRequest, error)

	ListAuditLogs(ctx context.Context, filter repository.AuditLogFilter) ([]model.AuditLog, error)

	ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error)
	UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error)
}

type adminService struct {
	cfg      *config.Config
	repo     repository.AdminRepository
	sessions *session.Manager
	dummy    string
}

func NewAdminService(cfg *config.Config, repo repository.AdminRepository, sessions *session.Manager) AdminService {
	dummy, _ := security.HashPassword(uuid.NewString())
	return &adminService{cfg: cfg, repo: repo, sessions: sessions, dummy: dummy}
}

func (s *adminService) audit(ctx context.Context, action, target, status, details string) {
	audit.Record(ctx, s.repo.DB(), "ADMIN", "", "", action, target, status, "WEB-BACKOFFICE", details)
}

func currentAdminID(ctx context.Context) string {
	if a, ok := reqctx.AdminFrom(ctx); ok {
		return a.ID
	}
	return ""
}

var (
	colorPattern = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)
)

func limitLen(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		return s[:n]
	}
	return s
}

func validHTTPSURL(raw string, allowRelative bool) bool {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return true
	}
	if allowRelative && strings.HasPrefix(raw, "/") && !strings.HasPrefix(raw, "//") {
		return true
	}
	u, err := url.Parse(raw)
	return err == nil && u.Scheme == "https" && u.Host != ""
}

func (s *adminService) IsProductionLike() bool {
	return s.cfg != nil && s.cfg.IsProductionLike()
}

func (s *adminService) DB() *gorm.DB {
	return s.repo.DB()
}

func (s *adminService) Logout(ctx context.Context) {
	target := "UNKNOWN"
	if a, ok := reqctx.AdminFrom(ctx); ok && a.Username != "" {
		target = a.Username
	}
	s.audit(ctx, "ADMIN_LOGOUT", target, "SUCCESS", "Logout konsol backoffice")
}

func (s *adminService) Login(ctx context.Context, username, password, totpCode string) (*AdminLoginResult, error) {
	admin, err := s.repo.FindByUsername(ctx, strings.TrimSpace(username))
	if err != nil || admin == nil {
		security.CheckPassword(s.dummy, password)
		audit.Record(ctx, s.repo.DB(), "ADMIN", "UNKNOWN", limitLen(username, 50), "ADMIN_LOGIN_FAILED", limitLen(username, 50), "WARNING", "WEB-BACKOFFICE", "Login backoffice gagal: username tidak dikenal")
		return nil, ErrAdminInvalidCredentials
	}
	if admin.LockedUntil != nil && admin.LockedUntil.After(time.Now()) {
		audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_LOGIN_LOCKED", admin.Username, "WARNING", "WEB-BACKOFFICE", "Percobaan login saat akun petugas terkunci sementara")
		return nil, ErrAdminAccountLocked
	}
	if !security.CheckPassword(admin.PasswordHash, password) {
		maxFailed := 5
		lockMinutes := 15
		if s.cfg != nil {
			if s.cfg.AdminMaxFailedLogin > 0 {
				maxFailed = s.cfg.AdminMaxFailedLogin
			}
			if s.cfg.AdminLockoutMinutes > 0 {
				lockMinutes = s.cfg.AdminLockoutMinutes
			}
		}
		lockedUntil, attempts, _ := s.repo.RecordAdminLoginFailure(ctx, admin.ID, maxFailed, time.Duration(lockMinutes)*time.Minute)
		if lockedUntil != nil {
			audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_LOGIN_LOCKED", admin.Username, "DANGER", "WEB-BACKOFFICE",
				fmt.Sprintf("Akun petugas dikunci sementara karena %dx salah password", attempts))
			return nil, ErrAdminAccountLocked
		}
		audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_LOGIN_FAILED", admin.Username, "WARNING", "WEB-BACKOFFICE",
			fmt.Sprintf("Login backoffice gagal: password salah (Percobaan %d/%d)", attempts, maxFailed))
		return nil, ErrAdminInvalidCredentials
	}
	if !admin.IsActive {
		return nil, ErrAdminAccountDisabled
	}
	if security.IsCompromisedCredential(password) {
		audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_LOGIN_DEFAULT_PASSWORD_REFUSED", admin.Username, "DANGER", "WEB-BACKOFFICE", "Login dengan password bawaan yang terpublikasi ditolak")
		return nil, ErrAdminDefaultPassword
	}
	if !model.IsValidAdminRole(admin.Role) {
		return nil, ErrInvalidRole
	}

	if admin.TOTPEnabled {
		code := strings.TrimSpace(totpCode)
		if code == "" {
			return nil, ErrAdminMFARequired
		}
		secret, decErr := crypto.DecryptString(admin.TOTPSecret)
		if decErr != nil || secret == "" {
			return nil, ErrAdminMFACodeInvalid
		}
		step, ok := security.VerifyTOTP(secret, code, time.Now(), admin.TOTPLastStep)
		if !ok {
			maxFailed := 5
			lockMinutes := 15
			if s.cfg != nil {
				if s.cfg.AdminMaxFailedLogin > 0 {
					maxFailed = s.cfg.AdminMaxFailedLogin
				}
				if s.cfg.AdminLockoutMinutes > 0 {
					lockMinutes = s.cfg.AdminLockoutMinutes
				}
			}
			lockedUntil, attempts, _ := s.repo.RecordAdminLoginFailure(ctx, admin.ID, maxFailed, time.Duration(lockMinutes)*time.Minute)
			if lockedUntil != nil {
				audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_LOGIN_LOCKED", admin.Username, "DANGER", "WEB-BACKOFFICE",
					fmt.Sprintf("Akun petugas dikunci sementara karena %dx salah kode MFA TOTP", attempts))
				return nil, ErrAdminAccountLocked
			}
			audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_MFA_FAILED", admin.Username, "WARNING", "WEB-BACKOFFICE",
				fmt.Sprintf("Kode MFA TOTP salah atau sudah digunakan (Percobaan %d/%d)", attempts, maxFailed))
			return nil, ErrAdminMFACodeInvalid
		}
		advanced, advErr := s.repo.AdvanceAdminTOTPStep(ctx, admin.ID, step)
		if advErr != nil || !advanced {
			return nil, ErrAdminMFACodeInvalid
		}
	}

	// MA-03: an officer whose password was issued by someone else, or who has no MFA yet,
	// gets only a short-lived setup token: first the password change, then MFA enrolment.
	needMFA := s.mfaRequiredFor(admin)
	if admin.MustChangePassword || needMFA {
		_ = s.repo.ResetAdminLoginFailures(ctx, admin.ID)
		setupTok, exp, err := security.GenerateAdminTokenOfType(security.TokenTypeAdminMFASetup, admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret, 10*time.Minute)
		if err != nil {
			return nil, err
		}
		detail := "Petugas wajib menyelesaikan pendaftaran MFA TOTP"
		if admin.MustChangePassword {
			detail = "Petugas wajib mengganti kata sandi awal sebelum dapat menggunakan konsol"
		}
		audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_SETUP_REQUIRED", admin.Username, "WARNING", "WEB-BACKOFFICE", detail)
		return &AdminLoginResult{
			MFASetupRequired: needMFA, PasswordChangeRequired: admin.MustChangePassword,
			MFASetupToken: setupTok, ExpiresAt: exp, Admin: admin,
		}, nil
	}

	_ = s.repo.ResetAdminLoginFailures(ctx, admin.ID)
	token, exp, err := security.GenerateAdminToken(admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret,
		time.Duration(s.cfg.AdminJWTExpiryMinutes)*time.Minute)
	if err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username+" ("+admin.Role+")", "ADMIN_LOGIN", admin.Username, "SUCCESS", "WEB-BACKOFFICE", "Login konsol backoffice")
	return &AdminLoginResult{Token: token, ExpiresAt: exp, Admin: admin}, nil
}

// mfaRequiredFor: MFA enrolment is pending for this officer.
func (s *adminService) mfaRequiredFor(admin *model.AdminUser) bool {
	return s.cfg != nil && s.cfg.AdminMFARequired && !admin.TOTPEnabled
}

// ErrAdminPasswordChangeFirst: MFA enrolment starts only after the issued password is replaced.
var ErrAdminPasswordChangeFirst = errors.New("ganti kata sandi awal terlebih dahulu sebelum mendaftarkan MFA")

func (s *adminService) SetupMFA(ctx context.Context, adminID string) (*MFASetupInfo, error) {
	admin, err := s.repo.FindAdminByID(ctx, adminID)
	if err != nil || admin == nil || !admin.IsActive {
		return nil, ErrValidation
	}
	if admin.MustChangePassword {
		return nil, ErrAdminPasswordChangeFirst
	}
	if admin.TOTPEnabled {
		return nil, fmt.Errorf("%w: MFA sudah aktif untuk petugas ini", ErrValidation)
	}
	secret, err := security.NewTOTPSecret()
	if err != nil {
		return nil, err
	}
	enc, err := crypto.EncryptString(secret)
	if err != nil {
		return nil, err
	}
	if err := s.repo.SetAdminTOTP(ctx, admin.ID, enc, false, 0); err != nil {
		return nil, err
	}
	issuer := "DMB Backoffice"
	return &MFASetupInfo{
		Secret:          secret,
		ProvisioningURI: security.TOTPProvisioningURI(issuer, admin.Username, secret),
		Issuer:          issuer,
		Account:         admin.Username,
	}, nil
}

func (s *adminService) ConfirmMFA(ctx context.Context, adminID, code string) (*AdminLoginResult, error) {
	admin, err := s.repo.FindAdminByID(ctx, adminID)
	if err != nil || admin == nil || !admin.IsActive {
		return nil, ErrValidation
	}
	if admin.MustChangePassword {
		return nil, ErrAdminPasswordChangeFirst
	}
	secret, err := crypto.DecryptString(admin.TOTPSecret)
	if err != nil || secret == "" {
		return nil, fmt.Errorf("%w: silakan mulai ulang setup MFA", ErrValidation)
	}
	step, ok := security.VerifyTOTP(secret, code, time.Now(), admin.TOTPLastStep)
	if !ok {
		return nil, ErrAdminMFACodeInvalid
	}
	if err := s.repo.SetAdminTOTP(ctx, admin.ID, admin.TOTPSecret, true, step); err != nil {
		return nil, err
	}
	token, exp, err := security.GenerateAdminToken(admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret,
		time.Duration(s.cfg.AdminJWTExpiryMinutes)*time.Minute)
	if err != nil {
		return nil, err
	}
	admin.TOTPEnabled = true
	audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_MFA_ENABLED", admin.Username, "SUCCESS", "WEB-BACKOFFICE", "Pendaftaran MFA TOTP petugas aktif")
	return &AdminLoginResult{Token: token, ExpiresAt: exp, Admin: admin}, nil
}

// SetInitialPassword replaces a password issued by someone else (MA-03). It is reachable
// only with the setup token from Login. When MFA enrolment is still pending no session is
// issued (MFASetupRequired); otherwise the officer receives a normal session.
func (s *adminService) SetInitialPassword(ctx context.Context, adminID, newPassword string) (*AdminLoginResult, error) {
	admin, err := s.repo.FindAdminByID(ctx, adminID)
	if err != nil || admin == nil || !admin.IsActive {
		return nil, ErrValidation
	}
	if !admin.MustChangePassword {
		return nil, fmt.Errorf("%w: kata sandi tidak perlu diganti melalui jalur ini", ErrValidation)
	}
	if len(newPassword) < 12 {
		return nil, fmt.Errorf("%w: password baru petugas minimal 12 karakter", ErrValidation)
	}
	if err := security.ValidateNewPassword(newPassword); err != nil {
		return nil, err
	}
	if security.CheckPassword(admin.PasswordHash, newPassword) {
		return nil, fmt.Errorf("%w: password baru tidak boleh sama dengan password sementara", ErrValidation)
	}
	pwHash, err := security.HashPassword(newPassword)
	if err != nil {
		return nil, err
	}
	if err := s.repo.UpdateAdminPassword(ctx, admin.ID, pwHash); err != nil {
		return nil, err
	}
	admin.MustChangePassword = false
	audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username, "ADMIN_INITIAL_PASSWORD_CHANGED", admin.Username, "SUCCESS", "WEB-BACKOFFICE", "Petugas mengganti kata sandi awal")
	if s.mfaRequiredFor(admin) {
		return &AdminLoginResult{MFASetupRequired: true, Admin: admin}, nil
	}
	token, exp, err := security.GenerateAdminToken(admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret,
		time.Duration(s.cfg.AdminJWTExpiryMinutes)*time.Minute)
	if err != nil {
		return nil, err
	}
	return &AdminLoginResult{Token: token, ExpiresAt: exp, Admin: admin}, nil
}

func (s *adminService) ResetAdminMFA(ctx context.Context, targetID string) (*model.ApprovalRequest, error) {
	if err := s.guardAdminChange(ctx, targetID, false); err != nil {
		return nil, err
	}
	target, err := s.repo.FindAdminByID(ctx, targetID)
	if err != nil || target == nil {
		return nil, fmt.Errorf("%w: petugas tidak ditemukan", ErrValidation)
	}
	return s.createApproval(ctx, model.ApprovalAdminManage, targetID,
		fmt.Sprintf("Reset MFA TOTP akun petugas %s (%s)", target.Username, target.Role),
		map[string]interface{}{"action": "RESET_MFA", "target_id": targetID})
}

func (s *adminService) GetDashboardStats(ctx context.Context) (map[string]interface{}, error) {
	return s.repo.GetDashboardStats(ctx)
}

func (s *adminService) ListCustomers(ctx context.Context, search string, page, limit int) ([]repository.CustomerSummary, int64, error) {
	if page <= 0 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	return s.repo.ListCustomers(ctx, search, page, limit)
}

func (s *adminService) ResetCustomerDevice(ctx context.Context, userID string) error {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return ErrCustomerNotFound
	}
	if err := s.repo.ResetDeviceBinding(ctx, userID); err != nil {
		return err
	}
	if s.sessions != nil {
		_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAdminAction, "")
	}
	s.audit(ctx, "UNBIND_CUSTOMER_DEVICE", user.FullName+" ("+user.CIF+")", "WARNING",
		fmt.Sprintf("Unbind/Reset Device ID nasabah (perangkat sebelumnya: %s); kunci perangkat dicabut; seluruh sesi dicabut", user.DeviceID))
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Reset Perangkat Berhasil",
		"Ikatan perangkat akun Mobile DMB Anda telah di-reset oleh petugas Bank DMB. Verifikasi perangkat baru melalui menu Lupa Password.", "SECURITY")
	return nil
}

func (s *adminService) ToggleCustomerActive(ctx context.Context, userID string, isActive bool) error {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return ErrCustomerNotFound
	}
	if err := s.repo.ToggleCustomerStatus(ctx, userID, isActive); err != nil {
		return err
	}
	if isActive {
		s.audit(ctx, "UNBLOCK_CUSTOMER", user.FullName+" ("+user.CIF+")", "SUCCESS", "Membuka blokir akun nasabah & me-reset counter gagal login/PIN")
		notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Akun Telah Diaktifkan Kembali", "Akun Mobile DMB Anda telah diaktifkan kembali oleh Customer Service Bank DMB.", "SECURITY")
	} else {
		if s.sessions != nil {
			_ = s.sessions.RevokeAllForUser(ctx, user.ID, session.ReasonAccountBlocked, "")
		}
		s.audit(ctx, "BLOCK_CUSTOMER", user.FullName+" ("+user.CIF+")", "DANGER", "Memblokir akun nasabah secara manual; seluruh sesi dicabut")
	}
	return nil
}

func (s *adminService) ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error) {
	return s.repo.ListBanners(ctx, activeOnly)
}

func (s *adminService) validateBanner(in BannerInput) (*model.Banner, error) {
	b := &model.Banner{
		Title: limitLen(in.Title, 120), ImageURL: strings.TrimSpace(in.ImageURL),
		TargetUrl: strings.TrimSpace(in.TargetUrl), IsActive: in.IsActive, DisplayOrder: in.DisplayOrder,
		Tag: limitLen(in.Tag, 60), Highlight: limitLen(in.Highlight, 255),
		BadgeText: limitLen(in.BadgeText, 50), BgColor: strings.TrimSpace(in.BgColor), AccentColor: strings.TrimSpace(in.AccentColor),
		IconName: limitLen(in.IconName, 50),
	}
	if b.Title == "" {
		return nil, fmt.Errorf("%w: judul banner promosi wajib diisi", ErrValidation)
	}
	if b.ImageURL == "" {
		return nil, fmt.Errorf("%w: gambar banner promosi (image URL) wajib diisi atau diunggah", ErrValidation)
	}
	if !validHTTPSURL(b.ImageURL, true) {
		return nil, fmt.Errorf("%w: URL gambar banner tidak valid", ErrValidation)
	}
	if b.Tag == "" {
		b.Tag = "PROMO"
	}
	if b.BgColor == "" {
		b.BgColor = "#0A3B66"
	}
	if b.AccentColor == "" {
		b.AccentColor = "#16984B"
	}
	if b.TargetUrl != "" && !validHTTPSURL(b.TargetUrl, true) {
		return nil, fmt.Errorf("%w: target URL banner harus berupa URL valid (https:// atau path)", ErrValidation)
	}
	return b, nil
}

func (s *adminService) createApproval(ctx context.Context, kind, targetID, summary string, payload interface{}) (*model.ApprovalRequest, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	enc, err := crypto.EncryptString(string(raw))
	if err != nil {
		return nil, err
	}
	a, _ := reqctx.AdminFrom(ctx)
	req := &model.ApprovalRequest{
		ID:              uuid.NewString(),
		Kind:            kind,
		TargetID:        targetID,
		Summary:         limitLen(summary, 500),
		Payload:         enc,
		RequestedBy:     a.ID,
		RequestedByName: a.Username,
		RequestedByRole: a.Role,
	}
	if err := s.repo.CreateApproval(ctx, req); err != nil {
		return nil, err
	}
	s.audit(ctx, "APPROVAL_REQUESTED", kind+":"+targetID, "WARNING", summary)
	return req, nil
}

func (s *adminService) RequestResetCustomerDevice(ctx context.Context, userID string) (*model.ApprovalRequest, error) {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return nil, ErrCustomerNotFound
	}
	return s.createApproval(ctx, model.ApprovalDeviceReset, user.ID,
		fmt.Sprintf("Reset perangkat nasabah %s (%s)", user.FullName, user.CIF),
		map[string]string{"user_id": user.ID})
}

func (s *adminService) RequestCustomerUnblock(ctx context.Context, userID string) (*model.ApprovalRequest, error) {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return nil, ErrCustomerNotFound
	}
	return s.createApproval(ctx, model.ApprovalCustomerUnblock, user.ID,
		fmt.Sprintf("Buka blokir / aktifkan kembali akun %s (%s)", user.FullName, user.CIF),
		map[string]string{"user_id": user.ID})
}

func bannerContentHash(b *model.Banner) string {
	if b == nil {
		return ""
	}
	raw := fmt.Sprintf("%s|%s|%s|%d|%s|%s|%s|%s|%s|%s",
		b.Title, b.ImageURL, b.TargetUrl, b.DisplayOrder,
		b.Tag, b.Highlight, b.BadgeText, b.BgColor, b.AccentColor, b.IconName)
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func (s *adminService) CreateBanner(ctx context.Context, in BannerInput) (*model.Banner, *model.ApprovalRequest, error) {
	b, err := s.validateBanner(in)
	if err != nil {
		return nil, nil, err
	}
	wantActive := b.IsActive
	b.IsActive = false // C-04: banner never goes live without checker approval
	if err := s.repo.CreateBanner(ctx, b); err != nil {
		return nil, nil, err
	}
	s.audit(ctx, "CREATE_BANNER", b.Title, "SUCCESS", "Menambah draf banner promosi")
	var appr *model.ApprovalRequest
	if wantActive {
		appr, err = s.createApproval(ctx, model.ApprovalBannerPublish, b.ID,
			fmt.Sprintf("Publikasikan banner promosi: %s", b.Title),
			map[string]string{"banner_id": b.ID, "content_hash": bannerContentHash(b)})
		if err != nil {
			return b, nil, err
		}
	}
	return b, appr, nil
}

func (s *adminService) UpdateBanner(ctx context.Context, id string, in BannerInput) (*model.Banner, *model.ApprovalRequest, error) {
	existing, err := s.repo.GetBannerByID(ctx, id)
	if err != nil || existing == nil {
		return nil, nil, ErrBannerNotFound
	}
	b, err := s.validateBanner(in)
	if err != nil {
		return nil, nil, err
	}
	wantActive := b.IsActive
	b.ID = existing.ID
	b.CreatedAt = existing.CreatedAt
	// H-02: activating or modifying an active banner requires checker approval so active
	// promo content/links cannot be changed silently by a single officer.
	needsApproval := wantActive
	if needsApproval {
		b.IsActive = false
	}
	if err := s.repo.UpdateBanner(ctx, b); err != nil {
		return nil, nil, err
	}
	s.audit(ctx, "UPDATE_BANNER", b.Title, "SUCCESS", "Memperbarui banner promosi")
	var appr *model.ApprovalRequest
	if needsApproval {
		appr, err = s.createApproval(ctx, model.ApprovalBannerPublish, b.ID,
			fmt.Sprintf("Publikasikan perubahan banner promosi: %s", b.Title),
			map[string]string{"banner_id": b.ID, "content_hash": bannerContentHash(b)})
		if err != nil {
			return b, nil, err
		}
	}
	return b, appr, nil
}

func (s *adminService) DeleteBanner(ctx context.Context, id string) error {
	if err := s.repo.DeleteBanner(ctx, id); err != nil {
		return err
	}
	s.audit(ctx, "DELETE_BANNER", id, "WARNING", "Menghapus banner promosi")
	return nil
}

func (s *adminService) GetAppConfig(ctx context.Context) (*model.AppConfig, error) {
	return s.repo.GetAppConfig(ctx)
}

func (s *adminService) UpdateAppConfig(ctx context.Context, in AppConfigUpdate) (*ConfigUpdateResult, error) {
	current, err := s.repo.GetAppConfig(ctx)
	if err != nil || current == nil {
		return nil, fmt.Errorf("%w: konfigurasi belum tersedia", ErrValidation)
	}
	provider := strings.ToUpper(strings.TrimSpace(in.OTPProvider))
	switch provider {
	case "", "SANDBOX", "SANDBOX_DUMMY", "JATIS", "SMS_GATEWAY":
	default:
		return nil, fmt.Errorf("%w: penyedia OTP tidak dikenal", ErrValidation)
	}
	if provider == "" {
		provider = current.OTPProvider
	}
	if s.cfg != nil && s.cfg.IsProductionLike() && (provider == "SANDBOX" || provider == "SANDBOX_DUMMY") {
		return nil, fmt.Errorf("%w: mode %s OTP tidak diizinkan di lingkungan produksi", ErrValidation, provider)
	}
	if !validHTTPSURL(in.OTPGatewayURL, false) || !validHTTPSURL(in.WebsiteURL, false) ||
		!validHTTPSURL(in.LogoURL, true) || !validHTTPSURL(in.LoginBgURL, true) ||
		!validHTTPSURL(in.SplashBgURL, true) || !validHTTPSURL(in.OnboardingBgURL, true) ||
		!validHTTPSURL(in.TermsPdfURL, true) || !validHTTPSURL(in.PrivacyPdfURL, true) {
		return nil, fmt.Errorf("%w: alamat URL harus diawali https:// (atau path lokal)", ErrValidation)
	}
	// S-08: align validation to 3..10 matching backend runtime behavior
	if in.MaxLoginAttempts != 0 && (in.MaxLoginAttempts < 3 || in.MaxLoginAttempts > 10) {
		return nil, fmt.Errorf("%w: batas percobaan login harus antara 3 sampai 10", ErrValidation)
	}

	updated := *current
	if strings.TrimSpace(in.BankName) != "" {
		updated.BankName = limitLen(in.BankName, 120)
	}
	if strings.TrimSpace(in.BankShortName) != "" {
		updated.BankShortName = limitLen(in.BankShortName, 50)
	}
	if strings.TrimSpace(in.Tagline) != "" {
		updated.Tagline = limitLen(in.Tagline, 255)
	}
	updated.LogoURL = limitLen(in.LogoURL, 500)
	if strings.TrimSpace(in.LoginBgURL) != "" {
		updated.LoginBgURL = limitLen(in.LoginBgURL, 500)
	}
	if strings.TrimSpace(in.SplashBgURL) != "" {
		updated.SplashBgURL = limitLen(in.SplashBgURL, 500)
	}
	if strings.TrimSpace(in.OnboardingBgURL) != "" {
		updated.OnboardingBgURL = limitLen(in.OnboardingBgURL, 500)
	}
	if strings.TrimSpace(in.WelcomeTitle) != "" {
		updated.WelcomeTitle = limitLen(in.WelcomeTitle, 150)
	}
	if strings.TrimSpace(in.WelcomeSubtitle) != "" {
		updated.WelcomeSubtitle = limitLen(in.WelcomeSubtitle, 255)
	}
	if strings.TrimSpace(in.LoginTitle) != "" {
		updated.LoginTitle = limitLen(in.LoginTitle, 150)
	}
	if strings.TrimSpace(in.LoginSubtitle) != "" {
		updated.LoginSubtitle = limitLen(in.LoginSubtitle, 255)
	}
	if strings.TrimSpace(in.TermsVersion) != "" {
		updated.TermsVersion = limitLen(in.TermsVersion, 50)
	}
	if strings.TrimSpace(in.HomeGreeting) != "" {
		updated.HomeGreeting = limitLen(in.HomeGreeting, 150)
	}
	if strings.TrimSpace(in.AnnouncementText) != "" {
		updated.AnnouncementText = limitLen(in.AnnouncementText, 1000)
	}
	if strings.TrimSpace(in.TermsPdfURL) != "" {
		updated.TermsPdfURL = limitLen(in.TermsPdfURL, 500)
	}
	if strings.TrimSpace(in.PrivacyPdfURL) != "" {
		updated.PrivacyPdfURL = limitLen(in.PrivacyPdfURL, 500)
	}
	if strings.TrimSpace(in.QuickMenuConfig) != "" {
		updated.QuickMenuConfig = limitLen(in.QuickMenuConfig, 2000)
	}
	updated.CallCenter = limitLen(in.CallCenter, 50)
	updated.WhatsAppCS = limitLen(in.WhatsAppCS, 50)
	updated.EmailCS = limitLen(in.EmailCS, 100)
	updated.WebsiteURL = limitLen(in.WebsiteURL, 255)
	updated.HeadOfficeAddress = limitLen(in.HeadOfficeAddress, 500)
	updated.MaintenanceMode = in.MaintenanceMode
	updated.MaintenanceMessage = limitLen(in.MaintenanceMessage, 255)

	// S-09: EnforceDeviceBinding follows ENV DEVICE_BINDING_MODE ("enforced"), never a UI toggle.
	if s.cfg != nil {
		updated.EnforceDeviceBinding = s.cfg.DeviceBindingMode == "enforced"
	}

	// C-04: Security/OTP changes require Maker-Checker approval instead of immediate apply.
	secPayload := map[string]interface{}{}
	var secDiffs []string
	if provider != current.OTPProvider {
		secPayload["otp_provider"] = provider
		secDiffs = append(secDiffs, fmt.Sprintf("otp_provider: %q -> %q", current.OTPProvider, provider))
	}
	newGW := limitLen(in.OTPGatewayURL, 255)
	if newGW != current.OTPGatewayURL {
		secPayload["otp_gateway_url"] = newGW
		secDiffs = append(secDiffs, fmt.Sprintf("otp_gateway_url: %q -> %q", current.OTPGatewayURL, newGW))
	}
	if in.MaxLoginAttempts > 0 && in.MaxLoginAttempts != current.MaxLoginAttempts {
		secPayload["max_login_attempts"] = in.MaxLoginAttempts
		secDiffs = append(secDiffs, fmt.Sprintf("max_login_attempts: %d -> %d", current.MaxLoginAttempts, in.MaxLoginAttempts))
	}
	if in.ClearOTPGatewayToken {
		secPayload["clear_otp_gateway_token"] = true
		secDiffs = append(secDiffs, "otp_gateway_token: [CLEARED]")
	} else if in.OTPGatewayToken != nil {
		if t := strings.TrimSpace(*in.OTPGatewayToken); t != "" {
			secPayload["otp_gateway_token"] = t
			secDiffs = append(secDiffs, "otp_gateway_token: [UPDATED]")
		}
	}

	var diffs []string
	addDiff := func(name, oldVal, newVal string) {
		if oldVal != newVal {
			diffs = append(diffs, fmt.Sprintf("%s: %q -> %q", name, oldVal, newVal))
		}
	}
	addDiff("bank_name", current.BankName, updated.BankName)
	addDiff("bank_short_name", current.BankShortName, updated.BankShortName)
	addDiff("tagline", current.Tagline, updated.Tagline)
	addDiff("logo_url", current.LogoURL, updated.LogoURL)
	addDiff("call_center", current.CallCenter, updated.CallCenter)
	addDiff("whatsapp_cs", current.WhatsAppCS, updated.WhatsAppCS)
	addDiff("email_cs", current.EmailCS, updated.EmailCS)
	addDiff("website_url", current.WebsiteURL, updated.WebsiteURL)
	addDiff("head_office_address", current.HeadOfficeAddress, updated.HeadOfficeAddress)
	addDiff("maintenance_mode", fmt.Sprintf("%t", current.MaintenanceMode), fmt.Sprintf("%t", updated.MaintenanceMode))
	addDiff("maintenance_message", current.MaintenanceMessage, updated.MaintenanceMessage)

	// D-3: create approval request BEFORE saving non-security fields so a duplicate pending
	// CONFIG_SECURITY request fails cleanly without partial persistence.
	var appr *model.ApprovalRequest
	if len(secPayload) > 0 {
		appr, err = s.createApproval(ctx, model.ApprovalConfigSecurity, "app_config",
			"Perubahan konfigurasi keamanan/OTP: "+strings.Join(secDiffs, "; "),
			secPayload)
		if err != nil {
			return nil, err
		}
	}

	if len(diffs) > 0 {
		if err := s.repo.UpdateAppConfig(ctx, &updated); err != nil {
			return nil, err
		}
		s.audit(ctx, "UPDATE_CONFIG", updated.BankShortName, "SUCCESS",
			fmt.Sprintf("Memperbarui konfigurasi sistem: %s", strings.Join(diffs, "; ")))
	}
	return &ConfigUpdateResult{Config: &updated, ApprovalRequest: appr}, nil
}

func (s *adminService) ListApprovals(ctx context.Context, status string, limit int) ([]model.ApprovalRequest, error) {
	return s.repo.ListApprovals(ctx, status, limit)
}

func (s *adminService) ApproveRequest(ctx context.Context, id, note string) (*model.ApprovalRequest, error) {
	checker, _ := reqctx.AdminFrom(ctx)
	var revokeUserID string
	var notifyUnblockUserID string
	var notifyResetUserID string
	var auditAction, auditTarget, auditSummary string
	// MA-03: a password for an officer is generated here, on approval, and shown once to the
	// approving checker only, so the maker never knows it. issueTemp hashes it for storage.
	var issuedPassword string
	issueTemp := func() (string, error) {
		pw, err := security.GenerateTemporaryPassword()
		if err != nil {
			return "", err
		}
		issuedPassword = pw
		return security.HashPassword(pw)
	}

	decided, err := s.repo.RunApprovalTx(ctx, id, checker.ID, checker.Username, limitLen(note, 500), func(tx *gorm.DB, req *model.ApprovalRequest) error {
		plain, err := crypto.DecryptString(req.Payload)
		if err != nil {
			return fmt.Errorf("gagal mendekripsi payload persetujuan: %w", err)
		}

		switch req.Kind {
		case model.ApprovalConfigSecurity:
			var p map[string]interface{}
			if err := json.Unmarshal([]byte(plain), &p); err != nil {
				return err
			}
			var cur model.AppConfig
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&cur).Error; err != nil {
				return err
			}
			if v, ok := p["otp_provider"].(string); ok && v != "" {
				cur.OTPProvider = v
			}
			if v, ok := p["otp_gateway_url"].(string); ok {
				cur.OTPGatewayURL = v
			}
			if v, ok := p["max_login_attempts"].(float64); ok && int(v) >= 3 && int(v) <= 10 {
				cur.MaxLoginAttempts = int(v)
			}
			if clearTok, _ := p["clear_otp_gateway_token"].(bool); clearTok {
				cur.OTPGatewayToken = ""
			} else if tok, ok := p["otp_gateway_token"].(string); ok && tok != "" {
				enc, encErr := crypto.EncryptString(tok)
				if encErr != nil {
					return encErr
				}
				cur.OTPGatewayToken = enc
			}
			cur.UpdatedAt = time.Now()
			if err := tx.Save(&cur).Error; err != nil {
				return err
			}
			auditAction, auditTarget, auditSummary = "UPDATE_CONFIG_APPROVED", cur.BankShortName, req.Summary

		case model.ApprovalDeviceReset:
			var user model.User
			if err := tx.Where("id = ?", req.TargetID).First(&user).Error; err != nil {
				return ErrCustomerNotFound
			}
			if err := tx.Model(&model.User{}).Where("id = ?", req.TargetID).
				Updates(map[string]interface{}{"device_id": "", "device_enroll_until": nil, "updated_at": time.Now()}).Error; err != nil {
				return err
			}
			if _, err := devicebind.RevokeUserKeys(tx, req.TargetID, "ADMIN_RESET"); err != nil {
				return err
			}
			revokeUserID = req.TargetID
			notifyResetUserID = req.TargetID
			auditAction, auditTarget, auditSummary = "RESET_DEVICE_APPROVED", user.FullName+" ("+user.CIF+")", req.Summary

		case model.ApprovalCustomerUnblock:
			var user model.User
			if err := tx.Where("id = ?", req.TargetID).First(&user).Error; err != nil {
				return ErrCustomerNotFound
			}
			if err := tx.Model(&model.User{}).Where("id = ?", req.TargetID).Updates(map[string]interface{}{
				"is_active":             true,
				"failed_login_attempts": 0,
				"failed_pin_attempts":   0,
				"updated_at":            time.Now(),
			}).Error; err != nil {
				return err
			}
			notifyUnblockUserID = req.TargetID
			auditAction, auditTarget, auditSummary = "UNBLOCK_CUSTOMER_APPROVED", user.FullName+" ("+user.CIF+")", req.Summary

		case model.ApprovalBannerPublish:
			var p map[string]string
			_ = json.Unmarshal([]byte(plain), &p)
			var banner model.Banner
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", req.TargetID).First(&banner).Error; err != nil {
				return ErrBannerNotFound
			}
			if expectedHash := strings.TrimSpace(p["content_hash"]); expectedHash != "" && bannerContentHash(&banner) != expectedHash {
				return fmt.Errorf("%w: konten banner telah diubah setelah diajukan; silakan ajukan ulang persetujuan", ErrValidation)
			}
			if err := tx.Model(&model.Banner{}).Where("id = ?", req.TargetID).Updates(map[string]interface{}{
				"is_active":  true,
				"updated_at": time.Now(),
			}).Error; err != nil {
				return err
			}
			auditAction, auditTarget, auditSummary = "PUBLISH_BANNER_APPROVED", req.TargetID, req.Summary

		case model.ApprovalAdminManage:
			var p map[string]interface{}
			if err := json.Unmarshal([]byte(plain), &p); err != nil {
				return err
			}
			action, _ := p["action"].(string)
			switch action {
			case "RESET_MFA":
				if err := tx.Model(&model.AdminUser{}).Where("id = ?", req.TargetID).Updates(map[string]interface{}{
					"totp_secret":    "",
					"totp_enabled":   false,
					"totp_last_step": 0,
					"updated_at":     time.Now(),
				}).Error; err != nil {
					return err
				}
				auditAction, auditTarget, auditSummary = "RESET_ADMIN_MFA_APPROVED", req.TargetID, req.Summary
			case "CREATE_SUPER_ADMIN", "CREATE_CHECKER_ADMIN":
				username, _ := p["username"].(string)
				fullName, _ := p["full_name"].(string)
				email, _ := p["email"].(string)
				isActive, _ := p["is_active"].(bool)
				// Any password_hash in an older pending payload (chosen by the maker) is ignored.
				pwHash, err := issueTemp()
				if err != nil {
					return err
				}
				role, _ := p["role"].(string)
				if role == "" {
					role = model.AdminRoleSuperAdmin
				}
				if !model.IsValidAdminRole(role) {
					return ErrInvalidRole
				}
				var cnt int64
				if err := tx.Model(&model.AdminUser{}).Where("username = ?", username).Count(&cnt).Error; err != nil {
					return err
				}
				if cnt > 0 {
					return errors.New("username petugas sudah digunakan")
				}
				newAdmin := &model.AdminUser{
					ID: uuid.NewString(), Username: username, FullName: fullName, Email: email,
					PasswordHash: pwHash, Role: role, IsActive: isActive, MustChangePassword: true,
				}
				if err := tx.Create(newAdmin).Error; err != nil {
					return err
				}
				auditAction, auditTarget, auditSummary = "CREATE_CHECKER_ADMIN_APPROVED", username, req.Summary
			case "ACTIVATE_ADMIN":
				if err := tx.Model(&model.AdminUser{}).Where("id = ?", req.TargetID).Updates(map[string]interface{}{
					"is_active":  true,
					"updated_at": time.Now(),
				}).Error; err != nil {
					return err
				}
				auditAction, auditTarget, auditSummary = "ACTIVATE_ADMIN_APPROVED", req.TargetID, req.Summary
			case "PROMOTE_SUPER_ADMIN", "UPDATE_ADMIN_PRIVILEGED":
				updates := map[string]interface{}{
					"updated_at": time.Now(),
				}
				if role, _ := p["role"].(string); role != "" {
					if !model.IsValidAdminRole(role) {
						return ErrInvalidRole
					}
					updates["role"] = role
				} else if action == "PROMOTE_SUPER_ADMIN" {
					updates["role"] = model.AdminRoleSuperAdmin
				}
				if fn, _ := p["full_name"].(string); fn != "" {
					updates["full_name"] = fn
				}
				if em, ok := p["email"].(string); ok {
					updates["email"] = em
				}
				resetPw, _ := p["reset_password"].(bool)
				if legacy, _ := p["password_hash"].(string); legacy != "" {
					resetPw = true // older payload: the maker's chosen hash is replaced
				}
				if resetPw {
					pwHash, err := issueTemp()
					if err != nil {
						return err
					}
					updates["password_hash"] = pwHash
					updates["must_change_password"] = true
					updates["password_changed_at"] = time.Now()
					updates["failed_login_attempts"] = 0
					updates["locked_until"] = nil
				}
				if err := tx.Model(&model.AdminUser{}).Where("id = ?", req.TargetID).Updates(updates).Error; err != nil {
					return err
				}
				auditAction, auditTarget, auditSummary = "UPDATE_ADMIN_PRIVILEGED_APPROVED", req.TargetID, req.Summary
			default:
				return fmt.Errorf("%w: aksi pengelolaan admin tidak dikenal", ErrValidation)
			}

		default:
			return fmt.Errorf("%w: jenis persetujuan tidak dikenal", ErrValidation)
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, repository.ErrSelfApproval) {
			return nil, ErrMakerChecker
		}
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrApprovalNotFound
		}
		return nil, err
	}

	if revokeUserID != "" && s.sessions != nil {
		_ = s.sessions.RevokeAllForUser(ctx, revokeUserID, session.ReasonAdminAction, "")
	}
	if notifyResetUserID != "" {
		notification.CreateAndPush(ctx, s.repo.DB(), notifyResetUserID, "Reset Perangkat Berhasil",
			"Ikatan perangkat akun Mobile DMB Anda telah di-reset oleh petugas Bank DMB. Verifikasi perangkat baru melalui menu Lupa Password.", "SECURITY")
	}
	if notifyUnblockUserID != "" {
		notification.CreateAndPush(ctx, s.repo.DB(), notifyUnblockUserID, "Akun Telah Diaktifkan Kembali", "Akun Mobile DMB Anda telah diaktifkan kembali oleh Customer Service Bank DMB.", "SECURITY")
	}
	if auditAction != "" {
		s.audit(ctx, auditAction, auditTarget, "SUCCESS", auditSummary)
	}
	if issuedPassword != "" && decided != nil {
		decided.IssuedPassword = issuedPassword
		s.audit(ctx, "ADMIN_TEMP_PASSWORD_ISSUED", auditTarget, "WARNING",
			"Password sementara diterbitkan untuk petugas checker penyetuju; wajib diganti saat login pertama")
	}
	return decided, nil
}

func (s *adminService) RejectRequest(ctx context.Context, id, note string) (*model.ApprovalRequest, error) {
	req, err := s.repo.GetApproval(ctx, id)
	if err != nil || req == nil {
		return nil, ErrApprovalNotFound
	}
	if req.Status != model.ApprovalPending {
		return nil, fmt.Errorf("%w: permintaan ini sudah diputuskan (%s)", ErrValidation, req.Status)
	}
	checker, _ := reqctx.AdminFrom(ctx)
	if req.RequestedBy != "" && req.RequestedBy == checker.ID {
		return nil, ErrMakerChecker
	}
	decided, err := s.repo.DecideApproval(ctx, id, model.ApprovalRejected, checker.ID, checker.Username, limitLen(note, 500))
	if err != nil {
		return nil, err
	}
	s.audit(ctx, "APPROVAL_REJECTED", req.Kind+":"+req.TargetID, "WARNING", limitLen(note, 500))
	return decided, nil
}

func (s *adminService) ListAdminUsers(ctx context.Context) ([]model.AdminUser, error) {
	return s.repo.ListAdminUsers(ctx)
}

func (s *adminService) CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, *model.ApprovalRequest, error) {
	username = strings.TrimSpace(username)
	if len(username) < 4 || len(username) > 50 {
		return nil, nil, fmt.Errorf("%w: username petugas 4-50 karakter", ErrValidation)
	}
	role = strings.ToUpper(strings.TrimSpace(role))
	if !model.IsValidAdminRole(role) {
		return nil, nil, ErrInvalidRole // no implicit SUPER_ADMIN default
	}
	if existing, _ := s.repo.FindByUsername(ctx, username); existing != nil {
		return nil, nil, errors.New("username petugas sudah digunakan")
	}
	// C-1 / MA-03: creating a checker role (SUPER_ADMIN or COMPLIANCE) requires approval, and
	// its first password is generated by the system at approval time: the maker's input is
	// not used, so the maker can never sign in as the new checker.
	if role == model.AdminRoleSuperAdmin || role == model.AdminRoleCompliance {
		appr, err := s.createApproval(ctx, model.ApprovalAdminManage, username,
			fmt.Sprintf("Pendaftaran petugas checker (%s) baru: %s (%s)", role, username, limitLen(fullName, 100)),
			map[string]interface{}{
				"action":    "CREATE_CHECKER_ADMIN",
				"username":  username,
				"full_name": limitLen(fullName, 100),
				"email":     limitLen(email, 100),
				"role":      role,
				"is_active": isActive,
			})
		if err != nil {
			return nil, nil, err
		}
		return nil, appr, nil
	}
	if len(password) < 12 {
		return nil, nil, fmt.Errorf("%w: password petugas minimal 12 karakter", ErrValidation)
	}
	if err := security.ValidateNewPassword(password); err != nil {
		return nil, nil, err
	}
	pwHash, err := security.HashPassword(password)
	if err != nil {
		return nil, nil, err
	}
	// The password was chosen by the creating officer: the new officer must replace it.
	newAdmin := &model.AdminUser{
		Username: username, FullName: limitLen(fullName, 100), Email: limitLen(email, 100),
		PasswordHash: pwHash, Role: role, IsActive: isActive, MustChangePassword: true,
	}
	if err := s.repo.CreateAdminUser(ctx, newAdmin); err != nil {
		return nil, nil, err
	}
	s.audit(ctx, "CREATE_ADMIN_USER", username, "WARNING", fmt.Sprintf("Mendaftarkan petugas baru dengan role %s", role))
	return newAdmin, nil, nil
}

func (s *adminService) guardAdminChange(ctx context.Context, id string, deactivating bool) error {
	if id == currentAdminID(ctx) {
		return ErrSelfModification
	}
	target, err := s.repo.FindAdminByID(ctx, id)
	if err != nil || target == nil {
		return fmt.Errorf("%w: petugas tidak ditemukan", ErrValidation)
	}
	if deactivating && target.Role == model.AdminRoleSuperAdmin && target.IsActive {
		n, err := s.repo.CountActiveSuperAdmins(ctx, id)
		if err != nil {
			return err
		}
		if n == 0 {
			return ErrLastSuperAdmin
		}
	}
	return nil
}

func (s *adminService) ToggleAdminStatus(ctx context.Context, id string, isActive bool) (*model.ApprovalRequest, error) {
	if err := s.guardAdminChange(ctx, id, !isActive); err != nil {
		return nil, err
	}
	if isActive {
		target, err := s.repo.FindAdminByID(ctx, id)
		if err != nil || target == nil {
			return nil, fmt.Errorf("%w: petugas tidak ditemukan", ErrValidation)
		}
		appr, err := s.createApproval(ctx, model.ApprovalAdminManage, id,
			fmt.Sprintf("Aktifkan kembali akun petugas %s (%s)", target.Username, target.Role),
			map[string]interface{}{"action": "ACTIVATE_ADMIN", "target_id": id})
		if err != nil {
			return nil, err
		}
		return appr, nil
	}
	if err := s.repo.ToggleAdminStatus(ctx, id, isActive); err != nil {
		return nil, err
	}
	s.audit(ctx, "TOGGLE_ADMIN_STATUS", id, "WARNING", fmt.Sprintf("Status petugas diubah menjadi aktif=%t", isActive))
	return nil, nil
}

func (s *adminService) UpdateAdminUser(ctx context.Context, id, fullName, email, role, password string) (*model.AdminUser, *model.ApprovalRequest, error) {
	target, err := s.repo.FindAdminByID(ctx, id)
	if err != nil || target == nil {
		return nil, nil, fmt.Errorf("%w: petugas tidak ditemukan", ErrValidation)
	}
	role = strings.ToUpper(strings.TrimSpace(role))
	if role == "" {
		role = target.Role
	}
	if !model.IsValidAdminRole(role) {
		return nil, nil, ErrInvalidRole
	}
	if target.Role == model.AdminRoleSuperAdmin && role != model.AdminRoleSuperAdmin && target.IsActive {
		if id == currentAdminID(ctx) {
			return nil, nil, ErrSelfModification
		}
		n, err := s.repo.CountActiveSuperAdmins(ctx, id)
		if err != nil {
			return nil, nil, err
		}
		if n == 0 {
			return nil, nil, ErrLastSuperAdmin
		}
	}

	newFullName := limitLen(fullName, 100)
	if newFullName == "" {
		newFullName = target.FullName
	}
	newEmail := limitLen(email, 100)

	// MA-03: a non-empty password field only *requests* a reset. The new password is
	// generated by the system when a checker approves, so the requester never knows it.
	resetPassword := strings.TrimSpace(password) != ""
	pwHash := ""

	// C-1: promoting/changing role to any checker role (SUPER_ADMIN or COMPLIANCE) or
	// resetting another officer's password requires Maker-Checker approval.
	promotingToChecker := (role == model.AdminRoleSuperAdmin || role == model.AdminRoleCompliance) && target.Role != role
	if promotingToChecker || resetPassword {
		summary := fmt.Sprintf("Perubahan hak akses/sandi petugas %s", target.Username)
		switch {
		case promotingToChecker && resetPassword:
			summary = fmt.Sprintf("Ubah role petugas %s menjadi %s dan reset kata sandi", target.Username, role)
		case promotingToChecker:
			summary = fmt.Sprintf("Ubah role petugas %s menjadi %s", target.Username, role)
		default:
			summary = fmt.Sprintf("Reset kata sandi petugas %s", target.Username)
		}
		appr, err := s.createApproval(ctx, model.ApprovalAdminManage, id, summary,
			map[string]interface{}{
				"action":         "UPDATE_ADMIN_PRIVILEGED",
				"target_id":      id,
				"full_name":      newFullName,
				"email":          newEmail,
				"role":           role,
				"reset_password": resetPassword,
			})
		if err != nil {
			return nil, nil, err
		}
		return nil, appr, nil
	}

	if err := s.repo.UpdateAdminUser(ctx, id, newFullName, newEmail, role, pwHash); err != nil {
		return nil, nil, err
	}

	var diffs []string
	if target.FullName != newFullName {
		diffs = append(diffs, fmt.Sprintf("full_name: %q -> %q", target.FullName, newFullName))
	}
	if target.Email != newEmail {
		diffs = append(diffs, fmt.Sprintf("email: %q -> %q", target.Email, newEmail))
	}
	if target.Role != role {
		diffs = append(diffs, fmt.Sprintf("role: %q -> %q", target.Role, role))
	}
	if pwHash != "" {
		diffs = append(diffs, "password: [RESET_BY_SUPER_ADMIN]")
	}
	diffStr := "tidak ada perubahan"
	if len(diffs) > 0 {
		diffStr = strings.Join(diffs, "; ")
	}
	s.audit(ctx, "UPDATE_ADMIN_USER", target.Username, "WARNING", fmt.Sprintf("Memperbarui data petugas %s: %s", target.Username, diffStr))

	updated, err := s.repo.FindAdminByID(ctx, id)
	if err != nil {
		return nil, nil, err
	}
	return updated, nil, nil
}

func (s *adminService) ChangeOwnPassword(ctx context.Context, oldPassword, newPassword string) (*AdminLoginResult, error) {
	adminID := currentAdminID(ctx)
	if adminID == "" {
		return nil, ErrAdminInvalidCredentials
	}
	admin, err := s.repo.FindAdminByID(ctx, adminID)
	if err != nil || admin == nil {
		return nil, ErrAdminInvalidCredentials
	}
	if !security.CheckPassword(admin.PasswordHash, oldPassword) {
		s.audit(ctx, "ADMIN_CHANGE_PASSWORD_FAILED", admin.Username, "WARNING", "Gagal ganti password petugas: password lama salah")
		return nil, fmt.Errorf("%w: password lama yang Anda masukkan salah", ErrValidation)
	}
	if len(newPassword) < 12 {
		return nil, fmt.Errorf("%w: password baru petugas minimal 12 karakter", ErrValidation)
	}
	if err := security.ValidateNewPassword(newPassword); err != nil {
		return nil, err
	}
	if oldPassword == newPassword {
		return nil, fmt.Errorf("%w: password baru tidak boleh sama dengan password lama", ErrValidation)
	}
	pwHash, err := security.HashPassword(newPassword)
	if err != nil {
		return nil, err
	}
	if err := s.repo.UpdateAdminPassword(ctx, admin.ID, pwHash); err != nil {
		return nil, err
	}
	s.audit(ctx, "ADMIN_CHANGE_PASSWORD", admin.Username, "SUCCESS", "Petugas berhasil mengganti password akunnya sendiri; sesi lain dicabut")
	token, exp, err := security.GenerateAdminToken(admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret,
		time.Duration(s.cfg.AdminJWTExpiryMinutes)*time.Minute)
	if err != nil {
		return nil, err
	}
	return &AdminLoginResult{Token: token, ExpiresAt: exp, Admin: admin}, nil
}

func (s *adminService) DeleteAdminUser(ctx context.Context, id string) error {
	if err := s.guardAdminChange(ctx, id, true); err != nil {
		return err
	}
	if err := s.repo.ToggleAdminStatus(ctx, id, false); err != nil {
		return err
	}
	s.audit(ctx, "DISABLE_ADMIN_USER", id, "WARNING", "Menonaktifkan akun petugas (soft-disable untuk integritas audit)")
	return nil
}

func (s *adminService) ListAuditLogs(ctx context.Context, filter repository.AuditLogFilter) ([]model.AuditLog, error) {
	return s.repo.ListAuditLogs(ctx, filter)
}

func (s *adminService) ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error) {
	return s.repo.ListAllApplications(ctx, productType, limit)
}

func (s *adminService) UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error) {
	status = strings.ToUpper(strings.TrimSpace(status))
	switch status {
	case "PENDING", "CONTACTED", "APPROVED", "REJECTED":
	default:
		return nil, fmt.Errorf("%w: status pengajuan tidak dikenal", ErrValidation)
	}
	app, err := s.repo.UpdateApplicationStatus(ctx, id, status, limitLen(adminNotes, 500))
	if err != nil {
		if errors.Is(err, repository.ErrApplicationFinalStatus) {
			return nil, fmt.Errorf("%w: %s", ErrValidation, err.Error())
		}
		return nil, err
	}
	statusLabel := app.Status
	switch app.Status {
	case "PENDING":
		statusLabel = "DIAJUKAN (MENUNGGU TINJAUAN PETUGAS)"
	case "APPROVED":
		statusLabel = "SELESAI DIPROSES"
	case "CONTACTED":
		statusLabel = "SEDANG DIPROSES / AKAN DIHUBUNGI PETUGAS"
	case "REJECTED":
		statusLabel = "DIBATALKAN"
	}
	msg := fmt.Sprintf("Status pengajuan %s Anda sebesar %s kini: %s.", app.ProductName, money.FormatIDR(app.Amount), statusLabel)
	if app.AdminNotes != "" {
		msg += " Catatan Petugas: " + app.AdminNotes
	}
	s.audit(ctx, "UPDATE_APPLICATION_STATUS", app.FullName+" - "+app.ProductName, "SUCCESS", fmt.Sprintf("Status pengajuan diubah menjadi %s", app.Status))
	notification.CreateAndPush(ctx, s.repo.DB(), app.UserID, "Update Pengajuan "+app.ProductName, msg, "INFO")
	return app, nil
}
