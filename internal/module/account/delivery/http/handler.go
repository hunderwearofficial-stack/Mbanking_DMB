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

// GetLoans handles GET /api/v1/account/loans (calls /api/loan-accounts)
func (h *AccountHandler) GetLoans(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	if cifNo == "" {
		cifNo = "001000309659"
	}

	loans, err := h.accountService.GetLoans(c.Request.Context(), cifNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Daftar rekening pinjaman berhasil diambil", gin.H{
		"cif_number":  cifNo,
		"total_loans": len(loans),
		"loans":      loans,
	})
}

// GetLoanDetail handles GET /api/v1/account/loans/:account_no (calls /api/loan-account-detail)
func (h *AccountHandler) GetLoanDetail(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	if cifNo == "" {
		cifNo = "001000309659"
	}
	accountNo := c.Param("account_no")
	if accountNo == "" {
		accountNo = c.Query("account_number")
	}

	detail, err := h.accountService.GetLoanDetail(c.Request.Context(), cifNo, accountNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Rincian pinjaman berhasil diambil", detail)
}

// GetLoanMutations handles GET /api/v1/account/loans/:account_no/mutations (calls /api/loan-account-mutations)
func (h *AccountHandler) GetLoanMutations(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	if cifNo == "" {
		cifNo = "001000309659"
	}
	accountNo := c.Param("account_no")
	if accountNo == "" {
		accountNo = c.Query("account_number")
	}
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	muts, err := h.accountService.GetLoanMutations(c.Request.Context(), cifNo, accountNo, startDate, endDate, 20)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Riwayat angsuran pinjaman berhasil diambil", gin.H{
		"account_number": accountNo,
		"total_records":  len(muts),
		"mutations":      muts,
	})
}

// GetDeposits handles GET /api/v1/account/deposits (calls /api/deposit-accounts)
func (h *AccountHandler) GetDeposits(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	if cifNo == "" {
		cifNo = "001000309659"
	}

	deposits, err := h.accountService.GetDeposits(c.Request.Context(), cifNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Daftar bilyet deposito berhasil diambil", gin.H{
		"cif_number":     cifNo,
		"total_deposits": len(deposits),
		"deposits":      deposits,
	})
}

// GetDepositDetail handles GET /api/v1/account/deposits/:account_no (calls /api/deposit-account-detail)
func (h *AccountHandler) GetDepositDetail(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	if cifNo == "" {
		cifNo = "001000309659"
	}
	accountNo := c.Param("account_no")
	if accountNo == "" {
		accountNo = c.Query("account_number")
	}

	detail, err := h.accountService.GetDepositDetail(c.Request.Context(), cifNo, accountNo)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Rincian bilyet deposito berhasil diambil", detail)
}

// GetDepositMutations handles GET /api/v1/account/deposits/:account_no/mutations (calls /api/deposit-account-mutations)
func (h *AccountHandler) GetDepositMutations(c *gin.Context) {
	cifNo := c.Query("cif_number")
	if cifNo == "" {
		if val, exists := c.Get(middleware.CtxCIF); exists {
			cifNo = val.(string)
		}
	}
	accountNo := c.Param("account_no")
	if accountNo == "" {
		accountNo = c.Query("account_number")
	}
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	muts, err := h.accountService.GetDepositMutations(c.Request.Context(), cifNo, accountNo, startDate, endDate, 20)
	if err != nil {
		response.NotFound(c, err.Error())
		return
	}

	response.Success(c, "Riwayat bagi hasil deposito berhasil diambil", gin.H{
		"account_number": accountNo,
		"total_records":  len(muts),
		"mutations":      muts,
	})
}

// GetProducts handles GET /api/v1/account/products (calls /api/products)
func (h *AccountHandler) GetProducts(c *gin.Context) {
	catalog, err := h.accountService.GetProductsCatalog(c.Request.Context())
	if err != nil {
		response.InternalServerError(c, err.Error())
		return
	}

	response.Success(c, "Katalog resmi produk perbankan DMB berhasil diambil", catalog)
}


