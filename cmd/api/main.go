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

// Command api menjalankan backend MBanking BPR.
//
//	go run ./cmd/api                  # jalankan server (local: membaca .env)
//	go run ./cmd/api -check-config    # hanya periksa konfigurasi lalu keluar
func main() {
	checkOnly := flag.Bool("check-config", false, "periksa konfigurasi (.env / environment) lalu keluar tanpa menjalankan server")
	flag.Parse()

	// 1. Configuration & secrets (fail-fast, audit DMB-007)
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
	log.Info("Memulai Mobile Banking BPR Middleware Backend", map[string]interface{}{
		"app_version": cfg.AppVersion, "env": cfg.AppEnv, "port": cfg.AppPort,
	})

	// 2. Database (mandatory: sessions, idempotency and audit depend on it — fail-closed)
	db, err := database.InitPostgres(cfg)
	if err != nil || db == nil {
		fatal("PostgreSQL wajib tersedia", err)
	}
	if cfg.AppEnv == "local" {
		// Remediasi kompatibilitas skema database lokal untuk kolom terenkripsi & data CBS OpenAPI
		_ = db.Exec(`ALTER TABLE users ALTER COLUMN nik TYPE text;
ALTER TABLE users ALTER COLUMN email TYPE text;
ALTER TABLE users ALTER COLUMN alamat TYPE text;
ALTER TABLE users ALTER COLUMN tgl_lahir TYPE text;
ALTER TABLE users ALTER COLUMN tempat_lahir TYPE text;
ALTER TABLE users ALTER COLUMN nama_ibu_kandung TYPE text;
ALTER TABLE users ALTER COLUMN agama TYPE character varying(255);
ALTER TABLE users ALTER COLUMN jenis_kelamin TYPE character varying(50);
ALTER TABLE users ALTER COLUMN kode_pos TYPE character varying(50);
ALTER TABLE accounts ALTER COLUMN account_type TYPE character varying(255);
ALTER TABLE accounts ALTER COLUMN product_code TYPE character varying(50);
ALTER TABLE accounts ALTER COLUMN account_number TYPE character varying(100);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS splash_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS onboarding_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS welcome_title character varying(150) DEFAULT 'Selamat Datang di DMB Mobile';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS welcome_subtitle character varying(255) DEFAULT 'Transaksi mudah, aman, dan tepercaya bersama BPR Dana Mandiri Bogor';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_title character varying(150) DEFAULT 'Masuk ke Akun M-Banking';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_subtitle character varying(255) DEFAULT 'Silakan masukkan User ID dan Kata Sandi Anda';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS terms_version character varying(50) DEFAULT 'Versi 2.4 - Efektif 2026';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS home_greeting character varying(150) DEFAULT 'Semoga harimu menyenangkan!';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS announcement_text text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS terms_pdf_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS privacy_pdf_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS quick_menu_config text;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE banners ALTER COLUMN tag DROP NOT NULL;
ALTER TABLE banners ALTER COLUMN highlight DROP NOT NULL;`).Error
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
	if err := database.BootstrapAdmin(db, adminUser, adminPass); err != nil {
		fatal("bootstrap admin gagal", err)
	}

	// 3. Redis (OTP state, rate limits). In-memory mode only when REDIS_HOST is
	var redisClient *redis.Client
	if cfg.UseInMemoryRedis() {
		redisClient = redis.NewMemoryClient()
		log.Warn("REDIS_HOST kosong: OTP & rate limit memakai memori proses (khusus pengembangan, satu instance)")
	} else if redisClient, err = redis.InitRedis(cfg); err != nil {
		fatal("Redis wajib tersedia", err)
	}

	// 4. Core Banking provider. The local ledger is a development/test tool, selected
	var cbsProv cbsprovider.CBSProvider
	if cfg.EnableMockCBS {
		cbsProv = cbsprovider.NewDatabaseCBSProvider(db)
		log.Warn("Core Banking Provider: ledger database lokal (KHUSUS LOCAL/DEVELOPMENT/TEST)")
	} else {
		cbsProv = cbsprovider.NewOpenAPICBSProvider(cfg, db)
		log.Info("Core Banking Provider: CBS OpenAPI")
	}

	// 5. Services, security middleware and routes (see internal/app/router.go)
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
