package devicebind

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"testing"
	"time"
)

func TestCanonicalIdentifiers(t *testing.T) {
	cases := map[string]string{
		"and-00a1b2c3d4e5f607":                     "android",
		"ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427": "ios",
	}
	for id, want := range cases {
		if p, ok := CanonicalPlatform(id); !ok || p != want {
			t.Fatalf("%s: got %q %v, want %s", id, p, ok, want)
		}
		if IsLegacy(id) {
			t.Fatalf("%s must not be legacy", id)
		}
	}
	for _, id := range []string{
		"SAMSUNG-SM-A515F-1A2B3C4D", "ANDROID-SM-1A2B3C4D", // previous formats
		"and-00A1B2C3D4E5F607", // upper case is not canonical
		"and-a1b2c3",           // truncated
		"ios-1b4e28ba-2fa1-11d2-883f-0016d3cca427", // not a v4 UUID
		"ANDROID-ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427",
	} {
		if _, ok := CanonicalPlatform(id); ok {
			t.Fatalf("%s must not be canonical", id)
		}
		if !IsLegacy(id) {
			t.Fatalf("%s must be legacy", id)
		}
	}
	if IsLegacy("") || IsLegacy("   ") {
		t.Fatal("an empty binding is not a legacy binding")
	}
}

func TestSecurityLevelPolicy(t *testing.T) {
	ok := [][2]string{{"android", LevelStrongBox}, {"android", LevelTEE}, {"ios", LevelSecureEnclave}}
	for _, c := range ok {
		if !levelAllowed(c[0], c[1]) {
			t.Fatalf("%v must be allowed", c)
		}
	}
	bad := [][2]string{{"android", "SOFTWARE"}, {"android", LevelSecureEnclave}, {"ios", LevelTEE}, {"ios", "SOFTWARE"}, {"web", LevelTEE}, {"android", ""}}
	for _, c := range bad {
		if levelAllowed(c[0], c[1]) {
			t.Fatalf("%v must be refused (no silent downgrade to software keys)", c)
		}
	}
}

func spki(t *testing.T, pub interface{}) string {
	t.Helper()
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(der)
}

func TestParsePublicKey(t *testing.T) {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, der, fp, err := ParsePublicKey(spki(t, &k.PublicKey))
	if err != nil || pub == nil {
		t.Fatalf("valid P-256 key refused: %v", err)
	}
	sum := sha256.Sum256(der)
	if fp != hex.EncodeToString(sum[:]) || !ValidFingerprint(fp) {
		t.Fatal("fingerprint must be the SHA-256 of the SPKI DER")
	}

	k384, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	rsaKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	for name, in := range map[string]string{
		"P-384":   spki(t, &k384.PublicKey),
		"RSA":     spki(t, &rsaKey.PublicKey),
		"garbage": base64.StdEncoding.EncodeToString([]byte("not a key")),
		"not b64": "%%%",
		"empty":   "",
	} {
		if _, _, _, err := ParsePublicKey(in); err != ErrInvalidKey {
			t.Fatalf("%s: expected ErrInvalidKey, got %v", name, err)
		}
	}
}

func TestIOSRawKeyWithSPKIHeader(t *testing.T) {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	raw := elliptic.Marshal(elliptic.P256(), k.PublicKey.X, k.PublicKey.Y) //nolint:staticcheck // test of the wire format
	header, _ := hex.DecodeString("3059301306072a8648ce3d020106082a8648ce3d030107034200")
	der := append(append([]byte{}, header...), raw...)
	pub, _, _, err := ParsePublicKey(base64.StdEncoding.EncodeToString(der))
	if err != nil {
		t.Fatalf("iOS SPKI rejected: %v", err)
	}
	if pub.X.Cmp(k.PublicKey.X) != 0 || pub.Y.Cmp(k.PublicKey.Y) != 0 {
		t.Fatal("decoded key differs")
	}
}

func sign(t *testing.T, k *ecdsa.PrivateKey, msg []byte) string {
	t.Helper()
	d := sha256.Sum256(msg)
	sig, err := ecdsa.SignASN1(rand.Reader, k, d[:])
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(sig)
}

