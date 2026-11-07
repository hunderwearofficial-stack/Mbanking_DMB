package service

import (
	"context"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/account/repository"
)

type AccountService interface {
	GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, accountNo string, query domain.MutationQueryParam) ([]domain.Mutation, error)
	GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error)
	GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error)
}

type accountService struct {
	repo    repository.AccountRepository
	cbsProv cbsprovider.CBSProvider
}

func NewAccountService(repo repository.AccountRepository, cbsProv cbsprovider.CBSProvider) AccountService {
	return &accountService{
		repo:    repo,
		cbsProv: cbsProv,
	}
}

func (s *accountService) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	// 1. Primary: Query Live Core Banking System (CBS OpenAPI /api/savings-account-balance)
	// OpenAPICBSProvider also syncs the latest balance & holder name into PostgreSQL automatically.
	res, err := s.cbsProv.GetBalance(ctx, accountNo)
	if err == nil && res != nil {
		return res, nil
	}

	// 2. Fallback: Read from local PostgreSQL if CBS is unreachable
	acc, dbErr := s.repo.FindAccountByNumber(ctx, accountNo)
	if dbErr == nil && acc != nil {
		return &domain.BalanceResponse{
			AccountNumber:    acc.AccountNumber,
			AccountType:      acc.AccountType,
			Balance:          acc.Balance,
			EffectiveBalance: acc.Balance,
			Status:           acc.Status,
			UpdatedAt:        acc.UpdatedAt,
		}, nil
	}

	return nil, err
}

func (s *accountService) GetMutations(ctx context.Context, accountNo string, query domain.MutationQueryParam) ([]domain.Mutation, error) {
	limit := query.Limit
	if limit <= 0 {
		limit = 20
	}

	// 1. Read from PostgreSQL (which stores synchronized CBS overbooking mutations)
	mutations, err := s.repo.FindMutationsByAccount(ctx, accountNo, limit)
	if err == nil && len(mutations) > 0 {
		return mutations, nil
	}

	// 2. Fallback to CBS Provider
	return s.cbsProv.GetMutations(ctx, accountNo, "", "", limit)
}

func (s *accountService) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	return s.cbsProv.GetCustomerByCIF(ctx, cifNumber)
}

func (s *accountService) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	return s.cbsProv.GetSavingsAccountsByCIF(ctx, cifNumber)
}

