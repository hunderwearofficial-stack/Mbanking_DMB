package database

import (
	"time"

	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/utils"

	"gorm.io/gorm"
)

// SeedDatabase seeds initial demo records into PostgreSQL if empty
func SeedDatabase(db *gorm.DB) error {
	if db == nil {
		return nil
	}

	var userCount int64
	if err := db.Model(&model.User{}).Count(&userCount).Error; err != nil {
		return err
	}

	// 1. Seed Admin Users if empty
	var adminCount int64
	_ = db.Model(&model.AdminUser{}).Count(&adminCount)
	if adminCount == 0 {
		adminPw, _ := utils.HashPassword("admin123")
		admin := model.AdminUser{
			Username:     "admin",
			FullName:     "Super Administrator DMB",
			Email:        "admin@bprdanamandiribogor.co.id",
			PasswordHash: adminPw,
			Role:         model.AdminRoleSuperAdmin,
			IsActive:     true,
			CreatedAt:    time.Now(),
			UpdatedAt:    time.Now(),
		}
		_ = db.Create(&admin).Error
		logger.GetLogger().Info("Seeding Admin User default berhasil (admin / admin123)")
	}

	// 2. Seed Dynamic Banners if empty
	var bannerCount int64
	_ = db.Model(&model.Banner{}).Count(&bannerCount)
	if bannerCount == 0 {
		banners := []model.Banner{
			{
				Tag:          "BPR DANA MANDIRI BOGOR",
				Title:        "SIMPANAN NASABAH DIMANFAATKAN",
				Highlight:    "UNTUK PENGEMBANGAN USAHA PEREMPUAN MIKRO PRODUKTIF",
				BadgeText:    "BPR DMB CSR",
				BgColor:      "#1E293B",
				AccentColor:  "#FFB703",
				IconName:     "groups",
				TargetUrl:    "https://bprdanamandiribogor.co.id",
				IsActive:     true,
				DisplayOrder: 1,
				CreatedAt:    time.Now(),
				UpdatedAt:    time.Now(),
			},
			{
				Tag:          "DEPOSITO BERJANGKA DMB",
				Title:        "BUNGA KOMPETITIF 6,25% P.A.",
				Highlight:    "DAPAT DICAIRKAN SEWAKTU-WAKTU TANPA PENALTI",
				BadgeText:    "Bunga 6,25%",
				BgColor:      "#0F172A",
				AccentColor:  "#16984B",
				IconName:     "savings",
				TargetUrl:    "https://bprdanamandiribogor.co.id/deposito",
				IsActive:     true,
				DisplayOrder: 2,
				CreatedAt:    time.Now(),
				UpdatedAt:    time.Now(),
			},
			{
				Tag:          "SOLUSI KEUANGAN ANDA",
				Title:        "TABUNGAN MANDIRI DMB",
				Highlight:    "SIMPANAN AMAN & DIJAMIN LPS HINGGA 2 MILYAR",
				BadgeText:    "Dijamin LPS",
				BgColor:      "#0B4371",
				AccentColor:  "#38BDF8",
				IconName:     "verified_user",
				TargetUrl:    "https://bprdanamandiribogor.co.id/tabungan",
				IsActive:     true,
				DisplayOrder: 3,
				CreatedAt:    time.Now(),
				UpdatedAt:    time.Now(),
			},
		}
		for _, b := range banners {
			_ = db.Create(&b).Error
		}
		logger.GetLogger().Info("Seeding Dynamic Promotional Banners berhasil")
	}

	// 3. Seed Default AppConfig if empty
	var cfgCount int64
	_ = db.Model(&model.AppConfig{}).Count(&cfgCount)
	if cfgCount == 0 {
		defaultCfg := model.AppConfig{
			ID:                   "DEFAULT",
			BankName:             "PT BPR DANA MANDIRI BOGOR",
			BankShortName:        "Bank DMB",
			Tagline:              "Mitra Terpercaya Menuju Sejahtera",
			LogoURL:              "/admin/uploads/logo_1793872119776565700.png",
			CallCenter:           "(0251) 832-1234",
			WhatsAppCS:           "081199887766",
			EmailCS:              "layanan@bprdanamandiribogor.co.id",
			WebsiteURL:           "https://bprdanamandiribogor.co.id",
			HeadOfficeAddress:    "Jl. Pajajaran No. 88, Bogor, Jawa Barat",
			MaintenanceMode:      false,
			MaintenanceMessage:   "Sistem sedang dalam peningkatan layanan berkala.",
			MinTransferAmount:    10000,
			DailyTransferLimit:   25000000,
			InterbankTransferFee: 2500,
			EnforceDeviceBinding: true,
			MaxLoginAttempts:     3,
			UpdatedAt:            time.Now(),
		}
		_ = db.Create(&defaultCfg).Error
		logger.GetLogger().Info("Seeding Default AppConfig berhasil")
	}

	return nil
}
