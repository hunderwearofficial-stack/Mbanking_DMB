package integration

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"strings"
	"sync"
	"testing"

	"mbanking-bpr/internal/app"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/devicebind/attesttest"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/security"
)

// ---------------------------------------------------------------- test device

// testDeviceKey plays the Android Keystore / Secure Enclave key: only the SPKI public
// key leaves this struct.
type testDeviceKey struct {
	priv *ecdsa.PrivateKey
	spki string
	fp   string
}

func newDeviceKey(t *testing.T) *testDeviceKey {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKIXPublicKey(&k.PublicKey)
	sum := sha256.Sum256(der)
	return &testDeviceKey{priv: k, spki: base64.StdEncoding.EncodeToString(der), fp: hex.EncodeToString(sum[:])}
}

func (k *testDeviceKey) sign(msg []byte) string {
	d := sha256.Sum256(msg)
	sig, _ := ecdsa.SignASN1(rand.Reader, k.priv, d[:])
	return base64.StdEncoding.EncodeToString(sig)
}

const (
	itAndroidPkg = "id.co.bank.integration"
	itAppleAppID = "TEAMID9999.id.co.bank.integration"
)

var itCertDigest = func() []byte { s := sha256.Sum256([]byte("integration-signing-cert")); return s[:] }()

// attestationCAs are test-only trust anchors written to temp files (production uses the
// official Google / Apple roots, see docs/SECURITY_AND_OJK.md).
type attestationCAs struct {
	android, apple *attesttest.CA
	androidFile    string
	appleFile      string
}

func newAttestationCAs(t *testing.T) *attestationCAs {
	dir := t.TempDir()
	a := &attestationCAs{android: attesttest.NewCA("it-android"), apple: attesttest.NewCA("it-apple")}
	a.androidFile = a.android.WriteRootPEM(dir, "android-roots.pem")
	a.appleFile = a.apple.WriteRootPEM(dir, "apple-root.pem")
	return a
}

// withBinding rebuilds the router with another binding / attestation configuration.
func (e *itEnv) withBinding(mode, attestation string, cas *attestationCAs) {
	e.t.Helper()
	cfg := *e.cfg
	cfg.DeviceBindingMode, cfg.DeviceAttestationMode = mode, attestation
	cfg.AndroidRequireVerifiedBoot = true
	cfg.AndroidAttestationRootsFile, cfg.AndroidPackageName, cfg.AndroidSigningCertSHA256 = "", "", nil
	cfg.AppleAppAttestRootFile, cfg.AppleAppID = "", ""
	if cas != nil {
		cfg.AndroidAttestationRootsFile, cfg.AndroidPackageName = cas.androidFile, itAndroidPkg
		cfg.AndroidSigningCertSHA256 = []string{hex.EncodeToString(itCertDigest)}
		cfg.AppleAppAttestRootFile, cfg.AppleAppID, cfg.AppleAppAttestEnvironment = cas.appleFile, itAppleAppID, "production"
	}
	e.cfg = &cfg
	r, deps, err := app.NewRouter(e.cfg, e.db, redis.NewMemoryClient(), cbsprovider.NewDatabaseCBSProvider(e.db))
	if err != nil {
		e.t.Fatal(err)
	}
	e.router, e.deps = r, deps
}

func (e *itEnv) publicChallenge(purpose, phone, refresh, device string) map[string]interface{} {
	e.t.Helper()
	r := e.call("POST", "/api/v1/auth/device-challenge", map[string]string{"purpose": purpose, "phone_number": phone, "refresh_token": refresh, "device_id": device},
		map[string]string{"X-Device-ID": device})
	if r.Status != 200 {
		e.t.Fatalf("device-challenge %s: %d %v", purpose, r.Status, r.Body)
	}
	return r.data()
}

func (e *itEnv) sessionChallenge(h map[string]string, purpose, fp string) map[string]interface{} {
	e.t.Helper()
	r := e.call("POST", "/api/v1/device/challenge", map[string]string{"purpose": purpose, "public_key_sha256": fp}, h)
	if r.Status != 200 {
		e.t.Fatalf("session challenge %s: %d %v", purpose, r.Status, r.Body)
	}
	return r.data()
}

func msgFor(ch map[string]interface{}, purpose, device, context string) []byte {
	return devicebind.SigningMessage(purpose, ch["challenge_id"].(string), ch["nonce"].(string), device, context)
}

// prover produces the device proof for a challenge (ES256 signature or App Attest assertion).
type prover func(ch map[string]interface{}, purpose, device, context string) string

