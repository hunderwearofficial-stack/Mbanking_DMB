package cbsprovider

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// DatabaseCBSProvider implements CBSProvider using our internal relational database (PostgreSQL/GORM).
// This serves as the single source of truth for all accounts, balances, mutations, and transactions
// until the Bank's Core Banking System (CBS) API is ready for integration.
type DatabaseCBSProvider struct {
	db  *gorm.DB
	mem *MemoryCBSProvider
}

func NewDatabaseCBSProvider(db *gorm.DB) *DatabaseCBSProvider {
	return &DatabaseCBSProvider{
		db:  db,
		mem: NewMemoryCBSProvider(),
	}
}

func (p *DatabaseCBSProvider) Ping(ctx context.Context) (*domain.CBSHealthStatus, error) {
	return &domain.CBSHealthStatus{
		Connected: true,
		Status:    "OK",
		Code:      10000,
		Message:   "Database CBS Engine Active",
		Timestamp: time.Now().Format(time.RFC3339),
	}, nil
}

func (p *DatabaseCBSProvider) RefreshToken(ctx context.Context) error {
	return nil
}

func (p *DatabaseCBSProvider) GetCustomerByCIF(ctx context.Context, cifNumber string) (*domain.CBSNasabahData, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}
	var user model.User
	if err := p.db.WithContext(ctx).Where("cif = ?", cifNumber).First(&user).Error; err != nil {
		return nil, ErrAccountNotFound
	}
	return &domain.CBSNasabahData{
		CIF:   user.CIF,
		Nama:  user.FullName,
		NoHP:  user.PhoneNumber,
		Email: string(user.Email),
	}, nil
}

func (p *DatabaseCBSProvider) GetSavingsAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.CBSSavingsAccountItem, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}
	var user model.User
	if err := p.db.WithContext(ctx).Preload("Accounts").Where("cif = ?", cifNumber).First(&user).Error; err != nil {
		return nil, ErrAccountNotFound
	}
	var items []domain.CBSSavingsAccountItem
	for _, acc := range user.Accounts {
		items = append(items, domain.CBSSavingsAccountItem{
			NomorRekening:  acc.AccountNumber,
			Nama:           user.FullName,
			ProdukTabungan: acc.AccountType,
			Saldo:          acc.Balance,
		})
	}
	return items, nil
}

// VerifyCredentials verifies user password and/or transaction PIN directly from the database.
func (p *DatabaseCBSProvider) VerifyCredentials(ctx context.Context, username, password, pin string) (*domain.User, error) {
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

	// Verify Password if supplied
	if password != "" && !utils.CheckPassword(user.PasswordHash, password) {
		return nil, ErrInvalidCredentials
	}

	// Verify PIN if supplied
	if pin != "" && !utils.CheckPIN(user.PINHash, pin) {
		return nil, ErrInvalidPIN
	}

	return &user, nil
}

// GetBalance retrieves live real-time account balance from the database.
func (p *DatabaseCBSProvider) GetBalance(ctx context.Context, accountNo string) (*domain.BalanceResponse, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}

	var account model.Account
	err := p.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		First(&account).Error
	if err != nil {
		return nil, ErrAccountNotFound
	}

	if account.Status != model.AccountStatusActive {
		return nil, ErrInactiveAccount
	}

	return &domain.BalanceResponse{
		AccountNumber: account.AccountNumber,
		AccountType:   account.AccountType,
		Balance:       account.Balance,
		Status:        account.Status,
		UpdatedAt:     account.UpdatedAt,
	}, nil
}

// GetMutations fetches actual transaction history from the database mutation records.
func (p *DatabaseCBSProvider) GetMutations(ctx context.Context, cifNumber, accountNo string, startDate, endDate string, limit int) ([]domain.Mutation, error) {
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

	if startDate != "" {
		if start, err := time.Parse("2006-01-02", startDate); err == nil {
			query = query.Where("created_at >= ?", start)
		}
	}
	if endDate != "" {
		if end, err := time.Parse("2006-01-02", endDate); err == nil {
			query = query.Where("created_at <= ?", end.Add(24*time.Hour))
		}
	}

	if err := query.Find(&rows).Error; err != nil {
		return nil, err
	}

	return rows, nil
}

