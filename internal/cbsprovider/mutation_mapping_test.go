package cbsprovider

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/pkg/money"
)

func TestParseCBSTimeIsWIB(t *testing.T) {
	got, ok := ParseCBSTime("2026-11-20", "21:30:00")
	if !ok {
		t.Fatal("tanggal valid ditolak")
	}
	// 21:30 WIB is 14:30 UTC; the transaction must stay on 20 November for the customer.
	if want := time.Date(2026, 11, 20, 14, 30, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("got %s, want %s", got.UTC(), want)
	}
	b, _ := json.Marshal(got)
	if !strings.Contains(string(b), "+07:00") {
		t.Fatalf("JSON harus membawa offset WIB, got %s", b)
	}
	if d, ok := ParseCBSTime("2026-11-20", ""); !ok || d.In(BankLocation).Day() != 20 {
		t.Fatalf("tanggal tanpa jam harus tetap 20 WIB, got %v %v", d, ok)
	}
	if _, ok := ParseCBSTime("20/11/2026", "x"); ok {
		t.Fatal("format tidak dikenal harus ditolak")
	}
}

func items(stamps ...string) []cbsMutationItem {
	out := make([]cbsMutationItem, 0, len(stamps))
	for i, s := range stamps {
		parts := strings.SplitN(s, " ", 2)
		it := cbsMutationItem{Tanggal: parts[0], Keterangan: "TRX", MutasiKredit: money.Rupiah(int64(i + 1))}
		if len(parts) == 2 {
			it.Waktu = parts[1]
		}
		out = append(out, it)
	}
	return out
}

func TestMapCBSMutationsNewestFirstAndTruncation(t *testing.T) {
	asc := items("2026-11-01 08:00:00", "2026-11-02 09:00:00", "2026-11-03 10:00:00", "2026-11-03 23:59:00")
	got := mapCBSMutations(asc, "111", "SAV", 3)
	if len(got) != 3 {
		t.Fatalf("limit tidak diterapkan: %d", len(got))
	}
	if got[0].CreatedAt.In(BankLocation).Format("2006-01-02 15:04") != "2026-11-03 23:59" {
		t.Fatalf("transaksi terbaru harus pertama, got %s", got[0].CreatedAt)
	}
	for i := 1; i < len(got); i++ {
		if got[i].CreatedAt.After(got[i-1].CreatedAt) {
			t.Fatal("urutan harus terbaru lebih dulu")
		}
	}

	desc := items("2026-11-03 23:59:00", "2026-11-03 10:00:00", "2026-11-02 09:00:00")
	if g := mapCBSMutations(desc, "111", "SAV", 2); g[0].CreatedAt.In(BankLocation).Hour() != 23 {
		t.Fatal("daftar menurun harus tetap terbaru lebih dulu")
	}
}

func TestMapCBSMutationsSameDayOrderAndUniqueReference(t *testing.T) {
	// Passbook order without clock: the later row of the same day is the newer one.
	asc := items("2026-11-05", "2026-11-05", "2026-11-06")
	got := mapCBSMutations(asc, "111", "SAV", 10)
	if got[0].Amount != money.Rupiah(3) || got[1].Amount != money.Rupiah(2) || got[2].Amount != money.Rupiah(1) {
		t.Fatalf("urutan hari yang sama salah: %v %v %v", got[0].Amount, got[1].Amount, got[2].Amount)
	}
	seen := map[string]bool{}
	for _, m := range got {
		if seen[m.ReferenceNumber] {
			t.Fatalf("nomor referensi ganda: %s", m.ReferenceNumber)
		}
		seen[m.ReferenceNumber] = true
	}
}

func TestDefaultMutationPeriodUsesBankCalendar(t *testing.T) {
	s, e := DefaultMutationPeriod("", "")
	today := time.Now().In(BankLocation).Format("2006-01-02")
	if e != today || s == "" {
		t.Fatalf("periode bawaan salah: %s - %s (hari ini %s)", s, e, today)
	}
	if s2, e2 := DefaultMutationPeriod("2026-01-01", "2026-01-31"); s2 != "2026-01-01" || e2 != "2026-01-31" {
		t.Fatal("periode dari klien tidak boleh diubah")
	}
}
