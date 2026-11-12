package cbsprovider

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// OpenAPICBSProvider connects directly to the Bank DMB Core Banking System OpenAPI (https://api-dev.bpr-danamandiribogor.co.id)
// using OAuth 2.0 Bearer JWT tokens (with automatic refresh rotation) and Base64 HMAC-SHA512 payload signing.
// It also synchronizes live CBS state (balances, account holder names, and overbooking ledger entries)
// with the local PostgreSQL database for M-Banking authentication, PIN verification, and mutation history.
type OpenAPICBSProvider struct {
	cfg        *config.Config
	db         *gorm.DB
	httpClient *http.Client

	tokenMu        sync.RWMutex
	accessToken    string
	refreshToken   string
	tokenExpiresAt time.Time

	productMu    sync.RWMutex
	productNames map[string]string

	memFallback *MemoryCBSProvider
}

func NewOpenAPICBSProvider(cfg *config.Config, db *gorm.DB) *OpenAPICBSProvider {
	timeout := time.Duration(cfg.CBSTimeoutSec) * time.Second
	if timeout <= 0 {
		timeout = 15 * time.Second
	}
	prov := &OpenAPICBSProvider{
		cfg: cfg,
		db:  db,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		productNames: make(map[string]string),
		memFallback:  NewMemoryCBSProvider(),
	}

	// Warm up product catalogue in background
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = prov.FetchProducts(ctx)
	}()

	return prov
}

// --- CBS Standard Envelope Structs ---

type cbsEnvelope struct {
	Status    string          `json:"status"`
	Code      int             `json:"code"`
	RefID     string          `json:"ref_id"`
	Timestamp string          `json:"timestamp"`
	Message   string          `json:"message"`
	Data      json.RawMessage `json:"data"`
}

type cbsTokenData struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	TokenType    string `json:"tokenType"`
	ExpiresIn    int    `json:"expiresIn"`
}

type cbsBalanceData struct {
	NomorRekening           string  `json:"nomor_rekening"`
	Nama                    string  `json:"nama"`
	KodeProduk              string  `json:"kode_produk"`
	NamaProduk              string  `json:"nama_produk"`
	ProdukTabungan          string  `json:"produk_tabungan"` // fallback
	StatusRekening          int     `json:"status_rekening"`
	StatusRekeningKeterangan string `json:"status_rekening_keterangan"`
	Saldo                   float64 `json:"saldo"`
	SaldoMinimum            float64 `json:"saldo_minimum"`
	SaldoTertahan           float64 `json:"saldo_tertahan"`
	SaldoEfektif            float64 `json:"saldo_efektif"`
}

type cbsOverbookingItem struct {
	IDTransaksi   string  `json:"id_transaksi"`
	NoRef         int     `json:"noref"`
	NomorRekening string  `json:"nomor_rekening"`
	Nominal       float64 `json:"nominal"`
	TglTransaksi  string  `json:"tgl_transaksi"`
	SaldoAwal     float64 `json:"saldo_awal"`
	SaldoAkhir    float64 `json:"saldo_akhir"`
	Deskripsi     string  `json:"deskripsi"`
}

type cbsMutationItem struct {
	Tanggal      string `json:"tanggal"`
	Waktu        string `json:"waktu"`
	Keterangan   string `json:"keterangan"`
	MutasiDebit  int64  `json:"mutasi_debit"`
	MutasiKredit int64  `json:"mutasi_kredit"`
	SaldoAkhir   int64  `json:"saldo_akhir"`
}

