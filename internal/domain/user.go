package domain

import (
	"time"

	"mbanking-bpr/internal/model"
)

type User = model.User

type LoginRequest struct {
	CIF               string `json:"cif"`          // Primary identifier: 12-digit CIF number
	PhoneNumber       string `json:"phone_number"` // Alternative identifier: Phone number
	Username          string `json:"username"`     // Optional fallback identifier
	Password          string `json:"password" binding:"required"`
	DeviceID          string `json:"device_id"` // For device binding check
	TermsAcceptanceID string `json:"terms_acceptance_id"`
	DeviceChallengeID string `json:"device_challenge_id"`
	DeviceSignature   string `json:"device_signature"`
}

type LoginResponse struct {
	AccessToken   string               `json:"access_token"`
	RefreshToken  string               `json:"refresh_token"`
	TokenType     string               `json:"token_type"`
	ExpiresIn     int                  `json:"expires_in"` // in seconds (e.g. 900 for 15 mins)
	User          UserProfile          `json:"user"`
	DeviceBinding *DeviceBindingStatus `json:"device_binding,omitempty"`
}

type DeviceBindingStatus struct {
	Mode              string `json:"mode"`               // off | dual | enforced
	AttestationMode   string `json:"attestation_mode"`   // off | observe | enforce
	Enrolled          bool   `json:"enrolled"`           // an active device key exists
	KeyAlgorithm      string `json:"key_algorithm"`      // ES256 | APPATTEST
	SecurityLevel     string `json:"security_level"`     // STRONGBOX | TEE | SECURE_ENCLAVE
	AttestationStatus string `json:"attestation_status"` // HARDWARE_VERIFIED | UNVERIFIED | FAILED
	Enrollment        string `json:"enrollment"`         // ALLOWED | OTP_REQUIRED | NOT_NEEDED | NOT_AVAILABLE
	SessionDeviceID   string `json:"session_device_id"`  // identifier bound to this session
}

type DeviceChallengeRequest struct {
	Purpose         string `json:"purpose" binding:"required"`
	PhoneNumber     string `json:"phone_number"`
	CIF             string `json:"cif"`
	RefreshToken    string `json:"refresh_token"`
	DeviceID        string `json:"device_id"`
	PublicKeySHA256 string `json:"public_key_sha256"`
}

type DeviceChallengeResponse struct {
	ChallengeID   string    `json:"challenge_id"`
	Nonce         string    `json:"nonce"`
	Purpose       string    `json:"purpose"`
	ExpiresAt     time.Time `json:"expires_at"`
	SigningFormat string    `json:"signing_format"`
}

type EnrollDeviceRequest struct {
	DeviceID          string   `json:"device_id" binding:"required"` // canonical and-… / ios-…
	Platform          string   `json:"platform" binding:"required"`
	AttestationFormat string   `json:"attestation_format"`
	PublicKey         string   `json:"public_key"`
	SecurityLevel     string   `json:"security_level"`
	AttestationChain  []string `json:"attestation_chain"`
	AppAttestKeyID    string   `json:"app_attest_key_id"`
	AttestationObject string   `json:"attestation_object"`
	ChallengeID       string   `json:"challenge_id" binding:"required"`
	Signature         string   `json:"signature"`
}

type RotateDeviceKeyRequest struct {
	NewPublicKey     string   `json:"new_public_key" binding:"required"`
	NewSecurityLevel string   `json:"new_security_level" binding:"required"`
	AttestationChain []string `json:"attestation_chain"`
	ChallengeID      string   `json:"challenge_id" binding:"required"`
	Signature        string   `json:"signature" binding:"required"`
	NewKeySignature  string   `json:"new_key_signature" binding:"required"`
}

type UserProfile struct {
	ID             string    `json:"id"`
	CIF            string    `json:"cif"`
	FullName       string    `json:"full_name"`
	Username       string    `json:"username,omitempty"`
	PhoneNumber    string    `json:"phone_number"`
	Email          string    `json:"email"`
	KodePos        string    `json:"kode_pos"`
	JenisKelamin   string    `json:"jenis_kelamin"`
	Agama          string    `json:"agama"`
	TglLahir       string    `json:"tgl_lahir"`
	TempatLahir    string    `json:"tempat_lahir"`
	DeviceID       string    `json:"device_id"`
	PrimaryAccount string    `json:"primary_account"`
	IsActive       bool      `json:"is_active"`
	CreatedAt      time.Time `json:"created_at"`
}

type ActivateVerifyRequest struct {
	CIFNumber     string `json:"cif_number"`     // Primary: 12-digit CIF number
	AccountNumber string `json:"account_number"` // Fallback / backwards-compatibility
	PhoneNumber   string `json:"phone_number" binding:"required"`
	DeviceID      string `json:"device_id"`
}

type ActivateVerifyResponse struct {
	SessionID         string `json:"session_id"`
	MaskedPhone       string `json:"masked_phone"`
	FullName          string `json:"full_name"`
	CIFNumber         string `json:"cif_number"`
	AccountNo         string `json:"account_no"`
	SuggestedUsername string `json:"suggested_username,omitempty"`
}

type ActivateOTPRequest struct {
	SessionID string `json:"session_id" binding:"required"`
	OTPCode   string `json:"otp_code" binding:"required"`
}

type ActivateSetupRequest struct {
	SessionID         string `json:"session_id" binding:"required"`
	Username          string `json:"username"`
	Password          string `json:"password" binding:"required"`
	PIN               string `json:"pin" binding:"required"`
	DeviceID          string `json:"device_id"`
	TermsAcceptanceID string `json:"terms_acceptance_id"`
}

type RefreshTokenRequest struct {
	RefreshToken      string `json:"refresh_token" binding:"required"`
	DeviceID          string `json:"device_id"`
	DeviceChallengeID string `json:"device_challenge_id"`
	DeviceSignature   string `json:"device_signature"`
}

type ForgotPasswordRequest struct {
	PhoneNumber string `json:"phone_number" binding:"required"`
	DeviceID    string `json:"device_id"`
}

type ForgotPasswordVerifyOTPRequest struct {
	SessionID string `json:"session_id" binding:"required"`
	OTPCode   string `json:"otp_code" binding:"required"`
}

type ForgotPasswordResetRequest struct {
	SessionID   string `json:"session_id" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
	DeviceID    string `json:"device_id"`
}

type ChangePasswordRequest struct {
	OldPassword       string `json:"old_password" binding:"required"`
	NewPassword       string `json:"new_password" binding:"required"`
	DeviceChallengeID string `json:"device_challenge_id"`
	DeviceSignature   string `json:"device_signature"`
}

type ChangePINRequest struct {
	OldPIN            string `json:"old_pin" binding:"required"`
	NewPIN            string `json:"new_pin" binding:"required"`
	DeviceChallengeID string `json:"device_challenge_id"`
	DeviceSignature   string `json:"device_signature"`
}