func esProver(k *testDeviceKey) prover {
	return func(ch map[string]interface{}, purpose, device, context string) string {
		return k.sign(msgFor(ch, purpose, device, context))
	}
}

func appleProver(k *attesttest.AppleKey, counter *uint32) prover {
	return func(ch map[string]interface{}, purpose, device, context string) string {
		*counter++
		return attesttest.AppleAssertion(k, itAppleAppID, *counter, msgFor(ch, purpose, device, context))
	}
}

// loginWith performs the app login: LOGIN challenge → proof → login.
func (e *itEnv) loginWith(phone, device string, p prover) apiResp {
	e.t.Helper()
	acc := e.acceptTerms(device)
	body := map[string]string{"phone_number": phone, "password": itPassword, "device_id": device, "terms_acceptance_id": acc}
	if p != nil {
		ch := e.publicChallenge("LOGIN", phone, "", device)
		body["device_challenge_id"], body["device_signature"] = ch["challenge_id"].(string), p(ch, "LOGIN", device, "")
	}
	return e.call("POST", "/api/v1/auth/login", body, map[string]string{"X-Device-ID": device})
}

// otpRebind runs Lupa Password with an OTP on device (opens the enrollment window).
func (e *itEnv) otpRebind(u *model.User, phone, device, code string) string {
	e.t.Helper()
	sid, err := e.deps.OTPStore.Create(context.Background(), otp.Session{Purpose: otp.PurposeForgotPassword, UserID: u.ID,
		PhoneNumber: phone, FullName: u.FullName, DeviceID: device}, code)
	if err != nil {
		e.t.Fatal(err)
	}
	hd := map[string]string{"X-Device-ID": device}
	if r := e.call("POST", "/api/v1/auth/forgot-password/otp", map[string]string{"session_id": sid, "otp_code": code}, hd); r.Status != 200 {
		e.t.Fatalf("otp: %d %v", r.Status, r.Body)
	}
	if r := e.call("POST", "/api/v1/auth/forgot-password/reset", map[string]string{"session_id": sid, "new_password": itPassword, "device_id": device}, hd); r.Status != 200 {
		e.t.Fatalf("reset: %d %v", r.Status, r.Body)
	}
	return sid
}

func (e *itEnv) enrollAndroid(h map[string]string, device string, k *testDeviceKey, cas *attestationCAs, mutate func(*attesttest.AndroidOptions)) apiResp {
	e.t.Helper()
	ch := e.sessionChallenge(h, "ENROLL", "")
	body := map[string]interface{}{"device_id": device, "platform": "android", "public_key": k.spki, "security_level": "STRONGBOX",
		"challenge_id": ch["challenge_id"], "signature": k.sign(msgFor(ch, "ENROLL", device, devicebind.EnrollContext(k.fp, device)))}
	if cas != nil {
		o := attesttest.DefaultAndroid(itAndroidPkg, itCertDigest, []byte(ch["nonce"].(string)))
		if mutate != nil {
			mutate(&o)
		}
		body["attestation_format"], body["attestation_chain"] = "android-key", cas.android.AndroidChain(&k.priv.PublicKey, o)
	}
	return e.call("POST", "/api/v1/device/enroll", body, h)
}

func binding(r apiResp) map[string]interface{} {
	b, _ := r.data()["device_binding"].(map[string]interface{})
	return b
}

func (e *itEnv) auditCount(action string) int64 {
	var n int64
	e.db.Model(&model.AuditLog{}).Where("action = ?", action).Count(&n)
	return n
}

func expectCode(t *testing.T, r apiResp, status int, code, what string) {
	t.Helper()
	if r.Status != status || r.Body["response_code"] != code {
		t.Fatalf("%s: expected %d/%s, got %d %v", what, status, code, r.Status, r.Body)
	}
}

func tokens(r apiResp) (string, string) {
	return r.data()["access_token"].(string), r.data()["refresh_token"].(string)
}

// ---------------------------------------------------------------- Android

