package repository

import (
	"context"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AdminRepository interface {
	// Admin Auth
	FindByUsername(ctx context.Context, username string) (*model.AdminUser, error)
	FindAdminByID(ctx context.Context, id string) (*model.AdminUser, error)

	// Dashboard KPI Stats
	GetDashboardStats(ctx context.Context) (map[string]interface{}, error)

	// Customer Management (Device Binding, Status)
	ListCustomers(ctx context.Context, search string, page, limit int) ([]model.User, int64, error)
	GetCustomerByID(ctx context.Context, id string) (*model.User, error)
	ResetDeviceBinding(ctx context.Context, userID string) error
	ToggleCustomerStatus(ctx context.Context, userID string, isActive bool) error

	// Banner CMS
	ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error)
	GetBannerByID(ctx context.Context, id string) (*model.Banner, error)
	CreateBanner(ctx context.Context, banner *model.Banner) error
	UpdateBanner(ctx context.Context, banner *model.Banner) error
	DeleteBanner(ctx context.Context, id string) error

	// Transactions
	ListRecentTransactions(ctx context.Context, limit int) ([]model.Transaction, error)

	// Admin Users & RBAC
	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, admin *model.AdminUser) error
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) error
	DeleteAdminUser(ctx context.Context, id string) error

	// App & Bank Branding Settings
	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error

	// Audit Trail & Notifications
	DB() *gorm.DB
	ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error)
	ListNotificationsForUser(ctx context.Context, userID string, limit int) ([]model.Notification, error)
	MarkNotificationsRead(ctx context.Context, userID string) error
	UpdateUserFCMToken(ctx context.Context, userID, fcmToken string) error

	// Saved Beneficiaries (Favorite Destination Accounts)
	ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error)
	SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error
	DeleteBeneficiary(ctx context.Context, id string, userID string) error

	// Online Product Applications (Deposito & Pinjaman)
	CreateProductApplication(ctx context.Context, app *model.ProductApplication) error
	ListUserApplications(ctx context.Context, userID string) ([]model.ProductApplication, error)
	ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error)
	UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error)
}

type adminRepository struct {
	db *gorm.DB

	// In-Memory Fallback State (when PostgreSQL is not running or disconnected)
	mu           sync.RWMutex
	memAdmins    map[string]*model.AdminUser
	memUsers     map[string]*model.User
	memBanners   []*model.Banner
	memTx        []*model.Transaction
	memConfig    *model.AppConfig
}

func NewAdminRepository(db *gorm.DB) AdminRepository {
	repo := &adminRepository{
		db:         db,
		memAdmins:  make(map[string]*model.AdminUser),
		memUsers:   make(map[string]*model.User),
		memBanners: make([]*model.Banner, 0),
		memTx:      make([]*model.Transaction, 0),
	}

	repo.initMemoryDefaults()
	return repo
}

