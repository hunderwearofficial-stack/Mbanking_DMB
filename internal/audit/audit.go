// Package audit menulis dan memverifikasi audit trail append-only ber-hash-chain
// (audit DMB-016). Tabel audit_logs juga dilindungi trigger DB (pkg/database).
package audit

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/reqctx"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// auditChainLockID serializes audit inserts so the hash chain is linear.
const auditChainLockID = 7203112601

var (
	ErrAuditChainBroken = errors.New("integritas hash audit chain terputus atau tidak valid")
	ErrAuditTampered    = errors.New("data audit log terdeteksi mengalami modifikasi")
)

// canonicalAudit returns the canonical string hashed into the chain.
func canonicalAudit(e *model.AuditLog) string {
	return strings.Join([]string{
		e.ID, e.ActorType, e.ActorID, e.ActorName, e.Action, e.Target, e.Status,
		e.IPAddress, e.UserAgent, e.DeviceID, e.Details, e.CreatedAt.UTC().Format(time.RFC3339Nano),
	}, "\x1f")
}

// ComputeHash returns SHA-256(prevHash || canonical entry).
func ComputeHash(prevHash string, e *model.AuditLog) string {
	h := sha256.New()
	h.Write([]byte(prevHash))
	h.Write([]byte{0x1e})
	h.Write([]byte(canonicalAudit(e)))
	return hex.EncodeToString(h.Sum(nil))
}

// Record appends an audit entry (audit DMB-016):
//   - client IP / user agent are extracted from the verified request context;
//   - for ADMIN actions the authenticated officer (from context) is recorded,
//     never a generic placeholder;
//   - device IDs are recorded as received — no substitution with fabricated values;
//   - entries are hash-chained and the table is protected by DB triggers against UPDATE/DELETE.
func Record(ctx context.Context, db *gorm.DB, actorType, actorID, actorName, action, target, status, deviceID, details string) {
	if db == nil {
		return
	}
	meta := reqctx.MetaFrom(ctx)
	if actorType == "ADMIN" {
		if a, ok := reqctx.AdminFrom(ctx); ok {
			actorID = a.ID
			actorName = a.Username + " (" + a.Role + ")"
		}
	}
	trim := func(s string, n int) string {
		if len(s) > n {
			return s[:n]
		}
		return s
	}
	entry := model.AuditLog{
		ActorType: trim(actorType, 20),
		ActorID:   trim(actorID, 60),
		ActorName: trim(actorName, 100),
		Action:    trim(action, 60),
		Target:    trim(target, 100),
		Status:    trim(status, 20),
		IPAddress: trim(meta.ClientIP, 50),
		UserAgent: trim(meta.UserAgent, 255),
		DeviceID:  trim(strings.TrimSpace(deviceID), 120),
		Details:   details,
		// Truncated to the DB timestamp precision so the hash can be recomputed on verification.
		CreatedAt: time.Now().UTC().Truncate(time.Microsecond),
	}
	if entry.ActorID == "" {
		entry.ActorID = "UNKNOWN"
	}

	err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if tx.Dialector.Name() == "postgres" {
			if err := tx.Exec("SELECT pg_advisory_xact_lock(?)", auditChainLockID).Error; err != nil {
				return err
			}
		}
		var last model.AuditLog
		prev := ""
		if err := tx.Select("hash").Order("seq DESC").Limit(1).Find(&last).Error; err == nil {
			prev = last.Hash
		}
		if entry.ID == "" {
			entry.ID = uuid.NewString()
		}
		entry.PrevHash = prev
		entry.Hash = ComputeHash(prev, &entry)
		return tx.Omit("Seq").Create(&entry).Error
	})
	if err != nil {
		// Audit failures must be visible to operations (never silently dropped).
		logger.GetLogger().Error("AUDIT WRITE FAILED", map[string]interface{}{
			"action":     action,
			"actor_type": actorType,
			"error":      err.Error(),
		})
	}
}

// VerifyChain walks audit_logs in seq order and verifies the hash chain.
//
// Rows written before the chain existed (legacy rows with an empty hash, e.g. after an
// upgrade from an older schema) are tolerated only as a prefix; once the chain has
// started, every row must carry a valid PrevHash/Hash.
//
// It returns the seq of the first offending row (0 when the chain is intact), and
// ErrAuditChainBroken / ErrAuditTampered describing the failure.
func VerifyChain(ctx context.Context, db *gorm.DB) (int64, error) {
	if db == nil {
		return 0, errors.New("database connection is nil")
	}
	var logs []model.AuditLog
	if err := db.WithContext(ctx).Order("seq ASC").Find(&logs).Error; err != nil {
		return 0, err
	}
	prev := ""
	started := false
	for i := range logs {
		e := &logs[i]
		if e.Hash == "" {
			if started {
				return e.Seq, ErrAuditChainBroken
			}
			continue // legacy prefix
		}
		started = true
		if e.PrevHash != prev {
			return e.Seq, ErrAuditChainBroken
		}
		if ComputeHash(prev, e) != e.Hash {
			return e.Seq, ErrAuditTampered
		}
		prev = e.Hash
	}
	return 0, nil
}
