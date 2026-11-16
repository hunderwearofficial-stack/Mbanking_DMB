// Package money provides an exact monetary type for Rupiah (audit DMB-015).
//
// Amount stores value in sen (1/100 rupiah) as int64, matching the database column
// type decimal(15,2) and Core Banking values without any floating-point step:
//   - JSON & DB values are parsed with math/big (exact); more than 2 decimals is an error;
//   - JSON output is a plain number (e.g. 15000 or 15000.5) — the API shape is unchanged;
//   - arithmetic and comparisons are integer operations.
//
// Transfer amounts must additionally be whole rupiah (IsWholeRupiah).
package money

import (
	"database/sql/driver"
	"errors"
	"fmt"
	"math"
	"math/big"
	"strconv"
	"strings"
)

// Amount is a monetary value in sen (minor unit). 150000 = Rp 1.500,00.
type Amount int64

const senPerRupiah = 100

var (
	ErrInvalidAmount   = errors.New("format nominal tidak valid")
	ErrTooManyDecimal  = errors.New("nominal maksimal memiliki 2 angka desimal")
	ErrAmountOverflow  = errors.New("nominal melebihi batas maksimum")
	ErrNegativeAmount  = errors.New("nominal tidak boleh bernilai negatif")
	ErrZeroAmount      = errors.New("nominal harus lebih besar dari 0")
	ErrInvalidFraction = errors.New("nominal rupiah tidak boleh memiliki pecahan sen")
	ErrAmountTooLow    = errors.New("nominal di bawah batas minimum transaksi")
	ErrAmountTooHigh   = errors.New("nominal melebihi batas maksimum transaksi")
)

// maxSen keeps values inside decimal(15,2) (13 integer digits).
const maxSen = int64(9_999_999_999_999_99)

// Rupiah builds an Amount from whole rupiah.
func Rupiah(r int64) Amount { return Amount(r * senPerRupiah) }

// Parse converts a decimal string ("15000", "15000.50", "1.5e4") to an exact Amount.
func Parse(s string) (Amount, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, ErrInvalidAmount
	}
	r, ok := new(big.Rat).SetString(s)
	if !ok {
		return 0, ErrInvalidAmount
	}
	r.Mul(r, big.NewRat(senPerRupiah, 1))
	if !r.IsInt() {
		return 0, ErrTooManyDecimal
	}
	n := r.Num()
	if !n.IsInt64() || n.Int64() > maxSen || n.Int64() < -maxSen {
		return 0, ErrAmountOverflow
	}
	return Amount(n.Int64()), nil
}

// FromFloat converts a float64 coming from a non-exact source (e.g. a SQL driver).
// The shortest decimal representation is parsed exactly; >2 decimals is an error.
func FromFloat(f float64) (Amount, error) {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, ErrInvalidAmount
	}
	return Parse(strconv.FormatFloat(f, 'f', -1, 64))
}

// Sen returns the raw value in sen.
func (a Amount) Sen() int64 { return int64(a) }

// IsWholeRupiah reports whether the amount has no sen fraction.
func (a Amount) IsWholeRupiah() bool { return int64(a)%senPerRupiah == 0 }

// String returns the canonical decimal form without trailing zeros ("15000", "15000.5").
func (a Amount) String() string {
	v := int64(a)
	neg := v < 0
	if neg {
		v = -v
	}
	s := strconv.FormatInt(v/senPerRupiah, 10)
	if frac := v % senPerRupiah; frac != 0 {
		s += strings.TrimRight(fmt.Sprintf(".%02d", frac), "0")
	}
	if neg {
		s = "-" + s
	}
	return s
}

// MarshalJSON writes the amount as a JSON number.
func (a Amount) MarshalJSON() ([]byte, error) { return []byte(a.String()), nil }

// UnmarshalJSON accepts a JSON number or a numeric string, exactly.
func (a *Amount) UnmarshalJSON(b []byte) error {
	s := strings.Trim(strings.TrimSpace(string(b)), `"`)
	if s == "null" || s == "" {
		*a = 0
		return nil
	}
	v, err := Parse(s)
	if err != nil {
		return err
	}
	*a = v
	return nil
}

// Decimal2 returns the fixed two-decimal form ("15000.00"), identical to the
// historical %.2f formatting used in idempotency request hashes.
func (a Amount) Decimal2() string {
	v := int64(a)
	neg := v < 0
	if neg {
		v = -v
	}
	s := fmt.Sprintf("%d.%02d", v/senPerRupiah, v%senPerRupiah)
	if neg {
		s = "-" + s
	}
	return s
}

// Value stores the amount as an exact decimal string (PostgreSQL numeric).
func (a Amount) Value() (driver.Value, error) {
	return a.Decimal2(), nil
}

// Scan reads numeric/decimal columns exactly.
func (a *Amount) Scan(src interface{}) error {
	var (
		v   Amount
		err error
	)
	switch t := src.(type) {
	case nil:
		v = 0
	case []byte:
		v, err = Parse(string(t))
	case string:
		v, err = Parse(t)
	case int64:
		v = Rupiah(t)
	case float64:
		v, err = FromFloat(t)
	default:
		return fmt.Errorf("money: tipe kolom tidak didukung %T", src)
	}
	if err != nil {
		return err
	}
	*a = v
	return nil
}

// ValidateTransferAmount checks a transfer amount: positive, whole rupiah, within [min, max]
// (bounds ignored when zero).
func ValidateTransferAmount(amount, min, max Amount) error {
	switch {
	case amount < 0:
		return ErrNegativeAmount
	case amount == 0:
		return ErrZeroAmount
	case !amount.IsWholeRupiah():
		return ErrInvalidFraction
	case min > 0 && amount < min:
		return fmt.Errorf("%w: minimal %s", ErrAmountTooLow, FormatIDR(min))
	case max > 0 && amount > max:
		return fmt.Errorf("%w: maksimal %s", ErrAmountTooHigh, FormatIDR(max))
	}
	return nil
}

// FormatIDR formats an amount as "Rp 1.000.000" (or "Rp 1.000.000,50" with sen).
func FormatIDR(a Amount) string {
	v := int64(a)
	neg := v < 0
	if neg {
		v = -v
	}
	s := "Rp " + FormatNumber(v/senPerRupiah)
	if frac := v % senPerRupiah; frac != 0 {
		s += fmt.Sprintf(",%02d", frac)
	}
	if neg {
		s = "-" + s
	}
	return s
}

// FormatNumber formats an integer with thousands separator (dots): "1.000.000".
func FormatNumber(n int64) string {
	in := strconv.FormatInt(n, 10)
	neg := strings.HasPrefix(in, "-")
	in = strings.TrimPrefix(in, "-")
	var out []string
	for len(in) > 3 {
		out = append([]string{in[len(in)-3:]}, out...)
		in = in[:len(in)-3]
	}
	out = append([]string{in}, out...)
	res := strings.Join(out, ".")
	if neg {
		return "-" + res
	}
	return res
}
