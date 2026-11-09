package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/admin/repository"
	"mbanking-bpr/internal/otpprovider"
	"mbanking-bpr/pkg/utils"
)

var (
	ErrAdminInvalidCredentials = errors.New("username atau password admin salah")
	ErrAdminAccountDisabled    = errors.New("akun admin telah dinonaktifkan")
	ErrBannerNotFound          = errors.New("data banner tidak ditemukan")
	ErrCustomerNotFound        = errors.New("data nasabah tidak ditemukan")
)

type AdminService interface {
	Login(ctx context.Context, username, password string) (string, *model.AdminUser, error)
	GetDashboardStats(ctx context.Context) (map[string]interface{}, error)

	ListCustomers(ctx context.Context, search string, page, limit int) ([]model.User, int64, error)
	ResetCustomerDevice(ctx context.Context, userID string) error
	ToggleCustomerActive(ctx context.Context, userID string, isActive bool) error

	ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error)
	GetBanner(ctx context.Context, id string) (*model.Banner, error)
	CreateBanner(ctx context.Context, banner *model.Banner) error
	UpdateBanner(ctx context.Context, banner *model.Banner) error
	DeleteBanner(ctx context.Context, id string) error

	ListTransactions(ctx context.Context, limit int) ([]model.Transaction, error)

	// Admin Users & RBAC
	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, error)
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) error
	DeleteAdminUser(ctx context.Context, id string) error

	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error

	// Audit Trail & Notifications
	ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error)
	ListNotificationsForUser(ctx context.Context, userID string, limit int) ([]model.Notification, error)
	MarkNotificationsRead(ctx context.Context, userID string) error
	UpdateUserFCMToken(ctx context.Context, userID, fcmToken string) error
	BroadcastNotification(ctx context.Context, title, message, category string) error

	// Saved Beneficiaries
	ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error)
	SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error
	DeleteBeneficiary(ctx context.Context, id string, userID string) error

	// Online Product Applications (Deposito & Pinjaman)
	CreateProductApplication(ctx context.Context, userID string, app *model.ProductApplication) (*model.ProductApplication, error)
	ListUserApplications(ctx context.Context, userID string) ([]model.ProductApplication, error)
	ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error)
	UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error)
}

type adminService struct {
	cfg  *config.Config
	repo repository.AdminRepository
}

func NewAdminService(cfg *config.Config, repo repository.AdminRepository) AdminService {
	return &adminService{
		cfg:  cfg,
		repo: repo,
	}
}

func (s *adminService) Login(ctx context.Context, username, password string) (string, *model.AdminUser, error) {
	admin, err := s.repo.FindByUsername(ctx, username)
	if err != nil {
		return "", nil, ErrAdminInvalidCredentials
	}

	if !admin.IsActive {
		return "", nil, ErrAdminAccountDisabled
	}

	if !utils.CheckPassword(admin.PasswordHash, password) {
		return "", nil, ErrAdminInvalidCredentials
	}

	// Generate Admin JWT token (Valid 8 hours)
	tokenPair, err := utils.GenerateTokenPair(
		admin.ID,
		admin.Username,
		admin.Email,
		admin.Role,
		"ADMIN-CONSOLE",
		s.cfg.JWTSecret,
		480, // 8 hours (480 minutes)
		7,   // 7 days
	)
	if err != nil {
		return "", nil, err
	}

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", admin.ID, admin.FullName, "ADMIN_LOGIN", admin.Username, "SUCCESS", "WEB-BACKOFFICE", fmt.Sprintf("Login konsol backoffice (%s)", admin.Role))

	return tokenPair.AccessToken, admin, nil
}

func (s *adminService) GetDashboardStats(ctx context.Context) (map[string]interface{}, error) {
	return s.repo.GetDashboardStats(ctx)
}

