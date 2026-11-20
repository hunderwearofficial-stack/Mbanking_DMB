package legaldoc

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

const (
	CodeConsentRequired  = "10"
	CodeTermsUnavailable = "11"
	CodeVersionNotActive = "12"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

type ActiveMeta struct {
	DocumentID         string     `json:"document_id"`
	Title              string     `json:"title"`
	VersionID          string     `json:"version_id"`
	VersionNumber      int        `json:"version_number"`
	DocumentNumber     *string    `json:"document_number"`
	PublishedAt        *time.Time `json:"published_at"`
	EffectiveFrom      *time.Time `json:"effective_from"`
	PDFSHA256          string     `json:"pdf_sha256"`
	PDFURL             string     `json:"pdf_url"`
	ConsentHeading     string     `json:"consent_heading"`
	ConsentInstruction string     `json:"consent_instruction"`
	ConsentStatements  []string   `json:"consent_statements"`
}

func activeMeta(v *Version, c *Content) ActiveMeta {
	m := ActiveMeta{
		DocumentID: v.DocumentID, Title: "Syarat dan Ketentuan Layanan Mobile Banking",
		VersionID: v.ID, VersionNumber: v.VersionNumber, DocumentNumber: v.DocumentNumber,
		PublishedAt: v.PublishedAt, EffectiveFrom: v.EffectiveFrom,
		PDFURL:             "/api/v1/terms/versions/" + v.ID + "/pdf",
		ConsentHeading:     c.ConsentHeading,
		ConsentInstruction: c.ConsentInstruction,
		ConsentStatements:  c.ConsentStatements,
	}
	if v.PDFSHA256 != nil {
		m.PDFSHA256 = *v.PDFSHA256
	}
	return m
}

func WriteError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrNoActiveVersion):
		response.ErrorWithCode(c, http.StatusServiceUnavailable, CodeTermsUnavailable, ErrNoActiveVersion.Error(), nil)
	case errors.Is(err, ErrConsentRequired), errors.Is(err, ErrInvalidAcceptance):
		response.ErrorWithCode(c, http.StatusForbidden, CodeConsentRequired, err.Error(), gin.H{"action": "ACCEPT_TERMS"})
	case errors.Is(err, ErrVersionNotActive):
		response.ErrorWithCode(c, http.StatusConflict, CodeVersionNotActive, err.Error(), gin.H{"action": "RELOAD_TERMS"})
	case errors.Is(err, ErrNotFound), errors.Is(err, ErrFileNotFound):
		response.NotFound(c, ErrNotFound.Error())
	case errors.Is(err, ErrMakerChecker):
		response.ErrorWithCode(c, http.StatusForbidden, response.CodeUnauthorized, err.Error(), nil)
	case errors.Is(err, ErrInvalidState):
		response.ErrorWithCode(c, http.StatusConflict, "07", err.Error(), nil)
	case errors.Is(err, ErrInvalidContent), errors.Is(err, ErrInvalidFile):
		response.ErrorWithCode(c, http.StatusUnprocessableEntity, response.CodeBadRequest, err.Error(), nil)
	default:
		logger.GetLogger().Error("Kesalahan modul Syarat dan Ketentuan", map[string]interface{}{"error": err.Error()})
		response.ErrorWithCode(c, http.StatusServiceUnavailable, response.CodeInternalError, "Layanan sedang tidak tersedia, silakan coba beberapa saat lagi", nil)
	}
}

func (h *Handler) Active(c *gin.Context) {
	v, content, err := h.svc.Active(c.Request.Context())
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Syarat dan Ketentuan yang berlaku", activeMeta(v, content))
}

