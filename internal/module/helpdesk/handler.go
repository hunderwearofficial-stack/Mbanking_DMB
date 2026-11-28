package helpdesk

import (
	"net/http"
	"strings"
	"sync"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Handler struct {
	db   *gorm.DB
	once sync.Once
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{db: db}
}

func (h *Handler) ensureReady() {
	if h.db == nil {
		return
	}
	h.once.Do(func() {
		_ = h.db.AutoMigrate(&model.HelpdeskFAQ{}, &model.HelpdeskInquiry{})
		var count int64
		if err := h.db.Model(&model.HelpdeskFAQ{}).Count(&count).Error; err == nil && count == 0 {
			defaults := []model.HelpdeskFAQ{
				{
					ID:        uuid.NewString(),
					Topic:     "Lupa PIN / Password",
					Keywords:  "pin,password,sandi,lupa,blokir,terkunci,login,masuk",
					Answer:    "Jika lupa password, gunakan menu \"Lupa Password\" di halaman Login dan ikuti verifikasi OTP ke nomor HP terdaftar.\n\nJika akun/PIN terblokir karena salah memasukkan PIN/password berulang kali, silakan hubungi Contact Center Bank DMB untuk pembukaan blokir.",
					IsActive:  true,
					SortOrder: 1,
				},
				{
					ID:        uuid.NewString(),
					Topic:     "Ganti HP / Perangkat",
					Keywords:  "hp,perangkat,device,ganti,pindah,unbind,reset device",
					Answer:    "Demi keamanan, 1 akun DMB terikat pada 1 perangkat smartphone.\n\nJika Anda berganti HP, silakan hubungi Contact Center Bank DMB untuk melakukan reset ikatan perangkat (Unbind Device), lalu lakukan aktivasi ulang dengan verifikasi OTP di HP baru.",
					IsActive:  true,
					SortOrder: 2,
				},
				{
					ID:        uuid.NewString(),
					Topic:     "Kredit & KKM",
					Keywords:  "kredit,pinjaman,kkm,kilat,mil,kmg,angsuran,hadir,pertemuan,tunggak",
					Answer:    "Anda dapat memantau seluruh fasilitas kredit melalui menu Kredit & Jadwal Angsuran di Beranda:\n• KKM Reguler & KILAT KKM: menampilkan tagihan mingguan, status bayar, dan kehadiran kelompok.\n• MIL & KMG: menampilkan sisa pokok, progres, serta jadwal angsuran.\n\nPengajuan kredit baru dapat dilakukan melalui menu Ajukan Kredit.",
					IsActive:  true,
					SortOrder: 3,
				},
				{
					ID:        uuid.NewString(),
					Topic:     "Deposito & Pencairan",
					Keywords:  "deposito,bilyet,cair,pencairan,aro,jatuh tempo,bunga",
					Answer:    "Untuk melihat rincian bilyet deposito, buka menu Deposito di Beranda lalu klik bilyet yang ingin dilihat.\n\nPengajuan pencairan deposito (Pokok, Bunga, atau Pokok & Bunga) dapat langsung diajukan dari halaman Detail Deposito dan akan ditindaklanjuti oleh petugas Bank DMB.",
					IsActive:  true,
					SortOrder: 4,
				},
				{
					ID:        uuid.NewString(),
					Topic:     "Mutasi & Saldo",
					Keywords:  "mutasi,saldo,rekening,transaksi,riwayat,tabungan",
					Answer:    "• Informasi Saldo: menampilkan ringkasan saldo seluruh rekening tabungan aktif (dapat diintip/disembunyikan).\n• Mutasi: menampilkan riwayat transaksi Tabungan, Deposito, maupun Pinjaman per rekening dengan rentang maksimal 31 hari.",
					IsActive:  true,
					SortOrder: 5,
				},
				{
					ID:        uuid.NewString(),
					Topic:     "Status Pengajuan",
					Keywords:  "pengajuan,ajukan,status,diajukan,proses,selesai",
					Answer:    "Seluruh pengajuan produk (Kredit, Deposito, Tabungan, dan Pencairan Deposito) dapat dipantau di menu Status Pengajuan di Beranda:\n• Diajukan: menunggu peninjauan petugas\n• Diproses: sedang ditindaklanjuti / dihubungi petugas\n• Selesai: proses tindak lanjut telah selesai",
					IsActive:  true,
					SortOrder: 6,
				},
			}
			_ = h.db.Create(&defaults).Error
		}
	})
}

func errResp(c *gin.Context, status int, msg string) {
	response.Error(c, status, http.StatusText(status), msg, nil)
}

// Mobile: GET /api/v1/helpdesk/faqs
func (h *Handler) ListActiveFAQs(c *gin.Context) {
	if h.db == nil {
		response.Success(c, "Daftar FAQ", []model.HelpdeskFAQ{})
		return
	}
	h.ensureReady()
	var faqs []model.HelpdeskFAQ
	if err := h.db.WithContext(c.Request.Context()).
		Where("is_active = ?", true).
		Order("sort_order asc, created_at asc").
		Find(&faqs).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal memuat FAQ")
		return
	}
	response.Success(c, "Daftar FAQ berhasil dimuat", faqs)
}