func (s *adminService) ListCustomers(ctx context.Context, search string, page, limit int) ([]model.User, int64, error) {
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
	oldDev := user.DeviceID
	if err := s.repo.ResetDeviceBinding(ctx, userID); err != nil {
		return err
	}
	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Petugas CS/Admin", "UNBIND_CUSTOMER_DEVICE", user.FullName+" ("+user.CIF+")", "WARNING", "WEB-BACKOFFICE", fmt.Sprintf("Unbind/Reset Device ID nasabah (Perangkat sebelumnya: %s)", oldDev))
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Reset Perangkat Berhasil", "Ikatan perangkat (Device ID) akun Mobile DMB Anda telah di-reset oleh petugas Bank DMB.", "SECURITY")
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
		otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Petugas CS/Admin", "UNBLOCK_CUSTOMER", user.FullName+" ("+user.CIF+")", "SUCCESS", "WEB-BACKOFFICE", "Membuka blokir akun nasabah & me-reset counter gagal login/PIN")
		otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Akun Telah Diaktifkan Kembali", "Akun Mobile DMB Anda telah diaktifkan kembali oleh Customer Service Bank DMB.", "SECURITY")
	} else {
		otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Petugas CS/Admin", "BLOCK_CUSTOMER", user.FullName+" ("+user.CIF+")", "DANGER", "WEB-BACKOFFICE", "Memblokir akun nasabah secara manual")
	}
	return nil
}

func (s *adminService) ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error) {
	return s.repo.ListBanners(ctx, activeOnly)
}

func (s *adminService) GetBanner(ctx context.Context, id string) (*model.Banner, error) {
	return s.repo.GetBannerByID(ctx, id)
}

func (s *adminService) CreateBanner(ctx context.Context, banner *model.Banner) error {
	if banner.Tag == "" {
		banner.Tag = "BANK DMB"
	}
	return s.repo.CreateBanner(ctx, banner)
}

func (s *adminService) UpdateBanner(ctx context.Context, banner *model.Banner) error {
	existing, err := s.repo.GetBannerByID(ctx, banner.ID)
	if err != nil || existing == nil {
		return ErrBannerNotFound
	}
	banner.CreatedAt = existing.CreatedAt
	banner.UpdatedAt = time.Now()
	return s.repo.UpdateBanner(ctx, banner)
}

func (s *adminService) DeleteBanner(ctx context.Context, id string) error {
	return s.repo.DeleteBanner(ctx, id)
}

func (s *adminService) ListTransactions(ctx context.Context, limit int) ([]model.Transaction, error) {
	return s.repo.ListRecentTransactions(ctx, limit)
}

func (s *adminService) GetAppConfig(ctx context.Context) (*model.AppConfig, error) {
	return s.repo.GetAppConfig(ctx)
}

func (s *adminService) UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error {
	if err := s.repo.UpdateAppConfig(ctx, cfg); err != nil {
		return err
	}
	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Super Admin", "UPDATE_BANK_CONFIG", cfg.BankShortName, "SUCCESS", "WEB-BACKOFFICE", fmt.Sprintf("Memperbarui konfigurasi bank & OTP Provider (%s)", cfg.OTPProvider))
	return nil
}

func (s *adminService) ListAdminUsers(ctx context.Context) ([]model.AdminUser, error) {
	return s.repo.ListAdminUsers(ctx)
}

func (s *adminService) CreateAdminUser(ctx context.Context, username, fullName, email, password, role string, isActive bool) (*model.AdminUser, error) {
	if username == "" || password == "" {
		return nil, errors.New("username dan password wajib diisi")
	}

	existing, _ := s.repo.FindByUsername(ctx, username)
	if existing != nil {
		return nil, errors.New("username petugas sudah digunakan")
	}

	pwHash, err := utils.HashPassword(password)
	if err != nil {
		return nil, err
	}

	if role == "" {
		role = model.AdminRoleSuperAdmin
	}

	newAdmin := &model.AdminUser{
		Username:     username,
		FullName:     fullName,
		Email:        email,
		PasswordHash: pwHash,
		Role:         role,
		IsActive:     isActive,
	}

	if err := s.repo.CreateAdminUser(ctx, newAdmin); err != nil {
		return nil, err
	}
	return newAdmin, nil
}

func (s *adminService) ToggleAdminStatus(ctx context.Context, id string, isActive bool) error {
	return s.repo.ToggleAdminStatus(ctx, id, isActive)
}