func TestIntegration_DeviceBindingAndroid(t *testing.T) {
	e := setupIT(t)
	cas := newAttestationCAs(t)
	e.withBinding(devicebind.ModeDual, devicebind.AttestEnforce, cas)
	const (
		legacyID = "SAMSUNG-SM-A515F-1A2B3C4D"
		andID    = "and-00a1b2c3d4e5f607"
		accA     = "0010100000301"
		accB     = "0010100000302"
	)
	cust := e.seedCustomer("001000000301", "081200000301", legacyID, accA, 5_000_000)
	other := e.seedCustomer("001000000302", "081200000302", "and-0000000000000302", accB, 1_000_000)
	e.seedAdmin("cs_device", model.AdminRoleCS)
	key := newDeviceKey(t)

	t.Run("old app keeps its identifier binding; new app with a new identifier needs OTP (no hint, no migration)", func(t *testing.T) {
		if r := e.loginWith("081200000301", legacyID, nil); r.Status != 200 {
			t.Fatalf("old app login: %d %v", r.Status, r.Body)
		}
		acc := e.acceptTerms(andID)
		r := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000301", "password": itPassword,
			"device_id": andID, "legacy_device_id": legacyID, "terms_acceptance_id": acc}, map[string]string{"X-Device-ID": andID})
		expectCode(t, r, http.StatusForbidden, "08", "canonical id against legacy binding")
	})

	t.Run("bound device without OTP window cannot enroll", func(t *testing.T) {
		tokB, _ := e.login("081200000302", "and-0000000000000302")
		h := auth(tokB, "and-0000000000000302")
		if st := e.call("GET", "/api/v1/device/status", nil, h); st.data()["enrollment"] != "OTP_REQUIRED" {
			t.Fatalf("status: %v", st.Body)
		}
		expectCode(t, e.enrollAndroid(h, "and-0000000000000302", newDeviceKey(t), cas, nil), http.StatusForbidden, "08", "enroll without OTP")
	})

	var tok, refresh string
	t.Run("legacy recovery: OTP re-binding opens the window; attested StrongBox key enrolled", func(t *testing.T) {
		e.otpRebind(cust, "081200000301", andID, "731904")
		r := e.loginWith("081200000301", andID, nil)
		if r.Status != 200 || binding(r)["enrollment"] != "ALLOWED" {
			t.Fatalf("login after OTP: %d %v", r.Status, r.Body)
		}
		oldTok, _ := tokens(r)
		h := auth(oldTok, andID)

		// Attestation enforce: forged / weak attestations are refused.
		for name, m := range map[string]func(*attesttest.AndroidOptions){
			"software key":      func(o *attesttest.AndroidOptions) { o.SecurityLevel = 0 },
			"wrong challenge":   func(o *attesttest.AndroidOptions) { o.Challenge = []byte("stale") },
			"other application": func(o *attesttest.AndroidOptions) { o.PackageName = "com.attacker" },
			"unlocked device":   func(o *attesttest.AndroidOptions) { o.DeviceLocked = false },
		} {
			e.freshRateLimits() // enrollment is rate limited (5 per 5 minutes) by design
			expectCode(t, e.enrollAndroid(h, andID, newDeviceKey(t), cas, m), http.StatusForbidden, devicebind.CodeAttestationRequired, name)
		}
		e.freshRateLimits()
		expectCode(t, e.enrollAndroid(h, andID, newDeviceKey(t), nil, nil), http.StatusForbidden, devicebind.CodeAttestationRequired, "no attestation")
		rogue := &attestationCAs{android: attesttest.NewCA("rogue")}
		expectCode(t, e.enrollAndroid(h, andID, newDeviceKey(t), rogue, nil), http.StatusForbidden, devicebind.CodeAttestationRequired, "untrusted root")
		if e.auditCount("DEVICE_ATTESTATION_FAILED") < 6 {
			t.Fatal("refused attestations must be audited")
		}

		e.freshRateLimits()
		r = e.enrollAndroid(h, andID, key, cas, nil)
		if r.Status != 200 {
			t.Fatalf("enroll: %d %v", r.Status, r.Body)
		}
		b := binding(r)
		if b["enrolled"] != true || b["attestation_status"] != "HARDWARE_VERIFIED" || b["security_level"] != "STRONGBOX" || b["key_algorithm"] != "ES256" {
			t.Fatalf("binding after enroll: %v", b)
		}
		tok, refresh = tokens(r)
		claims, err := security.ValidateAccessToken(tok, itCustomerSecret)
		var k devicebind.Key
		e.db.Where("user_id = ? AND status = 'ACTIVE'", cust.ID).First(&k)
		if err != nil || claims.DeviceKeyID != k.ID || k.PublicKey != key.spki || k.EnrolledVia != "OTP_ENROLLMENT" {
			t.Fatalf("token dk / stored key: %v %+v %+v", err, claims, k)
		}
		if e.call("GET", "/api/v1/account/balance", nil, h).Status != http.StatusUnauthorized {
			t.Fatal("pre-enrollment session must be revoked")
		}
		var u model.User
		e.db.First(&u, "id = ?", cust.ID)
		if st := e.call("GET", "/api/v1/device/status", nil, auth(tok, andID)); st.data()["enrollment"] != "NOT_NEEDED" {
			t.Fatalf("enrollment window must be closed: %v", st.Body)
		}
		e.freshRateLimits()
		expectCode(t, e.enrollAndroid(auth(tok, andID), andID, newDeviceKey(t), cas, nil), http.StatusForbidden, "08", "second enrollment")
	})

	t.Run("enrolled device must prove; Device ID alone is not enough", func(t *testing.T) {
		e.freshRateLimits()
		expectCode(t, e.loginWith("081200000301", andID, nil), http.StatusForbidden, "10", "unsigned login")
		if r := e.loginWith("081200000301", andID, esProver(newDeviceKey(t))); r.Status != http.StatusForbidden {
			t.Fatalf("cloned/other key: %d", r.Status)
		}
		r := e.loginWith("081200000301", andID, esProver(key))
		if r.Status != 200 {
			t.Fatalf("signed login: %d %v", r.Status, r.Body)
		}
		tok, refresh = tokens(r)
	})

	t.Run("replayed, expired and cross-purpose challenges are refused", func(t *testing.T) {
		e.freshRateLimits()
		ch := e.publicChallenge("LOGIN", "081200000301", "", andID)
		body := map[string]string{"phone_number": "081200000301", "password": itPassword, "device_id": andID, "terms_acceptance_id": e.acceptTerms(andID),
			"device_challenge_id": ch["challenge_id"].(string), "device_signature": key.sign(msgFor(ch, "LOGIN", andID, ""))}
		if r := e.call("POST", "/api/v1/auth/login", body, map[string]string{"X-Device-ID": andID}); r.Status != 200 {
			t.Fatalf("first use: %d %v", r.Status, r.Body)
		}
		body["terms_acceptance_id"] = e.acceptTerms(andID)
		expectCode(t, e.call("POST", "/api/v1/auth/login", body, map[string]string{"X-Device-ID": andID}), http.StatusForbidden, "10", "replay")
		if e.auditCount("DEVICE_CHALLENGE_REPLAY") < 1 {
			t.Fatal("replay must be audited")
		}
		ch = e.publicChallenge("LOGIN", "081200000301", "", andID)
		e.db.Exec("UPDATE device_challenges SET expires_at = now() - interval '1 second' WHERE id = ?", ch["challenge_id"])
		body["device_challenge_id"], body["device_signature"] = ch["challenge_id"].(string), key.sign(msgFor(ch, "LOGIN", andID, ""))
		body["terms_acceptance_id"] = e.acceptTerms(andID)
		expectCode(t, e.call("POST", "/api/v1/auth/login", body, map[string]string{"X-Device-ID": andID}), http.StatusForbidden, "10", "expired")

		r := e.loginWith("081200000301", andID, esProver(key))
		tok, refresh = tokens(r)
		ch = e.publicChallenge("LOGIN", "081200000301", "", andID)
		r = e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh, "device_challenge_id": ch["challenge_id"].(string),
			"device_signature": key.sign(msgFor(ch, "REFRESH", andID, ""))}, map[string]string{"X-Device-ID": andID})
		expectCode(t, r, http.StatusForbidden, "10", "LOGIN challenge used for REFRESH")
		// The challenge of customer A cannot be used by customer B.
		chA := e.publicChallenge("LOGIN", "081200000301", "", andID)
		if chA["challenge_id"] == "" {
			t.Fatal("challenge")
		}
		var row struct{ UserID *string }
		e.db.Raw("SELECT user_id FROM device_challenges WHERE id = ?", chA["challenge_id"]).Scan(&row)
		if row.UserID == nil || *row.UserID != cust.ID {
			t.Fatal("challenge must be bound to the customer")
		}
		decoy := e.publicChallenge("LOGIN", "089999999999", "", andID)
		e.db.Raw("SELECT user_id FROM device_challenges WHERE id = ?", decoy["challenge_id"]).Scan(&row)
		if row.UserID != nil || decoy["nonce"] == "" {
			t.Fatal("unknown identifier must get an unbound decoy challenge")
		}
		r = e.loginWith("081200000301", andID, esProver(key))
		tok, refresh = tokens(r)
	})

	t.Run("refresh and biometric unlock require the proof; session bound to key (dk)", func(t *testing.T) {
		e.freshRateLimits()
		expectCode(t, e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh}, map[string]string{"X-Device-ID": andID}),
			http.StatusForbidden, "10", "unsigned refresh")
		ch := e.publicChallenge("REFRESH", "", refresh, andID)
		r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh, "device_challenge_id": ch["challenge_id"].(string),
			"device_signature": key.sign(msgFor(ch, "REFRESH", andID, ""))}, map[string]string{"X-Device-ID": andID})
		if r.Status != 200 {
			t.Fatalf("signed refresh: %d %v", r.Status, r.Body)
		}
		tok, refresh = tokens(r)
		// A token whose key is no longer active is refused even if the session lives.
		var k devicebind.Key
		e.db.Where("user_id = ? AND status = 'ACTIVE'", cust.ID).First(&k)
		e.db.Exec("UPDATE device_keys SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'IT' WHERE id = ?", k.ID)
		if r := e.call("GET", "/api/v1/account/balance", nil, auth(tok, andID)); r.Status != http.StatusUnauthorized {
			t.Fatalf("token with revoked key: %d", r.Status)
		}
		e.db.Exec("UPDATE device_keys SET status = 'ACTIVE', revoked_at = NULL, revoked_reason = NULL WHERE id = ?", k.ID)
		if r := e.call("GET", "/api/v1/account/balance", nil, auth(tok, andID)); r.Status != 200 {
			t.Fatalf("restored key: %d %v", r.Status, r.Body)
		}
	})

	t.Run("change PIN and change password require the proof", func(t *testing.T) {
		e.freshRateLimits()
		h := auth(tok, andID)
		expectCode(t, e.call("POST", "/api/v1/auth/change-pin", map[string]string{"old_pin": "000000", "new_pin": "739182"}, h), http.StatusForbidden, "10", "unsigned change PIN")
		var u model.User
		e.db.First(&u, "id = ?", cust.ID)
		if u.FailedPINAttempts != 0 {
			t.Fatal("forged change-PIN must not consume PIN attempts")
		}
		ch := e.sessionChallenge(h, "CHANGE_PIN", "")
		r := e.call("POST", "/api/v1/auth/change-pin", map[string]string{"old_pin": itPIN, "new_pin": "739182",
			"device_challenge_id": ch["challenge_id"].(string), "device_signature": key.sign(msgFor(ch, "CHANGE_PIN", andID, devicebind.OperationContext("CHANGE_PIN")))}, h)
		if r.Status != 200 {
			t.Fatalf("signed change PIN: %d %v", r.Status, r.Body)
		}
		// Proof made for CHANGE_PIN cannot authorize CHANGE_PASSWORD.
		ch = e.sessionChallenge(h, "CHANGE_PIN", "")
		r = e.call("POST", "/api/v1/auth/change-password", map[string]string{"old_password": itPassword, "new_password": "Rahasia-Baru-2026",
			"device_challenge_id": ch["challenge_id"].(string), "device_signature": key.sign(msgFor(ch, "CHANGE_PIN", andID, devicebind.OperationContext("CHANGE_PIN")))}, h)
		expectCode(t, r, http.StatusForbidden, "10", "cross-operation proof")
		e.db.Model(&model.User{}).Where("id = ?", cust.ID).Update("pin_hash", func() string { h, _ := security.HashPIN(itPIN); return h }())
	})

	t.Run("rotation: new attested key, old key and its tokens retired", func(t *testing.T) {
		e.freshRateLimits()
		h := auth(tok, andID)
		next := newDeviceKey(t)
		ch := e.sessionChallenge(h, "ROTATE", next.fp)
		msg := msgFor(ch, "ROTATE", andID, devicebind.EnrollContext(next.fp, andID))
		r := e.call("POST", "/api/v1/device/keys/rotate", map[string]interface{}{"new_public_key": next.spki, "new_security_level": "TEE",
			"attestation_chain": cas.android.AndroidChain(&next.priv.PublicKey, attesttest.DefaultAndroid(itAndroidPkg, itCertDigest, []byte(ch["nonce"].(string)))),
			"challenge_id":      ch["challenge_id"], "signature": key.sign(msg), "new_key_signature": next.sign(msg)}, h)
		if r.Status != 200 || binding(r)["attestation_status"] != "HARDWARE_VERIFIED" {
			t.Fatalf("rotate: %d %v", r.Status, r.Body)
		}
		if e.call("GET", "/api/v1/account/balance", nil, h).Status != http.StatusUnauthorized {
			t.Fatal("tokens of the rotated key must be refused")
		}
		if r := e.loginWith("081200000301", andID, esProver(key)); r.Status != http.StatusForbidden {
			t.Fatalf("retired key logged in: %d", r.Status)
		}
		r = e.loginWith("081200000301", andID, esProver(next))
		if r.Status != 200 {
			t.Fatalf("rotated key login: %d %v", r.Status, r.Body)
		}
		key = next
		tok, refresh = tokens(r)
	})

	t.Run("device replacement / signing key change: new identifier needs OTP, old key revoked, OTP not replayable", func(t *testing.T) {
		e.freshRateLimits()
		newPhoneID := "and-1111222233334444" // other phone, or same phone after an app signing key change
		expectCode(t, e.loginWith("081200000301", newPhoneID, nil), http.StatusForbidden, "08", "new device")
		sid := e.otpRebind(cust, "081200000301", newPhoneID, "551188")
		if r := e.call("POST", "/api/v1/auth/forgot-password/reset", map[string]string{"session_id": sid, "new_password": itPassword, "device_id": newPhoneID},
			map[string]string{"X-Device-ID": newPhoneID}); r.Status == 200 {
			t.Fatal("OTP session must not be reusable")
		}
		var active int64
		e.db.Model(&devicebind.Key{}).Where("user_id = ? AND status = 'ACTIVE'", cust.ID).Count(&active)
		if active != 0 {
			t.Fatal("key of the previous device must be revoked by the re-binding")
		}
		expectCode(t, e.loginWith("081200000301", andID, esProver(key)), http.StatusForbidden, "08", "old device after replacement")
		r := e.loginWith("081200000301", newPhoneID, nil)
		if r.Status != 200 || binding(r)["enrollment"] != "ALLOWED" {
			t.Fatalf("new device login: %d %v", r.Status, r.Body)
		}
		nt, _ := tokens(r)
		key = newDeviceKey(t)
		if r := e.enrollAndroid(auth(nt, newPhoneID), newPhoneID, key, cas, nil); r.Status != 200 {
			t.Fatalf("re-enrollment with a fresh key: %d %v", r.Status, r.Body)
		}
	})

	t.Run("re-enrollment never reuses a public key; concurrent enrollment has one winner", func(t *testing.T) {
		e.freshRateLimits()
		sa := e.adminLogin("cs_device")
		if r := e.call("POST", "/api/v1/admin/customers/"+other.ID+"/reset-device", nil, map[string]string{"Authorization": "Bearer " + sa}); r.Status != 200 {
			t.Fatalf("reset: %d", r.Status)
		}
		dev := "and-0000000000000302"
		e.otpRebind(other, "081200000302", dev, "662211")
		r := e.loginWith("081200000302", dev, nil)
		ot, _ := tokens(r)
		h := auth(ot, dev)
		reused := &testDeviceKey{priv: key.priv, spki: key.spki, fp: key.fp} // key already enrolled by customer A
		expectCode(t, e.enrollAndroid(h, dev, reused, cas, nil), http.StatusUnprocessableEntity, "03", "public key reuse")

		var wg sync.WaitGroup
		results := make([]int, 4)
		for i := range results {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				results[i] = e.enrollAndroid(h, dev, newDeviceKey(t), cas, nil).Status
			}(i)
		}
		wg.Wait()
		ok := 0
		for _, s := range results {
			if s == 200 {
				ok++
			}
		}
		var active int64
		e.db.Model(&devicebind.Key{}).Where("user_id = ? AND status = 'ACTIVE'", other.ID).Count(&active)
		if ok != 1 || active != 1 {
			t.Fatalf("concurrent enrollment: %v active=%d", results, active)
		}
	})

	t.Run("expired or revoked session cannot refresh or enroll", func(t *testing.T) {
		e.freshRateLimits()
		r := e.loginWith("081200000301", "and-1111222233334444", esProver(key))
		at, rt := tokens(r)
		e.db.Exec("UPDATE user_sessions SET revoked_at = now(), revoked_reason = 'IT' WHERE user_id = ?", cust.ID)
		if e.call("GET", "/api/v1/device/status", nil, auth(at, "and-1111222233334444")).Status != http.StatusUnauthorized {
			t.Fatal("revoked session accepted")
		}
		ch := e.publicChallenge("REFRESH", "", rt, "and-1111222233334444")
		r = e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": rt, "device_challenge_id": ch["challenge_id"].(string),
			"device_signature": key.sign(msgFor(ch, "REFRESH", "and-1111222233334444", ""))}, map[string]string{"X-Device-ID": "and-1111222233334444"})
		if r.Status == 200 {
			t.Fatal("revoked session refreshed")
		}
	})

	t.Run("rollback switch (mode off) and enforced gating", func(t *testing.T) {
		e.withBinding(devicebind.ModeOff, devicebind.AttestEnforce, cas)
		if r := e.loginWith("081200000301", "and-1111222233334444", nil); r.Status != 200 {
			t.Fatalf("mode off login: %d %v", r.Status, r.Body)
		}
		e.withBinding(devicebind.ModeEnforced, devicebind.AttestEnforce, cas)
		r := e.loginWith("081200000301", "and-1111222233334444", esProver(key))
		at, _ := tokens(r)
		if e.call("GET", "/api/v1/account/balance", nil, auth(at, "and-1111222233334444")).Status != 200 {
			t.Fatal("enrolled customer in enforced mode")
		}
		// Customer without key (old app binding) is limited to /device/* in enforced mode.
		e.db.Exec("UPDATE device_keys SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'IT' WHERE user_id = ? AND status = 'ACTIVE'", other.ID)
		r = e.loginWith("081200000302", "and-0000000000000302", nil)
		ot, _ := tokens(r)
		expectCode(t, e.call("GET", "/api/v1/account/balance", nil, auth(ot, "and-0000000000000302")), http.StatusForbidden, "11", "enforced without key")
		if e.call("GET", "/api/v1/device/status", nil, auth(ot, "and-0000000000000302")).Status != 200 {
			t.Fatal("device endpoints stay reachable")
		}
		e.withBinding(devicebind.ModeDual, devicebind.AttestEnforce, cas)
	})

	t.Run("DID-06: unbound device gets one answer for every outcome; failures counted", func(t *testing.T) {
		e.freshRateLimits()
		dev := "and-9999999999999999"
		wrong := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000302", "password": "Salah-Sekali-1", "device_id": dev}, nil)
		right := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "081200000302", "password": itPassword, "device_id": dev}, nil)
		unknown := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "089900000000", "password": itPassword, "device_id": dev}, nil)
		for name, r := range map[string]apiResp{"wrong password": wrong, "right password": right, "unknown account": unknown} {
			expectCode(t, r, http.StatusForbidden, "08", name)
			if r.Body["message"] != right.Body["message"] {
				t.Fatalf("%s: message differs (oracle)", name)
			}
		}
		var u model.User
		e.db.First(&u, "id = ?", other.ID)
		if u.FailedLoginAttempts != 1 {
			t.Fatalf("wrong password from an unbound device must count, got %d", u.FailedLoginAttempts)
		}
	})

	t.Run("monitoring summary", func(t *testing.T) {
		sa := e.adminLogin("cs_device")
		r := e.call("GET", "/api/v1/admin/device-binding/summary", nil, map[string]string{"Authorization": "Bearer " + sa})
		if r.Status != 200 || r.data()["hardware_verified_keys"].(float64) < 1 || r.data()["attestation_failed_24h"].(float64) < 6 {
			t.Fatalf("summary: %d %v", r.Status, r.Body)
		}
	})
}

