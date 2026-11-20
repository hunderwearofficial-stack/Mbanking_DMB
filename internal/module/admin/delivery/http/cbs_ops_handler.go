package http

import (
	"net/http"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
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