func (s *adminService) DeleteAdminUser(ctx context.Context, id string) error {
	return s.repo.DeleteAdminUser(ctx, id)
}

func (s *adminService) ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error) {
	return s.repo.ListAuditLogs(ctx, actorType, limit)
}

func (s *adminService) ListNotificationsForUser(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	return s.repo.ListNotificationsForUser(ctx, userID, limit)
}

func (s *adminService) MarkNotificationsRead(ctx context.Context, userID string) error {
	return s.repo.MarkNotificationsRead(ctx, userID)
}

func (s *adminService) UpdateUserFCMToken(ctx context.Context, userID, fcmToken string) error {
	return s.repo.UpdateUserFCMToken(ctx, userID, fcmToken)
}

func (s *adminService) BroadcastNotification(ctx context.Context, title, message, category string) error {
	if category == "" {
		category = "PROMO"
	}
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), "ALL", title, message, category)
	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Marketing / Admin", "BROADCAST_NOTIFICATION", "ALL_CUSTOMERS", "SUCCESS", "WEB-BACKOFFICE", fmt.Sprintf("Broadcast notifikasi [%s]: %s", category, title))
	return nil
}

func (s *adminService) ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error) {
	return s.repo.ListBeneficiaries(ctx, userID)
}

func (s *adminService) SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error {
	if b.AccountNumber == "" || b.AccountName == "" {
		return errors.New("nomor rekening dan nama penerima wajib diisi")
	}
	if b.BankCode == "" {
		b.BankCode = "BPR"
	}
	if b.BankName == "" {
		b.BankName = "Bank DMB"
	}
	return s.repo.SaveBeneficiary(ctx, b)
}

func (s *adminService) DeleteBeneficiary(ctx context.Context, id string, userID string) error {
	return s.repo.DeleteBeneficiary(ctx, id, userID)
}

func (s *adminService) CreateProductApplication(ctx context.Context, userID string, app *model.ProductApplication) (*model.ProductApplication, error) {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return nil, ErrCustomerNotFound
	}
	app.UserID = user.ID
	app.CIF = user.CIF
	app.FullName = user.FullName
	app.PhoneNumber = user.PhoneNumber
	app.Status = "PENDING"

	if err := s.repo.CreateProductApplication(ctx, app); err != nil {
		return nil, err
	}

	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "SUBMIT_PRODUCT_APPLICATION", app.ProductName, "SUCCESS", user.DeviceID, fmt.Sprintf("Pengajuan %s sebesar Rp %.0f (Tenor %d bulan)", app.ProductName, app.Amount, app.TenorMonths))
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Pengajuan "+app.ProductName+" Diterima", fmt.Sprintf("Terima kasih %s, pengajuan %s sebesar Rp %.0f (Tenor %d bulan) telah diterima. Petugas Bank DMB akan segera menindaklanjuti pengajuan Anda.", user.FullName, app.ProductName, app.Amount, app.TenorMonths), "INFO")
	return app, nil
}

func (s *adminService) ListUserApplications(ctx context.Context, userID string) ([]model.ProductApplication, error) {
	return s.repo.ListUserApplications(ctx, userID)
}

func (s *adminService) ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error) {
	return s.repo.ListAllApplications(ctx, productType, limit)
}

func (s *adminService) UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error) {
	app, err := s.repo.UpdateApplicationStatus(ctx, id, status, adminNotes)
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
	msg := fmt.Sprintf("Status pengajuan %s Anda sebesar Rp %.0f kini: %s.", app.ProductName, app.Amount, statusLabel)
	if adminNotes != "" {
		msg += " Catatan Petugas: " + adminNotes
	}
	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "ADMIN", "BACKOFFICE", "Petugas CS / Marketing", "UPDATE_APPLICATION_STATUS", app.FullName+" - "+app.ProductName, "SUCCESS", "WEB-BACKOFFICE", fmt.Sprintf("Status pengajuan diubah menjadi %s (%s)", app.Status, adminNotes))
	otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), app.UserID, "Update Pengajuan "+app.ProductName, msg, "INFO")
	return app, nil
}
