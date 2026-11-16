package legaldoc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/pkg/reqctx"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrNoActiveVersion   = errors.New("Syarat dan Ketentuan layanan belum tersedia. Silakan coba beberapa saat lagi")
	ErrConsentRequired   = errors.New("Anda perlu membaca dan menyetujui Syarat dan Ketentuan Layanan Mobile Banking versi terbaru sebelum melanjutkan")
	ErrVersionNotActive  = errors.New("versi Syarat dan Ketentuan yang disetujui bukan versi yang sedang berlaku. Silakan muat ulang dokumen")
	ErrInvalidAcceptance = errors.New("bukti persetujuan Syarat dan Ketentuan tidak valid atau sudah kedaluwarsa. Silakan setujui kembali")
	ErrNotFound          = errors.New("dokumen tidak ditemukan")
	ErrInvalidState      = errors.New("status dokumen tidak memungkinkan tindakan ini")
	ErrMakerChecker      = errors.New("persetujuan harus dilakukan petugas yang berbeda dari pembuat dan pengaju dokumen (maker-checker)")
	errDBUnavailable     = errors.New("database tidak tersedia")
)

// PreLoginValidity is how long a consent given on the device before login may be
// linked to the customer who then logs in / activates on that device.
const PreLoginValidity = 24 * time.Hour

// preLoginReuseWindow: repeated submissions from the same device within this window
// return the same record (duplicate tap / retry), later ones create a new record.
const preLoginReuseWindow = 10 * time.Minute

// RenderMeta is the metadata printed on a PDF rendition.
type RenderMeta struct {
	VersionNumber  int
	DocumentNumber string
	PublishedAt    *time.Time
	EffectiveFrom  *time.Time
	Draft          bool
	GeneratedAt    time.Time
}

// Renderer turns content into PDF bytes (implemented by package pdfdoc).
type Renderer func(*Content, RenderMeta) ([]byte, error)

// Actor identifies the officer performing an action.
type Actor struct {
	ID   string
	Name string
}

// ActorFromContext returns the authenticated officer.
func ActorFromContext(ctx context.Context) (Actor, bool) {
	a, ok := reqctx.AdminFrom(ctx)
	if !ok {
		return Actor{}, false
	}
	return Actor{ID: a.ID, Name: a.Username + " (" + a.Role + ")"}, true
}

// ClientMeta is audit metadata of the consenting client.
type ClientMeta struct {
	IP        string
	UserAgent string
}

// Service implements versioning, publication and consent.
type Service struct {
	db     *gorm.DB
	files  FileStore
	render Renderer
	now    func() time.Time
}

func NewService(db *gorm.DB, files FileStore, render Renderer) *Service {
	return &Service{db: db, files: files, render: render, now: func() time.Time { return time.Now().UTC() }}
}

// SetClock replaces the clock (tests).
func (s *Service) SetClock(now func() time.Time) { s.now = now }