func (r *adminRepository) initMemoryDefaults() {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Default Admin User: admin / admin123
	hash, _ := utils.HashPassword("admin123")
	admin := &model.AdminUser{
		ID:           "adm-001",
		Username:     "admin",
		FullName:     "Administrator IT DMB",
		Email:        "admin@bankdmb.co.id",
		PasswordHash: hash,
		Role:         "SUPER_ADMIN",
		IsActive:     true,
		CreatedAt:    time.Now().Add(-30 * 24 * time.Hour),
		UpdatedAt:    time.Now(),
	}
	r.memAdmins[admin.Username] = admin

	// Default Banners
	r.memBanners = []*model.Banner{
		{
			ID:           "ban-001",
			Tag:          "BPR DANA MANDIRI BOGOR",
			Title:        "SIMPANAN NASABAH DIMANFAATKAN",
			Highlight:    "UNTUK PENGEMBANGAN USAHA PEREMPUAN MIKRO PRODUKTIF",
			BadgeText:    "CSR DMB",
			BgColor:      "#1E293B",
			AccentColor:  "#FFB703",
			IconName:     "groups",
			TargetUrl:    "https://bprdanamandiribogor.co.id/csr",
			IsActive:     true,
			DisplayOrder: 1,
			CreatedAt:    time.Now(),
			UpdatedAt:    time.Now(),
		},
		{
			ID:           "ban-002",
			Tag:          "DEPOSITO BERJANGKA DMB",
			Title:        "BUNGA KOMPETITIF 6,25% P.A.",
			Highlight:    "DAPAT DICAIRKAN SEWAKTU-WAKTU TANPA PENALTI",
			BadgeText:    "Bunga 6.25%",
			BgColor:      "#0F172A",
			AccentColor:  "#16984B",
			IconName:     "savings",
			TargetUrl:    "https://bprdanamandiribogor.co.id/deposito",
			IsActive:     true,
			DisplayOrder: 2,
			CreatedAt:    time.Now(),
			UpdatedAt:    time.Now(),
		},
		{
			ID:           "ban-003",
			Tag:          "SOLUSI KEUANGAN ANDA",
			Title:        "TABUNGAN MANDIRI DMB",
			Highlight:    "SIMPANAN AMAN & DIJAMIN LPS HINGGA 2 MILYAR",
			BadgeText:    "Dijamin LPS",
			BgColor:      "#0B4371",
			AccentColor:  "#38BDF8",
			IconName:     "verified_user",
			TargetUrl:    "https://bprdanamandiribogor.co.id/tabungan",
			IsActive:     true,
			DisplayOrder: 3,
			CreatedAt:    time.Now(),
			UpdatedAt:    time.Now(),
		},
	}

	// Default Bank Branding & App Config
	r.memConfig = &model.AppConfig{
		ID:                   "DEFAULT",
		BankName:             "PT BPR DANA MANDIRI BOGOR",
		BankShortName:        "Bank DMB",
		Tagline:              "Mitra Terpercaya Menuju Sejahtera",
		LogoURL:              "/admin/uploads/logo_1793872119776565700.png",
		CallCenter:           "(0251) 832-1234",
		WhatsAppCS:           "081199887766",
		EmailCS:              "layanan@bprdanamandiribogor.co.id",
		WebsiteURL:           "https://bprdanamandiribogor.co.id",
		HeadOfficeAddress:    "Jl. Pajajaran No. 88, Bogor, Jawa Barat",
		MaintenanceMode:      false,
		MaintenanceMessage:   "Sistem sedang dalam peningkatan layanan berkala.",
		MinTransferAmount:    10000,
		DailyTransferLimit:   25000000,
		InterbankTransferFee: 2500,
		EnforceDeviceBinding: true,
		MaxLoginAttempts:     3,
		UpdatedAt:            time.Now(),
	}
}

func (r *adminRepository) FindByUsername(ctx context.Context, username string) (*model.AdminUser, error) {
	if r.db != nil {
		var admin model.AdminUser
		if err := r.db.WithContext(ctx).Where("username = ?", username).First(&admin).Error; err == nil {
			return &admin, nil
		}
	}

	// In-memory fallback
	r.mu.RLock()
	defer r.mu.RUnlock()
	admin, ok := r.memAdmins[username]
	if !ok {
		return nil, gorm.ErrRecordNotFound
	}
	return admin, nil
}

