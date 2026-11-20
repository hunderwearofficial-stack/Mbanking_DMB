package cbsprovider

import (
	"context"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

type DatabaseCBSProvider struct {
	db *gorm.DB
}

func NewDatabaseCBSProvider(db *gorm.DB) *DatabaseCBSProvider {
	return &DatabaseCBSProvider{db: db}
}

func (p *DatabaseCBSProvider) Ping(ctx context.Context) (*domain.CBSHealthStatus, error) {
	return &domain.CBSHealthStatus{
		Connected: true,
		Status:    "OK",
		Code:      10000,
		Message:   "Database CBS Engine Active",
		Timestamp: time.Now().Format(time.RFC3339),
	}, nil
}

func (p *DatabaseCBSProvider) RefreshToken(ctx context.Context) error {
	return nil
}

func (p *DatabaseCBSProvider) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}
	var user model.User
	if err := p.db.WithContext(ctx).Where("cif = ?", cifNumber).First(&user).Error; err != nil {
		return nil, ErrAccountNotFound
	}
	return &domain.CBSNasabahData{
		CIF:   user.CIF,
		Nama:  user.FullName,
		NoHP:  user.PhoneNumber,
		Email: string(user.Email),
	}, nil
}

func (p *DatabaseCBSProvider) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}
	var user model.User
	if err := p.db.WithContext(ctx).Preload("Accounts").Where("cif = ?", cifNumber).First(&user).Error; err != nil {
		return nil, ErrAccountNotFound
	}
	var items []domain.CBSSavingsAccountItem
	for _, acc := range user.Accounts {
		items = append(items, domain.CBSSavingsAccountItem{
			NomorRekening:  acc.AccountNumber,
			Nama:           user.FullName,
			ProdukTabungan: acc.AccountType,
			Saldo:          acc.Balance,
		})
	}
	return items, nil
}

func (p *DatabaseCBSProvider) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}

	var account model.Account
	err := p.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		First(&account).Error
	if err != nil {
		return nil, ErrAccountNotFound
	}

	if account.Status != model.AccountStatusActive {
		return nil, ErrInactiveAccount
	}

	return &domain.BalanceResponse{
		AccountNumber:    account.AccountNumber,
		HolderName:       account.HolderName,
		ProductCode:      account.ProductCode,
		AccountType:      account.AccountType,
		Balance:          account.Balance,
		MinimumBalance:   account.MinimumBalance,
		BlockedBalance:   account.BlockedBalance,
		EffectiveBalance: account.EffectiveBalance,
		Status:           account.Status,
		UpdatedAt:        account.UpdatedAt,
	}, nil
}

func (p *DatabaseCBSProvider) GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if p.db == nil {
		return []domain.Mutation{}, nil
	}

	if limit <= 0 || limit > 50 {
		limit = 20
	}

	var rows []model.Mutation
	query := p.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		Order("created_at DESC").
		Limit(limit)

	if startDate != "" {
		if start, err := time.Parse("2006-01-02", startDate); err == nil {
			query = query.Where("created_at >= ?", start)
		}
	}
	if endDate != "" {
		if end, err := time.Parse("2006-01-02", endDate); err == nil {
			query = query.Where("created_at <= ?", end.Add(24*time.Hour))
		}
	}

	if err := query.Find(&rows).Error; err != nil {
		return nil, err
	}

	return rows, nil
}

func (p *DatabaseCBSProvider) GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error) {
	return []domain.DMBLoanAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	return nil, ErrAccountNotFound
}

func (p *DatabaseCBSProvider) GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error) {
	return []domain.DMBDepositAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	return nil, ErrAccountNotFound
}

func (p *DatabaseCBSProvider) GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{}, nil
}

func (p *DatabaseCBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	return nil, ErrCBSUnavailable
}