func trimTo(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

// ---------------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------------

func (s *Service) activeTx(ctx context.Context, db *gorm.DB) (*Version, error) {
	if db == nil {
		return nil, errDBUnavailable
	}
	var v Version
	err := db.WithContext(ctx).
		Where("document_id = ? AND status = ? AND effective_from <= ?", DocMobileTerms, StatusPublished, s.now()).
		Order("effective_from DESC, version_number DESC").First(&v).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNoActiveVersion
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// Active returns the published version in force now, with its content.
func (s *Service) Active(ctx context.Context) (*Version, *Content, error) {
	v, err := s.activeTx(ctx, s.db)
	if err != nil {
		return nil, nil, err
	}
	c, err := v.ParsedContent()
	if err != nil {
		return nil, nil, err
	}
	return v, c, nil
}

// ParsedContent decodes the stored content.
func (v *Version) ParsedContent() (*Content, error) {
	var c Content
	if err := json.Unmarshal([]byte(v.Content), &c); err != nil {
		return nil, fmt.Errorf("isi dokumen tersimpan rusak: %w", err)
	}
	return &c, nil
}

// PublishedPDF returns the final PDF of a published or archived version (draft and
// pending versions are never served to customers).
func (s *Service) PublishedPDF(ctx context.Context, versionID string) (*Version, []byte, error) {
	v, err := s.version(ctx, s.db, versionID)
	if err != nil {
		return nil, nil, err
	}
	if (v.Status != StatusPublished && v.Status != StatusArchived) || v.PDFSHA256 == nil {
		return nil, nil, ErrNotFound
	}
	data, _, err := s.files.Get(ctx, *v.PDFSHA256)
	if err != nil {
		return nil, nil, err
	}
	return v, data, nil
}

func (s *Service) version(ctx context.Context, db *gorm.DB, id string) (*Version, error) {
	if db == nil {
		return nil, errDBUnavailable
	}
	if !validUUID(id) {
		return nil, ErrNotFound
	}
	var v Version
	err := db.WithContext(ctx).Where("id = ? AND document_id = ?", id, DocMobileTerms).First(&v).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &v, err
}

func validUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, r := range s {
		switch i {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		default:
			if !strings.ContainsRune("0123456789abcdefABCDEF", r) {
				return false
			}
		}
	}
	return true
}

// ---------------------------------------------------------------------------------
// Consent
// ---------------------------------------------------------------------------------

// AcceptPreLogin records consent given on a device before the customer is identified.
// Only the version in force can be accepted; the server sets the time.
func (s *Service) AcceptPreLogin(ctx context.Context, versionID, deviceID string, meta ClientMeta) (*Acceptance, error) {
	if s.db == nil {
		return nil, errDBUnavailable
	}
	deviceID = strings.TrimSpace(deviceID)
	if len(deviceID) < 8 || len(deviceID) > 128 {
		return nil, ErrInvalidAcceptance
	}
	var out *Acceptance
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT pg_advisory_xact_lock(hashtext(?))", "legal-consent:"+deviceID).Error; err != nil {
			return err
		}
		active, err := s.activeTx(ctx, tx)
		if err != nil {
			return err
		}
		if active.ID != versionID {
			return ErrVersionNotActive
		}
		var existing Acceptance
		// Reuse only a record that is not yet linked to a customer (a linked consent is
		// evidence for that customer only; the next customer on the device gets a new one).
		err = tx.Where("device_id = ? AND version_id = ? AND user_id IS NULL AND accepted_at > ?",
			deviceID, versionID, s.now().Add(-preLoginReuseWindow)).
			Where("NOT EXISTS (SELECT 1 FROM legal_acceptances l WHERE l.pre_login_acceptance_id = legal_acceptances.id)").
			Order("accepted_at DESC").First(&existing).Error
		if err == nil {
			out = &existing
			return nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		a := Acceptance{
			DocumentID: DocMobileTerms, VersionID: active.ID, VersionNumber: active.VersionNumber,
			DeviceID: deviceID, Channel: ChannelPreLogin, Status: "ACCEPTED", PDFSHA256: *active.PDFSHA256,
			AcceptedAt: s.now(), IPAddress: trimTo(meta.IP, 64), UserAgent: trimTo(meta.UserAgent, 255),
		}
		if err := tx.Create(&a).Error; err != nil {
			return err
		}
		out = &a
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// UserConsent reports whether the customer accepted the version in force.
func (s *Service) UserConsent(ctx context.Context, userID string) (bool, *Version, *Acceptance, error) {
	active, err := s.activeTx(ctx, s.db)
	if err != nil {
		return false, nil, nil, err
	}
	var a Acceptance
	err = s.db.WithContext(ctx).Where("version_id = ? AND user_id = ?", active.ID, userID).First(&a).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, active, nil, nil
	}
	if err != nil {
		return false, active, nil, err
	}
	return true, active, &a, nil
}

// RequireUserConsent fails with ErrConsentRequired when the customer has not accepted
// the version in force (used when refreshing a session).
func (s *Service) RequireUserConsent(ctx context.Context, userID string) error {
	ok, _, _, err := s.UserConsent(ctx, userID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrConsentRequired
	}
	return nil
}

func (s *Service) loadPreLogin(ctx context.Context, db *gorm.DB, deviceID, acceptanceID string, lock bool) (*Acceptance, *Version, error) {
	if !validUUID(acceptanceID) {
		return nil, nil, ErrInvalidAcceptance
	}
	active, err := s.activeTx(ctx, db)
	if err != nil {
		return nil, nil, err
	}
	q := db.WithContext(ctx)
	if lock {
		// legal_acceptances is append-only for the application role (no UPDATE privilege,
		// so no row lock): serialise linking of one device consent with an advisory lock.
		if err := q.Exec("SELECT pg_advisory_xact_lock(hashtext(?))", "legal-accept:"+acceptanceID).Error; err != nil {
			return nil, nil, err
		}
	}
	var a Acceptance
	if err := q.Where("id = ? AND channel = ? AND user_id IS NULL", acceptanceID, ChannelPreLogin).First(&a).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil, ErrInvalidAcceptance
		}
		return nil, nil, err
	}
	if a.DeviceID != deviceID || a.AcceptedAt.Before(s.now().Add(-PreLoginValidity)) {
		return nil, nil, ErrInvalidAcceptance
	}
	if a.VersionID != active.ID {
		return nil, nil, ErrConsentRequired
	}
	return &a, active, nil
}

