// Package app wires configuration, services, security middleware and HTTP routes.
// It is used by the API entrypoint (cmd/api) and by tests.
package app

import (
	"context"
	"errors"
	"net/http"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/cbsprovider"
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
	txHttp "mbanking-bpr/internal/module/transaction/delivery/http"
	txRepo "mbanking-bpr/internal/module/transaction/repository"
	txSvc "mbanking-bpr/internal/module/transaction/service"
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

// Deps exposes components needed by integration tests.
type Deps struct {
	Push     *push.Service
	Sessions *session.Manager
	OTPStore *otp.Store
}

// NewRouter wires services and routes. All security middleware is configured here.
func NewRouter(cfg *config.Config, db *gorm.DB, redisClient *redis.Client, cbsProv cbsprovider.CBSProvider) (*gin.Engine, *Deps, error) {
	sessions := session.NewManager(db)
	otpStore := otp.NewStore(redisClient, cfg.JWTSecret)
	resolver := ownership.NewResolver(cbsProv, db, cfg.UseLiveCBS())
	terms := legaldoc.NewService(db, legaldoc.NewDBFileStore(db), pdfdoc.RenderPDF)
	termsHandler := legaldoc.NewHandler(terms)
	contentHandler := mobilecontent.NewHandler(mobilecontent.NewService(db))
	pushSvc := push.NewService(db)
	pushHandler := push.NewHandler(pushSvc)
	notification.SetPusher(pushSvc)

	authHandler := authHttp.NewAuthHandler(authSvc.NewAuthService(cfg, authRepo.NewAuthRepository(db), cbsProv, otpStore, sessions, terms))
	accHandler := accountHttp.NewAccountHandler(accountSvc.NewAccountService(cbsProv, resolver))
	txHandler := txHttp.NewTransactionHandler(txSvc.NewTransactionService(txRepo.NewTransactionRepository(db), cbsProv, resolver, cfg.AllowedBankCodes))
	adminHandler := adminHttp.NewAdminHandler(adminSvc.NewAdminService(cfg, adminRepo.NewAdminRepository(db), sessions))
	cbsOpsHandler := adminHttp.NewCBSOpsHandler(cbsProv)
	customerHandler := customerHttp.NewCustomerHandler(customerSvc.NewCustomerService(customerRepo.NewCustomerRepository(db)))

	if cfg.IsProductionLike() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	// Only explicitly configured reverse proxies may set X-Forwarded-For (audit DMB-018).
	if err := r.SetTrustedProxies(cfg.TrustedProxies); err != nil {
		return nil, nil, err
	}
	r.MaxMultipartMemory = 4 << 20
	r.Use(gin.Recovery())
	r.Use(middleware.RequestMeta())
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.CORS(cfg.CORSAllowedOrigins))
	r.Use(middleware.RequestLogger())

	// Liveness only — no internal/integration details (audit DMB-023).
	r.GET("/health", func(c *gin.Context) {
		response.Success(c, "OK", gin.H{"status": "UP", "timestamp": time.Now().Format(time.RFC3339)})
	})

	// Readiness: dependencies required to serve traffic (DB, Redis). Details stay in
	// the server log; the response only says READY / NOT_READY.
	r.GET("/ready", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()
		if err := checkReady(ctx, db, redisClient); err != nil {
			logger.GetLogger().Error("Readiness check gagal", map[string]interface{}{"error": err.Error()})
			response.Error(c, http.StatusServiceUnavailable, "Layanan belum siap", "NOT_READY", gin.H{"status": "NOT_READY"})
			return
		}
		response.Success(c, "OK", gin.H{"status": "READY"})
	})

	rl := func(max, window int, prefix string, key middleware.KeyFunc) gin.HandlerFunc {
		return middleware.RateLimiterBy(redisClient, max, window, prefix, key)
	}
	byIdentity := middleware.ByJSONField("phone_number", "cif", "username")
	byCIF := middleware.ByJSONField("cif_number")

	customerAuth := middleware.AuthMiddleware(middleware.AuthConfig{Secret: cfg.JWTSecret, DB: db, Sessions: sessions})
	adminAuth := middleware.AdminAuth(cfg.AdminJWTSecret, db)
	roles := middleware.RequireRoles

	v1 := r.Group("/api/v1")
	{
		// Public, unauthenticated (client-safe data only)
		v1.GET("/banners", rl(60, 60, "public", middleware.ByIP), adminHandler.GetPublicBanners)
		v1.GET("/config", rl(60, 60, "public", middleware.ByIP), adminHandler.GetPublicConfig)
		v1.GET("/content", rl(60, 60, "content", middleware.ByIP), contentHandler.Public)

		// Syarat dan Ketentuan: published version metadata + PDF, and device consent before login
		v1.GET("/terms/active", rl(60, 60, "terms", middleware.ByIP), termsHandler.Active)
		v1.GET("/terms/versions/:id/pdf", rl(30, 60, "terms_pdf", middleware.ByIP), termsHandler.PublicPDF)
		v1.POST("/terms/acceptances", rl(20, 60, "terms_accept", middleware.ByIP), termsHandler.AcceptPreLogin)

		authGroup := v1.Group("/auth")
		{
			authGroup.POST("/login", rl(10, 60, "login_ip", middleware.ByIP), rl(5, 300, "login_id", byIdentity), authHandler.Login)
			authGroup.POST("/refresh", rl(30, 60, "refresh_ip", middleware.ByIP), authHandler.RefreshToken)
			authGroup.POST("/activate/verify", rl(5, 600, "act_ip", middleware.ByIP), rl(3, 900, "act_cif", byCIF), rl(3, 900, "act_phone", byIdentity), authHandler.VerifyActivation)
			authGroup.POST("/activate/otp", rl(10, 60, "otp_ip", middleware.ByIP), authHandler.VerifyActivationOTP)
			authGroup.POST("/activate/setup", rl(10, 60, "setup_ip", middleware.ByIP), authHandler.CompleteActivation)
			authGroup.POST("/forgot-password/request", rl(5, 600, "fp_ip", middleware.ByIP), rl(3, 900, "fp_phone", byIdentity), authHandler.RequestForgotPassword)
			authGroup.POST("/forgot-password/otp", rl(10, 60, "otp_ip", middleware.ByIP), authHandler.VerifyForgotPasswordOTP)
			authGroup.POST("/forgot-password/reset", rl(10, 60, "setup_ip", middleware.ByIP), authHandler.ResetForgotPassword)
		}

		// Backoffice: separate key/audience + RBAC per route (audit DMB-001, DMB-021)
		adminGroup := v1.Group("/admin")
		{
			adminGroup.POST("/login", rl(5, 60, "admin_login_ip", middleware.ByIP), rl(5, 300, "admin_login_user", byIdentity), adminHandler.Login)

			a := adminGroup.Group("")
			a.Use(adminAuth)
			{
				const (
					SA = model.AdminRoleSuperAdmin
					CS = model.AdminRoleCS
					MK = model.AdminRoleMarketing
					CO = model.AdminRoleCompliance
				)
				a.GET("/stats", roles(SA, CS, MK, CO), adminHandler.GetDashboardStats)
				a.GET("/customers", roles(SA, CS, CO), adminHandler.ListCustomers)
				a.POST("/customers/:id/reset-device", roles(SA, CS), adminHandler.ResetCustomerDevice)
				a.POST("/customers/:id/status", roles(SA, CS), adminHandler.ToggleCustomerStatus)
				a.GET("/banners", roles(SA, MK), adminHandler.ListBannersAdmin)
				a.POST("/banners", roles(SA, MK), adminHandler.CreateBanner)
				a.PUT("/banners/:id", roles(SA, MK), adminHandler.UpdateBanner)
				a.DELETE("/banners/:id", roles(SA, MK), adminHandler.DeleteBanner)
				a.GET("/transactions", roles(SA, CS, CO), adminHandler.ListTransactions)
				a.GET("/audit-logs", roles(SA, CO), adminHandler.ListAuditLogs)
				// Push notifications (FCM HTTP v1): Firebase integration is managed by SUPER_ADMIN;
				// officer notifications need approval by a different officer before sending
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
				a.GET("/config", roles(SA), adminHandler.GetConfig)
				a.PUT("/config", roles(SA), adminHandler.UpdateConfig)
				a.POST("/upload", roles(SA, MK), adminHandler.UploadFile)
				a.GET("/users", roles(SA), adminHandler.ListAdminUsers)
				a.POST("/users", roles(SA), adminHandler.CreateAdminUser)
				a.PUT("/users/:id/status", roles(SA), adminHandler.ToggleAdminUserStatus)
				a.DELETE("/users/:id", roles(SA), adminHandler.DeleteAdminUser)

				// Syarat dan Ketentuan: versioning with maker-checker (approver must differ from maker/submitter)
				a.GET("/terms/versions", roles(SA, CO, CS), termsHandler.ListVersions)
				a.GET("/terms/versions/:id", roles(SA, CO, CS), termsHandler.GetVersion)
				a.GET("/terms/versions/:id/pdf", roles(SA, CO, CS), termsHandler.AdminPDF)
				a.POST("/terms/versions", roles(SA, CO), termsHandler.CreateDraft)
				a.PUT("/terms/versions/:id", roles(SA, CO), termsHandler.UpdateDraft)
				a.POST("/terms/versions/:id/pdf", roles(SA, CO), termsHandler.GeneratePDF)
				a.POST("/terms/versions/:id/submit", roles(SA, CO), termsHandler.Submit)
				a.POST("/terms/versions/:id/approve", roles(SA, CO), termsHandler.Approve)
				a.POST("/terms/versions/:id/reject", roles(SA, CO), termsHandler.Reject)
				a.POST("/terms/versions/:id/archive", roles(SA, CO), termsHandler.Archive)
				a.GET("/terms/acceptances", roles(SA, CO), termsHandler.ListAcceptances)

				// Content shown by the Flutter app (registry): draft → pending approval → published,
				// maker-checker (approver ≠ creator/submitter), history and rollback
				a.GET("/content/schema", roles(SA, MK, CO), contentHandler.Schema)
				a.GET("/content", roles(SA, MK, CO), contentHandler.Current)
				a.GET("/content/revisions", roles(SA, MK, CO), contentHandler.History)
				a.PUT("/content/draft", roles(SA, MK), contentHandler.SaveDraft)
				a.POST("/content/revisions/:id/submit", roles(SA, MK), contentHandler.Submit)
				a.POST("/content/revisions/:id/approve", roles(SA, MK, CO), contentHandler.Approve)
				a.POST("/content/revisions/:id/reject", roles(SA, MK, CO), contentHandler.Reject)
				a.POST("/content/revisions/:id/rollback", roles(SA, MK), contentHandler.Rollback)
				a.DELETE("/content/revisions/:id", roles(SA, MK), contentHandler.Discard)

				// CBS operational endpoints (formerly public — audit DMB-023)
				a.GET("/cbs/health", roles(SA), cbsOpsHandler.Health)
				a.POST("/cbs/refresh-token", roles(SA), cbsOpsHandler.RefreshToken)
			}
		}

		// Customer API (Bearer + server-side session + device binding)
		p := v1.Group("")
		p.Use(customerAuth, rl(120, 60, "customer", middleware.ByUser))
		{
			p.POST("/auth/logout", pushHandler.DetachOnLogout, authHandler.Logout)
			p.GET("/terms/status", termsHandler.Status)
			p.POST("/auth/change-password", rl(5, 300, "chg_pw", middleware.ByUser), authHandler.ChangePassword)
			p.POST("/auth/change-pin", rl(5, 300, "chg_pin", middleware.ByUser), authHandler.ChangePIN)

			p.GET("/beneficiaries", customerHandler.ListBeneficiaries)
			p.POST("/beneficiaries", customerHandler.SaveBeneficiary)
			p.DELETE("/beneficiaries/:id", customerHandler.DeleteBeneficiary)

			p.GET("/applications", customerHandler.ListProductApplications)
			p.POST("/applications", rl(5, 3600, "applications", middleware.ByUser), customerHandler.CreateProductApplication)

			acc := p.Group("/account")
			{
				acc.GET("/balance", accHandler.GetBalance)
				acc.GET("/mutations", accHandler.GetMutations)
				acc.GET("/inquiry", rl(30, 60, "inquiry", middleware.ByUser), accHandler.InquiryAccount)
				acc.GET("/profile", accHandler.GetCustomerProfile)
				acc.GET("/list", accHandler.GetSavingsAccounts)
				acc.GET("/loans", accHandler.GetLoans)
				acc.GET("/loans/:account_no", accHandler.GetLoanDetail)
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

			p.POST("/transaction/transfer", rl(10, 60, "tx_transfer", middleware.ByUser), txHandler.Transfer)
		}
	}

	// Web backoffice (static, same origin)
	r.Static("/admin", "./web/admin")

	return r, &Deps{Sessions: sessions, OTPStore: otpStore, Push: pushSvc}, nil
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
