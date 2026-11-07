package cbsprovider

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/utils"
)

var (
	ErrAccountNotFound     = errors.New("nomor rekening tidak ditemukan")
	ErrInvalidCredentials  = errors.New("nomor handphone, password, atau PIN salah")
	ErrInsufficientBalance = errors.New("saldo tidak mencukupi untuk melakukan transaksi")
	ErrInvalidPIN          = errors.New("PIN transaksi salah")
	ErrInactiveAccount     = errors.New("rekening sedang tidak aktif / terblokir")
)

// MemoryCBSProvider provides an in-memory adapter for unit tests and offline development
type MemoryCBSProvider struct {
	mu        sync.RWMutex
	users     map[string]*model.User
	accounts  map[string]*model.Account
	mutations map[string][]model.Mutation
}

func NewMemoryCBSProvider() *MemoryCBSProvider {
	cbs := &MemoryCBSProvider{
		users:     make(map[string]*model.User),
		accounts:  make(map[string]*model.Account),
		mutations: make(map[string][]model.Mutation),
	}
	cbs.seedInitialData()
	return cbs
}

func (m *MemoryCBSProvider) Ping(ctx context.Context) (*domain.CBSHealthStatus, error) {
	return &domain.CBSHealthStatus{
		Connected: true,
		Status:    "OK",
		Code:      10000,
		Message:   "Memory CBS Engine Active",
		Timestamp: time.Now().Format(time.RFC3339),
	}, nil
}

func (m *MemoryCBSProvider) RefreshToken(ctx context.Context) error {
	return nil
}

func (m *MemoryCBSProvider) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, u := range m.users {
		if u.CIF == cifNumber {
			return &domain.CBSNasabahData{
				CIF:   u.CIF,
				Nama:  u.FullName,
				NoHP:  u.PhoneNumber,
				Email: u.Email,
			}, nil
		}
	}
	return nil, ErrAccountNotFound
}

func (m *MemoryCBSProvider) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var items []domain.CBSSavingsAccountItem
	for _, acc := range m.accounts {
		items = append(items, domain.CBSSavingsAccountItem{
			NomorRekening:  acc.AccountNumber,
			Nama:           "Nasabah Demo",
			ProdukTabungan: acc.AccountType,
			Saldo:          acc.Balance,
		})
	}
	return items, nil
}

func (m *MemoryCBSProvider) seedInitialData() {
	m.mu.Lock()
	defer m.mu.Unlock()

	pwHash, _ := utils.HashPassword("rahasia123")
	pinHash, _ := utils.HashPIN("123456")

	demoUser := &model.User{
		ID:           "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
		CIF:          "CIF998877",
		FullName:     "Bima Cahya Ayu",
		PhoneNumber:  "081234567890",
		Email:        "budi.santoso@email.com",
		PasswordHash: pwHash,
		PINHash:      pinHash,
		DeviceID:     "DEVICE-DEMO-001",
		IsActive:     true,
		CreatedAt:    time.Now().Add(-180 * 24 * time.Hour),
		UpdatedAt:    time.Now(),
	}
	m.users[demoUser.PhoneNumber] = demoUser
	m.users["nasabah1"] = demoUser

	primaryAcc := &model.Account{
		ID:            "b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22",
		UserID:        demoUser.ID,
		AccountNumber: "1001002003",
		AccountType:   "Savings",
		Balance:       15250000.00,
		Status:        model.AccountStatusActive,
		CreatedAt:     time.Now().Add(-180 * 24 * time.Hour),
		UpdatedAt:     time.Now(),
	}
	m.accounts[primaryAcc.AccountNumber] = primaryAcc

	now := time.Now()
	m.mutations[primaryAcc.AccountNumber] = []model.Mutation{
		{
			ID:              "d3eebc99-9c0b-4ef8-bb6d-6bb9bd380a44",
			AccountNumber:   primaryAcc.AccountNumber,
			TransactionType: model.TxTypeCredit,
			Amount:          10000000.00,
			BalanceAfter:    10000000.00,
			Description:     "SETORAN AWAL PEMBUKAAN REKENING",
			ReferenceNumber: "REF202611010001",
			CreatedAt:       now.Add(-10 * 24 * time.Hour),
		},
		{
			ID:              "d4eebc99-9c0b-4ef8-bb6d-6bb9bd380a55",
			AccountNumber:   primaryAcc.AccountNumber,
			TransactionType: model.TxTypeCredit,
			Amount:          5500000.00,
			BalanceAfter:    15500000.00,
			Description:     "TRANSFER MASUK DARI BCA - ACHMAD FAUZI",
			ReferenceNumber: "REF202611020002",
			CreatedAt:       now.Add(-5 * 24 * time.Hour),
		},
		{
			ID:              "d5eebc99-9c0b-4ef8-bb6d-6bb9bd380a66",
			AccountNumber:   primaryAcc.AccountNumber,
			TransactionType: model.TxTypeDebit,
			Amount:          250000.00,
			BalanceAfter:    15250000.00,
			Description:     "PEMBAYARAN QRIS MERCHANT KOPI KENANGAN",
			ReferenceNumber: "REF202611030003",
			CreatedAt:       now.Add(-1 * 24 * time.Hour),
		},
	}

	logger.GetLogger().Info("Memory Core Banking Provider initialized", map[string]interface{}{
		"demo_phone":   demoUser.PhoneNumber,
		"demo_account": primaryAcc.AccountNumber,
	})
}

