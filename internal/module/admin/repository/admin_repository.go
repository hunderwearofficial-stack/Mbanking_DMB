package repository

import (
	"context"
	"errors"
	"mbanking-bpr/pkg/money"
	"strings"
	"time"

	"mbanking-bpr/internal/model"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ErrDBUnavailable is returned when the database is not connected.
//
// SECURITY (audit DMB-009 / DMB-026): the former in-memory fallback — which
// included a SUPER_ADMIN account with a published default password — was removed.
// The backoffice works only against the database (fail-closed).
var ErrDBUnavailable = errors.New("database tidak tersedia")

// CustomerSummary is the backoffice view of a customer (data minimisation, audit DMB-022):
// no NIK, address, birth data or mother's maiden name; no FCM token.
type CustomerSummary struct {
	ID                  string    `json:"id"`
	CIF                 string    `json:"cif"`
	FullName            string    `json:"full_name"`
	PhoneNumber         string    `json:"phone_number"`
	DeviceBound         bool      `json:"device_bound"`
	DeviceID            string    `json:"device_id"`
	IsActive            bool      `json:"is_active"`
	Activated           bool      `json:"activated"`
	FailedLoginAttempts int       `json:"failed_login_attempts"`
	FailedPINAttempts   int       `json:"failed_pin_attempts"`
	AccountNumbers      []string  `json:"account_numbers"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// TransactionSummary is the backoffice view of a transaction (no customer PII).
type TransactionSummary struct {
	ID              string       `json:"id"`
	UserID          string       `json:"user_id"`
	CustomerName    string       `json:"customer_name"`
	FromAccount     string       `json:"from_account"`
	ToAccount       string       `json:"to_account"`
	Amount          money.Amount `json:"amount"`
	TransactionType string       `json:"transaction_type"`
	Status          string       `json:"status"`
	CBSReferenceNo  string       `json:"cbs_ref_no"`
	CreatedAt       time.Time    `json:"created_at"`
}

type AdminRepository interface {
	FindByUsername(ctx context.Context, username string) (*model.AdminUser, error)
	FindAdminByID(ctx context.Context, id string) (*model.AdminUser, error)
	CountActiveSuperAdmins(ctx context.Context, excludeID string) (int64, error)

	GetDashboardStats(ctx context.Context) (map[string]interface{}, error)

	ListCustomers(ctx context.Context, search string, page, limit int) ([]CustomerSummary, int64, error)
	GetCustomerByID(ctx context.Context, id string) (*model.User, error)
	ResetDeviceBinding(ctx context.Context, userID string) error
	ToggleCustomerStatus(ctx context.Context, userID string, isActive bool) error

	ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error)
	GetBannerByID(ctx context.Context, id string) (*model.Banner, error)
	CreateBanner(ctx context.Context, banner *model.Banner) error
	UpdateBanner(ctx context.Context, banner *model.Banner) error
	DeleteBanner(ctx context.Context, id string) error

	ListRecentTransactions(ctx context.Context, limit int) ([]TransactionSummary, error)

	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, admin *model.AdminUser) error
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) error
	DeleteAdminUser(ctx context.Context, id string) error

	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error

	DB() *gorm.DB
	ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error)
	ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error)
	UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error)
}

type adminRepository struct {
	db *gorm.DB
}

func NewAdminRepository(db *gorm.DB) AdminRepository {
	return &adminRepository{db: db}
}

func (r *adminRepository) DB() *gorm.DB { return r.db }

func (r *adminRepository) q(ctx context.Context) (*gorm.DB, error) {
	if r.db == nil {
		return nil, ErrDBUnavailable
	}
	return r.db.WithContext(ctx), nil
}

func clampLimit(limit, def, max int) int {
	if limit <= 0 || limit > max {
		return def
	}
	return limit
}

// escapeLike escapes LIKE wildcards in user-supplied search text.
func escapeLike(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
}

func (r *adminRepository) FindByUsername(ctx context.Context, username string) (*model.AdminUser, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var admin model.AdminUser
	if err := db.Where("username = ?", username).First(&admin).Error; err != nil {
		return nil, err
	}
	return &admin, nil
}

func (r *adminRepository) FindAdminByID(ctx context.Context, id string) (*model.AdminUser, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var admin model.AdminUser
	if err := db.Where("id = ?", id).First(&admin).Error; err != nil {
		return nil, err
	}
	return &admin, nil
}

func (r *adminRepository) CountActiveSuperAdmins(ctx context.Context, excludeID string) (int64, error) {
	db, err := r.q(ctx)
	if err != nil {
		return 0, err
	}
	var n int64
	err = db.Model(&model.AdminUser{}).Where("role = ? AND is_active = ? AND id <> ?", model.AdminRoleSuperAdmin, true, excludeID).Count(&n).Error
	return n, err
}

func (r *adminRepository) GetDashboardStats(ctx context.Context) (map[string]interface{}, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var totalUsers, activeUsers, boundDevices, totalBanners, totalTxToday int64
	var totalVolumeToday money.Amount
	now := time.Now()
	startOfDay := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	if err := errors.Join(
		db.Model(&model.User{}).Count(&totalUsers).Error,
		db.Model(&model.User{}).Where("is_active = ?", true).Count(&activeUsers).Error,
		db.Model(&model.User{}).Where("device_id <> ''").Count(&boundDevices).Error,
		db.Model(&model.Banner{}).Where("is_active = ?", true).Count(&totalBanners).Error,
		db.Model(&model.Transaction{}).Where("created_at >= ?", startOfDay).Count(&totalTxToday).Error,
		db.Model(&model.Transaction{}).Where("created_at >= ? AND status = ?", startOfDay, model.TxStatusSuccess).
			Select("COALESCE(SUM(amount), 0)").Scan(&totalVolumeToday).Error,
	); err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"total_users":        totalUsers,
		"active_users":       activeUsers,
		"bound_devices":      boundDevices,
		"total_accounts":     totalUsers,
		"active_banners":     totalBanners,
		"total_transactions": totalTxToday,
		"transaction_volume": totalVolumeToday,
		"system_health":      "ONLINE",
		"last_updated":       time.Now().Format(time.RFC3339),
	}, nil
}

func (r *adminRepository) ListCustomers(ctx context.Context, search string, page, limit int) ([]CustomerSummary, int64, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, 0, err
	}
	var users []model.User
	var total int64
	query := db.Model(&model.User{}).Preload("Accounts")
	if s := strings.TrimSpace(search); s != "" {
		if len(s) > 60 {
			s = s[:60]
		}
		like := "%" + escapeLike(s) + "%"
		query = query.Where("full_name ILIKE ? OR phone_number ILIKE ? OR cif ILIKE ?", like, like, like)
	}
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if err := query.Order("created_at DESC").Limit(limit).Offset((page - 1) * limit).Find(&users).Error; err != nil {
		return nil, 0, err
	}
	out := make([]CustomerSummary, 0, len(users))
	for _, u := range users {
		accs := make([]string, 0, len(u.Accounts))
		for _, a := range u.Accounts {
			accs = append(accs, a.AccountNumber)
		}
		out = append(out, CustomerSummary{
			ID: u.ID, CIF: u.CIF, FullName: u.FullName, PhoneNumber: u.PhoneNumber,
			DeviceBound: u.DeviceID != "", DeviceID: u.DeviceID, IsActive: u.IsActive, Activated: u.PasswordHash != "",
			FailedLoginAttempts: u.FailedLoginAttempts, FailedPINAttempts: u.FailedPINAttempts,
			AccountNumbers: accs, CreatedAt: u.CreatedAt, UpdatedAt: u.UpdatedAt,
		})
	}
	return out, total, nil
}

func (r *adminRepository) GetCustomerByID(ctx context.Context, id string) (*model.User, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var user model.User
	if err := db.Where("id = ?", id).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *adminRepository) ResetDeviceBinding(ctx context.Context, userID string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Model(&model.User{}).Where("id = ?", userID).
		Updates(map[string]interface{}{"device_id": "", "updated_at": time.Now()}).Error
}

func (r *adminRepository) ToggleCustomerStatus(ctx context.Context, userID string, isActive bool) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{"is_active": isActive, "updated_at": time.Now()}
	if isActive {
		updates["failed_login_attempts"] = 0
		updates["failed_pin_attempts"] = 0
	}
	return db.Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
}

func (r *adminRepository) ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var banners []model.Banner
	query := db.Model(&model.Banner{})
	if activeOnly {
		query = query.Where("is_active = ?", true)
	}
	if err := query.Order("display_order ASC, created_at DESC").Find(&banners).Error; err != nil {
		return nil, err
	}
	return banners, nil
}

func (r *adminRepository) GetBannerByID(ctx context.Context, id string) (*model.Banner, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var banner model.Banner
	if err := db.Where("id = ?", id).First(&banner).Error; err != nil {
		return nil, err
	}
	return &banner, nil
}

func (r *adminRepository) CreateBanner(ctx context.Context, banner *model.Banner) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	banner.ID = uuid.NewString()
	banner.CreatedAt = time.Now()
	banner.UpdatedAt = time.Now()
	return db.Create(banner).Error
}

func (r *adminRepository) UpdateBanner(ctx context.Context, banner *model.Banner) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	banner.UpdatedAt = time.Now()
	return db.Save(banner).Error
}

func (r *adminRepository) DeleteBanner(ctx context.Context, id string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Where("id = ?", id).Delete(&model.Banner{}).Error
}

func (r *adminRepository) ListRecentTransactions(ctx context.Context, limit int) ([]TransactionSummary, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	limit = clampLimit(limit, 20, 200)
	var txs []model.Transaction
	if err := db.Preload("User", func(tx *gorm.DB) *gorm.DB { return tx.Select("id", "full_name") }).
		Order("created_at DESC").Limit(limit).Find(&txs).Error; err != nil {
		return nil, err
	}
	out := make([]TransactionSummary, 0, len(txs))
	for _, t := range txs {
		name := ""
		if t.User != nil {
			name = t.User.FullName
		}
		out = append(out, TransactionSummary{
			ID: t.ID, UserID: t.UserID, CustomerName: name, FromAccount: t.FromAccount, ToAccount: t.ToAccount,
			Amount: t.Amount, TransactionType: t.TransactionType, Status: t.Status, CBSReferenceNo: t.CBSReferenceNo, CreatedAt: t.CreatedAt,
		})
	}
	return out, nil
}

func (r *adminRepository) GetAppConfig(ctx context.Context) (*model.AppConfig, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var cfg model.AppConfig
	if err := db.First(&cfg).Error; err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (r *adminRepository) UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	cfg.ID = "DEFAULT"
	cfg.UpdatedAt = time.Now()
	// Only operational settings are written here. Mobile content columns (tagline, logo,
	// login texts/background, announcement, greeting, contacts, content_version) belong
	// to the versioned content workflow and must not be overwritten with stale values.
	return db.Model(&model.AppConfig{}).Where("id = ?", "DEFAULT").Select(
		"bank_name", "bank_short_name", "email_cs", "website_url", "head_office_address",
		"maintenance_mode", "maintenance_message", "min_transfer_amount", "daily_transfer_limit",
		"interbank_transfer_fee", "enforce_device_binding", "max_login_attempts", "otp_provider",
		"otp_gateway_url", "otp_gateway_token", "updated_at",
	).Updates(cfg).Error
}

func (r *adminRepository) ListAdminUsers(ctx context.Context) ([]model.AdminUser, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var admins []model.AdminUser
	if err := db.Order("created_at ASC").Find(&admins).Error; err != nil {
		return nil, err
	}
	return admins, nil
}

func (r *adminRepository) CreateAdminUser(ctx context.Context, admin *model.AdminUser) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	admin.ID = uuid.NewString()
	admin.CreatedAt = time.Now()
	admin.UpdatedAt = time.Now()
	return db.Create(admin).Error
}

func (r *adminRepository) ToggleAdminStatus(ctx context.Context, id string, isActive bool) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(map[string]interface{}{"is_active": isActive, "updated_at": time.Now()}).Error
}

func (r *adminRepository) DeleteAdminUser(ctx context.Context, id string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Where("id = ?", id).Delete(&model.AdminUser{}).Error
}

func (r *adminRepository) ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	limit = clampLimit(limit, 100, 500)
	var logs []model.AuditLog
	query := db.Model(&model.AuditLog{})
	if actorType != "" && actorType != "ALL" {
		query = query.Where("actor_type = ?", strings.ToUpper(actorType))
	}
	// Records are returned exactly as stored (no value substitution — audit DMB-016).
	if err := query.Order("created_at DESC").Limit(limit).Find(&logs).Error; err != nil {
		return nil, err
	}
	return logs, nil
}

func (r *adminRepository) ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	limit = clampLimit(limit, 50, 200)
	var list []model.ProductApplication
	q := db.Model(&model.ProductApplication{})
	if productType != "" && productType != "ALL" {
		q = q.Where("product_type = ?", strings.ToUpper(productType))
	}
	if err := q.Order("created_at DESC").Limit(limit).Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *adminRepository) UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var app model.ProductApplication
	if err := db.Where("id = ?", id).First(&app).Error; err != nil {
		return nil, err
	}
	app.Status = strings.ToUpper(status)
	app.AdminNotes = adminNotes
	app.UpdatedAt = time.Now()
	if err := db.Save(&app).Error; err != nil {
		return nil, err
	}
	return &app, nil
}
