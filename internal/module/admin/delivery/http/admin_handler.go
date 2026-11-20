package http

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/module/admin/repository"
	"mbanking-bpr/internal/module/admin/service"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type AdminHandler struct {
	adminService service.AdminService
}

func NewAdminHandler(adminService service.AdminService) *AdminHandler {
	return &AdminHandler{adminService: adminService}
}

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
			errors.Is(err, service.ErrAdminAccountLocked), errors.Is(err, service.ErrAdminDefaultPassword),
			errors.Is(err, service.ErrInvalidRole):
			response.Error(c, http.StatusUnauthorized, err.Error(), "02", nil)
		default:
			fail(c, err, "Login petugas gagal diproses")
		}
		return
	}
	maxAge := int(time.Until(res.ExpiresAt).Seconds())
	if maxAge <= 0 {
		maxAge = 3600
	}
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(middleware.AdminSessionCookie, res.Token, maxAge, middleware.AdminCookiePath, "", h.adminService.IsProductionLike(), true)

	response.Success(c, "Login admin berhasil", gin.H{
		"token":      res.Token,
		"expires_at": res.ExpiresAt,
		"admin": gin.H{
			"id": res.Admin.ID, "username": res.Admin.Username, "full_name": res.Admin.FullName,
			"email": res.Admin.Email, "role": res.Admin.Role,
		},
	})
}

func (h *AdminHandler) Logout(c *gin.Context) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(middleware.AdminSessionCookie, "", -1, middleware.AdminCookiePath, "", h.adminService.IsProductionLike(), true)
	h.adminService.Logout(c.Request.Context())
	response.Success(c, "Logout admin berhasil", gin.H{"logged_out": true})
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
	response.Success(c, "Ikatan perangkat nasabah berhasil di-reset", nil)
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
		response.Error(c, http.StatusBadRequest, "Format data banner tidak valid", "01", nil)
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
		response.Error(c, http.StatusBadRequest, "Format data banner tidak valid", "01", nil)
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

func (h *AdminHandler) GetPublicConfig(c *gin.Context) {
	cfg, err := h.adminService.GetAppConfig(c.Request.Context())
	if err != nil {
		fail(c, err, "Gagal mengambil konfigurasi aplikasi")
		return
	}
	response.Success(c, "Konfigurasi aplikasi berhasil dimuat", cfg.Public())
}

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
		response.Error(c, http.StatusBadRequest, "Format data konfigurasi tidak valid", "01", nil)
		return
	}
	cfg, err := h.adminService.UpdateAppConfig(c.Request.Context(), req)
	if err != nil {
		fail(c, err, "Gagal memperbarui konfigurasi")
		return
	}
	response.Success(c, "Pengaturan aplikasi & identitas bank berhasil disimpan", cfg.AdminView())
}

var allowedImageTypes = map[string]string{
	"image/png":  ".png",
	"image/jpeg": ".jpg",
	"image/webp": ".webp",
}

func decodeWebPDimensions(raw []byte) (int, int, error) {
	if len(raw) < 30 || string(raw[0:4]) != "RIFF" || string(raw[8:12]) != "WEBP" {
		return 0, 0, errors.New("header WebP tidak valid")
	}
	chunk := string(raw[12:16])
	switch chunk {
	case "VP8X":
		w := 1 + (int(raw[24]) | int(raw[25])<<8 | int(raw[26])<<16)
		h := 1 + (int(raw[27]) | int(raw[28])<<8 | int(raw[29])<<16)
		return w, h, nil
	case "VP8 ":
		if raw[23] != 0x9d || raw[24] != 0x01 || raw[25] != 0x2a {
			return 0, 0, errors.New("frame VP8 tidak valid")
		}
		w := (int(raw[26]) | int(raw[27])<<8) & 0x3fff
		h := (int(raw[28]) | int(raw[29])<<8) & 0x3fff
		return w, h, nil
	case "VP8L":
		if len(raw) < 25 || raw[20] != 0x2f {
			return 0, 0, errors.New("frame VP8L tidak valid")
		}
		b0, b1, b2, b3 := uint32(raw[21]), uint32(raw[22]), uint32(raw[23]), uint32(raw[24])
		bits := b0 | b1<<8 | b2<<16 | b3<<24
		w := int(bits&0x3fff) + 1
		h := int((bits>>14)&0x3fff) + 1
		return w, h, nil
	default:
		return 0, 0, errors.New("format chunk WebP tidak didukung")
	}
}

