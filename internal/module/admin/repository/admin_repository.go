package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrDBUnavailable          = errors.New("database tidak tersedia")
	ErrSelfApproval           = errors.New("pembuat permintaan tidak dapat menyetujui atau menolak permintaannya sendiri")
	ErrApplicationFinalStatus = errors.New("pengajuan yang sudah selesai atau dibatalkan tidak dapat ditindaklanjuti lagi")
)

type CustomerSummary struct {
	ID                   string    `json:"id"`
	CIF                  string    `json:"cif"`
	FullName             string    `json:"full_name"`
	PhoneNumber          string    `json:"phone_number"`
	Email                string    `json:"email"`
	DeviceBound          bool      `json:"device_bound"`
	DeviceID             string    `json:"device_id"`
	IsActive             bool      `json:"is_active"`
	Activated            bool      `json:"activated"`
	FailedLoginAttempts  int       `json:"failed_login_attempts"`
	FailedPINAttempts    int       `json:"failed_pin_attempts"`
	AccountNumbers       []string  `json:"account_numbers"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`
	DeviceKeyAlgorithm   string    `json:"device_key_algorithm"`
	DeviceSecurityLevel  string    `json:"device_security_level"`
	DeviceAttestation    string    `json:"device_attestation_status"`
	DeviceKeyEnrolledVia string    `json:"device_key_enrolled_via"`
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

	ListAdminUsers(ctx context.Context) ([]model.AdminUser, error)
	CreateAdminUser(ctx context.Context, admin *model.AdminUser) error
	UpdateAdminUser(ctx context.Context, id string, fullName, email, role, passwordHash string) error
	UpdateAdminPassword(ctx context.Context, id, passwordHash string) error
	ToggleAdminStatus(ctx context.Context, id string, isActive bool) error
	DeleteAdminUser(ctx context.Context, id string) error

	RecordAdminLoginFailure(ctx context.Context, id string, maxAttempts int, lockDuration time.Duration) (*time.Time, int, error)
	ResetAdminLoginFailures(ctx context.Context, id string) error
	SetAdminTOTP(ctx context.Context, id, encryptedSecret string, enabled bool, step int64) error
	AdvanceAdminTOTPStep(ctx context.Context, id string, step int64) (bool, error)

	CreateApproval(ctx context.Context, req *model.ApprovalRequest) error
	GetApproval(ctx context.Context, id string) (*model.ApprovalRequest, error)
	ListApprovals(ctx context.Context, status string, limit int) ([]model.ApprovalRequest, error)
	DecideApproval(ctx context.Context, id, status, decidedBy, decidedByName, note string) (*model.ApprovalRequest, error)
	RunApprovalTx(ctx context.Context, id, decidedBy, decidedByName, note string, fn func(tx *gorm.DB, req *model.ApprovalRequest) error) (*model.ApprovalRequest, error)
	SetBannerActive(ctx context.Context, id string, active bool) error

	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	UpdateAppConfig(ctx context.Context, cfg *model.AppConfig) error

	DB() *gorm.DB
	ListAuditLogs(ctx context.Context, f AuditLogFilter) ([]model.AuditLog, error)
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
	var totalUsers, activeUsers, boundDevices, totalBanners, totalAccounts int64

	if err := errors.Join(
		db.Model(&model.User{}).Count(&totalUsers).Error,
		db.Model(&model.User{}).Where("is_active = ?", true).Count(&activeUsers).Error,
		db.Model(&model.User{}).Where("device_id <> ''").Count(&boundDevices).Error,
		db.Model(&model.Banner{}).Where("is_active = ?", true).Count(&totalBanners).Error,
		db.Model(&model.Account{}).Count(&totalAccounts).Error,
	); err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"total_users":    totalUsers,
		"active_users":   activeUsers,
		"bound_devices":  boundDevices,
		"total_accounts": totalAccounts,
		"active_banners": totalBanners,
		"system_health":  "ONLINE",
		"last_updated":   time.Now().Format(time.RFC3339),
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
		// Audit H-3: digits are a phone number or CIF prefix (index-backed, 0019); text
		// searches the name.
		if strings.Trim(s, "0123456789") == "" {
			prefix := escapeLike(s) + "%"
			query = query.Where("phone_number LIKE ? OR cif LIKE ?", prefix, prefix)
		} else {
			query = query.Where("full_name ILIKE ?", "%"+escapeLike(s)+"%")
		}
	}
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if err := query.Order("created_at DESC").Limit(limit).Offset((page - 1) * limit).Find(&users).Error; err != nil {
		return nil, 0, err
	}
	ids := make([]string, 0, len(users))
	for _, u := range users {
		ids = append(ids, u.ID)
	}
	type keyRow struct{ UserID, Algorithm, SecurityLevel, AttestationStatus, EnrolledVia string }
	var keys []keyRow
	if len(ids) > 0 {
		if err := db.Raw(`SELECT user_id, algorithm, security_level, attestation_status, enrolled_via FROM device_keys WHERE status = 'ACTIVE' AND user_id IN ?`, ids).Scan(&keys).Error; err != nil {
			return nil, 0, err
		}
	}
	byUser := map[string]keyRow{}
	for _, k := range keys {
		byUser[k.UserID] = k
	}
	out := make([]CustomerSummary, 0, len(users))
	for _, u := range users {
		k := byUser[u.ID]
		accs := make([]string, 0, len(u.Accounts))
		for _, a := range u.Accounts {
			accs = append(accs, a.AccountNumber)
		}
		email := strings.TrimSpace(string(u.Email))
		if d, derr := crypto.DecryptString(email); derr == nil && d != "" {
			email = d
		}
		out = append(out, CustomerSummary{
			ID: u.ID, CIF: u.CIF, FullName: u.FullName, PhoneNumber: u.PhoneNumber, Email: email,
			DeviceBound: u.DeviceID != "", DeviceID: u.DeviceID, IsActive: u.IsActive, Activated: u.PasswordHash != "",
			FailedLoginAttempts: u.FailedLoginAttempts, FailedPINAttempts: u.FailedPINAttempts,
			AccountNumbers: accs, CreatedAt: u.CreatedAt, UpdatedAt: u.UpdatedAt,
			DeviceKeyAlgorithm: k.Algorithm, DeviceSecurityLevel: k.SecurityLevel, DeviceAttestation: k.AttestationStatus, DeviceKeyEnrolledVia: k.EnrolledVia,
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
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.User{}).Where("id = ?", userID).
			Updates(map[string]interface{}{"device_id": "", "device_enroll_until": nil, "updated_at": time.Now()}).Error; err != nil {
			return err
		}
		_, err := devicebind.RevokeUserKeys(tx, userID, "ADMIN_RESET")
		return err
	})
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
	return db.Model(&model.AppConfig{}).Where("id = ?", "DEFAULT").Select(
		"bank_name", "bank_short_name", "tagline", "logo_url",
		"login_bg_url", "splash_bg_url", "onboarding_bg_url",
		"welcome_title", "welcome_subtitle", "login_title", "login_subtitle",
		"terms_version", "home_greeting", "announcement_text", "terms_pdf_url", "privacy_pdf_url", "quick_menu_config",
		"call_center", "whats_app_cs", "email_cs", "website_url", "head_office_address",
		"maintenance_mode", "maintenance_message", "enforce_device_binding", "max_login_attempts", "otp_provider",
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

func (r *adminRepository) UpdateAdminUser(ctx context.Context, id string, fullName, email, role, passwordHash string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{
		"full_name":  fullName,
		"email":      email,
		"role":       role,
		"updated_at": time.Now(),
	}
	if passwordHash != "" {
		updates["password_hash"] = passwordHash
		updates["failed_login_attempts"] = 0
		updates["locked_until"] = nil
		updates["password_changed_at"] = time.Now()
	}
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(updates).Error
}

func (r *adminRepository) UpdateAdminPassword(ctx context.Context, id, passwordHash string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	now := time.Now()
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(map[string]interface{}{
		"password_hash":         passwordHash,
		"failed_login_attempts": 0,
		"locked_until":          nil,
		"must_change_password":  false,
		"password_changed_at":   now,
		"updated_at":            now,
	}).Error
}

func (r *adminRepository) ToggleAdminStatus(ctx context.Context, id string, isActive bool) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{"is_active": isActive, "updated_at": time.Now()}
	if isActive {
		// Re-activation by a SUPER_ADMIN also lifts a login lockout.
		updates["failed_login_attempts"] = 0
		updates["locked_until"] = nil
	}
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(updates).Error
}

