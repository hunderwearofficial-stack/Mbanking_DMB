package push

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/reqctx"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrValidation   = errors.New("data tidak valid")
	ErrNotFound     = errors.New("data tidak ditemukan")
	ErrState        = errors.New("status tidak memungkinkan tindakan ini")
	ErrMakerChecker = errors.New("persetujuan harus dilakukan petugas yang berbeda dari pembuat (maker-checker)")
	ErrDisabled     = errors.New("integrasi Firebase belum aktif. Aktifkan di menu Notifikasi → Integrasi Firebase")
)

const (
	StatusQueued       = "QUEUED"
	StatusAccepted     = "ACCEPTED" // accepted by FCM — not proof that the phone displayed it
	StatusFailed       = "FAILED"
	StatusInvalidToken = "INVALID_TOKEN"
)

const (
	CampaignDraft       = "DRAFT"
	CampaignPending     = "PENDING_APPROVAL"
	CampaignRejected    = "REJECTED"
	CampaignSending     = "SENDING"
	CampaignSent        = "SENT"
	CampaignPartial     = "PARTIAL"
	CampaignFailed      = "FAILED"
	CampaignNoRecipient = "NO_RECIPIENT"
)

const maxAttempts = 3

type Settings struct {
	ID                    string     `gorm:"column:id;primaryKey"`
	Enabled               bool       `gorm:"column:enabled"`
	ProjectID             *string    `gorm:"column:project_id"`
	ClientEmail           *string    `gorm:"column:client_email"`
	CredentialEnc         *string    `gorm:"column:credential_enc"`
	CredentialFingerprint *string    `gorm:"column:credential_fingerprint"`
	CredentialUpdatedBy   *string    `gorm:"column:credential_updated_by"`
	CredentialUpdatedAt   *time.Time `gorm:"column:credential_updated_at"`
	LastTestAt            *time.Time `gorm:"column:last_test_at"`
	LastTestOK            *bool      `gorm:"column:last_test_ok"`
	LastTestError         *string    `gorm:"column:last_test_error"`
	LastTestFingerprint   *string    `gorm:"column:last_test_fingerprint"`
	UpdatedBy             *string    `gorm:"column:updated_by"`
	UpdatedAt             time.Time  `gorm:"column:updated_at"`
}

func (Settings) TableName() string { return "push_settings" }

type Device struct {
	ID                string     `gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	UserID            string     `gorm:"column:user_id"`
	DeviceID          string     `gorm:"column:device_id"`
	Platform          string     `gorm:"column:platform"`
	TokenSHA256       string     `gorm:"column:token_sha256"`
	TokenEnc          string     `gorm:"column:token_enc"`
	IsActive          bool       `gorm:"column:is_active"`
	DeactivatedReason *string    `gorm:"column:deactivated_reason"`
	DeactivatedAt     *time.Time `gorm:"column:deactivated_at"`
	CreatedAt         time.Time  `gorm:"column:created_at;autoCreateTime:false;default:now()"`
	LastSeenAt        time.Time  `gorm:"column:last_seen_at;autoCreateTime:false;default:now()"`
}

func (Device) TableName() string { return "push_devices" }

type Campaign struct {
	ID                string     `json:"id" gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	Title             string     `json:"title" gorm:"column:title"`
	Body              string     `json:"body" gorm:"column:body"`
	Category          string     `json:"category" gorm:"column:category"`
	TargetType        string     `json:"target_type" gorm:"column:target_type"`
	TargetUserID      *string    `json:"target_user_id" gorm:"column:target_user_id"`
	Status            string     `json:"status" gorm:"column:status"`
	CreatedBy         string     `json:"created_by" gorm:"column:created_by"`
	CreatedByName     string     `json:"created_by_name" gorm:"column:created_by_name"`
	CreatedAt         time.Time  `json:"created_at" gorm:"column:created_at;autoCreateTime:false;default:now()"`
	SubmittedAt       *time.Time `json:"submitted_at" gorm:"column:submitted_at"`
	ApprovedBy        *string    `json:"approved_by" gorm:"column:approved_by"`
	ApprovedByName    *string    `json:"approved_by_name" gorm:"column:approved_by_name"`
	ApprovedAt        *time.Time `json:"approved_at" gorm:"column:approved_at"`
	RejectReason      *string    `json:"reject_reason" gorm:"column:reject_reason"`
	SendStartedAt     *time.Time `json:"send_started_at" gorm:"column:send_started_at"`
	SendFinishedAt    *time.Time `json:"send_finished_at" gorm:"column:send_finished_at"`
	TargetDevices     int        `json:"target_devices" gorm:"column:target_devices"`
	AcceptedCount     int        `json:"accepted_count" gorm:"column:accepted_count"`
	FailedCount       int        `json:"failed_count" gorm:"column:failed_count"`
	InvalidTokenCount int        `json:"invalid_token_count" gorm:"column:invalid_token_count"`
	LastError         *string    `json:"last_error" gorm:"column:last_error"`
}

