package app

import (
	"context"
	"errors"
	"net/http"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/legaldoc/pdfdoc"
	"mbanking-bpr/internal/mobilecontent"
	"mbanking-bpr/internal/model"
	accountHttp "mbanking-bpr/internal/module/account/delivery/http"
	accountSvc "mbanking-bpr/internal/module/account/service"
	adminHttp "mbanking-bpr/internal/module/admin/delivery/http"
	adminRepo "mbanking-bpr/internal/module/admin/repository"
	adminSvc "mbanking-bpr/internal/module/admin/service"
	authHttp "mbanking-bpr/internal/module/auth/delivery/http"
	authRepo "mbanking-bpr/internal/module/auth/repository"
	authSvc "mbanking-bpr/internal/module/auth/service"
	customerHttp "mbanking-bpr/internal/module/customer/delivery/http"
	customerRepo "mbanking-bpr/internal/module/customer/repository"
	customerSvc "mbanking-bpr/internal/module/customer/service"
	"mbanking-bpr/internal/module/helpdesk"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/otp"
	"mbanking-bpr/internal/ownership"
	"mbanking-bpr/internal/push"
	"mbanking-bpr/internal/session"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/redis"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type Deps struct {
	Push     *push.Service
	Sessions *session.Manager
	OTPStore *otp.Store
	Binder   *devicebind.Service
}

