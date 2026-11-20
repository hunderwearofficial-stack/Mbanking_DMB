package audit

import (
	"testing"
	"time"

	"mbanking-bpr/internal/model"
)

func TestComputeHashDeterministic(t *testing.T) {
	fixedTime := time.Date(2026, 11, 13, 10, 0, 0, 0, time.UTC)
	entry := &model.AuditLog{
		ID:        "id-123",
		ActorType: "ADMIN",
		ActorID:   "adm-1",
		ActorName: "Officer",
		Action:    "PASSWORD_RESET",
		Target:    "usr-99",
		Status:    "SUCCESS",
		IPAddress: "192.168.1.1",
		UserAgent: "Mozilla/5.0",
		DeviceID:  "device-abc",
		Details:   "Reset password via CS",
		CreatedAt: fixedTime,
	}

	h1 := ComputeHash("prev-hash-abc", entry)
	h2 := ComputeHash("prev-hash-abc", entry)
	if h1 != h2 {
		t.Fatalf("ComputeHash is not deterministic: %s != %s", h1, h2)
	}

	entry.Details = "Reset password via CS (modified)"
	h3 := ComputeHash("prev-hash-abc", entry)
	if h1 == h3 {
		t.Fatalf("ComputeHash collision: hash didn't change when details changed")
	}

	entry.Details = "Reset password via CS"
	entry.Status = "FAILED"
	h4 := ComputeHash("prev-hash-abc", entry)
	if h1 == h4 {
		t.Fatalf("ComputeHash collision: hash didn't change when status changed")
	}

	entry.Status = "SUCCESS"
	h5 := ComputeHash("different-prev-hash", entry)
	if h1 == h5 {
		t.Fatalf("ComputeHash collision: hash didn't change when prevHash changed")
	}
}

func TestHashChainDetectsTampering(t *testing.T) {
	fixedTime := time.Date(2026, 11, 13, 10, 0, 0, 0, time.UTC)

	logs := []model.AuditLog{
		{
			ID: "log-1", ActorType: "ADMIN", ActorID: "adm-1", ActorName: "Admin Satu",
			Action: "ADMIN_LOGIN", Target: "adm-1", Status: "SUCCESS",
			IPAddress: "127.0.0.1", UserAgent: "AdminWeb/1.0", DeviceID: "WEB",
			Details: "Login console", CreatedAt: fixedTime,
		},
		{
			ID: "log-2", ActorType: "NASABAH", ActorID: "usr-1", ActorName: "Nasabah Uji",
			Action: "CHANGE_PIN_SUCCESS", Target: "0000000000000001", Status: "SUCCESS",
			IPAddress: "192.168.1.50", UserAgent: "DMBMobile/1.0", DeviceID: "dev-uuid-1",
			Details: "Ganti PIN transaksi", CreatedAt: fixedTime.Add(1 * time.Minute),
		},
		{
			ID: "log-3", ActorType: "NASABAH", ActorID: "usr-1", ActorName: "Nasabah Uji",
			Action: "CHANGE_PIN", Target: "usr-1", Status: "SUCCESS",
			IPAddress: "192.168.1.50", UserAgent: "DMBMobile/1.0", DeviceID: "dev-uuid-1",
			Details: "Ganti PIN Transaksi", CreatedAt: fixedTime.Add(2 * time.Minute),
		},
	}

	prev := ""
	for i := range logs {
		logs[i].PrevHash = prev
		logs[i].Hash = ComputeHash(prev, &logs[i])
		prev = logs[i].Hash
	}

	validateChain := func(entries []model.AuditLog) (bool, int) {
		p := ""
		for idx, e := range entries {
			if e.PrevHash != p {
				return false, idx
			}
			if e.Hash != ComputeHash(p, &e) {
				return false, idx
			}
			p = e.Hash
		}
		return true, len(entries)
	}

	ok, count := validateChain(logs)
	if !ok || count != 3 {
		t.Fatalf("expected valid chain of 3 entries, got ok=%v, count=%d", ok, count)
	}

	logs[1].Details = "Tampered audit detail"
	ok, brokenIdx := validateChain(logs)
	if ok || brokenIdx != 1 {
		t.Fatalf("expected tampering detected at index 1, got ok=%v, brokenIdx=%d", ok, brokenIdx)
	}
}