func (r *adminRepository) DeleteAdminUser(ctx context.Context, id string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Where("id = ?", id).Delete(&model.AdminUser{}).Error
}

func (r *adminRepository) RecordAdminLoginFailure(ctx context.Context, id string, maxAttempts int, lockDuration time.Duration) (*time.Time, int, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, 0, err
	}
	if maxAttempts <= 0 {
		maxAttempts = 5
	}
	if lockDuration <= 0 {
		lockDuration = 15 * time.Minute
	}
	var attempts int
	var lockedUntil *time.Time
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		if err := tx.Model(&model.AdminUser{}).Where("id = ?", id).
			Updates(map[string]interface{}{
				"failed_login_attempts": gorm.Expr("failed_login_attempts + 1"),
				"updated_at":            now,
			}).Error; err != nil {
			return err
		}
		var admin model.AdminUser
		if err := tx.Where("id = ?", id).First(&admin).Error; err != nil {
			return err
		}
		attempts = admin.FailedLoginAttempts
		if attempts >= maxAttempts {
			lu := now.Add(lockDuration)
			lockedUntil = &lu
			return tx.Model(&model.AdminUser{}).Where("id = ?", id).
				Update("locked_until", lu).Error
		}
		return nil
	})
	return lockedUntil, attempts, err
}

