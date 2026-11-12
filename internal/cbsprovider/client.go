package cbsprovider

import (
	"context"
	"mbanking-bpr/internal/domain"
)

// CBSProvider is the interface contract for Core Banking System integrations.
// This allows seamless swapping between OpenAPICBSProvider (Live CBS REST API), DatabaseCBSProvider, and MemoryCBSProvider.
type CBSProvider interface {
	Ping(ctx context.Context) (*domain.CBSHealthStatus, error)
	RefreshToken(ctx context.Context) error
	GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error)
	GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error)
	VerifyCredentials(ctx context.Context, username, password, pin string) (*domain.User, error)
	GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error)
	ProcessTransfer(ctx context.Context, req *domain.TransferRequest, fromAccount string) (*domain.TransferResponse, error)

	// Loan (Kredit) Endpoints
	GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error)
	GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error)
	GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	// Deposit (Deposito) Endpoints
	GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error)
	GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error)
	GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	// Products Catalog
	GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error)
}