// computeSignature computes Base64 HMAC-SHA512 with the client secret over:
// METHOD:PATH:ACCESS_TOKEN:lowercase hex SHA-256 of minified body:X-TIMESTAMP
func (p *OpenAPICBSProvider) computeSignature(method, path, accessToken string, bodyBytes []byte, timestamp string) string {
	shaHash := sha256.Sum256(bodyBytes)
	bodySha256Hex := hex.EncodeToString(shaHash[:])
	stringToSign := fmt.Sprintf("%s:%s:%s:%s:%s", method, path, accessToken, bodySha256Hex, timestamp)

	mac := hmac.New(sha512.New, []byte(p.cfg.CBSClientSecret))
	mac.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

// mapProductName converts CBS product code (e.g. "05", "20") into human-readable BPR product name
func mapProductName(code string) string {
	switch strings.TrimSpace(code) {
	case "05":
		return "Tabungan Mandiri DMB (Kode 05)"
	case "06":
		return "Simpanan BL Tabungan (Kode 06)"
	case "07":
		return "Tabungan Dana Mandiri 07"
	case "09":
		return "Tabungan Karyawan"
	case "12":
		return "Tabungan Sikawan 1"
	case "20":
		return "Tabungan Mikro TBW (Kode 20)"
	case "21":
		return "Tabungan Impianku"
	case "22":
		return "Tabungan Sikawan 2"
	case "23":
		return "Tabungan Sikawan 3"
	case "25":
		return "Tabungan Simpel"
	case "26":
		return "Tabungan Sikawan 4"
	case "28":
		return "Tabungan Sikawan 5"
	case "30":
		return "Tabungan Phone Plus"
	default:
		if code != "" {
			return fmt.Sprintf("Tabungan Mandiri DMB (%s)", code)
		}
		return "Tabungan Mandiri DMB"
	}
}

// resolveProductName resolves product name dynamically from /api/products cache or mapProductName fallback
func (p *OpenAPICBSProvider) resolveProductName(code, fallbackName string) string {
	if strings.TrimSpace(fallbackName) != "" {
		return strings.TrimSpace(fallbackName)
	}
	code = strings.TrimSpace(code)
	p.productMu.RLock()
	if name, ok := p.productNames[code]; ok && name != "" {
		p.productMu.RUnlock()
		return name
	}
	p.productMu.RUnlock()
	return mapProductName(code)
}

// FetchProducts caches product definitions from /api/products
func (p *OpenAPICBSProvider) FetchProducts(ctx context.Context) error {
	env, statusCode, err := p.doSignedPost(ctx, "/api/products", map[string]interface{}{})
	if err != nil || statusCode != http.StatusOK || env == nil || env.Code != 10000 {
		return err
	}

	var prodData struct {
		Tabungan []struct {
			KodeProduk string `json:"kode_produk"`
			NamaProduk string `json:"nama_produk"`
			Aktif      bool   `json:"aktif"`
		} `json:"tabungan"`
	}
	if err := json.Unmarshal(env.Data, &prodData); err != nil {
		return err
	}

	p.productMu.Lock()
	defer p.productMu.Unlock()
	for _, item := range prodData.Tabungan {
		p.productNames[strings.TrimSpace(item.KodeProduk)] = strings.TrimSpace(item.NamaProduk)
	}
	return nil
}

// ==================== 1. GET /ping (Health Check) ====================

func (p *OpenAPICBSProvider) Ping(ctx context.Context) (*domain.CBSHealthStatus, error) {
	start := time.Now()
	url := strings.TrimRight(p.cfg.CBSBaseURL, "/") + "/ping"

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return &domain.CBSHealthStatus{
			Connected: false,
			Status:    "DOWN",
			Message:   err.Error(),
			LatencyMs: time.Since(start).Milliseconds(),
		}, err
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(resp.Body)
	var env cbsEnvelope
	_ = json.Unmarshal(raw, &env)

	var innerMsg struct {
		Message string `json:"message"`
	}
	_ = json.Unmarshal(env.Data, &innerMsg)
	msg := innerMsg.Message
	if msg == "" {
		msg = env.Message
	}

	return &domain.CBSHealthStatus{
		Connected: resp.StatusCode == http.StatusOK && env.Code == 10000,
		Status:    env.Status,
		Code:      env.Code,
		RefID:     env.RefID,
		Timestamp: env.Timestamp,
		Message:   msg,
		LatencyMs: time.Since(start).Milliseconds(),
	}, nil
}

// ==================== 2 & 3. OAuth Access Token & Refresh Token ====================

func (p *OpenAPICBSProvider) getAccessToken(ctx context.Context) (string, error) {
	p.tokenMu.RLock()
	if p.accessToken != "" && time.Now().Add(45*time.Second).Before(p.tokenExpiresAt) {
		tok := p.accessToken
		p.tokenMu.RUnlock()
		return tok, nil
	}
	hasRefresh := p.refreshToken != ""
	p.tokenMu.RUnlock()

	// Try rotating via /api/oauth/refresh-token first if we have a refresh token
	if hasRefresh {
		if err := p.RefreshToken(ctx); err == nil {
			p.tokenMu.RLock()
			tok := p.accessToken
			p.tokenMu.RUnlock()
			return tok, nil
		}
	}

	return p.requestNewAccessToken(ctx)
}

func (p *OpenAPICBSProvider) requestNewAccessToken(ctx context.Context) (string, error) {
	p.tokenMu.Lock()
	defer p.tokenMu.Unlock()

	// Double-check after acquiring write lock
	if p.accessToken != "" && time.Now().Add(45*time.Second).Before(p.tokenExpiresAt) {
		return p.accessToken, nil
	}

	url := strings.TrimRight(p.cfg.CBSBaseURL, "/") + "/api/oauth/access-token"
	payload := map[string]string{
		"clientId":     p.cfg.CBSClientID,
		"clientSecret": p.cfg.CBSClientSecret,
	}
	bodyBytes, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("gagal menghubungi CBS OAuth endpoint: %w", err)
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(resp.Body)
	var env cbsEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return "", fmt.Errorf("respons OAuth CBS tidak valid: %w", err)
	}

	if resp.StatusCode != http.StatusOK || env.Code != 10000 {
		return "", fmt.Errorf("CBS OAuth gagal (%d): %s", env.Code, env.Message)
	}

	var tokenData cbsTokenData
	if err := json.Unmarshal(env.Data, &tokenData); err != nil {
		return "", fmt.Errorf("gagal membaca token CBS: %w", err)
	}

	expSec := tokenData.ExpiresIn
	if expSec <= 0 {
		expSec = 900
	}
	p.accessToken = tokenData.AccessToken
	p.refreshToken = tokenData.RefreshToken
	p.tokenExpiresAt = time.Now().Add(time.Duration(expSec) * time.Second)

	logger.GetLogger().Info("CBS OpenAPI OAuth Access Token berhasil diperbarui", map[string]interface{}{
		"ref_id":     env.RefID,
		"expires_in": expSec,
	})

	return p.accessToken, nil
}

