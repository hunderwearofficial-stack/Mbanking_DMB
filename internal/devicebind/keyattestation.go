package devicebind

import (
	"bytes"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

var oidAndroidKeyDescription = asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 11129, 2, 1, 17}

const (
	kmSecuritySoftware   = 0
	kmSecurityTEE        = 1
	kmSecurityStrongBox  = 2
	kmPurposeSign        = 2
	kmAlgorithmEC        = 3
	kmCurveP256          = 1
	kmOriginGenerated    = 0
	kmBootStateVerified  = 0
	tagPurpose           = 1
	tagAlgorithm         = 2
	tagECCurve           = 10
	tagOrigin            = 702
	tagRootOfTrust       = 704
	tagAttestationAppID  = 709
	maxAttestationChain  = 10
	maxAttestationCertSz = 8 * 1024
)

type AndroidAttestationConfig struct {
	Roots               *x509.CertPool
	PackageName         string
	SigningCertSHA256   [][]byte
	RequireVerifiedBoot bool
	Revoked             map[string]bool
	RevocationLoaded    bool
	Now                 func() time.Time

	// Reloaded list (StartRevocationRefresh); read lock-free by concurrent verifications.
	reloaded atomic.Pointer[map[string]bool]
}

func (c *AndroidAttestationConfig) setRevoked(m map[string]bool) {
	c.reloaded.Store(&m)
}

func (c *AndroidAttestationConfig) revoked() map[string]bool {
	if m := c.reloaded.Load(); m != nil {
		return *m
	}
	return c.Revoked
}

type AttestationResult struct {
	Status        string // HARDWARE_VERIFIED | UNVERIFIED | FAILED
	SecurityLevel string // STRONGBOX | TEE | SECURE_ENCLAVE (only when verified)
	Summary       string // non-personal summary for the audit trail
	Reason        string // failure reason (audit only)
}

type keyDescription struct {
	AttestationVersion       int
	AttestationSecurityLevel asn1.Enumerated
	KeymasterVersion         int
	KeymasterSecurityLevel   asn1.Enumerated
	AttestationChallenge     []byte
	UniqueID                 []byte
	SoftwareEnforced         asn1.RawValue
	TeeEnforced              asn1.RawValue
}

type rootOfTrust struct {
	VerifiedBootKey   []byte
	DeviceLocked      bool
	VerifiedBootState asn1.Enumerated
	VerifiedBootHash  []byte `asn1:"optional"`
}

type attestationPackageInfo struct {
	PackageName []byte
	Version     int64
}

type attestationApplicationID struct {
	PackageInfos     []attestationPackageInfo `asn1:"set"`
	SignatureDigests [][]byte                 `asn1:"set"`
}

func authorizationList(raw asn1.RawValue) (map[int][]byte, error) {
	if raw.Class != asn1.ClassUniversal || raw.Tag != asn1.TagSequence {
		return nil, errors.New("authorization list bukan SEQUENCE")
	}
	out := map[int][]byte{}
	rest := raw.Bytes
	for len(rest) > 0 {
		var el asn1.RawValue
		var err error
		rest, err = asn1.Unmarshal(rest, &el)
		if err != nil {
			return nil, err
		}
		if el.Class != asn1.ClassContextSpecific {
			return nil, errors.New("elemen authorization list tidak bertag")
		}
		if _, dup := out[el.Tag]; dup {
			return nil, errors.New("tag authorization list ganda")
		}
		out[el.Tag] = el.Bytes // explicit tag: Bytes is the DER of the inner value
	}
	return out, nil
}

func asnInt(der []byte) (int64, error) {
	var v int64
	rest, err := asn1.Unmarshal(der, &v)
	if err == nil && len(rest) != 0 {
		err = errors.New("data tersisa")
	}
	return v, err
}

func asnIntSet(der []byte) ([]int64, error) {
	var v []int64
	rest, err := asn1.UnmarshalWithParams(der, &v, "set")
	if err == nil && len(rest) != 0 {
		err = errors.New("data tersisa")
	}
	return v, err
}