// ValidatePreLogin checks, before an irreversible step (activation), that the device
// holds a valid consent for the version in force.
func (s *Service) ValidatePreLogin(ctx context.Context, deviceID, acceptanceID string) error {
	if strings.TrimSpace(acceptanceID) == "" {
		return ErrConsentRequired
	}
	_, _, err := s.loadPreLogin(ctx, s.db, deviceID, acceptanceID, false)
	return err
}

// EnsureUserConsent makes sure the customer has a consent record for the version in
// force. If not, the device's pre-login consent is linked to the customer through a new
// record (the pre-login record itself is never modified).
func (s *Service) EnsureUserConsent(ctx context.Context, userID, deviceID, acceptanceID, channel string, meta ClientMeta) error {
	if channel != ChannelLogin && channel != ChannelActivation {
		return fmt.Errorf("kanal persetujuan tidak dikenal: %s", channel)
	}
	ok, _, _, err := s.UserConsent(ctx, userID)
	if err != nil {
		return err
	}
	if ok {
		return nil
	}
	if strings.TrimSpace(acceptanceID) == "" {
		return ErrConsentRequired
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		pre, active, err := s.loadPreLogin(ctx, tx, deviceID, acceptanceID, true)
		if err != nil {
			return err
		}
		var already int64
		if err := tx.Model(&Acceptance{}).Where("version_id = ? AND user_id = ?", active.ID, userID).Count(&already).Error; err != nil {
			return err
		}
		if already > 0 {
			return nil
		}
		var linked int64
		if err := tx.Model(&Acceptance{}).Where("pre_login_acceptance_id = ?", pre.ID).Count(&linked).Error; err != nil {
			return err
		}
		if linked > 0 {
			return ErrInvalidAcceptance // one device consent is evidence for one customer only
		}
		uid := userID
		preID := pre.ID
		a := Acceptance{
			DocumentID: DocMobileTerms, VersionID: active.ID, VersionNumber: active.VersionNumber,
			UserID: &uid, DeviceID: deviceID, Channel: channel, Status: "ACCEPTED",
			PreLoginAcceptanceID: &preID, PDFSHA256: pre.PDFSHA256, AcceptedAt: s.now(),
			IPAddress: trimTo(meta.IP, 64), UserAgent: trimTo(meta.UserAgent, 255),
		}
		if err := tx.Create(&a).Error; err != nil {
			return err
		}
		audit.Record(ctx, tx, "NASABAH", userID, "", "TERMS_ACCEPTED", fmt.Sprintf("SK versi %d", active.VersionNumber), "SUCCESS", deviceID,
			fmt.Sprintf("Persetujuan Syarat dan Ketentuan versi %d tercatat (kanal %s, PDF %s…)", active.VersionNumber, channel, pre.PDFSHA256[:12]))
		return nil
	})
}

