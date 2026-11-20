package legaldoc

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const MaxPDFBytes = 10 << 20

var (
	ErrFileNotFound = errors.New("berkas tidak ditemukan")
	ErrInvalidFile  = errors.New("berkas tidak valid")
)

type FileStore interface {
	Put(ctx context.Context, tx *gorm.DB, contentType string, data []byte) (string, error)
	Get(ctx context.Context, sha string) ([]byte, string, error)
}

type storedFile struct {
	SHA256      string `gorm:"column:sha256;primaryKey"`
	ContentType string `gorm:"column:content_type"`
	SizeBytes   int    `gorm:"column:size_bytes"`
	Content     []byte `gorm:"column:content"`
}

func (storedFile) TableName() string { return "stored_files" }

type DBFileStore struct{ db *gorm.DB }

func NewDBFileStore(db *gorm.DB) *DBFileStore { return &DBFileStore{db: db} }

func (s *DBFileStore) Put(ctx context.Context, tx *gorm.DB, contentType string, data []byte) (string, error) {
	if contentType != "application/pdf" {
		return "", fmt.Errorf("%w: tipe berkas tidak diizinkan", ErrInvalidFile)
	}
	if len(data) == 0 || len(data) > MaxPDFBytes {
		return "", fmt.Errorf("%w: ukuran berkas tidak valid", ErrInvalidFile)
	}
	if !bytes.HasPrefix(data, []byte("%PDF-")) || !bytes.Contains(data[max(0, len(data)-1024):], []byte("%%EOF")) {
		return "", fmt.Errorf("%w: bukan dokumen PDF yang lengkap", ErrInvalidFile)
	}
	sum := sha256.Sum256(data)
	sha := hex.EncodeToString(sum[:])
	db := tx
	if db == nil {
		db = s.db
	}
	err := db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).
		Create(&storedFile{SHA256: sha, ContentType: contentType, SizeBytes: len(data), Content: data}).Error
	if err != nil {
		return "", err
	}
	return sha, nil
}

func (s *DBFileStore) Get(ctx context.Context, sha string) ([]byte, string, error) {
	if len(sha) != 64 {
		return nil, "", ErrFileNotFound
	}
	var f storedFile
	if err := s.db.WithContext(ctx).Where("sha256 = ?", sha).First(&f).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, "", ErrFileNotFound
		}
		return nil, "", err
	}
	sum := sha256.Sum256(f.Content)
	if hex.EncodeToString(sum[:]) != sha {
		return nil, "", fmt.Errorf("integritas berkas %s tidak sesuai (hash berbeda)", sha[:12])
	}
	return f.Content, f.ContentType, nil
}
