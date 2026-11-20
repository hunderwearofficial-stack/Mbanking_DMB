package devicebind

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"

	"mbanking-bpr/internal/devicebind/attesttest"
)

const testPkg = "id.co.bank.test"

var testDigest = func() []byte { s := sha256.Sum256([]byte("test-signing-cert")); return s[:] }()

func androidCfg(t *testing.T, ca *attesttest.CA) *AndroidAttestationConfig {
	t.Helper()
	pool := x509.NewCertPool()
	pool.AddCert(ca.Root)
	return &AndroidAttestationConfig{Roots: pool, PackageName: testPkg, SigningCertSHA256: [][]byte{testDigest}, RequireVerifiedBoot: true}
}

func newKey(t *testing.T) (*ecdsa.PrivateKey, []byte) {
	t.Helper()
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKIXPublicKey(&k.PublicKey)
	return k, der
}

func TestAndroidKeyAttestation(t *testing.T) {
	ca := attesttest.NewCA("android")
	cfg := androidCfg(t, ca)
	k, der := newKey(t)
	challenge := []byte("nonce-123")

	ok := VerifyAndroidAttestation(cfg, ca.AndroidChain(&k.PublicKey, attesttest.DefaultAndroid(testPkg, testDigest, challenge)), der, challenge)
	if ok.Status != AttestationHardwareVerified || ok.SecurityLevel != LevelStrongBox {
		t.Fatalf("genuine StrongBox key: %+v", ok)
	}
	tee := attesttest.DefaultAndroid(testPkg, testDigest, challenge)
	tee.SecurityLevel = 1
	if r := VerifyAndroidAttestation(cfg, ca.AndroidChain(&k.PublicKey, tee), der, challenge); r.Status != AttestationHardwareVerified || r.SecurityLevel != LevelTEE {
		t.Fatalf("genuine TEE key: %+v", r)
	}

	mutate := func(f func(o *attesttest.AndroidOptions)) []string {
		o := attesttest.DefaultAndroid(testPkg, testDigest, challenge)
		f(&o)
		return ca.AndroidChain(&k.PublicKey, o)
	}
	other := attesttest.NewCA("rogue")
	_, otherDer := newKey(t)
	cases := map[string]struct {
		chain  []string
		der    []byte
		chal   []byte
		reason string
	}{
		"software key":        {mutate(func(o *attesttest.AndroidOptions) { o.SecurityLevel = 0 }), der, challenge, "SOFTWARE_ATTESTATION"},
		"wrong challenge":     {mutate(func(o *attesttest.AndroidOptions) { o.Challenge = []byte("old") }), der, challenge, "CHALLENGE_MISMATCH"},
		"imported key":        {mutate(func(o *attesttest.AndroidOptions) { o.Origin = 2 }), der, challenge, "ORIGIN"},
		"decrypt purpose":     {mutate(func(o *attesttest.AndroidOptions) { o.Purposes = []int{2, 1} }), der, challenge, "PURPOSE"},
		"wrong curve":         {mutate(func(o *attesttest.AndroidOptions) { o.Curve = 2 }), der, challenge, "CURVE"},
		"unlocked bootloader": {mutate(func(o *attesttest.AndroidOptions) { o.DeviceLocked = false }), der, challenge, "BOOT_NOT_VERIFIED"},
		"unverified boot":     {mutate(func(o *attesttest.AndroidOptions) { o.BootState = 2 }), der, challenge, "BOOT_NOT_VERIFIED"},
		"other app":           {mutate(func(o *attesttest.AndroidOptions) { o.PackageName = "com.attacker" }), der, challenge, "PACKAGE_MISMATCH"},
		"re-signed app":       {mutate(func(o *attesttest.AndroidOptions) { o.CertDigest = make([]byte, 32) }), der, challenge, "SIGNING_CERT_MISMATCH"},
		"untrusted root":      {other.AndroidChain(&k.PublicKey, attesttest.DefaultAndroid(testPkg, testDigest, challenge)), der, challenge, "CHAIN_UNTRUSTED"},
		"chain of other key":  {ca.AndroidChain(&k.PublicKey, attesttest.DefaultAndroid(testPkg, testDigest, challenge)), otherDer, challenge, "LEAF_KEY_MISMATCH"},
		"too short":           {[]string{"AA=="}, der, challenge, "CHAIN_LENGTH"},
		"garbage":             {[]string{"!!", "!!"}, der, challenge, "CHAIN_ENCODING"},
	}
	for name, c := range cases {
		r := VerifyAndroidAttestation(cfg, c.chain, c.der, c.chal)
		if r.Status != AttestationFailed || r.Reason != c.reason {
			t.Errorf("%s: expected FAILED/%s, got %+v", name, c.reason, r)
		}
	}

	chain := ca.AndroidChain(&k.PublicKey, attesttest.DefaultAndroid(testPkg, testDigest, challenge))
	revCfg := androidCfg(t, ca)
	revCfg.RevocationLoaded = true
	revCfg.Revoked = map[string]bool{ca.Inter.SerialNumber.Text(16): true}
	if r := VerifyAndroidAttestation(revCfg, chain, der, challenge); r.Reason != "CERT_REVOKED" {
		t.Fatalf("revoked intermediate: %+v", r)
	}
	if r := VerifyAndroidAttestation(nil, chain, der, challenge); r.Status != AttestationUnverified {
		t.Fatalf("no roots: %+v", r)
	}
	noApp := androidCfg(t, ca)
	noApp.PackageName = ""
	if r := VerifyAndroidAttestation(noApp, chain, der, challenge); r.Status != AttestationUnverified {
		t.Fatalf("app identity not configured must not be verified: %+v", r)
	}
}

