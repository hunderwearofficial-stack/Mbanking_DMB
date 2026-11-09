package http

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/admin/service"
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

type AdminLoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AdminHandler) Login(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Username dan password wajib diisi", "01", err.Error())
		return
	}

	token, admin, err := h.adminService.Login(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, err.Error(), "02", nil)
		return
	}

	response.Success(c, "Login admin berhasil", gin.H{
		"token": token,
		"admin": gin.H{
			"id":        admin.ID,
			"username":  admin.Username,
			"full_name": admin.FullName,
			"email":     admin.Email,
			"role":      admin.Role,
		},
	})
}

func (h *AdminHandler) GetDashboardStats(c *gin.Context) {
	stats, err := h.adminService.GetDashboardStats(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memuat statistik", "99", err.Error())
		return
	}
	response.Success(c, "Statistik dashboard berhasil dimuat", stats)
}

func (h *AdminHandler) ListCustomers(c *gin.Context) {
	search := c.Query("search")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	users, total, err := h.adminService.ListCustomers(c.Request.Context(), search, page, limit)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengambil data nasabah", "99", err.Error())
		return
	}

	response.Success(c, "Data nasabah berhasil diambil", gin.H{
		"customers": users,
		"total":     total,
		"page":      page,
		"limit":     limit,
	})
}

func (h *AdminHandler) ResetCustomerDevice(c *gin.Context) {
	userID := c.Param("id")
	if userID == "" {
		response.Error(c, http.StatusBadRequest, "ID nasabah wajib diisi", "01", nil)
		return
	}

	if err := h.adminService.ResetCustomerDevice(c.Request.Context(), userID); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mereset ikatan perangkat", "99", err.Error())
		return
	}

	response.Success(c, "Ikatan perangkat (Device ID) nasabah berhasil di-reset / unbind", nil)
}

type ToggleStatusRequest struct {
	IsActive bool `json:"is_active"`
}

func (h *AdminHandler) ToggleCustomerStatus(c *gin.Context) {
	userID := c.Param("id")
	var req ToggleStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Parameter status tidak valid", "01", err.Error())
		return
	}

	if err := h.adminService.ToggleCustomerActive(c.Request.Context(), userID, req.IsActive); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengubah status nasabah", "99", err.Error())
		return
	}

	statusText := "diaktifkan"
	if !req.IsActive {
		statusText = "diblokir"
	}
	response.Success(c, "Status akun nasabah berhasil "+statusText, nil)
}

// Public API for Flutter Mobile App
func (h *AdminHandler) GetPublicBanners(c *gin.Context) {
	banners, err := h.adminService.ListBanners(c.Request.Context(), true)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengambil banner", "99", err.Error())
		return
	}
	response.Success(c, "Daftar banner berhasil diambil", banners)
}

// Admin APIs for Banner CMS
func (h *AdminHandler) ListBannersAdmin(c *gin.Context) {
	banners, err := h.adminService.ListBanners(c.Request.Context(), false)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengambil banner", "99", err.Error())
		return
	}
	response.Success(c, "Daftar banner berhasil diambil", banners)
}

func (h *AdminHandler) CreateBanner(c *gin.Context) {
	var banner model.Banner
	if err := c.ShouldBindJSON(&banner); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload banner tidak valid", "01", err.Error())
		return
	}

	if err := h.adminService.CreateBanner(c.Request.Context(), &banner); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal membuat banner baru", "99", err.Error())
		return
	}

	response.Success(c, "Banner promosi berhasil ditambahkan", banner)
}

func (h *AdminHandler) UpdateBanner(c *gin.Context) {
	id := c.Param("id")
	var banner model.Banner
	if err := c.ShouldBindJSON(&banner); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload banner tidak valid", "01", err.Error())
		return
	}
	banner.ID = id

	if err := h.adminService.UpdateBanner(c.Request.Context(), &banner); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memperbarui banner", "99", err.Error())
		return
	}

	response.Success(c, "Banner promosi berhasil diperbarui", banner)
}

func (h *AdminHandler) DeleteBanner(c *gin.Context) {
	id := c.Param("id")
	if err := h.adminService.DeleteBanner(c.Request.Context(), id); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal menghapus banner", "99", err.Error())
		return
	}
	response.Success(c, "Banner promosi berhasil dihapus", nil)
}

func (h *AdminHandler) ListTransactions(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	txs, err := h.adminService.ListTransactions(c.Request.Context(), limit)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memuat transaksi", "99", err.Error())
		return
	}
	response.Success(c, "Data transaksi berhasil dimuat", txs)
}

func (h *AdminHandler) GetConfig(c *gin.Context) {
	cfg, err := h.adminService.GetAppConfig(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengambil konfigurasi aplikasi", "99", err.Error())
		return
	}
	response.Success(c, "Konfigurasi aplikasi berhasil dimuat", cfg)
}

func (h *AdminHandler) UpdateConfig(c *gin.Context) {
	var req model.AppConfig
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Payload konfigurasi tidak valid", "01", err.Error())
		return
	}

	if err := h.adminService.UpdateAppConfig(c.Request.Context(), &req); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memperbarui konfigurasi", "99", err.Error())
		return
	}

	response.Success(c, "Pengaturan aplikasi & identitas bank berhasil disimpan", req)
}

