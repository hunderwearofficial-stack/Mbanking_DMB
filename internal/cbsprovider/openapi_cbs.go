package cbsprovider

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha512"
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
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// OpenAPICBSProvider connects directly to the Bank DMB Core Banking System OpenAPI (https://cbs-openapi-dev.bprdmb.id)
// using OAuth 2.0 Bearer JWT tokens (with automatic refresh rotation) and HMAC-SHA512 payload signing.
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
}

func NewOpenAPICBSProvider(cfg *config.Config, db *gorm.DB) *OpenAPICBSProvider {
	timeout := time.Duration(cfg.CBSTimeoutSec) * time.Second
	if timeout <= 0 {
		timeout = 15 * time.Second
	}
	return &OpenAPICBSProvider{
		cfg: cfg,
		db:  db,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
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
	NomorRekening  string  `json:"nomor_rekening"`
	Nama           string  `json:"nama"`
	ProdukTabungan string  `json:"produk_tabungan"`
	Saldo          float64 `json:"saldo"`
	SaldoMinimum   float64 `json:"saldo_minimum"`
	SaldoTertahan  float64 `json:"saldo_tertahan"`
	SaldoEfektif   float64 `json:"saldo_efektif"`
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

// computeHMACSHA512 computes lowercase hex HMAC-SHA512 of compact JSON body using CBSClientSecret
func (p *OpenAPICBSProvider) computeHMACSHA512(bodyBytes []byte) string {
	mac := hmac.New(sha512.New, []byte(p.cfg.CBSClientSecret))
	mac.Write(bodyBytes)
	return hex.EncodeToString(mac.Sum(nil))
}

// mapProductName converts CBS product code (e.g. "05", "20") into human-readable BPR product name
func mapProductName(code string) string {
	switch strings.TrimSpace(code) {
	case "05":
		return "Tabungan Mandiri DMB (Kode 05)"
	case "20":
		return "Tabungan Mikro DMB (Kode 20)"
	default:
		if code != "" {
			return fmt.Sprintf("Tabungan Mandiri DMB (%s)", code)
		}
		return "Tabungan Mandiri DMB"
	}
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

// doSignedPost executes an authenticated & HMAC-SHA512 signed POST request to CBS OpenAPI
func (p *OpenAPICBSProvider) doSignedPost(ctx context.Context, path string, payload interface{}) (*cbsEnvelope, int, error) {
	// Compact JSON marshaling (no spaces/newlines) so HMAC-SHA512 matches CBS server canonicalization
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, err
	}

	signature := p.computeHMACSHA512(bodyBytes)
	token, err := p.getAccessToken(ctx)
	if err != nil {
		return nil, 0, err
	}

	url := strings.TrimRight(p.cfg.CBSBaseURL, "/") + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-Client-ID", p.cfg.CBSClientID)
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
		(env.Code != 10000 && (strings.Contains(msgLower, "token") || strings.Contains(msgLower, "unauthorized") || strings.Contains(msgLower, "expired")))

	// If token expired or rejected by CBS, force a brand-new access token once and retry
	if isTokenExpired {
		p.tokenMu.Lock()
		p.accessToken = ""
		p.refreshToken = ""
		p.tokenMu.Unlock()

		newToken, tokErr := p.requestNewAccessToken(ctx)
		if tokErr == nil {
			retryReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
			retryReq.Header.Set("Content-Type", "application/json")
			retryReq.Header.Set("Accept", "application/json")
			retryReq.Header.Set("Authorization", "Bearer "+newToken)
			retryReq.Header.Set("X-Client-ID", p.cfg.CBSClientID)
			retryReq.Header.Set("X-Signature", signature)

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
	payload := map[string]string{
		"cif_number": strings.TrimSpace(cifNumber),
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

	// Sync complete customer profile from CBS /api/nasabah into local PostgreSQL
	if p.db != nil && data.CIF != "" {
		updates := map[string]interface{}{
			"nik":              data.NIK,
			"full_name":        data.Nama,
			"email":            data.Email,
			"alamat":           data.Alamat,
			"kode_pos":         data.KodePos,
			"jenis_kelamin":    data.JenisKelamin,
			"agama":            data.Agama,
			"tgl_lahir":        data.TglLahir,
			"tempat_lahir":     data.TempatLahir,
			"nama_ibu_kandung": data.NamaIbuKandung,
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
	payload := map[string]string{
		"cif_number": strings.TrimSpace(cifNumber),
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
		if uErr := p.db.WithContext(ctx).Where("cif = ?", strings.TrimSpace(cifNumber)).First(&user).Error; uErr == nil {
			now := time.Now()
			for _, item := range items {
				var acc model.Account
				prodName := mapProductName(item.ProdukTabungan)
				if aErr := p.db.WithContext(ctx).Where("account_number = ?", item.NomorRekening).First(&acc).Error; aErr != nil {
					newAcc := model.Account{
						ID:               uuid.NewString(),
						UserID:           user.ID,
						AccountNumber:    item.NomorRekening,
						HolderName:       user.FullName,
						ProductCode:      item.ProdukTabungan,
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
						"product_code": item.ProdukTabungan,
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
			productName := mapProductName(balData.ProdukTabungan)
			now := time.Now()

			// Synchronize live CBS balance & holder name into PostgreSQL
			if p.db != nil {
				var acc model.Account
				if dbErr := p.db.WithContext(ctx).Where("account_number = ?", accNo).First(&acc).Error; dbErr == nil {
					_ = p.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
						"holder_name":       balData.Nama,
						"product_code":      balData.ProdukTabungan,
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
				ProductCode:      balData.ProdukTabungan,
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

	// Fallback to local PostgreSQL if account is a local/deposit account or CBS is unreachable
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

// ==================== 8. Credentials & Mutations (PostgreSQL Backed) ====================

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

func (p *OpenAPICBSProvider) GetMutations(ctx context.Context, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if p.db == nil {
		return []domain.Mutation{}, nil
	}
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	var rows []model.Mutation
	query := p.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		Order("created_at DESC").
		Limit(limit)

	if err := query.Find(&rows).Error; err != nil {
		return nil, err
	}
	return rows, nil
}