func appleCfg(ca *attesttest.CA) *AppleAttestationConfig {
	pool := x509.NewCertPool()
	pool.AddCert(ca.Root)
	return &AppleAttestationConfig{Roots: pool, AppID: "TEAMID1234.id.co.bank.test", Environment: "production"}
}

var prodAAGUID = append([]byte("appattest"), make([]byte, 7)...)

func TestAppleAppAttest(t *testing.T) {
	ca := attesttest.NewCA("apple")
	cfg := appleCfg(ca)
	key := attesttest.NewAppleKey()
	msg := []byte("enroll message")

	att := ca.AppleAttestation(key, cfg.AppID, prodAAGUID, 0, msg)
	got, res := VerifyAppleAttestation(cfg, att, key.KeyIDB64(), msg)
	if res.Status != AttestationHardwareVerified || got == nil || res.SecurityLevel != LevelSecureEnclave {
		t.Fatalf("genuine attestation: %+v", res)
	}
	if !got.PublicKey.Equal(&key.Priv.PublicKey) {
		t.Fatal("attested key differs")
	}

	other := attesttest.NewAppleKey()
	rogue := attesttest.NewCA("rogue")
	cases := map[string]struct {
		att, kid string
		msg      []byte
		reason   string
	}{
		"other challenge":  {att, key.KeyIDB64(), []byte("another message"), "NONCE_MISMATCH"},
		"other key id":     {att, other.KeyIDB64(), msg, "KEY_ID_MISMATCH"},
		"other app":        {ca.AppleAttestation(key, "TEAMID1234.com.attacker", prodAAGUID, 0, msg), key.KeyIDB64(), msg, "APP_ID_MISMATCH"},
		"development env":  {ca.AppleAttestation(key, cfg.AppID, []byte("appattestdevelop"), 0, msg), key.KeyIDB64(), msg, "ENVIRONMENT_MISMATCH"},
		"non-zero counter": {ca.AppleAttestation(key, cfg.AppID, prodAAGUID, 5, msg), key.KeyIDB64(), msg, "COUNTER_NOT_ZERO"},
		"untrusted root":   {rogue.AppleAttestation(key, cfg.AppID, prodAAGUID, 0, msg), key.KeyIDB64(), msg, "CHAIN_UNTRUSTED"},
		"not cbor":         {base64.StdEncoding.EncodeToString([]byte{0xff}), key.KeyIDB64(), msg, "ATTESTATION_FORMAT"},
		"key id too short": {att, "AAAA", msg, "KEY_ID_ENCODING"},
	}
	for name, c := range cases {
		if _, r := VerifyAppleAttestation(cfg, c.att, c.kid, c.msg); r.Status != AttestationFailed || r.Reason != c.reason {
			t.Errorf("%s: expected FAILED/%s, got %+v", name, c.reason, r)
		}
	}
	if _, r := VerifyAppleAttestation(&AppleAttestationConfig{}, att, key.KeyIDB64(), msg); r.Status != AttestationUnverified {
		t.Fatalf("unconfigured: %+v", r)
	}

	proof := []byte("login message")
	a1 := attesttest.AppleAssertion(key, cfg.AppID, 1, proof)
	if c, reason := VerifyAppleAssertion(cfg.AppID, &key.Priv.PublicKey, a1, proof, 0); reason != "" || c != 1 {
		t.Fatalf("valid assertion: %d %s", c, reason)
	}
	if _, reason := VerifyAppleAssertion(cfg.AppID, &key.Priv.PublicKey, a1, proof, 1); reason != "ASSERTION_COUNTER_REPLAY" {
		t.Fatalf("replay: %s", reason)
	}
	if _, reason := VerifyAppleAssertion(cfg.AppID, &other.Priv.PublicKey, a1, proof, 0); reason != "SIGNATURE_INVALID" {
		t.Fatalf("other key: %s", reason)
	}
	if _, reason := VerifyAppleAssertion(cfg.AppID, &key.Priv.PublicKey, a1, []byte("other message"), 0); reason != "SIGNATURE_INVALID" {
		t.Fatalf("other message: %s", reason)
	}
	bad := attesttest.AppleAssertion(key, "TEAMID1234.com.attacker", 2, proof)
	if _, reason := VerifyAppleAssertion(cfg.AppID, &key.Priv.PublicKey, bad, proof, 0); reason != "APP_ID_MISMATCH" {
		t.Fatalf("other app: %s", reason)
	}
}