func NewRouter(cfg *config.Config, db *gorm.DB, redisClient *redis.Client, cbsProv cbsprovider.CBSProvider) (*gin.Engine, *Deps, error) {
	sessions := session.NewManager(db)
	otpStore := otp.NewStore(redisClient, cfg.JWTSecret)
	resolver := ownership.NewResolver(cbsProv, db, cfg.UseLiveCBS())
	terms := legaldoc.NewService(db, legaldoc.NewDBFileStore(db), pdfdoc.RenderPDF)
	termsHandler := legaldoc.NewHandler(terms)
	contentHandler := mobilecontent.NewHandler(mobilecontent.NewService(db))
	helpdeskHandler := helpdesk.NewHandler(db)
	pushSvc := push.NewService(db)
	pushHandler := push.NewHandler(pushSvc)
	bindOpts, err := devicebind.LoadOptions(cfg)
	if err != nil {
		return nil, nil, err
	}
	binder := devicebind.NewService(db, bindOpts)
	binder.LogStartup(context.Background(), cfg.AppEnv)
	// SECURITY: revoked attestation certificates must not stay trusted between restarts.
	binder.StartRevocationRefresh(context.Background(), cfg.AndroidAttestationRevocationFile, time.Hour, 48*time.Hour)
	notification.SetPusher(pushSvc)

	authHandler := authHttp.NewAuthHandler(authSvc.NewAuthService(cfg, authRepo.NewAuthRepository(db), cbsProv, otpStore, sessions, terms, binder))
	accHandler := accountHttp.NewAccountHandler(accountSvc.NewAccountService(cbsProv, resolver))
	adminHandler := adminHttp.NewAdminHandler(adminSvc.NewAdminService(cfg, adminRepo.NewAdminRepository(db), sessions))
	cbsOpsHandler := adminHttp.NewCBSOpsHandler(cbsProv, db)
	customerHandler := customerHttp.NewCustomerHandler(customerSvc.NewCustomerService(customerRepo.NewCustomerRepository(db)))

	if cfg.IsProductionLike() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	if err := r.SetTrustedProxies(cfg.TrustedProxies); err != nil {
		return nil, nil, err
	}
	r.MaxMultipartMemory = 4 << 20
	r.Use(gin.Recovery())
	r.Use(middleware.MaxBodyBytes(cfg.MaxJSONBodyBytes))
	r.Use(middleware.RequestMeta())
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.CORS(cfg.CORSAllowedOrigins))
	r.Use(middleware.RequestLogger())

	r.GET("/health", func(c *gin.Context) {
		response.Success(c, "OK", gin.H{"status": "UP", "timestamp": time.Now().Format(time.RFC3339)})
	})

	r.GET("/ready", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()
		if err := checkReady(ctx, db, redisClient); err != nil {
			logger.GetLogger().Error("Readiness check gagal", map[string]interface{}{"error": err.Error()})
			response.Error(c, http.StatusServiceUnavailable, "Layanan belum siap", "NOT_READY", gin.H{"status": "NOT_READY"})
			return
		}
		// audit_degraded only says whether the audit trail failed recently; no detail leaks.
		response.Success(c, "OK", gin.H{"status": "READY", "audit_degraded": audit.DegradedWithin(5 * time.Minute)})
	})

	// RATE_LIMIT_MULTIPLIER relaxes limits for local/development testing; config validation
	// forces 1 in staging/production.
	multiplier := cfg.RateLimitMultiplier
	if multiplier < 1 {
		multiplier = 1
	}
	rl := func(max, window int, prefix string, key middleware.KeyFunc) gin.HandlerFunc {
		return middleware.RateLimiterBy(redisClient, max*multiplier, window, prefix, key)
	}
	// In local/development environments, do not rate-limit OTP requests/verifications.
	otpRL := func(max, window int, prefix string, key middleware.KeyFunc) gin.HandlerFunc {
		if !cfg.IsProductionLike() {
			return func(c *gin.Context) { c.Next() }
		}
		return rl(max, window, prefix, key)
	}
	bySession := middleware.ByJSONField("session_id")
	maintenance := newMaintenanceGate(db).Middleware()
	byIdentity := middleware.ByJSONField("phone_number", "cif", "username")
	byCIF := middleware.ByJSONField("cif_number")

	customerAuth := middleware.AuthMiddleware(middleware.AuthConfig{Secret: cfg.JWTSecret, DB: db, Sessions: sessions, DeviceKeys: binder})
	adminRevoked := func(ctx context.Context, jti string) bool {
		if jti == "" {
			return false
		}
		if redisClient == nil {
			return true
		}
		val, err := redisClient.Get(ctx, "admin:revoked:"+jti)
		if err != nil {
			if errors.Is(err, redis.ErrNotFound) {
				return false
			}
			// Fail-closed: bila Redis bermasalah, tolak token agar token yang sudah logout/dicabut tidak bisa lolos.
			return true
		}
		return len(val) > 0
	}
	adminHandler.TokenRevoker = func(ctx context.Context, jti string, exp time.Time) {
		if redisClient == nil || jti == "" {
			return
		}
		ttl := time.Until(exp)
		if ttl > 0 {
			_ = redisClient.Set(ctx, "admin:revoked:"+jti, []byte("1"), ttl)
		}
	}
	adminAuth := middleware.AdminAuth(middleware.AdminAuthConfig{Secret: cfg.AdminJWTSecret, DB: db, Revoked: adminRevoked})
	roles := middleware.RequireRoles

	v1 := r.Group("/api/v1")
	{
		v1.GET("/banners", rl(60, 60, "public", middleware.ByIP), adminHandler.GetPublicBanners)
		v1.GET("/config", rl(60, 60, "public", middleware.ByIP), adminHandler.GetPublicConfig)
		v1.GET("/content", rl(60, 60, "content", middleware.ByIP), contentHandler.Public)
		v1.GET("/terms/active", rl(60, 60, "terms", middleware.ByIP), termsHandler.Active)
		v1.GET("/terms/versions/:id/pdf", rl(30, 60, "terms_pdf", middleware.ByIP), termsHandler.PublicPDF)
		v1.POST("/terms/acceptances", rl(20, 60, "terms_accept", middleware.ByIP), termsHandler.AcceptPreLogin)

		authGroup := v1.Group("/auth")
		authGroup.Use(maintenance)
		{
			authGroup.POST("/login", rl(10, 60, "login_ip", middleware.ByIP), rl(5, 300, "login_id", byIdentity), authHandler.Login)
			authGroup.POST("/refresh", rl(30, 60, "refresh_ip", middleware.ByIP), authHandler.RefreshToken)
			authGroup.POST("/device-challenge", rl(20, 60, "devchal_ip", middleware.ByIP), rl(10, 300, "devchal_id", byIdentity), authHandler.DeviceChallenge)
			authGroup.POST("/activate/verify", otpRL(5, 600, "act_ip", middleware.ByIP), otpRL(3, 900, "act_cif", byCIF), otpRL(3, 900, "act_phone", byIdentity), authHandler.VerifyActivation)
			authGroup.POST("/activate/otp", otpRL(10, 60, "otp_ip", middleware.ByIP), otpRL(5, 600, "otp_session", bySession), authHandler.VerifyActivationOTP)
			authGroup.POST("/activate/setup", rl(10, 60, "setup_ip", middleware.ByIP), authHandler.CompleteActivation)
			authGroup.POST("/forgot-password/request", otpRL(5, 600, "fp_ip", middleware.ByIP), otpRL(3, 900, "fp_phone", byIdentity), authHandler.RequestForgotPassword)
			authGroup.POST("/forgot-password/otp", otpRL(10, 60, "otp_ip", middleware.ByIP), otpRL(5, 600, "otp_session", bySession), authHandler.VerifyForgotPasswordOTP)
			authGroup.POST("/forgot-password/reset", rl(10, 60, "setup_ip", middleware.ByIP), authHandler.ResetForgotPassword)
		}

		adminGroup := v1.Group("/admin")
		{
			adminGroup.POST("/login", rl(5, 60, "admin_login_ip", middleware.ByIP), rl(5, 300, "admin_login_user", byIdentity), adminHandler.Login)

			mfaSetup := adminGroup.Group("/mfa")
			mfaSetup.Use(middleware.AdminMFASetupAuth(cfg.AdminJWTSecret))
			{
				mfaSetup.POST("/setup", rl(5, 300, "admin_mfa_setup", middleware.ByIP), adminHandler.SetupMFA)
				mfaSetup.POST("/confirm", rl(5, 300, "admin_mfa_confirm", middleware.ByIP), adminHandler.ConfirmMFA)
				mfaSetup.POST("/password", rl(5, 300, "admin_initial_pw", middleware.ByIP), adminHandler.SetInitialPassword)
			}

			a := adminGroup.Group("")
			a.Use(adminAuth)
			{
				const (
					SA = model.AdminRoleSuperAdmin
					CS = model.AdminRoleCS
					MK = model.AdminRoleMarketing
					CO = model.AdminRoleCompliance
				)
				a.POST("/logout", roles(SA, CS, MK, CO), adminHandler.Logout)
				a.POST("/change-password", roles(SA, CS, MK, CO), adminHandler.ChangeOwnPassword)
				a.POST("/users/:id/reset-mfa", roles(SA), adminHandler.ResetAdminMFA)
				a.GET("/approvals", roles(SA, CO), adminHandler.ListApprovals)
				a.POST("/approvals/:id/approve", roles(SA, CO), adminHandler.ApproveRequest)
				a.POST("/approvals/:id/reject", roles(SA, CO), adminHandler.RejectRequest)
				a.GET("/stats", roles(SA, CS, MK, CO), adminHandler.GetDashboardStats)
				a.GET("/customers", roles(SA, CS, CO), adminHandler.ListCustomers)
				a.POST("/customers/:id/reset-device", roles(SA, CS), adminHandler.ResetCustomerDevice)
				a.GET("/device-binding/summary", roles(SA, CS, CO), binder.SummaryHandler)
				a.POST("/customers/:id/status", roles(SA, CS), adminHandler.ToggleCustomerStatus)
				a.GET("/banners", roles(SA, MK), adminHandler.ListBannersAdmin)
				a.POST("/banners", roles(SA, MK), adminHandler.CreateBanner)
				a.PUT("/banners/:id", roles(SA, MK), adminHandler.UpdateBanner)
				a.DELETE("/banners/:id", roles(SA, MK), adminHandler.DeleteBanner)
				a.GET("/audit-logs", roles(SA, CO), adminHandler.ListAuditLogs)
				a.GET("/push/settings", roles(SA, MK, CO), pushHandler.GetSettings)
				a.POST("/push/credential", rl(5, 300, "push_cred", middleware.ByIP), roles(SA), pushHandler.UploadCredential)
				a.POST("/push/test", rl(10, 300, "push_test", middleware.ByIP), roles(SA), pushHandler.Test)
				a.PUT("/push/settings", roles(SA), pushHandler.SetEnabled)
				a.GET("/push/campaigns", roles(SA, MK, CO), pushHandler.ListCampaigns)
				a.POST("/push/campaigns", rl(30, 3600, "push_campaign", middleware.ByIP), roles(SA, MK), pushHandler.CreateCampaign)
				a.POST("/push/campaigns/:id/submit", roles(SA, MK), pushHandler.Submit)
				a.POST("/push/campaigns/:id/approve", roles(SA, MK, CO), pushHandler.Approve)
				a.POST("/push/campaigns/:id/reject", roles(SA, MK, CO), pushHandler.Reject)
				a.GET("/push/campaigns/:id/deliveries", roles(SA, MK, CO), pushHandler.Deliveries)
				a.GET("/applications", roles(SA, CS, MK, CO), adminHandler.ListAllApplicationsAdmin)
				a.PUT("/applications/:id/status", roles(SA, CS, MK), adminHandler.UpdateApplicationStatusAdmin)
				a.GET("/helpdesk/faqs", roles(SA, CS, MK, CO), helpdeskHandler.AdminListFAQs)
				a.POST("/helpdesk/faqs", roles(SA, CS, MK), helpdeskHandler.AdminCreateFAQ)
				a.PUT("/helpdesk/faqs/:id", roles(SA, CS, MK), helpdeskHandler.AdminUpdateFAQ)
				a.DELETE("/helpdesk/faqs/:id", roles(SA, CS, MK), helpdeskHandler.AdminDeleteFAQ)
				a.GET("/helpdesk/inquiries", roles(SA, CS, MK, CO), helpdeskHandler.AdminListInquiries)
				a.PUT("/helpdesk/inquiries/:id", roles(SA, CS, MK), helpdeskHandler.AdminResolveInquiry)
				a.GET("/config", roles(SA), adminHandler.GetConfig)
				a.PUT("/config", roles(SA), adminHandler.UpdateConfig)
				a.POST("/upload", roles(SA, MK), adminHandler.UploadFile)
				a.GET("/assets", roles(SA, MK, CO), adminHandler.ListAssets)
				a.DELETE("/assets/:filename", roles(SA, MK), adminHandler.DeleteAsset)
				a.GET("/users", roles(SA), adminHandler.ListAdminUsers)
				a.POST("/users", roles(SA), adminHandler.CreateAdminUser)
				a.PUT("/users/:id", roles(SA), adminHandler.UpdateAdminUser)
				a.PUT("/users/:id/status", roles(SA), adminHandler.ToggleAdminUserStatus)
				a.DELETE("/users/:id", roles(SA), adminHandler.DeleteAdminUser)
				a.GET("/terms/versions", roles(SA, CO, CS), termsHandler.ListVersions)
				a.GET("/terms/versions/:id", roles(SA, CO, CS), termsHandler.GetVersion)
				a.GET("/terms/versions/:id/pdf", roles(SA, CO, CS), termsHandler.AdminPDF)
				a.POST("/terms/versions", roles(SA, CO), termsHandler.CreateDraft)
				a.PUT("/terms/versions/:id", roles(SA, CO), termsHandler.UpdateDraft)
				a.POST("/terms/versions/:id/pdf", roles(SA, CO), termsHandler.GeneratePDF)
				a.POST("/terms/versions/:id/pdf/upload", roles(SA, CO), termsHandler.UploadPDF)
				a.POST("/terms/versions/:id/submit", roles(SA, CO), termsHandler.Submit)
				a.POST("/terms/versions/:id/approve", roles(SA, CO), termsHandler.Approve)
				a.POST("/terms/versions/:id/reject", roles(SA, CO), termsHandler.Reject)
				a.POST("/terms/versions/:id/archive", roles(SA, CO), termsHandler.Archive)
				a.GET("/terms/acceptances", roles(SA, CO), termsHandler.ListAcceptances)
				a.GET("/content/schema", roles(SA, MK, CO), contentHandler.Schema)
				a.GET("/content", roles(SA, MK, CO), contentHandler.Current)
				a.GET("/content/revisions", roles(SA, MK, CO), contentHandler.History)
				a.PUT("/content/draft", roles(SA, MK), contentHandler.SaveDraft)
				a.POST("/content/revisions/:id/submit", roles(SA, MK), contentHandler.Submit)
				a.POST("/content/revisions/:id/approve", roles(SA, MK, CO), contentHandler.Approve)
				a.POST("/content/revisions/:id/reject", roles(SA, MK, CO), contentHandler.Reject)
				a.POST("/content/revisions/:id/rollback", roles(SA, MK), contentHandler.Rollback)
				a.DELETE("/content/revisions/:id", roles(SA, MK), contentHandler.Discard)
				a.GET("/cbs/health", roles(SA), cbsOpsHandler.Health)
				a.POST("/cbs/refresh-token", roles(SA), cbsOpsHandler.RefreshToken)
			}
		}

		p := v1.Group("")
		p.Use(maintenance, customerAuth, rl(120, 60, "customer", middleware.ByUser), binder.RequireEnrolled("/api/v1/device/", "/api/v1/auth/logout"))
		{
			p.GET("/device/status", authHandler.DeviceStatus)
			p.POST("/device/challenge", rl(30, 60, "devchal_user", middleware.ByUser), authHandler.SessionDeviceChallenge)
			p.POST("/device/enroll", rl(5, 300, "dev_enroll", middleware.ByUser), authHandler.EnrollDevice)
			p.POST("/device/keys/rotate", rl(5, 3600, "dev_rotate", middleware.ByUser), authHandler.RotateDeviceKey)

			p.POST("/auth/logout", pushHandler.DetachOnLogout, authHandler.Logout)
			p.GET("/terms/status", termsHandler.Status)
			p.POST("/auth/change-password", rl(5, 300, "chg_pw", middleware.ByUser), authHandler.ChangePassword)
			p.POST("/auth/change-pin", rl(5, 300, "chg_pin", middleware.ByUser), authHandler.ChangePIN)

			p.GET("/applications", customerHandler.ListProductApplications)
			p.POST("/applications", rl(5, 3600, "applications", middleware.ByUser), customerHandler.CreateProductApplication)
			p.GET("/helpdesk/faqs", helpdeskHandler.ListActiveFAQs)
			p.POST("/helpdesk/inquiries", rl(30, 3600, "helpdesk_inquiry", middleware.ByUser), helpdeskHandler.CreateInquiry)

			acc := p.Group("/account")
			{
				acc.GET("/balance", accHandler.GetBalance)
				acc.GET("/mutations", accHandler.GetMutations)
				acc.GET("/profile", accHandler.GetCustomerProfile)
				acc.POST("/profile/reveal", rl(5, 300, "profile_reveal", middleware.ByUser), authHandler.RevealProfile)
				acc.GET("/list", accHandler.GetSavingsAccounts)
				acc.GET("/loans", accHandler.GetLoans)
				acc.GET("/loans/:account_no", accHandler.GetLoanDetail)
				acc.GET("/loans/:account_no/kkm", accHandler.GetLoanKKM)
				acc.GET("/loans/:account_no/mutations", accHandler.GetLoanMutations)
				acc.GET("/deposits", accHandler.GetDeposits)
				acc.GET("/deposits/:account_no", accHandler.GetDepositDetail)
				acc.GET("/deposits/:account_no/mutations", accHandler.GetDepositMutations)
				acc.GET("/products", accHandler.GetProducts)
			}

			notif := p.Group("/notifications")
			{
				notif.GET("", customerHandler.ListNotifications)
				notif.POST("/read", customerHandler.MarkNotificationsRead)
				notif.POST("/fcm-token", rl(20, 3600, "fcm_token", middleware.ByUser), pushHandler.RegisterToken)
				notif.DELETE("/fcm-token", pushHandler.UnregisterToken)
				notif.POST("/opened", pushHandler.Opened)
			}
		}
	}

	r.Static("/admin", "./web/admin")

	return r, &Deps{Sessions: sessions, OTPStore: otpStore, Push: pushSvc, Binder: binder}, nil
}

func checkReady(ctx context.Context, db *gorm.DB, rc *redis.Client) error {
	if db == nil {
		return errors.New("database tidak terhubung")
	}
	sqlDB, err := db.DB()
	if err != nil {
		return err
	}
	if err := sqlDB.PingContext(ctx); err != nil {
		return err
	}
	if rc == nil {
		return errors.New("redis tidak terhubung")
	}
	return rc.Ping(ctx)
}
