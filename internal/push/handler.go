package push

import (
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

// Handler exposes customer device endpoints and the back-office notification module.
type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func writeErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrValidation), errors.Is(err, ErrInvalidCredential):
		response.ErrorWithCode(c, http.StatusUnprocessableEntity, response.CodeBadRequest, err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, ErrMakerChecker):
		response.ErrorWithCode(c, http.StatusForbidden, response.CodeUnauthorized, err.Error(), nil)
	case errors.Is(err, ErrState), errors.Is(err, ErrDisabled):
		response.ErrorWithCode(c, http.StatusConflict, "07", err.Error(), nil)
	default:
		logger.GetLogger().Error("Kesalahan modul notifikasi push", map[string]interface{}{"error": err.Error()})
		response.ErrorWithCode(c, http.StatusServiceUnavailable, response.CodeInternalError, "Layanan sedang tidak tersedia, silakan coba beberapa saat lagi", nil)
	}
}

// ---- customer (authenticated, device-bound) ---------------------------------------------

type tokenRequest struct {
	FCMToken string `json:"fcm_token" binding:"required"`
	Platform string `json:"platform"`
}

// RegisterToken handles POST /notifications/fcm-token.
func (h *Handler) RegisterToken(c *gin.Context) {
	var req tokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "fcm_token wajib diisi", nil)
		return
	}
	if err := h.svc.RegisterDevice(c.Request.Context(), c.GetString(middleware.CtxUserID), c.GetString(middleware.CtxDeviceID), req.FCMToken, req.Platform); err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Perangkat terdaftar untuk notifikasi", gin.H{"registered": true})
}

// UnregisterToken handles DELETE /notifications/fcm-token.
func (h *Handler) UnregisterToken(c *gin.Context) {
	if err := h.svc.UnregisterDevice(c.Request.Context(), c.GetString(middleware.CtxUserID), c.GetString(middleware.CtxDeviceID), "LOGOUT"); err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Perangkat dilepas dari notifikasi", gin.H{"registered": false})
}

// DetachOnLogout is placed before the logout handler: the device stops receiving pushes
// even if the app could not call UnregisterToken.
func (h *Handler) DetachOnLogout(c *gin.Context) {
	if err := h.svc.UnregisterDevice(c.Request.Context(), c.GetString(middleware.CtxUserID), c.GetString(middleware.CtxDeviceID), "LOGOUT"); err != nil {
		logger.GetLogger().Warn("Gagal melepas perangkat push saat logout", map[string]interface{}{"error": err.Error()})
	}
	c.Next()
}

// Opened handles POST /notifications/opened (the app reports a tapped notification).
func (h *Handler) Opened(c *gin.Context) {
	var req struct {
		Ref string `json:"ref" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "ref wajib diisi", nil)
		return
	}
	if err := h.svc.MarkOpened(c.Request.Context(), c.GetString(middleware.CtxUserID), strings.TrimSpace(req.Ref)); err != nil && !errors.Is(err, ErrNotFound) {
		writeErr(c, err)
		return
	}
	response.Success(c, "OK", gin.H{"recorded": true})
}

// ---- back office: Firebase integration ---------------------------------------------------

func (h *Handler) view(c *gin.Context, v *SettingsView, err error, msg string) {
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, msg, v)
}

// GetSettings handles GET /admin/push/settings.
func (h *Handler) GetSettings(c *gin.Context) {
	v, err := h.svc.GetSettings(c.Request.Context())
	h.view(c, v, err, "Status integrasi Firebase")
}

// UploadCredential handles POST /admin/push/credential (multipart "file": the Firebase
// service-account JSON). The content is validated against Google and stored encrypted;
// it is never returned by any endpoint.
func (h *Handler) UploadCredential(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)
	fh, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "Berkas service account (.json) wajib diunggah", nil)
		return
	}
	f, err := fh.Open()
	if err != nil {
		response.BadRequest(c, "Berkas tidak dapat dibaca", nil)
		return
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, 32*1024))
	if err != nil {
		response.BadRequest(c, "Berkas tidak dapat dibaca", nil)
		return
	}
	v, err := h.svc.ReplaceCredential(c.Request.Context(), raw)
	h.view(c, v, err, "Credential Firebase tervalidasi dan disimpan terenkripsi. Aktifkan integrasi untuk mulai mengirim.")
}

// Test handles POST /admin/push/test.
func (h *Handler) Test(c *gin.Context) {
	v, err := h.svc.TestConnection(c.Request.Context())
	h.view(c, v, err, "Uji koneksi selesai")
}

// SetEnabled handles PUT /admin/push/settings.
func (h *Handler) SetEnabled(c *gin.Context) {
	var req struct {
		Enabled *bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Enabled == nil {
		response.BadRequest(c, "enabled wajib diisi", nil)
		return
	}
	v, err := h.svc.SetEnabled(c.Request.Context(), *req.Enabled)
	h.view(c, v, err, "Pengaturan disimpan")
}

// ---- back office: notifications ----------------------------------------------------------

func (h *Handler) campaign(c *gin.Context, v *Campaign, err error, msg string) {
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, msg, v)
}

// ListCampaigns handles GET /admin/push/campaigns.
func (h *Handler) ListCampaigns(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	out, err := h.svc.ListCampaigns(c.Request.Context(), limit)
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Riwayat notifikasi", out)
}

// CreateCampaign handles POST /admin/push/campaigns.
func (h *Handler) CreateCampaign(c *gin.Context) {
	var in CampaignInput
	if err := c.ShouldBindJSON(&in); err != nil {
		response.BadRequest(c, "Format notifikasi tidak valid", nil)
		return
	}
	v, err := h.svc.CreateCampaign(c.Request.Context(), in)
	h.campaign(c, v, err, "Draf notifikasi dibuat")
}

// Submit handles POST /admin/push/campaigns/:id/submit.
func (h *Handler) Submit(c *gin.Context) {
	v, err := h.svc.SubmitCampaign(c.Request.Context(), c.Param("id"))
	h.campaign(c, v, err, "Diajukan untuk persetujuan")
}

// Approve handles POST /admin/push/campaigns/:id/approve.
func (h *Handler) Approve(c *gin.Context) {
	v, err := h.svc.ApproveCampaign(c.Request.Context(), c.Param("id"))
	h.campaign(c, v, err, "Disetujui. Pengiriman sedang diproses.")
}

// Reject handles POST /admin/push/campaigns/:id/reject.
func (h *Handler) Reject(c *gin.Context) {
	var req struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&req)
	v, err := h.svc.RejectCampaign(c.Request.Context(), c.Param("id"), req.Reason)
	h.campaign(c, v, err, "Notifikasi ditolak")
}

// Deliveries handles GET /admin/push/campaigns/:id/deliveries.
func (h *Handler) Deliveries(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	out, err := h.svc.CampaignDeliveries(c.Request.Context(), c.Param("id"), limit)
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Detail pengiriman", out)
}
