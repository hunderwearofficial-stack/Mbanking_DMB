package service

import "testing"

func TestIllustrativeRate(t *testing.T) {
	cases := map[string]string{
		"6.25% p.a. (ilustrasi)":     "Ilustrasi aplikasi: 6.25% p.a.",
		"1.25% flat/bln (ilustrasi)": "Ilustrasi aplikasi: 1.25% flat/bln",
		"1,25 % /bln":                "Ilustrasi aplikasi: 1,25 % /bln",
		"25% dijamin bank":           "",
		"<script>alert(1)</script>":  "",
		"":                           "",
		"999%":                       "",
	}
	for in, want := range cases {
		if got := illustrativeRate(in); got != want {
			t.Errorf("illustrativeRate(%q) = %q, want %q", in, got, want)
		}
	}
}
