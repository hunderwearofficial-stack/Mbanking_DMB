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
		response.BadRequest(c, "Nomor rekening dan nomor handphone wajib diisi", err.Error())
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
