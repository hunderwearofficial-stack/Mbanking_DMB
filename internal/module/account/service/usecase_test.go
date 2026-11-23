package service

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/ownership"
)

type fakeCBS struct {
	cbsprovider.CBSProvider
	accounts  map[string][]string
	available int // rows the CBS holds for the period
	asked     int // limit the service requested
}

func (f *fakeCBS) GetSavingsAccountsByCIF(_ context.Context, cif string) ([]domain.CBSSavingsAccountItem, error) {
	var out []domain.CBSSavingsAccountItem
	for _, a := range f.accounts[cif] {
		out = append(out, domain.CBSSavingsAccountItem{NomorRekening: a})
	}
	return out, nil
}

func (f *fakeCBS) GetMutations(_ context.Context, _, acc, _, _ string, limit int) ([]domain.Mutation, error) {
	f.asked = limit
	n := f.available
	if n > limit {
		n = limit
	}
	out := make([]domain.Mutation, n)
	for i := range out {
		out[i] = domain.Mutation{ID: fmt.Sprint(i), AccountNumber: acc}
	}
	return out, nil
}

func newSvc(f *fakeCBS) AccountService {
	return NewAccountService(f, ownership.NewResolver(f, nil, true))
}

func TestGetMutationsReportsTruncation(t *testing.T) {
	f := &fakeCBS{accounts: map[string][]string{"CIF-A": {"111"}}, available: 80}
	svc := newSvc(f)
	caller := Caller{UserID: "u1", CIF: "CIF-A"}

	_, muts, more, err := svc.GetMutations(context.Background(), caller, domain.MutationQueryParam{Limit: 50})
	if err != nil || len(muts) != 50 || !more || f.asked != 51 {
		t.Fatalf("got len=%d more=%v asked=%d err=%v; want 50 true 51", len(muts), more, f.asked, err)
	}

	f.available = 50
	_, muts, more, _ = svc.GetMutations(context.Background(), caller, domain.MutationQueryParam{Limit: 50})
	if len(muts) != 50 || more {
		t.Fatalf("tepat 50 baris tidak boleh ditandai terpotong: len=%d more=%v", len(muts), more)
	}
}

func TestGetMutationsRejectsForeignAccount(t *testing.T) {
	f := &fakeCBS{accounts: map[string][]string{"CIF-A": {"111"}, "CIF-B": {"222"}}}
	_, _, _, err := newSvc(f).GetMutations(context.Background(), Caller{UserID: "u1", CIF: "CIF-A"},
		domain.MutationQueryParam{AccountNumber: "222"})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("rekening nasabah lain harus ditolak, got %v", err)
	}
}

func TestValidateRangeBankCalendar(t *testing.T) {
	today := time.Now().In(cbsprovider.BankLocation)
	d := func(t time.Time) string { return t.Format("2006-01-02") }
	cases := []struct {
		start, end string
		ok         bool
	}{
		{"", "", true},
		{d(today.AddDate(0, 0, -31)), d(today), true},
		{d(today.AddDate(0, 0, -32)), d(today), false},
		{d(today), d(today), true},
		{d(today.AddDate(0, 0, 1)), d(today.AddDate(0, 0, 1)), false},
		{d(today), d(today.AddDate(0, 0, -1)), false},
		{"2026/01/01", "2026-01-02", false},
		{d(today), "", false},
	}
	for _, c := range cases {
		if err := validateRange(c.start, c.end); (err == nil) != c.ok {
			t.Errorf("validateRange(%q,%q) err=%v, want ok=%v", c.start, c.end, err, c.ok)
		}
	}
}