func androidFailure(reason string) *AttestationResult {
	return &AttestationResult{Status: AttestationFailed, Reason: reason}
}

func VerifyAndroidAttestation(cfg *AndroidAttestationConfig, chainB64 []string, spkiDER []byte, challenge []byte) *AttestationResult {
	if cfg == nil || cfg.Roots == nil {
		return &AttestationResult{Status: AttestationUnverified, Reason: "ANDROID_ROOTS_NOT_CONFIGURED"}
	}
	if len(chainB64) < 2 || len(chainB64) > maxAttestationChain {
		return androidFailure("CHAIN_LENGTH")
	}
	certs := make([]*x509.Certificate, 0, len(chainB64))
	for _, s := range chainB64 {
		der, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
		if err != nil || len(der) == 0 || len(der) > maxAttestationCertSz {
			return androidFailure("CHAIN_ENCODING")
		}
		c, err := x509.ParseCertificate(der)
		if err != nil {
			return androidFailure("CHAIN_PARSE")
		}
		certs = append(certs, c)
	}
	leaf := certs[0]
	if !bytes.Equal(leaf.RawSubjectPublicKeyInfo, spkiDER) {
		return androidFailure("LEAF_KEY_MISMATCH") // the chain attests another key
	}
	now := time.Now
	if cfg.Now != nil {
		now = cfg.Now
	}
	inter := x509.NewCertPool()
	for _, c := range certs[1:] {
		inter.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots: cfg.Roots, Intermediates: inter, CurrentTime: now(), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return androidFailure("CHAIN_UNTRUSTED")
	}
	if cfg.RevocationLoaded {
		for _, c := range certs {
			if cfg.revoked()[strings.ToLower(c.SerialNumber.Text(16))] {
				return androidFailure("CERT_REVOKED")
			}
		}
	}

	var ext []byte
	for _, e := range leaf.Extensions {
		if e.Id.Equal(oidAndroidKeyDescription) {
			ext = e.Value
		}
	}
	if ext == nil {
		return androidFailure("NO_KEY_DESCRIPTION")
	}
	var kd keyDescription
	if rest, err := asn1.Unmarshal(ext, &kd); err != nil || len(rest) != 0 {
		return androidFailure("KEY_DESCRIPTION_PARSE")
	}
	if !bytes.Equal(kd.AttestationChallenge, challenge) {
		return androidFailure("CHALLENGE_MISMATCH")
	}
	level := ""
	switch kd.AttestationSecurityLevel {
	case kmSecurityStrongBox:
		level = LevelStrongBox
	case kmSecurityTEE:
		level = LevelTEE
	default:
		return androidFailure("SOFTWARE_ATTESTATION")
	}
	if kd.KeymasterSecurityLevel != kd.AttestationSecurityLevel {
		return androidFailure("SECURITY_LEVEL_MISMATCH")
	}
	hw, err := authorizationList(kd.TeeEnforced)
	if err != nil {
		return androidFailure("HW_LIST_PARSE")
	}
	sw, err := authorizationList(kd.SoftwareEnforced)
	if err != nil {
		return androidFailure("SW_LIST_PARSE")
	}
	if purposes, err := asnIntSet(hw[tagPurpose]); err != nil || len(purposes) != 1 || purposes[0] != kmPurposeSign {
		return androidFailure("PURPOSE")
	}
	if alg, err := asnInt(hw[tagAlgorithm]); err != nil || alg != kmAlgorithmEC {
		return androidFailure("ALGORITHM")
	}
	if curve, err := asnInt(hw[tagECCurve]); err != nil || curve != kmCurveP256 {
		return androidFailure("CURVE")
	}
	if origin, err := asnInt(hw[tagOrigin]); err != nil || origin != kmOriginGenerated {
		return androidFailure("ORIGIN") // imported keys are refused
	}
	rotDER, ok := hw[tagRootOfTrust]
	if !ok {
		return androidFailure("NO_ROOT_OF_TRUST")
	}
	var rot rootOfTrust
	if rest, err := asn1.Unmarshal(rotDER, &rot); err != nil || len(rest) != 0 {
		return androidFailure("ROOT_OF_TRUST_PARSE")
	}
	if cfg.RequireVerifiedBoot && (!rot.DeviceLocked || rot.VerifiedBootState != kmBootStateVerified) {
		return androidFailure("BOOT_NOT_VERIFIED")
	}

	appDER, ok := sw[tagAttestationAppID]
	if !ok {
		appDER, ok = hw[tagAttestationAppID]
	}
	if cfg.PackageName == "" || len(cfg.SigningCertSHA256) == 0 {
		return &AttestationResult{Status: AttestationUnverified, Reason: "APP_IDENTITY_NOT_CONFIGURED"}
	}
	if !ok {
		return androidFailure("NO_APPLICATION_ID")
	}
	var octets []byte
	if rest, err := asn1.Unmarshal(appDER, &octets); err != nil || len(rest) != 0 {
		return androidFailure("APPLICATION_ID_PARSE")
	}
	var appID attestationApplicationID
	if rest, err := asn1.Unmarshal(octets, &appID); err != nil || len(rest) != 0 {
		return androidFailure("APPLICATION_ID_PARSE")
	}
	pkgOK := false
	for _, p := range appID.PackageInfos {
		if string(p.PackageName) == cfg.PackageName {
			pkgOK = true
		}
	}
	if !pkgOK || len(appID.PackageInfos) != 1 {
		return androidFailure("PACKAGE_MISMATCH") // shared UID / other app
	}
	digestOK := len(appID.SignatureDigests) > 0
	for _, d := range appID.SignatureDigests {
		match := false
		for _, want := range cfg.SigningCertSHA256 {
			if bytes.Equal(d, want) {
				match = true
			}
		}
		digestOK = digestOK && match
	}
	if !digestOK {
		return androidFailure("SIGNING_CERT_MISMATCH")
	}
	return &AttestationResult{
		Status: AttestationHardwareVerified, SecurityLevel: level,
		Summary: fmt.Sprintf("android-key v%d %s boot=%d locked=%v revocation_checked=%v",
			kd.AttestationVersion, level, rot.VerifiedBootState, rot.DeviceLocked, cfg.RevocationLoaded),
	}
}

