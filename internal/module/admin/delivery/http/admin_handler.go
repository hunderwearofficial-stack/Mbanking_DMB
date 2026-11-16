package http

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"mbanking-bpr/internal/module/admin/service"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type AdminHandler struct {
	adminService service.AdminService
}

func NewAdminHandler(adminService service.AdminService) *AdminHandler {
	return &AdminHandler{adminService: adminService}
}

// fail writes a safe error response: validation / business errors are shown to the
// user; anything else is logged and replaced by a generic message (audit DMB-024).
func fail(c *gin.Context, err error, generic string) {
	switch {
	case errors.Is(err, service.ErrValidation), errors.Is(err, service.ErrInvalidRole),
		errors.Is(err, service.ErrSelfModification), errors.Is(err, service.ErrLastSuperAdmin),
		errors.Is(err, service.ErrBannerNotFound), errors.Is(err, service.ErrCustomerNotFound):
		response.Error(c, http.StatusBadRequest, err.Error(), "01", nil)
	default:
		logger.GetLogger().Error(generic, map[string]interface{}{"error": err.Error(), "path": c.FullPath()})
		response.Error(c, http.StatusInternalServerError, generic, "99", nil)
	}
}

type AdminLoginRequest struct {
	Username string `json:"username" binding:"required,max=50"`
	Password string `json:"password" binding:"required,max=128"`
}

func (h *AdminHandler) Login(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Username dan password wajib diisi", "01", nil)
		return
	}
	res, err := h.adminService.Login(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrAdminInvalidCredentials), errors.Is(err, service.ErrAdminAccountDisabled),
			errors.Is(err, service.ErrAdminDefaultPassword), errors.Is(err, service.ErrInvalidRole):
			response.Error(c, http.StatusUnauthorized, err.Error(), "02", nil)
		default:
			fail(c, err, "Login petugas gagal diproses")
		}
		return
	}
	response.Success(c, "Login admin berhasil", gin.H{
		"token":      res.Token,
		"expires_at": res.ExpiresAt,
		"admin": gin.H{
			"id": res.Admin.ID, "username": res.Admin.Username, "full_name": res.Admin.FullName,
			"email": res.Admin.Email, "role": res.Admin.Role,
		},
	})
}

func (h *AdminHandler) GetDashboardStats(c *gin.Context) {
	stats, err := h.adminService.GetDashboardStats(c.Request.Context())
	if err != nil {
		fail(c, err, "Gagal memuat statistik")
		return
	}
	response.Success(c, "Statistik dashboard berhasil dimuat", stats)
}

func (h *AdminHandler) ListCustomers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	users, total, err := h.adminService.ListCustomers(c.Request.Context(), c.Query("search"), page, limit)
	if err != nil {
		fail(c, err, "Gagal mengambil data nasabah")
		return
	}
	response.Success(c, "Data nasabah berhasil diambil", gin.H{"customers": users, "total": total, "page": page, "limit": limit})
}

func (h *AdminHandler) ResetCustomerDevice(c *gin.Context) {
	if err := h.adminService.ResetCustomerDevice(c.Request.Context(), c.Param("id")); err != nil {
		fail(c, err, "Gagal mereset ikatan perangkat")
		return
	}
	response.Success(c, "Ikatan perangkat (Device ID) nasabah berhasil di-reset / unbind", nil)
}

type ToggleStatusRequest struct {
	IsActive bool `json:"is_active"`
}

func (h *AdminHandler) ToggleCustomerStatus(c *gin.Context) {
	var req ToggleStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Parameter status tidak valid", "01", nil)
		return
	}
	if err := h.adminService.ToggleCustomerActive(c.Request.Context(), c.Param("id"), req.IsActive); err != nil {
		fail(c, err, "Gagal mengubah status nasabah")
		return
	}
	statusText := "diaktifkan"
	if !req.IsActive {
		statusText = "diblokir"
	}
	response.Success(c, "Status akun nasabah berhasil "+statusText, nil)
}

// GetPublicBanners is the public API for the mobile app.
func (h *AdminHandler) GetPublicBanners(c *gin.Context) {
	banners, err := h.adminService.ListBanners(c.Request.Context(), true)
	if err != nil {
		fail(c, err, "Gagal mengambil banner")
		return
	}
	response.Success(c, "Daftar banner berhasil diambil", banners)
}

func (h *AdminHandler) ListBannersAdmin(c *gin.Context) {
	banners, err := h.adminService.ListBanners(c.Request.Context(), false)
	if err != nil {
		fail(c, err, "Gagal mengambil banner")
		return
	}
	response.Success(c, "Daftar banner berhasil diambil", banners)
}

func (h *AdminHandler) CreateBanner(c *gin.Context) {
	var in service.BannerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload banner tidak valid", "01", nil)
		return
	}
	b, err := h.adminService.CreateBanner(c.Request.Context(), in)
	if err != nil {
		fail(c, err, "Gagal membuat banner baru")
		return
	}
	response.Success(c, "Banner promosi berhasil ditambahkan", b)
}

