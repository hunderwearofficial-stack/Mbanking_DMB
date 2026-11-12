package http

import (
	"errors"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/auth/service"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	authService service.AuthService
}

func NewAuthHandler(authService service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

// Login handles POST /api/v1/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data request login tidak valid", err.Error())
		return
	}

	// Read device_id from header if not in body
	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}

	res, err := h.authService.Login(c.Request.Context(), req)
	if err != nil {
		if errors.Is(err, service.ErrDeviceBindingMismatch) {
			response.Unauthorized(c, response.CodeUnauthorized, err.Error())
			return
		}
		if errors.Is(err, service.ErrUserInactive) {
			response.Unauthorized(c, response.CodeUnauthorized, err.Error())
			return
		}
		response.Unauthorized(c, response.CodeInvalidCredentials, err.Error())
		return
	}

	response.Success(c, "Login nasabah berhasil", res)
}

// RefreshToken handles POST /api/v1/auth/refresh
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req domain.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Refresh token wajib disertakan", err.Error())
		return
	}

	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}

	res, err := h.authService.RefreshToken(c.Request.Context(), req)
	if err != nil {
		response.Unauthorized(c, response.CodeUnauthorized, err.Error())
		return
	}

	response.Success(c, "Sesi berhasil diperbarui", res)
}

// VerifyActivation handles POST /api/v1/auth/activate/verify
func (h *AuthHandler) VerifyActivation(c *gin.Context) {
	var req domain.ActivateVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Nomor CIF dan nomor handphone wajib diisi", err.Error())
		return
	}

	if req.CIFNumber == "" && req.AccountNumber == "" {
		response.BadRequest(c, "Nomor CIF wajib diisi", nil)
		return
	}

	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}

	res, err := h.authService.VerifyActivation(c.Request.Context(), req)
	if err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}

	response.Success(c, "Data rekening nasabah terverifikasi. Kode OTP telah dikirimkan.", res)
}

// VerifyActivationOTP handles POST /api/v1/auth/activate/otp
func (h *AuthHandler) VerifyActivationOTP(c *gin.Context) {
	var req domain.ActivateOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Sesi dan kode OTP wajib disertakan", err.Error())
		return
	}

	if err := h.authService.VerifyActivationOTP(c.Request.Context(), req); err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}

	response.Success(c, "Kode OTP berhasil diverifikasi.", gin.H{"verified": true})
}

// CompleteActivation handles POST /api/v1/auth/activate/setup
func (h *AuthHandler) CompleteActivation(c *gin.Context) {
	var req domain.ActivateSetupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data setup password dan PIN tidak valid", err.Error())
		return
	}

	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}

	res, err := h.authService.CompleteActivation(c.Request.Context(), req)
	if err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}

	response.Success(c, "Aktivasi Mobile Banking Bank DMB berhasil diselesaikan!", res)
}

// RequestForgotPassword handles POST /api/v1/auth/forgot-password/request
func (h *AuthHandler) RequestForgotPassword(c *gin.Context) {
	var req domain.ForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Nomor handphone wajib diisi", err.Error())
		return
	}
	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}
	res, err := h.authService.RequestForgotPassword(c.Request.Context(), req)
	if err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}
	response.Success(c, "Kode OTP reset password telah dikirimkan", res)
}

// VerifyForgotPasswordOTP handles POST /api/v1/auth/forgot-password/otp
func (h *AuthHandler) VerifyForgotPasswordOTP(c *gin.Context) {
	var req domain.ForgotPasswordVerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Sesi dan kode OTP wajib diisi", err.Error())
		return
	}
	if err := h.authService.VerifyForgotPasswordOTP(c.Request.Context(), req); err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}
	response.Success(c, "Kode OTP berhasil diverifikasi", gin.H{"verified": true})
}

// ResetForgotPassword handles POST /api/v1/auth/forgot-password/reset
func (h *AuthHandler) ResetForgotPassword(c *gin.Context) {
	var req domain.ForgotPasswordResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Password baru wajib diisi", err.Error())
		return
	}
	if req.DeviceID == "" {
		req.DeviceID = c.GetHeader(middleware.HeaderDeviceID)
	}
	if err := h.authService.ResetForgotPassword(c.Request.Context(), req); err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}
	response.Success(c, "Password berhasil diperbarui. Silakan masuk kembali.", gin.H{"reset": true})
}

// ChangePassword handles POST /api/v1/auth/change-password
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := c.GetString(middleware.CtxUserID)
	if userID == "" {
		response.Unauthorized(c, response.CodeUnauthorized, "Sesi tidak valid")
		return
	}
	var req domain.ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Password lama dan password baru (minimal 8 karakter) wajib diisi", err.Error())
		return
	}
	if err := h.authService.ChangePassword(c.Request.Context(), userID, req); err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}
	response.Success(c, "Password login Anda berhasil diperbarui", gin.H{"updated": true})
}

// ChangePIN handles POST /api/v1/auth/change-pin
func (h *AuthHandler) ChangePIN(c *gin.Context) {
	userID := c.GetString(middleware.CtxUserID)
	if userID == "" {
		response.Unauthorized(c, response.CodeUnauthorized, "Sesi tidak valid")
		return
	}
	var req domain.ChangePINRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "PIN lama dan PIN baru (6 digit) wajib diisi", err.Error())
		return
	}
	if err := h.authService.ChangePIN(c.Request.Context(), userID, req); err != nil {
		response.BadRequest(c, err.Error(), nil)
		return
	}
	response.Success(c, "PIN Transaksi 6 Digit Anda berhasil diperbarui", gin.H{"updated": true})
}