// RefreshToken calls POST /api/oauth/refresh-token to rotate the CBS JWT and Refresh Token
func (p *OpenAPICBSProvider) RefreshToken(ctx context.Context) error {
	p.tokenMu.Lock()
	defer p.tokenMu.Unlock()

	if p.refreshToken == "" {
		return errors.New("refresh token belum tersedia")
	}

	url := strings.TrimRight(p.cfg.CBSBaseURL, "/") + "/api/oauth/refresh-token"
	payload := map[string]string{
		"refreshToken": p.refreshToken,
	}
	bodyBytes, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(resp.Body)
	var env cbsEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK || env.Code != 10000 {
		p.accessToken = ""
		p.refreshToken = ""
		return fmt.Errorf("refresh token CBS ditolak (%d): %s", env.Code, env.Message)
	}

	var tokenData cbsTokenData
	if err := json.Unmarshal(env.Data, &tokenData); err != nil {
		return err
	}
	if strings.TrimSpace(tokenData.AccessToken) == "" {
		p.accessToken = ""
		p.refreshToken = ""
		return errors.New("refresh token CBS mengembalikan accessToken kosong")
	}

	expSec := tokenData.ExpiresIn
	if expSec <= 0 {
		expSec = 900
	}
	p.accessToken = tokenData.AccessToken
	if strings.TrimSpace(tokenData.RefreshToken) != "" {
		p.refreshToken = tokenData.RefreshToken
	}
	p.tokenExpiresAt = time.Now().Add(time.Duration(expSec) * time.Second)

	logger.GetLogger().Info("CBS OpenAPI Token berhasil di-refresh via /api/oauth/refresh-token", map[string]interface{}{
		"ref_id": env.RefID,
	})
	return nil
}

// doSignedPost executes an authenticated & Base64 HMAC-SHA512 signed POST request to CBS OpenAPI
func (p *OpenAPICBSProvider) doSignedPost(ctx context.Context, path string, payload interface{}) (*cbsEnvelope, int, error) {
	// Compact JSON marshaling (no spaces/newlines) so SHA-256 matches CBS server canonicalization
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, err
	}

	token, err := p.getAccessToken(ctx)
	if err != nil {
		return nil, 0, err
	}

	// Generate ISO-8601 timestamp with offset (e.g. 2026-11-12T10:30:00+07:00)
	timestamp := time.Now().Format("2006-01-02T15:04:05-07:00")
	signature := p.computeSignature(http.MethodPost, path, token, bodyBytes, timestamp)

	url := strings.TrimRight(p.cfg.CBSBaseURL, "/") + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-Client-ID", p.cfg.CBSClientID)
	req.Header.Set("X-TIMESTAMP", timestamp)
	req.Header.Set("X-Signature", signature)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(resp.Body)
	var env cbsEnvelope
	_ = json.Unmarshal(raw, &env)

	msgLower := strings.ToLower(env.Message)
	isTokenExpired := resp.StatusCode == http.StatusUnauthorized ||
		resp.StatusCode == http.StatusForbidden ||
		(env.Code != 10000 && (strings.Contains(msgLower, "token") || strings.Contains(msgLower, "unauthorized") || strings.Contains(msgLower, "expired") || strings.Contains(msgLower, "signature")))

	// If token expired or rejected by CBS, force a brand-new access token once and retry
	if isTokenExpired {
		p.tokenMu.Lock()
		p.accessToken = ""
		p.refreshToken = ""
		p.tokenMu.Unlock()

		newToken, tokErr := p.requestNewAccessToken(ctx)
		if tokErr == nil {
			newTimestamp := time.Now().Format("2006-01-02T15:04:05-07:00")
			newSignature := p.computeSignature(http.MethodPost, path, newToken, bodyBytes, newTimestamp)

			retryReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
			retryReq.Header.Set("Content-Type", "application/json")
			retryReq.Header.Set("Accept", "application/json")
			retryReq.Header.Set("Authorization", "Bearer "+newToken)
			retryReq.Header.Set("X-Client-ID", p.cfg.CBSClientID)
			retryReq.Header.Set("X-TIMESTAMP", newTimestamp)
			retryReq.Header.Set("X-Signature", newSignature)

			retryResp, retryErr := p.httpClient.Do(retryReq)
			if retryErr == nil {
				defer retryResp.Body.Close()
				rawRetry, _ := io.ReadAll(retryResp.Body)
				var retryEnv cbsEnvelope
				_ = json.Unmarshal(rawRetry, &retryEnv)
				return &retryEnv, retryResp.StatusCode, nil
			}
		}
	}

	if env.Status == "" && env.Code == 0 && len(raw) > 0 {
		if err := json.Unmarshal(raw, &env); err != nil {
			return nil, resp.StatusCode, fmt.Errorf("respons JSON CBS tidak valid: %w", err)
		}
	}

	return &env, resp.StatusCode, nil
}

