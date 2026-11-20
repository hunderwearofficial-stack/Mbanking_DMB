package ownership

import (
	"context"
	"errors"
	"testing"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
)

type fakeCBS struct {
	cbsprovider.CBSProvider
	savings map[string][]string
	loans   map[string][]string
	fail    bool
}

func (f *fakeCBS) GetSavingsAccountsByCIF(_ context.Context, cif string) ([]domain.CBSSavingsAccountItem, error) {
	if f.fail {
		return nil, errors.New("cbs down")
	}
	var out []domain.CBSSavingsAccountItem
	for _, n := range f.savings[cif] {
		out = append(out, domain.CBSSavingsAccountItem{NomorRekening: n})
	}
	return out, nil
}

func (f *fakeCBS) GetLoanAccountsByCIF(_ context.Context, cif string) ([]domain.DMBLoanAccountItem, error) {
	if f.fail {
		return nil, errors.New("cbs down")
	}
	var out []domain.DMBLoanAccountItem
	for _, n := range f.loans[cif] {
		out = append(out, domain.DMBLoanAccountItem{NomorRekening: n})
	}
	return out, nil
}

func (f *fakeCBS) GetDepositAccountsByCIF(_ context.Context, cif string) ([]domain.DMBDepositAccountItem, error) {
	if f.fail {
		return nil, errors.New("cbs down")
	}
	return nil, nil
}

func TestResolveSavingsAccount(t *testing.T) {
	cbs := &fakeCBS{savings: map[string][]string{"CIF-A": {"111", "112"}, "CIF-B": {"222"}}}
	r := NewResolver(cbs, nil, true)
	ctx := context.Background()

	if got, err := r.ResolveSavingsAccount(ctx, "uA", "CIF-A", "", ""); err != nil || got != "111" {
		t.Fatalf("primary: %q %v", got, err)
	}
	if got, err := r.ResolveSavingsAccount(ctx, "uA", "CIF-A", "", "112"); err != nil || got != "112" {
		t.Fatalf("owned secondary: %q %v", got, err)
	}
	if _, err := r.ResolveSavingsAccount(ctx, "uA", "CIF-A", "", "222"); !errors.Is(err, ErrNotOwned) {
		t.Fatal("foreign account must be rejected (DMB-004/005)")
	}
	if got, _ := r.ResolveSavingsAccount(ctx, "uA", "CIF-A", "222", ""); got == "222" {
		t.Fatal("a token account that is not owned must not be used")
	}
}

func TestLiveCBSFailureFailsClosed(t *testing.T) {
	r := NewResolver(&fakeCBS{fail: true}, nil, true)
	_, err := r.ResolveSavingsAccount(context.Background(), "uA", "CIF-A", "", "111")
	if err == nil {
		t.Fatal("CBS outage must deny ownership, not fall back")
	}
	if !errors.Is(err, cbsprovider.ErrCBSUnavailable) || errors.Is(err, ErrNotOwned) {
		t.Fatalf("CBS outage must be reported as unavailable, not as 'not owned': %v", err)
	}
	if err := r.OwnsLoan(context.Background(), "CIF-A", "L1"); !errors.Is(err, cbsprovider.ErrCBSUnavailable) {
		t.Fatalf("CBS outage must deny loan ownership as unavailable, got %v", err)
	}
	if err := r.OwnsDeposit(context.Background(), "CIF-A", "D1"); !errors.Is(err, cbsprovider.ErrCBSUnavailable) {
		t.Fatalf("CBS outage must deny deposit ownership as unavailable, got %v", err)
	}
}

func TestOwnsLoan(t *testing.T) {
	r := NewResolver(&fakeCBS{loans: map[string][]string{"CIF-A": {"L1"}}}, nil, true)
	if r.OwnsLoan(context.Background(), "CIF-A", "L1") != nil ||
		!errors.Is(r.OwnsLoan(context.Background(), "CIF-A", "L2"), ErrNotOwned) ||
		!errors.Is(r.OwnsLoan(context.Background(), "", "L1"), ErrNotOwned) {
		t.Fatal("loan ownership incorrect")
	}
}
