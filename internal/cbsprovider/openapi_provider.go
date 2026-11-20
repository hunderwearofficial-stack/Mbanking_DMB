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
	"mbanking-bpr/pkg/money"
	"net/http"
	"strings"
	"sync"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/logger"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

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
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = prov.FetchProducts(ctx)
	}()

	return prov
}

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
	NomorRekening            string       `json:"nomor_rekening"`
	Nama                     string       `json:"nama"`
	KodeProduk               string       `json:"kode_produk"`
	NamaProduk               string       `json:"nama_produk"`
	ProdukTabungan           string       `json:"produk_tabungan"` // fallback
	StatusRekening           int          `json:"status_rekening"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan"`
	Saldo                    money.Amount `json:"saldo"`
	SaldoMinimum             money.Amount `json:"saldo_minimum"`
	SaldoTertahan            money.Amount `json:"saldo_tertahan"`
	SaldoEfektif             money.Amount `json:"saldo_efektif"`
}

type cbsMutationItem struct {
	Tanggal      string       `json:"tanggal"`
	Waktu        string       `json:"waktu"`
	Keterangan   string       `json:"keterangan"`
	MutasiDebit  money.Amount `json:"mutasi_debit"`
	MutasiKredit money.Amount `json:"mutasi_kredit"`
	SaldoAkhir   money.Amount `json:"saldo_akhir"`
}

func (p *OpenAPICBSProvider) computeSignature(method, path, accessToken string, bodyBytes []byte, timestamp string) string {
	shaHash := sha256.Sum256(bodyBytes)
	bodySha256Hex := hex.EncodeToString(shaHash[:])
	stringToSign := fmt.Sprintf("%s:%s:%s:%s:%s", method, path, accessToken, bodySha256Hex, timestamp)

	mac := hmac.New(sha512.New, []byte(p.cfg.CBSClientSecret))
	mac.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

func productLabel(code string) string {
	if code = strings.TrimSpace(code); code != "" {
		return "Produk " + code
	}
	return "-"
}

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
	return productLabel(code)
}

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
		logger.GetLogger().Warn("Ping layanan perbankan inti gagal", map[string]interface{}{"error": err.Error()})
		return &domain.CBSHealthStatus{
			Connected: false,
			Status:    "DOWN",
			Message:   "Layanan perbankan inti belum dapat dihubungi",
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

func (p *OpenAPICBSProvider) getAccessToken(ctx context.Context) (string, error) {
	p.tokenMu.RLock()
	if p.accessToken != "" && time.Now().Add(45*time.Second).Before(p.tokenExpiresAt) {
		tok := p.accessToken
		p.tokenMu.RUnlock()
		return tok, nil
	}
	hasRefresh := p.refreshToken != ""
	p.tokenMu.RUnlock()

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

// errCBSBody: the CBS answered but the body could not be read or parsed.
var errCBSBody = errors.New("respons CBS tidak dapat dibaca")

// maxCBSResponseBytes bounds a CBS response body (inquiry payloads are small).
const maxCBSResponseBytes = 2 << 20

func (p *OpenAPICBSProvider) sendSigned(ctx context.Context, path, token string, bodyBytes []byte) (*cbsEnvelope, int, error) {
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

	// SECURITY: bounded read — a misbehaving upstream cannot exhaust memory.
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxCBSResponseBytes+1))
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("%w: %v", errCBSBody, err)
	}
	if len(raw) > maxCBSResponseBytes {
		return nil, resp.StatusCode, fmt.Errorf("%w: melebihi %d byte", errCBSBody, maxCBSResponseBytes)
	}
	var env cbsEnvelope
	if len(bytes.TrimSpace(raw)) > 0 {
		if err := json.Unmarshal(raw, &env); err != nil {
			return &env, resp.StatusCode, fmt.Errorf("%w: %v", errCBSBody, err)
		}
	}
	return &env, resp.StatusCode, nil
}

func (p *OpenAPICBSProvider) invalidateTokens() {
	p.tokenMu.Lock()
	p.accessToken = ""
	p.refreshToken = ""
	p.tokenMu.Unlock()
}

