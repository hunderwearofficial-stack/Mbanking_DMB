package service

import (
	"context"
	"errors"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/admin/repository"
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
	return s.repo.ResetDeviceBinding(ctx, userID)
}

func (s *adminService) ToggleCustomerActive(ctx context.Context, userID string, isActive bool) error {
	user, err := s.repo.GetCustomerByID(ctx, userID)
	if err != nil || user == nil {
		return ErrCustomerNotFound
	}
	return s.repo.ToggleCustomerStatus(ctx, userID, isActive)
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
	return s.repo.UpdateAppConfig(ctx, cfg)
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
