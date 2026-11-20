package cbsprovider

import (
	"context"

	"mbanking-bpr/internal/domain"
)

type CBSProvider interface {
	Ping(ctx context.Context) (*domain.CBSHealthStatus, error)
	RefreshToken(ctx context.Context) error
	GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error)
	GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error)
	GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error)

	GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error)
	GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error)
	GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error)
	GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error)
	GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error)
}