func (r *adminRepository) ResetAdminLoginFailures(ctx context.Context, id string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(map[string]interface{}{
		"failed_login_attempts": 0,
		"locked_until":          nil,
		"updated_at":            time.Now(),
	}).Error
}

func (r *adminRepository) SetAdminTOTP(ctx context.Context, id, encryptedSecret string, enabled bool, step int64) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Model(&model.AdminUser{}).Where("id = ?", id).Updates(map[string]interface{}{
		"totp_secret":    encryptedSecret,
		"totp_enabled":   enabled,
		"totp_last_step": step,
		"updated_at":     time.Now(),
	}).Error
}

func (r *adminRepository) AdvanceAdminTOTPStep(ctx context.Context, id string, step int64) (bool, error) {
	db, err := r.q(ctx)
	if err != nil {
		return false, err
	}
	res := db.Model(&model.AdminUser{}).Where("id = ? AND totp_last_step < ?", id, step).Updates(map[string]interface{}{
		"totp_last_step": step,
		"updated_at":     time.Now(),
	})
	return res.RowsAffected == 1, res.Error
}

func (r *adminRepository) CreateApproval(ctx context.Context, req *model.ApprovalRequest) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	if req.ID == "" {
		req.ID = uuid.NewString()
	}
	if req.Status == "" {
		req.Status = model.ApprovalPending
	}
	if req.RequestedAt.IsZero() {
		req.RequestedAt = time.Now()
	}
	return db.Create(req).Error
}

