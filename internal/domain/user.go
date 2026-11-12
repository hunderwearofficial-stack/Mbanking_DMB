package domain

import (
	"time"

	"mbanking-bpr/internal/model"
)

// Re-export model.User as domain.User
type User = model.User

type LoginRequest struct {
	CIF         string `json:"cif"`          // Primary identifier: 12-digit CIF number
	PhoneNumber string `json:"phone_number"` // Alternative identifier: Phone number
	Username    string `json:"username"`     // Optional fallback identifier
	Password    string `json:"password" binding:"required"`
	DeviceID    string `json:"device_id"`    // For device binding check
}

type LoginResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	TokenType    string      `json:"token_type"`
	ExpiresIn    int         `json:"expires_in"` // in seconds (e.g. 900 for 15 mins)
	User         UserProfile `json:"user"`
}

type UserProfile struct {
	ID             string    `json:"id"`
	NIK            string    `json:"nik"`
	CIF            string    `json:"cif"`
	FullName       string    `json:"full_name"`
	PhoneNumber    string    `json:"phone_number"`
	Email          string    `json:"email"`
	Alamat         string    `json:"alamat"`
	KodePos        string    `json:"kode_pos"`
	JenisKelamin   string    `json:"jenis_kelamin"`
	Agama          string    `json:"agama"`
	TglLahir       string    `json:"tgl_lahir"`
	TempatLahir    string    `json:"tempat_lahir"`
	NamaIbuKandung string    `json:"nama_ibu_kandung"`
	DeviceID       string    `json:"device_id"`
	PrimaryAccount string    `json:"primary_account"`
	IsActive       bool      `json:"is_active"`
	CreatedAt      time.Time `json:"created_at"`
}

// Activation / Self-Registration DTOs
type ActivateVerifyRequest struct {
	CIFNumber     string `json:"cif_number"`     // Primary: 12-digit CIF number (e.g. "001000309659")
	AccountNumber string `json:"account_number"` // Fallback / backwards-compatibility
	PhoneNumber   string `json:"phone_number" binding:"required"`
	DeviceID      string `json:"device_id"`
}

type ActivateVerifyResponse struct {
	SessionID   string `json:"session_id"`
	MaskedPhone string `json:"masked_phone"`
	FullName    string `json:"full_name"`
	CIFNumber   string `json:"cif_number"`
	AccountNo   string `json:"account_no"`
}

type ActivateOTPRequest struct {
	SessionID string `json:"session_id" binding:"required"`
	OTPCode   string `json:"otp_code" binding:"required"`
}

type ActivateSetupRequest struct {
	SessionID string `json:"session_id" binding:"required"`
	Password  string `json:"password" binding:"required"`
	PIN       string `json:"pin" binding:"required"`
	DeviceID  string `json:"device_id"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
	DeviceID     string `json:"device_id"`
}

// Forgot Password DTOs
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
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

type ChangePINRequest struct {
	OldPIN string `json:"old_pin" binding:"required"`
	NewPIN string `json:"new_pin" binding:"required"`
}
