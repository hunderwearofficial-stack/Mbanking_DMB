package integration

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/devicebind/attesttest"
	"mbanking-bpr/internal/model"
)

// Regression tests for the final self-review findings SR-2, SR-3, SR-4 and SR-7.
func TestIntegration_DeviceBindingSelfReviewFixes(t *testing.T) {
	e := setupIT(t)
	cas := newAttestationCAs(t)
	const dev = "and-00000000000a0001"
	cust := e.seedCustomer("001000000601", "081200000601", dev, "0010100000601", 1_000_000)
	e.seedCustomer("001000000602", "081200000602", "and-00000000000a0002", "0010100000602", 1_000_000)
	e.seedAdmin("sa_review", model.AdminRoleSuperAdmin)

	// Observe mode: a key WITHOUT attestation is accepted and stored UNVERIFIED.
	e.withBinding(devicebind.ModeDual, devicebind.AttestObserve, cas)
	weak := newDeviceKey(t)
	e.otpRebind(cust, "081200000601", dev, "771001")
	r := e.loginWith("081200000601", dev, nil)
	at, _ := tokens(r)
	r = e.enrollAndroid(auth(at, dev), dev, weak, nil, nil) // no attestation chain
	if r.Status != 200 || binding(r)["attestation_status"] != "UNVERIFIED" {
		t.Fatalf("observe enrollment: %d %v", r.Status, r.Body)
	}
	observeTok, observeRefresh := tokens(r)

	t.Run("SR-2: switching to enforce stops an UNVERIFIED key everywhere", func(t *testing.T) {
		e.withBinding(devicebind.ModeDual, devicebind.AttestEnforce, cas)
		h := auth(observeTok, dev)
		expectCode(t, e.call("GET", "/api/v1/account/balance", nil, h), http.StatusForbidden, devicebind.CodeAttestationRequired, "existing session")
		expectCode(t, e.loginWith("081200000601", dev, esProver(weak)), http.StatusForbidden, devicebind.CodeAttestationRequired, "signed login")
		ch := e.publicChallenge("REFRESH", "", observeRefresh, dev)
		r := e.call("POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": observeRefresh, "device_challenge_id": ch["challenge_id"].(string),
			"device_signature": weak.sign(msgFor(ch, "REFRESH", dev, ""))}, map[string]string{"X-Device-ID": dev})
		expectCode(t, r, http.StatusForbidden, devicebind.CodeAttestationRequired, "signed refresh")
		// Never downgraded to the identifier binding: an unsigned login is refused too.
		if r := e.loginWith("081200000601", dev, nil); r.Status == 200 {
			t.Fatal("unsigned login accepted for a customer with a non-attested key")
		}
		if e.auditCount("DEVICE_ATTESTATION_FAILED") < 3 {
			t.Fatal("refusals must be audited")
		}
	})

	var strong *testDeviceKey
	var tok string
	t.Run("SR-2: recovery through OTP enrolls an attested key", func(t *testing.T) {
		e.freshRateLimits()
		e.otpRebind(cust, "081200000601", dev, "771002")
		r := e.loginWith("081200000601", dev, nil)
		at, _ := tokens(r)
		strong = newDeviceKey(t)
		r = e.enrollAndroid(auth(at, dev), dev, strong, cas, nil)
		if r.Status != 200 || binding(r)["attestation_status"] != "HARDWARE_VERIFIED" || binding(r)["security_level"] != "STRONGBOX" {
			t.Fatalf("attested enrollment: %d %v", r.Status, r.Body)
		}
		tok, _ = tokens(r)
		if r := e.call("GET", "/api/v1/account/balance", nil, auth(tok, dev)); r.Status != 200 {
			t.Fatalf("attested session: %d %v", r.Status, r.Body)
		}
	})

	t.Run("SR-3: a verified StrongBox key cannot be rotated to a weaker key", func(t *testing.T) {
		e.withBinding(devicebind.ModeDual, devicebind.AttestObserve, cas) // weakest mode on purpose
		rotate := func(next *testDeviceKey, chain []string) apiResp {
			h := auth(tok, dev)
			ch := e.sessionChallenge(h, "ROTATE", next.fp)
			msg := msgFor(ch, "ROTATE", dev, devicebind.EnrollContext(next.fp, dev))
			body := map[string]interface{}{"new_public_key": next.spki, "new_security_level": "STRONGBOX",
				"challenge_id": ch["challenge_id"], "signature": strong.sign(msg), "new_key_signature": next.sign(msg)}
			if chain != nil {
				body["attestation_chain"] = chain
			}
			return e.call("POST", "/api/v1/device/keys/rotate", body, h)
		}
		noProof := newDeviceKey(t)
		expectCode(t, rotate(noProof, nil), http.StatusForbidden, devicebind.CodeAttestationRequired, "rotation without attestation")
		e.freshRateLimits()
		tee := newDeviceKey(t)
		ch := e.sessionChallenge(auth(tok, dev), "ROTATE", tee.fp)
		o := attesttest.DefaultAndroid(itAndroidPkg, itCertDigest, []byte(ch["nonce"].(string)))
		o.SecurityLevel = 1
		msg := msgFor(ch, "ROTATE", dev, devicebind.EnrollContext(tee.fp, dev))
		r := e.call("POST", "/api/v1/device/keys/rotate", map[string]interface{}{"new_public_key": tee.spki, "new_security_level": "TEE",
			"attestation_chain": cas.android.AndroidChain(&tee.priv.PublicKey, o), "challenge_id": ch["challenge_id"],
			"signature": strong.sign(msg), "new_key_signature": tee.sign(msg)}, auth(tok, dev))
		expectCode(t, r, http.StatusForbidden, devicebind.CodeAttestationRequired, "StrongBox → TEE")
		if e.auditCount("DEVICE_KEY_ROTATION_REFUSED") != 2 {
			t.Fatal("downgrade attempts must be audited")
		}
		e.freshRateLimits()
		next := newDeviceKey(t)
		ch = e.sessionChallenge(auth(tok, dev), "ROTATE", next.fp)
		msg = msgFor(ch, "ROTATE", dev, devicebind.EnrollContext(next.fp, dev))
		r = e.call("POST", "/api/v1/device/keys/rotate", map[string]interface{}{"new_public_key": next.spki, "new_security_level": "STRONGBOX",
			"attestation_chain": cas.android.AndroidChain(&next.priv.PublicKey, attesttest.DefaultAndroid(itAndroidPkg, itCertDigest, []byte(ch["nonce"].(string)))),
			"challenge_id":      ch["challenge_id"], "signature": strong.sign(msg), "new_key_signature": next.sign(msg)}, auth(tok, dev))
		if r.Status != 200 || binding(r)["security_level"] != "STRONGBOX" {
			t.Fatalf("equal-strength rotation: %d %v", r.Status, r.Body)
		}
	})

	t.Run("SR-4: an off switch is visible in the audit trail and the monitoring summary", func(t *testing.T) {
		cfg := *e.cfg
		cfg.DeviceBindingMode, cfg.DeviceBindingOffReason, cfg.DeviceBindingOffUntil = "off", "INC-2026-009 rollback", time.Now().Add(2*time.Hour)
		e.cfg = &cfg
		e.withBinding(devicebind.ModeOff, devicebind.AttestObserve, cas)
		var n int64
		e.db.Model(&model.AuditLog{}).Where("action = ? AND status = ? AND details LIKE ?", "DEVICE_BINDING_CONFIG", "DANGER", "%INC-2026-009%").Count(&n)
		if n == 0 {
			t.Fatal("off switch must be audited as DANGER with its reason")
		}
		sa := e.adminLogin("sa_review")
		r := e.call("GET", "/api/v1/admin/device-binding/summary", nil, map[string]string{"Authorization": "Bearer " + sa})
		if r.Status != 200 || r.data()["protection_disabled"] != true || r.data()["off_reason"] != "INC-2026-009 rollback" || r.data()["off_until"] == "" {
			t.Fatalf("summary: %d %v", r.Status, r.Body)
		}
		// Expired switch: the service is dual again without restart.
		cfg2 := *e.cfg
		cfg2.DeviceBindingOffUntil = time.Now().Add(-time.Minute)
		e.cfg = &cfg2
		e.withBinding(devicebind.ModeOff, devicebind.AttestObserve, cas)
		r = e.call("GET", "/api/v1/admin/device-binding/summary", nil, map[string]string{"Authorization": "Bearer " + sa})
		if r.data()["mode"] != "dual" || r.data()["configured_mode"] != "off" {
			t.Fatalf("expired switch: %v", r.Body)
		}
		e.withBinding(devicebind.ModeDual, devicebind.AttestEnforce, cas)
	})

	t.Run("SR-7: one generic, non-misleading answer from an unbound device", func(t *testing.T) {
		e.freshRateLimits()
		r := e.call("POST", "/api/v1/auth/login", map[string]string{"phone_number": "089911112222", "password": itPassword, "device_id": "and-1234123412341234"}, nil)
		expectCode(t, r, http.StatusForbidden, "08", "unknown account")
		msg, _ := r.Body["message"].(string)
		if !strings.Contains(msg, "Periksa kembali nomor handphone dan password") || strings.Contains(strings.ToLower(msg), "perangkat baru terdeteksi") {
			t.Fatalf("message: %q", msg)
		}
	})
}
