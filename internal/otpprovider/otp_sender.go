package otpprovider

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"

	"gorm.io/gorm"
)

// GenerateOTP generates a cryptographic 6-digit numeric OTP code
func GenerateOTP() string {
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return fmt.Sprintf("%06d", time.Now().UnixNano()%900000+100000)
	}
	return fmt.Sprintf("%06d", n.Int64()+100000)
}

// SendOTP dispatches a 6-digit OTP via the configured WhatsApp/SMS Gateway in AppConfig.
// Returns (otpCode, isSandboxMode, error)
func SendOTP(ctx context.Context, db *gorm.DB, phoneNumber, customerName, purpose string) (string, bool, error) {
	otpCode := GenerateOTP()

	var cfg model.AppConfig
	if db != nil {
		_ = db.WithContext(ctx).First(&cfg).Error
	}

	provider := strings.ToUpper(strings.TrimSpace(cfg.OTPProvider))
	token := strings.TrimSpace(cfg.OTPGatewayToken)
	gatewayURL := strings.TrimSpace(cfg.OTPGatewayURL)

	if provider == "" || provider == "SANDBOX" || token == "" {
		logger.GetLogger().Info("OTP dikirim dalam mode SANDBOX", map[string]interface{}{
			"phone":   phoneNumber,
			"purpose": purpose,
			"otp":     otpCode,
		})
		return otpCode, true, nil
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
		strings.ToUpper(bankName),
		greeting,
		purpose,
		otpCode,
		bankName,
	)

	client := &http.Client{Timeout: 8 * time.Second}

	switch provider {
	case "FONNTE":
		if gatewayURL == "" {
			gatewayURL = "https://api.fonnte.com/send"
		}
		form := url.Values{}
		form.Set("target", phoneNumber)
		form.Set("message", message)
		form.Set("countryCode", "62")

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, strings.NewReader(form.Encode()))
		if err != nil {
			return otpCode, false, err
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		req.Header.Set("Authorization", token)

		resp, err := client.Do(req)
		if err != nil {
			logger.GetLogger().Warn("Gagal mengirim WA OTP via Fonnte, fallback ke kode internal", map[string]interface{}{
				"error": err.Error(),
			})
			return otpCode, false, nil
		}
		defer resp.Body.Close()

	case "WABLAS":
		if gatewayURL == "" {
			gatewayURL = "https://pati.wablas.com/api/send-message"
		}
		form := url.Values{}
		form.Set("phone", phoneNumber)
		form.Set("message", message)

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, strings.NewReader(form.Encode()))
		if err != nil {
			return otpCode, false, err
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		req.Header.Set("Authorization", token)

		resp, err := client.Do(req)
		if err != nil {
			logger.GetLogger().Warn("Gagal mengirim WA OTP via Wablas", map[string]interface{}{
				"error": err.Error(),
			})
			return otpCode, false, nil
		}
		defer resp.Body.Close()

	default: // CUSTOM_WEBHOOK or SMS Gateway JSON
		if gatewayURL != "" {
			payload, _ := json.Marshal(map[string]string{
				"phone":   phoneNumber,
				"otp":     otpCode,
				"purpose": purpose,
				"message": message,
			})
			req, err := http.NewRequestWithContext(ctx, http.MethodPost, gatewayURL, bytes.NewReader(payload))
			if err == nil {
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("Authorization", "Bearer "+token)
				if resp, doErr := client.Do(req); doErr == nil {
					resp.Body.Close()
				}
			}
		}
	}

	return otpCode, false, nil
}

// SendPushNotification dispatches an FCM push notification if FCMServerKey & user FCMToken are available,
// and always stores the notification in PostgreSQL notifications inbox.
func CreateNotificationAndPush(ctx context.Context, db *gorm.DB, userID, title, message, category string) {
	if db == nil {
		return
	}

	notif := model.Notification{
		UserID:    userID,
		Title:     title,
		Message:   message,
		Category:  category,
		IsRead:    false,
		CreatedAt: time.Now(),
	}
	_ = db.WithContext(ctx).Create(&notif).Error

	// Optional Firebase Cloud Messaging (FCM) dispatch if configured
	var cfg model.AppConfig
	if err := db.WithContext(ctx).First(&cfg).Error; err != nil || strings.TrimSpace(cfg.FCMServerKey) == "" {
		return
	}

	var fcmTokens []string
	if userID == "ALL" {
		_ = db.WithContext(ctx).Model(&model.User{}).Where("fcm_token <> '' AND is_active = ?", true).Pluck("fcm_token", &fcmTokens).Error
	} else {
		var u model.User
		if err := db.WithContext(ctx).Select("fcm_token").Where("id = ?", userID).First(&u).Error; err == nil && u.FCMToken != "" {
			fcmTokens = append(fcmTokens, u.FCMToken)
		}
	}

	if len(fcmTokens) == 0 {
		return
	}

	go func(serverKey string, tokens []string, t, m, cat string) {
		client := &http.Client{Timeout: 6 * time.Second}
		for _, tk := range tokens {
			body, _ := json.Marshal(map[string]interface{}{
				"to": tk,
				"notification": map[string]string{
					"title": t,
					"body":  m,
					"sound": "default",
				},
				"data": map[string]string{
					"category": cat,
				},
			})
			req, err := http.NewRequest(http.MethodPost, "https://fcm.googleapis.com/fcm/send", bytes.NewReader(body))
			if err == nil {
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("Authorization", "key="+serverKey)
				if resp, doErr := client.Do(req); doErr == nil {
					resp.Body.Close()
				}
			}
		}
	}(strings.TrimSpace(cfg.FCMServerKey), fcmTokens, title, message, category)
}

// RecordAuditLog writes an immutable security/operational audit trail entry to PostgreSQL
func RecordAuditLog(ctx context.Context, db *gorm.DB, actorType, actorID, actorName, action, target, status, deviceID, details string) {
	if db == nil {
		return
	}
	entry := model.AuditLog{
		ActorType: actorType,
		ActorID:   actorID,
		ActorName: actorName,
		Action:    action,
		Target:    target,
		Status:    status,
		DeviceID:  deviceID,
		Details:   details,
		CreatedAt: time.Now(),
	}
	_ = db.WithContext(ctx).Create(&entry).Error
}

