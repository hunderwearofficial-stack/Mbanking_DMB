package devicebind

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	ModeOff      = "off"
	ModeDual     = "dual"
	ModeEnforced = "enforced"

	AttestOff     = "off"
	AttestObserve = "observe"
	AttestEnforce = "enforce"

	PurposeLogin          = "LOGIN"
	PurposeRefresh        = "REFRESH"
	PurposeEnroll         = "ENROLL"
	PurposeRotate         = "ROTATE"
	PurposeChangePIN      = "CHANGE_PIN"
	PurposeChangePassword = "CHANGE_PASSWORD"

	LevelStrongBox     = "STRONGBOX"
	LevelTEE           = "TEE"
	LevelSecureEnclave = "SECURE_ENCLAVE"

	AlgES256     = "ES256"
	AlgAppAttest = "APPATTEST"

	FormatAndroidKey  = "android-key"
	FormatAppleAttest = "apple-appattest"
	FormatNone        = "none"

	AttestationHardwareVerified = "HARDWARE_VERIFIED"
	AttestationUnverified       = "UNVERIFIED"
	AttestationFailed           = "FAILED"

	SigningFormat = "DMB-DEVICE-BINDING-V1"

	ChallengeTTL = 2 * time.Minute
	EnrollWindow = 30 * time.Minute

	statusActive  = "ACTIVE"
	statusRotated = "ROTATED"
	statusRevoked = "REVOKED"
)

var (
	ErrSignatureRequired      = errors.New("verifikasi kunci keamanan perangkat diperlukan. Perbarui aplikasi Mobile DMB ke versi terbaru")
	ErrVerificationFailed     = errors.New("verifikasi kunci keamanan perangkat gagal. Silakan coba kembali")
	ErrEnrollmentNotAllowed   = errors.New("pendaftaran kunci keamanan perangkat memerlukan verifikasi OTP. Silakan verifikasi ulang perangkat melalui menu Lupa Password")
	ErrAlreadyEnrolled        = errors.New("perangkat ini sudah memiliki kunci keamanan terdaftar")
	ErrNoActiveKey            = errors.New("perangkat ini belum memiliki kunci keamanan terdaftar")
	ErrInvalidKey             = errors.New("kunci publik perangkat tidak valid")
	ErrInsecureKey            = errors.New("perangkat tidak memiliki penyimpanan kunci keamanan yang memenuhi kebijakan Bank DMB")
	ErrAttestationRequired    = errors.New("perangkat tidak dapat membuktikan kunci keamanan yang asli. Mobile DMB tidak dapat diaktifkan pada perangkat ini")
	ErrAttestationUnavailable = errors.New("verifikasi perangkat iOS (App Attest) sedang belum tersedia")
	ErrInvalidDeviceID        = errors.New("format identitas perangkat tidak valid")
	ErrInvalidPurpose         = errors.New("tujuan verifikasi perangkat tidak valid")
	ErrBindingDisabled        = errors.New("pendaftaran kunci keamanan perangkat sedang tidak aktif")
	ErrRotationUnsupported    = errors.New("kunci App Attest tidak dapat dirotasi; verifikasi ulang perangkat melalui menu Lupa Password")
	ErrEnrollmentRequired     = errors.New("perangkat Anda belum memiliki kunci keamanan. Silakan verifikasi ulang perangkat melalui menu Lupa Password")
)

