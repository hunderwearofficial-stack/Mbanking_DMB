package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql/driver"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
)

const (
	// AESKeyLength is 32 bytes for AES-256
	AESKeyLength = 32
	// GCMNonceLength standard 12 bytes for AES-GCM
	GCMNonceLength = 12
	// CipherPrefix identifies AES-256-GCM encrypted fields version 1
	CipherPrefix = "enc:v1:"
)

var (
	// Default master key (used for development/fallback, overridden in production via DB_ENCRYPTION_KEY)
	defaultKey = []byte("dmb-bank-aes256-gcm-master-key32")

	keyMu        sync.RWMutex
	activeKey    = defaultKey
	activeKeySet = false

	ErrInvalidCiphertext = errors.New("ciphertext tidak valid atau format rusak")
	ErrDecryptionFailed  = errors.New("dekripsi AES-256-GCM gagal: tag integritas tidak cocok atau kunci salah")
	ErrKeyLengthInvalid  = errors.New("kunci enkripsi AES-256 harus tepat 32 byte (256-bit)")
)

// InitEncryptionKey sets the global 256-bit AES master key from configuration or environment
func InitEncryptionKey(rawKey string) error {
	keyMu.Lock()
	defer keyMu.Unlock()

	trimmed := strings.TrimSpace(rawKey)
	if trimmed == "" {
		// Keep default development key
		return nil
	}

	// 1. Try decoding as 64-char Hex (32 bytes)
	if len(trimmed) == 64 {
		if decodedHex, err := hex.DecodeString(trimmed); err == nil && len(decodedHex) == AESKeyLength {
			activeKey = decodedHex
			activeKeySet = true
			return nil
		}
	}

	// 2. Try decoding as Base64 (32 bytes)
	if decodedB64, err := base64.StdEncoding.DecodeString(trimmed); err == nil && len(decodedB64) == AESKeyLength {
		activeKey = decodedB64
		activeKeySet = true
		return nil
	}

	// 3. Raw byte string: pad or derive SHA-256 to ensure exactly 32 bytes
	if len(trimmed) == AESKeyLength {
		activeKey = []byte(trimmed)
		activeKeySet = true
		return nil
	}

	// Derive uniform 32-byte key using SHA-256
	h := sha256.Sum256([]byte(trimmed))
	activeKey = h[:]
	activeKeySet = true
	return nil
}

// GetActiveKey safely returns a copy of current active master key
func GetActiveKey() []byte {
	keyMu.RLock()
	defer keyMu.RUnlock()
	keyCopy := make([]byte, len(activeKey))
	copy(keyCopy, activeKey)
	return keyCopy
}

// Encrypt encrypts raw plaintext bytes using AES-256-GCM with a cryptographically secure random nonce.
// The result is prefixed with "enc:v1:" and Base64-encoded (nonce + ciphertext + tag).
func Encrypt(plaintext []byte) (string, error) {
	if len(plaintext) == 0 {
		return "", nil
	}

	key := GetActiveKey()
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("gagal membuat AES cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("gagal menginisialisasi GCM mode: %w", err)
	}

	// Generate 12-byte cryptographically secure random nonce
	nonce := make([]byte, GCMNonceLength)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("gagal menghasilkan nonce acak: %w", err)
	}

	// Seal: appends ciphertext + 16-byte authentication tag to nonce
	sealed := gcm.Seal(nonce, nonce, plaintext, nil)

	// Return prefixed base64 string
	return CipherPrefix + base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt decrypts an "enc:v1:" prefixed Base64 string using AES-256-GCM.
// If the input is not prefixed (e.g. legacy unencrypted plaintext during migration), it gracefully returns the input as-is.
func Decrypt(ciphertextStr string) ([]byte, error) {
	trimmed := strings.TrimSpace(ciphertextStr)
	if trimmed == "" {
		return []byte(""), nil
	}

	// Backward Compatibility: If not encrypted with prefix, return plain string bytes
	if !strings.HasPrefix(trimmed, CipherPrefix) {
		return []byte(trimmed), nil
	}

	rawB64 := strings.TrimPrefix(trimmed, CipherPrefix)
	ciphertext, err := base64.StdEncoding.DecodeString(rawB64)
	if err != nil {
		return nil, ErrInvalidCiphertext
	}

	if len(ciphertext) < GCMNonceLength+16 {
		return nil, ErrInvalidCiphertext
	}

	key := GetActiveKey()
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("gagal membuat AES cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gagal menginisialisasi GCM mode: %w", err)
	}

	nonce := ciphertext[:GCMNonceLength]
	actualCiphertext := ciphertext[GCMNonceLength:]

	plaintext, err := gcm.Open(nil, nonce, actualCiphertext, nil)
	if err != nil {
		return nil, ErrDecryptionFailed
	}

	return plaintext, nil
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
	bytes, err := Decrypt(ciphertext)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// BlindIndex creates a deterministic HMAC-SHA256 hash of a search term (e.g. for looking up encrypted columns).
func BlindIndex(term string) string {
	if strings.TrimSpace(term) == "" {
		return ""
	}
	key := GetActiveKey()
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(strings.ToLower(strings.TrimSpace(term))))
	return hex.EncodeToString(mac.Sum(nil))
}

// ============================================================================
// GORM Custom Data Type: EncryptedString
// ============================================================================

// EncryptedString is a GORM-compatible string type that automatically encrypts
// on INSERT/UPDATE (Valuer) and automatically decrypts on SELECT (Scanner).
type EncryptedString string

// Value implements driver.Valuer interface for GORM / database writes
func (e EncryptedString) Value() (driver.Value, error) {
	val := string(e)
	if val == "" {
		return "", nil
	}

	// If already encrypted with prefix, don't double-encrypt
	if strings.HasPrefix(val, CipherPrefix) {
		return val, nil
	}

	encrypted, err := EncryptString(val)
	if err != nil {
		return nil, fmt.Errorf("gagal mengenkripsi kolom database: %w", err)
	}
	return encrypted, nil
}

// Scan implements sql.Scanner interface for GORM / database reads
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
		// In case of integrity error, keep raw string rather than crashing application
		*e = EncryptedString(raw)
		return nil
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

