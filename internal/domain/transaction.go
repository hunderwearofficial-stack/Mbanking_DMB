package domain

import (
	"time"

	"mbanking-bpr/internal/model"
)

type Transaction = model.Transaction

type TransferRequest struct {
	FromAccount   string  `json:"from_account"`
	ToBankCode    string  `json:"to_bank_code" binding:"required"` // "BPR" or 3-digit bank code
	ToAccount     string  `json:"to_account" binding:"required"`
	ToAccountName string  `json:"to_account_name"`
	Amount        float64 `json:"amount" binding:"required,gt=0"`
	Note          string  `json:"note"`
	PIN           string  `json:"pin" binding:"required,len=6"` // 6-digit transaction PIN
}

type TransferResponse struct {
	TransactionID string    `json:"transaction_id"`
	ReferenceNo   string    `json:"reference_no"`
	FromAccount   string    `json:"from_account"`
	ToBankCode    string    `json:"to_bank_code"`
	ToBankName    string    `json:"to_bank_name"`
	ToAccount     string    `json:"to_account"`
	ToAccountName string    `json:"to_account_name"`
	Amount        float64   `json:"amount"`
	Fee           float64   `json:"fee"`
	TotalAmount   float64   `json:"total_amount"`
	Note          string    `json:"note"`
	Status        string    `json:"status"` // SUCCESS, PENDING, FAILED
	Timestamp     time.Time `json:"timestamp"`
}
