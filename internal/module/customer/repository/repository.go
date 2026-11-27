package repository

import (
	"context"
	"errors"
	"time"

	"mbanking-bpr/internal/model"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

var ErrDBUnavailable = errors.New("database tidak tersedia")

type CustomerRepository interface {
	DB() *gorm.DB
	GetUserByID(ctx context.Context, id string) (*model.User, error)

	ListNotifications(ctx context.Context, userID string, limit int) ([]model.Notification, error)
	MarkNotificationsRead(ctx context.Context, userID string) error

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
	if err := db.Table("notifications n").
		Select("n.id, n.user_id, n.title, n.message, n.category, (n.is_read OR nr.notification_id IS NOT NULL) AS is_read, n.created_at").
		Joins("LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = ?", userID).
		Where("n.user_id = ? OR n.user_id = ?", userID, "ALL").
		Order("n.created_at DESC").
		Limit(limit).
		Scan(&notifs).Error; err != nil {
		return nil, err
	}
	return notifs, nil
}

func (r *customerRepository) MarkNotificationsRead(ctx context.Context, userID string) error {
	db, err := r.q(ctx)
	if err != nil || userID == "" {
		return err
	}
	if err := db.Model(&model.Notification{}).Where("user_id = ? AND is_read = ?", userID, false).Update("is_read", true).Error; err != nil {
		return err
	}
	return db.Exec(
		`INSERT INTO notification_reads (user_id, notification_id, read_at)
		 SELECT ?, id, NOW() FROM notifications WHERE user_id = 'ALL'
		 ON CONFLICT (user_id, notification_id) DO NOTHING`,
		userID,
	).Error
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