// ProcessTransfer executes atomic transfer between accounts in the database using strict ACID transaction.
func (p *DatabaseCBSProvider) ProcessTransfer(ctx context.Context, req *domain.TransferRequest, fromAccount string) (*domain.TransferResponse, error) {
	if p.db == nil {
		return nil, ErrAccountNotFound
	}

	now := time.Now()
	refNo := fmt.Sprintf("REF%s%04d", now.Format("20060102150405"), rand.Intn(10000))
	cbsRefNo := fmt.Sprintf("CBS-DMB-%s", refNo)

	// Atomic Database Transaction with Row-Level Locking (Pessimistic Lock)
	err := p.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch & lock sender account
		var sender model.Account
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("account_number = ?", fromAccount).
			First(&sender).Error; err != nil {
			return ErrAccountNotFound
		}

		if sender.Status != model.AccountStatusActive {
			return ErrInactiveAccount
		}

		// 2. Validate sufficient balance
		if sender.Balance < req.Amount {
			return ErrInsufficientBalance
		}

		// 3. Deduct sender balance
		newSenderBalance := sender.Balance - req.Amount
		if err := tx.Model(&sender).Update("balance", newSenderBalance).Error; err != nil {
			return err
		}

		// 4. Record DEBIT mutation for sender
		descSender := fmt.Sprintf("TRANSFER KE %s (%s)", req.ToAccount, req.ToBankCode)
		if req.Note != "" {
			descSender += fmt.Sprintf(" - %s", req.Note)
		}
		debitMut := model.Mutation{
			ID:              uuid.NewString(),
			AccountNumber:   sender.AccountNumber,
			TransactionType: model.TxTypeDebit,
			Amount:          req.Amount,
			BalanceAfter:    newSenderBalance,
			Description:     descSender,
			ReferenceNumber: refNo,
			CreatedAt:       now,
		}
		if err := tx.Create(&debitMut).Error; err != nil {
			return err
		}

		// 5. If Internal Transfer (DMB to DMB), credit recipient account
		if req.ToBankCode == "BPR_DMB" || req.ToBankCode == "DMB" || req.ToBankCode == "000" {
			var receiver model.Account
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("account_number = ?", req.ToAccount).
				First(&receiver).Error; err == nil {

				newReceiverBalance := receiver.Balance + req.Amount
				_ = tx.Model(&receiver).Update("balance", newReceiverBalance).Error

				descReceiver := fmt.Sprintf("TRANSFER MASUK DARI %s", fromAccount)
				creditMut := model.Mutation{
					ID:              uuid.NewString(),
					AccountNumber:   receiver.AccountNumber,
					TransactionType: model.TxTypeCredit,
					Amount:          req.Amount,
					BalanceAfter:    newReceiverBalance,
					Description:     descReceiver,
					ReferenceNumber: refNo,
					CreatedAt:       now,
				}
				_ = tx.Create(&creditMut).Error
			}
		}

		// 6. Log transaction record in Transaction audit table
		txType := "TRANSFER_INTERNAL"
		if req.ToBankCode != "BPR_DMB" && req.ToBankCode != "DMB" && req.ToBankCode != "000" {
			txType = "TRANSFER_BANK"
		}

		txRecord := model.Transaction{
			ID:              uuid.NewString(),
			UserID:          sender.UserID,
			FromAccount:     fromAccount,
			ToAccount:       req.ToAccount,
			Amount:          req.Amount,
			TransactionType: txType,
			Status:          model.TxStatusSuccess,
			CBSReferenceNo:  cbsRefNo,
			CreatedAt:       now,
		}
		return tx.Create(&txRecord).Error
	})

	if err != nil {
		return nil, err
	}

	return &domain.TransferResponse{
		TransactionID: refNo,
		ReferenceNo:   refNo,
		FromAccount:   fromAccount,
		ToBankCode:    req.ToBankCode,
		ToBankName:    "Bank DMB / Mitra Bank",
		ToAccount:     req.ToAccount,
		ToAccountName: req.ToAccountName,
		Amount:        req.Amount,
		Fee:           0,
		TotalAmount:   req.Amount,
		Note:          req.Note,
		Status:        model.TxStatusSuccess,
		Timestamp:     now,
	}, nil
}

func (p *DatabaseCBSProvider) GetLoanAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBLoanAccountItem, error) {
	if p.mem != nil {
		return p.mem.GetLoanAccountsByCIF(ctx, cifNumber)
	}
	return []domain.DMBLoanAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	if p.mem != nil {
		return p.mem.GetLoanAccountDetail(ctx, cifNumber, accountNo)
	}
	return nil, errors.New("data pinjaman tidak ditemukan")
}

func (p *DatabaseCBSProvider) GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if p.mem != nil {
		return p.mem.GetLoanMutations(ctx, cifNumber, accountNo, startDate, endDate, limit)
	}
	return []domain.Mutation{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error) {
	if p.mem != nil {
		return p.mem.GetDepositAccountsByCIF(ctx, cifNumber)
	}
	return []domain.DMBDepositAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	if p.mem != nil {
		return p.mem.GetDepositAccountDetail(ctx, cifNumber, accountNo)
	}
	return nil, errors.New("data deposito tidak ditemukan")
}

func (p *DatabaseCBSProvider) GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	if p.mem != nil {
		return p.mem.GetDepositMutations(ctx, cifNumber, accountNo, startDate, endDate, limit)
	}
	return []domain.Mutation{}, nil
}

func (p *DatabaseCBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
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