func (r *adminRepository) FindAdminByID(ctx context.Context, id string) (*model.AdminUser, error) {
	if r.db != nil {
		var admin model.AdminUser
		if err := r.db.WithContext(ctx).Where("id = ?", id).First(&admin).Error; err == nil {
			return &admin, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, a := range r.memAdmins {
		if a.ID == id {
			return a, nil
		}
	}
	return nil, gorm.ErrRecordNotFound
}

func (r *adminRepository) GetDashboardStats(ctx context.Context) (map[string]interface{}, error) {
	if r.db != nil {
		var totalUsers int64
		var activeUsers int64
		var totalBanners int64
		var totalTxToday int64
		var totalVolumeToday float64

		startOfDay := time.Now().Truncate(24 * time.Hour)

		_ = r.db.WithContext(ctx).Model(&model.User{}).Count(&totalUsers)
		_ = r.db.WithContext(ctx).Model(&model.User{}).Where("is_active = ?", true).Count(&activeUsers)
		_ = r.db.WithContext(ctx).Model(&model.Banner{}).Where("is_active = ?", true).Count(&totalBanners)

		_ = r.db.WithContext(ctx).Model(&model.Transaction{}).
			Where("created_at >= ?", startOfDay).
			Count(&totalTxToday)

		row := r.db.WithContext(ctx).Model(&model.Transaction{}).
			Where("created_at >= ? AND status = ?", startOfDay, model.TxStatusSuccess).
			Select("COALESCE(SUM(amount), 0)").Row()
		_ = row.Scan(&totalVolumeToday)

		return map[string]interface{}{
			"total_users":          totalUsers,
			"active_users":         activeUsers,
			"bound_devices":        activeUsers,
			"total_accounts":       totalUsers,
			"active_banners":       totalBanners,
			"total_transactions":   totalTxToday,
			"transaction_volume":   totalVolumeToday,
			"system_health":        "ONLINE",
			"core_banking_status":  "CONNECTED",
			"last_updated":         time.Now().Format(time.RFC3339),
		}, nil
	}

	// In-memory fallback
	r.mu.RLock()
	defer r.mu.RUnlock()

	var activeUsers int64
	var boundDevices int64
	for _, u := range r.memUsers {
		if u.IsActive {
			activeUsers++
		}
		if u.DeviceID != "" {
			boundDevices++
		}
	}

	var activeBanners int64
	for _, b := range r.memBanners {
		if b.IsActive {
			activeBanners++
		}
	}

	var volume float64
	for _, tx := range r.memTx {
		if tx.Status == model.TxStatusSuccess {
			volume += tx.Amount
		}
	}

	return map[string]interface{}{
		"total_users":         len(r.memUsers),
		"active_users":        activeUsers,
		"bound_devices":       boundDevices,
		"total_accounts":      len(r.memUsers),
		"active_banners":      activeBanners,
		"total_transactions":  len(r.memTx),
		"transaction_volume":  volume,
		"system_health":       "STANDALONE",
		"core_banking_status": "MOCK_ACTIVE",
		"last_updated":        time.Now().Format(time.RFC3339),
	}, nil
}

func (r *adminRepository) ListCustomers(ctx context.Context, search string, page, limit int) ([]model.User, int64, error) {
	if r.db != nil {
		var users []model.User
		var total int64

		query := r.db.WithContext(ctx).Model(&model.User{}).Preload("Accounts")
		if search != "" {
			like := "%" + search + "%"
			query = query.Where("full_name ILIKE ? OR phone_number ILIKE ? OR cif ILIKE ?", like, like, like)
		}

		if err := query.Count(&total).Error; err != nil {
			return nil, 0, err
		}

		offset := (page - 1) * limit
		if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&users).Error; err != nil {
			return nil, 0, err
		}

		return users, total, nil
	}

	// In-memory fallback
	r.mu.RLock()
	defer r.mu.RUnlock()

	var filtered []model.User
	searchLower := strings.ToLower(search)

	for _, u := range r.memUsers {
		if search == "" ||
			strings.Contains(strings.ToLower(u.FullName), searchLower) ||
			strings.Contains(strings.ToLower(u.CIF), searchLower) ||
			strings.Contains(u.PhoneNumber, search) {
			filtered = append(filtered, *u)
		}
	}

	return filtered, int64(len(filtered)), nil
}

func (r *adminRepository) GetCustomerByID(ctx context.Context, id string) (*model.User, error) {
	if r.db != nil {
		var user model.User
		if err := r.db.WithContext(ctx).Preload("Accounts").Where("id = ?", id).First(&user).Error; err == nil {
			return &user, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	user, ok := r.memUsers[id]
	if !ok {
		return nil, gorm.ErrRecordNotFound
	}
	return user, nil
}

func (r *adminRepository) ResetDeviceBinding(ctx context.Context, userID string) error {
	if r.db != nil {
		_ = r.db.WithContext(ctx).Model(&model.User{}).
			Where("id = ?", userID).
			Updates(map[string]interface{}{
				"device_id":  "",
				"updated_at": time.Now(),
			}).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if u, ok := r.memUsers[userID]; ok {
		u.DeviceID = ""
		u.UpdatedAt = time.Now()
	}
	return nil
}

func (r *adminRepository) ToggleCustomerStatus(ctx context.Context, userID string, isActive bool) error {
	if r.db != nil {
		updates := map[string]interface{}{
			"is_active":  isActive,
			"updated_at": time.Now(),
		}
		if isActive {
			updates["failed_login_attempts"] = 0
			updates["failed_pin_attempts"] = 0
		}
		_ = r.db.WithContext(ctx).Model(&model.User{}).
			Where("id = ?", userID).
			Updates(updates).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if u, ok := r.memUsers[userID]; ok {
		u.IsActive = isActive
		if isActive {
			u.FailedLoginAttempts = 0
			u.FailedPINAttempts = 0
		}
		u.UpdatedAt = time.Now()
	}
	return nil
}

func (r *adminRepository) ListBanners(ctx context.Context, activeOnly bool) ([]model.Banner, error) {
	if r.db != nil {
		var banners []model.Banner
		query := r.db.WithContext(ctx).Model(&model.Banner{})
		if activeOnly {
			query = query.Where("is_active = ?", true)
		}
		if err := query.Order("display_order ASC, created_at DESC").Find(&banners).Error; err == nil && len(banners) > 0 {
			return banners, nil
		}
	}

	// In-memory fallback
	r.mu.RLock()
	defer r.mu.RUnlock()

	var result []model.Banner
	for _, b := range r.memBanners {
		if !activeOnly || b.IsActive {
			result = append(result, *b)
		}
	}
	return result, nil
}

func (r *adminRepository) GetBannerByID(ctx context.Context, id string) (*model.Banner, error) {
	if r.db != nil {
		var banner model.Banner
		if err := r.db.WithContext(ctx).Where("id = ?", id).First(&banner).Error; err == nil {
			return &banner, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, b := range r.memBanners {
		if b.ID == id {
			return b, nil
		}
	}
	return nil, gorm.ErrRecordNotFound
}

func (r *adminRepository) CreateBanner(ctx context.Context, banner *model.Banner) error {
	if banner.ID == "" {
		banner.ID = uuid.NewString()
	}
	banner.CreatedAt = time.Now()
	banner.UpdatedAt = time.Now()

	if r.db != nil {
		_ = r.db.WithContext(ctx).Create(banner).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	r.memBanners = append(r.memBanners, banner)
	return nil
}

func (r *adminRepository) UpdateBanner(ctx context.Context, banner *model.Banner) error {
	banner.UpdatedAt = time.Now()

	if r.db != nil {
		_ = r.db.WithContext(ctx).Save(banner).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	for i, b := range r.memBanners {
		if b.ID == banner.ID {
			r.memBanners[i] = banner
			return nil
		}
	}
	r.memBanners = append(r.memBanners, banner)
	return nil
}

func (r *adminRepository) DeleteBanner(ctx context.Context, id string) error {
	if r.db != nil {
		_ = r.db.WithContext(ctx).Where("id = ?", id).Delete(&model.Banner{}).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	newBanners := make([]*model.Banner, 0, len(r.memBanners))
	for _, b := range r.memBanners {
		if b.ID != id {
			newBanners = append(newBanners, b)
		}
	}
	r.memBanners = newBanners
	return nil
}

func (r *adminRepository) ListRecentTransactions(ctx context.Context, limit int) ([]model.Transaction, error) {
	if r.db != nil {
		var txs []model.Transaction
		if limit <= 0 {
			limit = 20
		}
		if err := r.db.WithContext(ctx).Preload("User").Order("created_at DESC").Limit(limit).Find(&txs).Error; err == nil {
			return txs, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	var result []model.Transaction
	for _, tx := range r.memTx {
		result = append(result, *tx)
	}
	return result, nil
}

func (r *adminRepository) GetAppConfig(ctx context.Context) (*model.AppConfig, error) {
	if r.db != nil {
		var cfg model.AppConfig
		if err := r.db.WithContext(ctx).First(&cfg).Error; err == nil {
			return &cfg, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.memConfig, nil
}

func (r *adminRepository) UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error {
	cfg.ID = "DEFAULT"
	cfg.UpdatedAt = time.Now()

	if r.db != nil {
		_ = r.db.WithContext(ctx).Save(cfg).Error
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	r.memConfig = cfg
	return nil
}

func (r *adminRepository) ListAdminUsers(ctx context.Context) ([]model.AdminUser, error) {
	if r.db != nil {
		var admins []model.AdminUser
		if err := r.db.WithContext(ctx).Order("created_at ASC").Find(&admins).Error; err == nil && len(admins) > 0 {
			return admins, nil
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	var result []model.AdminUser
	for _, a := range r.memAdmins {
		result = append(result, *a)
	}
	return result, nil
}

func (r *adminRepository) CreateAdminUser(ctx context.Context, admin *model.AdminUser) error {
	if admin.ID == "" {
		admin.ID = uuid.NewString()
	}
	admin.CreatedAt = time.Now()
	admin.UpdatedAt = time.Now()

	if r.db != nil {
		if err := r.db.WithContext(ctx).Create(admin).Error; err != nil {
			return err
		}
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	r.memAdmins[admin.Username] = admin
	return nil
}

func (r *adminRepository) ToggleAdminStatus(ctx context.Context, id string, isActive bool) error {
	if r.db != nil {
		if err := r.db.WithContext(ctx).Model(&model.AdminUser{}).Where("id = ?", id).Update("is_active", isActive).Error; err != nil {
			return err
		}
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	for _, a := range r.memAdmins {
		if a.ID == id {
			a.IsActive = isActive
			a.UpdatedAt = time.Now()
			break
		}
	}
	return nil
}

func (r *adminRepository) DeleteAdminUser(ctx context.Context, id string) error {
	if r.db != nil {
		if err := r.db.WithContext(ctx).Where("id = ?", id).Delete(&model.AdminUser{}).Error; err != nil {
			return err
		}
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	for u, a := range r.memAdmins {
		if a.ID == id {
			delete(r.memAdmins, u)
			break
		}
	}
	return nil
}

func (r *adminRepository) DB() *gorm.DB {
	return r.db
}

func (r *adminRepository) ListAuditLogs(ctx context.Context, actorType string, limit int) ([]model.AuditLog, error) {
	if r.db == nil {
		return []model.AuditLog{}, nil
	}
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	var logs []model.AuditLog
	query := r.db.WithContext(ctx).Model(&model.AuditLog{})
	if actorType != "" && actorType != "ALL" {
		query = query.Where("actor_type = ?", strings.ToUpper(actorType))
	}
	if err := query.Order("created_at DESC").Limit(limit).Find(&logs).Error; err != nil {
		return []model.AuditLog{}, err
	}
	return logs, nil
}

func (r *adminRepository) ListNotificationsForUser(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	if r.db == nil {
		return []model.Notification{}, nil
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	var notifs []model.Notification
	if err := r.db.WithContext(ctx).
		Where("user_id = ? OR user_id = ?", userID, "ALL").
		Order("created_at DESC").
		Limit(limit).
		Find(&notifs).Error; err != nil {
		return []model.Notification{}, err
	}
	return notifs, nil
}

func (r *adminRepository) MarkNotificationsRead(ctx context.Context, userID string) error {
	if r.db == nil || userID == "" {
		return nil
	}
	return r.db.WithContext(ctx).
		Model(&model.Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Update("is_read", true).Error
}

func (r *adminRepository) UpdateUserFCMToken(ctx context.Context, userID, fcmToken string) error {
	if r.db == nil || userID == "" {
		return nil
	}
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"fcm_token":  fcmToken,
			"updated_at": time.Now(),
		}).Error
}

func (r *adminRepository) ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error) {
	if r.db == nil || userID == "" {
		return []model.SavedBeneficiary{}, nil
	}
	var list []model.SavedBeneficiary
	if err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Find(&list).Error; err != nil {
		return []model.SavedBeneficiary{}, err
	}
	return list, nil
}

func (r *adminRepository) SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error {
	if r.db == nil || b == nil {
		return nil
	}
	var existing model.SavedBeneficiary
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND account_number = ? AND bank_code = ?", b.UserID, b.AccountNumber, b.BankCode).
		First(&existing).Error
	if err == nil {
		return r.db.WithContext(ctx).Model(&existing).Updates(map[string]interface{}{
			"account_name": b.AccountName,
			"bank_name":    b.BankName,
			"nickname":     b.Nickname,
		}).Error
	}
	if b.ID == "" {
		b.ID = uuid.NewString()
	}
	b.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(b).Error
}

func (r *adminRepository) DeleteBeneficiary(ctx context.Context, id string, userID string) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).
		Where("id = ? AND user_id = ?", id, userID).
		Delete(&model.SavedBeneficiary{}).Error
}

func (r *adminRepository) CreateProductApplication(ctx context.Context, app *model.ProductApplication) error {
	if r.db == nil || app == nil {
		return nil
	}
	if app.ID == "" {
		app.ID = uuid.NewString()
	}
	if app.Status == "" {
		app.Status = "PENDING"
	}
	app.CreatedAt = time.Now()
	app.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(app).Error
}

func (r *adminRepository) ListUserApplications(ctx context.Context, userID string) ([]model.ProductApplication, error) {
	if r.db == nil || userID == "" {
		return []model.ProductApplication{}, nil
	}
	var list []model.ProductApplication
	if err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Find(&list).Error; err != nil {
		return []model.ProductApplication{}, err
	}
	return list, nil
}

func (r *adminRepository) ListAllApplications(ctx context.Context, productType string, limit int) ([]model.ProductApplication, error) {
	if r.db == nil {
		return []model.ProductApplication{}, nil
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var list []model.ProductApplication
	q := r.db.WithContext(ctx).Model(&model.ProductApplication{})
	if productType != "" && productType != "ALL" {
		q = q.Where("product_type = ?", strings.ToUpper(productType))
	}
	if err := q.Order("created_at DESC").Limit(limit).Find(&list).Error; err != nil {
		return []model.ProductApplication{}, err
	}
	return list, nil
}

func (r *adminRepository) UpdateApplicationStatus(ctx context.Context, id string, status string, adminNotes string) (*model.ProductApplication, error) {
	if r.db == nil {
		return nil, gorm.ErrInvalidDB
	}
	var app model.ProductApplication
	if err := r.db.WithContext(ctx).Where("id = ?", id).First(&app).Error; err != nil {
		return nil, err
	}
	app.Status = strings.ToUpper(status)
	app.AdminNotes = adminNotes
	app.UpdatedAt = time.Now()
	if err := r.db.WithContext(ctx).Save(&app).Error; err != nil {
		return nil, err
	}
	return &app, nil
}