// AcceptanceFilter selects consent records for evidence queries.
type AcceptanceFilter struct {
	UserID    string
	VersionID string
	Limit     int
}

// ListAcceptances returns consent records (newest first).
func (s *Service) ListAcceptances(ctx context.Context, f AcceptanceFilter) ([]Acceptance, error) {
	q := s.db.WithContext(ctx).Where("document_id = ?", DocMobileTerms)
	if f.UserID != "" {
		if !validUUID(f.UserID) {
			return []Acceptance{}, nil
		}
		q = q.Where("user_id = ?", f.UserID)
	}
	if f.VersionID != "" {
		if !validUUID(f.VersionID) {
			return []Acceptance{}, nil
		}
		q = q.Where("version_id = ?", f.VersionID)
	}
	if f.Limit <= 0 || f.Limit > 500 {
		f.Limit = 100
	}
	var out []Acceptance
	err := q.Order("accepted_at DESC").Limit(f.Limit).Find(&out).Error
	return out, err
}

// ---------------------------------------------------------------------------------
// Back-office workflow (maker-checker)
// ---------------------------------------------------------------------------------

// VersionView is a version with derived flags for the back office.
type VersionView struct {
	Version
	IsActive bool     `json:"is_active"`
	Content  *Content `json:"content,omitempty"`
}

// ListVersions returns all versions, newest first.
func (s *Service) ListVersions(ctx context.Context) ([]VersionView, error) {
	var vs []Version
	if err := s.db.WithContext(ctx).Where("document_id = ?", DocMobileTerms).Order("version_number DESC").Find(&vs).Error; err != nil {
		return nil, err
	}
	activeID := ""
	if a, err := s.activeTx(ctx, s.db); err == nil {
		activeID = a.ID
	} else if !errors.Is(err, ErrNoActiveVersion) {
		return nil, err
	}
	out := make([]VersionView, 0, len(vs))
	for _, v := range vs {
		out = append(out, VersionView{Version: v, IsActive: v.ID == activeID})
	}
	return out, nil
}

// GetVersion returns one version with its content.
func (s *Service) GetVersion(ctx context.Context, id string) (*VersionView, error) {
	v, err := s.version(ctx, s.db, id)
	if err != nil {
		return nil, err
	}
	c, err := v.ParsedContent()
	if err != nil {
		return nil, err
	}
	view := &VersionView{Version: *v, Content: c}
	if a, err := s.activeTx(ctx, s.db); err == nil && a.ID == v.ID {
		view.IsActive = true
	}
	return view, nil
}

// DraftInput is the editable part of a draft.
type DraftInput struct {
	BaseVersionID  string
	Content        *Content
	ChangeSummary  string
	DocumentNumber string
}

func (s *Service) auditAdmin(ctx context.Context, db *gorm.DB, action string, v *Version, details string) {
	audit.Record(ctx, db, "ADMIN", "", "", action, fmt.Sprintf("SK versi %d", v.VersionNumber), "SUCCESS", "WEB-BACKOFFICE", details)
}

