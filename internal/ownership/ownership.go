// Package ownership answers "does this customer own this account?" (audit DMB-004, DMB-005).
//
// Rules:
//   - The customer identity (user id + CIF) always comes from the verified token,
//     never from request parameters.
//   - Savings accounts: the authoritative list is CBS /api/savings-accounts for the
//     customer's CIF. With a live CBS, failure to obtain the list denies access.
//     Only in mock/local-database mode (non-production) are local account links used.
//   - Loan / deposit accounts: membership in the CBS list for the CIF.
//   - Any lookup error results in "not owned" (fail-closed).
package ownership

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

var ErrNotOwned = errors.New("rekening tidak terdaftar atas nama nasabah ini")

// Resolver resolves account ownership.
type Resolver struct {
	cbs     cbsprovider.CBSProvider
	db      *gorm.DB
	liveCBS bool
}

// NewResolver creates a resolver. When liveCBS is true, the CBS list is the only
// accepted source: if CBS cannot be reached, ownership is denied (fail-closed),
// because the local database may contain placeholder account records.
func NewResolver(cbs cbsprovider.CBSProvider, db *gorm.DB, liveCBS bool) *Resolver {
	return &Resolver{cbs: cbs, db: db, liveCBS: liveCBS}
}

// SavingsAccounts returns the customer's savings account numbers (first = primary).
func (r *Resolver) SavingsAccounts(ctx context.Context, userID, cif string) ([]string, error) {
	seen := map[string]bool{}
	var out []string
	add := func(n string) {
		n = strings.TrimSpace(n)
		if n != "" && !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}

	cif = strings.TrimSpace(cif)
	if r.cbs != nil && cif != "" {
		items, err := r.cbs.GetSavingsAccountsByCIF(ctx, cif)
		if err == nil && len(items) > 0 {
			for _, it := range items {
				add(it.NomorRekening)
			}
			return out, nil
		}
		if err != nil && r.liveCBS {
			// Fail closed, but report the real cause: Core Banking could not be reached.
			return nil, fmt.Errorf("%w: %v", cbsprovider.ErrCBSUnavailable, err)
		}
	}
	if r.liveCBS {
		return nil, ErrNotOwned
	}

	if r.db != nil && strings.TrimSpace(userID) != "" {
		var accs []model.Account
		if err := r.db.WithContext(ctx).
			Where("user_id = ? AND status = ?", userID, model.AccountStatusActive).
			Order("created_at ASC").Find(&accs).Error; err != nil {
			return nil, err
		}
		for _, a := range accs {
			add(a.AccountNumber)
		}
	}
	if len(out) == 0 {
		return nil, ErrNotOwned
	}
	return out, nil
}

// ResolveSavingsAccount returns requested if owned; if requested is empty, returns
// the customer's primary account (preferring the token's account when owned).
func (r *Resolver) ResolveSavingsAccount(ctx context.Context, userID, cif, tokenAccount, requested string) (string, error) {
	owned, err := r.SavingsAccounts(ctx, userID, cif)
	if err != nil {
		if errors.Is(err, cbsprovider.ErrCBSUnavailable) {
			return "", err
		}
		return "", ErrNotOwned
	}
	contains := func(n string) bool {
		for _, o := range owned {
			if o == n {
				return true
			}
		}
		return false
	}
	requested = strings.TrimSpace(requested)
	if requested != "" {
		if contains(requested) {
			return requested, nil
		}
		return "", ErrNotOwned
	}
	if t := strings.TrimSpace(tokenAccount); t != "" && contains(t) {
		return t, nil
	}
	return owned[0], nil
}

// OwnsLoan returns nil when the loan account belongs to the CIF, ErrNotOwned when it
// does not, or ErrCBSUnavailable when Core Banking could not be asked (fail closed).
func (r *Resolver) OwnsLoan(ctx context.Context, cif, accountNo string) error {
	if r.cbs == nil || strings.TrimSpace(cif) == "" || strings.TrimSpace(accountNo) == "" {
		return ErrNotOwned
	}
	items, err := r.cbs.GetLoanAccountsByCIF(ctx, cif)
	if err != nil {
		return fmt.Errorf("%w: %v", cbsprovider.ErrCBSUnavailable, err)
	}
	for _, it := range items {
		if strings.TrimSpace(it.NomorRekening) == strings.TrimSpace(accountNo) {
			return nil
		}
	}
	return ErrNotOwned
}

// OwnsDeposit returns nil when the deposit account belongs to the CIF, ErrNotOwned when
// it does not, or ErrCBSUnavailable when Core Banking could not be asked (fail closed).
func (r *Resolver) OwnsDeposit(ctx context.Context, cif, accountNo string) error {
	if r.cbs == nil || strings.TrimSpace(cif) == "" || strings.TrimSpace(accountNo) == "" {
		return ErrNotOwned
	}
	items, err := r.cbs.GetDepositAccountsByCIF(ctx, cif)
	if err != nil {
		return fmt.Errorf("%w: %v", cbsprovider.ErrCBSUnavailable, err)
	}
	for _, it := range items {
		if strings.TrimSpace(it.NomorRekening) == strings.TrimSpace(accountNo) {
			return nil
		}
	}
	return ErrNotOwned
}