type createInquiryReq struct {
	Question     string `json:"question" binding:"required"`
	MatchedFAQID string `json:"matched_faq_id"`
	IsAnswered   bool   `json:"is_answered"`
}

// Mobile: POST /api/v1/helpdesk/inquiries
func (h *Handler) CreateInquiry(c *gin.Context) {
	if h.db == nil {
		response.Success(c, "Pertanyaan dicatat", nil)
		return
	}
	h.ensureReady()
	var req createInquiryReq
	if err := c.ShouldBindJSON(&req); err != nil {
		errResp(c, http.StatusBadRequest, "Pertanyaan wajib diisi")
		return
	}
	q := strings.TrimSpace(req.Question)
	if q == "" {
		errResp(c, http.StatusBadRequest, "Pertanyaan tidak boleh kosong")
		return
	}
	if len(q) > 1000 {
		q = q[:1000]
	}

	userID := c.GetString("user_id")
	var user model.User
	if userID != "" {
		_ = h.db.WithContext(c.Request.Context()).Where("id = ?", userID).First(&user).Error
	}

	status := "OPEN"
	if req.IsAnswered {
		status = "RESOLVED"
	}
	inq := model.HelpdeskInquiry{
		ID:           uuid.NewString(),
		UserID:       userID,
		CIF:          user.CIF,
		FullName:     user.FullName,
		PhoneNumber:  user.PhoneNumber,
		Question:     q,
		MatchedFAQID: strings.TrimSpace(req.MatchedFAQID),
		IsAnswered:   req.IsAnswered,
		Status:       status,
	}
	if err := h.db.WithContext(c.Request.Context()).Create(&inq).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal menyimpan pertanyaan")
		return
	}
	response.Success(c, "Pertanyaan berhasil dicatat", inq)
}

// Admin: GET /api/v1/admin/helpdesk/faqs
func (h *Handler) AdminListFAQs(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	var faqs []model.HelpdeskFAQ
	if err := h.db.WithContext(c.Request.Context()).
		Order("sort_order asc, created_at asc").
		Find(&faqs).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal memuat FAQ")
		return
	}
	response.Success(c, "Daftar FAQ berhasil dimuat", faqs)
}

type faqPayload struct {
	Topic     string `json:"topic" binding:"required"`
	Keywords  string `json:"keywords" binding:"required"`
	Answer    string `json:"answer" binding:"required"`
	IsActive  *bool  `json:"is_active"`
	SortOrder int    `json:"sort_order"`
}

// Admin: POST /api/v1/admin/helpdesk/faqs
func (h *Handler) AdminCreateFAQ(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	var req faqPayload
	if err := c.ShouldBindJSON(&req); err != nil {
		errResp(c, http.StatusBadRequest, "Topik, kata kunci, dan jawaban wajib diisi")
		return
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	faq := model.HelpdeskFAQ{
		ID:        uuid.NewString(),
		Topic:     strings.TrimSpace(req.Topic),
		Keywords:  strings.TrimSpace(req.Keywords),
		Answer:    strings.TrimSpace(req.Answer),
		IsActive:  active,
		SortOrder: req.SortOrder,
	}
	if err := h.db.WithContext(c.Request.Context()).Create(&faq).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal menambah FAQ")
		return
	}
	response.Success(c, "FAQ berhasil ditambahkan", faq)
}

type faqImportReq struct {
	Items []faqPayload `json:"items" binding:"required"`
}

