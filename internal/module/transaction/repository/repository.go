package repository

import (
	"context"
	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

type TransactionRepository interface {
	SaveTransaction(ctx context.Context, tx *model.Transaction) error
}

type transactionRepository struct {
	db *gorm.DB
}

func NewTransactionRepository(db *gorm.DB) TransactionRepository {
	return &transactionRepository{db: db}
}

func (r *transactionRepository) SaveTransaction(ctx context.Context, tx *model.Transaction) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Create(tx).Error
}
