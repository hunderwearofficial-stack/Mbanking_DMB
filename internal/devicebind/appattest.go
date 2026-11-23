package devicebind

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"strings"
	"time"
)

var oidAppleNonce = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}

var (
	aaguidProduction  = append([]byte("appattest"), make([]byte, 7)...)
	aaguidDevelopment = []byte("appattestdevelop")
)

type AppleAttestationConfig struct {
	Roots       *x509.CertPool
	AppID       string // TeamID.bundleID (DB-H8 / bank input)
	Environment string // "production" | "development"
	Now         func() time.Time
}

func (c *AppleAttestationConfig) aaguid() []byte {
	if c.Environment == "development" {
		return aaguidDevelopment
	}
	return aaguidProduction
}

func appleFailure(reason string) *AttestationResult {
	return &AttestationResult{Status: AttestationFailed, Reason: reason}
}

type AppleAttestedKey struct {
	PublicKey *ecdsa.PublicKey
	SPKI      []byte
	KeyID     []byte // sha256 of the uncompressed public key
}

func VerifyAppleAttestation(cfg *AppleAttestationConfig, attestationB64, keyIDB64 string, clientData []byte) (*AppleAttestedKey, *AttestationResult) {
	if cfg == nil || cfg.Roots == nil || cfg.AppID == "" {
		return nil, &AttestationResult{Status: AttestationUnverified, Reason: "APPLE_ATTESTATION_NOT_CONFIGURED"}
	}
	keyID, err := base64.StdEncoding.DecodeString(strings.TrimSpace(keyIDB64))
	if err != nil || len(keyID) != 32 {
		return nil, appleFailure("KEY_ID_ENCODING")
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(attestationB64))
	if err != nil || len(raw) == 0 || len(raw) > 64*1024 {
		return nil, appleFailure("ATTESTATION_ENCODING")
	}
	obj, err := decodeCBOR(raw)
	m, ok := obj.(map[string]interface{})
	if err != nil || !ok || m["fmt"] != "apple-appattest" {
		return nil, appleFailure("ATTESTATION_FORMAT")
	}
	stmt, _ := m["attStmt"].(map[string]interface{})
	authData, _ := m["authData"].([]byte)
	x5c, _ := stmt["x5c"].([]interface{})
	if stmt == nil || len(authData) < 55 || len(x5c) < 2 || len(x5c) > maxAttestationChain {
		return nil, appleFailure("ATTESTATION_STRUCTURE")
	}
	certs := make([]*x509.Certificate, 0, len(x5c))
	for _, v := range x5c {
		der, ok := v.([]byte)
		if !ok {
			return nil, appleFailure("CHAIN_ENCODING")
		}
		c, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, appleFailure("CHAIN_PARSE")
		}
		certs = append(certs, c)
	}
	now := time.Now
	if cfg.Now != nil {
		now = cfg.Now
	}
	inter := x509.NewCertPool()
	for _, c := range certs[1:] {
		inter.AddCert(c)
	}
	leaf := certs[0]
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: cfg.Roots, Intermediates: inter, CurrentTime: now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); err != nil {
		return nil, appleFailure("CHAIN_UNTRUSTED")
	}
	cdh := sha256.Sum256(clientData)
	nonce := sha256.Sum256(append(append([]byte{}, authData...), cdh[:]...))
	var extNonce []byte
	for _, e := range leaf.Extensions {
		if e.Id.Equal(oidAppleNonce) {
			var wrapper struct {
				Nonce []byte `asn1:"explicit,tag:1"`
			}
			if rest, err := asn1.Unmarshal(e.Value, &wrapper); err != nil || len(rest) != 0 {
				return nil, appleFailure("NONCE_PARSE")
			}
			extNonce = wrapper.Nonce
		}
	}
	if !bytes.Equal(extNonce, nonce[:]) {
		return nil, appleFailure("NONCE_MISMATCH") // attestation not made for this challenge
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		return nil, appleFailure("LEAF_KEY_TYPE")
	}
	point := elliptic.Marshal(elliptic.P256(), pub.X, pub.Y) //nolint:staticcheck // uncompressed form required by Apple
	kid := sha256.Sum256(point)
	if !bytes.Equal(kid[:], keyID) {
		return nil, appleFailure("KEY_ID_MISMATCH")
	}
	rp := sha256.Sum256([]byte(cfg.AppID))
	if !bytes.Equal(authData[:32], rp[:]) {
		return nil, appleFailure("APP_ID_MISMATCH")
	}
	if binary.BigEndian.Uint32(authData[33:37]) != 0 {
		return nil, appleFailure("COUNTER_NOT_ZERO")
	}
	if !bytes.Equal(authData[37:53], cfg.aaguid()) {
		return nil, appleFailure("ENVIRONMENT_MISMATCH")
	}
	credLen := int(binary.BigEndian.Uint16(authData[53:55]))
	if len(authData) < 55+credLen || !bytes.Equal(authData[55:55+credLen], keyID) {
		return nil, appleFailure("CREDENTIAL_ID_MISMATCH")
	}
	return &AppleAttestedKey{PublicKey: pub, SPKI: leaf.RawSubjectPublicKeyInfo, KeyID: keyID},
		&AttestationResult{Status: AttestationHardwareVerified, SecurityLevel: LevelSecureEnclave,
			Summary: "apple-appattest " + cfg.Environment}
}

func VerifyAppleAssertion(appID string, pub *ecdsa.PublicKey, assertionB64 string, clientData []byte, storedCounter uint32) (uint32, string) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(assertionB64))
	if err != nil || len(raw) == 0 || len(raw) > 4096 {
		return 0, "ASSERTION_ENCODING"
	}
	obj, err := decodeCBOR(raw)
	m, ok := obj.(map[string]interface{})
	if err != nil || !ok {
		return 0, "ASSERTION_FORMAT"
	}
	sig, _ := m["signature"].([]byte)
	authData, _ := m["authenticatorData"].([]byte)
	if len(sig) == 0 || len(authData) < 37 {
		return 0, "ASSERTION_STRUCTURE"
	}
	cdh := sha256.Sum256(clientData)
	nonce := sha256.Sum256(append(append([]byte{}, authData...), cdh[:]...))
	if !ecdsa.VerifyASN1(pub, nonce[:], sig) {
		return 0, "SIGNATURE_INVALID"
	}
	rp := sha256.Sum256([]byte(appID))
	if !bytes.Equal(authData[:32], rp[:]) {
		return 0, "APP_ID_MISMATCH"
	}
	counter := binary.BigEndian.Uint32(authData[33:37])
	if counter <= storedCounter {
		return 0, "ASSERTION_COUNTER_REPLAY"
	}
	return counter, ""
}