func (Campaign) TableName() string { return "notification_campaigns" }

type Delivery struct {
	ID             string     `json:"id" gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	CampaignID     *string    `json:"campaign_id" gorm:"column:campaign_id"`
	NotificationID *string    `json:"notification_id" gorm:"column:notification_id"`
	UserID         string     `json:"user_id" gorm:"column:user_id"`
	DeviceID       string     `json:"device_id" gorm:"column:device_id"`
	Category       string     `json:"category" gorm:"column:category"`
	Status         string     `json:"status" gorm:"column:status"`
	Attempts       int        `json:"attempts" gorm:"column:attempts"`
	FCMMessageID   *string    `json:"fcm_message_id" gorm:"column:fcm_message_id"`
	ErrorCode      *string    `json:"error_code" gorm:"column:error_code"`
	ErrorMessage   *string    `json:"error_message" gorm:"column:error_message"`
	CreatedAt      time.Time  `json:"created_at" gorm:"column:created_at;autoCreateTime:false;default:now()"`
	UpdatedAt      time.Time  `json:"updated_at" gorm:"column:updated_at;autoUpdateTime:false;default:now()"`
	OpenedAt       *time.Time `json:"opened_at" gorm:"column:opened_at"`
}

func (Delivery) TableName() string { return "push_deliveries" }

type Service struct {
	db       *gorm.DB
	tokenURL string
	fcmBase  string
	backoff  func(attempt int) time.Duration

	mu     sync.Mutex
	client *Client
	fp     string
	wg     sync.WaitGroup
}

func NewService(db *gorm.DB) *Service {
	return &Service{db: db, backoff: func(a int) time.Duration { return time.Duration(a*a) * 500 * time.Millisecond }}
}

func (s *Service) SetEndpoints(tokenURL, fcmBase string, backoff func(int) time.Duration) {
	s.tokenURL, s.fcmBase = tokenURL, fcmBase
	if backoff != nil {
		s.backoff = backoff
	}
}

func (s *Service) Wait() { s.wg.Wait() }

func adminName(ctx context.Context) (id, name string, ok bool) {
	a, ok := reqctx.AdminFrom(ctx)
	if !ok {
		return "", "", false
	}
	return a.ID, a.Username + " (" + a.Role + ")", true
}

func (s *Service) auditAdmin(ctx context.Context, action, target, status, details string) {
	audit.Record(ctx, s.db, "ADMIN", "", "", action, target, status, "WEB-BACKOFFICE", details)
}

func hashToken(t string) string {
	sum := sha256.Sum256([]byte(t))
	return hex.EncodeToString(sum[:])
}

type SettingsView struct {
	Enabled               bool       `json:"enabled"`
	CredentialConfigured  bool       `json:"credential_configured"`
	ProjectID             string     `json:"project_id"`
	ClientEmail           string     `json:"client_email"`
	CredentialFingerprint string     `json:"credential_fingerprint"`
	CredentialUpdatedBy   string     `json:"credential_updated_by"`
	CredentialUpdatedAt   *time.Time `json:"credential_updated_at"`
	LastTestAt            *time.Time `json:"last_test_at"`
	LastTestOK            *bool      `json:"last_test_ok"`
	LastTestError         string     `json:"last_test_error"`
	TestedCurrent         bool       `json:"tested_current_credential"`
	ActiveDevices         int64      `json:"active_devices"`
	Last24h               struct {
		Accepted int64 `json:"accepted"`
		Failed   int64 `json:"failed"`
		Invalid  int64 `json:"invalid_token"`
	} `json:"last_24h"`
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func (s *Service) settings(ctx context.Context) (*Settings, error) {
	if s.db == nil {
		return nil, errors.New("database tidak tersedia")
	}
	var st Settings
	if err := s.db.WithContext(ctx).Where("id = ?", "DEFAULT").First(&st).Error; err != nil {
		return nil, err
	}
	return &st, nil
}

func (s *Service) GetSettings(ctx context.Context) (*SettingsView, error) {
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	v := &SettingsView{
		Enabled: st.Enabled, CredentialConfigured: st.CredentialEnc != nil, ProjectID: str(st.ProjectID),
		ClientEmail: str(st.ClientEmail), CredentialUpdatedBy: str(st.CredentialUpdatedBy), CredentialUpdatedAt: st.CredentialUpdatedAt,
		LastTestAt: st.LastTestAt, LastTestOK: st.LastTestOK, LastTestError: str(st.LastTestError),
	}
	if fp := str(st.CredentialFingerprint); len(fp) >= 12 {
		v.CredentialFingerprint = fp[:12]
	}
	v.TestedCurrent = st.LastTestOK != nil && *st.LastTestOK && st.CredentialFingerprint != nil && str(st.LastTestFingerprint) == *st.CredentialFingerprint
	s.db.WithContext(ctx).Model(&Device{}).Where("is_active").Count(&v.ActiveDevices)
	since := time.Now().Add(-24 * time.Hour)
	count := func(status string, dst *int64) {
		s.db.WithContext(ctx).Model(&Delivery{}).Where("status = ? AND updated_at > ?", status, since).Count(dst)
	}
	count(StatusAccepted, &v.Last24h.Accepted)
	count(StatusFailed, &v.Last24h.Failed)
	count(StatusInvalidToken, &v.Last24h.Invalid)
	return v, nil
}

func (s *Service) credential(st *Settings) (*Credential, error) {
	if st.CredentialEnc == nil {
		return nil, fmt.Errorf("%w: credential Firebase Admin belum diunggah", ErrState)
	}
	raw, err := crypto.Decrypt(*st.CredentialEnc)
	if err != nil {
		return nil, fmt.Errorf("credential Firebase tidak dapat didekripsi (periksa kunci enkripsi): %w", err)
	}
	return ParseCredential(raw)
}

func (s *Service) clientFor(st *Settings) (*Client, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fp := str(st.CredentialFingerprint)
	if s.client != nil && s.fp == fp {
		return s.client, nil
	}
	cred, err := s.credential(st)
	if err != nil {
		return nil, err
	}
	s.client, s.fp = NewClient(cred, s.tokenURL, s.fcmBase), fp
	return s.client, nil
}

func (s *Service) testCredential(ctx context.Context, c *Client, realToken string) error {
	tok := realToken
	if tok == "" {
		tok = "connection-test-placeholder-token"
	}
	_, err := c.Send(ctx, Message{Token: tok, Title: "Uji koneksi", Body: "Uji koneksi", Category: "INFO", Ref: "test"}, true)
	if err == nil {
		return nil
	}
	var se *SendError
	if errors.As(err, &se) && !se.AuthProblem() && !se.Retryable() &&
		(se.Code == "INVALID_ARGUMENT" || se.InvalidToken()) {
		return nil
	}
	return err
}

func (s *Service) ReplaceCredential(ctx context.Context, raw []byte) (*SettingsView, error) {
	_, name, ok := adminName(ctx)
	if !ok {
		return nil, fmt.Errorf("%w: petugas tidak dikenal", ErrValidation)
	}
	cred, err := ParseCredential(raw)
	if err != nil {
		s.auditAdmin(ctx, "FIREBASE_CREDENTIAL_REJECTED", "push_settings", "FAILED", "Credential Firebase ditolak: format tidak valid")
		return nil, err
	}
	tctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	if err := s.testCredential(tctx, NewClient(cred, s.tokenURL, s.fcmBase), ""); err != nil {
		s.auditAdmin(ctx, "FIREBASE_CREDENTIAL_REJECTED", cred.ProjectID, "FAILED", "Credential Firebase ditolak Google saat validasi: "+safeErr(err))
		return nil, fmt.Errorf("%w: ditolak saat diuji ke Firebase (%s)", ErrInvalidCredential, safeErr(err))
	}
	enc, err := crypto.Encrypt(raw)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	t := true
	if err := s.db.WithContext(ctx).Model(&Settings{}).Where("id = ?", "DEFAULT").Updates(map[string]interface{}{
		"enabled": false, "project_id": cred.ProjectID, "client_email": cred.ClientEmail, "credential_enc": enc,
		"credential_fingerprint": cred.Fingerprint, "credential_updated_by": name, "credential_updated_at": now,
		"last_test_at": now, "last_test_ok": t, "last_test_error": nil, "last_test_fingerprint": cred.Fingerprint,
		"updated_by": name, "updated_at": now,
	}).Error; err != nil {
		return nil, err
	}
	s.mu.Lock()
	s.client = nil
	s.mu.Unlock()
	s.auditAdmin(ctx, "FIREBASE_CREDENTIAL_REPLACED", cred.ProjectID, "SUCCESS",
		fmt.Sprintf("Credential Firebase Admin diganti (project %s, akun %s, sidik %s…); integrasi dinonaktifkan sampai diaktifkan kembali", cred.ProjectID, cred.ClientEmail, cred.Fingerprint[:12]))
	return s.GetSettings(ctx)
}

func safeErr(err error) string {
	var se *SendError
	if errors.As(err, &se) {
		return fmt.Sprintf("%s (HTTP %d): %s", se.Code, se.HTTPStatus, se.Message)
	}
	return "kesalahan internal"
}

func (s *Service) TestConnection(ctx context.Context) (*SettingsView, error) {
	_, name, ok := adminName(ctx)
	if !ok {
		return nil, fmt.Errorf("%w: petugas tidak dikenal", ErrValidation)
	}
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	cred, err := s.credential(st)
	if err != nil {
		return nil, err
	}
	tctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	testErr := s.testCredential(tctx, NewClient(cred, s.tokenURL, s.fcmBase), "")
	now := time.Now()
	upd := map[string]interface{}{"last_test_at": now, "last_test_ok": testErr == nil, "last_test_error": nil,
		"last_test_fingerprint": cred.Fingerprint, "updated_by": name, "updated_at": now}
	status := "SUCCESS"
	if testErr != nil {
		upd["last_test_error"] = safeErr(testErr)
		status = "FAILED"
	}
	if err := s.db.WithContext(ctx).Model(&Settings{}).Where("id = ?", "DEFAULT").Updates(upd).Error; err != nil {
		return nil, err
	}
	s.auditAdmin(ctx, "FIREBASE_CONNECTION_TEST", cred.ProjectID, status, "Uji koneksi Firebase: "+map[bool]string{true: "berhasil", false: safeErr(testErr)}[testErr == nil])
	return s.GetSettings(ctx)
}

func (s *Service) SetEnabled(ctx context.Context, enabled bool) (*SettingsView, error) {
	_, name, ok := adminName(ctx)
	if !ok {
		return nil, fmt.Errorf("%w: petugas tidak dikenal", ErrValidation)
	}
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	if enabled {
		if st.CredentialEnc == nil {
			return nil, fmt.Errorf("%w: unggah credential Firebase Admin terlebih dahulu", ErrState)
		}
		if st.LastTestOK == nil || !*st.LastTestOK || str(st.LastTestFingerprint) != str(st.CredentialFingerprint) {
			return nil, fmt.Errorf("%w: jalankan Uji Koneksi sampai berhasil sebelum mengaktifkan", ErrState)
		}
	}
	if err := s.db.WithContext(ctx).Model(&Settings{}).Where("id = ?", "DEFAULT").
		Updates(map[string]interface{}{"enabled": enabled, "updated_by": name, "updated_at": time.Now()}).Error; err != nil {
		return nil, err
	}
	s.auditAdmin(ctx, map[bool]string{true: "FIREBASE_ENABLED", false: "FIREBASE_DISABLED"}[enabled], str(st.ProjectID), "SUCCESS",
		"Integrasi Firebase Cloud Messaging "+map[bool]string{true: "diaktifkan", false: "dinonaktifkan"}[enabled])
	return s.GetSettings(ctx)
}

func (s *Service) RegisterDevice(ctx context.Context, userID, deviceID, token, platform string) error {
	token = strings.TrimSpace(token)
	if len(token) < 20 || len(token) > 4096 || strings.ContainsAny(token, " \n\r\t") {
		return fmt.Errorf("%w: token notifikasi perangkat tidak valid", ErrValidation)
	}
	if userID == "" || len(deviceID) < 8 || len(deviceID) > 128 {
		return fmt.Errorf("%w: identitas perangkat tidak valid", ErrValidation)
	}
	platform = strings.ToLower(strings.TrimSpace(platform))
	if platform != "ios" {
		platform = "android"
	}
	enc, err := crypto.EncryptString(token)
	if err != nil {
		return err
	}
	now := time.Now()
	hash := hashToken(token)
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&Device{}).Where("user_id = ? AND device_id = ? AND is_active AND token_sha256 <> ?", userID, deviceID, hash).
			Updates(map[string]interface{}{"is_active": false, "deactivated_reason": "TOKEN_REFRESHED", "deactivated_at": now}).Error; err != nil {
			return err
		}
		d := Device{UserID: userID, DeviceID: deviceID, Platform: platform, TokenSHA256: hash, TokenEnc: enc, IsActive: true, CreatedAt: now, LastSeenAt: now}
		return tx.Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "token_sha256"}},
			DoUpdates: clause.Assignments(map[string]interface{}{"user_id": userID, "device_id": deviceID, "platform": platform,
				"is_active": true, "deactivated_reason": nil, "deactivated_at": nil, "last_seen_at": now}),
		}).Create(&d).Error
	})
}

func (s *Service) UnregisterDevice(ctx context.Context, userID, deviceID, reason string) error {
	if s.db == nil || userID == "" || deviceID == "" {
		return nil
	}
	return s.db.WithContext(ctx).Model(&Device{}).Where("user_id = ? AND device_id = ? AND is_active", userID, deviceID).
		Updates(map[string]interface{}{"is_active": false, "deactivated_reason": reason, "deactivated_at": time.Now()}).Error
}

func (s *Service) MarkOpened(ctx context.Context, userID, deliveryID string) error {
	if len(deliveryID) != 36 {
		return ErrNotFound
	}
	res := s.db.WithContext(ctx).Model(&Delivery{}).Where("id = ? AND user_id = ? AND opened_at IS NULL", deliveryID, userID).
		Update("opened_at", time.Now())
	if res.Error != nil {
		return res.Error
	}
	return nil
}

func (s *Service) sendToDevices(ctx context.Context, c *Client, devices []Device, title, body, category string, campaignID, notificationID *string) (acc, failed, invalid int, lastErr string) {
	for _, d := range devices {
		del := Delivery{CampaignID: campaignID, NotificationID: notificationID, UserID: d.UserID, DeviceID: d.ID,
			Category: category, Status: StatusQueued, CreatedAt: time.Now(), UpdatedAt: time.Now()}
		res := s.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&del)
		if res.Error != nil {
			failed++
			lastErr = "gagal mencatat pengiriman"
			continue
		}
		if res.RowsAffected == 0 {
			continue // already sent to this device for this message
		}
		token, err := crypto.DecryptString(d.TokenEnc)
		if err != nil {
			s.finish(ctx, del.ID, StatusFailed, 0, "", "TOKEN_DECRYPT", "token perangkat tidak dapat didekripsi")
			failed++
			continue
		}
		var name string
		var sendErr error
		attempts := 0
		for attempts < maxAttempts {
			attempts++
			name, sendErr = c.Send(ctx, Message{Token: token, Title: title, Body: body, Category: category, Ref: del.ID}, false)
			var se *SendError
			if sendErr == nil || !errors.As(sendErr, &se) || !se.Retryable() || attempts == maxAttempts {
				break
			}
			select {
			case <-ctx.Done():
				attempts = maxAttempts
			case <-time.After(s.backoff(attempts)):
			}
		}
		var se *SendError
		switch {
		case sendErr == nil:
			s.finish(ctx, del.ID, StatusAccepted, attempts, name, "", "")
			acc++
		case errors.As(sendErr, &se) && se.InvalidToken():
			s.finish(ctx, del.ID, StatusInvalidToken, attempts, "", se.Code, se.Message)
			s.db.WithContext(ctx).Model(&Device{}).Where("id = ?", d.ID).
				Updates(map[string]interface{}{"is_active": false, "deactivated_reason": "FCM_UNREGISTERED", "deactivated_at": time.Now()})
			invalid++
		default:
			code, msg := "ERROR", "kesalahan internal"
			if se != nil {
				code, msg = se.Code, se.Message
			}
			s.finish(ctx, del.ID, StatusFailed, attempts, "", code, msg)
			failed++
			lastErr = safeErr(sendErr)
		}
	}
	return
}

func (s *Service) finish(ctx context.Context, id, status string, attempts int, msgID, code, msg string) {
	upd := map[string]interface{}{"status": status, "attempts": attempts, "updated_at": time.Now()}
	if msgID != "" {
		upd["fcm_message_id"] = msgID
	}
	if code != "" {
		upd["error_code"] = code
		upd["error_message"] = msg
	}
	if err := s.db.WithContext(ctx).Model(&Delivery{}).Where("id = ?", id).Updates(upd).Error; err != nil {
		logger.GetLogger().Error("Gagal memperbarui status pengiriman push", map[string]interface{}{"error": err.Error()})
	}
}

func (s *Service) ready(ctx context.Context) (*Client, error) {
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	if !st.Enabled {
		return nil, ErrDisabled
	}
	return s.clientFor(st)
}

func (s *Service) PushToUser(userID, notificationID, title, body, category string) {
	if s == nil || s.db == nil || userID == "" || notificationID == "" {
		return
	}
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		c, err := s.ready(ctx)
		if err != nil {
			if !errors.Is(err, ErrDisabled) {
				logger.GetLogger().Error("Push tidak terkirim: integrasi Firebase bermasalah", map[string]interface{}{"error": err.Error()})
			}
			return
		}
		var devices []Device
		if err := s.db.WithContext(ctx).Where("user_id = ? AND is_active", userID).Find(&devices).Error; err != nil || len(devices) == 0 {
			return
		}
		nid := notificationID
		_, failed, _, lastErr := s.sendToDevices(ctx, c, devices, title, body, category, nil, &nid)
		if failed > 0 {
			logger.GetLogger().Warn("Sebagian push gagal dikirim", map[string]interface{}{"failed": failed, "reason": lastErr})
		}
	}()
}

type CampaignInput struct {
	Title        string `json:"title"`
	Body         string `json:"body"`
	Category     string `json:"category"`
	TargetType   string `json:"target_type"`
	TargetUserID string `json:"target_user_id"`
}

func (s *Service) validateCampaign(ctx context.Context, in *CampaignInput) error {
	in.Title, in.Body = strings.TrimSpace(in.Title), strings.TrimSpace(in.Body)
	in.Category, in.TargetType = strings.ToUpper(strings.TrimSpace(in.Category)), strings.ToUpper(strings.TrimSpace(in.TargetType))
	if in.Title == "" || utf8.RuneCountInString(in.Title) > 100 {
		return fmt.Errorf("%w: judul wajib diisi (maks. 100 karakter)", ErrValidation)
	}
	if in.Body == "" || utf8.RuneCountInString(in.Body) > 500 {
		return fmt.Errorf("%w: isi wajib diisi (maks. 500 karakter)", ErrValidation)
	}
	for _, r := range in.Title + in.Body {
		if (r < 0x20 && r != '\n') || r == '<' || r == '>' {
			return fmt.Errorf("%w: teks berisi karakter yang tidak diizinkan", ErrValidation)
		}
	}
	if in.Category != "INFO" && in.Category != "PROMO" {
		return fmt.Errorf("%w: kategori harus INFO atau PROMO", ErrValidation)
	}
	switch in.TargetType {
	case "ALL":
		in.TargetUserID = ""
	case "USER":
		var n int64
		if len(in.TargetUserID) != 36 || s.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", in.TargetUserID).Count(&n).Error != nil || n != 1 {
			return fmt.Errorf("%w: nasabah penerima tidak ditemukan", ErrValidation)
		}
	default:
		return fmt.Errorf("%w: penerima harus ALL atau USER", ErrValidation)
	}
	return nil
}

func (s *Service) CreateCampaign(ctx context.Context, in CampaignInput) (*Campaign, error) {
	id, name, ok := adminName(ctx)
	if !ok {
		return nil, fmt.Errorf("%w: petugas tidak dikenal", ErrValidation)
	}
	if err := s.validateCampaign(ctx, &in); err != nil {
		return nil, err
	}
	c := Campaign{Title: in.Title, Body: in.Body, Category: in.Category, TargetType: in.TargetType, Status: CampaignDraft,
		CreatedBy: id, CreatedByName: name, CreatedAt: time.Now()}
	if in.TargetUserID != "" {
		c.TargetUserID = &in.TargetUserID
	}
	if err := s.db.WithContext(ctx).Create(&c).Error; err != nil {
		return nil, err
	}
	s.auditAdmin(ctx, "NOTIFICATION_DRAFT_CREATED", c.ID, "SUCCESS", fmt.Sprintf("Draf notifikasi [%s → %s]: %s", c.Category, c.TargetType, c.Title))
	return &c, nil
}

func (s *Service) transition(ctx context.Context, id string, fn func(tx *gorm.DB, c *Campaign) error) (*Campaign, error) {
	if len(id) != 36 {
		return nil, ErrNotFound
	}
	var out Campaign
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", id).First(&out).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrNotFound
			}
			return err
		}
		if err := fn(tx, &out); err != nil {
			return err
		}
		return tx.Where("id = ?", id).First(&out).Error
	})
	if err != nil {
		return nil, err
	}
	return &out, nil
}

func (s *Service) SubmitCampaign(ctx context.Context, id string) (*Campaign, error) {
	c, err := s.transition(ctx, id, func(tx *gorm.DB, c *Campaign) error {
		if c.Status != CampaignDraft && c.Status != CampaignRejected {
			return fmt.Errorf("%w: hanya draf yang dapat diajukan", ErrState)
		}
		return tx.Model(&Campaign{}).Where("id = ?", id).Updates(map[string]interface{}{"status": CampaignPending, "submitted_at": time.Now(), "reject_reason": nil}).Error
	})
	if err == nil {
		s.auditAdmin(ctx, "NOTIFICATION_SUBMITTED", id, "SUCCESS", "Notifikasi diajukan untuk persetujuan: "+c.Title)
	}
	return c, err
}

func (s *Service) RejectCampaign(ctx context.Context, id, reason string) (*Campaign, error) {
	reason = strings.TrimSpace(reason)
	if reason == "" || utf8.RuneCountInString(reason) > 300 {
		return nil, fmt.Errorf("%w: alasan wajib diisi (maks. 300 karakter)", ErrValidation)
	}
	c, err := s.transition(ctx, id, func(tx *gorm.DB, c *Campaign) error {
		if c.Status != CampaignPending {
			return fmt.Errorf("%w: hanya notifikasi yang menunggu persetujuan yang dapat ditolak", ErrState)
		}
		return tx.Model(&Campaign{}).Where("id = ?", id).Updates(map[string]interface{}{"status": CampaignRejected, "reject_reason": reason}).Error
	})
	if err == nil {
		s.auditAdmin(ctx, "NOTIFICATION_REJECTED", id, "SUCCESS", "Notifikasi ditolak: "+reason)
	}
	return c, err
}

func (s *Service) ApproveCampaign(ctx context.Context, id string) (*Campaign, error) {
	adminID, name, ok := adminName(ctx)
	if !ok {
		return nil, fmt.Errorf("%w: petugas tidak dikenal", ErrValidation)
	}
	client, err := s.ready(ctx)
	if err != nil {
		return nil, err
	}
	c, err := s.transition(ctx, id, func(tx *gorm.DB, c *Campaign) error {
		if c.Status != CampaignPending {
			return fmt.Errorf("%w: hanya notifikasi yang menunggu persetujuan yang dapat dikirim", ErrState)
		}
		if adminID == c.CreatedBy {
			return ErrMakerChecker
		}
		inboxUser := "ALL"
		if c.TargetUserID != nil {
			inboxUser = *c.TargetUserID
		}
		if err := tx.Create(&model.Notification{UserID: inboxUser, Title: c.Title, Message: c.Body, Category: c.Category, CreatedAt: time.Now()}).Error; err != nil {
			return err
		}
		now := time.Now()
		return tx.Model(&Campaign{}).Where("id = ?", id).Updates(map[string]interface{}{
			"status": CampaignSending, "approved_by": adminID, "approved_by_name": name, "approved_at": now, "send_started_at": now}).Error
	})
	if err != nil {
		return nil, err
	}
	s.auditAdmin(ctx, "NOTIFICATION_APPROVED", id, "SUCCESS", fmt.Sprintf("Notifikasi disetujui dan dikirim [%s → %s]: %s", c.Category, c.TargetType, c.Title))
	s.wg.Add(1)
	go func(c Campaign) {
		defer s.wg.Done()
		s.runCampaign(client, c)
	}(*c)
	return c, nil
}

func (s *Service) runCampaign(client *Client, c Campaign) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	q := s.db.WithContext(ctx).Table("push_devices").Select("push_devices.*").
		Joins("JOIN users ON users.id = push_devices.user_id").Where("push_devices.is_active AND users.is_active = ?", true)
	if c.TargetUserID != nil {
		q = q.Where("push_devices.user_id = ?", *c.TargetUserID)
	}
	var devices []Device
	err := q.Find(&devices).Error
	id := c.ID
	var acc, failed, invalid int
	lastErr := ""
	if err != nil {
		lastErr = "gagal membaca daftar perangkat"
	} else {
		acc, failed, invalid, lastErr = s.sendToDevices(ctx, client, devices, c.Title, c.Body, c.Category, &id, nil)
	}
	status := CampaignSent
	switch {
	case err != nil:
		status = CampaignFailed
	case len(devices) == 0:
		status = CampaignNoRecipient
	case acc == 0:
		status = CampaignFailed
	case failed+invalid > 0:
		status = CampaignPartial
	}
	upd := map[string]interface{}{"status": status, "send_finished_at": time.Now(), "target_devices": len(devices),
		"accepted_count": acc, "failed_count": failed, "invalid_token_count": invalid}
	if lastErr != "" {
		upd["last_error"] = lastErr
	}
	if e := s.db.WithContext(ctx).Model(&Campaign{}).Where("id = ?", c.ID).Updates(upd).Error; e != nil {
		logger.GetLogger().Error("Gagal memperbarui status notifikasi", map[string]interface{}{"error": e.Error()})
	}
	audit.Record(ctx, s.db, "SYSTEM", "push", "push-service", "NOTIFICATION_SEND_RESULT", c.ID, map[bool]string{true: "SUCCESS", false: "WARNING"}[status == CampaignSent], "",
		fmt.Sprintf("Hasil pengiriman: status %s; perangkat %d; diterima FCM %d; gagal %d; token tidak valid %d", status, len(devices), acc, failed, invalid))
}

func (s *Service) ListCampaigns(ctx context.Context, limit int) ([]Campaign, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var out []Campaign
	err := s.db.WithContext(ctx).Order("created_at DESC").Limit(limit).Find(&out).Error
	return out, err
}

type DeliveryView struct {
	Delivery
	Platform string `json:"platform"`
}

func (s *Service) CampaignDeliveries(ctx context.Context, id string, limit int) ([]DeliveryView, error) {
	if len(id) != 36 {
		return nil, ErrNotFound
	}
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	var out []DeliveryView
	err := s.db.WithContext(ctx).Table("push_deliveries").Select("push_deliveries.*, push_devices.platform").
		Joins("JOIN push_devices ON push_devices.id = push_deliveries.device_id").
		Where("push_deliveries.campaign_id = ?", id).Order("push_deliveries.created_at").Limit(limit).Scan(&out).Error
	return out, err
}
