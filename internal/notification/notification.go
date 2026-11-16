// Package notification menyimpan notifikasi in-app nasabah dan meneruskannya sebagai
// push notification (FCM). Detail transaksi/keamanan hanya disimpan di inbox in-app;
// kanal push pihak ketiga hanya menerima teks generik (minimisasi data, audit DMB-022).
package notification

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"

	"gorm.io/gorm"
)

// Kategori notifikasi yang dikenal aplikasi mobile.
const (
	CategoryTransaction = "TRANSACTION"
	CategorySecurity    = "SECURITY"
	CategoryInfo        = "INFO"
	CategoryPromo       = "PROMO"

	// Broadcast is the pseudo user id for notifications addressed to all customers.
	Broadcast = "ALL"
)

// pushBody returns the text sent through the third-party push channel. Details of
// security and transaction events (amounts, account numbers, device ids) stay in the
// in-app inbox only (data minimisation, audit DMB-022).
func pushBody(category, message string) string {
	switch strings.ToUpper(category) {
	case CategoryTransaction:
		return "Ada aktivitas transaksi pada akun Mobile DMB Anda. Buka aplikasi untuk melihat detail."
	case CategorySecurity:
		return "Ada aktivitas keamanan pada akun Mobile DMB Anda. Buka aplikasi untuk melihat detail."
	}
	return message
}

// CreateAndPush stores the notification in the in-app inbox and, if
// configured, dispatches a push notification.
//
// NOTE (audit DMB-027, BLOCKED): dispatch still uses the FCM legacy HTTP API with a
// server key. Migrating to FCM HTTP v1 requires a Firebase service account that is
// not available in this repository.
func CreateAndPush(ctx context.Context, db *gorm.DB, userID, title, message, category string) {
	if db == nil {
		return
	}
	notif := model.Notification{
		UserID: userID, Title: title, Message: message, Category: category, IsRead: false, CreatedAt: time.Now(),
	}
	if err := db.WithContext(ctx).Create(&notif).Error; err != nil {
		logger.GetLogger().Error("Gagal menyimpan notifikasi", map[string]interface{}{"error": err.Error()})
	}

	var cfg model.AppConfig
	if err := db.WithContext(ctx).First(&cfg).Error; err != nil || strings.TrimSpace(cfg.FCMServerKey) == "" {
		return
	}

	var fcmTokens []string
	if userID == Broadcast {
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

	body := pushBody(category, message)
	go func(serverKey string, tokens []string, t, m, cat string) {
		client := &http.Client{Timeout: 6 * time.Second}
		for _, tk := range tokens {
			payload, _ := json.Marshal(map[string]interface{}{
				"to":           tk,
				"notification": map[string]string{"title": t, "body": m, "sound": "default"},
				"data":         map[string]string{"category": cat},
			})
			req, err := http.NewRequest(http.MethodPost, "https://fcm.googleapis.com/fcm/send", bytes.NewReader(payload))
			if err != nil {
				continue
			}
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "key="+serverKey)
			if resp, doErr := client.Do(req); doErr == nil {
				resp.Body.Close()
			}
		}
	}(strings.TrimSpace(cfg.FCMServerKey), fcmTokens, title, body, category)
}
