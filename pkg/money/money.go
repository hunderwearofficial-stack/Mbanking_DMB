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

type Amount int64

const senPerRupiah = 100

var (
	ErrInvalidAmount  = errors.New("format nominal tidak valid")
	ErrTooManyDecimal = errors.New("nominal maksimal memiliki 2 angka desimal")
	ErrAmountOverflow = errors.New("nominal melebihi batas maksimum")
)

const maxSen = int64(9_999_999_999_999_99)

func Rupiah(r int64) Amount { return Amount(r * senPerRupiah) }

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

func FromFloat(f float64) (Amount, error) {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, ErrInvalidAmount
	}
	return Parse(strconv.FormatFloat(f, 'f', -1, 64))
}

func (a Amount) Sen() int64 { return int64(a) }

func (a Amount) IsWholeRupiah() bool { return int64(a)%senPerRupiah == 0 }

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

func (a Amount) MarshalJSON() ([]byte, error) { return []byte(a.String()), nil }

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

func (a Amount) Value() (driver.Value, error) {
	return a.Decimal2(), nil
}

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
