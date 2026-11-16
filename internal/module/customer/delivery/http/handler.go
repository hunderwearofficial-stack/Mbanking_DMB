// Package http berisi handler REST fitur layanan nasabah. Semua route berada di
// belakang middleware autentikasi nasabah; user_id selalu diambil dari konteks token.
package http

import (
	"errors"
	"net/http"
	"strconv"

	"mbanking-bpr/internal/module/customer/service"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type CustomerHandler struct {
	svc service.CustomerService
}

func NewCustomerHandler(svc service.CustomerService) *CustomerHandler {
	return &CustomerHandler{svc: svc}
}

// fail writes a safe error response: validation errors are shown to the user;
// anything else is logged and replaced by a generic message (audit DMB-024).
func fail(c *gin.Context, err error, generic string) {
	if errors.Is(err, service.ErrValidation) || errors.Is(err, service.ErrCustomerNotFound) {
		response.Error(c, http.StatusBadRequest, err.Error(), "01", nil)
		return
	}
	logger.GetLogger().Error(generic, map[string]interface{}{"error": err.Error(), "path": c.FullPath()})
	response.Error(c, http.StatusInternalServerError, generic, "99", nil)
}

func userID(c *gin.Context) string { return c.GetString(middleware.CtxUserID) }

// ---- Notifikasi ----

func (h *CustomerHandler) ListNotifications(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "30"))
	notifs, err := h.svc.ListNotifications(c.Request.Context(), userID(c), limit)
	if err != nil {
		fail(c, err, "Gagal memuat notifikasi")
		return
	}
	response.Success(c, "Daftar notifikasi berhasil dimuat", notifs)
}

func (h *CustomerHandler) MarkNotificationsRead(c *gin.Context) {
	if err := h.svc.MarkNotificationsRead(c.Request.Context(), userID(c)); err != nil {
		fail(c, err, "Gagal memperbarui status notifikasi")
		return
	}
	response.Success(c, "Seluruh notifikasi ditandai telah dibaca", gin.H{"read": true})
}

// ---- Rekening favorit ----

func (h *CustomerHandler) ListBeneficiaries(c *gin.Context) {
	list, err := h.svc.ListBeneficiaries(c.Request.Context(), userID(c))
	if err != nil {
		fail(c, err, "Gagal memuat daftar rekening favorit")
		return
	}
	response.Success(c, "Daftar rekening tujuan favorit berhasil dimuat", list)
}

func (h *CustomerHandler) SaveBeneficiary(c *gin.Context) {
	var in service.BeneficiaryInput
	if err := c.ShouldBindJSON(&in); err != nil {
		response.Error(c, http.StatusBadRequest, "Data rekening tujuan tidak valid", "01", nil)
		return
	}
	b, err := h.svc.SaveBeneficiary(c.Request.Context(), userID(c), in)
	if err != nil {
		fail(c, err, "Gagal menyimpan rekening favorit")
		return
	}
	response.Success(c, "Rekening tujuan berhasil disimpan ke daftar favorit", b)
}

func (h *CustomerHandler) DeleteBeneficiary(c *gin.Context) {
	if err := h.svc.DeleteBeneficiary(c.Request.Context(), c.Param("id"), userID(c)); err != nil {
		fail(c, err, "Gagal menghapus rekening favorit")
		return
	}
	response.Success(c, "Rekening favorit berhasil dihapus", gin.H{"deleted": true})
}

// ---- Pengajuan produk ----

func (h *CustomerHandler) CreateProductApplication(c *gin.Context) {
	var in service.ProductApplicationInput
	if err := c.ShouldBindJSON(&in); err != nil {
		response.Error(c, http.StatusBadRequest, "Data pengajuan produk tidak lengkap", "01", nil)
		return
	}
	app, err := h.svc.CreateProductApplication(c.Request.Context(), userID(c), in)
	if err != nil {
		fail(c, err, "Gagal mengirim pengajuan")
		return
	}
	response.Success(c, "Pengajuan berhasil dikirim! Petugas Bank DMB akan segera menindaklanjuti.", app)
}

func (h *CustomerHandler) ListProductApplications(c *gin.Context) {
	list, err := h.svc.ListProductApplications(c.Request.Context(), userID(c))
	if err != nil {
		fail(c, err, "Gagal memuat riwayat pengajuan")
		return
	}
	response.Success(c, "Riwayat pengajuan berhasil dimuat", list)
}
