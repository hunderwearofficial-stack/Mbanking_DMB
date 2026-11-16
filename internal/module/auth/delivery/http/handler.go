package http

import (
	"errors"
	"net/http"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/module/auth/service"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/internal/session"
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

func clientInfo(c *gin.Context) service.ClientInfo {
	dev := c.GetString(middleware.CtxDeviceID)
	if dev == "" {
		dev = c.GetHeader(middleware.HeaderDeviceID)
	}
	return service.ClientInfo{
		DeviceID:  dev,
		IP:        c.ClientIP(),
		SessionID: c.GetString(middleware.CtxSessionID),
		UserAgent: c.Request.UserAgent(),
	}
}

// writeAuthError maps service errors to HTTP responses. Only messages of known,
// user-facing errors are returned; unexpected errors produce a generic message.
func writeAuthError(c *gin.Context, err error, status int) {
	switch {
	case errors.Is(err, legaldoc.ErrConsentRequired), errors.Is(err, legaldoc.ErrInvalidAcceptance),
		errors.Is(err, legaldoc.ErrNoActiveVersion), errors.Is(err, legaldoc.ErrVersionNotActive):
		legaldoc.WriteError(c, err)
	case errors.Is(err, service.ErrServiceUnavailable), errors.Is(err, session.ErrUnavailable):
		response.Error(c, http.StatusServiceUnavailable, service.ErrServiceUnavailable.Error(), "99", nil)
	case errors.Is(err, session.ErrConcurrentRefresh):
		response.Error(c, http.StatusConflict, err.Error(), "07", nil)
	case errors.Is(err, otp.ErrTooManyAttempts), errors.Is(err, otp.ErrSessionNotFound),
		errors.Is(err, otp.ErrInvalidCode), errors.Is(err, otp.ErrNotVerified),
		errors.Is(err, otp.ErrDeviceMismatch), errors.Is(err, otp.ErrPurposeMismatch):
		response.BadRequest(c, err.Error(), nil)
	default:
		if status == http.StatusUnauthorized {
			response.Unauthorized(c, response.CodeInvalidCredentials, err.Error())
			return
		}
		response.BadRequest(c, err.Error(), nil)
	}
}

// Login handles POST /api/v1/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data request login tidak valid", nil)
		return
	}
	ci := clientInfo(c)
	if req.DeviceID == "" {
		req.DeviceID = ci.DeviceID
	}
	res, err := h.authService.Login(c.Request.Context(), req, ci)
	if err != nil {
		if errors.Is(err, service.ErrNewDeviceVerification) {
			response.Error(c, http.StatusForbidden, err.Error(), "08", gin.H{"action": "VERIFY_DEVICE_VIA_FORGOT_PASSWORD"})
			return
		}
		writeAuthError(c, err, http.StatusUnauthorized)
		return
	}
	response.Success(c, "Login nasabah berhasil", res)
}

// RefreshToken handles POST /api/v1/auth/refresh
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req domain.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Refresh token wajib disertakan", nil)
		return
	}
	res, err := h.authService.RefreshToken(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusUnauthorized)
		return
	}
	response.Success(c, "Sesi berhasil diperbarui", res)
}

// Logout handles POST /api/v1/auth/logout (authenticated): revokes the server-side session.
func (h *AuthHandler) Logout(c *gin.Context) {
	if err := h.authService.Logout(c.Request.Context(), c.GetString(middleware.CtxUserID), clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Logout berhasil", gin.H{"logged_out": true})
}

// VerifyActivation handles POST /api/v1/auth/activate/verify
func (h *AuthHandler) VerifyActivation(c *gin.Context) {
	var req domain.ActivateVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Nomor CIF dan nomor handphone wajib diisi", nil)
		return
	}
	res, err := h.authService.VerifyActivation(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Data rekening nasabah terverifikasi. Kode OTP telah dikirimkan.", res)
}

// VerifyActivationOTP handles POST /api/v1/auth/activate/otp
func (h *AuthHandler) VerifyActivationOTP(c *gin.Context) {
	var req domain.ActivateOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Sesi dan kode OTP wajib disertakan", nil)
		return
	}
	if err := h.authService.VerifyActivationOTP(c.Request.Context(), req, clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Kode OTP berhasil diverifikasi.", gin.H{"verified": true})
}

// CompleteActivation handles POST /api/v1/auth/activate/setup
func (h *AuthHandler) CompleteActivation(c *gin.Context) {
	var req domain.ActivateSetupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data setup password dan PIN tidak valid", nil)
		return
	}
	res, err := h.authService.CompleteActivation(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Aktivasi Mobile Banking Bank DMB berhasil diselesaikan!", res)
}

// RequestForgotPassword handles POST /api/v1/auth/forgot-password/request
func (h *AuthHandler) RequestForgotPassword(c *gin.Context) {
	var req domain.ForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Nomor handphone wajib diisi", nil)
		return
	}
	res, err := h.authService.RequestForgotPassword(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Jika nomor terdaftar, kode OTP reset password telah dikirimkan", res)
}

// VerifyForgotPasswordOTP handles POST /api/v1/auth/forgot-password/otp
func (h *AuthHandler) VerifyForgotPasswordOTP(c *gin.Context) {
	var req domain.ForgotPasswordVerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Sesi dan kode OTP wajib diisi", nil)
		return
	}
	if err := h.authService.VerifyForgotPasswordOTP(c.Request.Context(), req, clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Kode OTP berhasil diverifikasi", gin.H{"verified": true})
}

// ResetForgotPassword handles POST /api/v1/auth/forgot-password/reset
func (h *AuthHandler) ResetForgotPassword(c *gin.Context) {
	var req domain.ForgotPasswordResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Password baru wajib diisi", nil)
		return
	}
	if err := h.authService.ResetForgotPassword(c.Request.Context(), req, clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
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
		response.BadRequest(c, "Password lama dan password baru wajib diisi", nil)
		return
	}
	if err := h.authService.ChangePassword(c.Request.Context(), userID, req, clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
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
		response.BadRequest(c, "PIN lama dan PIN baru (6 digit) wajib diisi", nil)
		return
	}
	if err := h.authService.ChangePIN(c.Request.Context(), userID, req, clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "PIN Transaksi 6 Digit Anda berhasil diperbarui", gin.H{"updated": true})
}
