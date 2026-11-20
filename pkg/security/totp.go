package security

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// TOTP (RFC 6238: HMAC-SHA1, 30-second steps, 6 digits) for officer MFA (audit E-01).
// The parameters are those every authenticator app supports.
const (
	totpStep   = 30
	totpDigits = 6
	// totpSkew accepts the previous and next step (clock drift of the officer's phone).
	totpSkew = 1
)

var totpEncoding = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewTOTPSecret returns a random 160-bit secret, base32 encoded (no padding).
func NewTOTPSecret() (string, error) {
	b := make([]byte, 20)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return totpEncoding.EncodeToString(b), nil
}

// TOTPProvisioningURI is the otpauth:// URI an authenticator app imports (manually or as QR).
func TOTPProvisioningURI(issuer, account, secret string) string {
	label := url.PathEscape(issuer + ":" + account)
	q := url.Values{}
	q.Set("secret", secret)
	q.Set("issuer", issuer)
	q.Set("algorithm", "SHA1")
	q.Set("digits", fmt.Sprint(totpDigits))
	q.Set("period", fmt.Sprint(totpStep))
	return "otpauth://totp/" + label + "?" + q.Encode()
}

func totpCode(key []byte, counter int64) string {
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], uint64(counter))
	m := hmac.New(sha1.New, key)
	m.Write(msg[:])
	sum := m.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	v := (uint32(sum[off])&0x7f)<<24 | uint32(sum[off+1])<<16 | uint32(sum[off+2])<<8 | uint32(sum[off+3])
	return fmt.Sprintf("%0*d", totpDigits, v%1_000_000)
}

// VerifyTOTP checks a code against the secret at time now. A step at or before lastStep is
// refused (a code is single use: an observed code cannot be replayed). It returns the
// matched step, to be stored as the new lastStep.
func VerifyTOTP(secret, code string, now time.Time, lastStep int64) (int64, bool) {
	code = strings.TrimSpace(code)
	if len(code) != totpDigits {
		return 0, false
	}
	key, err := totpEncoding.DecodeString(strings.ToUpper(strings.TrimSpace(secret)))
	if err != nil || len(key) == 0 {
		return 0, false
	}
	current := now.Unix() / totpStep
	for d := int64(-totpSkew); d <= totpSkew; d++ {
		step := current + d
		if step <= lastStep {
			continue
		}
		if subtle.ConstantTimeCompare([]byte(totpCode(key, step)), []byte(code)) == 1 {
			return step, true
		}
	}
	return 0, false
}
