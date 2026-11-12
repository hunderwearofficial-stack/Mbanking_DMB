package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/model"
	accountHttp "mbanking-bpr/internal/module/account/delivery/http"
	accountRepo "mbanking-bpr/internal/module/account/repository"
	accountSvc "mbanking-bpr/internal/module/account/service"
	adminHttp "mbanking-bpr/internal/module/admin/delivery/http"
	adminRepo "mbanking-bpr/internal/module/admin/repository"
	adminSvc "mbanking-bpr/internal/module/admin/service"
	authHttp "mbanking-bpr/internal/module/auth/delivery/http"
	authRepo "mbanking-bpr/internal/module/auth/repository"
	authSvc "mbanking-bpr/internal/module/auth/service"
	txHttp "mbanking-bpr/internal/module/transaction/delivery/http"
	txRepo "mbanking-bpr/internal/module/transaction/repository"
	txSvc "mbanking-bpr/internal/module/transaction/service"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

func main() {
	// 1. Load Configurations
	cfg := config.LoadConfig()

	// 1b. Inisialisasi Enkripsi Kolom Database AES-256-GCM (OJK & UU PDP Compliance)
	if err := crypto.InitEncryptionKey(cfg.DBEncryptionKey); err != nil {
		fmt.Printf("PERINGATAN: Gagal inisialisasi master key enkripsi database: %v\n", err)
	}

	// 2. Initialize Structured Logger with Data Masking
	log := logger.InitLogger(cfg.AppEnv)
	log.Info("Memulai Mobile Banking BPR Middleware Backend...", map[string]interface{}{
		"app_name":    cfg.AppName,
		"app_version": cfg.AppVersion,
		"env":         cfg.AppEnv,
		"port":        cfg.AppPort,
	})

	// 3. Connect to PostgreSQL (GORM) & Auto-Migrate
	db, err := database.InitPostgres(cfg)
	if err == nil && db != nil {
		log.Info("Menjalankan migrasi skema tabel PostgreSQL...")
		if migrateErr := db.AutoMigrate(
			&model.User{},
			&model.Account{},
			&model.Mutation{},
			&model.Transaction{},
			&model.AdminUser{},
			&model.Banner{},
			&model.AppConfig{},
			&model.AuditLog{},
			&model.Notification{},
			&model.SavedBeneficiary{},
			&model.ProductApplication{},
		); migrateErr != nil {
			log.Error("Gagal menjalankan AutoMigrate GORM", map[string]interface{}{"error": migrateErr.Error()})
		} else {
			log.Info("Migrasi skema database berhasil diselesaikan.")
			// Seed initial data if tables are empty
			_ = database.SeedDatabase(db)

			// Clean up any legacy demo device IDs from DB tables
			_ = db.Exec("UPDATE users SET device_id = 'SAMSUNG-SM-A305F-14E37999' WHERE full_name ILIKE '%YEYEN%' AND (device_id = 'DEVICE-DEMO-001' OR device_id LIKE '%DEMO%' OR device_id = '')").Error
			_ = db.Exec("UPDATE users SET device_id = '' WHERE device_id = 'DEVICE-DEMO-001' OR device_id LIKE '%DEMO%'").Error
			_ = db.Exec("UPDATE audit_logs SET device_id = 'SAMSUNG-SM-A305F-14E37999' WHERE device_id = 'DEVICE-DEMO-001' OR device_id LIKE '%DEMO%'").Error
			_ = db.Exec("UPDATE app_configs SET logo_url = '/admin/images/bank_logo.png' WHERE logo_url LIKE '%bprdanamandiribogor.co.id%' OR logo_url LIKE '%cropped%' OR logo_url LIKE '%uploads%'").Error

			// Auto-Migration: Otomatis enkripsi data existing yang masih plaintext dengan AES-256-GCM
			type RawUserPlain struct {
				ID             string `gorm:"column:id"`
				NIK            string `gorm:"column:nik"`
				Email          string `gorm:"column:email"`
				Alamat         string `gorm:"column:alamat"`
				TglLahir       string `gorm:"column:tgl_lahir"`
				TempatLahir    string `gorm:"column:tempat_lahir"`
				NamaIbuKandung string `gorm:"column:nama_ibu_kandung"`
			}
			var plainUsers []RawUserPlain
			if err := db.Table("users").Where("nik NOT LIKE 'enc:v1:%' AND nik != ''").Find(&plainUsers).Error; err == nil && len(plainUsers) > 0 {
				log.Info(fmt.Sprintf("Ditemukan %d akun nasabah dengan data plaintext. Melakukan enkripsi otomatis AES-256-GCM...", len(plainUsers)))
				for _, u := range plainUsers {
					encNIK, _ := crypto.EncryptString(u.NIK)
					encEmail, _ := crypto.EncryptString(u.Email)
					encAlamat, _ := crypto.EncryptString(u.Alamat)
					encTgl, _ := crypto.EncryptString(u.TglLahir)
					encTempat, _ := crypto.EncryptString(u.TempatLahir)
					encIbu, _ := crypto.EncryptString(u.NamaIbuKandung)
					_ = db.Table("users").Where("id = ?", u.ID).Updates(map[string]interface{}{
						"nik":              encNIK,
						"email":            encEmail,
						"alamat":           encAlamat,
						"tgl_lahir":        encTgl,
						"tempat_lahir":     encTempat,
						"nama_ibu_kandung": encIbu,
					}).Error
				}
				log.Info("Auto-enkripsi kolom database AES-256-GCM selesai.")
			}
		}
	}

	// 4. Connect to Redis (With graceful In-Memory fallback)
	redisClient := redis.InitRedis(cfg)

	// 5. Initialize Core Banking System (CBS) Provider (Live OpenAPI CBS, Database, or Memory Fallback)
	var cbsProv cbsprovider.CBSProvider
	if !cfg.EnableMockCBS && cfg.CBSBaseURL != "" {
		cbsProv = cbsprovider.NewOpenAPICBSProvider(cfg, db)
		log.Info("Core Banking Provider aktif menggunakan Live CBS OpenAPI BPR DMB", map[string]interface{}{
			"cbs_base_url":  cfg.CBSBaseURL,
			"cbs_client_id": cfg.CBSClientID,
		})
	} else if db != nil {
		cbsProv = cbsprovider.NewDatabaseCBSProvider(db)
		log.Info("Core Banking Provider aktif menggunakan Relational Database (PostgreSQL Engine)")
	} else {
		cbsProv = cbsprovider.NewMemoryCBSProvider()
		log.Warn("Core Banking Provider berjalan dalam mode In-Memory Standalone")
	}

	// 6. Dependency Injection (Clean Architecture Wiring)
	authRepository := authRepo.NewAuthRepository(db)
	authService := authSvc.NewAuthService(cfg, authRepository, cbsProv)
	authHandler := authHttp.NewAuthHandler(authService)

	accRepository := accountRepo.NewAccountRepository(db)
	accService := accountSvc.NewAccountService(accRepository, cbsProv)
	accHandler := accountHttp.NewAccountHandler(accService)

	transactionRepo := txRepo.NewTransactionRepository(db)
	txService := txSvc.NewTransactionService(transactionRepo, cbsProv)
	txHandler := txHttp.NewTransactionHandler(txService)

	adminRepository := adminRepo.NewAdminRepository(db)
	adminService := adminSvc.NewAdminService(cfg, adminRepository)
	adminHandler := adminHttp.NewAdminHandler(adminService)

	// 7. Setup Router & Global Middlewares
	if cfg.AppEnv == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.CORS())
	r.Use(middleware.RequestLogger()) // Automatically masks sensitive fields (PIN/password)

	// Health Check (Includes Live CBS OpenAPI /ping check)
	r.GET("/health", func(c *gin.Context) {
		cbsHealth, _ := cbsProv.Ping(c.Request.Context())
		response.Success(c, "Service BPR Mobile Banking Middleware berjalan normal", gin.H{
			"app_name":       cfg.AppName,
			"app_version":    cfg.AppVersion,
			"redis_fallback": redisClient.IsFallback(),
			"mock_cbs":       cfg.EnableMockCBS,
			"cbs_openapi":    cbsHealth,
			"timestamp":      time.Now().Format(time.RFC3339),
		})
	})

	// Auth Middleware with Device Binding check
	authMiddleware := middleware.AuthMiddleware(middleware.AuthConfig{
		Secret:        cfg.JWTSecret,
		DB:            db,
		EnforceDevice: true, // Enforces Device Binding validation
	})

	// 8. Register API v1 Endpoints
	v1 := r.Group("/api/v1")
	{
		// Public Marketing Banners & App Config (for Mobile App)
		v1.GET("/banners", adminHandler.GetPublicBanners)
		v1.GET("/config", adminHandler.GetConfig)

		// CBS OpenAPI Health & Token Management Endpoints
		v1.GET("/cbs/health", func(c *gin.Context) {
			cbsHealth, err := cbsProv.Ping(c.Request.Context())
			if err != nil {
				response.Error(c, http.StatusBadGateway, "CBS_UNREACHABLE", err.Error(), nil)
				return
			}
			response.Success(c, "Koneksi Core Banking System (CBS) OpenAPI sehat", cbsHealth)
		})
		v1.POST("/cbs/refresh-token", func(c *gin.Context) {
			if err := cbsProv.RefreshToken(c.Request.Context()); err != nil {
				response.Error(c, http.StatusBadGateway, "CBS_TOKEN_REFRESH_FAILED", err.Error(), nil)
				return
			}
			response.Success(c, "Refresh Token OAuth2 CBS OpenAPI berhasil diperbarui", nil)
		})

		// Auth Routes (Rate Limited: 5 requests / 60 seconds)
		authGroup := v1.Group("/auth")
		{
			authGroup.POST("/login", middleware.RateLimiter(redisClient, 5, 60, "auth_login"), authHandler.Login)
			authGroup.POST("/refresh", authHandler.RefreshToken)
			authGroup.POST("/activate/verify", authHandler.VerifyActivation)
			authGroup.POST("/activate/otp", authHandler.VerifyActivationOTP)
			authGroup.POST("/activate/setup", authHandler.CompleteActivation)
			authGroup.POST("/forgot-password/request", authHandler.RequestForgotPassword)
			authGroup.POST("/forgot-password/otp", authHandler.VerifyForgotPasswordOTP)
			authGroup.POST("/forgot-password/reset", authHandler.ResetForgotPassword)
		}

		// Admin Backoffice API Group
		adminGroup := v1.Group("/admin")
		{
			adminGroup.POST("/login", middleware.RateLimiter(redisClient, 5, 60, "admin_login"), adminHandler.Login)

			adminProtected := adminGroup.Group("")
			adminProtected.Use(middleware.JWTAuth(cfg.JWTSecret))
			{
				adminProtected.GET("/stats", adminHandler.GetDashboardStats)
				adminProtected.GET("/customers", adminHandler.ListCustomers)
				adminProtected.POST("/customers/:id/reset-device", adminHandler.ResetCustomerDevice)
				adminProtected.POST("/customers/:id/status", adminHandler.ToggleCustomerStatus)
				adminProtected.GET("/banners", adminHandler.ListBannersAdmin)
				adminProtected.POST("/banners", adminHandler.CreateBanner)
				adminProtected.PUT("/banners/:id", adminHandler.UpdateBanner)
				adminProtected.DELETE("/banners/:id", adminHandler.DeleteBanner)
				adminProtected.GET("/transactions", adminHandler.ListTransactions)
				adminProtected.GET("/audit-logs", adminHandler.ListAuditLogs)
				adminProtected.POST("/notifications/broadcast", adminHandler.BroadcastNotification)
				adminProtected.GET("/applications", adminHandler.ListAllApplicationsAdmin)
				adminProtected.PUT("/applications/:id/status", adminHandler.UpdateApplicationStatusAdmin)
				adminProtected.GET("/config", adminHandler.GetConfig)
				adminProtected.PUT("/config", adminHandler.UpdateConfig)
				adminProtected.POST("/upload", adminHandler.UploadFile)
				adminProtected.GET("/users", adminHandler.ListAdminUsers)
				adminProtected.POST("/users", adminHandler.CreateAdminUser)
				adminProtected.PUT("/users/:id/status", adminHandler.ToggleAdminUserStatus)
				adminProtected.DELETE("/users/:id", adminHandler.DeleteAdminUser)
			}
		}

		// Authenticated Routes (Requires Bearer JWT + Valid Device Binding)
		protected := v1.Group("")
		protected.Use(authMiddleware)
		{
			// Security Self-Service Routes (Change Password & Change PIN)
			protected.POST("/auth/change-password", authHandler.ChangePassword)
			protected.POST("/auth/change-pin", authHandler.ChangePIN)

			// Saved Beneficiaries (Favorite Transfer Accounts)
			protected.GET("/beneficiaries", adminHandler.ListBeneficiaries)
			protected.POST("/beneficiaries", adminHandler.SaveBeneficiary)
			protected.DELETE("/beneficiaries/:id", adminHandler.DeleteBeneficiary)

			// Online Product Applications (Deposito & Pinjaman)
			protected.GET("/applications", adminHandler.ListUserApplications)
			protected.POST("/applications", adminHandler.CreateProductApplication)

			// Account Routes
			accountGroup := protected.Group("/account")
			{
				accountGroup.GET("/balance", accHandler.GetBalance)
				accountGroup.GET("/mutations", accHandler.GetMutations)
				accountGroup.GET("/inquiry", accHandler.InquiryAccount)
				accountGroup.GET("/profile", accHandler.GetCustomerProfile)
				accountGroup.GET("/list", accHandler.GetSavingsAccounts)
				accountGroup.GET("/loans", accHandler.GetLoans)
				accountGroup.GET("/loans/:account_no", accHandler.GetLoanDetail)
				accountGroup.GET("/loans/:account_no/mutations", accHandler.GetLoanMutations)
				accountGroup.GET("/deposits", accHandler.GetDeposits)
				accountGroup.GET("/deposits/:account_no", accHandler.GetDepositDetail)
				accountGroup.GET("/deposits/:account_no/mutations", accHandler.GetDepositMutations)
				accountGroup.GET("/products", accHandler.GetProducts)
			}

			// In-App & FCM Notification Routes
			notifGroup := protected.Group("/notifications")
			{
				notifGroup.GET("", adminHandler.ListUserNotifications)
				notifGroup.POST("/read", adminHandler.MarkNotificationsRead)
				notifGroup.POST("/fcm-token", adminHandler.UpdateUserFCMToken)
			}

			// Transaction Routes (Rate Limited: 10 transactions / 60s)
			txGroup := protected.Group("/transaction")
			txGroup.Use(middleware.RateLimiter(redisClient, 10, 60, "tx_transfer"))
			{
				txGroup.POST("/transfer", txHandler.Transfer)
			}
		}
	}

	// 9. Web Backoffice Portal UI
	r.Static("/admin", "./web/admin")

	// 10. Graceful Shutdown HTTP Server
	serverAddr := fmt.Sprintf(":%s", cfg.AppPort)
	srv := &http.Server{
		Addr:         serverAddr,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
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

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Error(fmt.Sprintf("Server terpaksa dimatikan: %v", err))
	}

	log.Info("Server berhasil dihentikan dengan aman.")
}