// doSignedPost sends a signed read-only inquiry to the CBS. On an expired/invalid token
// it is retried once with a fresh token (inquiries have no side effects).
func (p *OpenAPICBSProvider) doSignedPost(ctx context.Context, path string, payload interface{}) (*cbsEnvelope, int, error) {
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, err
	}

	token, err := p.getAccessToken(ctx)
	if err != nil {
		return nil, 0, err
	}

	env, status, err := p.sendSigned(ctx, path, token, bodyBytes)
	if err != nil && env == nil {
		return env, status, err
	}

	msgLower := strings.ToLower(env.Message)
	isTokenExpired := status == http.StatusUnauthorized || status == http.StatusForbidden ||
		(env.Code != 10000 && (strings.Contains(msgLower, "token") || strings.Contains(msgLower, "unauthorized") ||
			strings.Contains(msgLower, "expired") || strings.Contains(msgLower, "signature")))
	if !isTokenExpired {
		return env, status, err
	}

	p.invalidateTokens()
	newToken, tokErr := p.requestNewAccessToken(ctx)
	if tokErr != nil {
		return env, status, err
	}
	return p.sendSigned(ctx, path, newToken, bodyBytes)
}

func truncateCBSStr(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) > max {
		return s[:max]
	}
	return s
}

func (p *OpenAPICBSProvider) RegistrationCheck(ctx context.Context, accountNumber string) (*domain.CBSRegistrationCheckData, error) {
	accClean := strings.TrimSpace(accountNumber)
	if accClean == "" {
		return nil, errors.New("account_number tidak boleh kosong")
	}

	payload := map[string]string{
		"account_number": accClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/registration-check", payload)
	if err != nil {
		return nil, err
	}
	if statusCode == http.StatusNotFound || env.Code == 10003 {
		return nil, ErrAccountNotFound
	}
	if statusCode != http.StatusOK || env.Code != 10000 {
		return nil, fmt.Errorf("%s (code: %d)", env.Message, env.Code)
	}

	var data domain.CBSRegistrationCheckData
	if err := json.Unmarshal(env.Data, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (p *OpenAPICBSProvider) RegistrationComplete(ctx context.Context, accountNumber string) (*domain.CBSRegistrationCompleteData, error) {
	accClean := strings.TrimSpace(accountNumber)
	if accClean == "" {
		return nil, errors.New("account_number tidak boleh kosong")
	}

	payload := map[string]string{
		"account_number": accClean,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/registration-complete", payload)
	if err != nil {
		return nil, err
	}
	if statusCode == http.StatusNotFound || env.Code == 10003 {
		return nil, ErrAccountNotFound
	}
	if statusCode != http.StatusOK || env.Code != 10000 {
		return nil, fmt.Errorf("%s (code: %d)", env.Message, env.Code)
	}

	var data domain.CBSRegistrationCompleteData
	if err := json.Unmarshal(env.Data, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

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

	if p.db != nil && data.CIF != "" {
		encEmail, e2 := crypto.EncryptString(data.Email)
		encTglLahir, e4 := crypto.EncryptString(data.TglLahir)
		encTempatLahir, e5 := crypto.EncryptString(data.TempatLahir)
		if err := errors.Join(e2, e4, e5); err != nil {
			logger.GetLogger().Error("Sinkronisasi profil CBS dibatalkan: enkripsi PII gagal", map[string]interface{}{"error": err.Error()})
			return &data, nil
		}

		rawJK := strings.ToUpper(strings.TrimSpace(data.JenisKelamin))
		jk := truncateCBSStr(rawJK, 50)
		if len(rawJK) > 5 {
			if strings.HasPrefix(rawJK, "L") {
				jk = "L"
			} else if strings.HasPrefix(rawJK, "P") || strings.HasPrefix(rawJK, "W") {
				jk = "P"
			}
		}

		updates := map[string]interface{}{
			"full_name":     truncateCBSStr(strings.TrimSpace(data.Nama), 100),
			"email":         encEmail,
			"kode_pos":      truncateCBSStr(strings.TrimSpace(data.KodePos), 50),
			"jenis_kelamin": jk,
			"agama":         truncateCBSStr(strings.TrimSpace(data.Agama), 255),
			"tgl_lahir":     encTglLahir,
			"tempat_lahir":  encTempatLahir,
			"updated_at":    time.Now(),
		}
		// SECURITY (audit D-03): the login phone number is never overwritten from a CBS read;
		// it is verified by OTP at activation / Lupa Password. The mother's maiden name is a
		// verification secret the app does not need and is no longer copied (data minimisation).
		if err := p.db.WithContext(ctx).Model(&model.User{}).
			Where("cif = ?", data.CIF).
			Updates(updates).Error; err != nil {
			logger.GetLogger().Error("Sinkronisasi profil CBS gagal disimpan", map[string]interface{}{"error": err.Error()})
		}
	}

	return &data, nil
}

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
					if err := p.db.WithContext(ctx).Create(&newAcc).Error; err != nil {
						logger.GetLogger().Error("Cache rekening lokal gagal dibuat", map[string]interface{}{"error": err.Error()})
					}
				} else {
					if err := p.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
						"user_id":      user.ID,
						"holder_name":  user.FullName,
						"product_code": prodCode,
						"account_type": prodName,
						"balance":      item.Saldo,
						"updated_at":   now,
					}).Error; err != nil {
						logger.GetLogger().Error("Cache rekening lokal gagal diperbarui", map[string]interface{}{"error": err.Error()})
					}
				}
			}
		}
	}

	return items, nil
}

