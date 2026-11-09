package repository

import (
	"context"
	"time"

	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

type TransactionRepository interface {
	DB() *gorm.DB
	SaveTransaction(ctx context.Context, tx *model.Transaction) error
	GetUserByID(ctx context.Context, userID string) (*model.User, error)
	IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error)
	ResetFailedPIN(ctx context.Context, userID string) error
}

type transactionRepository struct {
	db *gorm.DB
}

func NewTransactionRepository(db *gorm.DB) TransactionRepository {
	return &transactionRepository{db: db}
}

func (r *transactionRepository) DB() *gorm.DB {
	return r.db
}

func (r *transactionRepository) SaveTransaction(ctx context.Context, tx *model.Transaction) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Create(tx).Error
}

func (r *transactionRepository) GetUserByID(ctx context.Context, userID string) (*model.User, error) {
	if r.db == nil || userID == "" {
		return nil, gorm.ErrRecordNotFound
	}
	var user model.User
	if err := r.db.WithContext(ctx).Where("id = ?", userID).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *transactionRepository) IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error) {
	if r.db == nil || userID == "" {
		return 1, false, nil
	}
	if maxAttempts <= 0 {
		maxAttempts = 3
	}
	var user model.User
	if err := r.db.WithContext(ctx).Where("id = ?", userID).First(&user).Error; err != nil {
		return 1, false, err
	}
	attempts := user.FailedPINAttempts + 1
	blocked := attempts >= maxAttempts
	updates := map[string]interface{}{
		"failed_pin_attempts": attempts,
		"updated_at":          time.Now(),
	}
	if blocked {
		updates["is_active"] = false
	}
	_ = r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
	return attempts, blocked, nil
}

func (r *transactionRepository) ResetFailedPIN(ctx context.Context, userID string) error {
	if r.db == nil || userID == "" {
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"failed_pin_attempts": 0,
		"updated_at":          time.Now(),
	}).Error
}
