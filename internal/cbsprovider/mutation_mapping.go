package cbsprovider

import (
	"fmt"
	"sort"
	"strings"
	"time"
	_ "time/tzdata" // embed the IANA database so Asia/Jakarta resolves on minimal images

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
)

// MaxProviderMutations is the most rows a provider returns for one mutation query. The
// account service asks for (limit + 1) rows to detect a truncated period (audit MA-02),
// so this must stay above the largest client limit.
const MaxProviderMutations = 101

// BankLocation is the timezone of the CBS: its "tanggal"/"waktu" fields carry the local
// wall-clock time of the bank (WIB) without an offset (audit MA-01).
var BankLocation = loadBankLocation()

func loadBankLocation() *time.Location {
	if loc, err := time.LoadLocation("Asia/Jakarta"); err == nil {
		return loc
	}
	return time.FixedZone("WIB", 7*60*60)
}

// ClampProviderLimit normalises the row count a provider fetches.
func ClampProviderLimit(limit int) int {
	if limit <= 0 {
		return 20
	}
	if limit > MaxProviderMutations {
		return MaxProviderMutations
	}
	return limit
}

// ParseCBSTime interprets a CBS date ("2006-01-02") and optional clock ("15:04:05") as WIB.
func ParseCBSTime(date, clock string) (time.Time, bool) {
	date, clock = strings.TrimSpace(date), strings.TrimSpace(clock)
	if date == "" {
		return time.Time{}, false
	}
	if clock != "" {
		if t, err := time.ParseInLocation("2006-01-02 15:04:05", date+" "+clock, BankLocation); err == nil {
			return t, true
		}
	}
	if t, err := time.ParseInLocation("2006-01-02", date, BankLocation); err == nil {
		return t, true
	}
	return time.Time{}, false
}

// DefaultMutationPeriod returns the period the CBS is queried for when the client sends no
// dates: the last 30 days up to today, in the bank's calendar.
func DefaultMutationPeriod(start, end string) (string, string) {
	now := time.Now().In(BankLocation)
	if strings.TrimSpace(start) == "" {
		start = now.AddDate(0, 0, -30).Format("2006-01-02")
	}
	if strings.TrimSpace(end) == "" {
		end = now.Format("2006-01-02")
	}
	return start, end
}

// mapCBSMutations converts CBS rows into mutations ordered newest first and keeps at most
// limit rows. The CBS order is not part of its contract: an ascending (passbook) list is
// reversed so rows of the same day keep their relative order, then a stable sort by time
// guarantees the most recent transactions are the ones kept (audit MA-02).
func mapCBSMutations(items []cbsMutationItem, accountNo, refPrefix string, limit int) []domain.Mutation {
	type row struct {
		item cbsMutationItem
		at   time.Time
		ok   bool
		seq  int
	}
	rows := make([]row, 0, len(items))
	for i, it := range items {
		t, ok := ParseCBSTime(it.Tanggal, it.Waktu)
		rows = append(rows, row{item: it, at: t, ok: ok, seq: i + 1})
	}

	firstIdx, lastIdx := -1, -1
	for i := range rows {
		if rows[i].ok {
			if firstIdx < 0 {
				firstIdx = i
			}
			lastIdx = i
		}
	}
	if firstIdx >= 0 && firstIdx != lastIdx && !rows[firstIdx].at.After(rows[lastIdx].at) {
		for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
			rows[i], rows[j] = rows[j], rows[i]
		}
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].ok != rows[j].ok {
			return rows[i].ok // rows with an unreadable date go last
		}
		return rows[i].at.After(rows[j].at)
	})

	limit = ClampProviderLimit(limit)
	out := make([]domain.Mutation, 0, minInt(len(rows), limit))
	for _, r := range rows {
		if len(out) >= limit {
			break
		}
		txType := model.TxTypeDebit
		amount := r.item.MutasiDebit
		if r.item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = r.item.MutasiKredit
		}
		stamp := strings.ReplaceAll(strings.TrimSpace(r.item.Tanggal), "-", "")
		if r.ok {
			stamp = r.at.Format("20060102150405")
		}
		out = append(out, model.Mutation{
			ID:              fmt.Sprintf("%s-%s-%03d", refPrefix, stamp, r.seq),
			AccountNumber:   accountNo,
			TransactionType: txType,
			Amount:          amount,
			BalanceAfter:    r.item.SaldoAkhir,
			Description:     r.item.Keterangan,
			ReferenceNumber: fmt.Sprintf("%s-%s-%03d", refPrefix, stamp, r.seq),
			CreatedAt:       r.at,
		})
	}
	return out
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