func (h *AdminHandler) UploadFile(c *gin.Context) {
	category := strings.ToLower(strings.TrimSpace(c.DefaultPostForm("category", c.Query("category"))))
	if category == "" {
		category = "general"
	}
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

	const maxImgSize = 5 * 1024 * 1024
	rawBytes, err := io.ReadAll(io.LimitReader(src, maxImgSize+1024))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "File tidak dapat dibaca", "01", nil)
		return
	}

	sniffed := http.DetectContentType(rawBytes)
	isPDF := (sniffed == "application/pdf" || strings.HasPrefix(string(rawBytes), "%PDF-") || strings.HasSuffix(strings.ToLower(file.Filename), ".pdf"))

	var uploadDir, prefix, ext string
	if isPDF || category == "document" || category == "terms" || category == "privacy" {
		response.Error(c, http.StatusBadRequest, "Unggah PDF tidak didukung. Dokumen Syarat dan Ketentuan dikelola di menu Syarat & Ketentuan (versi, PDF, dan persetujuan).", "01", nil)
		return
	} else {
		if file.Size > maxImgSize || len(rawBytes) > maxImgSize {
			response.Error(c, http.StatusBadRequest, "Ukuran file gambar maksimum adalah 5MB", "01", nil)
			return
		}
		imageExt, ok := allowedImageTypes[sniffed]
		if !ok {
			response.Error(c, http.StatusBadRequest, "Format gambar harus PNG, JPG, atau WebP", "01", nil)
			return
		}
		var width, height int
		if sniffed == "image/webp" {
			w, hDim, werr := decodeWebPDimensions(rawBytes)
			if werr != nil {
				response.Error(c, http.StatusBadRequest, "File gambar WebP rusak atau tidak valid", "01", nil)
				return
			}
			width, height = w, hDim
		} else {
			cfg, _, derr := image.DecodeConfig(bytes.NewReader(rawBytes))
			if derr != nil {
				response.Error(c, http.StatusBadRequest, "File gambar rusak atau tidak dapat diproses", "01", nil)
				return
			}
			width, height = cfg.Width, cfg.Height
		}
		if width <= 0 || height <= 0 || width > 4096 || height > 4096 {
			response.Error(c, http.StatusBadRequest, "Dimensi gambar tidak valid (maksimum 4096x4096 piksel)", "01", nil)
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
		fail(c, err, "Gagal menyiapkan direktori unggahan")
		return
	}

	rnd := make([]byte, 12)
	if _, err := rand.Read(rnd); err != nil {
		fail(c, err, "Gagal memproses file unggahan")
		return
	}

	filename := prefix + hex.EncodeToString(rnd) + ext
	if err := os.WriteFile(filepath.Join(uploadDir, filename), rawBytes, 0o640); err != nil {
		fail(c, err, "Gagal menyimpan file unggahan")
		return
	}

	fileURL := fmt.Sprintf("/admin/uploads/%s", filename)
	audit.Record(c.Request.Context(), h.adminService.DB(), "ADMIN", "", "", "UPLOAD_ASSET", filename, "SUCCESS", "WEB-BACKOFFICE",
		fmt.Sprintf("Mengunggah aset %s (kategori: %s, URL: %s, ukuran: %d byte)", filename, category, fileURL, file.Size))

	response.Success(c, "File berhasil diunggah", gin.H{
		"url":        fileURL,
		"filename":   filename,
		"category":   category,
		"size_bytes": file.Size,
		"file_size":  file.Size,
	})
}

var validAssetFilename = regexp.MustCompile(`^[A-Za-z0-9_\-]+\.(png|jpg|jpeg|webp|pdf)$`)

type AssetItem struct {
	Filename  string    `json:"filename"`
	URL       string    `json:"url"`
	Category  string    `json:"category"`
	SizeBytes int64     `json:"size_bytes"`
	UpdatedAt time.Time `json:"updated_at"`
	InUse     bool      `json:"in_use"`
	UsedBy    []string  `json:"used_by"`
}

