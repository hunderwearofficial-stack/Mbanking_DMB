// Package rekey re-encrypts customer PII columns to the current key (audit DMB-008).
//
// It converts legacy plaintext values and legacy "enc:v1:" ciphertext (produced
// with the key that was published in the repository) to "enc:v2:" under the
// active DB_ENCRYPTION_KEY. Plaintext values are never logged.
package rekey

import (
	"context"
	"fmt"

	"mbanking-bpr/pkg/crypto"

	"gorm.io/gorm"
)

// Columns of the users table holding encrypted PII.
var Columns = []string{"nik", "email", "alamat", "tgl_lahir", "tempat_lahir", "nama_ibu_kandung"}

// Stats summarizes a run.
type Stats struct {
	Scanned       int
	NeedsRekey    int
	Updated       int
	DecryptErrors int
}

type row struct {
	ID     string
	Values map[string]string
}

// Run scans all users; when apply is true, rewrites values that need re-encryption.
func Run(ctx context.Context, db *gorm.DB, apply bool, batchSize int) (Stats, error) {
	var st Stats
	if batchSize <= 0 {
		batchSize = 500
	}
	lastID := ""
	for {
		var ids []string
		q := db.WithContext(ctx).Table("users").Order("id ASC").Limit(batchSize)
		if lastID != "" {
			q = q.Where("id > ?", lastID)
		}
		if err := q.Pluck("id", &ids).Error; err != nil {
			return st, err
		}
		if len(ids) == 0 {
			return st, nil
		}
		for _, id := range ids {
			lastID = id
			st.Scanned++
			var raw map[string]interface{}
			if err := db.WithContext(ctx).Table("users").Select(Columns).Where("id = ?", id).Take(&raw).Error; err != nil {
				return st, err
			}
			updates := map[string]interface{}{}
			for _, col := range Columns {
				v, _ := raw[col].(string)
				if !crypto.NeedsReencryption(v) {
					continue
				}
				pt, err := crypto.DecryptString(v)
				if err != nil {
					st.DecryptErrors++
					continue
				}
				enc, err := crypto.EncryptString(pt)
				if err != nil {
					return st, fmt.Errorf("enkripsi gagal: %w", err)
				}
				updates[col] = enc
			}
			if len(updates) == 0 {
				continue
			}
			st.NeedsRekey++
			if apply {
				if err := db.WithContext(ctx).Table("users").Where("id = ?", id).Updates(updates).Error; err != nil {
					return st, err
				}
				st.Updated++
			}
		}
	}
}