// ==================== 4. POST /api/nasabah (Get Customer Data by CIF) ====================

func (p *OpenAPICBSProvider) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	cifClean := strings.TrimSpace(cifNumber)
	if cifClean == "" {
		return nil, errors.New("cif_number tidak boleh kosong")
	}

	payload := map[string]string{
		"cif_number": cifClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/nasabah", payload)
	if err != nil {
		return nil, err
	}
	if statusCode != http.StatusOK || env.Code != 10000 {
		return nil, fmt.Errorf("%s (code: %d)", env.Message, env.Code)
	}

	var data domain.CBSNasabahData
	if err := json.Unmarshal(env.Data, &data); err != nil {
		return nil, err
	}

	// Sync complete customer profile from CBS /api/nasabah into local PostgreSQL with AES-256-GCM encryption
	if p.db != nil && data.CIF != "" {
		encNIK, _ := crypto.EncryptString(data.NIK)
		encEmail, _ := crypto.EncryptString(data.Email)
		encAlamat, _ := crypto.EncryptString(data.Alamat)
		encTglLahir, _ := crypto.EncryptString(data.TglLahir)
		encTempatLahir, _ := crypto.EncryptString(data.TempatLahir)
		encIbuKandung, _ := crypto.EncryptString(data.NamaIbuKandung)

		updates := map[string]interface{}{
			"nik":              encNIK,
			"full_name":        data.Nama,
			"email":            encEmail,
			"alamat":           encAlamat,
			"kode_pos":         data.KodePos,
			"jenis_kelamin":    data.JenisKelamin,
			"agama":            data.Agama,
			"tgl_lahir":        encTglLahir,
			"tempat_lahir":     encTempatLahir,
			"nama_ibu_kandung": encIbuKandung,
			"updated_at":       time.Now(),
		}
		if data.NoHP != "" && data.NoHP != "0" {
			updates["phone_number"] = data.NoHP
		}
		_ = p.db.WithContext(ctx).Model(&model.User{}).
			Where("cif = ?", data.CIF).
			Updates(updates).Error
	}

	return &data, nil
}

// ==================== 5. POST /api/savings-accounts (Get Savings Accounts by CIF) ====================

func (p *OpenAPICBSProvider) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	cifClean := strings.TrimSpace(cifNumber)
	if cifClean == "" {
		return nil, errors.New("cif_number tidak boleh kosong")
	}

	payload := map[string]string{
		"cif_number": cifClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/savings-accounts", payload)
	if err != nil {
		return nil, err
	}
	if statusCode != http.StatusOK || env.Code != 10000 {
		return nil, fmt.Errorf("%s (code: %d)", env.Message, env.Code)
	}

	var items []domain.CBSSavingsAccountItem
	if err := json.Unmarshal(env.Data, &items); err != nil {
		return nil, err
	}

	// Sync all savings accounts under this CIF into PostgreSQL accounts table
	if p.db != nil && len(items) > 0 {
		var user model.User
		if uErr := p.db.WithContext(ctx).Where("cif = ?", cifClean).First(&user).Error; uErr == nil {
			now := time.Now()
			for _, item := range items {
				var acc model.Account
				prodCode := item.KodeProduk
				if prodCode == "" {
					prodCode = item.ProdukTabungan
				}
				prodName := p.resolveProductName(prodCode, item.NamaProduk)

				if aErr := p.db.WithContext(ctx).Where("account_number = ?", item.NomorRekening).First(&acc).Error; aErr != nil {
					newAcc := model.Account{
						ID:               uuid.NewString(),
						UserID:           user.ID,
						AccountNumber:    item.NomorRekening,
						HolderName:       user.FullName,
						ProductCode:      prodCode,
						AccountType:      prodName,
						Balance:          item.Saldo,
						EffectiveBalance: item.Saldo,
						Status:           model.AccountStatusActive,
						CreatedAt:        now,
						UpdatedAt:        now,
					}
					_ = p.db.WithContext(ctx).Create(&newAcc).Error
				} else {
					_ = p.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
						"user_id":      user.ID,
						"holder_name":  user.FullName,
						"product_code": prodCode,
						"account_type": prodName,
						"balance":      item.Saldo,
						"updated_at":   now,
					}).Error
				}
			}
		}
	}

	return items, nil
}

