package audit

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"sync/atomic"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/reqctx"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const auditChainLockID = 7203112601

var (
	ErrAuditChainBroken = errors.New("integritas hash audit chain terputus atau tidak valid")
	ErrAuditTampered    = errors.New("data audit log terdeteksi mengalami modifikasi")
)

func canonicalAudit(e *model.AuditLog) string {
	return strings.Join([]string{
		e.ID, e.ActorType, e.ActorID, e.ActorName, e.Action, e.Target, e.Status,
		e.IPAddress, e.UserAgent, e.DeviceID, e.Details, e.CreatedAt.UTC().Format(time.RFC3339Nano),
	}, "\x1f")
}

func ComputeHash(prevHash string, e *model.AuditLog) string {
	h := sha256.New()
	h.Write([]byte(prevHash))
	h.Write([]byte{0x1e})
	h.Write([]byte(canonicalAudit(e)))
	return hex.EncodeToString(h.Sum(nil))
}

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
		DeviceID:  trim(strings.TrimSpace(deviceID), 128),
		Details:   details,
		CreatedAt: time.Now().UTC().Truncate(time.Microsecond),
	}
	if entry.ActorID == "" {
		entry.ActorID = "UNKNOWN"
	}

	auditCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	err := db.WithContext(auditCtx).Transaction(func(tx *gorm.DB) error {
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
		failures.Add(1)
		lastFailureUnix.Store(time.Now().Unix())
		logger.GetLogger().Error("AUDIT WRITE FAILED", map[string]interface{}{
			"action":     action,
			"actor_type": actorType,
			"error":      err.Error(),
			"alert":      "AUDIT_WRITE_FAILED",
		})
	}
}

var (
	failures        atomic.Int64
	lastFailureUnix atomic.Int64
)

// FailureCount is the number of audit entries this process could not write since start.
func FailureCount() int64 { return failures.Load() }

// DegradedWithin reports whether an audit write failed during the last window. The
// readiness probe exposes it so monitoring can alert on a silently failing audit trail
// (audit S-07 / MA-04).
func DegradedWithin(window time.Duration) bool {
	last := lastFailureUnix.Load()
	return last > 0 && time.Since(time.Unix(last, 0)) <= window
}

func VerifyChain(ctx context.Context, db *gorm.DB) (int64, error) {
	if db == nil {
		return 0, errors.New("database connection is nil")
	}
	// Keyset pagination keeps memory bounded however large the trail grows (audit MA-19).
	const batch = 1000
	prev := ""
	started := false
	var lastSeq int64
	for {
		var logs []model.AuditLog
		if err := db.WithContext(ctx).Where("seq > ?", lastSeq).Order("seq ASC").Limit(batch).Find(&logs).Error; err != nil {
			return 0, err
		}
		for i := range logs {
			e := &logs[i]
			lastSeq = e.Seq
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
		if len(logs) < batch {
			return 0, nil
		}
	}
}
