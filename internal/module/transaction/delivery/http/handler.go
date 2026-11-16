package http

import (
	"errors"
	"net/http"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/transaction/service"
	"mbanking-bpr/pkg/logger"
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

// Transfer handles POST /api/v1/transaction/transfer.
// Requires header Idempotency-Key (unique per transfer attempt). `from_account` is
// optional and, if given, must belong to the authenticated customer.
func (h *TransactionHandler) Transfer(c *gin.Context) {
	var req domain.TransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "Data transaksi transfer tidak valid", nil)
		return
	}

	res, err := h.txService.Transfer(c.Request.Context(), service.TransferInput{
		UserID:         c.GetString(middleware.CtxUserID),
		CIF:            c.GetString(middleware.CtxCIF),
		TokenAccount:   c.GetString(middleware.CtxAccountNo),
		DeviceID:       c.GetString(middleware.CtxDeviceID),
		IdempotencyKey: c.GetHeader("Idempotency-Key"),
		Request:        req,
	})
	requestID := ""
	if res != nil {
		requestID = res.RequestID
	}
	if err != nil {
		detail := gin.H{"request_id": requestID}
		switch {
		case errors.Is(err, service.ErrOutcomeUnknown):
			response.ErrorWithCode(c, http.StatusAccepted, "09", err.Error(), detail)
		case errors.Is(err, service.ErrTransferInProgress), errors.Is(err, service.ErrIdempotencyConflict):
			response.ErrorWithCode(c, http.StatusConflict, "07", err.Error(), detail)
		case errors.Is(err, service.ErrSourceNotOwned):
			response.ErrorWithCode(c, http.StatusForbidden, response.CodeUnauthorized, "Rekening sumber tidak terdaftar atas nama Anda", nil)
		case errors.Is(err, cbsprovider.ErrInsufficientBalance):
			response.ErrorWithCode(c, http.StatusBadRequest, response.CodeInsufficientBalance, err.Error(), detail)
		case errors.Is(err, cbsprovider.ErrInvalidPIN):
			response.ErrorWithCode(c, http.StatusUnauthorized, response.CodeInvalidCredentials, err.Error(), nil)
		case errors.Is(err, cbsprovider.ErrAccountNotFound):
			response.NotFound(c, err.Error())
		case errors.Is(err, cbsprovider.ErrCBSRejected):
			response.ErrorWithCode(c, http.StatusUnprocessableEntity, response.CodeBadRequest, "Transaksi ditolak oleh Core Banking. Dana Anda tidak terdebet.", detail)
		case errors.Is(err, service.ErrServiceUnavailable):
			response.ErrorWithCode(c, http.StatusServiceUnavailable, response.CodeInternalError, err.Error(), nil)
		case errors.Is(err, service.ErrRejected):
			// Validation / business-rule rejection (safe message, no funds moved).
			response.ErrorWithCode(c, http.StatusBadRequest, response.CodeBadRequest, err.Error(), nil)
		default:
			// Unexpected failure: details only in the server log (audit DMB-024).
			logger.GetLogger().Error("Transfer gagal karena kesalahan internal", map[string]interface{}{"request_id": requestID, "error": err.Error()})
			response.ErrorWithCode(c, http.StatusServiceUnavailable, response.CodeInternalError,
				"Layanan sedang mengalami gangguan. Silakan coba kembali beberapa saat lagi.", detail)
		}
		return
	}
	response.Success(c, "Transaksi transfer berhasil diproses", res.Response)
}
