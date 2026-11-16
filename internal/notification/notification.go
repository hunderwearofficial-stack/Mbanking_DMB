// Package notification menyimpan notifikasi in-app nasabah dan meneruskannya sebagai
// push notification (FCM HTTP v1 melalui internal/push). Detail transaksi/keamanan hanya disimpan di inbox in-app;
// kanal push pihak ketiga hanya menerima teks generik (minimisasi data, audit DMB-022).
package notification

import (
	"context"
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

// PushBody returns the text sent through the third-party push channel. Details of
// security and transaction events (amounts, account numbers, device ids) stay in the
// in-app inbox only (data minimisation, audit DMB-022).
func PushBody(category, message string) string {
	switch strings.ToUpper(category) {
	case CategoryTransaction:
		return "Ada aktivitas transaksi pada akun Mobile DMB Anda. Buka aplikasi untuk melihat detail."
	case CategorySecurity:
		return "Ada aktivitas keamanan pada akun Mobile DMB Anda. Buka aplikasi untuk melihat detail."
	}
	return message
}

// Pusher delivers a push notification to all active devices of one customer
// (implemented by internal/push through FCM HTTP v1).
type Pusher interface {
	PushToUser(userID, notificationID, title, body, category string)
}

var pusher Pusher

// SetPusher installs the push channel (called once at startup; nil = inbox only).
func SetPusher(p Pusher) { pusher = p }

// CreateAndPush stores the notification in the customer's in-app inbox and forwards a
// generic text to the customer's registered devices. Sending happens in the background;
// its outcome is recorded per device in push_deliveries (never assumed).
func CreateAndPush(ctx context.Context, db *gorm.DB, userID, title, message, category string) {
	if db == nil {
		return
	}
	notif := model.Notification{
		UserID: userID, Title: title, Message: message, Category: category, IsRead: false, CreatedAt: time.Now(),
	}
	if err := db.WithContext(ctx).Create(&notif).Error; err != nil {
		logger.GetLogger().Error("Gagal menyimpan notifikasi", map[string]interface{}{"error": err.Error()})
		return
	}
	if pusher == nil || userID == "" || userID == Broadcast {
		return // broadcasts are sent only through approved campaigns (internal/push)
	}
	pusher.PushToUser(userID, notif.ID, title, PushBody(category, message), category)
}
