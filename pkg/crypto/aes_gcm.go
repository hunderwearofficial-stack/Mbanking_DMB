package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"database/sql/driver"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
)

// Column-level encryption for customer PII (UU PDP).
//
// SECURITY (audit DMB-008):
//   - There is NO built-in default key. The process must call InitKeys with a
//     key supplied from the secret manager; Encrypt/Decrypt fail otherwise.
//   - Ciphertext format v2: "enc:v2:" + base64(nonce|ciphertext|tag), encrypted
//     with the ACTIVE key.
//   - Legacy format v1 ("enc:v1:") was produced with a key that was published in
//     the repository. v1 values are decrypted with the PREVIOUS key (if set) or
//     the active key, and are re-encrypted to v2 on the next write or by running
//     `go run ./cmd/rekey`.
//   - Decryption failures are returned as errors (fail-closed), never silently
//     replaced by raw ciphertext.

const (
	// AESKeyLength is 32 bytes for AES-256
	AESKeyLength = 32
	// GCMNonceLength standard 12 bytes for AES-GCM
	GCMNonceLength = 12
	// CipherPrefix identifies the current ciphertext format (active key).
	CipherPrefix = "enc:v2:"
	// LegacyCipherPrefix identifies ciphertext produced before key rotation.
	LegacyCipherPrefix = "enc:v1:"
)

var (
	keyMu       sync.RWMutex
	activeKey   []byte
	previousKey []byte

	ErrKeyNotInitialized = errors.New("kunci enkripsi database belum diinisialisasi")
	ErrInvalidCiphertext = errors.New("ciphertext tidak valid atau format rusak")
	ErrDecryptionFailed  = errors.New("dekripsi AES-256-GCM gagal: tag integritas tidak cocok atau kunci salah")
	ErrKeyLengthInvalid  = errors.New("kunci enkripsi AES-256 harus tepat 32 byte (64 karakter hex atau base64 32 byte)")
)

// ParseKey decodes a 256-bit key given as 64 hex characters or base64 of 32 bytes.
// Raw passphrases are rejected: keys must be generated randomly (e.g. `openssl rand -hex 32`).
func ParseKey(raw string) ([]byte, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil, ErrKeyLengthInvalid
	}
	if len(trimmed) == 64 {
		if k, err := hex.DecodeString(trimmed); err == nil && len(k) == AESKeyLength {
			return k, nil
		}
	}
	if k, err := base64.StdEncoding.DecodeString(trimmed); err == nil && len(k) == AESKeyLength {
		return k, nil
	}
	return nil, ErrKeyLengthInvalid
}

// parseLegacyKey additionally accepts the historical 32-character raw-string key
// format, ONLY for decrypting legacy enc:v1 data during rotation.
func parseLegacyKey(raw string) ([]byte, error) {
	if k, err := ParseKey(raw); err == nil {
		return k, nil
	}
	trimmed := strings.TrimSpace(raw)
	if len(trimmed) == AESKeyLength {
		return []byte(trimmed), nil
	}
	return nil, ErrKeyLengthInvalid
}

// InitKeys configures the active key (required) and an optional previous key
// (decrypt-only, used for legacy/rotated ciphertext).
func InitKeys(active, previous string) error {
	ak, err := ParseKey(active)
	if err != nil {
		return fmt.Errorf("DB_ENCRYPTION_KEY: %w", err)
	}
	var pk []byte
	if strings.TrimSpace(previous) != "" {
		pk, err = parseLegacyKey(previous)
		if err != nil {
			return fmt.Errorf("DB_ENCRYPTION_KEY_PREVIOUS: %w", err)
		}
	}
	keyMu.Lock()
	defer keyMu.Unlock()
	activeKey = ak
	previousKey = pk
	return nil
}

func getKeys() (active, previous []byte, err error) {
	keyMu.RLock()
	defer keyMu.RUnlock()
	if len(activeKey) != AESKeyLength {
		return nil, nil, ErrKeyNotInitialized
	}
	a := append([]byte(nil), activeKey...)
	var p []byte
	if len(previousKey) == AESKeyLength {
		p = append([]byte(nil), previousKey...)
	}
	return a, p, nil
}

func newGCM(key []byte) (cipher.AEAD, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("gagal membuat AES cipher: %w", err)
	}
	return cipher.NewGCM(block)
}

