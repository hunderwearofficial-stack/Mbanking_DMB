// Pengiriman kode OTP melalui gateway WhatsApp/SMS yang dikonfigurasi di app_configs.
// State/verifikasi OTP ada di store.go (audit DMB-002, DMB-011, DMB-012).

package otp

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"

	"gorm.io/gorm"
)

var (
	// ErrOTPGatewayNotConfigured is returned in production when no real gateway is configured.
	ErrOTPGatewayNotConfigured = errors.New("layanan pengiriman OTP belum dikonfigurasi. Silakan hubungi Customer Service Bank DMB")
	// ErrOTPSendFailed is returned when the gateway rejects or cannot be reached.
	ErrOTPSendFailed = errors.New("kode OTP gagal dikirim. Silakan coba beberapa saat lagi")
	// ErrRandomUnavailable is returned if the CSPRNG fails (never fall back to a predictable source).
	ErrRandomUnavailable = errors.New("sumber angka acak kriptografis tidak tersedia")
)

var productionMode atomic.Bool

// Configure sets environment-dependent behaviour (call once at startup).
func Configure(isProduction bool) { productionMode.Store(isProduction) }

// Generate generates a cryptographically random 6-digit code.
// SECURITY (audit DMB-002): no time-based fallback; failure is an error.
func Generate() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", ErrRandomUnavailable
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func maskPhone(p string) string {
	if len(p) < 8 {
		return "****"
	}
	return p[:4] + "****" + p[len(p)-3:]
}

// Send generates a code, dispatches it through the configured gateway and returns it
// so the caller can store its HMAC. In production, SANDBOX mode is refused and gateway
// failures are returned as errors (audit DMB-011, DMB-012).
func Send(ctx context.Context, db *gorm.DB, phoneNumber, customerName, purpose string) (string, error) {
	otpCode, err := Generate()
	if err != nil {
		return "", err
	}

	var cfg model.AppConfig
	if db != nil {
		_ = db.WithContext(ctx).First(&cfg).Error
	}

	provider := strings.ToUpper(strings.TrimSpace(cfg.OTPProvider))
	token := strings.TrimSpace(cfg.OTPGatewayToken)
	gatewayURL := strings.TrimSpace(cfg.OTPGatewayURL)

	if provider == "" || provider == "SANDBOX" || token == "" {
		if productionMode.Load() {
			logger.GetLogger().Error("OTP tidak dikirim: gateway OTP belum dikonfigurasi di production", map[string]interface{}{
				"phone_masked": maskPhone(phoneNumber), "purpose": purpose,
			})
			return "", ErrOTPGatewayNotConfigured
		}
		// local/development/test only (staging & production return above). The structured
		// logger masks OTP values, so the code is written directly to the console of the
		// developer's own process — never to the log pipeline.
		logger.GetLogger().Warn("[LOCAL/DEV] OTP mode SANDBOX: kode ditampilkan di konsol proses, tidak dikirim ke nasabah", map[string]interface{}{
			"phone_masked": maskPhone(phoneNumber), "purpose": purpose,
		})
		fmt.Fprintf(os.Stderr, "[SANDBOX OTP - HANYA LOCAL/DEVELOPMENT] %s %s: %s\n", purpose, maskPhone(phoneNumber), otpCode)
		return otpCode, nil
	}

	bankName := cfg.BankShortName
	if bankName == "" {
		bankName = "Bank DMB"
	}
	greeting := "Nasabah Yth"
	if customerName != "" {
		greeting = customerName
	}
	message := fmt.Sprintf(
		"*[%s - KODE VERIFIKASI OTP]*\n\nHalo *%s*,\nKode OTP untuk *%s* di aplikasi Mobile DMB Anda adalah:\n\n*%s*\n\nBerlaku selama 3 menit. *JANGAN BERIKAN* kode rahasia ini kepada siapapun termasuk pihak %s.",
		strings.ToUpper(bankName), greeting, purpose, otpCode, bankName,
	)

	client := &http.Client{Timeout: 8 * time.Second}
	var req *http.Request

	switch provider {
	case "FONNTE":
		if gatewayURL == "" {
			gatewayURL = "https://api.fonnte.com/send"
		}
		form := url.Values{}
		form.Set("target", phoneNumber)
		form.Set("message", message)
		form.Set("countryCode", "62")
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, strings.NewReader(form.Encode()))
		if err == nil {
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			req.Header.Set("Authorization", token)
		}
	case "WABLAS":
		if gatewayURL == "" {
			gatewayURL = "https://pati.wablas.com/api/send-message"
		}
		form := url.Values{}
		form.Set("phone", phoneNumber)
		form.Set("message", message)
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, strings.NewReader(form.Encode()))
		if err == nil {
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			req.Header.Set("Authorization", token)
		}
	default: // CUSTOM_WEBHOOK or SMS Gateway JSON
		if gatewayURL == "" {
			return "", ErrOTPGatewayNotConfigured
		}
		payload, _ := json.Marshal(map[string]string{
			"phone": phoneNumber, "otp": otpCode, "purpose": purpose, "message": message,
		})
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, bytes.NewReader(payload))
		if err == nil {
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer "+token)
		}
	}
	if err != nil {
		return "", ErrOTPSendFailed
	}
	if !strings.HasPrefix(strings.ToLower(req.URL.Scheme), "https") {
		logger.GetLogger().Error("OTP gateway URL harus https", map[string]interface{}{"provider": provider})
		return "", ErrOTPSendFailed
	}

	resp, err := client.Do(req)
	if err != nil {
		logger.GetLogger().Error("Gagal mengirim OTP via gateway", map[string]interface{}{"provider": provider, "error": err.Error()})
		return "", ErrOTPSendFailed
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		logger.GetLogger().Error("Gateway OTP menolak permintaan", map[string]interface{}{"provider": provider, "status": resp.StatusCode})
		return "", ErrOTPSendFailed
	}
	return otpCode, nil
}