// CreateDraft starts a new version (copy of a base version or new content).
func (s *Service) CreateDraft(ctx context.Context, actor Actor, in DraftInput) (*Version, error) {
	if err := ValidDocumentNumber(in.DocumentNumber); err != nil {
		return nil, err
	}
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT pg_advisory_xact_lock(hashtext(?))", "legal-doc:"+DocMobileTerms).Error; err != nil {
			return err
		}
		var open int64
		if err := tx.Model(&Version{}).Where("document_id = ? AND status IN ?", DocMobileTerms, []string{StatusDraft, StatusPending}).Count(&open).Error; err != nil {
			return err
		}
		if open > 0 {
			return fmt.Errorf("%w: masih ada draf atau versi yang menunggu persetujuan", ErrInvalidState)
		}
		content := in.Content
		if content == nil {
			if in.BaseVersionID == "" {
				return fmt.Errorf("%w: isi dokumen atau versi dasar wajib diisi", ErrInvalidContent)
			}
			base, err := s.version(ctx, tx, in.BaseVersionID)
			if err != nil {
				return err
			}
			if content, err = base.ParsedContent(); err != nil {
				return err
			}
		}
		if err := content.Validate(); err != nil {
			return err
		}
		raw, _ := content.CanonicalJSON()
		sha, _ := content.SHA256()
		var maxNo int
		if err := tx.Model(&Version{}).Where("document_id = ?", DocMobileTerms).Select("COALESCE(MAX(version_number),0)").Scan(&maxNo).Error; err != nil {
			return err
		}
		v := Version{
			DocumentID: DocMobileTerms, VersionNumber: maxNo + 1, Status: StatusDraft,
			ChangeSummary: trimTo(strings.TrimSpace(in.ChangeSummary), 2000), Content: string(raw), ContentSHA256: sha,
			CreatedBy: actor.ID, CreatedByName: trimTo(actor.Name, 100), CreatedAt: s.now(), UpdatedAt: s.now(),
		}
		if dn := strings.TrimSpace(in.DocumentNumber); dn != "" {
			v.DocumentNumber = &dn
		}
		if err := tx.Create(&v).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_DRAFT_CREATED", &v, fmt.Sprintf("Draf SK versi %d dibuat (isi %s…)", v.VersionNumber, sha[:12]))
		out = &v
		return nil
	})
	return out, err
}

func (s *Service) lockVersion(ctx context.Context, tx *gorm.DB, id string) (*Version, error) {
	if !validUUID(id) {
		return nil, ErrNotFound
	}
	var v Version
	err := tx.WithContext(ctx).Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ? AND document_id = ?", id, DocMobileTerms).First(&v).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &v, err
}

// UpdateDraft changes a draft's content; any generated draft PDF is discarded.
func (s *Service) UpdateDraft(ctx context.Context, actor Actor, id string, in DraftInput) (*Version, error) {
	if in.Content == nil {
		return nil, fmt.Errorf("%w: isi dokumen wajib diisi", ErrInvalidContent)
	}
	if err := in.Content.Validate(); err != nil {
		return nil, err
	}
	if err := ValidDocumentNumber(in.DocumentNumber); err != nil {
		return nil, err
	}
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusDraft {
			return fmt.Errorf("%w: hanya draf yang dapat diubah; versi yang sudah diterbitkan tidak dapat diubah, buat draf baru", ErrInvalidState)
		}
		raw, _ := in.Content.CanonicalJSON()
		sha, _ := in.Content.SHA256()
		var dn *string
		if d := strings.TrimSpace(in.DocumentNumber); d != "" {
			dn = &d
		}
		upd := map[string]interface{}{
			"content": string(raw), "content_sha256": sha, "change_summary": trimTo(strings.TrimSpace(in.ChangeSummary), 2000),
			"document_number": dn, "draft_pdf_sha256": nil, "updated_at": s.now(),
		}
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(upd).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_DRAFT_UPDATED", v, fmt.Sprintf("Draf SK versi %d diubah (isi %s…)", v.VersionNumber, sha[:12]))
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}