// ==================== 6. POST /api/savings-account-balance (Get Live Balance) ====================

func (p *OpenAPICBSProvider) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	accNo := strings.TrimSpace(accountNo)
	payload := map[string]string{
		"account_number": accNo,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/savings-account-balance", payload)
	if err == nil && env != nil && statusCode == http.StatusOK && env.Code == 10000 {
		var balData cbsBalanceData
		if unmarshalErr := json.Unmarshal(env.Data, &balData); unmarshalErr == nil {
			prodCode := balData.KodeProduk
			if prodCode == "" {
				prodCode = balData.ProdukTabungan
			}
			productName := p.resolveProductName(prodCode, balData.NamaProduk)
			now := time.Now()

			// Synchronize live CBS balance & holder name into PostgreSQL
			if p.db != nil {
				var acc model.Account
				if dbErr := p.db.WithContext(ctx).Where("account_number = ?", accNo).First(&acc).Error; dbErr == nil {
					_ = p.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
						"holder_name":       balData.Nama,
						"product_code":      prodCode,
						"account_type":      productName,
						"balance":           balData.Saldo,
						"minimum_balance":   balData.SaldoMinimum,
						"blocked_balance":   balData.SaldoTertahan,
						"effective_balance": balData.SaldoEfektif,
						"updated_at":        now,
					}).Error
					if balData.Nama != "" && acc.UserID != "" {
						_ = p.db.WithContext(ctx).Model(&model.User{}).
							Where("id = ?", acc.UserID).
							Update("full_name", balData.Nama).Error
					}
				}
			}

			return &domain.BalanceResponse{
				AccountNumber:    balData.NomorRekening,
				HolderName:       balData.Nama,
				ProductCode:      prodCode,
				AccountType:      productName,
				Balance:          balData.Saldo,
				MinimumBalance:   balData.SaldoMinimum,
				BlockedBalance:   balData.SaldoTertahan,
				EffectiveBalance: balData.SaldoEfektif,
				Status:           model.AccountStatusActive,
				CBSRefID:         env.RefID,
				UpdatedAt:        now,
			}, nil
		}
	}

	// Fallback to local PostgreSQL if account is a local/deposit account or CBS returned not found
	if p.db != nil && accNo != "" {
		var account model.Account
		if dbErr := p.db.WithContext(ctx).Preload("User").Where("account_number = ?", accNo).First(&account).Error; dbErr == nil {
			holderName := account.HolderName
			if holderName == "" && account.User != nil {
				holderName = account.User.FullName
			}
			effBal := account.EffectiveBalance
			if effBal == 0 && account.Balance > 0 {
				effBal = account.Balance
			}
			return &domain.BalanceResponse{
				AccountNumber:    account.AccountNumber,
				HolderName:       holderName,
				ProductCode:      account.ProductCode,
				AccountType:      account.AccountType,
				Balance:          account.Balance,
				MinimumBalance:   account.MinimumBalance,
				BlockedBalance:   account.BlockedBalance,
				EffectiveBalance: effBal,
				Status:           account.Status,
				UpdatedAt:        account.UpdatedAt,
			}, nil
		}
	}

	return nil, ErrAccountNotFound
}

// ==================== 7. POST /api/overbooking (Live CBS Overbooking Transfer) ====================