func (h *AdminHandler) UpdateBanner(c *gin.Context) {
	var in service.BannerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload banner tidak valid", "01", nil)
		return
	}
	b, err := h.adminService.UpdateBanner(c.Request.Context(), c.Param("id"), in)
	if err != nil {
		fail(c, err, "Gagal memperbarui banner")
		return
	}
	response.Success(c, "Banner promosi berhasil diperbarui", b)
}

func (h *AdminHandler) DeleteBanner(c *gin.Context) {
	if err := h.adminService.DeleteBanner(c.Request.Context(), c.Param("id")); err != nil {
		fail(c, err, "Gagal menghapus banner")
		return
	}
	response.Success(c, "Banner promosi berhasil dihapus", nil)
}

func (h *AdminHandler) ListTransactions(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	txs, err := h.adminService.ListTransactions(c.Request.Context(), limit)
	if err != nil {
		fail(c, err, "Gagal memuat transaksi")
		return
	}
	response.Success(c, "Data transaksi berhasil dimuat", txs)
}

// GetPublicConfig returns only client-safe configuration (no secrets) — audit DMB-006.
func (h *AdminHandler) GetPublicConfig(c *gin.Context) {
	cfg, err := h.adminService.GetAppConfig(c.Request.Context())
	if err != nil {
		fail(c, err, "Gagal mengambil konfigurasi aplikasi")
		return
	}
	response.Success(c, "Konfigurasi aplikasi berhasil dimuat", cfg.Public())
}

// GetConfig returns the backoffice view (secrets reported only as "configured" flags).
func (h *AdminHandler) GetConfig(c *gin.Context) {
	cfg, err := h.adminService.GetAppConfig(c.Request.Context())
	if err != nil {
		fail(c, err, "Gagal mengambil konfigurasi aplikasi")
		return
	}
	response.Success(c, "Konfigurasi aplikasi berhasil dimuat", cfg.AdminView())
}

func (h *AdminHandler) UpdateConfig(c *gin.Context) {
	var req service.AppConfigUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload konfigurasi tidak valid", "01", nil)
		return
	}
	cfg, err := h.adminService.UpdateAppConfig(c.Request.Context(), req)
	if err != nil {
		fail(c, err, "Gagal memperbarui konfigurasi")
		return
	}
	response.Success(c, "Pengaturan aplikasi & identitas bank berhasil disimpan", cfg.AdminView())
}

// allowedImageTypes maps sniffed content types to file extensions. SVG is not
// accepted (it can carry script — audit DMB-017).
var allowedImageTypes = map[string]string{
	"image/png":  ".png",
	"image/jpeg": ".jpg",
	"image/webp": ".webp",
}

// UploadFile handles POST /api/v1/admin/upload for images and PDF documents.
func (h *AdminHandler) UploadFile(c *gin.Context) {
	category := strings.ToLower(strings.TrimSpace(c.DefaultPostForm("category", c.Query("category"))))
	const maxDocSize = 10 * 1024 * 1024
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxDocSize+64*1024)
	file, err := c.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "File wajib diunggah", "01", nil)
		return
	}

	src, err := file.Open()
	if err != nil {
		response.Error(c, http.StatusBadRequest, "File tidak dapat dibaca", "01", nil)
		return
	}
	defer src.Close()

	head := make([]byte, 512)
	n, _ := io.ReadFull(src, head)
	sniffed := http.DetectContentType(head[:n])
	isPDF := (sniffed == "application/pdf" || strings.HasPrefix(string(head[:n]), "%PDF-") || strings.HasSuffix(strings.ToLower(file.Filename), ".pdf"))

	var uploadDir, prefix, ext string
	if isPDF || category == "document" || category == "terms" || category == "privacy" {
		// Legal documents are generated, versioned and approved in the Terms module
		// (/admin/terms/*) and stored outside the public web directory. Free PDF uploads
		// into web/admin/uploads (publicly served, unversioned) are no longer accepted.
		response.Error(c, http.StatusBadRequest, "Unggah PDF tidak didukung. Dokumen Syarat dan Ketentuan dikelola di menu Syarat & Ketentuan (versi, PDF, dan persetujuan).", "01", nil)
		return
	} else {
		const maxImgSize = 5 * 1024 * 1024
		if file.Size > maxImgSize {
			response.Error(c, http.StatusBadRequest, "Ukuran file gambar maksimum adalah 5MB", "01", nil)
			return
		}
		imageExt, ok := allowedImageTypes[sniffed]
		if !ok {
			response.Error(c, http.StatusBadRequest, "Format gambar harus PNG, JPG, atau WebP", "01", nil)
			return
		}
		uploadDir = "./web/admin/uploads"
		prefix = "img_"
		if category == "logo" {
			prefix = "logo_"
		} else if category == "login_bg" || category == "bg" {
			prefix = "bg_"
		} else if category == "splash_bg" {
			prefix = "splash_"
		} else if category == "onboarding_bg" {
			prefix = "onboarding_"
		} else if category == "banner" {
			prefix = "banner_"
		}
		ext = imageExt
	}

	if err := os.MkdirAll(uploadDir, 0o750); err != nil {
		fail(c, err, "Gagal membuat direktori upload di server")
		return
	}

	rnd := make([]byte, 12)
	if _, err := rand.Read(rnd); err != nil {
		fail(c, err, "Gagal memproses file upload")
		return
	}

	filename := prefix + hex.EncodeToString(rnd) + ext
	if err := c.SaveUploadedFile(file, filepath.Join(uploadDir, filename)); err != nil {
		fail(c, err, "Gagal menyimpan file ke server")
		return
	}

	relURL := fmt.Sprintf("/admin/uploads/%s", filename)
	if isPDF || category == "document" || category == "terms" || category == "privacy" {
		relURL = fmt.Sprintf("/admin/uploads/documents/%s", filename)
	}

	response.Success(c, "File berhasil diunggah", gin.H{
		"url": relURL, "filename": filename, "file_size": file.Size, "is_document": isPDF,
	})
}

