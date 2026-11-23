package database

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"embed"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

const migrationLockID = 7203112602

var migrationName = regexp.MustCompile(`^(\d{4})_([a-z0-9_]+)\.sql$`)

var ErrSchemaNotCurrent = errors.New("skema database belum sesuai versi aplikasi")

type Migration struct {
	Version  int
	Name     string
	SQL      string
	Checksum string
}

type MigrationStatus struct {
	Migration
	AppliedAt *time.Time
}

func LoadMigrations() ([]Migration, error) {
	entries, err := migrationFiles.ReadDir("migrations")
	if err != nil {
		return nil, err
	}
	var out []Migration
	seen := map[int]bool{}
	for _, e := range entries {
		m := migrationName.FindStringSubmatch(e.Name())
		if m == nil {
			return nil, fmt.Errorf("nama file migrasi tidak valid: %s (format NNNN_nama.sql)", e.Name())
		}
		v, _ := strconv.Atoi(m[1])
		if seen[v] {
			return nil, fmt.Errorf("versi migrasi ganda: %04d", v)
		}
		seen[v] = true
		b, err := migrationFiles.ReadFile("migrations/" + e.Name())
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(b)
		out = append(out, Migration{Version: v, Name: m[2], SQL: string(b), Checksum: hex.EncodeToString(sum[:])})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Version < out[j].Version })
	return out, nil
}

const createMigrationsTable = `CREATE TABLE IF NOT EXISTS schema_migrations (
	version    integer PRIMARY KEY,
	name       text NOT NULL,
	checksum   char(64) NOT NULL,
	applied_at timestamptz NOT NULL DEFAULT now()
)`

type appliedRow struct {
	Name     string
	Checksum string
	At       time.Time
}

func readApplied(ctx context.Context, q interface {
	QueryContext(context.Context, string, ...interface{}) (*sql.Rows, error)
}) (map[int]appliedRow, error) {
	rows, err := q.QueryContext(ctx, `SELECT version, name, checksum, applied_at FROM schema_migrations`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int]appliedRow{}
	for rows.Next() {
		var v int
		var r appliedRow
		if err := rows.Scan(&v, &r.Name, &r.Checksum, &r.At); err != nil {
			return nil, err
		}
		out[v] = r
	}
	return out, rows.Err()
}

func verify(migs []Migration, applied map[int]appliedRow) (pending []Migration, err error) {
	known := map[int]bool{}
	for _, m := range migs {
		known[m.Version] = true
		a, ok := applied[m.Version]
		if !ok {
			pending = append(pending, m)
			continue
		}
		if a.Checksum != m.Checksum {
			return nil, fmt.Errorf("checksum migrasi %04d_%s berbeda dengan yang telah diterapkan (file migrasi tidak boleh diubah setelah diterapkan)", m.Version, m.Name)
		}
	}
	for v, a := range applied {
		if !known[v] {
			return nil, fmt.Errorf("database memiliki migrasi %04d_%s yang tidak dikenal versi aplikasi ini (aplikasi lebih lama dari skema)", v, a.Name)
		}
	}
	return pending, nil
}

func MigrateUp(ctx context.Context, db *gorm.DB) ([]Migration, error) {
	migs, err := LoadMigrations()
	if err != nil {
		return nil, err
	}
	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	conn, err := sqlDB.Conn(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock($1)`, migrationLockID); err != nil {
		return nil, err
	}
	defer conn.ExecContext(context.Background(), `SELECT pg_advisory_unlock($1)`, migrationLockID) //nolint:errcheck

	if _, err := conn.ExecContext(ctx, createMigrationsTable); err != nil {
		return nil, err
	}
	applied, err := readApplied(ctx, conn)
	if err != nil {
		return nil, err
	}
	pending, err := verify(migs, applied)
	if err != nil {
		return nil, err
	}
	var done []Migration
	for _, m := range pending {
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return done, err
		}
		if _, err := tx.ExecContext(ctx, m.SQL); err != nil {
			_ = tx.Rollback()
			return done, fmt.Errorf("migrasi %04d_%s gagal: %w", m.Version, m.Name, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)`, m.Version, m.Name, m.Checksum); err != nil {
			_ = tx.Rollback()
			return done, err
		}
		if err := tx.Commit(); err != nil {
			return done, err
		}
		done = append(done, m)
	}
	return done, nil
}

func MigrationStatusList(ctx context.Context, db *gorm.DB) ([]MigrationStatus, error) {
	migs, err := LoadMigrations()
	if err != nil {
		return nil, err
	}
	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	applied := map[int]appliedRow{}
	var exists bool
	if err := sqlDB.QueryRowContext(ctx, `SELECT to_regclass('public.schema_migrations') IS NOT NULL`).Scan(&exists); err != nil {
		return nil, err
	}
	if exists {
		if applied, err = readApplied(ctx, sqlDB); err != nil {
			return nil, err
		}
	}
	if _, err := verify(migs, applied); err != nil {
		return nil, err
	}
	out := make([]MigrationStatus, 0, len(migs))
	for _, m := range migs {
		s := MigrationStatus{Migration: m}
		if a, ok := applied[m.Version]; ok {
			at := a.At
			s.AppliedAt = &at
		}
		out = append(out, s)
	}
	return out, nil
}

func EnsureSchemaCurrent(ctx context.Context, db *gorm.DB) error {
	st, err := MigrationStatusList(ctx, db)
	if err != nil {
		return err
	}
	for _, s := range st {
		if s.AppliedAt == nil {
			return fmt.Errorf("%w: migrasi %04d_%s belum diterapkan — jalankan `go run ./cmd/migrate up` dengan role pemilik skema", ErrSchemaNotCurrent, s.Version, s.Name)
		}
	}
	return nil
}

func ApplyRolePrivileges(ctx context.Context, db *gorm.DB) error {
	migs, err := LoadMigrations()
	if err != nil {
		return err
	}
	applied := 0
	for _, m := range migs {
		if m.Name == "role_privileges_current" || (strings.HasSuffix(m.Name, "_privileges") && m.Name != "role_privileges") {
			if err := db.WithContext(ctx).Exec(m.SQL).Error; err != nil {
				return fmt.Errorf("migrasi %04d_%s: %w", m.Version, m.Name, err)
			}
			applied++
		}
	}
	if applied == 0 {
		return errors.New("migrasi role_privileges tidak ditemukan")
	}
	return nil
}