func (p *OpenAPICBSProvider) ProcessTransfer(ctx context.Context, req *domain.TransferRequest, fromAccount string) (*domain.TransferResponse, error) {
	senderAccNo := strings.TrimSpace(fromAccount)
	receiverAccNo := strings.TrimSpace(req.ToAccount)

	// 1. Verify User's 6-Digit Transaction PIN in PostgreSQL (Bank Security Standard)
	var senderAcc model.Account
	if p.db != nil {
		if err := p.db.WithContext(ctx).Preload("User").Where("account_number = ?", senderAccNo).First(&senderAcc).Error; err == nil {
			if senderAcc.User != nil && req.PIN != "" {
				if !utils.CheckPIN(senderAcc.User.PINHash, req.PIN) {
					return nil, ErrInvalidPIN
				}
			}
		}
	}

	// 2. Call Live CBS OpenAPI POST /api/overbooking
	type overbookingPayload struct {
		DebitAccount  string  `json:"debit_account"`
		CreditAccount string  `json:"credit_account"`
		Nominal       float64 `json:"nominal"`
	}
	payload := overbookingPayload{
		DebitAccount:  senderAccNo,
		CreditAccount: receiverAccNo,
		Nominal:       req.Amount,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/overbooking", payload)
	if err != nil {
		return nil, fmt.Errorf("gagal mengeksekusi overbooking ke Core Banking: %w", err)
	}

	if statusCode != http.StatusOK || env.Code != 10000 {
		if strings.Contains(strings.ToLower(env.Message), "saldo") {
			return nil, ErrInsufficientBalance
		}
		return nil, fmt.Errorf("CBS Overbooking ditolak: %s (code: %d)", env.Message, env.Code)
	}

	var items []cbsOverbookingItem
	if err := json.Unmarshal(env.Data, &items); err != nil || len(items) == 0 {
		return nil, errors.New("respons transaksi overbooking CBS kosong")
	}

	now := time.Now()
	cbsTxID := items[0].IDTransaksi
	if cbsTxID == "" {
		cbsTxID = env.RefID
	}

	recipientName := req.ToAccountName

	// 3. Synchronize CBS Ledger Entries (Balances + Mutations) into PostgreSQL
	if p.db != nil {
		for _, item := range items {
			// Update cached account balance in PostgreSQL
			_ = p.db.WithContext(ctx).Model(&model.Account{}).
				Where("account_number = ?", item.NomorRekening).
				Update("balance", item.SaldoAkhir).Error

			txType := model.TxTypeDebit
			if item.NomorRekening == receiverAccNo && item.NomorRekening != senderAccNo {
				txType = model.TxTypeCredit
			} else if item.SaldoAkhir > item.SaldoAwal {
				txType = model.TxTypeCredit
			}

			// Extract recipient name from CBS description if available (e.g. "Transfer Overbooking Ke BAMBANG TRI LAKSONO")
			if txType == model.TxTypeDebit && strings.Contains(item.Deskripsi, "Ke ") {
				parts := strings.SplitN(item.Deskripsi, "Ke ", 2)
				if len(parts) == 2 && strings.TrimSpace(parts[1]) != "" {
					recipientName = strings.TrimSpace(parts[1])
				}
			}

			desc := item.Deskripsi
			if req.Note != "" {
				desc = fmt.Sprintf("%s (%s)", item.Deskripsi, req.Note)
			}

			refUnique := fmt.Sprintf("%s-%d", cbsTxID, item.NoRef)
			mut := model.Mutation{
				ID:              uuid.NewString(),
				AccountNumber:   item.NomorRekening,
				TransactionType: txType,
				Amount:          item.Nominal,
				BalanceAfter:    item.SaldoAkhir,
				Description:     desc,
				ReferenceNumber: refUnique,
				CreatedAt:       now,
			}
			_ = p.db.WithContext(ctx).Create(&mut).Error
		}
	}

	if recipientName == "" {
		recipientName = "Nasabah Bank DMB"
	}

	return &domain.TransferResponse{
		TransactionID: cbsTxID,
		ReferenceNo:   env.RefID,
		FromAccount:   senderAccNo,
		ToBankCode:    "DMB",
		ToBankName:    "PT BPR Dana Mandiri Bogor",
		ToAccount:     receiverAccNo,
		ToAccountName: recipientName,
		Amount:        req.Amount,
		Fee:           0,
		TotalAmount:   req.Amount,
		Note:          req.Note,
		Status:        model.TxStatusSuccess,
		Timestamp:     now,
	}, nil
}

// ==================== 8. Credentials & Mutations ====================

func (p *OpenAPICBSProvider) VerifyCredentials(ctx context.Context, username, password, pin string) (*domain.User, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}
	var user model.User
	err := p.db.WithContext(ctx).
		Preload("Accounts").
		Where("phone_number = ? OR cif = ?", username, username).
		First(&user).Error
	if err != nil {
		return nil, ErrInvalidCredentials
	}
	if !user.IsActive {
		return nil, ErrInactiveAccount
	}
	if password != "" && !utils.CheckPassword(user.PasswordHash, password) {
		return nil, ErrInvalidCredentials
	}
	if pin != "" && !utils.CheckPIN(user.PINHash, pin) {
		return nil, ErrInvalidPIN
	}
	return &user, nil
}

