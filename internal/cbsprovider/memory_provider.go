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
				Email: string(u.Email),
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
	// Clean initial state (no dummy customer/mutation seeding)
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

func (m *MemoryCBSProvider) GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
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

func (m *MemoryCBSProvider) GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error) {
	return []domain.DMBLoanAccountItem{
		{
			NomorRekening:           "1700105000000013",
			KodeProduk:              "17",
			NamaProduk:              "Kredit Modal Kerja",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Plafon:                  1700000000,
			BakiDebet:               1000000000,
			Kolektibilitas:          1,
			KolektibilitasKeterangan: "Lancar",
		},
	}, nil
}

func (m *MemoryCBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	acc := accountNo
	if acc == "" {
		acc = "1700105000000013"
	}
	return &domain.DMBLoanAccountDetail{
		NomorRekening:           acc,
		KodeProduk:              "17",
		NamaProduk:              "Kredit Modal Kerja",
		StatusRekening:          1,
		StatusRekeningKeterangan: "Aktif",
		Plafon:                  1700000000,
		BakiDebet:               1000000000,
		Kolektibilitas:          1,
		KolektibilitasKeterangan: "Lancar",
		NomorPerjanjian:         "PK-KMK/DMB/2025/11/0088",
		Angsuran:                38500000,
		JatuhTempoBerikutnya:    "2026-12-15",
		JangkaWaktu:             36,
		SisaJangkaWaktu:         24,
		SatuanWaktu:             "Bulan",
		TanggalJatuhTempo:       "2028-11-15",
		SukuBungaTahunan:        11.5,
		MetodeBunga:             "Efektif/Anuitas",
		Agunan:                  "Sertifikat Hak Milik (SHM) No. 04812/Bogor",
		SandiKantor:             "001",
		NamaKantor:              "KC Bogor Utama",
	}, nil
}

func (m *MemoryCBSProvider) GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{
		{
			ID:              "mut-loan-001",
			AccountNumber:   accountNo,
			TransactionType: model.TxTypeCredit,
			Amount:          38500000,
			BalanceAfter:    1000000000,
			Description:     "Pembayaran Angsuran Kredit Modal Kerja",
			ReferenceNumber: "KMK-2026-11-10",
			CreatedAt:       time.Now().AddDate(0, 0, -2),
		},
	}, nil
}

func (m *MemoryCBSProvider) GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error) {
	return []domain.DMBDepositAccountItem{
		{
			NomorRekening:           "0100104000001716",
			KodeProduk:              "01",
			NamaProduk:              "DEPOSITO 01 BULAN",
			StatusRekening:          3,
			StatusRekeningKeterangan: "Blokir",
			Nominal:                 300000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-06-01",
		},
		{
			NomorRekening:           "0100104000001717",
			KodeProduk:              "01",
			NamaProduk:              "DEPOSITO 01 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 200000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-06-01",
		},
		{
			NomorRekening:           "0100104000001718",
			KodeProduk:              "01",
			NamaProduk:              "DEPOSITO 01 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 200000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-06-01",
		},
		{
			NomorRekening:           "0300104000000969",
			KodeProduk:              "03",
			NamaProduk:              "DEPOSITO 03 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 245000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-08-12",
		},
		{
			NomorRekening:           "0600104000000333",
			KodeProduk:              "06",
			NamaProduk:              "DEPOSITO 06 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 51310685,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-07-31",
		},
		{
			NomorRekening:           "0600104000000393",
			KodeProduk:              "06",
			NamaProduk:              "DEPOSITO 06 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 51196712,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-10-17",
		},
		{
			NomorRekening:           "0600104000000468",
			KodeProduk:              "06",
			NamaProduk:              "DEPOSITO 06 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 250000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-07-13",
		},
		{
			NomorRekening:           "0600104000000470",
			KodeProduk:              "06",
			NamaProduk:              "DEPOSITO 06 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 250000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-07-15",
		},
		{
			NomorRekening:           "0600104000000471",
			KodeProduk:              "06",
			NamaProduk:              "DEPOSITO 06 BULAN",
			StatusRekening:          1,
			StatusRekeningKeterangan: "Aktif",
			Nominal:                 250000000,
			SukuBungaTahunan:        6.0,
			TanggalJatuhTempo:       "2026-07-19",
		},
	}, nil
}

func (m *MemoryCBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	acc := accountNo
	if acc == "" {
		acc = "0100104000001717"
	}
	return &domain.DMBDepositAccountDetail{
		NomorRekening:           acc,
		KodeProduk:              "01",
		NamaProduk:              "DEPOSITO 01 BULAN",
		StatusRekening:          1,
		StatusRekeningKeterangan: "Aktif",
		Nominal:                 200000000,
		SukuBungaTahunan:        6.0,
		TanggalJatuhTempo:       "2026-06-01",
		NomorBilyet:             "BLT-DMB-" + acc[len(acc)-5:],
		JangkaWaktuBulan:        1,
		TanggalBuka:             "2026-05-01",
		TanggalEfektif:          "2026-05-01",
		ARO:                     true,
		JenisARO:                "Pokok & Bunga",
		BungaBerjalan:           1000000,
		SaldoTertahan:           0,
		RekeningPencairanBunga:  "0500103000006961",
		SandiKantor:             "001",
		NamaKantor:              "KC Bogor Utama",
	}, nil
}

func (m *MemoryCBSProvider) GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{
		{
			ID:              "mut-dep-001",
			AccountNumber:   accountNo,
			TransactionType: model.TxTypeCredit,
			Amount:          130200,
			BalanceAfter:    25000000,
			Description:     "Pencairan Bunga Deposito Bulanan",
			ReferenceNumber: "DEP-2026-10-15",
			CreatedAt:       time.Now().AddDate(0, 0, -28),
		},
	}, nil
}

func (m *MemoryCBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	return &domain.DMBProductsCatalog{
		Tabungan: []domain.DMBProductItem{
			{KodeProduk: "05", NamaProduk: "DANA MANDIRI", Aktif: true},
			{KodeProduk: "20", NamaProduk: "TBW", Aktif: true},
			{KodeProduk: "21", NamaProduk: "TAB IMPIANKU", Aktif: true},
		},
		Kredit: []domain.DMBProductItem{
			{KodeProduk: "17", NamaProduk: "Kredit Modal Kerja", Aktif: true},
			{KodeProduk: "18", NamaProduk: "Kredit Micro Individual Loan (MIL)", Aktif: true},
		},
		Deposito: []domain.DMBProductItem{
			{KodeProduk: "01", NamaProduk: "DEPOSITO 01 BULAN", Aktif: true},
			{KodeProduk: "03", NamaProduk: "DEPOSITO 03 BULAN", Aktif: true},
			{KodeProduk: "06", NamaProduk: "DEPOSITO 06 BULAN", Aktif: true},
			{KodeProduk: "12", NamaProduk: "DEPOSITO 12 BULAN", Aktif: true},
		},
	}, nil
}
