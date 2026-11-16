package repository

import (
	"context"
	"errors"
	"mbanking-bpr/pkg/money"
	"time"

	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	// ErrDuplicateRequest is returned with the existing record when the idempotency key was already used.
	ErrDuplicateRequest = errors.New("idempotency key sudah digunakan")
	// ErrDailyLimitExceeded is returned when the reservation would exceed the daily limit.
	ErrDailyLimitExceeded = errors.New("melebihi batas limit transfer harian")
)

type TransactionRepository interface {
	DB() *gorm.DB
	SaveTransaction(ctx context.Context, tx *model.Transaction) error
	GetUserByID(ctx context.Context, userID string) (*model.User, error)
	IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error)
	ResetFailedPIN(ctx context.Context, userID string) error
	GetAppConfig(ctx context.Context) (*model.AppConfig, error)
	// ReserveTransfer atomically checks idempotency and the daily limit and records a PENDING request.
	// It returns (existing, ErrDuplicateRequest) if the key was used, or (nil, ErrDailyLimitExceeded) with
	// the amount already used today.
	ReserveTransfer(ctx context.Context, req *model.TransferRequest, dailyLimit money.Amount) (*model.TransferRequest, money.Amount, error)
	CompleteTransfer(ctx context.Context, id, status, cbsRef, responseJSON, failure string) error
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
		return gorm.ErrInvalidDB
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

// IncrementFailedPIN atomically increments the PIN failure counter and blocks the
// account at maxAttempts (audit DMB-018).
func (r *transactionRepository) IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error) {
	if r.db == nil || userID == "" {
		return 0, false, gorm.ErrInvalidDB
	}
	if maxAttempts <= 0 {
		maxAttempts = 3
	}
	var attempts int
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
			"failed_pin_attempts": gorm.Expr("failed_pin_attempts + 1"), "updated_at": time.Now(),
		}).Error; err != nil {
			return err
		}
		if err := tx.Model(&model.User{}).Where("id = ?", userID).Select("failed_pin_attempts").Scan(&attempts).Error; err != nil {
			return err
		}
		if attempts >= maxAttempts {
			return tx.Model(&model.User{}).Where("id = ?", userID).Update("is_active", false).Error
		}
		return nil
	})
	if err != nil {
		return 0, false, err
	}
	return attempts, attempts >= maxAttempts, nil
}

func (r *transactionRepository) ResetFailedPIN(ctx context.Context, userID string) error {
	if r.db == nil || userID == "" {
		return gorm.ErrInvalidDB
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"failed_pin_attempts": 0, "updated_at": time.Now(),
	}).Error
}

func (r *transactionRepository) GetAppConfig(ctx context.Context) (*model.AppConfig, error) {
	if r.db == nil {
		return nil, gorm.ErrInvalidDB
	}
	var cfg model.AppConfig
	if err := r.db.WithContext(ctx).First(&cfg).Error; err != nil {
		return nil, err
	}
	return &cfg, nil
}

func startOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

func (r *transactionRepository) ReserveTransfer(ctx context.Context, req *model.TransferRequest, dailyLimit money.Amount) (*model.TransferRequest, money.Amount, error) {
	if r.db == nil {
		return nil, 0, gorm.ErrInvalidDB
	}
	var existing *model.TransferRequest
	var used money.Amount
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Serialize all transfer reservations of this customer.
		var u model.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Select("id").Where("id = ?", req.UserID).First(&u).Error; err != nil {
			return err
		}

		var prev model.TransferRequest
		err := tx.Where("user_id = ? AND idempotency_key = ?", req.UserID, req.IdempotencyKey).First(&prev).Error
		if err == nil {
			existing = &prev
			return ErrDuplicateRequest
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}

		// PENDING and UNKNOWN reservations count against the limit until resolved.
		if err := tx.Model(&model.TransferRequest{}).
			Where("user_id = ? AND created_at >= ? AND status IN ?", req.UserID, startOfDay(time.Now()),
				[]string{model.TransferReqPending, model.TransferReqSuccess, model.TransferReqUnknown}).
			Select("COALESCE(SUM(amount), 0)").Scan(&used).Error; err != nil {
			return err
		}
		if used+req.Amount > dailyLimit {
			return ErrDailyLimitExceeded
		}
		req.Status = model.TransferReqPending
		return tx.Create(req).Error
	})
	return existing, used, err
}

func (r *transactionRepository) CompleteTransfer(ctx context.Context, id, status, cbsRef, responseJSON, failure string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	if len(failure) > 255 {
		failure = failure[:255]
	}
	return r.db.WithContext(ctx).Model(&model.TransferRequest{}).Where("id = ?", id).Updates(map[string]interface{}{
		"status": status, "cbs_reference_no": cbsRef, "response_json": responseJSON, "failure_reason": failure, "updated_at": time.Now(),
	}).Error
}