func inferAssetCategory(filename string) string {
	lower := strings.ToLower(filename)
	switch {
	case strings.HasPrefix(lower, "logo_"):
		return "logo"
	case strings.HasPrefix(lower, "bg_"):
		return "login_bg"
	case strings.HasPrefix(lower, "splash_"):
		return "splash_bg"
	case strings.HasPrefix(lower, "onboarding_"):
		return "onboarding_bg"
	case strings.HasPrefix(lower, "banner_"):
		return "banner"
	case strings.HasSuffix(lower, ".pdf"):
		return "document"
	default:
		return "general"
	}
}

func (h *AdminHandler) collectAssetUsage(c *gin.Context) map[string][]string {
	usage := map[string][]string{}
	addUse := func(urlStr, label string) {
		urlStr = strings.TrimSpace(urlStr)
		if urlStr == "" {
			return
		}
		for _, existing := range usage[urlStr] {
			if existing == label {
				return
			}
		}
		usage[urlStr] = append(usage[urlStr], label)
	}

	if cfg, err := h.adminService.GetAppConfig(c.Request.Context()); err == nil && cfg != nil {
		addUse(cfg.LogoURL, "Konfigurasi: Logo Bank")
		addUse(cfg.LoginBgURL, "Konfigurasi: Latar Login")
		addUse(cfg.SplashBgURL, "Konfigurasi: Latar Splash")
		addUse(cfg.OnboardingBgURL, "Konfigurasi: Latar Onboarding")
		addUse(cfg.TermsPdfURL, "Konfigurasi: PDF S&K")
		addUse(cfg.PrivacyPdfURL, "Konfigurasi: PDF Privasi")
	}

	if banners, err := h.adminService.ListBanners(c.Request.Context(), false); err == nil {
		for _, b := range banners {
			addUse(b.ImageURL, "Banner: "+b.Title)
		}
	}

	if db := h.adminService.DB(); db != nil {
		var rows []struct {
			VersionNumber int
			Status        string
			Content       string
		}
		if err := db.WithContext(c.Request.Context()).Table("mobile_content_revisions").
			Select("version_number, status, content::text AS content").
			Where("status IN ?", []string{"PUBLISHED", "DRAFT", "PENDING_APPROVAL"}).
			Scan(&rows).Error; err == nil {
			for _, r := range rows {
				label := fmt.Sprintf("Konten Aplikasi v%d (%s)", r.VersionNumber, r.Status)
				// Extract any /admin/uploads/<filename> references in the JSONB content
				matches := regexp.MustCompile(`/admin/uploads/[A-Za-z0-9_\-]+\.(png|jpg|jpeg|webp|pdf)`).FindAllString(r.Content, -1)
				for _, m := range matches {
					addUse(m, label)
				}
			}
		}
	}
	return usage
}

func (h *AdminHandler) ListAssets(c *gin.Context) {
	uploadDir := "./web/admin/uploads"
	entries, err := os.ReadDir(uploadDir)
	if err != nil {
		if os.IsNotExist(err) {
			response.Success(c, "Daftar aset berhasil dimuat", []AssetItem{})
			return
		}
		fail(c, err, "Gagal membaca direktori aset")
		return
	}
	usage := h.collectAssetUsage(c)
	items := make([]AssetItem, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || !validAssetFilename.MatchString(e.Name()) {
			continue
		}
		info, ierr := e.Info()
		if ierr != nil {
			continue
		}
		u := "/admin/uploads/" + e.Name()
		usedBy := usage[u]
		if usedBy == nil {
			usedBy = []string{}
		}
		items = append(items, AssetItem{
			Filename:  e.Name(),
			URL:       u,
			Category:  inferAssetCategory(e.Name()),
			SizeBytes: info.Size(),
			UpdatedAt: info.ModTime(),
			InUse:     len(usedBy) > 0,
			UsedBy:    usedBy,
		})
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].UpdatedAt.After(items[j].UpdatedAt)
	})
	response.Success(c, "Daftar aset berhasil dimuat", items)
}

