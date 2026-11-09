package service

import (
	"context"
	"strings"
	"time"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/account/repository"
)

type AccountService interface {
	GetBalance(ctx context.Context, accountNo, cifNo, userID string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, accountNo, cifNo, userID string, query domain.MutationQueryParam) ([]domain.Mutation, error)
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

func (s *accountService) GetBalance(ctx context.Context, accountNo, cifNo, userID string) (*domain.BalanceResponse, error) {
	accNo := strings.TrimSpace(accountNo)
	cif := strings.TrimSpace(cifNo)

	// Layer 1: Query Live CBS OpenAPI (/api/savings-account-balance) if accountNo is provided
	if accNo != "" && accNo != cif {
		if res, err := s.cbsProv.GetBalance(ctx, accNo); err == nil && res != nil {
			return res, nil
		}
	}

	// Layer 2: Query Live CBS OpenAPI (/api/savings-accounts) by CIF if Layer 1 didn't resolve
	if cif != "" && s.cbsProv != nil {
		if items, err := s.cbsProv.GetSavingsAccountsByCIF(ctx, cif); err == nil && len(items) > 0 {
			selected := items[0]
			for _, it := range items {
				if accNo != "" && it.NomorRekening == accNo {
					selected = it
					break
				}
			}
			// Try getting full balance details from CBS /api/savings-account-balance for this account
			if res, balErr := s.cbsProv.GetBalance(ctx, selected.NomorRekening); balErr == nil && res != nil {
				return res, nil
			}
			return &domain.BalanceResponse{
				AccountNumber:    selected.NomorRekening,
				HolderName:       selected.Nama,
				ProductCode:      selected.ProdukTabungan,
				AccountType:      "Tabungan Mandiri DMB",
				Balance:          selected.Saldo,
				EffectiveBalance: selected.Saldo,
				Status:           model.AccountStatusActive,
				UpdatedAt:        time.Now(),
			}, nil
		}
	}

	// Layer 3: Resolve or Auto-Heal from Local PostgreSQL by userID / cifNo / accountNo
	acc, dbErr := s.repo.FindOrCreateAccountByUserOrCIF(ctx, userID, cif, accNo)
	if dbErr == nil && acc != nil {
		// If DB resolved an account number that wasn't tried yet against CBS Layer 1, try CBS once
		if accNo == "" && acc.AccountNumber != "" && s.cbsProv != nil {
			if res, cbsErr := s.cbsProv.GetBalance(ctx, acc.AccountNumber); cbsErr == nil && res != nil {
				return res, nil
			}
		}

		holderName := acc.HolderName
		if holderName == "" && acc.User != nil {
			holderName = acc.User.FullName
		}
		effBal := acc.EffectiveBalance
		if effBal == 0 && acc.Balance > 0 {
			effBal = acc.Balance
		}
		return &domain.BalanceResponse{
			AccountNumber:    acc.AccountNumber,
			HolderName:       holderName,
			ProductCode:      acc.ProductCode,
			AccountType:      acc.AccountType,
			Balance:          acc.Balance,
			MinimumBalance:   acc.MinimumBalance,
			BlockedBalance:   acc.BlockedBalance,
			EffectiveBalance: effBal,
			Status:           acc.Status,
			UpdatedAt:        acc.UpdatedAt,
		}, nil
	}

	// Final fallback to CBS provider if accountNo was given (e.g. recipient account inquiry)
	if accNo != "" && s.cbsProv != nil {
		return s.cbsProv.GetBalance(ctx, accNo)
	}

	return nil, cbsprovider.ErrAccountNotFound
}

func (s *accountService) GetMutations(ctx context.Context, accountNo, cifNo, userID string, query domain.MutationQueryParam) ([]domain.Mutation, error) {
	limit := query.Limit
	if limit <= 0 {
		limit = 20
	}

	accNo := strings.TrimSpace(accountNo)
	if accNo == "" {
		if acc, err := s.repo.FindOrCreateAccountByUserOrCIF(ctx, userID, cifNo, ""); err == nil && acc != nil {
			accNo = acc.AccountNumber
		}
	}

	if accNo != "" {
		// 1. Read from PostgreSQL (which stores synchronized CBS overbooking mutations)
		mutations, err := s.repo.FindMutationsByAccount(ctx, accNo, limit)
		if err == nil && len(mutations) > 0 {
			return mutations, nil
		}

		// 2. Fallback to CBS Provider
		if s.cbsProv != nil {
			if cbsMuts, cbsErr := s.cbsProv.GetMutations(ctx, accNo, "", "", limit); cbsErr == nil && cbsMuts != nil {
				return cbsMuts, nil
			}
		}
	}

	return []domain.Mutation{}, nil
}

func (s *accountService) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	return s.cbsProv.GetCustomerByCIF(ctx, cifNumber)
}

func (s *accountService) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	return s.cbsProv.GetSavingsAccountsByCIF(ctx, cifNumber)
}

