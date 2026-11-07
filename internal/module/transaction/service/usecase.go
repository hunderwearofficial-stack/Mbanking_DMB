package service

import (
	"context"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/transaction/repository"
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
	// Call CBS to process transfer
	res, err := s.cbsProv.ProcessTransfer(ctx, &req, fromAccount)
	if err != nil {
		return nil, err
	}

	txType := model.TxTransferBank
	if req.ToBankCode == "BPR" || req.ToBankCode == "" {
		txType = model.TxTransferInternal
	}

	// Record transaction log into local PostgreSQL
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

	return res, nil
}
