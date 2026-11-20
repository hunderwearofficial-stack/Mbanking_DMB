package service

import (
	"context"
	"errors"
	"fmt"
	"mbanking-bpr/pkg/money"
	"net/url"
	"regexp"
	"strings"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/admin/repository"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/session"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/reqctx"
	"mbanking-bpr/pkg/security"

	"github.com/google/uuid"
	"gorm.io/gorm"
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
)

type AdminLoginResult struct {
	Token     string
	ExpiresAt time.Time
	Admin     *model.AdminUser
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
	Login(ctx context.Context, username, password string) (*AdminLoginResult, error)
	Logout(ctx context.Context)
	IsProductionLike() bool
	DB() *gorm.DB
	GetDashboardStats(ctx context.Context) (map[string]interface{}, error)

	ListCustomers(ctx context.Context, search string, page, limit int) ([]repository.CustomerSummary, int64, error)
	ResetCustomerDevice(ctx context.Context, userID string) error
	ToggleCustomerActive(ctx context.Context, userID string, isActive bool) error

	ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error)
	CreateBanner(ctx context.Context, in BannerInput) (*model.Banner, error)
	UpdateBanner(ctx context.Context, id string, in BannerInput) (*model.Banner, error)
	DeleteBanner(ctx context.Context, id string) error

	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, error)
	UpdateAdminUser(ctx context.Context, id, fullName, email, role, password string) (*model.AdminUser, error)
	ChangeOwnPassword(ctx context.Context, oldPassword, newPassword string) error
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) error
	DeleteAdminUser(ctx context.Context, id string) error

	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, in AppConfigUpdate) (*model.AppConfig, error)

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

func (s *adminService) Login(ctx context.Context, username, password string) (*AdminLoginResult, error) {
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
	_ = s.repo.ResetAdminLoginFailures(ctx, admin.ID)
	token, exp, err := security.GenerateAdminToken(admin.ID, admin.Username, admin.Role, s.cfg.AdminJWTSecret,
		time.Duration(s.cfg.AdminJWTExpiryMinutes)*time.Minute)
	if err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.Username+" ("+admin.Role+")", "ADMIN_LOGIN", admin.Username, "SUCCESS", "WEB-BACKOFFICE", "Login konsol backoffice")
	return &AdminLoginResult{Token: token, ExpiresAt: exp, Admin: admin}, nil
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

func (s *adminService) CreateBanner(ctx context.Context, in BannerInput) (*model.Banner, error) {
	b, err := s.validateBanner(in)
	if err != nil {
		return nil, err
	}
	if err := s.repo.CreateBanner(ctx, b); err != nil {
		return nil, err
	}
	s.audit(ctx, "CREATE_BANNER", b.Title, "SUCCESS", "Menambah banner promosi")
	return b, nil
}