var (
	androidID = regexp.MustCompile(`^and-[0-9a-f]{16}$`)
	iosID     = regexp.MustCompile(`^ios-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	fpPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

func CanonicalPlatform(deviceID string) (string, bool) {
	switch {
	case androidID.MatchString(deviceID):
		return "android", true
	case iosID.MatchString(deviceID):
		return "ios", true
	}
	return "", false
}

func IsLegacy(deviceID string) bool {
	_, ok := CanonicalPlatform(deviceID)
	return strings.TrimSpace(deviceID) != "" && !ok
}

func levelRank(level string) int {
	switch level {
	case LevelStrongBox:
		return 2
	case LevelTEE, LevelSecureEnclave:
		return 1
	}
	return 0
}

func levelAllowed(platform, level string) bool {
	switch platform {
	case "android":
		return level == LevelStrongBox || level == LevelTEE
	case "ios":
		return level == LevelSecureEnclave
	}
	return false
}

type Options struct {
	Mode            string
	AttestationMode string
	Android         *AndroidAttestationConfig
	Apple           *AppleAttestationConfig
	// SR-4: an "off" (rollback) switch is time-boxed and justified. After OffUntil the
	// service behaves as dual again, without restart. Zero = no expiry (non-production only;
	// config validation requires both values in staging/production).
	OffReason string
	OffUntil  time.Time
	Now       func() time.Time
}

type Service struct {
	db         *gorm.DB
	opt        Options
	expiryOnce sync.Once
}

func NewService(db *gorm.DB, opt Options) *Service {
	opt.Mode = strings.ToLower(strings.TrimSpace(opt.Mode))
	if opt.Mode == "" {
		opt.Mode = ModeDual
	}
	opt.AttestationMode = strings.ToLower(strings.TrimSpace(opt.AttestationMode))
	if opt.AttestationMode == "" {
		opt.AttestationMode = AttestObserve
	}
	return &Service{db: db, opt: opt}
}

func (s *Service) now() time.Time {
	if s.opt.Now != nil {
		return s.opt.Now()
	}
	return time.Now()
}

// Mode is the effective binding mode: an expired "off" switch reverts to dual.
func (s *Service) Mode() string {
	if s == nil {
		return ModeOff
	}
	if s.opt.Mode == ModeOff && !s.opt.OffUntil.IsZero() && s.now().After(s.opt.OffUntil) {
		s.expiryOnce.Do(func() {
			logger.GetLogger().Warn("DEVICE_BINDING_MODE=off kedaluwarsa: proteksi kunci perangkat aktif kembali (dual)",
				map[string]interface{}{"off_until": s.opt.OffUntil.UTC().Format(time.RFC3339)})
			if s.db != nil {
				audit.Record(context.Background(), s.db, "SYSTEM", "devicebind", "device-binding", "DEVICE_BINDING_OFF_EXPIRED",
					ModeDual, "WARNING", "", "Saklar DEVICE_BINDING_MODE=off kedaluwarsa; perilaku kembali ke dual")
			}
		})
		return ModeDual
	}
	return s.opt.Mode
}

func (s *Service) Active() bool { return s != nil && s.Mode() != ModeOff }

// keyAccepted (SR-2): with attestation enforced, a key is usable only when its hardware
// properties were verified by the server. Keys enrolled earlier as UNVERIFIED / FAILED
// (e.g. during observe) stop working when enforce is switched on; the customer re-binds
// through OTP. They are never downgraded to the identifier binding.
func (s *Service) keyAccepted(k *Key) bool {
	return s.opt.AttestationMode != AttestEnforce || k.AttestationStatus == AttestationHardwareVerified
}

func (s *Service) auditKeyNotAccepted(ctx context.Context, k *Key, purpose string) {
	audit.Record(ctx, s.db, "NASABAH", k.UserID, "", "DEVICE_ATTESTATION_FAILED", purpose, "DANGER", k.DeviceID,
		fmt.Sprintf("Kunci perangkat ditolak saat dipakai: attestation %s tidak memenuhi DEVICE_ATTESTATION_MODE=enforce", k.AttestationStatus))
}

// LogStartup records the effective device binding configuration at start-up (SR-4):
// structured log + audit entry; "off" and non-enforced attestation are DANGER/WARNING.
func (s *Service) LogStartup(ctx context.Context, appEnv string) {
	mode, att := s.Mode(), s.opt.AttestationMode
	fields := map[string]interface{}{"app_env": appEnv, "device_binding_mode": mode, "device_attestation_mode": att}
	if !s.opt.OffUntil.IsZero() {
		fields["off_until"] = s.opt.OffUntil.UTC().Format(time.RFC3339)
	}
	if s.opt.OffReason != "" {
		fields["off_reason"] = s.opt.OffReason
	}
	status, details := "SUCCESS", fmt.Sprintf("Device binding aktif: mode %s, attestation %s", mode, att)
	switch {
	case mode == ModeOff:
		status = "DANGER"
		details = fmt.Sprintf("PROTEKSI KUNCI PERANGKAT NONAKTIF (DEVICE_BINDING_MODE=off) hingga %s; alasan: %s",
			fieldOr(fields["off_until"], "tanpa batas"), fieldOr(fields["off_reason"], "-"))
		logger.GetLogger().Error("DEVICE_BINDING_MODE=off: verifikasi kunci perangkat, klaim sesi dk, dan gate enforced NONAKTIF", fields)
	case att != AttestEnforce:
		status = "WARNING"
		logger.GetLogger().Warn("DEVICE_ATTESTATION_MODE bukan enforce: kunci tanpa bukti hardware diterima", fields)
	default:
		logger.GetLogger().Info("Device binding aktif", fields)
	}
	if s.db != nil {
		audit.Record(ctx, s.db, "SYSTEM", "devicebind", "device-binding", "DEVICE_BINDING_CONFIG", mode, status, "", details)
	}
}

func fieldOr(v interface{}, def string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return def
}

type Key struct {
	ID                   string     `gorm:"column:id;primaryKey"`
	UserID               string     `gorm:"column:user_id"`
	DeviceID             string     `gorm:"column:device_id"`
	Platform             string     `gorm:"column:platform"`
	Algorithm            string     `gorm:"column:algorithm"`
	PublicKey            string     `gorm:"column:public_key"`
	KeyFingerprint       string     `gorm:"column:key_fingerprint"`
	SecurityLevel        string     `gorm:"column:security_level"`
	Status               string     `gorm:"column:status"`
	EnrolledVia          string     `gorm:"column:enrolled_via"`
	PreviousDeviceID     *string    `gorm:"column:previous_device_id"`
	AttestationStatus    string     `gorm:"column:attestation_status"`
	AttestationSummary   *string    `gorm:"column:attestation_summary"`
	AttestationCheckedAt *time.Time `gorm:"column:attestation_checked_at"`
	AppAttestKeyID       *string    `gorm:"column:app_attest_key_id"`
	SignCount            int64      `gorm:"column:sign_count"`
	CreatedAt            time.Time  `gorm:"column:created_at"`
	LastUsedAt           *time.Time `gorm:"column:last_used_at"`
	RevokedAt            *time.Time `gorm:"column:revoked_at"`
	RevokedReason        *string    `gorm:"column:revoked_reason"`
}

func (Key) TableName() string { return "device_keys" }

type challengeRow struct {
	ID             string     `gorm:"column:id;primaryKey"`
	Purpose        string     `gorm:"column:purpose"`
	UserID         *string    `gorm:"column:user_id"`
	DeviceID       string     `gorm:"column:device_id"`
	KeyID          *string    `gorm:"column:key_id"`
	KeyFingerprint *string    `gorm:"column:key_fingerprint"`
	Nonce          string     `gorm:"column:nonce"`
	ExpiresAt      time.Time  `gorm:"column:expires_at"`
	UsedAt         *time.Time `gorm:"column:used_at"`
	CreatedIP      string     `gorm:"column:created_ip"`
}

func (challengeRow) TableName() string { return "device_challenges" }

func ContextDigest(context string) string {
	sum := sha256.Sum256([]byte(context))
	return hex.EncodeToString(sum[:])
}

func SigningMessage(purpose, challengeID, nonce, deviceID, context string) []byte {
	return []byte(strings.Join([]string{SigningFormat, purpose, challengeID, nonce, deviceID, ContextDigest(context)}, "\n"))
}

func EnrollContext(keyRef, deviceID string) string { return keyRef + "\n" + deviceID }

func OperationContext(purpose string) string { return "operation=" + purpose }

func ParsePublicKey(b64 string) (*ecdsa.PublicKey, []byte, string, error) {
	der, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil || len(der) == 0 || len(der) > 512 {
		return nil, nil, "", ErrInvalidKey
	}
	parsed, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return nil, nil, "", ErrInvalidKey
	}
	pub, ok := parsed.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		return nil, nil, "", ErrInvalidKey
	}
	sum := sha256.Sum256(der)
	return pub, der, hex.EncodeToString(sum[:]), nil
}

func fingerprintOf(der []byte) string {
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:])
}

func verifySignature(pub *ecdsa.PublicKey, msg []byte, sigB64 string) bool {
	sig, err := base64.StdEncoding.DecodeString(strings.TrimSpace(sigB64))
	if err != nil || len(sig) == 0 || len(sig) > 128 {
		return false
	}
	digest := sha256.Sum256(msg)
	return ecdsa.VerifyASN1(pub, digest[:], sig)
}

func newNonce() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func (s *Service) ActiveKey(ctx context.Context, userID string) (*Key, error) {
	if userID == "" {
		userID = uuid.Nil.String() // same query for decoys (uniform timing, L3)
	}
	var k Key
	if err := s.db.WithContext(ctx).Where("user_id = ? AND status = ?", userID, statusActive).Limit(1).Find(&k).Error; err != nil {
		return nil, err
	}
	if k.ID == "" {
		return nil, nil
	}
	return &k, nil
}

func (s *Service) ActiveKeyID(ctx context.Context, userID string) (string, bool, error) {
	if !s.Active() {
		return "", false, nil
	}
	k, err := s.ActiveKey(ctx, userID)
	if err != nil || k == nil {
		return "", true, err
	}
	if !s.keyAccepted(k) {
		return k.ID, true, middleware.ErrDeviceKeyNotAccepted
	}
	return k.ID, true, nil
}

func RevokeUserKeys(tx *gorm.DB, userID, reason string) (int64, error) {
	res := tx.Model(&Key{}).Where("user_id = ? AND status = ?", userID, statusActive).
		Updates(map[string]interface{}{"status": statusRevoked, "revoked_at": time.Now(), "revoked_reason": reason})
	return res.RowsAffected, res.Error
}

func OpenEnrollmentWindow(tx *gorm.DB, userID string) error {
	return tx.Exec(`UPDATE users SET device_enroll_until = now() + make_interval(secs => ?) WHERE id = ?`,
		int(EnrollWindow.Seconds()), userID).Error
}

type ChallengeSpec struct {
	Purpose        string
	UserID         string // empty = decoy (unknown identifier) — never verifiable
	DeviceID       string
	KeyID          string
	KeyFingerprint string
	IP             string
}

func (s *Service) IssueChallenge(ctx context.Context, spec ChallengeSpec) (*domain.DeviceChallengeResponse, error) {
	nonce, err := newNonce()
	if err != nil {
		return nil, err
	}
	id := uuid.NewString()
	null := func(v string) interface{} {
		if v == "" {
			return nil
		}
		return v
	}
	var out struct{ ExpiresAt time.Time }
	err = s.db.WithContext(ctx).Raw(`INSERT INTO device_challenges
		(id, purpose, user_id, device_id, key_id, key_fingerprint, nonce, expires_at, created_ip)
		VALUES (?, ?, ?, ?, ?, ?, ?, now() + make_interval(secs => ?), ?)
		RETURNING expires_at`,
		id, spec.Purpose, null(spec.UserID), spec.DeviceID, null(spec.KeyID), null(spec.KeyFingerprint), nonce,
		int(ChallengeTTL.Seconds()), truncate(spec.IP, 64)).Scan(&out).Error
	if err != nil {
		return nil, err
	}
	return &domain.DeviceChallengeResponse{
		ChallengeID: id, Nonce: nonce, Purpose: spec.Purpose, ExpiresAt: out.ExpiresAt.UTC(), SigningFormat: SigningFormat,
	}, nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

type verifyFailure struct{ reason string }

func (v *verifyFailure) Error() string        { return ErrVerificationFailed.Error() }
func (v *verifyFailure) Is(target error) bool { return target == ErrVerificationFailed }

func fail(reason string) error { return &verifyFailure{reason: reason} }

func FailureReason(err error) string {
	var v *verifyFailure
	if errors.As(err, &v) {
		return v.reason
	}
	if errors.Is(err, ErrSignatureRequired) {
		return "SIGNATURE_MISSING"
	}
	return ""
}

func (s *Service) consume(ctx context.Context, id, purpose string) (*challengeRow, error) {
	if _, err := uuid.Parse(strings.TrimSpace(id)); err != nil {
		return nil, fail("CHALLENGE_UNKNOWN")
	}
	var rows []challengeRow
	err := s.db.WithContext(ctx).Raw(`UPDATE device_challenges SET used_at = now()
		WHERE id = ? AND purpose = ? AND used_at IS NULL AND expires_at > now()
		RETURNING id, purpose, user_id, device_id, key_id, key_fingerprint, nonce, expires_at, used_at, created_ip`,
		id, purpose).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	if len(rows) == 1 {
		return &rows[0], nil
	}
	var existing challengeRow
	if err := s.db.WithContext(ctx).Where("id = ?", id).Limit(1).Find(&existing).Error; err != nil {
		return nil, err
	}
	switch {
	case existing.ID == "":
		return nil, fail("CHALLENGE_UNKNOWN")
	case existing.Purpose != purpose:
		return nil, fail("CHALLENGE_PURPOSE_MISMATCH")
	case existing.UsedAt != nil:
		return nil, fail("CHALLENGE_REPLAYED")
	default:
		return nil, fail("CHALLENGE_EXPIRED")
	}
}

type Proof struct {
	ChallengeID string
	Signature   string
}

func (p Proof) empty() bool {
	return strings.TrimSpace(p.ChallengeID) == "" && strings.TrimSpace(p.Signature) == ""
}

func strPtrEq(p *string, v string) bool { return p != nil && *p == v }

func (s *Service) verifyKeyProof(ctx context.Context, key *Key, msg []byte, sig string) error {
	pub, _, _, err := ParsePublicKey(key.PublicKey)
	if err != nil {
		return fail("STORED_KEY_INVALID")
	}
	switch key.Algorithm {
	case AlgES256:
		if !verifySignature(pub, msg, sig) {
			return fail("SIGNATURE_INVALID")
		}
		_ = s.db.WithContext(ctx).Model(&Key{}).Where("id = ?", key.ID).Update("last_used_at", time.Now()).Error
		return nil
	case AlgAppAttest:
		if s.opt.Apple == nil || s.opt.Apple.AppID == "" {
			return fail("APPLE_ATTESTATION_NOT_CONFIGURED")
		}
		if key.SignCount < 0 || key.SignCount > int64(^uint32(0)) {
			return fail("ASSERTION_COUNTER_INVALID")
		}
		counter, reason := VerifyAppleAssertion(s.opt.Apple.AppID, pub, sig, msg, uint32(key.SignCount))
		if reason != "" {
			return fail(reason)
		}
		res := s.db.WithContext(ctx).Exec(`UPDATE device_keys SET sign_count = ?, last_used_at = now()
			WHERE id = ? AND status = 'ACTIVE' AND sign_count < ?`, int64(counter), key.ID, int64(counter))
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return fail("ASSERTION_COUNTER_REPLAY")
		}
		return nil
	}
	return fail("UNKNOWN_KEY_ALGORITHM")
}

func (s *Service) verifyWithKey(ctx context.Context, purpose, userID, deviceID string, key *Key, proof Proof, context string) error {
	if proof.empty() {
		return ErrSignatureRequired
	}
	row, err := s.consume(ctx, proof.ChallengeID, purpose)
	if err != nil {
		return err
	}
	if !strPtrEq(row.UserID, userID) {
		return fail("CHALLENGE_USER_MISMATCH")
	}
	if row.DeviceID != deviceID {
		return fail("CHALLENGE_DEVICE_MISMATCH")
	}
	if !strPtrEq(row.KeyID, key.ID) {
		return fail("CHALLENGE_KEY_MISMATCH")
	}
	return s.verifyKeyProof(ctx, key, SigningMessage(purpose, row.ID, row.Nonce, deviceID, context), proof.Signature)
}

func (s *Service) Require(ctx context.Context, purpose, userID, deviceID string, proof Proof, context string) error {
	if !s.Active() {
		return nil
	}
	key, err := s.ActiveKey(ctx, userID)
	if err != nil {
		return err
	}
	if key == nil {
		return nil
	}
	if !s.keyAccepted(key) {
		s.auditKeyNotAccepted(ctx, key, purpose)
		return ErrAttestationRequired
	}
	if key.DeviceID != deviceID {
		err = fail("KEY_DEVICE_MISMATCH")
	} else {
		err = s.verifyWithKey(ctx, purpose, userID, deviceID, key, proof, context)
	}
	if err != nil {
		s.auditFailure(ctx, userID, deviceID, purpose, err)
	}
	return err
}

func (s *Service) auditFailure(ctx context.Context, userID, deviceID, purpose string, err error) {
	reason := FailureReason(err)
	if reason == "" {
		return // infrastructure error, logged by the caller
	}
	action, level := "DEVICE_SIGNATURE_REJECTED", "WARNING"
	switch reason {
	case "CHALLENGE_REPLAYED", "ASSERTION_COUNTER_REPLAY":
		action, level = "DEVICE_CHALLENGE_REPLAY", "DANGER"
	case "SIGNATURE_INVALID", "KEY_DEVICE_MISMATCH", "CHALLENGE_USER_MISMATCH", "CHALLENGE_KEY_MISMATCH", "SIGNATURE_MISSING":
		level = "DANGER"
	}
	if strings.HasPrefix(reason, "ATTEST:") {
		action, level = "DEVICE_ATTESTATION_FAILED", "DANGER"
	}
	audit.Record(ctx, s.db, "NASABAH", userID, "", action, purpose, level, deviceID,
		fmt.Sprintf("Verifikasi kunci perangkat ditolak (%s, alasan %s)", purpose, reason))
}

func (s *Service) Status(ctx context.Context, userID, sessionDeviceID string) domain.DeviceBindingStatus {
	st := domain.DeviceBindingStatus{Mode: s.Mode(), AttestationMode: s.opt.AttestationMode,
		SessionDeviceID: sessionDeviceID, Enrollment: "NOT_AVAILABLE"}
	if !s.Active() {
		return st
	}
	key, err := s.ActiveKey(ctx, userID)
	if err != nil {
		return st
	}
	if key != nil {
		st.Enrolled = true
		st.SecurityLevel = key.SecurityLevel
		st.KeyAlgorithm = key.Algorithm
		st.AttestationStatus = key.AttestationStatus
		st.Enrollment = "NOT_NEEDED"
		if !s.keyAccepted(key) {
			st.Enrollment = "OTP_REQUIRED" // re-bind through Lupa Password to enroll an attested key
		}
		return st
	}
	var u struct {
		DeviceID          string
		DeviceEnrollUntil *time.Time
	}
	_ = s.db.WithContext(ctx).Raw(`SELECT device_id, device_enroll_until FROM users WHERE id = ?`, userID).Scan(&u).Error
	if u.DeviceEnrollUntil != nil && u.DeviceEnrollUntil.After(time.Now()) && u.DeviceID == sessionDeviceID {
		st.Enrollment = "ALLOWED"
	} else {
		st.Enrollment = "OTP_REQUIRED"
	}
	return st
}

type EnrollInput struct {
	UserID            string
	SessionDeviceID   string // identifier the current session is bound to
	DeviceID          string // canonical identifier (and-… / ios-…), must equal the binding
	Platform          string
	Format            string // android-key | apple-appattest | none
	PublicKey         string // SPKI DER base64 (ES256)
	SecurityLevel     string // client-reported level, only used when not attested
	AttestationChain  []string
	AppAttestKeyID    string
	AttestationObject string
	Proof             Proof
}

type EnrollResult struct{ Key *Key }

func (s *Service) attestationAccepted(res *AttestationResult) bool {
	return s.opt.AttestationMode != AttestEnforce || res.Status == AttestationHardwareVerified
}

func (s *Service) Enroll(ctx context.Context, in EnrollInput) (*EnrollResult, error) {
	if !s.Active() {
		return nil, ErrBindingDisabled
	}
	platform, ok := CanonicalPlatform(in.DeviceID)
	if !ok || platform != strings.ToLower(strings.TrimSpace(in.Platform)) || in.DeviceID != in.SessionDeviceID {
		return nil, ErrInvalidDeviceID
	}
	format := strings.ToLower(strings.TrimSpace(in.Format))
	switch {
	case format == "":
		format = FormatNone
	case format == FormatAndroidKey && platform != "android", format == FormatAppleAttest && platform != "ios":
		return nil, ErrInvalidKey
	case format != FormatAndroidKey && format != FormatAppleAttest && format != FormatNone:
		return nil, ErrInvalidKey
	}
	if format == FormatAppleAttest && (s.opt.Apple == nil || s.opt.Apple.Roots == nil || s.opt.Apple.AppID == "") {
		return nil, ErrAttestationUnavailable
	}
	if in.Proof.ChallengeID == "" {
		return nil, ErrSignatureRequired
	}

	row, err := s.consume(ctx, in.Proof.ChallengeID, PurposeEnroll)
	if err == nil && (!strPtrEq(row.UserID, in.UserID) || row.DeviceID != in.SessionDeviceID) {
		err = fail("CHALLENGE_USER_MISMATCH")
	}
	if err != nil {
		s.auditFailure(ctx, in.UserID, in.SessionDeviceID, PurposeEnroll, err)
		return nil, err
	}

	key := &Key{ID: uuid.NewString(), UserID: in.UserID, DeviceID: in.DeviceID, Platform: platform, Status: statusActive, EnrolledVia: "OTP_ENROLLMENT"}
	var att *AttestationResult
	switch format {
	case FormatAppleAttest:
		msg := SigningMessage(PurposeEnroll, row.ID, row.Nonce, in.SessionDeviceID, EnrollContext(strings.TrimSpace(in.AppAttestKeyID), in.DeviceID))
		attested, res := VerifyAppleAttestation(s.opt.Apple, in.AttestationObject, in.AppAttestKeyID, msg)
		att = res
		if attested == nil {
			audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_ATTESTATION_FAILED", platform, "DANGER", in.SessionDeviceID,
				"Pendaftaran App Attest ditolak: "+res.Reason)
			return nil, ErrAttestationRequired
		}
		kid := base64.StdEncoding.EncodeToString(attested.KeyID)
		key.Algorithm, key.AppAttestKeyID = AlgAppAttest, &kid
		key.PublicKey = base64.StdEncoding.EncodeToString(attested.SPKI)
		key.KeyFingerprint = fingerprintOf(attested.SPKI)
	default:
		pub, der, fp, perr := ParsePublicKey(in.PublicKey)
		if perr != nil {
			return nil, perr
		}
		if row.KeyFingerprint != nil && *row.KeyFingerprint != fp {
			err = fail("CHALLENGE_KEY_MISMATCH")
			break
		}
		if !verifySignature(pub, SigningMessage(PurposeEnroll, row.ID, row.Nonce, in.SessionDeviceID, EnrollContext(fp, in.DeviceID)), in.Proof.Signature) {
			err = fail("SIGNATURE_INVALID")
			break
		}
		key.Algorithm, key.PublicKey, key.KeyFingerprint = AlgES256, base64.StdEncoding.EncodeToString(der), fp
		switch {
		case format == FormatAndroidKey && s.opt.AttestationMode != AttestOff:
			att = VerifyAndroidAttestation(s.opt.Android, in.AttestationChain, der, []byte(row.Nonce))
		default:
			att = &AttestationResult{Status: AttestationUnverified, Reason: "NO_ATTESTATION"}
		}
	}
	if err != nil {
		s.auditFailure(ctx, in.UserID, in.SessionDeviceID, PurposeEnroll, err)
		return nil, err
	}
	if !s.attestationAccepted(att) {
		audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_ATTESTATION_FAILED", platform, "DANGER", in.SessionDeviceID,
			fmt.Sprintf("Pendaftaran kunci ditolak: attestation %s (%s)", att.Status, att.Reason))
		return nil, ErrAttestationRequired
	}
	if att.Status == AttestationHardwareVerified {
		key.SecurityLevel = att.SecurityLevel
	} else {
		level := strings.ToUpper(strings.TrimSpace(in.SecurityLevel))
		if !levelAllowed(platform, level) {
			audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_KEY_ENROLL_REFUSED", platform, "WARNING", in.SessionDeviceID,
				fmt.Sprintf("Pendaftaran kunci ditolak: tingkat keamanan %q tidak memenuhi kebijakan", truncate(level, 20)))
			return nil, ErrInsecureKey
		}
		key.SecurityLevel = level // client-reported: stored as UNVERIFIED / FAILED, never "verified"
	}
	key.AttestationStatus = att.Status
	summary := truncate(strings.TrimSpace(att.Summary+" "+att.Reason), 200)
	key.AttestationSummary = &summary
	now := time.Now()
	key.AttestationCheckedAt, key.CreatedAt = &now, now

	txErr := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var u struct {
			DeviceID          string
			DeviceEnrollUntil *time.Time
		}
		if err := tx.Raw(`SELECT device_id, device_enroll_until FROM users WHERE id = ? FOR UPDATE`, in.UserID).Scan(&u).Error; err != nil {
			return err
		}
		if u.DeviceID == "" || u.DeviceID != in.DeviceID {
			return ErrEnrollmentNotAllowed // the binding is another (or a legacy) identifier
		}
		if u.DeviceEnrollUntil == nil || !u.DeviceEnrollUntil.After(time.Now()) {
			return ErrEnrollmentNotAllowed // no OTP-verified (re)binding is pending
		}
		var n int64
		if err := tx.Model(&Key{}).Where("user_id = ? AND status = ?", in.UserID, statusActive).Count(&n).Error; err != nil {
			return err
		}
		if n > 0 {
			return ErrAlreadyEnrolled
		}
		q := tx.Model(&Key{}).Where("key_fingerprint = ?", key.KeyFingerprint)
		if key.AppAttestKeyID != nil {
			q = tx.Model(&Key{}).Where("key_fingerprint = ? OR app_attest_key_id = ?", key.KeyFingerprint, *key.AppAttestKeyID)
		}
		if err := q.Count(&n).Error; err != nil {
			return err
		}
		if n > 0 {
			return ErrInvalidKey // a key is never reused across enrollments
		}
		if err := tx.Create(key).Error; err != nil {
			return err
		}
		return tx.Exec(`UPDATE users SET device_enroll_until = NULL, updated_at = now() WHERE id = ?`, in.UserID).Error
	})
	if txErr != nil {
		if errors.Is(txErr, ErrEnrollmentNotAllowed) || errors.Is(txErr, ErrAlreadyEnrolled) || errors.Is(txErr, ErrInvalidKey) {
			audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_KEY_ENROLL_REFUSED", platform, "WARNING", in.SessionDeviceID,
				"Pendaftaran kunci perangkat ditolak: "+txErr.Error())
		}
		return nil, txErr
	}
	audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_KEY_ENROLLED", platform, "SUCCESS", in.DeviceID,
		fmt.Sprintf("Kunci perangkat terdaftar (%s, %s, %s, attestation %s, fingerprint %s…)",
			platform, key.Algorithm, key.SecurityLevel, key.AttestationStatus, key.KeyFingerprint[:16]))
	return &EnrollResult{Key: key}, nil
}

type RotateInput struct {
	UserID           string
	DeviceID         string
	NewPublicKey     string
	NewSecurityLevel string
	AttestationChain []string
	Proof            Proof  // signature by the current key
	NewKeySignature  string // signature by the new key
}

func (s *Service) Rotate(ctx context.Context, in RotateInput) (*Key, error) {
	if !s.Active() {
		return nil, ErrBindingDisabled
	}
	old, err := s.ActiveKey(ctx, in.UserID)
	if err != nil {
		return nil, err
	}
	if old == nil {
		return nil, ErrNoActiveKey
	}
	if old.Algorithm != AlgES256 {
		return nil, ErrRotationUnsupported
	}
	if !s.keyAccepted(old) {
		s.auditKeyNotAccepted(ctx, old, PurposeRotate)
		return nil, ErrAttestationRequired
	}
	newPub, der, fp, err := ParsePublicKey(in.NewPublicKey)
	if err != nil {
		return nil, err
	}
	if in.Proof.empty() {
		return nil, ErrSignatureRequired
	}
	row, err := s.consume(ctx, in.Proof.ChallengeID, PurposeRotate)
	if err == nil {
		switch {
		case old.DeviceID != in.DeviceID:
			err = fail("KEY_DEVICE_MISMATCH")
		case !strPtrEq(row.UserID, in.UserID) || row.DeviceID != in.DeviceID || !strPtrEq(row.KeyID, old.ID) || !strPtrEq(row.KeyFingerprint, fp):
			err = fail("CHALLENGE_KEY_MISMATCH")
		default:
			msg := SigningMessage(PurposeRotate, row.ID, row.Nonce, in.DeviceID, EnrollContext(fp, in.DeviceID))
			if verr := s.verifyKeyProof(ctx, old, msg, in.Proof.Signature); verr != nil || !verifySignature(newPub, msg, in.NewKeySignature) {
				err = fail("SIGNATURE_INVALID")
			}
		}
	}
	if err != nil {
		s.auditFailure(ctx, in.UserID, in.DeviceID, PurposeRotate, err)
		return nil, err
	}
	att := &AttestationResult{Status: AttestationUnverified, Reason: "NO_ATTESTATION"}
	if old.Platform == "android" && len(in.AttestationChain) > 0 && s.opt.AttestationMode != AttestOff {
		att = VerifyAndroidAttestation(s.opt.Android, in.AttestationChain, der, []byte(row.Nonce))
	}
	if !s.attestationAccepted(att) {
		return nil, ErrAttestationRequired
	}
	// SR-3: rotation never lowers the assurance of the binding, in every attestation mode:
	// a HARDWARE_VERIFIED key is only replaced by a HARDWARE_VERIFIED key of the same or a
	// higher security level (StrongBox > TEE). Anything else needs an OTP re-binding.
	if old.AttestationStatus == AttestationHardwareVerified &&
		(att.Status != AttestationHardwareVerified || levelRank(att.SecurityLevel) < levelRank(old.SecurityLevel)) {
		audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_KEY_ROTATION_REFUSED", old.Platform, "DANGER", in.DeviceID,
			fmt.Sprintf("Rotasi ditolak: kunci baru (%s, %s) lebih lemah dari kunci aktif (%s, %s)", att.Status, att.SecurityLevel, old.AttestationStatus, old.SecurityLevel))
		return nil, ErrAttestationRequired
	}
	level := att.SecurityLevel
	if att.Status != AttestationHardwareVerified {
		level = strings.ToUpper(strings.TrimSpace(in.NewSecurityLevel))
		if !levelAllowed(old.Platform, level) {
			return nil, ErrInsecureKey
		}
	}
	now := time.Now()
	summary := truncate(strings.TrimSpace(att.Summary+" "+att.Reason), 200)
	k := &Key{
		ID: uuid.NewString(), UserID: in.UserID, DeviceID: old.DeviceID, Platform: old.Platform, Algorithm: AlgES256,
		PublicKey: base64.StdEncoding.EncodeToString(der), KeyFingerprint: fp, SecurityLevel: level, Status: statusActive,
		EnrolledVia: "ROTATION", AttestationStatus: att.Status, AttestationSummary: &summary, AttestationCheckedAt: &now, CreatedAt: now,
	}
	txErr := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var dup int64
		if err := tx.Model(&Key{}).Where("key_fingerprint = ?", fp).Count(&dup).Error; err != nil {
			return err
		}
		if dup > 0 {
			return ErrInvalidKey
		}
		res := tx.Model(&Key{}).Where("id = ? AND status = ?", old.ID, statusActive).
			Updates(map[string]interface{}{"status": statusRotated, "revoked_at": time.Now(), "revoked_reason": "ROTATED"})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return ErrNoActiveKey
		}
		return tx.Create(k).Error
	})
	if txErr != nil {
		return nil, txErr
	}
	audit.Record(ctx, s.db, "NASABAH", in.UserID, "", "DEVICE_KEY_ROTATED", old.Platform, "SUCCESS", in.DeviceID,
		fmt.Sprintf("Kunci perangkat dirotasi (%s, attestation %s, fingerprint baru %s…)", level, att.Status, fp[:16]))
	return k, nil
}

type Summary struct {
	Mode                  string `json:"mode"`
	ConfiguredMode        string `json:"configured_mode"`
	ProtectionDisabled    bool   `json:"protection_disabled"`
	OffReason             string `json:"off_reason,omitempty"`
	OffUntil              string `json:"off_until,omitempty"`
	AttestationMode       string `json:"attestation_mode"`
	BoundCustomers        int64  `json:"bound_customers"`
	EnrolledCustomers     int64  `json:"enrolled_customers"`
	HardwareVerifiedKeys  int64  `json:"hardware_verified_keys"`
	UnverifiedKeys        int64  `json:"unverified_keys"`
	FailedAttestationKeys int64  `json:"failed_attestation_keys"`
	LegacyIdentifiers     int64  `json:"legacy_identifiers"`
	EnrollRefused24h      int64  `json:"enroll_refused_24h"`
	AttestationFailed24h  int64  `json:"attestation_failed_24h"`
	SignatureRejected24   int64  `json:"signature_rejected_24h"`
	ChallengeReplay24h    int64  `json:"challenge_replay_24h"`
}

func (s *Service) Summary(ctx context.Context) (*Summary, error) {
	out := &Summary{Mode: s.Mode(), ConfiguredMode: s.opt.Mode, AttestationMode: s.opt.AttestationMode, OffReason: s.opt.OffReason}
	out.ProtectionDisabled = out.Mode == ModeOff || out.AttestationMode == AttestOff
	if !s.opt.OffUntil.IsZero() {
		out.OffUntil = s.opt.OffUntil.UTC().Format(time.RFC3339)
	}
	db := s.db.WithContext(ctx)
	audit24 := `SELECT count(*) FROM audit_logs WHERE action = ? AND created_at > now() - interval '24 hours'`
	q := []struct {
		dst  *int64
		sql  string
		args []interface{}
	}{
		{&out.BoundCustomers, `SELECT count(*) FROM users WHERE COALESCE(device_id,'') <> ''`, nil},
		{&out.EnrolledCustomers, `SELECT count(DISTINCT user_id) FROM device_keys WHERE status = 'ACTIVE'`, nil},
		{&out.HardwareVerifiedKeys, `SELECT count(*) FROM device_keys WHERE status = 'ACTIVE' AND attestation_status = 'HARDWARE_VERIFIED'`, nil},
		{&out.UnverifiedKeys, `SELECT count(*) FROM device_keys WHERE status = 'ACTIVE' AND attestation_status = 'UNVERIFIED'`, nil},
		{&out.FailedAttestationKeys, `SELECT count(*) FROM device_keys WHERE status = 'ACTIVE' AND attestation_status = 'FAILED'`, nil},
		{&out.LegacyIdentifiers, `SELECT count(*) FROM users WHERE COALESCE(device_id,'') <> '' AND device_id !~ '^(and-[0-9a-f]{16}|ios-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$'`, nil},
		{&out.EnrollRefused24h, audit24, []interface{}{"DEVICE_KEY_ENROLL_REFUSED"}},
		{&out.AttestationFailed24h, audit24, []interface{}{"DEVICE_ATTESTATION_FAILED"}},
		{&out.SignatureRejected24, audit24, []interface{}{"DEVICE_SIGNATURE_REJECTED"}},
		{&out.ChallengeReplay24h, audit24, []interface{}{"DEVICE_CHALLENGE_REPLAY"}},
	}
	for _, x := range q {
		if err := db.Raw(x.sql, x.args...).Scan(x.dst).Error; err != nil {
			return nil, err
		}
	}
	return out, nil
}

func PurgeChallenges(ctx context.Context, db *gorm.DB, olderThan time.Duration) (int64, error) {
	if olderThan < 24*time.Hour {
		return 0, errors.New("retensi challenge minimal 24 jam")
	}
	res := db.WithContext(ctx).Exec(`DELETE FROM device_challenges WHERE expires_at < now() - make_interval(secs => ?)`,
		int64(olderThan.Seconds()))
	return res.RowsAffected, res.Error
}

func ValidFingerprint(s string) bool { return fpPattern.MatchString(s) }