// Admin: POST /api/v1/admin/helpdesk/faqs/import
func (h *Handler) AdminImportFAQs(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	var req faqImportReq
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Items) == 0 {
		errResp(c, http.StatusBadRequest, "Daftar FAQ tidak boleh kosong")
		return
	}
	if len(req.Items) > 500 {
		errResp(c, http.StatusBadRequest, "Maksimal 500 baris FAQ per unggahan")
		return
	}
	var created []model.HelpdeskFAQ
	for i, item := range req.Items {
		topic := strings.TrimSpace(item.Topic)
		keywords := strings.TrimSpace(item.Keywords)
		answer := strings.TrimSpace(item.Answer)
		if topic == "" || answer == "" {
			continue
		}
		if keywords == "" {
			keywords = strings.ToLower(topic)
		}
		active := true
		if item.IsActive != nil {
			active = *item.IsActive
		}
		sortOrder := item.SortOrder
		if sortOrder == 0 {
			sortOrder = i + 1
		}
		created = append(created, model.HelpdeskFAQ{
			ID:        uuid.NewString(),
			Topic:     topic,
			Keywords:  keywords,
			Answer:    answer,
			IsActive:  active,
			SortOrder: sortOrder,
		})
	}
	if len(created) == 0 {
		errResp(c, http.StatusBadRequest, "Tidak ada baris FAQ valid (wajib ada Topik & Jawaban)")
		return
	}
	if err := h.db.WithContext(c.Request.Context()).Create(&created).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal mengimpor FAQ")
		return
	}
	response.Success(c, "FAQ berhasil diimpor", gin.H{
		"imported": len(created),
		"items":    created,
	})
}

// Admin: PUT /api/v1/admin/helpdesk/faqs/:id
func (h *Handler) AdminUpdateFAQ(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	id := c.Param("id")
	var faq model.HelpdeskFAQ
	if err := h.db.WithContext(c.Request.Context()).Where("id = ?", id).First(&faq).Error; err != nil {
		errResp(c, http.StatusNotFound, "FAQ tidak ditemukan")
		return
	}
	var req faqPayload
	if err := c.ShouldBindJSON(&req); err != nil {
		errResp(c, http.StatusBadRequest, "Topik, kata kunci, dan jawaban wajib diisi")
		return
	}
	faq.Topic = strings.TrimSpace(req.Topic)
	faq.Keywords = strings.TrimSpace(req.Keywords)
	faq.Answer = strings.TrimSpace(req.Answer)
	faq.SortOrder = req.SortOrder
	if req.IsActive != nil {
		faq.IsActive = *req.IsActive
	}
	if err := h.db.WithContext(c.Request.Context()).Save(&faq).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal memperbarui FAQ")
		return
	}
	response.Success(c, "FAQ berhasil diperbarui", faq)
}

// Admin: DELETE /api/v1/admin/helpdesk/faqs/:id
func (h *Handler) AdminDeleteFAQ(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	id := c.Param("id")
	if err := h.db.WithContext(c.Request.Context()).Delete(&model.HelpdeskFAQ{}, "id = ?", id).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal menghapus FAQ")
		return
	}
	response.Success(c, "FAQ berhasil dihapus", nil)
}

// Admin: GET /api/v1/admin/helpdesk/inquiries
func (h *Handler) AdminListInquiries(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	var items []model.HelpdeskInquiry
	q := h.db.WithContext(c.Request.Context()).Order("created_at desc").Limit(200)
	if filter := strings.ToUpper(strings.TrimSpace(c.Query("status"))); filter != "" && filter != "ALL" {
		q = q.Where("status = ?", filter)
	}
	if err := q.Find(&items).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal memuat pertanyaan nasabah")
		return
	}
	response.Success(c, "Daftar pertanyaan nasabah berhasil dimuat", items)
}

// Admin: PUT /api/v1/admin/helpdesk/inquiries/:id
func (h *Handler) AdminResolveInquiry(c *gin.Context) {
	if h.db == nil {
		errResp(c, http.StatusServiceUnavailable, "Database tidak tersedia")
		return
	}
	h.ensureReady()
	id := c.Param("id")
	var body struct {
		Status string `json:"status"`
	}
	_ = c.ShouldBindJSON(&body)
	status := strings.ToUpper(strings.TrimSpace(body.Status))
	if status != "OPEN" && status != "RESOLVED" {
		status = "RESOLVED"
	}
	if err := h.db.WithContext(c.Request.Context()).
		Model(&model.HelpdeskInquiry{}).
		Where("id = ?", id).
		Update("status", status).Error; err != nil {
		errResp(c, http.StatusInternalServerError, "Gagal memperbarui status pertanyaan")
		return
	}
	response.Success(c, "Status pertanyaan diperbarui", nil)
}