// Encrypt encrypts plaintext with the active key (format v2).
func Encrypt(plaintext []byte) (string, error) {
	if len(plaintext) == 0 {
		return "", nil
	}
	key, _, err := getKeys()
	if err != nil {
		return "", err
	}
	gcm, err := newGCM(key)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, GCMNonceLength)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("gagal menghasilkan nonce acak: %w", err)
	}
	sealed := gcm.Seal(nonce, nonce, plaintext, nil)
	return CipherPrefix + base64.StdEncoding.EncodeToString(sealed), nil
}

func openWith(key []byte, raw []byte) ([]byte, error) {
	gcm, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	plaintext, err := gcm.Open(nil, raw[:GCMNonceLength], raw[GCMNonceLength:], nil)
	if err != nil {
		return nil, ErrDecryptionFailed
	}
	return plaintext, nil
}

// NeedsReencryption reports whether a stored value is plaintext or legacy v1.
func NeedsReencryption(v string) bool {
	t := strings.TrimSpace(v)
	return t != "" && !strings.HasPrefix(t, CipherPrefix)
}

// Decrypt decrypts v2 (active key) or v1 (previous key, then active key).
// Values without any prefix are legacy plaintext and returned unchanged so the
// rekey migration can encrypt them; they are reported by NeedsReencryption.
func Decrypt(ciphertextStr string) ([]byte, error) {
	trimmed := strings.TrimSpace(ciphertextStr)
	if trimmed == "" {
		return []byte(""), nil
	}

	var payload string
	legacy := false
	switch {
	case strings.HasPrefix(trimmed, CipherPrefix):
		payload = strings.TrimPrefix(trimmed, CipherPrefix)
	case strings.HasPrefix(trimmed, LegacyCipherPrefix):
		payload = strings.TrimPrefix(trimmed, LegacyCipherPrefix)
		legacy = true
	default:
		return []byte(trimmed), nil
	}

	raw, err := base64.StdEncoding.DecodeString(payload)
	if err != nil || len(raw) < GCMNonceLength+16 {
		return nil, ErrInvalidCiphertext
	}

	active, previous, err := getKeys()
	if err != nil {
		return nil, err
	}

	if !legacy {
		return openWith(active, raw)
	}
	if previous != nil {
		if pt, err := openWith(previous, raw); err == nil {
			return pt, nil
		}
	}
	return openWith(active, raw)
}

// EncryptString is a convenience helper for string plaintext
func EncryptString(plaintext string) (string, error) {
	if plaintext == "" {
		return "", nil
	}
	return Encrypt([]byte(plaintext))
}

// DecryptString is a convenience helper for string ciphertext
func DecryptString(ciphertext string) (string, error) {
	if ciphertext == "" {
		return "", nil
	}
	b, err := Decrypt(ciphertext)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// ============================================================================
// GORM Custom Data Type: EncryptedString
// ============================================================================

// EncryptedString is a GORM-compatible string type that automatically encrypts
// on INSERT/UPDATE (Valuer) and automatically decrypts on SELECT (Scanner).
type EncryptedString string

// Value implements driver.Valuer interface for GORM / database writes.
// Values are always written in the current (v2) format.
func (e EncryptedString) Value() (driver.Value, error) {
	val := string(e)
	if val == "" {
		return "", nil
	}
	if strings.HasPrefix(val, CipherPrefix) {
		return val, nil
	}
	if strings.HasPrefix(val, LegacyCipherPrefix) {
		pt, err := DecryptString(val)
		if err != nil {
			return nil, fmt.Errorf("gagal re-enkripsi kolom legacy: %w", err)
		}
		val = pt
	}
	encrypted, err := EncryptString(val)
	if err != nil {
		return nil, fmt.Errorf("gagal mengenkripsi kolom database: %w", err)
	}
	return encrypted, nil
}

// Scan implements sql.Scanner interface for GORM / database reads (fail-closed).
func (e *EncryptedString) Scan(value interface{}) error {
	if value == nil {
		*e = ""
		return nil
	}
	var raw string
	switch v := value.(type) {
	case string:
		raw = v
	case []byte:
		raw = string(v)
	default:
		return fmt.Errorf("tipe data tidak didukung untuk EncryptedString: %T", value)
	}
	if raw == "" {
		*e = ""
		return nil
	}
	decrypted, err := DecryptString(raw)
	if err != nil {
		return fmt.Errorf("dekripsi kolom PII gagal: %w", err)
	}
	*e = EncryptedString(decrypted)
	return nil
}

func (e EncryptedString) String() string {
	return string(e)
}

func (e EncryptedString) IsEmpty() bool {
	return string(e) == ""
}
