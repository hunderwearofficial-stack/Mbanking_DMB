package attesttest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type CA struct {
	rootKey, interKey *ecdsa.PrivateKey
	Root, Inter       *x509.Certificate
}

func mustKey() *ecdsa.PrivateKey {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	return k
}

var serial int64 = 1000

func nextSerial() *big.Int { serial++; return big.NewInt(serial) }

func NewCA(name string) *CA {
	ca := &CA{rootKey: mustKey(), interKey: mustKey()}
	now := time.Now()
	rootT := &x509.Certificate{SerialNumber: nextSerial(), Subject: pkix.Name{CommonName: name + " TEST ROOT"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), IsCA: true, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageCertSign}
	der, err := x509.CreateCertificate(rand.Reader, rootT, rootT, &ca.rootKey.PublicKey, ca.rootKey)
	if err != nil {
		panic(err)
	}
	ca.Root, _ = x509.ParseCertificate(der)
	interT := &x509.Certificate{SerialNumber: nextSerial(), Subject: pkix.Name{CommonName: name + " TEST INTERMEDIATE"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), IsCA: true, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageCertSign}
	der, err = x509.CreateCertificate(rand.Reader, interT, ca.Root, &ca.interKey.PublicKey, ca.rootKey)
	if err != nil {
		panic(err)
	}
	ca.Inter, _ = x509.ParseCertificate(der)
	return ca
}

func (ca *CA) WriteRootPEM(dir, name string) string {
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: ca.Root.Raw}), 0o600); err != nil {
		panic(err)
	}
	return p
}

func (ca *CA) leaf(pub *ecdsa.PublicKey, ext pkix.Extension) *x509.Certificate {
	now := time.Now()
	t := &x509.Certificate{SerialNumber: nextSerial(), Subject: pkix.Name{CommonName: "TEST LEAF"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), KeyUsage: x509.KeyUsageDigitalSignature,
		ExtraExtensions: []pkix.Extension{ext}}
	der, err := x509.CreateCertificate(rand.Reader, t, ca.Inter, pub, ca.interKey)
	if err != nil {
		panic(err)
	}
	c, _ := x509.ParseCertificate(der)
	return c
}

type AndroidOptions struct {
	SecurityLevel int // 0 software, 1 TEE, 2 StrongBox
	Purposes      []int
	Algorithm     int
	Curve         int
	Origin        int
	DeviceLocked  bool
	BootState     int // 0 verified
	PackageName   string
	CertDigest    []byte
	Challenge     []byte
}

func DefaultAndroid(pkg string, digest, challenge []byte) AndroidOptions {
	return AndroidOptions{SecurityLevel: 2, Purposes: []int{2}, Algorithm: 3, Curve: 1, Origin: 0, DeviceLocked: true,
		BootState: 0, PackageName: pkg, CertDigest: digest, Challenge: challenge}
}

func mustMarshal(v interface{}, params ...string) []byte {
	var b []byte
	var err error
	if len(params) > 0 {
		b, err = asn1.MarshalWithParams(v, params[0])
	} else {
		b, err = asn1.Marshal(v)
	}
	if err != nil {
		panic(err)
	}
	return b
}

func explicit(tag int, inner []byte) []byte {
	return mustMarshal(asn1.RawValue{Class: asn1.ClassContextSpecific, Tag: tag, IsCompound: true, Bytes: inner})
}

func sequence(elements ...[]byte) []byte {
	var body []byte
	for _, e := range elements {
		body = append(body, e...)
	}
	return mustMarshal(asn1.RawValue{Class: asn1.ClassUniversal, Tag: asn1.TagSequence, IsCompound: true, Bytes: body})
}

func (ca *CA) AndroidChain(pub *ecdsa.PublicKey, o AndroidOptions) []string {
	rot := mustMarshal(struct {
		VerifiedBootKey   []byte
		DeviceLocked      bool
		VerifiedBootState asn1.Enumerated
		VerifiedBootHash  []byte
	}{make([]byte, 32), o.DeviceLocked, asn1.Enumerated(o.BootState), make([]byte, 32)})
	hw := sequence(
		explicit(1, mustMarshal(o.Purposes, "set")),
		explicit(2, mustMarshal(o.Algorithm)),
		explicit(3, mustMarshal(256)),
		explicit(10, mustMarshal(o.Curve)),
		explicit(702, mustMarshal(o.Origin)),
		explicit(704, rot),
	)
	type pkgInfo struct {
		PackageName []byte
		Version     int64
	}
	appID := mustMarshal(struct {
		PackageInfos     []pkgInfo `asn1:"set"`
		SignatureDigests [][]byte  `asn1:"set"`
	}{[]pkgInfo{{[]byte(o.PackageName), 1}}, [][]byte{o.CertDigest}})
	sw := sequence(explicit(709, mustMarshal(appID)))
	kd := mustMarshal(struct {
		AttestationVersion       int
		AttestationSecurityLevel asn1.Enumerated
		KeymasterVersion         int
		KeymasterSecurityLevel   asn1.Enumerated
		AttestationChallenge     []byte
		UniqueID                 []byte
		SoftwareEnforced         asn1.RawValue
		TeeEnforced              asn1.RawValue
	}{300, asn1.Enumerated(o.SecurityLevel), 300, asn1.Enumerated(o.SecurityLevel), o.Challenge, []byte{},
		asn1.RawValue{FullBytes: sw}, asn1.RawValue{FullBytes: hw}})
	leaf := ca.leaf(pub, pkix.Extension{Id: asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 11129, 2, 1, 17}, Value: kd})
	return []string{
		base64.StdEncoding.EncodeToString(leaf.Raw),
		base64.StdEncoding.EncodeToString(ca.Inter.Raw),
		base64.StdEncoding.EncodeToString(ca.Root.Raw),
	}
}