func (p *OpenAPICBSProvider) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	accNo := strings.TrimSpace(accountNo)
	payload := map[string]string{
		"account_number": accNo,
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/savings-account-balance", payload)
	if err != nil || env == nil || statusCode >= 500 {
		logger.GetLogger().Warn("CBS savings-account-balance tidak tersedia", map[string]interface{}{"status": statusCode, "error": fmt.Sprint(err)})
		return nil, ErrCBSUnavailable
	}
	if statusCode == http.StatusOK && env.Code == 10000 {
		var balData cbsBalanceData
		if unmarshalErr := json.Unmarshal(env.Data, &balData); unmarshalErr != nil {
			return nil, ErrCBSUnavailable
		}
		{
			prodCode := balData.KodeProduk
			if prodCode == "" {
				prodCode = balData.ProdukTabungan
			}
			productName := p.resolveProductName(prodCode, balData.NamaProduk)
			now := time.Now()

			if p.db != nil {
				var acc model.Account
				if dbErr := p.db.WithContext(ctx).Where("account_number = ?", accNo).First(&acc).Error; dbErr == nil {
					if err := p.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
						"holder_name":       balData.Nama,
						"product_code":      prodCode,
						"account_type":      productName,
						"balance":           balData.Saldo,
						"minimum_balance":   balData.SaldoMinimum,
						"blocked_balance":   balData.SaldoTertahan,
						"effective_balance": balData.SaldoEfektif,
						"updated_at":        now,
					}).Error; err != nil {
						logger.GetLogger().Error("Cache saldo lokal gagal diperbarui", map[string]interface{}{"error": err.Error()})
					}
					// The account holder name is not the customer name (joint accounts): the
					// customer name is synchronised from /api/nasabah only.
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

	return nil, ErrAccountNotFound
}

func (p *OpenAPICBSProvider) GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	accNo := strings.TrimSpace(accountNo)
	cif := strings.TrimSpace(cifNumber)
	if limit <= 0 || limit > 50 {
		limit = 20
	}

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

	if cif == "" || accNo == "" {
		return nil, ErrAccountNotFound
	}
	payload := map[string]string{
		"cif_number":     cif,
		"account_number": accNo,
		"start_date":     startDate,
		"end_date":       endDate,
	}
	env, statusCode, err := p.doSignedPost(ctx, "/api/savings-account-mutations", payload)
	if err != nil || env == nil || statusCode != http.StatusOK || env.Code != 10000 {
		logger.GetLogger().Warn("CBS savings-account-mutations tidak tersedia", map[string]interface{}{"status": statusCode, "error": fmt.Sprint(err)})
		return nil, ErrCBSUnavailable
	}
	var cbsItems []cbsMutationItem
	if len(env.Data) > 0 && string(env.Data) != "null" {
		if err := json.Unmarshal(env.Data, &cbsItems); err != nil {
			return nil, ErrCBSUnavailable
		}
	}
	result := make([]domain.Mutation, 0, len(cbsItems))
	for _, item := range cbsItems {
		txType := model.TxTypeDebit
		amount := item.MutasiDebit
		if item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = item.MutasiKredit
		}
		result = append(result, model.Mutation{
			ID:              uuid.NewString(),
			AccountNumber:   accNo,
			TransactionType: txType,
			Amount:          amount,
			BalanceAfter:    item.SaldoAkhir,
			Description:     item.Keterangan,
			ReferenceNumber: fmt.Sprintf("CBS-%s", item.Tanggal),
			CreatedAt:       parseCBSTime(item.Tanggal, item.Waktu),
		})
		if len(result) >= limit {
			break
		}
	}
	return result, nil
}

