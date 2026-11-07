package repository

import (
	"context"
	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

type AccountRepository interface {
	FindAccountByNumber(ctx context.Context, accountNo string) (*model.Account, error)
	FindMutationsByAccount(ctx context.Context, accountNo string, limit int) ([]model.Mutation, error)
	SaveAccount(ctx context.Context, account *model.Account) error
}

type accountRepository struct {
	db *gorm.DB
}

func NewAccountRepository(db *gorm.DB) AccountRepository {
	return &accountRepository{db: db}
}

func (r *accountRepository) FindAccountByNumber(ctx context.Context, accountNo string) (*model.Account, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	var account model.Account
	err := r.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		First(&account).Error
	if err != nil {
		return nil, err
	}
	return &account, nil
}

func (r *accountRepository) FindMutationsByAccount(ctx context.Context, accountNo string, limit int) ([]model.Mutation, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var mutations []model.Mutation
	err := r.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		Order("created_at DESC").
		Limit(limit).
		Find(&mutations).Error
	if err != nil {
		return nil, err
	}
	return mutations, nil
}

func (r *accountRepository) SaveAccount(ctx context.Context, account *model.Account) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Save(account).Error
}