// GetMutations fetches mutations first from live CBS /api/savings-account-mutations (if CIF & account known),
// and falls back gracefully to local PostgreSQL mutation ledger.
func (p *OpenAPICBSProvider) GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	accNo := strings.TrimSpace(accountNo)
	cif := strings.TrimSpace(cifNumber)
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	// 1. Resolve CIF from database if not supplied directly
	if cif == "" && p.db != nil && accNo != "" {
		var acc model.Account
		if err := p.db.WithContext(ctx).Preload("User").Where("account_number = ?", accNo).First(&acc).Error; err == nil {
			if acc.User != nil && acc.User.CIF != "" {
				cif = acc.User.CIF
			}
		}
	}

	if startDate == "" {
		startDate = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if endDate == "" {
		endDate = time.Now().Format("2006-01-02")
	}

	if cif != "" && accNo != "" {
		payload := map[string]string{
			"cif_number":     cif,
			"account_number": accNo,
			"start_date":     startDate,
			"end_date":       endDate,
		}

		env, statusCode, err := p.doSignedPost(ctx, "/api/savings-account-mutations", payload)
		if err == nil && statusCode == http.StatusOK && env != nil && env.Code == 10000 {
			var cbsItems []cbsMutationItem
			if unmarshalErr := json.Unmarshal(env.Data, &cbsItems); unmarshalErr == nil && len(cbsItems) > 0 {
				var result []domain.Mutation
				for _, item := range cbsItems {
					txType := model.TxTypeDebit
					amount := float64(item.MutasiDebit)
					if item.MutasiKredit > 0 {
						txType = model.TxTypeCredit
						amount = float64(item.MutasiKredit)
					}

					parsedTime, _ := time.Parse("2006-01-02 15:04:05", item.Tanggal+" "+item.Waktu)
					if parsedTime.IsZero() {
						parsedTime, _ = time.Parse("2006-01-02", item.Tanggal)
					}
					if parsedTime.IsZero() {
						parsedTime = time.Now()
					}

					result = append(result, model.Mutation{
						ID:              uuid.NewString(),
						AccountNumber:   accNo,
						TransactionType: txType,
						Amount:          amount,
						BalanceAfter:    float64(item.SaldoAkhir),
						Description:     item.Keterangan,
						ReferenceNumber: fmt.Sprintf("CBS-%s", item.Tanggal),
						CreatedAt:       parsedTime,
					})
					if len(result) >= limit {
						break
					}
				}
				if len(result) > 0 {
					return result, nil
				}
			}
		}
	}

	// 2. Fallback to local PostgreSQL if CBS has no records or account is local
	if p.db == nil {
		return []domain.Mutation{}, nil
	}
	var rows []model.Mutation
	query := p.db.WithContext(ctx).
		Where("account_number = ?", accNo).
		Order("created_at DESC").
		Limit(limit)

	if err := query.Find(&rows).Error; err != nil {
		return nil, err
	}
	return rows, nil
}

// ==================== 9. Loan (Kredit) Endpoints ====================

// GetLoanAccountsByCIF calls POST /api/loan-accounts
func (p *OpenAPICBSProvider) GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error) {
	cifClean := strings.TrimSpace(cifNumber)
	if cifClean == "" {
		return nil, errors.New("cif_number tidak boleh kosong")
	}

	payload := map[string]string{
		"cif_number": cifClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/loan-accounts", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		logger.GetLogger().Warn("OpenAPI /api/loan-accounts tidak dapat diakses atau error, beralih ke fallback provider", map[string]interface{}{
			"error": err,
			"code":  statusCode,
		})
		if p.memFallback != nil {
			return p.memFallback.GetLoanAccountsByCIF(ctx, cifNumber)
		}
		return []domain.DMBLoanAccountItem{}, nil
	}

	var items []domain.DMBLoanAccountItem
	if err := json.Unmarshal(env.Data, &items); err != nil {
		return nil, err
	}
	return items, nil
}

// GetLoanAccountDetail calls POST /api/loan-account-detail
func (p *OpenAPICBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/loan-account-detail", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		if p.memFallback != nil {
			return p.memFallback.GetLoanAccountDetail(ctx, cifNumber, accountNo)
		}
		return nil, errors.New("data pinjaman tidak ditemukan")
	}

	var detail domain.DMBLoanAccountDetail
	if err := json.Unmarshal(env.Data, &detail); err != nil {
		return nil, err
	}
	return &detail, nil
}

// GetLoanMutations calls POST /api/loan-account-mutations
func (p *OpenAPICBSProvider) GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if startDate == "" {
		startDate = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if endDate == "" {
		endDate = time.Now().Format("2006-01-02")
	}
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
		"start_date":     startDate,
		"end_date":       endDate,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/loan-account-mutations", payload)
	if err != nil || statusCode != http.StatusOK || env == nil || env.Code != 10000 {
		return []domain.Mutation{}, nil
	}

	var cbsItems []cbsMutationItem
	if err := json.Unmarshal(env.Data, &cbsItems); err != nil || len(cbsItems) == 0 {
		return []domain.Mutation{}, nil
	}

	var result []domain.Mutation
	for _, item := range cbsItems {
		txType := model.TxTypeDebit
		amount := float64(item.MutasiDebit)
		if item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = float64(item.MutasiKredit)
		}

		parsedTime, _ := time.Parse("2006-01-02 15:04:05", item.Tanggal+" "+item.Waktu)
		if parsedTime.IsZero() {
			parsedTime, _ = time.Parse("2006-01-02", item.Tanggal)
		}
		if parsedTime.IsZero() {
			parsedTime = time.Now()
		}

		result = append(result, model.Mutation{
			ID:              uuid.NewString(),
			AccountNumber:   accountNo,
			TransactionType: txType,
			Amount:          amount,
			BalanceAfter:    float64(item.SaldoAkhir),
			Description:     item.Keterangan,
			ReferenceNumber: fmt.Sprintf("LOAN-%s", item.Tanggal),
			CreatedAt:       parsedTime,
		})
		if len(result) >= limit {
			break
		}
	}
	return result, nil
}

