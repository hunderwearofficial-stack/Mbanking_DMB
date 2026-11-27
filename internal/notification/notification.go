package notification

import (
	"context"
	"strings"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"

	"gorm.io/gorm"
)

const (
	CategoryTransaction = "TRANSACTION"
	CategorySecurity    = "SECURITY"
	CategoryInfo        = "INFO"
	CategoryPromo       = "PROMO"

	Broadcast = "ALL"
)

func PushBody(category, message string) string {
	switch strings.ToUpper(category) {
	case CategorySecurity:
		return "Ada aktivitas keamanan pada akun Mobile DMB Anda. Buka aplikasi untuk melihat detail."
	}
	return message
}

type Pusher interface {
	PushToUser(userID, notificationID, title, body, category string)
}

var pusher Pusher

func SetPusher(p Pusher) { pusher = p }

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
