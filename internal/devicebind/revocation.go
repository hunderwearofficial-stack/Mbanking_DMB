package devicebind

import (
	"context"
	"fmt"
	"os"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/pkg/logger"
)

// StartRevocationRefresh reloads the Google attestation status list periodically (the
// file is refreshed by operations). A file older than maxAge is reported once per day
// (log + audit) because revoked attestation keys would otherwise stay trusted.
func (s *Service) StartRevocationRefresh(ctx context.Context, path string, every, maxAge time.Duration) {
	if s == nil || s.opt.Android == nil || path == "" {
		return
	}
	go func() {
		t := time.NewTicker(every)
		defer t.Stop()
		var lastWarn time.Time
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
			}
			info, err := os.Stat(path)
			if err == nil {
				if revoked, lerr := LoadRevocationList(path); lerr == nil {
					s.opt.Android.setRevoked(revoked)
				} else {
					err = lerr
				}
			}
			stale := err == nil && time.Since(info.ModTime()) > maxAge
			if (err != nil || stale) && time.Since(lastWarn) > 24*time.Hour {
				lastWarn = time.Now()
				msg := "Daftar status attestation Android tidak dapat dimuat ulang"
				if stale {
					msg = fmt.Sprintf("Daftar status attestation Android kedaluwarsa (lebih dari %s)", maxAge)
				}
				logger.GetLogger().Warn(msg, map[string]interface{}{"path": path})
				if s.db != nil {
					audit.Record(context.Background(), s.db, "SYSTEM", "devicebind", "device-binding", "DEVICE_ATTESTATION_REVOCATION_STALE",
						"android", "WARNING", "", msg)
				}
			}
		}
	}()
}
