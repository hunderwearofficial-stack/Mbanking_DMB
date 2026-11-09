package service

import (
	"context"
	"errors"
	"fmt"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/transaction/repository"
	"mbanking-bpr/internal/otpprovider"
	"mbanking-bpr/pkg/utils"
)

type TransactionService interface {
	Transfer(ctx context.Context, req domain.TransferRequest, fromAccount string, userID string) (*domain.TransferResponse, error)
}

type transactionService struct {
	repo    repository.TransactionRepository
	cbsProv cbsprovider.CBSProvider
}

func NewTransactionService(repo repository.TransactionRepository, cbsProv cbsprovider.CBSProvider) TransactionService {
	return &transactionService{
		repo:    repo,
		cbsProv: cbsProv,
	}
}

func (s *transactionService) Transfer(ctx context.Context, req domain.TransferRequest, fromAccount string, userID string) (*domain.TransferResponse, error) {
	// 1. Validate Customer PIN & Auto-Freeze after 3 failed PIN attempts
	user, _ := s.repo.GetUserByID(ctx, userID)
	if user != nil {
		if !user.IsActive {
			return nil, errors.New("akun nasabah sedang diblokir. Hubungi CS Bank DMB")
		}
		if user.PINHash != "" && !utils.CheckPIN(user.PINHash, req.PIN) {
			attempts, blocked, _ := s.repo.IncrementFailedPIN(ctx, user.ID, 3)
			if blocked {
				otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "AUTO_BLOCK_PIN", fromAccount, "DANGER", user.DeviceID, "Akun diblokir otomatis karena 3x salah memasukkan PIN Transaksi")
				otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), user.ID, "Akun Diblokir: 3x Salah PIN", "Demi keamanan dana Anda, akun Mobile DMB telah dikunci otomatis karena 3x salah memasukkan PIN Transaksi. Hubungi CS Bank DMB.", "SECURITY")
				return nil, errors.New("akun Anda diblokir otomatis karena 3x salah memasukkan PIN Transaksi. Silakan hubungi CS Bank DMB")
			}
			otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_PIN_FAILED", fromAccount, "WARNING", user.DeviceID, fmt.Sprintf("Salah PIN Transaksi (Percobaan %d/3)", attempts))
			return nil, fmt.Errorf("PIN transaksi salah (Percobaan %d/3)", attempts)
		}
		_ = s.repo.ResetFailedPIN(ctx, user.ID)
	}

	// 2. Call CBS to process transfer
	res, err := s.cbsProv.ProcessTransfer(ctx, &req, fromAccount)
	if err != nil {
		if user != nil {
			otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_FAILED", req.ToAccount, "WARNING", user.DeviceID, fmt.Sprintf("Transfer gagal Rp %.0f ke %s: %v", req.Amount, req.ToAccount, err))
		}
		return nil, err
	}

	txType := model.TxTransferBank
	if req.ToBankCode == "BPR" || req.ToBankCode == "" {
		txType = model.TxTransferInternal
	}

	// 3. Record transaction log into local PostgreSQL
	_ = s.repo.SaveTransaction(ctx, &model.Transaction{
		ID:              res.TransactionID,
		UserID:          userID,
		FromAccount:     res.FromAccount,
		ToAccount:       res.ToAccount,
		Amount:          res.Amount,
		TransactionType: txType,
		Status:          model.TxStatusSuccess,
		CBSReferenceNo:  res.ReferenceNo,
		CreatedAt:       res.Timestamp,
	})

	// 4. Record Audit Trail & Customer Notification
	actorName := fromAccount
	devID := ""
	if user != nil {
		actorName = user.FullName
		devID = user.DeviceID
	}
	otpprovider.RecordAuditLog(ctx, s.repo.DB(), "NASABAH", userID, actorName, "TRANSFER_SUCCESS", res.ToAccount, "SUCCESS", devID, fmt.Sprintf("Transfer Rp %.0f dari %s ke %s (%s) Ref: %s", res.Amount, res.FromAccount, res.ToAccount, res.ToAccountName, res.ReferenceNo))
	if userID != "" {
		otpprovider.CreateNotificationAndPush(ctx, s.repo.DB(), userID, "Transfer Dana Berhasil", fmt.Sprintf("Transfer sebesar Rp %.0f ke rekening %s (%s) telah berhasil diproses. No Ref: %s", res.Amount, res.ToAccount, res.ToAccountName, res.ReferenceNo), "TRANSACTION")
	}

	return res, nil
}