func writePDF(c *gin.Context, v *Version, data []byte, sha string, public bool) {
	etag := `"` + sha + `"`
	if public {
		c.Header("Cache-Control", "public, max-age=86400, immutable")
		if strings.Contains(c.GetHeader("If-None-Match"), sha) {
			c.Header("ETag", etag)
			c.Status(http.StatusNotModified)
			return
		}
	} else {
		c.Header("Cache-Control", "no-store")
	}
	c.Header("ETag", etag)
	c.Header("X-Document-Version", strconv.Itoa(v.VersionNumber))
	c.Header("X-Content-SHA256", sha)
	c.Header("Content-Disposition", fmt.Sprintf(`inline; filename="SK-Mobile-Banking-v%d.pdf"`, v.VersionNumber))
	c.Data(http.StatusOK, "application/pdf", data)
}

func (h *Handler) PublicPDF(c *gin.Context) {
	v, data, err := h.svc.PublishedPDF(c.Request.Context(), c.Param("id"))
	if err != nil {
		WriteError(c, err)
		return
	}
	writePDF(c, v, data, *v.PDFSHA256, true)
}

type acceptRequest struct {
	VersionID string `json:"version_id" binding:"required"`
	Accepted  bool   `json:"accepted"`
}

func (h *Handler) AcceptPreLogin(c *gin.Context) {
	var req acceptRequest
	if err := c.ShouldBindJSON(&req); err != nil || !req.Accepted {
		response.BadRequest(c, "Persetujuan wajib dinyatakan secara eksplisit untuk versi dokumen yang dibaca", nil)
		return
	}
	dev := strings.TrimSpace(c.GetHeader(middleware.HeaderDeviceID))
	a, err := h.svc.AcceptPreLogin(c.Request.Context(), strings.TrimSpace(req.VersionID), dev,
		ClientMeta{IP: c.ClientIP(), UserAgent: c.Request.UserAgent()})
	if err != nil {
		WriteError(c, err)
		return
	}
	c.JSON(http.StatusCreated, response.StandardBankingResponse{
		Success: true, ResponseCode: response.CodeSuccess, Message: "Persetujuan Syarat dan Ketentuan tercatat",
		Data:      gin.H{"acceptance_id": a.ID, "version_id": a.VersionID, "version_number": a.VersionNumber, "accepted_at": a.AcceptedAt},
		Timestamp: time.Now().Format(time.RFC3339),
	})
}

func (h *Handler) Status(c *gin.Context) {
	ok, active, acc, err := h.svc.UserConsent(c.Request.Context(), c.GetString(middleware.CtxUserID))
	if err != nil {
		WriteError(c, err)
		return
	}
	data := gin.H{"accepted": ok, "required_version_id": active.ID, "required_version_number": active.VersionNumber}
	if acc != nil {
		data["accepted_at"] = acc.AcceptedAt
	}
	response.Success(c, "Status persetujuan Syarat dan Ketentuan", data)
}

func actor(c *gin.Context) (Actor, bool) {
	a, ok := ActorFromContext(c.Request.Context())
	if !ok {
		response.Unauthorized(c, response.CodeUnauthorized, "Sesi petugas tidak valid")
	}
	return a, ok
}

func (h *Handler) ListVersions(c *gin.Context) {
	vs, err := h.svc.ListVersions(c.Request.Context())
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Daftar versi Syarat dan Ketentuan", vs)
}

func (h *Handler) GetVersion(c *gin.Context) {
	v, err := h.svc.GetVersion(c.Request.Context(), c.Param("id"))
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Detail versi", v)
}

type draftRequest struct {
	BaseVersionID  string   `json:"base_version_id"`
	Content        *Content `json:"content"`
	ChangeSummary  string   `json:"change_summary"`
	DocumentNumber string   `json:"document_number"`
}

func (r *draftRequest) input() (DraftInput, error) {
	in := DraftInput{BaseVersionID: strings.TrimSpace(r.BaseVersionID), ChangeSummary: r.ChangeSummary, DocumentNumber: r.DocumentNumber}
	if r.Content != nil {
		raw, err := r.Content.CanonicalJSON()
		if err != nil {
			return in, err
		}
		c, err := ParseContent(raw)
		if err != nil {
			return in, err
		}
		in.Content = c
	}
	return in, nil
}

