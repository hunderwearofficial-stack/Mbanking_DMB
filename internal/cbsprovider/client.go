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
	GetMutations(ctx context.Context, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error)
	ProcessTransfer(ctx context.Context, req *domain.TransferRequest, fromAccount string) (*domain.TransferResponse, error)
}


