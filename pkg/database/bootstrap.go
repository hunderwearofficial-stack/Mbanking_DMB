package database

import (
	"errors"
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/security"

	"gorm.io/gorm"
)

func BootstrapAdmin(db *gorm.DB, username, password string) error {
	if db == nil || username == "" || password == "" {
		return nil
	}
	if security.IsCompromisedCredential(password) || len(password) < 12 {
		return errors.New("ADMIN_BOOTSTRAP_PASSWORD terlalu lemah atau termasuk kredensial yang terpublikasi")
	}
	hash, err := security.HashPassword(password)
	if err != nil {
		return err
	}
	var admin model.AdminUser
	err = db.Where("username = ?", username).First(&admin).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		admin = model.AdminUser{
			Username: username, FullName: "Super Administrator (bootstrap)", PasswordHash: hash,
			Role: model.AdminRoleSuperAdmin, IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now(),
		}
		if err := db.Create(&admin).Error; err != nil {
			return err
		}
		logger.GetLogger().Warn("Akun SUPER_ADMIN bootstrap dibuat. Hapus ADMIN_BOOTSTRAP_* dari environment setelah login pertama.", map[string]interface{}{"username": username})
		return nil
	}
	if err != nil {
		return err
	}
	if err := db.Model(&model.AdminUser{}).Where("id = ?", admin.ID).Updates(map[string]interface{}{
		"password_hash": hash, "role": model.AdminRoleSuperAdmin, "is_active": true, "updated_at": time.Now(),
	}).Error; err != nil {
		return err
	}
	logger.GetLogger().Warn("Password akun SUPER_ADMIN bootstrap di-reset dari environment. Hapus ADMIN_BOOTSTRAP_* setelah digunakan.", map[string]interface{}{"username": username})
	return nil
}
