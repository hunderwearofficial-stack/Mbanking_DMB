package service

import (
	"context"
	"errors"
	"strings"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/ownership"
)

// Caller is the authenticated customer (always derived from the verified token).
type Caller struct {
	UserID       string
	CIF          string
	TokenAccount string
}

var ErrForbidden = ownership.ErrNotOwned

// AccountService enforces object-level authorization on every read (audit DMB-005):
// the CIF always comes from the token, and any account number supplied by the
// client must belong to that CIF.
type AccountService interface {
	GetBalance(ctx context.Context, caller Caller, requestedAccount string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, caller Caller, query domain.MutationQueryParam) (string, []domain.Mutation, error)
	InquiryRecipient(ctx context.Context, accountNo string) (*domain.BalanceResponse, error)
	GetCustomerProfile(ctx context.Context, caller Caller) (*domain.CBSNasabahData, error)
	GetSavingsAccounts(ctx context.Context, caller Caller) ([]domain.CBSSavingsAccountItem, error)

	GetLoans(ctx context.Context, caller Caller) ([]domain.DMBLoanAccountItem, error)
	GetLoanDetail(ctx context.Context, caller Caller, accountNo string) (*domain.DMBLoanAccountDetail, error)
	GetLoanMutations(ctx context.Context, caller Caller, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	GetDeposits(ctx context.Context, caller Caller) ([]domain.DMBDepositAccountItem, error)
	GetDepositDetail(ctx context.Context, caller Caller, accountNo string) (*domain.DMBDepositAccountDetail, error)
	GetDepositMutations(ctx context.Context, caller Caller, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error)

	GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error)
}

type accountService struct {
	cbsProv  cbsprovider.CBSProvider
	resolver *ownership.Resolver
}

func NewAccountService(cbsProv cbsprovider.CBSProvider, resolver *ownership.Resolver) AccountService {
	return &accountService{cbsProv: cbsProv, resolver: resolver}
}

// ownershipErr maps ownership failures: "not owned" -> ErrForbidden (403); a Core
// Banking outage is returned as-is so the handler reports a service disruption (503).
func ownershipErr(err error) error {
	if errors.Is(err, cbsprovider.ErrCBSUnavailable) {
		return err
	}
	return ErrForbidden
}

func requireCaller(c Caller) error {
	if strings.TrimSpace(c.UserID) == "" {
		return ErrForbidden
	}
	return nil
}

func (s *accountService) GetBalance(ctx context.Context, caller Caller, requestedAccount string) (*domain.BalanceResponse, error) {
	if err := requireCaller(caller); err != nil {
		return nil, err
	}
	accNo, err := s.resolver.ResolveSavingsAccount(ctx, caller.UserID, caller.CIF, caller.TokenAccount, requestedAccount)
	if err != nil {
		return nil, ownershipErr(err)
	}
	// Balance comes from Core Banking only; no cached/local substitute (audit DMB-026).
	return s.cbsProv.GetBalance(ctx, accNo)
}

func (s *accountService) GetMutations(ctx context.Context, caller Caller, query domain.MutationQueryParam) (string, []domain.Mutation, error) {
	if err := requireCaller(caller); err != nil {
		return "", nil, err
	}
	accNo, err := s.resolver.ResolveSavingsAccount(ctx, caller.UserID, caller.CIF, caller.TokenAccount, query.AccountNumber)
	if err != nil {
		return "", nil, ownershipErr(err)
	}
	limit := query.Limit
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	muts, err := s.cbsProv.GetMutations(ctx, caller.CIF, accNo, query.StartDate, query.EndDate, limit)
	if err != nil {
		return accNo, nil, err
	}
	return accNo, muts, nil
}

// InquiryRecipient verifies a transfer destination. Only the minimum fields needed
// to confirm the beneficiary are returned by the handler (never balances).
func (s *accountService) InquiryRecipient(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	accountNo = strings.TrimSpace(accountNo)
	if accountNo == "" || len(accountNo) > 30 {
		return nil, cbsprovider.ErrAccountNotFound
	}
	return s.cbsProv.GetBalance(ctx, accountNo)
}

func (s *accountService) GetCustomerProfile(ctx context.Context, caller Caller) (*domain.CBSNasabahData, error) {
	if err := requireCaller(caller); err != nil || caller.CIF == "" {
		return nil, ErrForbidden
	}
	data, err := s.cbsProv.GetCustomerByCIF(ctx, caller.CIF)
	if err != nil {
		return nil, err
	}
	if data == nil {
		return nil, cbsprovider.ErrAccountNotFound
	}
	sanitized := *data
	sanitized.NamaIbuKandung = "" // knowledge-based verification secret: never sent to clients (audit DMB-022)
	return &sanitized, nil
}

func (s *accountService) GetSavingsAccounts(ctx context.Context, caller Caller) ([]domain.CBSSavingsAccountItem, error) {
	if err := requireCaller(caller); err != nil || caller.CIF == "" {
		return nil, ErrForbidden
	}
	return s.cbsProv.GetSavingsAccountsByCIF(ctx, caller.CIF)
}

func (s *accountService) GetLoans(ctx context.Context, caller Caller) ([]domain.DMBLoanAccountItem, error) {
	if err := requireCaller(caller); err != nil || caller.CIF == "" {
		return nil, ErrForbidden
	}
	return s.cbsProv.GetLoanAccountsByCIF(ctx, caller.CIF)
}

func (s *accountService) GetLoanDetail(ctx context.Context, caller Caller, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	if err := s.resolver.OwnsLoan(ctx, caller.CIF, accountNo); err != nil {
		return nil, ownershipErr(err)
	}
	return s.cbsProv.GetLoanAccountDetail(ctx, caller.CIF, accountNo)
}

func (s *accountService) GetLoanMutations(ctx context.Context, caller Caller, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if err := s.resolver.OwnsLoan(ctx, caller.CIF, accountNo); err != nil {
		return nil, ownershipErr(err)
	}
	return s.cbsProv.GetLoanMutations(ctx, caller.CIF, accountNo, startDate, endDate, limit)
}

func (s *accountService) GetDeposits(ctx context.Context, caller Caller) ([]domain.DMBDepositAccountItem, error) {
	if err := requireCaller(caller); err != nil || caller.CIF == "" {
		return nil, ErrForbidden
	}
	return s.cbsProv.GetDepositAccountsByCIF(ctx, caller.CIF)
}

func (s *accountService) GetDepositDetail(ctx context.Context, caller Caller, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	if err := s.resolver.OwnsDeposit(ctx, caller.CIF, accountNo); err != nil {
		return nil, ownershipErr(err)
	}
	return s.cbsProv.GetDepositAccountDetail(ctx, caller.CIF, accountNo)
}

func (s *accountService) GetDepositMutations(ctx context.Context, caller Caller, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if err := s.resolver.OwnsDeposit(ctx, caller.CIF, accountNo); err != nil {
		return nil, ownershipErr(err)
	}
	return s.cbsProv.GetDepositMutations(ctx, caller.CIF, accountNo, startDate, endDate, limit)
}

func (s *accountService) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	return s.cbsProv.GetProductsCatalog(ctx)
}
