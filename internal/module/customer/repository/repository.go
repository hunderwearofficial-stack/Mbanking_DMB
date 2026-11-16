// Package repository berisi akses data fitur layanan nasabah (inbox notifikasi,
// rekening favorit, pengajuan produk). Seluruh query dibatasi user_id pemilik.
package repository

import (
	"context"
	"errors"
	"time"

	"mbanking-bpr/internal/model"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ErrDBUnavailable is returned when the database is not connected (fail-closed).
var ErrDBUnavailable = errors.New("database tidak tersedia")

type CustomerRepository interface {
	DB() *gorm.DB
	GetUserByID(ctx context.Context, id string) (*model.User, error)

	ListNotifications(ctx context.Context, userID string, limit int) ([]model.Notification, error)
	MarkNotificationsRead(ctx context.Context, userID string) error

	ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error)
	SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error
	DeleteBeneficiary(ctx context.Context, id, userID string) error

	CreateProductApplication(ctx context.Context, app *model.ProductApplication) error
	ListProductApplications(ctx context.Context, userID string) ([]model.ProductApplication, error)
}

type customerRepository struct {
	db *gorm.DB
}

func NewCustomerRepository(db *gorm.DB) CustomerRepository {
	return &customerRepository{db: db}
}

func (r *customerRepository) DB() *gorm.DB { return r.db }

func (r *customerRepository) q(ctx context.Context) (*gorm.DB, error) {
	if r.db == nil {
		return nil, ErrDBUnavailable
	}
	return r.db.WithContext(ctx), nil
}

func (r *customerRepository) GetUserByID(ctx context.Context, id string) (*model.User, error) {
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

func (r *customerRepository) ListNotifications(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	var notifs []model.Notification
	if err := db.Where("user_id = ? OR user_id = ?", userID, "ALL").Order("created_at DESC").Limit(limit).Find(&notifs).Error; err != nil {
		return nil, err
	}
	return notifs, nil
}

func (r *customerRepository) MarkNotificationsRead(ctx context.Context, userID string) error {
	db, err := r.q(ctx)
	if err != nil || userID == "" {
		return err
	}
	return db.Model(&model.Notification{}).Where("user_id = ? AND is_read = ?", userID, false).Update("is_read", true).Error
}

func (r *customerRepository) ListBeneficiaries(ctx context.Context, userID string) ([]model.SavedBeneficiary, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var list []model.SavedBeneficiary
	if err := db.Where("user_id = ?", userID).Order("created_at DESC").Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *customerRepository) SaveBeneficiary(ctx context.Context, b *model.SavedBeneficiary) error {
	db, err := r.q(ctx)
	if err != nil || b == nil {
		return err
	}
	var existing model.SavedBeneficiary
	err = db.Where("user_id = ? AND account_number = ? AND bank_code = ?", b.UserID, b.AccountNumber, b.BankCode).First(&existing).Error
	if err == nil {
		return db.Model(&existing).Updates(map[string]interface{}{
			"account_name": b.AccountName, "bank_name": b.BankName, "nickname": b.Nickname,
		}).Error
	}
	b.ID = uuid.NewString()
	b.CreatedAt = time.Now()
	return db.Create(b).Error
}

func (r *customerRepository) DeleteBeneficiary(ctx context.Context, id, userID string) error {
	db, err := r.q(ctx)
	if err != nil {
		return err
	}
	return db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.SavedBeneficiary{}).Error
}

func (r *customerRepository) CreateProductApplication(ctx context.Context, app *model.ProductApplication) error {
	db, err := r.q(ctx)
	if err != nil || app == nil {
		return err
	}
	app.ID = uuid.NewString()
	app.Status = "PENDING"
	app.CreatedAt = time.Now()
	app.UpdatedAt = time.Now()
	return db.Create(app).Error
}

func (r *customerRepository) ListProductApplications(ctx context.Context, userID string) ([]model.ProductApplication, error) {
	db, err := r.q(ctx)
	if err != nil {
		return nil, err
	}
	var list []model.ProductApplication
	if err := db.Where("user_id = ?", userID).Order("created_at DESC").Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}
