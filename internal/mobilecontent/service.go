package mobilecontent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/mail"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/pkg/reqctx"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type Values map[string]string

const (
	StatusDraft     = "DRAFT"
	StatusPending   = "PENDING_APPROVAL"
	StatusPublished = "PUBLISHED"
	StatusArchived  = "ARCHIVED"
)

var (
	ErrInvalid      = errors.New("konten tidak valid")
	ErrNotFound     = errors.New("revisi konten tidak ditemukan")
	ErrState        = errors.New("status revisi tidak memungkinkan tindakan ini")
	ErrMakerChecker = errors.New("persetujuan harus dilakukan petugas yang berbeda dari pembuat dan pengaju (maker-checker)")
)

type Revision struct {
	ID               string     `json:"id" gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	VersionNumber    int        `json:"version_number" gorm:"column:version_number"`
	Status           string     `json:"status" gorm:"column:status"`
	Content          string     `json:"-" gorm:"column:content;type:jsonb"`
	Note             string     `json:"note" gorm:"column:note"`
	SourceRevisionID *string    `json:"source_revision_id" gorm:"column:source_revision_id"`
	CreatedBy        string     `json:"created_by" gorm:"column:created_by"`
	CreatedByName    string     `json:"created_by_name" gorm:"column:created_by_name"`
	CreatedAt        time.Time  `json:"created_at" gorm:"column:created_at;autoCreateTime:false;default:now()"`
	UpdatedAt        time.Time  `json:"updated_at" gorm:"column:updated_at;autoUpdateTime:false;default:now()"`
	SubmittedBy      *string    `json:"submitted_by" gorm:"column:submitted_by"`
	SubmittedByName  *string    `json:"submitted_by_name" gorm:"column:submitted_by_name"`
	SubmittedAt      *time.Time `json:"submitted_at" gorm:"column:submitted_at"`
	PublishedBy      *string    `json:"published_by" gorm:"column:published_by"`
	PublishedByName  *string    `json:"published_by_name" gorm:"column:published_by_name"`
	PublishedAt      *time.Time `json:"published_at" gorm:"column:published_at"`
}

func (Revision) TableName() string { return "mobile_content_revisions" }

type View struct {
	Revision
	Values Values `json:"values"`
}

func (r *Revision) view() (*View, error) {
	v := Values{}
	if err := json.Unmarshal([]byte(r.Content), &v); err != nil {
		return nil, fmt.Errorf("isi revisi %d tidak dapat dibaca: %w", r.VersionNumber, err)
	}
	return &View{Revision: *r, Values: v}, nil
}

var (
	phonePattern = regexp.MustCompile(`^[0-9+()\- ]{3,20}$`)
	uploadPath   = regexp.MustCompile(`^/admin/(uploads|images)/[A-Za-z0-9_\-]+\.(png|jpg|jpeg|webp)$`)
)

func ValidImage(v string) bool {
	if v == "" {
		return true
	}
	if uploadPath.MatchString(v) {
		return true
	}
	u, err := url.Parse(v)
	return err == nil && u.Scheme == "https" && u.Host != "" && !strings.ContainsAny(v, "\"'<> \\")
}

func ValidateValue(f *Field, v string) error {
	bad := func(msg string) error { return fmt.Errorf("%w: %s (%s): %s", ErrInvalid, f.Label, f.Key, msg) }
	if !utf8.ValidString(v) {
		return bad("bukan teks UTF-8 yang valid")
	}
	if utf8.RuneCountInString(v) > f.Max {
		return bad(fmt.Sprintf("maksimal %d karakter", f.Max))
	}
	for _, r := range v {
		if r < 0x20 && !(r == '\n' && f.Type == TypeMultiline) {
			return bad("berisi karakter kontrol")
		}
		if r == '<' || r == '>' {
			return bad("tidak boleh berisi markup (< >)")
		}
	}
	if f.Required && strings.TrimSpace(v) == "" && f.Type != TypeImage {
		return bad("wajib diisi")
	}
	switch f.Type {
	case TypeImage:
		if !ValidImage(v) {
			return bad("gambar harus diunggah melalui backoffice atau URL https://")
		}
	case TypePhone:
		if !phonePattern.MatchString(v) {
			return bad("hanya angka, spasi, +, -, ( )")
		}
	case TypeEmail:
		if a, err := mail.ParseAddress(v); err != nil || a.Address != v {
			return bad("alamat email tidak valid")
		}
	case TypeBool:
		if v != "true" && v != "false" {
			return bad("harus true atau false")
		}
	case TypeEnum:
		ok := false
		for _, o := range f.Options {
			ok = ok || o.Value == v
		}
		if !ok {
			return bad("pilihan tidak dikenal")
		}
	}
	return nil
}

func Normalize(in, base Values) (Values, error) {
	out := Values{}
	for k, v := range in {
		f, ok := FieldByKey(k)
		if !ok {
			return nil, fmt.Errorf("%w: elemen %q tidak dikenal aplikasi", ErrInvalid, k)
		}
		if f.Type == TypeMultiline {
			v = strings.ReplaceAll(strings.TrimSpace(v), "\r\n", "\n")
		} else {
			v = strings.TrimSpace(v)
		}
		out[k] = v
	}
	for _, f := range Fields {
		if _, ok := out[f.Key]; !ok {
			out[f.Key] = base[f.Key]
		}
		if err := ValidateValue(fieldIndex[f.Key], out[f.Key]); err != nil {
			return nil, err
		}
	}
	return out, nil
}

type Service struct {
	db  *gorm.DB
	now func() time.Time
}

func NewService(db *gorm.DB) *Service {
	return &Service{db: db, now: func() time.Time { return time.Now().UTC() }}
}

type actor struct{ id, name string }

func actorOf(ctx context.Context) (actor, error) {
	if a, ok := reqctx.AdminFrom(ctx); ok {
		return actor{a.ID, a.Username + " (" + a.Role + ")"}, nil
	}
	return actor{}, fmt.Errorf("%w: petugas tidak dikenal", ErrInvalid)
}

func (s *Service) baseline(ctx context.Context, db *gorm.DB) (Values, error) {
	var row map[string]interface{}
	if err := db.WithContext(ctx).Table("app_configs").Where("id = ?", "DEFAULT").Take(&row).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			row = map[string]interface{}{}
		} else {
			return nil, err
		}
	}
	str := func(col string) string {
		if v, ok := row[col].(string); ok {
			return strings.TrimSpace(v)
		}
		return ""
	}
	out := Values{}
	for _, f := range Fields {
		v := ""
		if col, ok := legacyColumns[f.Key]; ok {
			v = str(col)
			if f.Key == "login.title" && v == "" {
				v = str("welcome_title")
			}
			if f.Key == "login.subtitle" && v == "" {
				v = str("welcome_subtitle")
			}
		}
		if v == "" || ValidateValue(&f, v) != nil {
			v = f.Default
		}
		out[f.Key] = v
	}
	return out, nil
}

func (s *Service) published(ctx context.Context, db *gorm.DB) (*View, error) {
	var r Revision
	err := db.WithContext(ctx).Where("status = ?", StatusPublished).Order("version_number DESC").First(&r).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return r.view()
}

func (s *Service) Live(ctx context.Context) (Values, int, *time.Time, error) {
	if s.db == nil {
		return nil, 0, nil, errors.New("database tidak tersedia")
	}
	base, err := s.baseline(ctx, s.db)
	if err != nil {
		return nil, 0, nil, err
	}
	pub, err := s.published(ctx, s.db)
	if err != nil || pub == nil {
		return base, 0, nil, err
	}
	out := Values{}
	for _, f := range Fields {
		v, ok := pub.Values[f.Key]
		if !ok || ValidateValue(&f, v) != nil {
			v = base[f.Key]
		}
		out[f.Key] = v
	}
	return out, pub.VersionNumber, pub.PublishedAt, nil
}

type State struct {
	Live        Values     `json:"live"`
	LiveVersion int        `json:"live_version"`
	PublishedAt *time.Time `json:"published_at"`
	Published   *View      `json:"published"`
	Open        *View      `json:"open"` // draft or pending approval
}

func (s *Service) open(ctx context.Context, db *gorm.DB) (*View, error) {
	var r Revision
	err := db.WithContext(ctx).Where("status IN ?", []string{StatusDraft, StatusPending}).First(&r).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return r.view()
}

func (s *Service) Current(ctx context.Context) (*State, error) {
	live, ver, at, err := s.Live(ctx)
	if err != nil {
		return nil, err
	}
	st := &State{Live: live, LiveVersion: ver, PublishedAt: at}
	if st.Published, err = s.published(ctx, s.db); err != nil {
		return nil, err
	}
	if st.Open, err = s.open(ctx, s.db); err != nil {
		return nil, err
	}
	return st, nil
}

func (s *Service) History(ctx context.Context, limit int) ([]View, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var rs []Revision
	if err := s.db.WithContext(ctx).Order("version_number DESC").Limit(limit).Find(&rs).Error; err != nil {
		return nil, err
	}
	out := make([]View, 0, len(rs))
	for i := range rs {
		v, err := rs[i].view()
		if err != nil {
			return nil, err
		}
		out = append(out, *v)
	}
	return out, nil
}

func lock(tx *gorm.DB) error {
	return tx.Exec("SELECT pg_advisory_xact_lock(hashtext('mobile-content'))").Error
}

func changedKeys(a, b Values) []string {
	var out []string
	for _, f := range Fields {
		if a[f.Key] != b[f.Key] {
			out = append(out, f.Key)
		}
	}
	sort.Strings(out)
	return out
}

func changedDiffs(a, b Values) string {
	var out []string
	for _, f := range Fields {
		oldVal, newVal := a[f.Key], b[f.Key]
		if oldVal != newVal {
			if len(oldVal) > 40 {
				oldVal = oldVal[:40] + "..."
			}
			if len(newVal) > 40 {
				newVal = newVal[:40] + "..."
			}
			out = append(out, fmt.Sprintf("%s: %q -> %q", f.Key, oldVal, newVal))
		}
	}
	sort.Strings(out)
	if len(out) == 0 {
		return "tidak ada perubahan"
	}
	return strings.Join(out, "; ")
}

func (s *Service) auditTx(ctx context.Context, tx *gorm.DB, action string, ver int, details string) {
	audit.Record(ctx, tx, "ADMIN", "", "", action, fmt.Sprintf("konten aplikasi v%d", ver), "SUCCESS", "WEB-BACKOFFICE", details)
}

func (s *Service) SaveDraft(ctx context.Context, in Values, note string, source *string) (*View, error) {
	a, err := actorOf(ctx)
	if err != nil {
		return nil, err
	}
	var out *View
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lock(tx); err != nil {
			return err
		}
		open, err := s.open(ctx, tx)
		if err != nil {
			return err
		}
		if open != nil && open.Status == StatusPending {
			return fmt.Errorf("%w: ada revisi yang menunggu persetujuan; setujui atau kembalikan dulu", ErrState)
		}
		base := Values{}
		if open != nil {
			base = open.Values
		} else {
			live, _, _, err := s.Live(ctx)
			if err != nil {
				return err
			}
			base = live
		}
		vals, err := Normalize(in, base)
		if err != nil {
			return err
		}
		raw, _ := json.Marshal(vals)
		var r Revision
		if open == nil {
			var maxNo int
			if err := tx.Model(&Revision{}).Select("COALESCE(MAX(version_number),0)").Scan(&maxNo).Error; err != nil {
				return err
			}
			r = Revision{VersionNumber: maxNo + 1, Status: StatusDraft, Content: string(raw), Note: strings.TrimSpace(note),
				SourceRevisionID: source, CreatedBy: a.id, CreatedByName: a.name, CreatedAt: s.now(), UpdatedAt: s.now()}
			if err := tx.Create(&r).Error; err != nil {
				return err
			}
		} else {
			if err := tx.Model(&Revision{}).Where("id = ?", open.ID).Updates(map[string]interface{}{
				"content": string(raw), "note": strings.TrimSpace(note), "source_revision_id": source, "updated_at": s.now(),
			}).Error; err != nil {
				return err
			}
			if err := tx.Where("id = ?", open.ID).First(&r).Error; err != nil {
				return err
			}
		}
		s.auditTx(ctx, tx, "MOBILE_CONTENT_DRAFT_SAVED", r.VersionNumber,
			fmt.Sprintf("Draf konten v%d disimpan (%s): %s", r.VersionNumber, a.name, changedDiffs(base, vals)))
		out, err = r.view()
		return err
	})
	return out, err
}

func (s *Service) lockRevision(ctx context.Context, tx *gorm.DB, id string) (*Revision, error) {
	var r Revision
	err := tx.WithContext(ctx).Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", id).First(&r).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil && strings.Contains(err.Error(), "invalid input syntax for type uuid") {
		return nil, ErrNotFound
	}
	return &r, err
}

func (s *Service) Submit(ctx context.Context, id string) (*View, error) {
	a, err := actorOf(ctx)
	if err != nil {
		return nil, err
	}
	var out *View
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lock(tx); err != nil {
			return err
		}
		r, err := s.lockRevision(ctx, tx, id)
		if err != nil {
			return err
		}
		if r.Status != StatusDraft {
			return fmt.Errorf("%w: hanya draf yang dapat diajukan", ErrState)
		}
		v, err := r.view()
		if err != nil {
			return err
		}
		if _, err := Normalize(v.Values, Values{}); err != nil {
			return err
		}
		now := s.now()
		if err := tx.Model(&Revision{}).Where("id = ?", r.ID).Updates(map[string]interface{}{
			"status": StatusPending, "submitted_by": a.id, "submitted_by_name": a.name, "submitted_at": now, "updated_at": now,
		}).Error; err != nil {
			return err
		}
		s.auditTx(ctx, tx, "MOBILE_CONTENT_SUBMITTED", r.VersionNumber, fmt.Sprintf("Konten v%d diajukan untuk persetujuan oleh %s", r.VersionNumber, a.name))
		if err := tx.Where("id = ?", r.ID).First(r).Error; err != nil {
			return err
		}
		out, err = r.view()
		return err
	})
	return out, err
}

func (s *Service) Reject(ctx context.Context, id, reason string) (*View, error) {
	a, err := actorOf(ctx)
	if err != nil {
		return nil, err
	}
	reason = strings.TrimSpace(reason)
	if reason == "" || utf8.RuneCountInString(reason) > 500 {
		return nil, fmt.Errorf("%w: alasan wajib diisi (maks. 500 karakter)", ErrInvalid)
	}
	var out *View
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lock(tx); err != nil {
			return err
		}
		r, err := s.lockRevision(ctx, tx, id)
		if err != nil {
			return err
		}
		if r.Status != StatusPending {
			return fmt.Errorf("%w: hanya revisi yang menunggu persetujuan yang dapat dikembalikan", ErrState)
		}
		if err := tx.Model(&Revision{}).Where("id = ?", r.ID).Updates(map[string]interface{}{
			"status": StatusDraft, "submitted_by": nil, "submitted_by_name": nil, "submitted_at": nil, "updated_at": s.now(),
		}).Error; err != nil {
			return err
		}
		s.auditTx(ctx, tx, "MOBILE_CONTENT_REJECTED", r.VersionNumber, fmt.Sprintf("Konten v%d dikembalikan ke draf oleh %s: %s", r.VersionNumber, a.name, reason))
		if err := tx.Where("id = ?", r.ID).First(r).Error; err != nil {
			return err
		}
		out, err = r.view()
		return err
	})
	return out, err
}

func (s *Service) Approve(ctx context.Context, id string) (*View, error) {
	a, err := actorOf(ctx)
	if err != nil {
		return nil, err
	}
	var out *View
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lock(tx); err != nil {
			return err
		}
		r, err := s.lockRevision(ctx, tx, id)
		if err != nil {
			return err
		}
		if r.Status != StatusPending {
			return fmt.Errorf("%w: hanya revisi yang menunggu persetujuan yang dapat dipublikasikan", ErrState)
		}
		if a.id == r.CreatedBy || (r.SubmittedBy != nil && a.id == *r.SubmittedBy) {
			return ErrMakerChecker
		}
		v, err := r.view()
		if err != nil {
			return err
		}
		vals, err := Normalize(v.Values, Values{})
		if err != nil {
			return err
		}
		prevLive, _, _, _ := s.Live(ctx)
		now := s.now()
		if err := tx.Model(&Revision{}).Where("status = ?", StatusPublished).Updates(map[string]interface{}{"status": StatusArchived, "updated_at": now}).Error; err != nil {
			return err
		}
		if err := tx.Model(&Revision{}).Where("id = ?", r.ID).Updates(map[string]interface{}{
			"status": StatusPublished, "published_by": a.id, "published_by_name": a.name, "published_at": now, "updated_at": now,
		}).Error; err != nil {
			return err
		}
		upd := map[string]interface{}{"content_version": r.VersionNumber, "updated_at": now}
		for k, col := range legacyColumns {
			upd[col] = vals[k]
		}
		if res := tx.Table("app_configs").Where("id = ?", "DEFAULT").Updates(upd); res.Error != nil {
			return res.Error
		}
		s.auditTx(ctx, tx, "MOBILE_CONTENT_PUBLISHED", r.VersionNumber,
			fmt.Sprintf("Konten v%d dipublikasikan oleh %s (dibuat %s): %s", r.VersionNumber, a.name, r.CreatedByName, changedDiffs(prevLive, vals)))
		if err := tx.Where("id = ?", r.ID).First(r).Error; err != nil {
			return err
		}
		out, err = r.view()
		return err
	})
	return out, err
}

func (s *Service) Rollback(ctx context.Context, revisionID string) (*View, error) {
	var src Revision
	if err := s.db.WithContext(ctx).Where("id = ?", revisionID).First(&src).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) || strings.Contains(err.Error(), "uuid") {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if src.Status == StatusDraft || src.Status == StatusPending {
		return nil, fmt.Errorf("%w: pilih revisi yang pernah dipublikasikan", ErrState)
	}
	v, err := src.view()
	if err != nil {
		return nil, err
	}
	keep := Values{}
	for k, val := range v.Values {
		if _, ok := FieldByKey(k); ok {
			keep[k] = val
		}
	}
	id := src.ID
	return s.SaveDraft(ctx, keep, fmt.Sprintf("Rollback ke versi %d", src.VersionNumber), &id)
}

func (s *Service) DiscardDraft(ctx context.Context, draftID string) error {
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Where("id = ? AND status = ?", draftID, StatusDraft).Delete(&Revision{})
		if res.Error != nil {
			if strings.Contains(res.Error.Error(), "uuid") {
				return ErrNotFound
			}
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrNotFound
		}
		audit.Record(ctx, tx, "ADMIN", "", "", "MOBILE_CONTENT_DRAFT_DISCARDED", "konten aplikasi", "SUCCESS", "WEB-BACKOFFICE", "Draf konten dibuang")
		return nil
	})
}
