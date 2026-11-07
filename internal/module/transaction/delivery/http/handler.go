package http

import (
	"errors"
	"net/http"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/transaction/service"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type TransactionHandler struct {
	txService service.TransactionService
}

func NewTransactionHandler(txService service.TransactionService) *TransactionHandler {
	return &TransactionHandler{txService: txService}
}

// Transfer handles POST /api/v1/transaction/transfer
func (h *TransactionHandler) Transfer(c *gin.Context) {
	var req domain.TransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Data transaksi transfer tidak valid", err.Error())
		return
	}

	fromAccount := req.FromAccount
	if fromAccount == "" {
		if val, exists := c.Get(middleware.CtxAccountNo); exists {
			fromAccount = val.(string)
		}
	}

	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID = val.(string)
	}

	if fromAccount == "" {
		response.BadRequest(c, "Nomor rekening pengirim tidak ditemukan", nil)
		return
	}

	res, err := h.txService.Transfer(c.Request.Context(), req, fromAccount, userID)
	if err != nil {
		if errors.Is(err, cbsprovider.ErrInsufficientBalance) {
			response.ErrorWithCode(c, http.StatusBadRequest, response.CodeInsufficientBalance, err.Error(), nil)
			return
		}
		if errors.Is(err, cbsprovider.ErrInvalidPIN) {
			response.ErrorWithCode(c, http.StatusUnauthorized, response.CodeInvalidCredentials, err.Error(), nil)
			return
		}
		if errors.Is(err, cbsprovider.ErrAccountNotFound) {
			response.NotFound(c, err.Error())
			return
		}
		response.InternalServerError(c, err.Error())
		return
	}

	response.Success(c, "Transaksi transfer berhasil diproses", res)
}