func (s *adminService) UpdateBanner(ctx context.Context, id string, in BannerInput) (*model.Banner, error) {
	existing, err := s.repo.GetBannerByID(ctx, id)
	if err != nil || existing == nil {
		return nil, ErrBannerNotFound
	}
	b, err := s.validateBanner(in)
	if err != nil {
		return nil, err
	}
	b.ID = existing.ID
	b.CreatedAt = existing.CreatedAt
	if err := s.repo.UpdateBanner(ctx, b); err != nil {
		return nil, err
	}
	s.audit(ctx, "UPDATE_BANNER", b.Title, "SUCCESS", "Memperbarui banner promosi")
	return b, nil
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

func (s *adminService) UpdateAppConfig(ctx context.Context, in AppConfigUpdate) (*model.AppConfig, error) {
	current, err := s.repo.GetAppConfig(ctx)
	if err != nil || current == nil {
		return nil, fmt.Errorf("%w: konfigurasi belum tersedia", ErrValidation)
	}
	provider := strings.ToUpper(strings.TrimSpace(in.OTPProvider))
	switch provider {
	case "", "SANDBOX", "JATIS", "SMS_GATEWAY":
	default:
		return nil, fmt.Errorf("%w: penyedia OTP tidak dikenal", ErrValidation)
	}
	if provider == "" {
		provider = current.OTPProvider
	}
	if s.cfg != nil && s.cfg.IsProductionLike() && provider == "SANDBOX" {
		return nil, fmt.Errorf("%w: mode SANDBOX OTP tidak diizinkan di lingkungan produksi", ErrValidation)
	}
	if !validHTTPSURL(in.OTPGatewayURL, false) || !validHTTPSURL(in.WebsiteURL, false) ||
		!validHTTPSURL(in.LogoURL, true) || !validHTTPSURL(in.LoginBgURL, true) ||
		!validHTTPSURL(in.SplashBgURL, true) || !validHTTPSURL(in.OnboardingBgURL, true) ||
		!validHTTPSURL(in.TermsPdfURL, true) || !validHTTPSURL(in.PrivacyPdfURL, true) {
		return nil, fmt.Errorf("%w: alamat URL harus diawali https:// (atau path lokal)", ErrValidation)
	}
	if in.MaxLoginAttempts < 0 || in.MaxLoginAttempts > 10 {
		return nil, fmt.Errorf("%w: batas percobaan login tidak valid", ErrValidation)
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

	if s.cfg != nil && (s.cfg.DeviceBindingMode == "required" || s.cfg.DeviceBindingMode == "enforced") {
		updated.EnforceDeviceBinding = true
	} else if in.EnforceDeviceBinding != nil {
		updated.EnforceDeviceBinding = *in.EnforceDeviceBinding
	}

	if in.MaxLoginAttempts > 0 {
		updated.MaxLoginAttempts = in.MaxLoginAttempts
	}
	updated.OTPProvider = provider
	updated.OTPGatewayURL = limitLen(in.OTPGatewayURL, 255)

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
	addDiff("enforce_device_binding", fmt.Sprintf("%t", current.EnforceDeviceBinding), fmt.Sprintf("%t", updated.EnforceDeviceBinding))
	addDiff("max_login_attempts", fmt.Sprintf("%d", current.MaxLoginAttempts), fmt.Sprintf("%d", updated.MaxLoginAttempts))
	addDiff("otp_provider", current.OTPProvider, updated.OTPProvider)
	addDiff("otp_gateway_url", current.OTPGatewayURL, updated.OTPGatewayURL)

	if in.ClearOTPGatewayToken {
		updated.OTPGatewayToken = ""
		diffs = append(diffs, "otp_gateway_token: [SET] -> [CLEARED]")
	} else if in.OTPGatewayToken != nil {
		if t := strings.TrimSpace(*in.OTPGatewayToken); t != "" {
			enc, encErr := crypto.EncryptString(t)
			if encErr != nil {
				return nil, encErr
			}
			updated.OTPGatewayToken = enc
			diffs = append(diffs, "otp_gateway_token: [REDACTED] -> [ENCRYPTED_NEW]")
		}
	}

	if err := s.repo.UpdateAppConfig(ctx, &updated); err != nil {
		return nil, err
	}
	diffSummary := "tidak ada perubahan nilai"
	if len(diffs) > 0 {
		diffSummary = strings.Join(diffs, "; ")
	}
	s.audit(ctx, "UPDATE_CONFIG", updated.BankShortName, "SUCCESS",
		fmt.Sprintf("Memperbarui konfigurasi sistem: %s", diffSummary))
	return &updated, nil
}

func (s *adminService) ListAdminUsers(ctx context.Context) ([]model.AdminUser, error) {
	return s.repo.ListAdminUsers(ctx)
}

func (s *adminService) CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, error) {
	username = strings.TrimSpace(username)
	if len(username) < 4 || len(username) > 50 {
		return nil, fmt.Errorf("%w: username petugas 4-50 karakter", ErrValidation)
	}
	role = strings.ToUpper(strings.TrimSpace(role))
	if !model.IsValidAdminRole(role) {
		return nil, ErrInvalidRole // no implicit SUPER_ADMIN default
	}
	if len(password) < 12 {
		return nil, fmt.Errorf("%w: password petugas minimal 12 karakter", ErrValidation)
	}
	if err := security.ValidateNewPassword(password); err != nil {
		return nil, err
	}
	if existing, _ := s.repo.FindByUsername(ctx, username); existing != nil {
		return nil, errors.New("username petugas sudah digunakan")
	}
	pwHash, err := security.HashPassword(password)
	if err != nil {
		return nil, err
	}
	newAdmin := &model.AdminUser{
		Username: username, FullName: limitLen(fullName, 100), Email: limitLen(email, 100),
		PasswordHash: pwHash, Role: role, IsActive: isActive,
	}
	if err := s.repo.CreateAdminUser(ctx, newAdmin); err != nil {
		return nil, err
	}
	s.audit(ctx, "CREATE_ADMIN_USER", username, "WARNING", fmt.Sprintf("Mendaftarkan petugas baru dengan role %s", role))
	return newAdmin, nil
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

func (s *adminService) ToggleAdminStatus(ctx context.Context, id string, isActive bool) error {
	if err := s.guardAdminChange(ctx, id, !isActive); err != nil {
		return err
	}
	if err := s.repo.ToggleAdminStatus(ctx, id, isActive); err != nil {
		return err
	}
	s.audit(ctx, "TOGGLE_ADMIN_STATUS", id, "WARNING", fmt.Sprintf("Status petugas diubah menjadi aktif=%t", isActive))
	return nil
}

func (s *adminService) UpdateAdminUser(ctx context.Context, id, fullName, email, role, password string) (*model.AdminUser, error) {
	target, err := s.repo.FindAdminByID(ctx, id)
	if err != nil || target == nil {
		return nil, fmt.Errorf("%w: petugas tidak ditemukan", ErrValidation)
	}
	role = strings.ToUpper(strings.TrimSpace(role))
	if role == "" {
		role = target.Role
	}
	if !model.IsValidAdminRole(role) {
		return nil, ErrInvalidRole
	}
	if target.Role == model.AdminRoleSuperAdmin && role != model.AdminRoleSuperAdmin && target.IsActive {
		if id == currentAdminID(ctx) {
			return nil, ErrSelfModification
		}
		n, err := s.repo.CountActiveSuperAdmins(ctx, id)
		if err != nil {
			return nil, err
		}
		if n == 0 {
			return nil, ErrLastSuperAdmin
		}
	}

	newFullName := limitLen(fullName, 100)
	if newFullName == "" {
		newFullName = target.FullName
	}
	newEmail := limitLen(email, 100)

	pwHash := ""
	if strings.TrimSpace(password) != "" {
		if len(password) < 12 {
			return nil, fmt.Errorf("%w: password petugas minimal 12 karakter", ErrValidation)
		}
		if err := security.ValidateNewPassword(password); err != nil {
			return nil, err
		}
		h, err := security.HashPassword(password)
		if err != nil {
			return nil, err
		}
		pwHash = h
	}

	if err := s.repo.UpdateAdminUser(ctx, id, newFullName, newEmail, role, pwHash); err != nil {
		return nil, err
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
		return nil, err
	}
	return updated, nil
}

func (s *adminService) ChangeOwnPassword(ctx context.Context, oldPassword, newPassword string) error {
	adminID := currentAdminID(ctx)
	if adminID == "" {
		return ErrAdminInvalidCredentials
	}
	admin, err := s.repo.FindAdminByID(ctx, adminID)
	if err != nil || admin == nil {
		return ErrAdminInvalidCredentials
	}
	if !security.CheckPassword(admin.PasswordHash, oldPassword) {
		s.audit(ctx, "ADMIN_CHANGE_PASSWORD_FAILED", admin.Username, "WARNING", "Gagal ganti password petugas: password lama salah")
		return fmt.Errorf("%w: password lama yang Anda masukkan salah", ErrValidation)
	}
	if len(newPassword) < 12 {
		return fmt.Errorf("%w: password baru petugas minimal 12 karakter", ErrValidation)
	}
	if err := security.ValidateNewPassword(newPassword); err != nil {
		return err
	}
	if oldPassword == newPassword {
		return fmt.Errorf("%w: password baru tidak boleh sama dengan password lama", ErrValidation)
	}
	pwHash, err := security.HashPassword(newPassword)
	if err != nil {
		return err
	}
	if err := s.repo.UpdateAdminPassword(ctx, admin.ID, pwHash); err != nil {
		return err
	}
	s.audit(ctx, "ADMIN_CHANGE_PASSWORD", admin.Username, "SUCCESS", "Petugas berhasil mengganti password akunnya sendiri")
	return nil
}

func (s *adminService) DeleteAdminUser(ctx context.Context, id string) error {
	if err := s.guardAdminChange(ctx, id, true); err != nil {
		return err
	}
	if err := s.repo.DeleteAdminUser(ctx, id); err != nil {
		return err
	}
	s.audit(ctx, "DELETE_ADMIN_USER", id, "DANGER", "Menghapus akun petugas")
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
		return nil, err
	}
	statusLabel := app.Status
	switch app.Status {
	case "APPROVED":
		statusLabel = "DISETUJUI"
	case "CONTACTED":
		statusLabel = "SEDANG DIPROSES / DIHUBUNGI CS"
	case "REJECTED":
		statusLabel = "BELUM DAPAT DISETUJUI"
	}
	msg := fmt.Sprintf("Status pengajuan %s Anda sebesar %s kini: %s.", app.ProductName, money.FormatIDR(app.Amount), statusLabel)
	if app.AdminNotes != "" {
		msg += " Catatan Petugas: " + app.AdminNotes
	}
	s.audit(ctx, "UPDATE_APPLICATION_STATUS", app.FullName+" - "+app.ProductName, "SUCCESS", fmt.Sprintf("Status pengajuan diubah menjadi %s", app.Status))
	notification.CreateAndPush(ctx, s.repo.DB(), app.UserID, "Update Pengajuan "+app.ProductName, msg, "INFO")
	return app, nil
}
