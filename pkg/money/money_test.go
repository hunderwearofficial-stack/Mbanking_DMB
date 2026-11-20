package money

import (
	"encoding/json"
	"math"
	"testing"
)

func TestParseExact(t *testing.T) {
	cases := map[string]Amount{
		"0": 0, "15000": 1_500_000, "15000.5": 1_500_050, "15000.50": 1_500_050,
		"0.01": 1, "1.5e4": 1_500_000, "-25.10": -2510,
		"0.30": 30,
	}
	for in, want := range cases {
		got, err := Parse(in)
		if err != nil || got != want {
			t.Errorf("Parse(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
}

func TestParseRejects(t *testing.T) {
	for _, in := range []string{"", "abc", "1.001", "12,5", "NaN", "1e30"} {
		if _, err := Parse(in); err == nil {
			t.Errorf("Parse(%q) should fail", in)
		}
	}
	for _, f := range []float64{math.NaN(), math.Inf(1), math.Pow(2, 63)} {
		if _, err := FromFloat(f); err == nil {
			t.Errorf("FromFloat(%v) should fail", f)
		}
	}
}

func TestJSONRoundTripKeepsNumberShape(t *testing.T) {
	var v struct {
		A Amount `json:"a"`
		B Amount `json:"b"`
	}
	if err := json.Unmarshal([]byte(`{"a": 1500000, "b": "2500.75"}`), &v); err != nil {
		t.Fatal(err)
	}
	if v.A != Rupiah(1_500_000) || v.B != 250_075 {
		t.Fatalf("unexpected %d %d", v.A, v.B)
	}
	out, _ := json.Marshal(v)
	if string(out) != `{"a":1500000,"b":2500.75}` {
		t.Fatalf("unexpected JSON %s", out)
	}
	if err := json.Unmarshal([]byte(`{"a": 1.234}`), &v); err == nil {
		t.Fatal("3 decimals must be rejected")
	}
}

func TestDBValueScan(t *testing.T) {
	a := Amount(1_500_050)
	dv, _ := a.Value()
	if dv != "15000.50" {
		t.Fatalf("Value() = %v", dv)
	}
	var b Amount
	for _, src := range []interface{}{[]byte("15000.50"), "15000.50", 15000.5} {
		if err := b.Scan(src); err != nil || b != a {
			t.Fatalf("Scan(%v) = %d, %v", src, b, err)
		}
	}
	if err := b.Scan(int64(7)); err != nil || b != Rupiah(7) {
		t.Fatalf("Scan(int64) = %d, %v", b, err)
	}
}

func TestFormatIDR(t *testing.T) {
	cases := map[Amount]string{
		Rupiah(1_000_000): "Rp 1.000.000", Rupiah(500): "Rp 500", 1_500_050: "Rp 15.000,50", Rupiah(-2500): "-Rp 2.500",
	}
	for in, want := range cases {
		if got := FormatIDR(in); got != want {
			t.Errorf("FormatIDR(%d) = %s, want %s", in, got, want)
		}
	}
}
