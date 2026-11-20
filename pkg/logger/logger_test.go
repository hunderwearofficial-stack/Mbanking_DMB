package logger

import (
	"strings"
	"testing"
)

func TestMaskJSONString_CoversVariants(t *testing.T) {
	body := `{"phone_number":"0812","password":"p1","new_password":"p2","old_password":"p3","otp_code":"482913",
	"refresh_token":"rt","session_id":"s","pin":"583920","old_pin":"1","new_pin":"2","fcm_token":"f",
	"nested":{"client_secret":"cs","nama_ibu_kandung":"Siti","list":[{"access_token":"at"}]},"amount":15000}`
	out := MaskJSONString(body)
	for _, leaked := range []string{"p1", "p2", "p3", "482913", `"rt"`, "583920", "Siti", `"cs"`, `"at"`, `"f"`} {
		if strings.Contains(out, leaked) {
			t.Fatalf("value %s leaked: %s", leaked, out)
		}
	}
	if !strings.Contains(out, "15000") {
		t.Fatal("non-sensitive fields should be kept")
	}
}

func TestMaskJSONString_NonJSONOmitted(t *testing.T) {
	if out := MaskJSONString("password=abc&pin=1"); strings.Contains(out, "abc") {
		t.Fatalf("non-JSON body leaked: %s", out)
	}
}

func TestMaskQuery(t *testing.T) {
	q := MaskQuery("account_number=0010100000001&cif_number=001000000101&limit=20&token=x")
	if strings.Contains(q, "0010100000001") || strings.Contains(q, "001000000101") || strings.Contains(q, "token=x") {
		t.Fatalf("query not masked: %s", q)
	}
	if !strings.Contains(q, "limit=20") {
		t.Fatal("benign parameters should be kept")
	}
}
