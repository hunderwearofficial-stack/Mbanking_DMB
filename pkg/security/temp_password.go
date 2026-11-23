package security

import (
	"crypto/rand"
	"errors"
	"math/big"
)

// Characters of a one-time officer password: no look-alikes (0/O, 1/l/I) so it can be
// read out or typed from a screen without mistakes.
const (
	tempLower  = "abcdefghijkmnpqrstuvwxyz"
	tempUpper  = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	tempDigits = "23456789"
	tempAll    = tempLower + tempUpper + tempDigits
)

// GenerateTemporaryPassword returns a random one-time password (16 characters, with lower
// case, upper case and digits) that satisfies the officer password policy. It is issued by
// the system on approval and must be changed at first login (audit MA-03).
func GenerateTemporaryPassword() (string, error) {
	const length = 16
	for attempt := 0; attempt < 10; attempt++ {
		b := make([]byte, length)
		sets := []string{tempLower, tempUpper, tempDigits}
		for i := 0; i < length; i++ {
			set := tempAll
			if i < len(sets) {
				set = sets[i]
			}
			c, err := randomChar(set)
			if err != nil {
				return "", err
			}
			b[i] = c
		}
		if err := shuffle(b); err != nil {
			return "", err
		}
		pw := string(b)
		if ValidateNewPassword(pw) == nil {
			return pw, nil
		}
	}
	return "", errors.New("gagal membuat password sementara")
}

func randomChar(set string) (byte, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(int64(len(set))))
	if err != nil {
		return 0, err
	}
	return set[n.Int64()], nil
}

func shuffle(b []byte) error {
	for i := len(b) - 1; i > 0; i-- {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(i+1)))
		if err != nil {
			return err
		}
		j := n.Int64()
		b[i], b[j] = b[j], b[i]
	}
	return nil
}