// ---------------------------------------------------------------- iOS

func TestIntegration_DeviceBindingIOS(t *testing.T) {
	e := setupIT(t)
	cas := newAttestationCAs(t)
	const iosID = "ios-1b4e28ba-2fa1-41d2-883f-0016d3cca427"
	cust := e.seedCustomer("001000000501", "081200000501", "ANDROID-SM-9F3A21BC", "0010100000501", 1_000_000) // old iOS app id
	e.withBinding(devicebind.ModeDual, devicebind.AttestEnforce, cas)

	enrollApple := func(h map[string]string, k *attesttest.AppleKey, appID string) apiResp {
		ch := e.sessionChallenge(h, "ENROLL", "")
		msg := msgFor(ch, "ENROLL", iosID, devicebind.EnrollContext(k.KeyIDB64(), iosID))
		att := cas.apple.AppleAttestation(k, appID, append([]byte("appattest"), make([]byte, 7)...), 0, msg)
		return e.call("POST", "/api/v1/device/enroll", map[string]interface{}{"device_id": iosID, "platform": "ios",
			"attestation_format": "apple-appattest", "app_attest_key_id": k.KeyIDB64(), "attestation_object": att,
			"security_level": "SECURE_ENCLAVE", "challenge_id": ch["challenge_id"]}, h)
	}

	var counter uint32
	ak := attesttest.NewAppleKey()
	t.Run("old iOS identifier needs OTP; App Attest enrollment is hardware verified", func(t *testing.T) {
		expectCode(t, e.loginWith("081200000501", iosID, nil), http.StatusForbidden, "08", "new identifier")
		e.otpRebind(cust, "081200000501", iosID, "418822")
		r := e.loginWith("081200000501", iosID, nil)
		at, _ := tokens(r)
		h := auth(at, iosID)
		expectCode(t, enrollApple(h, attesttest.NewAppleKey(), "TEAMID9999.com.attacker"), http.StatusForbidden, devicebind.CodeAttestationRequired, "attestation for another app")
		r = enrollApple(h, ak, itAppleAppID)
		b := binding(r)
		if r.Status != 200 || b["key_algorithm"] != "APPATTEST" || b["attestation_status"] != "HARDWARE_VERIFIED" || b["security_level"] != "SECURE_ENCLAVE" {
			t.Fatalf("app attest enroll: %d %v", r.Status, r.Body)
		}
	})

	t.Run("assertions: valid login, counter replay refused", func(t *testing.T) {
		e.freshRateLimits()
		r := e.loginWith("081200000501", iosID, appleProver(ak, &counter))
		if r.Status != 200 {
			t.Fatalf("assertion login: %d %v", r.Status, r.Body)
		}
		counter-- // reuse the same counter value on a fresh challenge
		expectCode(t, e.loginWith("081200000501", iosID, appleProver(ak, &counter)), http.StatusForbidden, "10", "counter replay")
		counter += 5
		if r := e.loginWith("081200000501", iosID, appleProver(ak, &counter)); r.Status != 200 {
			t.Fatalf("higher counter: %d %v", r.Status, r.Body)
		}
		other := attesttest.NewAppleKey()
		var c2 uint32 = 100
		expectCode(t, e.loginWith("081200000501", iosID, appleProver(other, &c2)), http.StatusForbidden, "10", "assertion by another key")
		if e.auditCount("DEVICE_CHALLENGE_REPLAY") < 1 {
			t.Fatal("counter replay must be audited")
		}
	})

	t.Run("Secure Enclave key without App Attest: UNVERIFIED, refused under enforce, never 'verified'", func(t *testing.T) {
		u2 := e.seedCustomer("001000000502", "081200000502", "ios-00000000-0000-4000-8000-000000000502", "0010100000502", 1000)
		dev := "ios-00000000-0000-4000-8000-000000000502"
		e.otpRebind(u2, "081200000502", dev, "882211")
		r := e.loginWith("081200000502", dev, nil)
		at, _ := tokens(r)
		h := auth(at, dev)
		se := newDeviceKey(t)
		enroll := func() apiResp {
			ch := e.sessionChallenge(h, "ENROLL", "")
			return e.call("POST", "/api/v1/device/enroll", map[string]interface{}{"device_id": dev, "platform": "ios", "attestation_format": "none",
				"public_key": se.spki, "security_level": "SECURE_ENCLAVE", "challenge_id": ch["challenge_id"],
				"signature": se.sign(msgFor(ch, "ENROLL", dev, devicebind.EnrollContext(se.fp, dev)))}, h)
		}
		expectCode(t, enroll(), http.StatusForbidden, devicebind.CodeAttestationRequired, "unattested key under enforce")
		e.withBinding(devicebind.ModeDual, devicebind.AttestObserve, cas)
		h = auth(at, dev)
		r = enroll()
		if r.Status != 200 || binding(r)["attestation_status"] != "UNVERIFIED" {
			t.Fatalf("observe: %d %v", r.Status, r.Body)
		}
	})

	t.Run("App Attest not configured on the server: explicit 503, no silent fallback", func(t *testing.T) {
		u3 := e.seedCustomer("001000000503", "081200000503", "ios-00000000-0000-4000-8000-000000000503", "0010100000503", 1000)
		dev := "ios-00000000-0000-4000-8000-000000000503"
		e.withBinding(devicebind.ModeDual, devicebind.AttestObserve, nil)
		e.otpRebind(u3, "081200000503", dev, "993311")
		r := e.loginWith("081200000503", dev, nil)
		at, _ := tokens(r)
		ch := e.sessionChallenge(auth(at, dev), "ENROLL", "")
		k := attesttest.NewAppleKey()
		r = e.call("POST", "/api/v1/device/enroll", map[string]interface{}{"device_id": dev, "platform": "ios", "attestation_format": "apple-appattest",
			"app_attest_key_id": k.KeyIDB64(), "attestation_object": "AA==", "challenge_id": ch["challenge_id"]}, auth(at, dev))
		if r.Status != http.StatusServiceUnavailable || !strings.Contains(r.Body["message"].(string), "App Attest") {
			t.Fatalf("unconfigured App Attest: %d %v", r.Status, r.Body)
		}
	})
}
