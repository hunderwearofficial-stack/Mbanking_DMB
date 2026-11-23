package ownership

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/model"

	"gorm.io/gorm"
)

var ErrNotOwned = errors.New("rekening tidak terdaftar atas nama nasabah ini")

type Resolver struct {
	cbs     cbsprovider.CBSProvider
	db      *gorm.DB
	liveCBS bool
	cache   *ownedCache
}

func NewResolver(cbs cbsprovider.CBSProvider, db *gorm.DB, liveCBS bool) *Resolver {
	return &Resolver{cbs: cbs, db: db, liveCBS: liveCBS, cache: newOwnedCache(ownedCacheTTL, ownedCacheMax)}
}

// Ownership lists from the CBS are cached briefly per CIF (audit MA-13): every inquiry used
// to cost one extra CBS call. Only positive CBS answers are cached, so a new account shows
// up at once; a closed account stays reachable by its own owner for at most the TTL.
const (
	ownedCacheTTL = 30 * time.Second
	ownedCacheMax = 20000
)

type ownedEntry struct {
	accounts []string
	until    time.Time
}

type ownedCache struct {
	mu   sync.Mutex
	ttl  time.Duration
	max  int
	data map[string]ownedEntry
}

func newOwnedCache(ttl time.Duration, max int) *ownedCache {
	return &ownedCache{ttl: ttl, max: max, data: map[string]ownedEntry{}}
}

func (c *ownedCache) get(key string) ([]string, bool) {
	if c == nil {
		return nil, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.data[key]
	if !ok || time.Now().After(e.until) {
		delete(c.data, key)
		return nil, false
	}
	return e.accounts, true
}

func (c *ownedCache) put(key string, accounts []string) {
	if c == nil || len(accounts) == 0 {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.data) >= c.max {
		c.data = map[string]ownedEntry{} // bounded memory: drop everything rather than grow
	}
	c.data[key] = ownedEntry{accounts: append([]string(nil), accounts...), until: time.Now().Add(c.ttl)}
}

func ownsAny(list []string, accountNo string) bool {
	accountNo = strings.TrimSpace(accountNo)
	for _, a := range list {
		if a == accountNo {
			return true
		}
	}
	return false
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
		if cached, ok := r.cache.get("sav:" + cif); ok {
			return append([]string(nil), cached...), nil
		}
		items, err := r.cbs.GetSavingsAccountsByCIF(ctx, cif)
		if err == nil && len(items) > 0 {
			for _, it := range items {
				add(it.NomorRekening)
			}
			r.cache.put("sav:"+cif, out)
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
	key := "loan:" + strings.TrimSpace(cif)
	if cached, ok := r.cache.get(key); ok && ownsAny(cached, accountNo) {
		return nil
	}
	items, err := r.cbs.GetLoanAccountsByCIF(ctx, cif)
	if err != nil {
		return fmt.Errorf("%w: %v", cbsprovider.ErrCBSUnavailable, err)
	}
	var list []string
	for _, it := range items {
		list = append(list, strings.TrimSpace(it.NomorRekening))
	}
	r.cache.put(key, list)
	if ownsAny(list, accountNo) {
		return nil
	}
	return ErrNotOwned
}

func (r *Resolver) OwnsDeposit(ctx context.Context, cif, accountNo string) error {
	if r.cbs == nil || strings.TrimSpace(cif) == "" || strings.TrimSpace(accountNo) == "" {
		return ErrNotOwned
	}
	key := "dep:" + strings.TrimSpace(cif)
	if cached, ok := r.cache.get(key); ok && ownsAny(cached, accountNo) {
		return nil
	}
	items, err := r.cbs.GetDepositAccountsByCIF(ctx, cif)
	if err != nil {
		return fmt.Errorf("%w: %v", cbsprovider.ErrCBSUnavailable, err)
	}
	var list []string
	for _, it := range items {
		list = append(list, strings.TrimSpace(it.NomorRekening))
	}
	r.cache.put(key, list)
	if ownsAny(list, accountNo) {
		return nil
	}
	return ErrNotOwned
}
