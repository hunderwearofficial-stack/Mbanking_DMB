package app

import (
	"context"
	"net/http"
	"sync"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// CodeMaintenance is the response code of customer requests refused during maintenance.
const CodeMaintenance = "MAINTENANCE"

const (
	maintenanceCacheTTL   = 15 * time.Second
	defaultMaintenanceMsg = "Layanan Mobile DMB sedang dalam pemeliharaan berkala. Silakan coba beberapa saat lagi."
)

// maintenanceGate enforces app_configs.maintenance_mode for customer traffic (audit D-04).
// The flag is cached briefly so every request does not hit the database; a database error
// keeps the last known state (the backoffice switch must not be bypassed by an outage, and
// an outage alone must not put the service in maintenance).
type maintenanceGate struct {
	db *gorm.DB

	mu        sync.RWMutex
	refreshMu sync.Mutex
	until     time.Time
	enabled   bool
	message   string
}

func newMaintenanceGate(db *gorm.DB) *maintenanceGate { return &maintenanceGate{db: db} }

func (g *maintenanceGate) state() (bool, string) {
	g.mu.RLock()
	if g.db == nil || time.Now().Before(g.until) {
		en, msg := g.enabled, g.message
		g.mu.RUnlock()
		return en, msg
	}
	g.mu.RUnlock()

	// Single-flight refresh outside read lock with short DB timeout (L-04).
	g.refreshMu.Lock()
	defer g.refreshMu.Unlock()

	g.mu.RLock()
	if time.Now().Before(g.until) {
		en, msg := g.enabled, g.message
		g.mu.RUnlock()
		return en, msg
	}
	g.mu.RUnlock()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var cfg model.AppConfig
	err := g.db.WithContext(ctx).Select("maintenance_mode", "maintenance_message").First(&cfg).Error

	g.mu.Lock()
	defer g.mu.Unlock()
	if err != nil {
		logger.GetLogger().Warn("Status maintenance tidak dapat dibaca; memakai status terakhir", map[string]interface{}{"error": err.Error()})
		g.until = time.Now().Add(maintenanceCacheTTL)
		return g.enabled, g.message
	}
	g.enabled, g.message = cfg.MaintenanceMode, cfg.MaintenanceMessage
	g.until = time.Now().Add(maintenanceCacheTTL)
	return g.enabled, g.message
}

// Middleware refuses the request with 503 MAINTENANCE while maintenance mode is on.
func (g *maintenanceGate) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if on, msg := g.state(); on {
			if msg == "" {
				msg = defaultMaintenanceMsg
			}
			response.Error(c, http.StatusServiceUnavailable, msg, CodeMaintenance, gin.H{"maintenance": true})
			c.Abort()
			return
		}
		c.Next()
	}
}