func (m *MemoryCBSProvider) VerifyCredentials(ctx context.Context, identifier, password, pin string) (*domain.User, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	user, exists := m.users[identifier]
	if !exists {
		return nil, ErrInvalidCredentials
	}

	if !utils.CheckPassword(user.PasswordHash, password) {
		return nil, ErrInvalidCredentials
	}

	if pin != "" && !utils.CheckPIN(user.PINHash, pin) {
		return nil, ErrInvalidCredentials
	}

	if !user.IsActive {
		return nil, ErrInactiveAccount
	}

	return user, nil
}

func (m *MemoryCBSProvider) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	acc, exists := m.accounts[accountNo]
	if !exists {
		return nil, ErrAccountNotFound
	}

	return &domain.BalanceResponse{
		AccountNumber: acc.AccountNumber,
		AccountType:   acc.AccountType,
		Balance:       acc.Balance,
		Status:        acc.Status,
		UpdatedAt:     acc.UpdatedAt,
	}, nil
}

func (m *MemoryCBSProvider) GetMutations(ctx context.Context, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	_, exists := m.accounts[accountNo]
	if !exists {
		return nil, ErrAccountNotFound
	}

	muts, found := m.mutations[accountNo]
	if !found {
		return []domain.Mutation{}, nil
	}

	if limit <= 0 || limit > 100 {
		limit = 20
	}

	count := len(muts)
	if count > limit {
		return muts[count-limit:], nil
	}

	return muts, nil
}

func (m *MemoryCBSProvider) ProcessTransfer(ctx context.Context, req *domain.TransferRequest, fromAccount string) (*domain.TransferResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	acc, exists := m.accounts[fromAccount]
	if !exists {
		return nil, ErrAccountNotFound
	}

	var userPINHash string
	for _, u := range m.users {
		if u.ID == acc.UserID {
			userPINHash = u.PINHash
			break
		}
	}
	if userPINHash != "" && !utils.CheckPIN(userPINHash, req.PIN) {
		return nil, ErrInvalidPIN
	}

	var fee float64 = 0
	toBankName := "Bank DMB Internal"
	if req.ToBankCode != "BPR" && req.ToBankCode != "DMB" && req.ToBankCode != "" {
		fee = 2500.00
		toBankName = fmt.Sprintf("BANK LAIN (%s)", req.ToBankCode)
	}

	totalDeduction := req.Amount + fee
	if acc.Balance < totalDeduction {
		return nil, ErrInsufficientBalance
	}

	acc.Balance -= totalDeduction
	acc.UpdatedAt = time.Now()

	refNo := fmt.Sprintf("TRF%s%04d", time.Now().Format("20060102150405"), rand.Intn(10000))
	txID := fmt.Sprintf("tx-%d", time.Now().UnixNano())

	desc := fmt.Sprintf("TRANSFER KE %s - %s (%s)", req.ToAccount, req.ToAccountName, toBankName)
	if req.Note != "" {
		desc += fmt.Sprintf(" - %s", req.Note)
	}

	newMutation := model.Mutation{
		ID:              txID,
		AccountNumber:   fromAccount,
		TransactionType: model.TxTypeDebit,
		Amount:          req.Amount,
		BalanceAfter:    acc.Balance,
		Description:     desc,
		ReferenceNumber: refNo,
		CreatedAt:       time.Now(),
	}
	m.mutations[fromAccount] = append(m.mutations[fromAccount], newMutation)

	return &domain.TransferResponse{
		TransactionID: txID,
		ReferenceNo:   refNo,
		FromAccount:   fromAccount,
		ToBankCode:    req.ToBankCode,
		ToBankName:    toBankName,
		ToAccount:     req.ToAccount,
		ToAccountName: req.ToAccountName,
		Amount:        req.Amount,
		Fee:           fee,
		TotalAmount:   totalDeduction,
		Note:          req.Note,
		Status:        "SUCCESS",
		Timestamp:     time.Now(),
	}, nil
}
