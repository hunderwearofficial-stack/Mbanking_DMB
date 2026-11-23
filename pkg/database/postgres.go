package database

import (
	"fmt"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/pkg/logger"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
)

func InitPostgres(cfg *config.Config) (*gorm.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=%s TimeZone=Asia/Jakarta",
		cfg.DBHost, cfg.DBUser, cfg.DBPass, cfg.DBName, cfg.DBPort, cfg.DBSSL,
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Silent),
	})
	if err != nil {
		logger.GetLogger().Error("PostgreSQL tidak dapat terhubung (backend akan berhenti: fail-closed)", map[string]interface{}{
			"host":  cfg.DBHost,
			"port":  cfg.DBPort,
			"error": err.Error(),
		})
		return nil, err
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	sqlDB.SetMaxIdleConns(cfg.DBMaxIdleConns)
	sqlDB.SetMaxOpenConns(cfg.DBMaxOpenConns)
	sqlDB.SetConnMaxLifetime(time.Hour)

	logger.GetLogger().Info("PostgreSQL berhasil terhubung", map[string]interface{}{
		"host":     cfg.DBHost,
		"database": cfg.DBName,
	})

	return db, nil
}