type AppleKey struct {
	Priv  *ecdsa.PrivateKey
	KeyID []byte
}

func NewAppleKey() *AppleKey {
	k := mustKey()
	sum := sha256.Sum256(elliptic.Marshal(elliptic.P256(), k.PublicKey.X, k.PublicKey.Y)) //nolint:staticcheck
	return &AppleKey{Priv: k, KeyID: sum[:]}
}

func (k *AppleKey) KeyIDB64() string { return base64.StdEncoding.EncodeToString(k.KeyID) }

func (ca *CA) AppleAttestation(k *AppleKey, appID string, aaguid []byte, counter uint32, clientData []byte) string {
	rp := sha256.Sum256([]byte(appID))
	auth := append([]byte{}, rp[:]...)
	auth = append(auth, 0x41)
	auth = binary.BigEndian.AppendUint32(auth, counter)
	auth = append(auth, aaguid...)
	auth = binary.BigEndian.AppendUint16(auth, uint16(len(k.KeyID)))
	auth = append(auth, k.KeyID...)
	cdh := sha256.Sum256(clientData)
	nonce := sha256.Sum256(append(append([]byte{}, auth...), cdh[:]...))
	ext := mustMarshal(struct {
		Nonce []byte `asn1:"explicit,tag:1"`
	}{nonce[:]})
	leaf := ca.leaf(&k.Priv.PublicKey, pkix.Extension{Id: asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}, Value: ext})
	obj := map[string]interface{}{
		"fmt":      "apple-appattest",
		"attStmt":  map[string]interface{}{"x5c": []interface{}{leaf.Raw, ca.Inter.Raw}, "receipt": []byte("test-receipt")},
		"authData": auth,
	}
	return base64.StdEncoding.EncodeToString(EncodeCBOR(obj))
}

func AppleAssertion(k *AppleKey, appID string, counter uint32, clientData []byte) string {
	rp := sha256.Sum256([]byte(appID))
	auth := append([]byte{}, rp[:]...)
	auth = append(auth, 0x01)
	auth = binary.BigEndian.AppendUint32(auth, counter)
	cdh := sha256.Sum256(clientData)
	nonce := sha256.Sum256(append(append([]byte{}, auth...), cdh[:]...))
	sig, err := ecdsa.SignASN1(rand.Reader, k.Priv, nonce[:])
	if err != nil {
		panic(err)
	}
	return base64.StdEncoding.EncodeToString(EncodeCBOR(map[string]interface{}{"signature": sig, "authenticatorData": auth}))
}

func EncodeCBOR(v interface{}) []byte {
	head := func(major byte, n uint64) []byte {
		switch {
		case n < 24:
			return []byte{major<<5 | byte(n)}
		case n < 256:
			return []byte{major<<5 | 24, byte(n)}
		case n < 65536:
			return binary.BigEndian.AppendUint16([]byte{major<<5 | 25}, uint16(n))
		default:
			return binary.BigEndian.AppendUint32([]byte{major<<5 | 26}, uint32(n))
		}
	}
	switch t := v.(type) {
	case uint64:
		return head(0, t)
	case []byte:
		return append(head(2, uint64(len(t))), t...)
	case string:
		return append(head(3, uint64(len(t))), t...)
	case []interface{}:
		out := head(4, uint64(len(t)))
		for _, e := range t {
			out = append(out, EncodeCBOR(e)...)
		}
		return out
	case map[string]interface{}:
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		out := head(5, uint64(len(t)))
		for _, k := range keys {
			out = append(out, EncodeCBOR(k)...)
			out = append(out, EncodeCBOR(t[k])...)
		}
		return out
	}
	panic("attesttest: unsupported CBOR type")
}
