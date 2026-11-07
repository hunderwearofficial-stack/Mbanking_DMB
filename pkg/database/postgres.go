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

// InitPostgres attempts to connect to PostgreSQL.
// Returns db instance or nil with error if unreachable.
func InitPostgres(cfg *config.Config) (*gorm.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=%s TimeZone=Asia/Jakarta",
		cfg.DBHost, cfg.DBUser, cfg.DBPass, cfg.DBName, cfg.DBPort, cfg.DBSSL,
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Silent),
	})
	if err != nil {
		logger.GetLogger().Warn("PostgreSQL tidak dapat terhubung, berjalan dalam mode Standalone/Mock CBS", map[string]interface{}{
			"host": cfg.DBHost,
			"port": cfg.DBPort,
			"error": err.Error(),
		})
		return nil, err
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	// Connection Pool Settings
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(50)
	sqlDB.SetConnMaxLifetime(time.Hour)

	logger.GetLogger().Info("PostgreSQL berhasil terhubung", map[string]interface{}{
		"host": cfg.DBHost,
		"database": cfg.DBName,
	})

	return db, nil
}

