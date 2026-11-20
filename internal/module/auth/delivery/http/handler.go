package http

import (
	"errors"
	"net/http"

	"mbanking-bpr/internal/devicebind"
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

func writeAuthError(c *gin.Context, err error, status int) {
	switch {
	case errors.Is(err, legaldoc.ErrConsentRequired), errors.Is(err, legaldoc.ErrInvalidAcceptance),
		errors.Is(err, legaldoc.ErrNoActiveVersion), errors.Is(err, legaldoc.ErrVersionNotActive):
		legaldoc.WriteError(c, err)
	case errors.Is(err, service.ErrServiceUnavailable), errors.Is(err, session.ErrUnavailable):
		response.Error(c, http.StatusServiceUnavailable, service.ErrServiceUnavailable.Error(), "99", nil)
	case errors.Is(err, devicebind.ErrSignatureRequired), errors.Is(err, devicebind.ErrVerificationFailed):
		response.Error(c, http.StatusForbidden, err.Error(), devicebind.CodeDeviceVerification, gin.H{"action": "SIGN_DEVICE_CHALLENGE"})
	case errors.Is(err, devicebind.ErrEnrollmentNotAllowed):
		response.Error(c, http.StatusForbidden, err.Error(), "08", gin.H{"action": "VERIFY_DEVICE_VIA_FORGOT_PASSWORD"})
	case errors.Is(err, devicebind.ErrAttestationRequired):
		response.Error(c, http.StatusForbidden, err.Error(), devicebind.CodeAttestationRequired, gin.H{"action": "DEVICE_NOT_SUPPORTED"})
	case errors.Is(err, devicebind.ErrAttestationUnavailable):
		response.Error(c, http.StatusServiceUnavailable, err.Error(), "99", nil)
	case errors.Is(err, devicebind.ErrAlreadyEnrolled), errors.Is(err, devicebind.ErrNoActiveKey), errors.Is(err, devicebind.ErrRotationUnsupported):
		response.Error(c, http.StatusConflict, err.Error(), "07", nil)
	case errors.Is(err, devicebind.ErrBindingDisabled):
		response.Error(c, http.StatusServiceUnavailable, err.Error(), "99", nil)
	case errors.Is(err, devicebind.ErrInvalidKey), errors.Is(err, devicebind.ErrInsecureKey),
		errors.Is(err, devicebind.ErrInvalidDeviceID), errors.Is(err, devicebind.ErrInvalidPurpose):
		response.Error(c, http.StatusUnprocessableEntity, err.Error(), response.CodeBadRequest, nil)
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

func (h *AuthHandler) Login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Format data masuk tidak valid", nil)
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

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req domain.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Data pembaruan sesi tidak lengkap", nil)
		return
	}
	res, err := h.authService.RefreshToken(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusUnauthorized)
		return
	}
	response.Success(c, "Sesi berhasil diperbarui", res)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	if err := h.authService.Logout(c.Request.Context(), c.GetString(middleware.CtxUserID), clientInfo(c)); err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Logout berhasil", gin.H{"logged_out": true})
}

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

func (h *AuthHandler) VerifyActivationOTP(c *gin.Context) {
	var req domain.ActivateOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Sesi dan kode OTP wajib disertakan", nil)
		return
	}
	res, err := h.authService.VerifyActivationOTP(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Kode OTP berhasil diverifikasi.", gin.H{
		"verified": true, "full_name": res.FullName, "cif_number": res.CIFNumber, "account_no": res.AccountNo,
		"masked_phone": res.MaskedPhone, "suggested_username": res.SuggestedUsername,
	})
}

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

// RevealProfile returns the unmasked identity data after a server-side PIN check (audit D-09).
func (h *AuthHandler) RevealProfile(c *gin.Context) {
	userID := c.GetString(middleware.CtxUserID)
	if userID == "" {
		response.Unauthorized(c, response.CodeUnauthorized, "Sesi tidak valid")
		return
	}
	var req struct {
		PIN string `json:"pin" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, service.ErrPINRequired.Error(), nil)
		return
	}
	data, err := h.authService.RevealProfile(c.Request.Context(), userID, req.PIN, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Data identitas berhasil dibuka", data)
}

func (h *AuthHandler) DeviceChallenge(c *gin.Context) {
	var req domain.DeviceChallengeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Tujuan verifikasi perangkat wajib diisi", nil)
		return
	}
	res, err := h.authService.DeviceChallenge(c.Request.Context(), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Permintaan verifikasi perangkat dibuat", res)
}

func (h *AuthHandler) SessionDeviceChallenge(c *gin.Context) {
	var req domain.DeviceChallengeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Tujuan verifikasi perangkat wajib diisi", nil)
		return
	}
	res, err := h.authService.SessionDeviceChallenge(c.Request.Context(), c.GetString(middleware.CtxUserID), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Permintaan verifikasi perangkat dibuat", res)
}

func (h *AuthHandler) EnrollDevice(c *gin.Context) {
	var req domain.EnrollDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Data pendaftaran kunci perangkat tidak lengkap", nil)
		return
	}
	res, err := h.authService.EnrollDevice(c.Request.Context(), c.GetString(middleware.CtxUserID), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Kunci keamanan perangkat berhasil didaftarkan", res)
}

func (h *AuthHandler) RotateDeviceKey(c *gin.Context) {
	var req domain.RotateDeviceKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Data rotasi kunci perangkat tidak lengkap", nil)
		return
	}
	res, err := h.authService.RotateDeviceKey(c.Request.Context(), c.GetString(middleware.CtxUserID), req, clientInfo(c))
	if err != nil {
		writeAuthError(c, err, http.StatusBadRequest)
		return
	}
	response.Success(c, "Kunci keamanan perangkat berhasil diperbarui", res)
}

func (h *AuthHandler) DeviceStatus(c *gin.Context) {
	response.Success(c, "Status perangkat", h.authService.DeviceStatus(c.Request.Context(), c.GetString(middleware.CtxUserID), clientInfo(c)))
}