// ==================== 10. Deposit (Deposito) Endpoints ====================

// GetDepositAccountsByCIF calls POST /api/deposit-accounts
func (p *OpenAPICBSProvider) GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error) {
	cifClean := strings.TrimSpace(cifNumber)
	if cifClean == "" {
		return nil, errors.New("cif_number tidak boleh kosong")
	}

	payload := map[string]string{
		"cif_number": cifClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/deposit-accounts", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		logger.GetLogger().Warn("OpenAPI /api/deposit-accounts tidak dapat diakses atau error, beralih ke fallback provider", map[string]interface{}{
			"error": err,
			"code":  statusCode,
		})
		if p.memFallback != nil {
			return p.memFallback.GetDepositAccountsByCIF(ctx, cifNumber)
		}
		return []domain.DMBDepositAccountItem{}, nil
	}

	var items []domain.DMBDepositAccountItem
	if err := json.Unmarshal(env.Data, &items); err != nil {
		return nil, err
	}
	return items, nil
}

// GetDepositAccountDetail calls POST /api/deposit-account-detail
func (p *OpenAPICBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/deposit-account-detail", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		if p.memFallback != nil {
			return p.memFallback.GetDepositAccountDetail(ctx, cifNumber, accountNo)
		}
		return nil, errors.New("data deposito tidak ditemukan")
	}

	var detail domain.DMBDepositAccountDetail
	if err := json.Unmarshal(env.Data, &detail); err != nil {
		return nil, err
	}
	return &detail, nil
}

// GetDepositMutations calls POST /api/deposit-account-mutations
func (p *OpenAPICBSProvider) GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if startDate == "" {
		startDate = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if endDate == "" {
		endDate = time.Now().Format("2006-01-02")
	}
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
		"start_date":     startDate,
		"end_date":       endDate,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/deposit-account-mutations", payload)
	if err != nil || statusCode != http.StatusOK || env == nil || env.Code != 10000 {
		return []domain.Mutation{}, nil
	}

	var cbsItems []cbsMutationItem
	if err := json.Unmarshal(env.Data, &cbsItems); err != nil || len(cbsItems) == 0 {
		return []domain.Mutation{}, nil
	}

	var result []domain.Mutation
	for _, item := range cbsItems {
		txType := model.TxTypeDebit
		amount := float64(item.MutasiDebit)
		if item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = float64(item.MutasiKredit)
		}

		parsedTime, _ := time.Parse("2006-01-02 15:04:05", item.Tanggal+" "+item.Waktu)
		if parsedTime.IsZero() {
			parsedTime, _ = time.Parse("2006-01-02", item.Tanggal)
		}
		if parsedTime.IsZero() {
			parsedTime = time.Now()
		}

		result = append(result, model.Mutation{
			ID:              uuid.NewString(),
			AccountNumber:   accountNo,
			TransactionType: txType,
			Amount:          amount,
			BalanceAfter:    float64(item.SaldoAkhir),
			Description:     item.Keterangan,
			ReferenceNumber: fmt.Sprintf("DEP-%s", item.Tanggal),
			CreatedAt:       parsedTime,
		})
		if len(result) >= limit {
			break
		}
	}
	return result, nil
}

// ==================== 11. Products Catalog ====================

// GetProductsCatalog calls POST /api/products
func (p *OpenAPICBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	env, statusCode, err := p.doSignedPost(ctx, "/api/products", map[string]interface{}{})
	if err != nil || statusCode != http.StatusOK || env == nil || env.Code != 10000 {
		logger.GetLogger().Warn("OpenAPI /api/products tidak dapat diakses atau error, beralih ke fallback provider", map[string]interface{}{
			"error": err,
			"code":  statusCode,
		})
		if p.memFallback != nil {
			return p.memFallback.GetProductsCatalog(ctx)
		}
		return nil, fmt.Errorf("gagal memuat katalog produk DMB: %v", err)
	}

	var catalog domain.DMBProductsCatalog
	if err := json.Unmarshal(env.Data, &catalog); err != nil {
		if p.memFallback != nil {
			return p.memFallback.GetProductsCatalog(ctx)
		}
		return nil, err
	}
	return &catalog, nil
}
