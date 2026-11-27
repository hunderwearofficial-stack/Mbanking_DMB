package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/app"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/redis"
)

func fatal(msg string, err error) {
	fmt.Fprintf(os.Stderr, "FATAL: %s: %v\n", msg, err)
	os.Exit(1)
}

func main() {
	checkOnly := flag.Bool("check-config", false, "periksa konfigurasi (.env / environment) lalu keluar tanpa menjalankan server")
	flag.Parse()

	cfg := config.LoadConfig()
	if err := cfg.Validate(); err != nil {
		fatal("konfigurasi tidak valid", err)
	}
	if err := crypto.InitKeys(cfg.DBEncryptionKey, cfg.DBEncryptionKeyPrevious); err != nil {
		fatal("kunci enkripsi database tidak valid", err)
	}
	if *checkOnly {
		src := "environment proses"
		if cfg.EnvFile != "" {
			src += " + " + cfg.EnvFile
		}
		fmt.Printf("Konfigurasi VALID (APP_ENV=%s, sumber: %s, CBS lokal=%t, Redis memori=%t)\n",
			cfg.AppEnv, src, cfg.EnableMockCBS, cfg.UseInMemoryRedis())
		return
	}
	log := logger.InitLogger(cfg.AppEnv)
	otp.Configure(cfg.IsProductionLike())
	otp.SetPolicy(time.Duration(cfg.OTPTTLMinutes)*time.Minute, cfg.OTPMaxAttempts)
	otp.ConfigureGateway(cfg.OTPGatewayHostAllowed)
	log.Info("Memulai Mobile Banking BPR Middleware Backend", map[string]interface{}{
		"app_version": cfg.AppVersion, "env": cfg.AppEnv, "port": cfg.AppPort,
	})

	db, err := database.InitPostgres(cfg)
	if err != nil || db == nil {
		fatal("PostgreSQL wajib tersedia", err)
	}
	if err := database.EnsureSchemaCurrent(context.Background(), db); err != nil {
		if cfg.AppEnv == "local" {
			log.Warn("Skema database belum sesuai versi aplikasi (local dev): menjalankan migrasi otomatis...", map[string]interface{}{"error": err.Error()})
			if done, mErr := database.MigrateUp(context.Background(), db); mErr != nil {
				fatal("migrasi otomatis di local gagal", mErr)
			} else {
				log.Info("Migrasi otomatis berhasil diterapkan", map[string]interface{}{"applied_migrations": len(done)})
			}
		} else {
			fatal("skema database tidak valid", err)
		}
	}
	adminUser := cfg.AdminBootstrapUsername
	adminPass := cfg.AdminBootstrapPassword
	if cfg.AppEnv == "local" && (adminUser == "" || adminPass == "") {
		adminUser = "admin"
		adminPass = "AdminBPR2026!"
	}
	if err := database.BootstrapAdminWithEmail(db, adminUser, adminPass, cfg.AdminBootstrapEmail); err != nil {
		fatal("bootstrap admin gagal", err)
	}
	if cfg.AdminBootstrapCheckerUsername != "" && cfg.AdminBootstrapCheckerPassword != "" {
		if err := database.BootstrapAdminWithEmail(db, cfg.AdminBootstrapCheckerUsername, cfg.AdminBootstrapCheckerPassword, cfg.AdminBootstrapCheckerEmail); err != nil {
			fatal("bootstrap admin checker gagal", err)
		}
	}

	var redisClient *redis.Client
	if cfg.UseInMemoryRedis() {
		redisClient = redis.NewMemoryClient()
		log.Warn("REDIS_HOST kosong: OTP & rate limit memakai memori proses (khusus pengembangan, satu instance)")
	} else if redisClient, err = redis.InitRedis(cfg); err != nil {
		fatal("Redis wajib tersedia", err)
	}

	var cbsProv cbsprovider.CBSProvider
	if cfg.EnableMockCBS {
		cbsProv = cbsprovider.NewDatabaseCBSProvider(db)
		log.Warn("Core Banking Provider: ledger database lokal (KHUSUS LOCAL/DEVELOPMENT/TEST)")
	} else {
		cbsProv = cbsprovider.NewOpenAPICBSProvider(cfg, db)
		log.Info("Core Banking Provider: CBS OpenAPI")
	}

	r, _, err := app.NewRouter(cfg, db, redisClient, cbsProv)
	if err != nil {
		fatal("inisialisasi router gagal", err)
	}

	srv := &http.Server{
		Addr:              cfg.AppHost + ":" + cfg.AppPort,
		Handler:           r,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      45 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	go func() {
		log.Info(fmt.Sprintf("Server HTTP siap menerima request di port %s", cfg.AppPort))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(fmt.Sprintf("Gagal menjalankan server HTTP: %v", err))
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Info("Mematikan server HTTP secara graceful...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Error(fmt.Sprintf("Server terpaksa dimatikan: %v", err))
	}
	log.Info("Server berhasil dihentikan dengan aman.")
}