// UploadFile handles POST /api/v1/admin/upload for bank logo and assets
func (h *AdminHandler) UploadFile(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "File gambar wajib diunggah", "01", err.Error())
		return
	}

	// Validate size (max 5MB)
	if file.Size > 5*1024*1024 {
		response.Error(c, http.StatusBadRequest, "Ukuran file maksimum adalah 5MB", "01", nil)
		return
	}

	// Validate extension
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".webp" && ext != ".svg" {
		response.Error(c, http.StatusBadRequest, "Format file harus PNG, JPG, WebP, atau SVG", "01", nil)
		return
	}

	uploadDir := "./web/admin/uploads"
	_ = os.MkdirAll(uploadDir, 0755)

	filename := fmt.Sprintf("logo_%d%s", time.Now().UnixNano(), ext)
	dst := filepath.Join(uploadDir, filename)

	if err := c.SaveUploadedFile(file, dst); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal menyimpan file gambar ke server", "99", err.Error())
		return
	}

	fileURL := fmt.Sprintf("/admin/uploads/%s", filename)
	response.Success(c, "File logo berhasil diunggah", gin.H{
		"url":       fileURL,
		"filename":  filename,
		"file_size": file.Size,
	})
}

// ListAdminUsers handles GET /api/v1/admin/users
func (h *AdminHandler) ListAdminUsers(c *gin.Context) {
	admins, err := h.adminService.ListAdminUsers(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memuat daftar petugas admin", "99", err.Error())
		return
	}
	response.Success(c, "Daftar petugas admin berhasil dimuat", admins)
}

type CreateAdminRequest struct {
	Username string `json:"username" binding:"required"`
	FullName string `json:"full_name" binding:"required"`
	Email    string `json:"email"`
	Password string `json:"password" binding:"required"`
	Role     string `json:"role"`
	IsActive bool   `json:"is_active"`
}

// CreateAdminUser handles POST /api/v1/admin/users
func (h *AdminHandler) CreateAdminUser(c *gin.Context) {
	var req CreateAdminRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Form data petugas tidak lengkap", "01", err.Error())
		return
	}

	admin, err := h.adminService.CreateAdminUser(c.Request.Context(), req.Username, req.FullName, req.Email, req.Password, req.Role, req.IsActive)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error(), "02", nil)
		return
	}

	response.Success(c, "Petugas admin baru berhasil didaftarkan", admin)
}

type ToggleAdminStatusRequest struct {
	IsActive bool `json:"is_active"`
}

// ToggleAdminUserStatus handles PUT /api/v1/admin/users/:id/status
func (h *AdminHandler) ToggleAdminUserStatus(c *gin.Context) {
	id := c.Param("id")
	var req ToggleAdminStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Format status tidak valid", "01", err.Error())
		return
	}

	if err := h.adminService.ToggleAdminStatus(c.Request.Context(), id, req.IsActive); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengubah status petugas", "99", err.Error())
		return
	}

	response.Success(c, "Status akun petugas berhasil diperbarui", gin.H{"id": id, "is_active": req.IsActive})
}

// DeleteAdminUser handles DELETE /api/v1/admin/users/:id
func (h *AdminHandler) DeleteAdminUser(c *gin.Context) {
	id := c.Param("id")
	if err := h.adminService.DeleteAdminUser(c.Request.Context(), id); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal menghapus petugas admin", "99", err.Error())
		return
	}
	response.Success(c, "Akun petugas admin berhasil dihapus", gin.H{"id": id})
}

// ListAuditLogs handles GET /api/v1/admin/audit-logs
func (h *AdminHandler) ListAuditLogs(c *gin.Context) {
	actorType := c.DefaultQuery("actor_type", "ALL")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	logs, err := h.adminService.ListAuditLogs(c.Request.Context(), actorType, limit)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memuat log audit keamanan", "99", err.Error())
		return
	}
	response.Success(c, "Data audit trail berhasil dimuat", logs)
}

type BroadcastNotificationRequest struct {
	Title    string `json:"title" binding:"required"`
	Message  string `json:"message" binding:"required"`
	Category string `json:"category"`
}

// BroadcastNotification handles POST /api/v1/admin/notifications/broadcast
func (h *AdminHandler) BroadcastNotification(c *gin.Context) {
	var req BroadcastNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "Judul dan isi pesan notifikasi wajib diisi", "01", err.Error())
		return
	}
	if err := h.adminService.BroadcastNotification(c.Request.Context(), req.Title, req.Message, req.Category); err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal mengirim broadcast notifikasi", "99", err.Error())
		return
	}
	response.Success(c, "Notifikasi broadcast berhasil dikirimkan ke seluruh nasabah", nil)
}

// ListUserNotifications handles GET /api/v1/notifications
func (h *AdminHandler) ListUserNotifications(c *gin.Context) {
	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID = val.(string)
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "30"))
	notifs, err := h.adminService.ListNotificationsForUser(c.Request.Context(), userID, limit)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Gagal memuat notifikasi", "99", err.Error())
		return
	}
	response.Success(c, "Daftar notifikasi berhasil dimuat", notifs)
}

// MarkNotificationsRead handles POST /api/v1/notifications/read
func (h *AdminHandler) MarkNotificationsRead(c *gin.Context) {
	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID = val.(string)
	}
	_ = h.adminService.MarkNotificationsRead(c.Request.Context(), userID)
	response.Success(c, "Seluruh notifikasi ditandai telah dibaca", gin.H{"read": true})
}

type FCMTokenRequest struct {
	FCMToken string `json:"fcm_token" binding:"required"`
}

// UpdateUserFCMToken handles POST /api/v1/notifications/fcm-token
func (h *AdminHandler) UpdateUserFCMToken(c *gin.Context) {
	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID = val.(string)
	}
	var req FCMTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "fcm_token wajib diisi", "01", err.Error())
		return
	}
	_ = h.adminService.UpdateUserFCMToken(c.Request.Context(), userID, req.FCMToken)
	response.Success(c, "FCM token perangkat berhasil didaftarkan", gin.H{"registered": true})
}

