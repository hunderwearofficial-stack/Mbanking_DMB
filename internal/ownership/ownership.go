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

type Resolver struct {
	cbs     cbsprovider.CBSProvider
	db      *gorm.DB
	liveCBS bool
}

func NewResolver(cbs cbsprovider.CBSProvider, db *gorm.DB, liveCBS bool) *Resolver {
	return &Resolver{cbs: cbs, db: db, liveCBS: liveCBS}
}

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