func parseCBSTime(date, clock string) time.Time {
	if t, err := time.Parse("2006-01-02 15:04:05", date+" "+clock); err == nil {
		return t
	}
	if t, err := time.Parse("2006-01-02", date); err == nil {
		return t
	}
	logger.GetLogger().Warn("Format tanggal mutasi CBS tidak dikenali", map[string]interface{}{"tanggal": date, "waktu": clock})
	return time.Time{}
}

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
		logger.GetLogger().Warn("OpenAPI /api/loan-accounts tidak dapat diakses", map[string]interface{}{"code": statusCode})
		return nil, errors.New("data pinjaman sedang tidak dapat diambil dari layanan perbankan")
	}

	var items []domain.DMBLoanAccountItem
	if err := json.Unmarshal(env.Data, &items); err != nil {
		return nil, err
	}
	return items, nil
}

func (p *OpenAPICBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/loan-account-detail", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		return nil, errors.New("data pinjaman tidak ditemukan")
	}

	var detail domain.DMBLoanAccountDetail
	if err := json.Unmarshal(env.Data, &detail); err != nil {
		return nil, err
	}
	return &detail, nil
}

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
		amount := item.MutasiDebit
		if item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = item.MutasiKredit
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
			BalanceAfter:    item.SaldoAkhir,
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
		logger.GetLogger().Warn("OpenAPI /api/deposit-accounts tidak dapat diakses", map[string]interface{}{"code": statusCode})
		return nil, errors.New("data deposito sedang tidak dapat diambil dari layanan perbankan")
	}

	var items []domain.DMBDepositAccountItem
	if err := json.Unmarshal(env.Data, &items); err != nil {
		return nil, err
	}
	return items, nil
}

func (p *OpenAPICBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	payload := map[string]string{
		"cif_number":     strings.TrimSpace(cifNumber),
		"account_number": strings.TrimSpace(accountNo),
	}

	env, statusCode, err := p.doSignedPost(ctx, "/api/deposit-account-detail", payload)
	if err != nil || statusCode != http.StatusOK || env.Code != 10000 {
		return nil, errors.New("data deposito tidak ditemukan")
	}

	var detail domain.DMBDepositAccountDetail
	if err := json.Unmarshal(env.Data, &detail); err != nil {
		return nil, err
	}
	return &detail, nil
}

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
		amount := item.MutasiDebit
		if item.MutasiKredit > 0 {
			txType = model.TxTypeCredit
			amount = item.MutasiKredit
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
			BalanceAfter:    item.SaldoAkhir,
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

func (p *OpenAPICBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	env, statusCode, err := p.doSignedPost(ctx, "/api/products", map[string]interface{}{})
	if err != nil || statusCode != http.StatusOK || env == nil || env.Code != 10000 {
		logger.GetLogger().Warn("OpenAPI /api/products tidak dapat diakses atau error", map[string]interface{}{
			"error": err,
			"code":  statusCode,
		})
		return nil, ErrCBSUnavailable
	}

	var catalog domain.DMBProductsCatalog
	if err := json.Unmarshal(env.Data, &catalog); err != nil {
		return nil, ErrCBSUnavailable
	}
	return &catalog, nil
}