func LoadCertPool(path string) (*x509.CertPool, int, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}
	pool := x509.NewCertPool()
	n := 0
	for {
		var block *pem.Block
		block, raw = pem.Decode(raw)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			continue
		}
		c, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, 0, fmt.Errorf("sertifikat root tidak valid: %w", err)
		}
		pool.AddCert(c)
		n++
	}
	if n == 0 {
		return nil, 0, errors.New("tidak ada sertifikat PEM di file root")
	}
	return pool, n, nil
}

func LoadRevocationList(path string) (map[string]bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Entries map[string]struct {
			Status string `json:"status"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("daftar status attestation tidak valid: %w", err)
	}
	if doc.Entries == nil {
		return nil, errors.New("daftar status attestation tidak memiliki entries")
	}
	out := make(map[string]bool, len(doc.Entries))
	for serial, e := range doc.Entries {
		st := strings.ToUpper(e.Status)
		if st == "REVOKED" || st == "SUSPENDED" {
			out[strings.ToLower(strings.TrimLeft(serial, "0"))] = true
		}
	}
	return out, nil
}

func ParseHexDigests(list []string) ([][]byte, error) {
	var out [][]byte
	for _, s := range list {
		s = strings.ReplaceAll(strings.TrimSpace(s), ":", "")
		if s == "" {
			continue
		}
		b, err := hex.DecodeString(s)
		if err != nil || len(b) != 32 {
			return nil, fmt.Errorf("digest sertifikat signing tidak valid: %q", s)
		}
		out = append(out, b)
	}
	return out, nil
}