func TestCBORDecoderIsStrict(t *testing.T) {
	good := attesttest.EncodeCBOR(map[string]interface{}{"a": []byte{1}, "b": []interface{}{"x", uint64(7)}})
	v, err := decodeCBOR(good)
	if err != nil || v.(map[string]interface{})["b"].([]interface{})[1].(uint64) != 7 {
		t.Fatalf("decode: %v %v", v, err)
	}
	for name, b := range map[string][]byte{
		"trailing":         append(append([]byte{}, good...), 0x00),
		"truncated bytes":  {0x45, 1, 2},
		"indefinite":       {0x5f},
		"tag":              {0xc0, 0x01},
		"float":            {0xfa, 0, 0, 0, 0},
		"non-text map key": {0xa1, 0x01, 0x01},
		"duplicate key":    {0xa2, 0x61, 'a', 0x01, 0x61, 'a', 0x02},
		"huge length":      {0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff},
		"too deep":         {0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x00},
		"empty":            {},
	} {
		if _, err := decodeCBOR(b); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}

func TestLoadAttestationFiles(t *testing.T) {
	dir := t.TempDir()
	ca := attesttest.NewCA("files")
	p := ca.WriteRootPEM(dir, "roots.pem")
	if _, n, err := LoadCertPool(p); err != nil || n != 1 {
		t.Fatalf("roots: %d %v", n, err)
	}
	empty := filepath.Join(dir, "empty.pem")
	_ = os.WriteFile(empty, []byte("no certificate"), 0o600)
	if _, _, err := LoadCertPool(empty); err == nil {
		t.Fatal("file without certificates must be refused")
	}
	rev := filepath.Join(dir, "status.json")
	_ = os.WriteFile(rev, []byte(`{"entries":{"0aBc":{"status":"REVOKED"},"ff":{"status":"SUSPENDED"},"11":{"status":"OK"}}}`), 0o600)
	m, err := LoadRevocationList(rev)
	if err != nil || !m["abc"] || !m["ff"] || m["11"] {
		t.Fatalf("revocation list: %v %v", m, err)
	}
	if _, err := ParseHexDigests([]string{"zz"}); err == nil {
		t.Fatal("invalid digest accepted")
	}
	if _, err := ParseHexDigests([]string{"AB:CD"}); err == nil {
		t.Fatal("short digest accepted")
	}
	sum := sha256.Sum256([]byte("x"))
	colon := ""
	for i, b := range sum {
		if i > 0 {
			colon += ":"
		}
		colon += string("0123456789ABCDEF"[b>>4]) + string("0123456789ABCDEF"[b&15])
	}
	if d, err := ParseHexDigests([]string{colon}); err != nil || len(d) != 1 || string(d[0]) != string(sum[:]) {
		t.Fatalf("apksigner-style colon digest must parse: %v", err)
	}
}