func (h *AdminHandler) ListAdminUsers(c *gin.Context) {
	admins, err := h.adminService.ListAdminUsers(c.Request.Context())
	if err != nil {
		fail(c, err, "Gagal memuat daftar petugas admin")
		return
	}
	response.Success(c, "Daftar petugas admin berhasil dimuat", admins)
}

type CreateAdminRequest struct {
	Username string `json:"username" binding:"required"`
	FullName string `json:"full_name" binding:"required"`
	Email    string `json:"email"`
	Password string `json:"password" binding:"required"`
	Role     string `json:"role" binding:"required"`
	IsActive bool   `json:"is_active"`
}

func (h *AdminHandler) CreateAdminUser(c *gin.Context) {
	var req CreateAdminRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Form data petugas tidak lengkap (username, nama, password, role wajib)", "01", nil)
		return
	}
	admin, err := h.adminService.CreateAdminUser(c.Request.Context(), req.Username, req.FullName, req.Email, req.Password, req.Role, req.IsActive)
	if err != nil {
		if errors.Is(err, service.ErrValidation) || errors.Is(err, service.ErrInvalidRole) {
			fail(c, err, "")
			return
		}
		response.Error(c, http.StatusBadRequest, err.Error(), "02", nil)
		return
	}
	response.Success(c, "Petugas admin baru berhasil didaftarkan", admin)
}

type ToggleAdminStatusRequest struct {
	IsActive bool `json:"is_active"`
}

func (h *AdminHandler) ToggleAdminUserStatus(c *gin.Context) {
	id := c.Param("id")
	var req ToggleAdminStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Format status tidak valid", "01", nil)
		return
	}
	if err := h.adminService.ToggleAdminStatus(c.Request.Context(), id, req.IsActive); err != nil {
		fail(c, err, "Gagal mengubah status petugas")
		return
	}
	response.Success(c, "Status akun petugas berhasil diperbarui", gin.H{"id": id, "is_active": req.IsActive})
}

func (h *AdminHandler) DeleteAdminUser(c *gin.Context) {
	id := c.Param("id")
	if err := h.adminService.DeleteAdminUser(c.Request.Context(), id); err != nil {
		fail(c, err, "Gagal menghapus petugas admin")
		return
	}
	response.Success(c, "Akun petugas admin berhasil dihapus", gin.H{"id": id})
}

func (h *AdminHandler) ListAuditLogs(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	logs, err := h.adminService.ListAuditLogs(c.Request.Context(), c.DefaultQuery("actor_type", "ALL"), limit)
	if err != nil {
		fail(c, err, "Gagal memuat log audit keamanan")
		return
	}
	response.Success(c, "Data audit trail berhasil dimuat", logs)
}

// ---- Pengajuan produk nasabah (backoffice) ----

func (h *AdminHandler) ListAllApplicationsAdmin(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	list, err := h.adminService.ListAllApplications(c.Request.Context(), c.DefaultQuery("type", "ALL"), limit)
	if err != nil {
		fail(c, err, "Gagal memuat daftar pengajuan nasabah")
		return
	}
	response.Success(c, "Daftar pengajuan produk nasabah berhasil dimuat", list)
}

type UpdateApplicationStatusRequest struct {
	Status     string `json:"status" binding:"required"`
	AdminNotes string `json:"admin_notes"`
}

func (h *AdminHandler) UpdateApplicationStatusAdmin(c *gin.Context) {
	var req UpdateApplicationStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Status wajib diisi", "01", nil)
		return
	}
	app, err := h.adminService.UpdateApplicationStatus(c.Request.Context(), c.Param("id"), req.Status, req.AdminNotes)
	if err != nil {
		fail(c, err, "Gagal memperbarui status pengajuan")
		return
	}
	response.Success(c, "Status pengajuan nasabah berhasil diperbarui", app)
}