// GenerateDraftPDF renders the draft PDF (marked DRAF) for review.
func (s *Service) GenerateDraftPDF(ctx context.Context, actor Actor, id string) (*Version, error) {
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusDraft {
			return fmt.Errorf("%w: PDF draf hanya dapat dibuat untuk versi berstatus DRAFT", ErrInvalidState)
		}
		c, err := v.ParsedContent()
		if err != nil {
			return err
		}
		if err := c.Validate(); err != nil {
			return err
		}
		raw, _ := c.CanonicalJSON()
		sha, _ := c.SHA256()
		dn := ""
		if v.DocumentNumber != nil {
			dn = *v.DocumentNumber
		}
		pdf, err := s.render(c, RenderMeta{VersionNumber: v.VersionNumber, DocumentNumber: dn, Draft: true, GeneratedAt: s.now()})
		if err != nil {
			return err
		}
		fileSHA, err := s.files.Put(ctx, tx, "application/pdf", pdf)
		if err != nil {
			return err
		}
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(map[string]interface{}{
			"content": string(raw), "content_sha256": sha, "draft_pdf_sha256": fileSHA, "updated_at": s.now(),
		}).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_DRAFT_PDF_GENERATED", v, fmt.Sprintf("PDF draf SK versi %d dibuat (PDF %s…, isi %s…)", v.VersionNumber, fileSHA[:12], sha[:12]))
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}

// AdminPDF returns the draft or final PDF of any version for officers.
func (s *Service) AdminPDF(ctx context.Context, id string, final bool) (*Version, []byte, error) {
	v, err := s.version(ctx, s.db, id)
	if err != nil {
		return nil, nil, err
	}
	sha := v.DraftPDFSHA256
	if final {
		sha = v.PDFSHA256
	}
	if sha == nil {
		return nil, nil, ErrNotFound
	}
	data, _, err := s.files.Get(ctx, *sha)
	if err != nil {
		return nil, nil, err
	}
	return v, data, nil
}

// Submit sends a reviewed draft for approval. effectiveFrom nil = upon approval.
func (s *Service) Submit(ctx context.Context, actor Actor, id string, effectiveFrom *time.Time) (*Version, error) {
	if effectiveFrom != nil && effectiveFrom.Before(s.now().Add(-time.Minute)) {
		return nil, fmt.Errorf("%w: tanggal mulai berlaku tidak boleh di masa lalu", ErrInvalidContent)
	}
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusDraft {
			return fmt.Errorf("%w: hanya draf yang dapat diajukan", ErrInvalidState)
		}
		if v.DraftPDFSHA256 == nil {
			return fmt.Errorf("%w: buat dan periksa PDF draf terlebih dahulu", ErrInvalidState)
		}
		upd := map[string]interface{}{"status": StatusPending, "submitted_by": actor.ID, "submitted_at": s.now(), "effective_from": effectiveFrom, "updated_at": s.now()}
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(upd).Error; err != nil {
			return err
		}
		when := "saat disetujui"
		if effectiveFrom != nil {
			when = effectiveFrom.UTC().Format(time.RFC3339)
		}
		s.auditAdmin(ctx, tx, "TERMS_SUBMITTED", v, fmt.Sprintf("SK versi %d diajukan untuk persetujuan (berlaku %s)", v.VersionNumber, when))
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}

// Reject returns a pending version to draft.
func (s *Service) Reject(ctx context.Context, actor Actor, id, reason string) (*Version, error) {
	reason = trimTo(strings.TrimSpace(reason), 500)
	if reason == "" {
		return nil, fmt.Errorf("%w: alasan penolakan wajib diisi", ErrInvalidContent)
	}
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusPending {
			return fmt.Errorf("%w: hanya versi yang menunggu persetujuan yang dapat ditolak", ErrInvalidState)
		}
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(map[string]interface{}{
			"status": StatusDraft, "submitted_by": nil, "submitted_at": nil, "effective_from": nil, "updated_at": s.now(),
		}).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_REJECTED", v, "SK versi "+fmt.Sprint(v.VersionNumber)+" dikembalikan ke draf: "+reason)
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}

