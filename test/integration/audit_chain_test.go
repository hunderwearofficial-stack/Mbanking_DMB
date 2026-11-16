package integration

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/model"
)

// TestIntegration_AuditChainDetectsTampering simulates an attacker with database-owner
// rights (the only actor able to bypass the append-only triggers) and verifies that
// audit.VerifyChain detects both a modified and a deleted row (audit DMB-016).
func TestIntegration_AuditChainDetectsTampering(t *testing.T) {
	e := setupIT(t)
	ctx := context.Background()
	for i := 0; i < 4; i++ {
		audit.Record(ctx, e.db, "SYSTEM", "it", "integration-test", "IT_EVENT", fmt.Sprintf("target-%d", i), "SUCCESS", "", "uji rantai")
	}
	if seq, err := audit.VerifyChain(ctx, e.db); err != nil {
		t.Fatalf("fresh chain must be valid, broken at seq %d: %v", seq, err)
	}

	var rows []model.AuditLog
	if err := e.db.Order("seq ASC").Find(&rows).Error; err != nil || len(rows) < 4 {
		t.Fatalf("expected >= 4 audit rows, got %d (%v)", len(rows), err)
	}

	bypass := func(stmt string, args ...interface{}) {
		t.Helper()
		for _, s := range []string{"ALTER TABLE audit_logs DISABLE TRIGGER USER", stmt, "ALTER TABLE audit_logs ENABLE TRIGGER USER"} {
			var err error
			if s == stmt {
				err = e.db.Exec(s, args...).Error
			} else {
				err = e.db.Exec(s).Error
			}
			if err != nil {
				t.Fatalf("%s: %v", s, err)
			}
		}
	}

	// 1. Silent modification of a row's content.
	bypass("UPDATE audit_logs SET details = ? WHERE seq = ?", "dimanipulasi", rows[1].Seq)
	seq, err := audit.VerifyChain(ctx, e.db)
	if !errors.Is(err, audit.ErrAuditTampered) || seq != rows[1].Seq {
		t.Fatalf("modification must be detected at seq %d, got seq %d err %v", rows[1].Seq, seq, err)
	}
	bypass("UPDATE audit_logs SET details = ? WHERE seq = ?", rows[1].Details, rows[1].Seq)
	if _, err := audit.VerifyChain(ctx, e.db); err != nil {
		t.Fatalf("restored chain must be valid again: %v", err)
	}

	// 2. Silent deletion of a row in the middle of the chain.
	bypass("DELETE FROM audit_logs WHERE seq = ?", rows[2].Seq)
	seq, err = audit.VerifyChain(ctx, e.db)
	if !errors.Is(err, audit.ErrAuditChainBroken) || seq != rows[3].Seq {
		t.Fatalf("deletion must break the chain at seq %d, got seq %d err %v", rows[3].Seq, seq, err)
	}
}
