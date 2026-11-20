package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/ownership"
)

type Caller struct {
	UserID       string
	CIF          string
	TokenAccount string
}

var ErrForbidden = ownership.ErrNotOwned

// ErrInvalidQuery: malformed mutation date range or limit (audit D-08).
var ErrInvalidQuery = errors.New("parameter riwayat mutasi tidak valid")

const (
	maxMutationRangeDays = 31
	maxMutationLimit     = 50
	defaultMutationLimit = 20
)

// validateRange enforces the documented contract server-side: YYYY-MM-DD dates, start <=
// end, at most 31 days, not in the future. Empty dates let the CBS apply its default period.
func validateRange(start, end string) error {
	start, end = strings.TrimSpace(start), strings.TrimSpace(end)
	if start == "" && end == "" {
		return nil
	}
	if start == "" || end == "" {
		return fmt.Errorf("%w: Tanggal awal dan tanggal akhir harus diisi bersamaan", ErrInvalidQuery)
	}
	s, err1 := time.Parse("2006-01-02", start)
	e, err2 := time.Parse("2006-01-02", end)
	if err1 != nil || err2 != nil {
		return fmt.Errorf("%w: format tanggal harus YYYY-MM-DD", ErrInvalidQuery)
	}
	if e.Before(s) {
		return fmt.Errorf("%w: tanggal akhir tidak boleh sebelum tanggal awal", ErrInvalidQuery)
	}
	if e.Sub(s) > time.Duration(maxMutationRangeDays)*24*time.Hour {
		return fmt.Errorf("%w: rentang tanggal maksimal %d hari", ErrInvalidQuery, maxMutationRangeDays)
	}
	if s.After(time.Now().Add(24 * time.Hour)) {
		return fmt.Errorf("%w: tanggal awal tidak boleh di masa depan", ErrInvalidQuery)
	}
	return nil
}

func clampLimit(limit int) int {
	if limit <= 0 {
		return defaultMutationLimit
	}
	if limit > maxMutationLimit {
		return maxMutationLimit
	}
	return limit
}

// maskTail keeps the last n characters of s.
func maskTail(s string, keep int) string {
	s = strings.TrimSpace(s)
	if s == "" || len(s) <= keep {
		return s
	}
	return strings.Repeat("*", len(s)-keep) + s[len(s)-keep:]
}

// maskWords keeps the first word of an address.
func maskWords(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	if i := strings.IndexByte(s, ' '); i > 0 {
		return s[:i] + " ***"
	}
	return "***"
}

type AccountService interface {
	GetBalance(ctx context.Context, caller Caller, requestedAccount string) (*domain.BalanceResponse, error)
	GetMutations(ctx context.Context, caller Caller, query domain.MutationQueryParam) (string, []domain.Mutation, error)
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
	if err := validateRange(query.StartDate, query.EndDate); err != nil {
		return accNo, nil, err
	}
	limit := clampLimit(query.Limit)
	muts, err := s.cbsProv.GetMutations(ctx, caller.CIF, accNo, query.StartDate, query.EndDate, limit)
	if err != nil {
		return accNo, nil, err
	}
	return accNo, muts, nil
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
	// SECURITY (audit D-09): identity data is masked by the server; the full values are only
	// returned by POST /account/profile/reveal after a server-side PIN check.
	sanitized.NIK = maskTail(sanitized.NIK, 4)
	sanitized.Alamat = maskWords(sanitized.Alamat)
	if sanitized.TglLahir != "" {
		sanitized.TglLahir = "**-**-****"
	}
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
	if err := validateRange(startDate, endDate); err != nil {
		return nil, err
	}
	return s.cbsProv.GetLoanMutations(ctx, caller.CIF, accountNo, startDate, endDate, clampLimit(limit))
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
	if err := validateRange(startDate, endDate); err != nil {
		return nil, err
	}
	return s.cbsProv.GetDepositMutations(ctx, caller.CIF, accountNo, startDate, endDate, clampLimit(limit))
}

func (s *accountService) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	return s.cbsProv.GetProductsCatalog(ctx)
}
