package http

import (
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/account/service"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

type AccountHandler struct {
	accountService service.AccountService
}

func NewAccountHandler(accountService service.AccountService) *AccountHandler {
	return &AccountHandler{accountService: accountService}
}

// GetBalance handles GET /api/v1/account/balance
func (h *AccountHandler) GetBalance(c *gin.Context) {
	// Account number, CIF, and UserID can be inferred from JWT context or passed via query
	accountNo := c.Query("account_number")
	if accountNo == "" {
		if val, exists := c.Get(middleware.CtxAccountNo); exists {
			accountNo, _ = val.(string)
		}
	}

	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo, _ = val.(string)
		}
	}

	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID, _ = val.(string)
	}

	if accountNo == "" && cifNo == "" && userID == "" {
		response.BadRequest(c, "Identitas rekening atau nasabah tidak ditemukan", nil)
		return
	}

	res, err := h.accountService.GetBalance(c.Request.Context(), accountNo, cifNo, userID)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Inquiry saldo berhasil", res)
}

// GetMutations handles GET /api/v1/account/mutations
func (h *AccountHandler) GetMutations(c *gin.Context) {
	var query domain.MutationQueryParam
	if err := c.ShouldBindQuery(&query); err != nil {
		response.BadRequest(c, "Format parameter query mutasi tidak valid", err.Error())
		return
	}

	if query.AccountNumber == "" {
		if val, exists := c.Get(middleware.CtxAccountNo); exists {
			query.AccountNumber, _ = val.(string)
		}
	}

	cifNo := ""
	if val, exists := c.Get(middleware.CtxCIF); exists {
		cifNo, _ = val.(string)
	}

	userID := ""
	if val, exists := c.Get(middleware.CtxUserID); exists {
		userID, _ = val.(string)
	}

	if query.AccountNumber == "" && cifNo == "" && userID == "" {
		response.BadRequest(c, "Nomor rekening wajib disertakan", nil)
		return
	}

	mutations, err := h.accountService.GetMutations(c.Request.Context(), query.AccountNumber, cifNo, userID, query)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Pengambilan riwayat mutasi rekening berhasil", gin.H{
		"account_number": query.AccountNumber,
		"total_records":  len(mutations),
		"mutations":      mutations,
	})
}

// InquiryAccount handles GET /api/v1/account/inquiry?account_number=... (for recipient lookup via CBS)
func (h *AccountHandler) InquiryAccount(c *gin.Context) {
	accountNo := c.Query("account_number")
	if accountNo == "" {
		response.BadRequest(c, "Nomor rekening tujuan wajib diisi", nil)
		return
	}

	res, err := h.accountService.GetBalance(c.Request.Context(), accountNo, "", "")
	if err != nil || res == nil {
		response.NotFound(c, "Nomor rekening tujuan tidak ditemukan di Core Banking")
		return
	}

	response.Success(c, "Verifikasi rekening tujuan berhasil", gin.H{
		"account_number": res.AccountNumber,
		"holder_name":    res.HolderName,
		"product_code":   res.ProductCode,
		"account_type":   res.AccountType,
		"status":         res.Status,
	})
}

// GetCustomerProfile handles GET /api/v1/account/profile (calls CBS POST /api/nasabah)
func (h *AccountHandler) GetCustomerProfile(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}

	if cifNo == "" {
		response.BadRequest(c, "Nomor CIF tidak ditemukan", nil)
		return
	}

	data, err := h.accountService.GetCustomerByCIF(c.Request.Context(), cifNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Data profil nasabah Core Banking berhasil diambil", data)
}

// GetSavingsAccounts handles GET /api/v1/account/list (calls CBS POST /api/savings-accounts)
func (h *AccountHandler) GetSavingsAccounts(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}

	if cifNo == "" {
		response.BadRequest(c, "Nomor CIF tidak ditemukan", nil)
		return
	}

	items, err := h.accountService.GetSavingsAccountsByCIF(c.Request.Context(), cifNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Daftar rekening tabungan Core Banking berhasil diambil", gin.H{
		"cif_number":     cifNo,
		"total_accounts": len(items),
		"accounts":       items,
	})
}