func (h *Handler) CreateDraft(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	var req draftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data draf tidak valid", nil)
		return
	}
	in, err := req.input()
	if err != nil {
		WriteError(c, err)
		return
	}
	v, err := h.svc.CreateDraft(c.Request.Context(), a, in)
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Draf versi baru dibuat", v)
}

func (h *Handler) UpdateDraft(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	var req draftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data draf tidak valid", nil)
		return
	}
	in, err := req.input()
	if err != nil {
		WriteError(c, err)
		return
	}
	v, err := h.svc.UpdateDraft(c.Request.Context(), a, c.Param("id"), in)
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Draf disimpan", v)
}

func (h *Handler) GeneratePDF(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	v, err := h.svc.GenerateDraftPDF(c.Request.Context(), a, c.Param("id"))
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "PDF draf dibuat", v)
}

func (h *Handler) UploadPDF(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	fh, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "File PDF wajib dipilih", nil)
		return
	}
	if fh.Size > maxUploadedPDFBytes {
		response.ErrorWithCode(c, http.StatusUnprocessableEntity, response.CodeBadRequest, "Ukuran file PDF maksimal 10 MB", nil)
		return
	}
	f, err := fh.Open()
	if err != nil {
		response.BadRequest(c, "File PDF tidak dapat dibaca", nil)
		return
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxUploadedPDFBytes+1))
	if err != nil {
		response.BadRequest(c, "Gagal membaca file PDF", nil)
		return
	}
	v, err := h.svc.UploadDraftPDF(c.Request.Context(), a, c.Param("id"), data)
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "PDF draf diunggah", v)
}

func (h *Handler) AdminPDF(c *gin.Context) {
	final := c.Query("type") != "draft"
	v, data, err := h.svc.AdminPDF(c.Request.Context(), c.Param("id"), final)
	if err != nil {
		WriteError(c, err)
		return
	}
	sha := ""
	if final {
		sha = *v.PDFSHA256
	} else {
		sha = *v.DraftPDFSHA256
	}
	writePDF(c, v, data, sha, false)
}

type submitRequest struct {
	EffectiveFrom string `json:"effective_from"`
}

func (h *Handler) Submit(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	var req submitRequest
	_ = c.ShouldBindJSON(&req)
	var eff *time.Time
	if s := strings.TrimSpace(req.EffectiveFrom); s != "" {
		t, err := time.Parse(time.RFC3339, s)
		if err != nil {
			response.BadRequest(c, "Format tanggal mulai berlaku tidak valid (contoh: 2026-12-01T00:00:00+07:00)", nil)
			return
		}
		eff = &t
	}
	v, err := h.svc.Submit(c.Request.Context(), a, c.Param("id"), eff)
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Diajukan untuk persetujuan", v)
}

func (h *Handler) Approve(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	v, err := h.svc.Approve(c.Request.Context(), a, c.Param("id"))
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Versi diterbitkan", v)
}

func (h *Handler) Reject(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	var req struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&req)
	v, err := h.svc.Reject(c.Request.Context(), a, c.Param("id"), req.Reason)
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Dikembalikan ke draf", v)
}

func (h *Handler) Archive(c *gin.Context) {
	a, ok := actor(c)
	if !ok {
		return
	}
	v, err := h.svc.Archive(c.Request.Context(), a, c.Param("id"))
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Versi diarsipkan", v)
}

func (h *Handler) ListAcceptances(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	out, err := h.svc.ListAcceptances(c.Request.Context(), AcceptanceFilter{UserID: c.Query("user_id"), VersionID: c.Query("version_id"), Limit: limit})
	if err != nil {
		WriteError(c, err)
		return
	}
	response.Success(c, "Riwayat persetujuan", out)
}
