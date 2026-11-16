package cbsprovider

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// DatabaseCBSProvider implements CBSProvider on top of the local PostgreSQL ledger.
// It is intended for local development and integration tests only; config.Validate
// refuses it in production. It has no loan, deposit or product data source and
// therefore returns empty results (never fabricated data).
type DatabaseCBSProvider struct {
	db *gorm.DB
}

func NewDatabaseCBSProvider(db *gorm.DB) *DatabaseCBSProvider {
	return &DatabaseCBSProvider{db: db}
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
		AccountNumber:    account.AccountNumber,
		HolderName:       account.HolderName,
		ProductCode:      account.ProductCode,
		AccountType:      account.AccountType,
		Balance:          account.Balance,
		MinimumBalance:   account.MinimumBalance,
		BlockedBalance:   account.BlockedBalance,
		EffectiveBalance: account.EffectiveBalance,
		Status:           account.Status,
		UpdatedAt:        account.UpdatedAt,
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
				First(&receiver).Error; err != nil {
				// Destination unknown: roll back the debit instead of letting funds vanish.
				return ErrAccountNotFound
			}
			{

				newReceiverBalance := receiver.Balance + req.Amount
				if err := tx.Model(&receiver).Update("balance", newReceiverBalance).Error; err != nil {
					return err
				}

				descReceiver := fmt.Sprintf("TRANSFER MASUK DARI %s", fromAccount)
				creditMut := model.Mutation{
					ID:              uuid.NewString(),
					AccountNumber:   receiver.AccountNumber,
					TransactionType: model.TxTypeCredit,
					Amount:          req.Amount,
					BalanceAfter:    newReceiverBalance,
					Description:     descReceiver,
					// reference_number is unique: the credit leg needs its own reference
					// (previously identical to the debit leg, which aborted the transaction).
					ReferenceNumber: refNo + "-CR",
					CreatedAt:       now,
				}
				if err := tx.Create(&creditMut).Error; err != nil {
					return err
				}
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
	return []domain.DMBLoanAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetLoanAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBLoanAccountDetail, error) {
	return nil, ErrAccountNotFound
}

func (p *DatabaseCBSProvider) GetLoanMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountsByCIF(ctx context.Context, cifNumber string) ([]domain.DMBDepositAccountItem, error) {
	return []domain.DMBDepositAccountItem{}, nil
}

func (p *DatabaseCBSProvider) GetDepositAccountDetail(ctx context.Context, cifNumber, accountNo string) (*domain.DMBDepositAccountDetail, error) {
	return nil, ErrAccountNotFound
}

func (p *DatabaseCBSProvider) GetDepositMutations(ctx context.Context, cifNumber, accountNo, startDate, endDate string, limit int) ([]domain.Mutation, error) {
	return []domain.Mutation{}, nil
}

// GetProductsCatalog: the local ledger has no product master data. Returning a
// hardcoded "official" catalog would present unverified data as bank data.
func (p *DatabaseCBSProvider) GetProductsCatalog(ctx context.Context) (*domain.DMBProductsCatalog, error) {
	return nil, ErrCBSUnavailable
}
