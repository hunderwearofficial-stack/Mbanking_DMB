package mobilecontent

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func writeErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalid):
		response.ErrorWithCode(c, http.StatusUnprocessableEntity, response.CodeBadRequest, err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, ErrMakerChecker):
		response.ErrorWithCode(c, http.StatusForbidden, response.CodeUnauthorized, err.Error(), nil)
	case errors.Is(err, ErrState):
		response.ErrorWithCode(c, http.StatusConflict, "07", err.Error(), nil)
	default:
		logger.GetLogger().Error("Kesalahan modul konten aplikasi", map[string]interface{}{"error": err.Error()})
		response.ErrorWithCode(c, http.StatusServiceUnavailable, response.CodeInternalError, "Layanan sedang tidak tersedia, silakan coba beberapa saat lagi", nil)
	}
}

func (h *Handler) Public(c *gin.Context) {
	vals, ver, at, err := h.svc.Live(c.Request.Context())
	if err != nil {
		writeErr(c, err)
		return
	}
	etag := `"content-v` + strconv.Itoa(ver) + `"`
	c.Header("ETag", etag)
	c.Header("Cache-Control", "no-cache")
	if strings.Contains(c.GetHeader("If-None-Match"), etag) {
		c.Status(http.StatusNotModified)
		return
	}
	data := gin.H{"version": ver, "items": vals}
	if at != nil {
		data["published_at"] = at.Format(time.RFC3339)
	}
	response.Success(c, "Konten aplikasi", data)
}

func (h *Handler) Schema(c *gin.Context) {
	response.Success(c, "Struktur konten aplikasi", gin.H{"pages": Pages, "fields": Fields})
}

func (h *Handler) Current(c *gin.Context) {
	st, err := h.svc.Current(c.Request.Context())
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Konten aplikasi", st)
}

func (h *Handler) History(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	out, err := h.svc.History(c.Request.Context(), limit)
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Riwayat konten aplikasi", out)
}

func (h *Handler) SaveDraft(c *gin.Context) {
	var req struct {
		Values Values `json:"values"`
		Note   string `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format konten tidak valid", nil)
		return
	}
	v, err := h.svc.SaveDraft(c.Request.Context(), req.Values, req.Note, nil)
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Draf disimpan (belum tampil di aplikasi)", v)
}

func (h *Handler) action(c *gin.Context, f func() (*View, error), msg string) {
	v, err := f()
	if err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, msg, v)
}

func (h *Handler) Submit(c *gin.Context) {
	h.action(c, func() (*View, error) { return h.svc.Submit(c.Request.Context(), c.Param("id")) }, "Diajukan untuk persetujuan")
}

func (h *Handler) Approve(c *gin.Context) {
	h.action(c, func() (*View, error) { return h.svc.Approve(c.Request.Context(), c.Param("id")) }, "Konten dipublikasikan")
}

func (h *Handler) Reject(c *gin.Context) {
	var req struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&req)
	h.action(c, func() (*View, error) { return h.svc.Reject(c.Request.Context(), c.Param("id"), req.Reason) }, "Dikembalikan ke draf")
}

func (h *Handler) Rollback(c *gin.Context) {
	h.action(c, func() (*View, error) { return h.svc.Rollback(c.Request.Context(), c.Param("id")) }, "Isi revisi lama disalin ke draf")
}

func (h *Handler) Discard(c *gin.Context) {
	if err := h.svc.DiscardDraft(c.Request.Context(), c.Param("id")); err != nil {
		writeErr(c, err)
		return
	}
	response.Success(c, "Draf dibuang", gin.H{"discarded": true})
}
