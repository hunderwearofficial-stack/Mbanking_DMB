package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/cbsprovider"
	accountHttp "mbanking-bpr/internal/module/account/delivery/http"
	accountRepo "mbanking-bpr/internal/module/account/repository"
	accountSvc "mbanking-bpr/internal/module/account/service"
	authHttp "mbanking-bpr/internal/module/auth/delivery/http"
	authRepo "mbanking-bpr/internal/module/auth/repository"
	authSvc "mbanking-bpr/internal/module/auth/service"
	txHttp "mbanking-bpr/internal/module/transaction/delivery/http"
	txRepo "mbanking-bpr/internal/module/transaction/repository"
	txSvc "mbanking-bpr/internal/module/transaction/service"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/redis"

	"github.com/gin-gonic/gin"
)

func setupTestServer() *gin.Engine {
	gin.SetMode(gin.TestMode)
	cfg := config.LoadConfig()
	cbsProv := cbsprovider.NewMemoryCBSProvider()
	_ = redis.InitRedis(cfg)

	authRepository := authRepo.NewAuthRepository(nil)
	authService := authSvc.NewAuthService(cfg, authRepository, cbsProv)
	authHandler := authHttp.NewAuthHandler(authService)

	accRepository := accountRepo.NewAccountRepository(nil)
	accService := accountSvc.NewAccountService(accRepository, cbsProv)
	accHandler := accountHttp.NewAccountHandler(accService)

	txRepository := txRepo.NewTransactionRepository(nil)
	txService := txSvc.NewTransactionService(txRepository, cbsProv)
	txHandler := txHttp.NewTransactionHandler(txService)

	r := gin.New()
	r.Use(middleware.CORS())

	v1 := r.Group("/api/v1")
	{
		authGroup := v1.Group("/auth")
		{
			authGroup.POST("/login", authHandler.Login)
		}

		protected := v1.Group("")
		protected.Use(middleware.AuthMiddleware(middleware.AuthConfig{
			Secret:        cfg.JWTSecret,
			DB:            nil,
			EnforceDevice: true,
		}))
		{
			accountGroup := protected.Group("/account")
			{
				accountGroup.GET("/balance", accHandler.GetBalance)
				accountGroup.GET("/mutations", accHandler.GetMutations)
			}

			txGroup := protected.Group("/transaction")
			{
				txGroup.POST("/transfer", txHandler.Transfer)
			}
		}
	}

	return r
}

func TestE2EFlow(t *testing.T) {
	router := setupTestServer()

	// 1. Test Login
	loginBody := map[string]string{
		"phone_number": "081234567890",
		"password":     "rahasia123",
		"device_id":    "DEVICE-TEST-001",
	}
	bodyBytes, _ := json.Marshal(loginBody)
	req, _ := http.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewBuffer(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Login gagal dengan status code: %d, response: %s", w.Code, w.Body.String())
	}

	var loginResp struct {
		Success bool `json:"success"`
		Data    struct {
			AccessToken string `json:"access_token"`
			User        struct {
				CIF      string `json:"cif"`
				DeviceID string `json:"device_id"`
			} `json:"user"`
		} `json:"data"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &loginResp)

	token := loginResp.Data.AccessToken
	if token == "" {
		t.Fatalf("Access token tidak boleh kosong")
	}

	// 2. Test Get Balance with Matching Device ID
	balReq, _ := http.NewRequest(http.MethodGet, "/api/v1/account/balance", nil)
	balReq.Header.Set("Authorization", "Bearer "+token)
	balReq.Header.Set("X-Device-ID", "DEVICE-TEST-001")
	balW := httptest.NewRecorder()
	router.ServeHTTP(balW, balReq)

	if balW.Code != http.StatusOK {
		t.Fatalf("Inquiry saldo gagal: status %d, response: %s", balW.Code, balW.Body.String())
	}

	// 3. Test Device Binding Mismatch
	tamperReq, _ := http.NewRequest(http.MethodGet, "/api/v1/account/balance", nil)
	tamperReq.Header.Set("Authorization", "Bearer "+token)
	tamperReq.Header.Set("X-Device-ID", "DEVICE-WRONG-999") // Different device ID
	tamperW := httptest.NewRecorder()
	router.ServeHTTP(tamperW, tamperReq)

	if tamperW.Code != http.StatusUnauthorized {
		t.Fatalf("Device binding harusnya menolak request dengan status 401 tapi mendapat: %d", tamperW.Code)
	}

	// 4. Test Mutations
	mutReq, _ := http.NewRequest(http.MethodGet, "/api/v1/account/mutations?limit=5", nil)
	mutReq.Header.Set("Authorization", "Bearer "+token)
	mutReq.Header.Set("X-Device-ID", "DEVICE-TEST-001")
	mutW := httptest.NewRecorder()
	router.ServeHTTP(mutW, mutReq)

	if mutW.Code != http.StatusOK {
		t.Fatalf("Inquiry mutasi gagal: status %d, response: %s", mutW.Code, mutW.Body.String())
	}

	// 5. Test Transfer Simulation
	txBody := map[string]interface{}{
		"to_bank_code":    "BPR",
		"to_account":      "1001002099",
		"to_account_name": "Siti Nurhaliza",
		"amount":          500000,
		"note":            "Uji Coba Transfer",
		"pin":             "123456",
	}
	txBytes, _ := json.Marshal(txBody)
	txReq, _ := http.NewRequest(http.MethodPost, "/api/v1/transaction/transfer", bytes.NewBuffer(txBytes))
	txReq.Header.Set("Authorization", "Bearer "+token)
	txReq.Header.Set("X-Device-ID", "DEVICE-TEST-001")
	txReq.Header.Set("Content-Type", "application/json")
	txW := httptest.NewRecorder()
	router.ServeHTTP(txW, txReq)

	if txW.Code != http.StatusOK {
		t.Fatalf("Transfer gagal: status %d, response: %s", txW.Code, txW.Body.String())
	}
}
