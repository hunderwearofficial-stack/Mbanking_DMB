package http

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type CBSOpsHandler struct {
	cbs cbsprovider.CBSProvider
	db  *gorm.DB
}

func NewCBSOpsHandler(cbs cbsprovider.CBSProvider, db ...*gorm.DB) *CBSOpsHandler {
	var d *gorm.DB
	if len(db) > 0 {
		d = db[0]
	}
	return &CBSOpsHandler{cbs: cbs, db: d}
}

func (h *CBSOpsHandler) Health(c *gin.Context) {
	status, err := h.cbs.Ping(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusBadGateway, "Layanan perbankan inti belum dapat dihubungi", "CBS_UNREACHABLE", nil)
		return
	}
	response.Success(c, "Koneksi layanan perbankan inti aktif dan sehat", status)
}

func (h *CBSOpsHandler) RefreshToken(c *gin.Context) {
	if err := h.cbs.RefreshToken(c.Request.Context()); err != nil {
		audit.Record(c.Request.Context(), h.db, "ADMIN", "", "", "CBS_REFRESH_TOKEN_FAILED", "cbs-oauth", "WARNING", "WEB-BACKOFFICE", "Pembaruan sesi otorisasi layanan perbankan gagal")
		response.Error(c, http.StatusBadGateway, "Pembaruan sesi otorisasi layanan perbankan gagal", "CBS_TOKEN_REFRESH_FAILED", nil)
		return
	}
	audit.Record(c.Request.Context(), h.db, "ADMIN", "", "", "CBS_REFRESH_TOKEN", "cbs-oauth", "SUCCESS", "WEB-BACKOFFICE", "Sesi otorisasi layanan perbankan berhasil diperbarui")
	response.Success(c, "Sesi otorisasi layanan perbankan berhasil diperbarui", nil)
}

type cbsWebhookNotificationReq struct {
	CIF      string `json:"cif" binding:"required"`
	Title    string `json:"title" binding:"required"`
	Body     string `json:"body"`
	Message  string `json:"message"`
	Category string `json:"category"`
}

// NotifyWebhook menerima trigger notifikasi dari Core Banking System (CBS)
// berdasarkan CIF nasabah, menyimpannya ke riwayat notifikasi aplikasi, dan
// mengirim push notification melalui FCM tanpa mengekspos FCM token ke CBS.
func (h *CBSOpsHandler) NotifyWebhook(webhookSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if strings.TrimSpace(webhookSecret) == "" {
			response.Error(c, http.StatusServiceUnavailable, "Webhook notifikasi CBS belum dikonfigurasi", "CBS_WEBHOOK_DISABLED", nil)
			return
		}
		provided := strings.TrimSpace(c.GetHeader("X-CBS-Webhook-Key"))
		if provided == "" {
			if auth := strings.TrimSpace(c.GetHeader("Authorization")); strings.HasPrefix(strings.ToLower(auth), "bearer ") {
				provided = strings.TrimSpace(auth[7:])
			}
		}
		if len(provided) == 0 || subtle.ConstantTimeCompare([]byte(provided), []byte(webhookSecret)) != 1 {
			audit.Record(c.Request.Context(), h.db, "SYSTEM", "cbs-webhook", "cbs-webhook", "CBS_WEBHOOK_UNAUTHORIZED", "notifications", "WARNING", c.ClientIP(), "Kunci webhook CBS tidak valid")
			response.Error(c, http.StatusUnauthorized, "Kunci otorisasi webhook tidak valid", "UNAUTHORIZED", nil)
			return
		}

		var req cbsWebhookNotificationReq
		if err := c.ShouldBindJSON(&req); err != nil {
			response.Error(c, http.StatusBadRequest, "Format JSON tidak valid (wajib: cif, title, body/message)", "VALIDATION_ERROR", nil)
			return
		}

		cif := strings.TrimSpace(req.CIF)
		title := strings.TrimSpace(req.Title)
		body := strings.TrimSpace(req.Body)
		if body == "" {
			body = strings.TrimSpace(req.Message)
		}
		if cif == "" || len(cif) > 32 || title == "" || len(title) > 120 || body == "" || len(body) > 1000 {
			response.Error(c, http.StatusBadRequest, "Nilai cif, title (maks 120), dan body/message (maks 1000) wajib diisi", "VALIDATION_ERROR", nil)
			return
		}

		category := strings.ToUpper(strings.TrimSpace(req.Category))
		switch category {
		case "", notification.CategoryTransaction:
			category = notification.CategoryTransaction
		case notification.CategorySecurity, notification.CategoryInfo, notification.CategoryPromo:
		default:
			response.Error(c, http.StatusBadRequest, "Kategori harus TRANSACTION, SECURITY, INFO, atau PROMO", "VALIDATION_ERROR", nil)
			return
		}

		if h.db == nil {
			response.Error(c, http.StatusServiceUnavailable, "Database tidak tersedia", "SERVICE_UNAVAILABLE", nil)
			return
		}

		var user model.User
		if err := h.db.WithContext(c.Request.Context()).Select("id, cif, is_active").Where("cif = ?", cif).First(&user).Error; err != nil {
			response.Error(c, http.StatusNotFound, "Nasabah dengan CIF tersebut belum terdaftar di Mobile DMB", "CUSTOMER_NOT_FOUND", nil)
			return
		}
		if !user.IsActive {
			response.Error(c, http.StatusForbidden, "Akun nasabah sedang nonaktif", "CUSTOMER_INACTIVE", nil)
			return
		}

		notification.CreateAndPush(c.Request.Context(), h.db, user.ID, title, body, category)
		audit.Record(c.Request.Context(), h.db, "SYSTEM", "cbs-webhook", "cbs-webhook", "CBS_WEBHOOK_NOTIFICATION", cif, "SUCCESS", c.ClientIP(), "Notifikasi CBS dikirim (kategori "+category+")")

		response.Success(c, "Notifikasi berhasil diproses", gin.H{
			"cif":      user.CIF,
			"user_id":  user.ID,
			"category": category,
		})
	}
}