// Approve publishes a pending version (checker ≠ maker and ≠ submitter). The final PDF
// is rendered with the publication metadata and stored; the version becomes immutable.
func (s *Service) Approve(ctx context.Context, actor Actor, id string) (*Version, error) {
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT pg_advisory_xact_lock(hashtext(?))", "legal-doc:"+DocMobileTerms).Error; err != nil {
			return err
		}
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusPending {
			return fmt.Errorf("%w: hanya versi yang menunggu persetujuan yang dapat diterbitkan", ErrInvalidState)
		}
		if actor.ID == "" || actor.ID == v.CreatedBy || (v.SubmittedBy != nil && actor.ID == *v.SubmittedBy) {
			return ErrMakerChecker
		}
		now := s.now()
		effective := now
		if v.EffectiveFrom != nil && v.EffectiveFrom.After(now) {
			effective = v.EffectiveFrom.UTC()
		}
		var latest Version
		err = tx.Where("document_id = ? AND status = ?", DocMobileTerms, StatusPublished).Order("effective_from DESC").First(&latest).Error
		if err == nil && latest.EffectiveFrom != nil && effective.Before(*latest.EffectiveFrom) {
			return fmt.Errorf("%w: tanggal berlaku harus setelah versi %d yang sudah dijadwalkan", ErrInvalidState, latest.VersionNumber)
		} else if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		c, err := v.ParsedContent()
		if err != nil {
			return err
		}
		sha, _ := c.SHA256()
		if sha != v.ContentSHA256 {
			return fmt.Errorf("%w: isi berubah setelah PDF draf dibuat; buat ulang PDF draf", ErrInvalidState)
		}
		dn := ""
		if v.DocumentNumber != nil {
			dn = *v.DocumentNumber
		}
		pdf, err := s.render(c, RenderMeta{VersionNumber: v.VersionNumber, DocumentNumber: dn, PublishedAt: &now, EffectiveFrom: &effective, GeneratedAt: now})
		if err != nil {
			return err
		}
		fileSHA, err := s.files.Put(ctx, tx, "application/pdf", pdf)
		if err != nil {
			return err
		}
		name := trimTo(actor.Name, 100)
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(map[string]interface{}{
			"status": StatusPublished, "pdf_sha256": fileSHA, "effective_from": effective, "published_at": now,
			"approved_by": actor.ID, "approved_by_name": name, "updated_at": now,
		}).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_PUBLISHED", v, fmt.Sprintf("SK versi %d diterbitkan; berlaku %s; PDF %s; isi %s",
			v.VersionNumber, effective.Format(time.RFC3339), fileSHA, sha))
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}

// Archive archives a published version that is no longer (or not yet) in force.
func (s *Service) Archive(ctx context.Context, actor Actor, id string) (*Version, error) {
	var out *Version
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT pg_advisory_xact_lock(hashtext(?))", "legal-doc:"+DocMobileTerms).Error; err != nil {
			return err
		}
		v, err := s.lockVersion(ctx, tx, id)
		if err != nil {
			return err
		}
		if v.Status != StatusPublished {
			return fmt.Errorf("%w: hanya versi terbit yang dapat diarsipkan", ErrInvalidState)
		}
		if active, err := s.activeTx(ctx, tx); err == nil && active.ID == v.ID {
			return fmt.Errorf("%w: versi yang sedang berlaku tidak dapat diarsipkan; terbitkan versi pengganti terlebih dahulu", ErrInvalidState)
		} else if err != nil && !errors.Is(err, ErrNoActiveVersion) {
			return err
		}
		if err := tx.Model(&Version{}).Where("id = ?", v.ID).Updates(map[string]interface{}{
			"status": StatusArchived, "archived_by": actor.ID, "archived_at": s.now(), "updated_at": s.now(),
		}).Error; err != nil {
			return err
		}
		s.auditAdmin(ctx, tx, "TERMS_ARCHIVED", v, fmt.Sprintf("SK versi %d diarsipkan", v.VersionNumber))
		out, err = s.version(ctx, tx, v.ID)
		return err
	})
	return out, err
}