func (r *adminRepository) GetApproval(ctx context.Context, id string) (*model.ApprovalRequest, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var req model.ApprovalRequest
	if err := db.Where("id = ?", id).First(&req).Error; err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *adminRepository) ListApprovals(ctx context.Context, status string, limit int) ([]model.ApprovalRequest, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	limit = clampLimit(limit, 50, 200)
	var list []model.ApprovalRequest
	q := db.Model(&model.ApprovalRequest{})
	if status != "" && status != "ALL" {
		q = q.Where("status = ?", strings.ToUpper(status))
	}
	if err := q.Order("requested_at DESC").Limit(limit).Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *adminRepository) DecideApproval(ctx context.Context, id, status, decidedBy, decidedByName, note string) (*model.ApprovalRequest, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var req model.ApprovalRequest
	err = db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", id).First(&req).Error; err != nil {
			return err
		}
		if req.Status != model.ApprovalPending {
			return errors.New("permintaan persetujuan sudah diproses")
		}
		now := time.Now()
		updates := map[string]interface{}{
			"status":          status,
			"decided_by":      decidedBy,
			"decided_by_name": decidedByName,
			"decided_at":      now,
			"decision_note":   note,
		}
		if err := tx.Model(&model.ApprovalRequest{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			return err
		}
		return tx.Where("id = ?", id).First(&req).Error
	})
	if err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *adminRepository) RunApprovalTx(ctx context.Context, id, decidedBy, decidedByName, note string, fn func(tx *gorm.DB, req *model.ApprovalRequest) error) (*model.ApprovalRequest, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var req model.ApprovalRequest
	err = db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", id).First(&req).Error; err != nil {
			return err
		}
		if req.Status != model.ApprovalPending {
			return errors.New("permintaan persetujuan sudah diproses")
		}
		if req.RequestedBy != "" && req.RequestedBy == decidedBy {
			return ErrSelfApproval
		}
		if fn != nil {
			if err := fn(tx, &req); err != nil {
				return err
			}
		}
		now := time.Now()
		updates := map[string]interface{}{
			"status":          model.ApprovalApproved,
			"decided_by":      decidedBy,
			"decided_by_name": decidedByName,
			"decided_at":      now,
			"decision_note":   note,
		}
		if err := tx.Model(&model.ApprovalRequest{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			return err
		}
		return tx.Where("id = ?", id).First(&req).Error
	})
	if err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *adminRepository) SetBannerActive(ctx context.Context, id string, active bool) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Model(&model.Banner{}).Where("id = ?", id).Updates(map[string]interface{}{
		"is_active":  active,
		"updated_at": time.Now(),
	}).Error
}

// AuditLogFilter selects audit entries (audit H-4): actor type, action, search text, a date range and keyset
// paging on seq (BeforeSeq = the smallest seq of the previous page).
type AuditLogFilter struct {
	ActorType string
	Action    string
	Search    string
	From, To  *time.Time
	BeforeSeq int64
	Limit     int
}

func (r *adminRepository) ListAuditLogs(ctx context.Context, f AuditLogFilter) ([]model.AuditLog, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	limit := clampLimit(f.Limit, 100, 500)
	var logs []model.AuditLog
	query := db.Model(&model.AuditLog{})
	if f.ActorType != "" && f.ActorType != "ALL" {
		query = query.Where("actor_type = ?", strings.ToUpper(strings.TrimSpace(f.ActorType)))
	}
	if act := strings.TrimSpace(f.Action); act != "" && !strings.EqualFold(act, "ALL") {
		query = query.Where("action = ?", strings.ToUpper(act))
	}
	if s := strings.TrimSpace(f.Search); s != "" {
		if len(s) > 100 {
			s = s[:100]
		}
		pat := "%" + escapeLike(s) + "%"
		query = query.Where("action ILIKE ? OR actor_name ILIKE ? OR target ILIKE ? OR details ILIKE ?", pat, pat, pat, pat)
	}
	if f.From != nil {
		query = query.Where("created_at >= ?", *f.From)
	}
	if f.To != nil {
		query = query.Where("created_at < ?", *f.To)
	}
	if f.BeforeSeq > 0 {
		query = query.Where("seq < ?", f.BeforeSeq)
	}
	if err := query.Order("seq DESC").Limit(limit).Find(&logs).Error; err != nil {
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
	existing := strings.ToUpper(strings.TrimSpace(app.Status))
	if existing == "APPROVED" || existing == "REJECTED" {
		return nil, ErrApplicationFinalStatus
	}
	app.Status = strings.ToUpper(status)
	app.AdminNotes = adminNotes
	app.UpdatedAt = time.Now()
	if err := db.Save(&app).Error; err != nil {
		return nil, err
	}
	return &app, nil
}