func TestSignatureVerification(t *testing.T) {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	other, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	ctx := OperationContext(PurposeChangePIN)
	msg := SigningMessage(PurposeChangePIN, "11111111-2222-4333-8444-555555555555", "nonce", "and-00a1b2c3d4e5f607", ctx)
	sig := sign(t, k, msg)
	if !verifySignature(&k.PublicKey, msg, sig) {
		t.Fatal("valid signature refused")
	}
	if verifySignature(&other.PublicKey, msg, sig) {
		t.Fatal("signature accepted for another key (device spoofing)")
	}
	tampered := SigningMessage(PurposeChangePIN, "11111111-2222-4333-8444-555555555555", "nonce", "and-00a1b2c3d4e5f607",
		OperationContext(PurposeChangePassword))
	if verifySignature(&k.PublicKey, tampered, sig) {
		t.Fatal("signature accepted for a different context")
	}
	otherPurpose := SigningMessage(PurposeLogin, "11111111-2222-4333-8444-555555555555", "nonce", "and-00a1b2c3d4e5f607", ctx)
	if verifySignature(&k.PublicKey, otherPurpose, sig) {
		t.Fatal("signature accepted for another purpose")
	}
	for _, bad := range []string{"", "!!", base64.StdEncoding.EncodeToString(make([]byte, 200))} {
		if verifySignature(&k.PublicKey, msg, bad) {
			t.Fatalf("malformed signature %q accepted", bad)
		}
	}
}

func TestSigningMessageVector(t *testing.T) {
	wantCtx := "operation=CHANGE_PIN"
	if ctx := OperationContext(PurposeChangePIN); ctx != wantCtx {
		t.Fatalf("operation context: %q want %q", ctx, wantCtx)
	}
	msg := string(SigningMessage(PurposeLogin, "c1", "n1", "and-00a1b2c3d4e5f607", ""))
	want := "DMB-DEVICE-BINDING-V1\nLOGIN\nc1\nn1\nand-00a1b2c3d4e5f607\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	if msg != want {
		t.Fatalf("signing message:\n%q\nwant\n%q", msg, want)
	}
	if got := ContextDigest(wantCtx); len(got) != 64 {
		t.Fatal("digest must be hex SHA-256")
	}
}

func TestModeNormalisation(t *testing.T) {
	if NewService(nil, Options{}).Mode() != ModeDual {
		t.Fatal("empty mode must default to dual")
	}
	off := NewService(nil, Options{Mode: "OFF"})
	if off.Active() {
		t.Fatal("off disables keys")
	}
	if NewService(nil, Options{}).opt.AttestationMode != AttestObserve {
		t.Fatal("empty attestation mode defaults to observe (non-production only, see config)")
	}
	var nilSvc *Service
	if nilSvc.Active() {
		t.Fatal("nil service is inactive")
	}
}

// SR-4: the rollback switch is time-boxed: after OffUntil the service is dual again.
func TestOffSwitchExpires(t *testing.T) {
	now := time.Date(2026, 11, 18, 10, 0, 0, 0, time.UTC)
	active := NewService(nil, Options{Mode: ModeOff, OffUntil: now.Add(time.Hour), OffReason: "INC-123 rollback", Now: func() time.Time { return now }})
	if active.Active() || active.Mode() != ModeOff {
		t.Fatal("off switch must apply before OffUntil")
	}
	expired := NewService(nil, Options{Mode: ModeOff, OffUntil: now.Add(-time.Minute), Now: func() time.Time { return now }})
	if !expired.Active() || expired.Mode() != ModeDual {
		t.Fatal("expired off switch must re-enable dual")
	}
	expired.LogStartup(context.Background(), "test") // no database: logs only, must not panic
}

// SR-2 / SR-3 helpers.
func TestKeyAcceptanceAndLevelRank(t *testing.T) {
	enforce := NewService(nil, Options{AttestationMode: AttestEnforce})
	observe := NewService(nil, Options{AttestationMode: AttestObserve})
	for _, st := range []string{AttestationUnverified, AttestationFailed, ""} {
		if enforce.keyAccepted(&Key{AttestationStatus: st}) {
			t.Fatalf("%q key accepted under enforce", st)
		}
		if !observe.keyAccepted(&Key{AttestationStatus: st}) {
			t.Fatalf("%q key refused under observe", st)
		}
	}
	if !enforce.keyAccepted(&Key{AttestationStatus: AttestationHardwareVerified}) {
		t.Fatal("verified key refused")
	}
	if !(levelRank(LevelStrongBox) > levelRank(LevelTEE) && levelRank(LevelTEE) > levelRank("SOFTWARE")) {
		t.Fatal("level ranking")
	}
}
