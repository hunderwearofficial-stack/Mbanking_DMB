package otp

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/logger"

	"gorm.io/gorm"
)

var (
	ErrOTPGatewayNotConfigured = errors.New("layanan pengiriman OTP belum dikonfigurasi. Silakan hubungi Customer Service Bank DMB")
	ErrOTPSendFailed           = errors.New("kode OTP gagal dikirim. Silakan coba beberapa saat lagi")
	ErrRandomUnavailable       = errors.New("sumber angka acak kriptografis tidak tersedia")
)

var productionMode atomic.Bool

func Configure(isProduction bool) { productionMode.Store(isProduction) }

// gatewayHostAllowed is the OTP_GATEWAY_ALLOWED_HOSTS check (audit E-03). nil = any host.
var gatewayHostAllowed atomic.Value // func(string) bool

// ConfigureGateway installs the allowlist check for OTP gateway hosts.
func ConfigureGateway(allowed func(host string) bool) { gatewayHostAllowed.Store(allowed) }

func hostAllowed(host string) bool {
	if f, ok := gatewayHostAllowed.Load().(func(string) bool); ok && f != nil {
		return f(host)
	}
	return true
}

// gatewayRejected reports a JSON body that explicitly signals failure despite HTTP 2xx
// ("success": false, or "status": "error"/"failed") — audit D-13.
func gatewayRejected(body []byte) bool {
	var m map[string]interface{}
	if json.Unmarshal(body, &m) != nil {
		return false
	}
	if v, ok := m["success"].(bool); ok && !v {
		return true
	}
	if v, ok := m["status"].(string); ok {
		switch strings.ToLower(strings.TrimSpace(v)) {
		case "error", "failed", "fail", "rejected":
			return true
		}
	}
	return false
}

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

func normalizeSMSPhone(phone string) string {
	p := strings.TrimSpace(phone)
	p = strings.TrimPrefix(p, "+")
	if strings.HasPrefix(p, "08") {
		p = "628" + p[2:]
	}
	return p
}

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
	// SECURITY (audit E-08): the token is stored AES-GCM encrypted; legacy plaintext is still read.
	token, decErr := crypto.DecryptString(strings.TrimSpace(cfg.OTPGatewayToken))
	if decErr != nil {
		logger.GetLogger().Error("Token gateway OTP tidak dapat didekripsi", map[string]interface{}{"error": decErr.Error()})
		return "", ErrOTPSendFailed
	}
	token = strings.TrimSpace(token)
	gatewayURL := strings.TrimSpace(cfg.OTPGatewayURL)

	if provider == "" || provider == "SANDBOX" || token == "" {
		if productionMode.Load() {
			logger.GetLogger().Error("OTP tidak dikirim: gateway OTP belum dikonfigurasi di production", map[string]interface{}{
				"phone_masked": maskPhone(phoneNumber), "purpose": purpose,
			})
			return "", ErrOTPGatewayNotConfigured
		}
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
	ttlMinutes := int(SessionTTL().Minutes())
	message := fmt.Sprintf("[%s] Kode OTP Anda: %s untuk %s. Berlaku %d mnt. JANGAN berikan kode ini kpd siapapun termasuk pihak Bank.", bankName, otpCode, purpose, ttlMinutes)

	destPhone := normalizeSMSPhone(phoneNumber)
	client := &http.Client{Timeout: 8 * time.Second}
	var req *http.Request

	switch provider {
	case "JATIS":
		if gatewayURL == "" {
			gatewayURL = "https://api.jatismobile.com/v1/sms/send"
		}
		payload, _ := json.Marshal(map[string]interface{}{
			"sender":      bankName,
			"destination": destPhone,
			"msisdn":      destPhone,
			"message":     message,
		})
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, bytes.NewReader(payload))
		if err == nil {
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("apikey", token)
		}
	default: // SMS_GATEWAY or Generic REST
		if gatewayURL == "" {
			return "", ErrOTPGatewayNotConfigured
		}
		payload, _ := json.Marshal(map[string]interface{}{
			"sender":      bankName,
			"destination": destPhone,
			"phone":       destPhone,
			"message":     message,
			"otp":         otpCode,
			"purpose":     purpose,
		})
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, bytes.NewReader(payload))
		if err == nil {
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("apikey", token)
		}
	}
	if err != nil {
		return "", ErrOTPSendFailed
	}
	if !strings.HasPrefix(strings.ToLower(req.URL.Scheme), "https") {
		logger.GetLogger().Error("OTP gateway URL harus https", map[string]interface{}{"provider": provider})
		return "", ErrOTPSendFailed
	}
	if !hostAllowed(req.URL.Hostname()) {
		logger.GetLogger().Error("Host gateway OTP tidak ada di OTP_GATEWAY_ALLOWED_HOSTS", map[string]interface{}{"provider": provider, "host": req.URL.Hostname()})
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
	if body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10)); gatewayRejected(body) {
		logger.GetLogger().Error("Gateway OTP membalas 2xx tetapi menyatakan gagal", map[string]interface{}{"provider": provider})
		return "", ErrOTPSendFailed
	}
	return otpCode, nil
}