func (h *AdminHandler) DeleteAsset(c *gin.Context) {
	filename := strings.TrimSpace(c.Param("filename"))
	if !validAssetFilename.MatchString(filename) || strings.Contains(filename, "..") || strings.ContainsAny(filename, `/\`) {
		response.Error(c, http.StatusBadRequest, "Nama file aset tidak valid", "01", nil)
		return
	}
	u := "/admin/uploads/" + filename
	usage := h.collectAssetUsage(c)
	if len(usage[u]) > 0 {
		response.Error(c, http.StatusConflict, "Aset sedang digunakan pada konfigurasi atau konten aktif dan tidak dapat dihapus", "07", gin.H{
			"in_use":  true,
			"used_by": usage[u],
		})
		return
	}
	targetPath := filepath.Join("./web/admin/uploads", filename)
	if _, err := os.Stat(targetPath); err != nil {
		if os.IsNotExist(err) {
			response.NotFound(c, "File aset tidak ditemukan")
			return
		}
		fail(c, err, "Gagal memeriksa file aset")
		return
	}
	if err := os.Remove(targetPath); err != nil {
		fail(c, err, "Gagal menghapus file aset")
		return
	}
	audit.Record(c.Request.Context(), h.adminService.DB(), "ADMIN", "", "", "DELETE_ASSET", filename, "WARNING", "WEB-BACKOFFICE",
		fmt.Sprintf("Menghapus file aset %s (%s)", filename, u))
	response.Success(c, "Aset berhasil dihapus", gin.H{"filename": filename, "deleted": true})
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

type UpdateAdminRequest struct {
	FullName string `json:"full_name"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	Password string `json:"password"`
}

func (h *AdminHandler) UpdateAdminUser(c *gin.Context) {
	id := c.Param("id")
	var req UpdateAdminRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Format data pembaruan petugas tidak valid", "01", nil)
		return
	}
	admin, err := h.adminService.UpdateAdminUser(c.Request.Context(), id, req.FullName, req.Email, req.Role, req.Password)
	if err != nil {
		if errors.Is(err, service.ErrValidation) || errors.Is(err, service.ErrInvalidRole) ||
			errors.Is(err, service.ErrSelfModification) || errors.Is(err, service.ErrLastSuperAdmin) {
			fail(c, err, "")
			return
		}
		response.Error(c, http.StatusBadRequest, err.Error(), "02", nil)
		return
	}
	response.Success(c, "Data petugas admin berhasil diperbarui", admin)
}

type ChangeOwnPasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

func (h *AdminHandler) ChangeOwnPassword(c *gin.Context) {
	var req ChangeOwnPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Password lama dan password baru wajib diisi", "01", nil)
		return
	}
	if err := h.adminService.ChangeOwnPassword(c.Request.Context(), req.OldPassword, req.NewPassword); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error(), "01", nil)
		return
	}
	response.Success(c, "Password akun petugas Anda berhasil diperbarui", gin.H{"updated": true})
}

func (h *AdminHandler) DeleteAdminUser(c *gin.Context) {
	id := c.Param("id")
	if err := h.adminService.DeleteAdminUser(c.Request.Context(), id); err != nil {
		fail(c, err, "Gagal menghapus petugas admin")
		return
	}
	response.Success(c, "Akun petugas admin berhasil dihapus", gin.H{"id": id})
}

func parseAuditDateParam(raw string, isEnd bool) *time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		return &t
	}
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		if isEnd {
			t = t.Add(24 * time.Hour)
		}
		return &t
	}
	return nil
}

func (h *AdminHandler) ListAuditLogs(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	beforeSeq, _ := strconv.ParseInt(c.Query("before_seq"), 10, 64)
	filter := repository.AuditLogFilter{
		ActorType: c.DefaultQuery("actor_type", "ALL"),
		Action:    c.Query("action"),
		Search:    c.Query("search"),
		From:      parseAuditDateParam(c.Query("from"), false),
		To:        parseAuditDateParam(c.Query("to"), true),
		BeforeSeq: beforeSeq,
		Limit:     limit,
	}
	logs, err := h.adminService.ListAuditLogs(c.Request.Context(), filter)
	if err != nil {
		fail(c, err, "Gagal memuat log audit keamanan")
		return
	}
	response.Success(c, "Data audit trail berhasil dimuat", logs)
}

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
