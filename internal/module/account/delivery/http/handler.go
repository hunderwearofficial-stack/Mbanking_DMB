package http

import (
	"errors"
	"net/http"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/account/service"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/middleware"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

// AccountHandler serves customer account data. The customer identity (user id,
// CIF) is ALWAYS taken from the verified token; the legacy `cif_number` query
// parameter is ignored. A client-supplied account number is accepted only if the
// service confirms it belongs to the caller (audit DMB-005).
type AccountHandler struct {
	accountService service.AccountService
}

func NewAccountHandler(accountService service.AccountService) *AccountHandler {
	return &AccountHandler{accountService: accountService}
}

func caller(c *gin.Context) service.Caller {
	return service.Caller{
		UserID:       c.GetString(middleware.CtxUserID),
		CIF:          c.GetString(middleware.CtxCIF),
		TokenAccount: c.GetString(middleware.CtxAccountNo),
	}
}

// respondErr distinguishes authorization failures, genuinely missing data and
// runtime service disruptions. Disruptions never return (stale) data and are
// reported with a retry message; technical details stay in the server log.
func respondErr(c *gin.Context, err error, notFoundMsg, unavailableMsg string) {
	switch {
	case errors.Is(err, service.ErrForbidden):
		response.Error(c, http.StatusForbidden, "Rekening tidak terdaftar atas nama Anda", "01", nil)
	case errors.Is(err, cbsprovider.ErrAccountNotFound):
		response.NotFound(c, notFoundMsg)
	default:
		logger.GetLogger().Warn("Data rekening tidak dapat diambil", map[string]interface{}{"path": c.FullPath(), "error": err.Error()})
		response.Error(c, http.StatusServiceUnavailable, unavailableMsg, "SERVICE_UNAVAILABLE", nil)
	}
}

// GetBalance handles GET /api/v1/account/balance[?account_number=<owned account>]
func (h *AccountHandler) GetBalance(c *gin.Context) {
	res, err := h.accountService.GetBalance(c.Request.Context(), caller(c), c.Query("account_number"))
	if err != nil {
		respondErr(c, err, "Data saldo rekening tidak ditemukan", "Saldo belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Inquiry saldo berhasil", res)
}

// GetMutations handles GET /api/v1/account/mutations
func (h *AccountHandler) GetMutations(c *gin.Context) {
	var query domain.MutationQueryParam
	if err := c.ShouldBindQuery(&query); err != nil {
		response.BadRequest(c, "Format parameter query mutasi tidak valid", nil)
		return
	}
	accNo, mutations, err := h.accountService.GetMutations(c.Request.Context(), caller(c), query)
	if err != nil {
		respondErr(c, err, "Riwayat mutasi tidak ditemukan", "Riwayat mutasi belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Pengambilan riwayat mutasi rekening berhasil", gin.H{
		"account_number": accNo,
		"total_records":  len(mutations),
		"mutations":      mutations,
	})
}

// InquiryAccount handles GET /api/v1/account/inquiry?account_number=... (transfer recipient lookup).
// Returns only the data needed to confirm the beneficiary — never balances.
func (h *AccountHandler) InquiryAccount(c *gin.Context) {
	accountNo := c.Query("account_number")
	if accountNo == "" {
		response.BadRequest(c, "Nomor rekening tujuan wajib diisi", nil)
		return
	}
	res, err := h.accountService.InquiryRecipient(c.Request.Context(), accountNo)
	if err == nil && res == nil {
		err = cbsprovider.ErrAccountNotFound
	}
	if err != nil {
		respondErr(c, err, "Nomor rekening tujuan tidak ditemukan di Core Banking", "Rekening tujuan belum dapat diverifikasi. Silakan coba kembali.")
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

// GetCustomerProfile handles GET /api/v1/account/profile (own profile only)
func (h *AccountHandler) GetCustomerProfile(c *gin.Context) {
	data, err := h.accountService.GetCustomerProfile(c.Request.Context(), caller(c))
	if err != nil {
		respondErr(c, err, "Data profil nasabah tidak ditemukan", "Data profil belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Data profil nasabah Core Banking berhasil diambil", data)
}

// GetSavingsAccounts handles GET /api/v1/account/list (own accounts only)
func (h *AccountHandler) GetSavingsAccounts(c *gin.Context) {
	cl := caller(c)
	items, err := h.accountService.GetSavingsAccounts(c.Request.Context(), cl)
	if err != nil {
		respondErr(c, err, "Daftar rekening tidak ditemukan", "Daftar rekening belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Daftar rekening tabungan Core Banking berhasil diambil", gin.H{
		"cif_number":     cl.CIF,
		"total_accounts": len(items),
		"accounts":       items,
	})
}

// GetLoans handles GET /api/v1/account/loans
func (h *AccountHandler) GetLoans(c *gin.Context) {
	cl := caller(c)
	loans, err := h.accountService.GetLoans(c.Request.Context(), cl)
	if err != nil {
		respondErr(c, err, "Data pinjaman tidak ditemukan", "Data pinjaman belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Daftar rekening pinjaman berhasil diambil", gin.H{
		"cif_number":  cl.CIF,
		"total_loans": len(loans),
		"loans":       loans,
	})
}

func accountParam(c *gin.Context) string {
	if v := c.Param("account_no"); v != "" {
		return v
	}
	return c.Query("account_number")
}

// GetLoanDetail handles GET /api/v1/account/loans/:account_no
func (h *AccountHandler) GetLoanDetail(c *gin.Context) {
	detail, err := h.accountService.GetLoanDetail(c.Request.Context(), caller(c), accountParam(c))
	if err != nil {
		respondErr(c, err, "Rincian pinjaman tidak ditemukan", "Rincian pinjaman belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Rincian pinjaman berhasil diambil", detail)
}

// GetLoanMutations handles GET /api/v1/account/loans/:account_no/mutations
func (h *AccountHandler) GetLoanMutations(c *gin.Context) {
	accountNo := accountParam(c)
	muts, err := h.accountService.GetLoanMutations(c.Request.Context(), caller(c), accountNo, c.Query("start_date"), c.Query("end_date"), 20)
	if err != nil {
		respondErr(c, err, "Riwayat angsuran tidak ditemukan", "Riwayat angsuran belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Riwayat angsuran pinjaman berhasil diambil", gin.H{
		"account_number": accountNo,
		"total_records":  len(muts),
		"mutations":      muts,
	})
}

// GetDeposits handles GET /api/v1/account/deposits
func (h *AccountHandler) GetDeposits(c *gin.Context) {
	cl := caller(c)
	deposits, err := h.accountService.GetDeposits(c.Request.Context(), cl)
	if err != nil {
		respondErr(c, err, "Data deposito tidak ditemukan", "Data deposito belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Daftar bilyet deposito berhasil diambil", gin.H{
		"cif_number":     cl.CIF,
		"total_deposits": len(deposits),
		"deposits":       deposits,
	})
}

// GetDepositDetail handles GET /api/v1/account/deposits/:account_no
func (h *AccountHandler) GetDepositDetail(c *gin.Context) {
	detail, err := h.accountService.GetDepositDetail(c.Request.Context(), caller(c), accountParam(c))
	if err != nil {
		respondErr(c, err, "Rincian deposito tidak ditemukan", "Rincian deposito belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Rincian bilyet deposito berhasil diambil", detail)
}

// GetDepositMutations handles GET /api/v1/account/deposits/:account_no/mutations
func (h *AccountHandler) GetDepositMutations(c *gin.Context) {
	accountNo := accountParam(c)
	muts, err := h.accountService.GetDepositMutations(c.Request.Context(), caller(c), accountNo, c.Query("start_date"), c.Query("end_date"), 20)
	if err != nil {
		respondErr(c, err, "Riwayat deposito tidak ditemukan", "Riwayat deposito belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Riwayat bagi hasil deposito berhasil diambil", gin.H{
		"account_number": accountNo,
		"total_records":  len(muts),
		"mutations":      muts,
	})
}

// GetProducts handles GET /api/v1/account/products
func (h *AccountHandler) GetProducts(c *gin.Context) {
	catalog, err := h.accountService.GetProductsCatalog(c.Request.Context())
	if err != nil {
		logger.GetLogger().Warn("Katalog produk tidak dapat diambil", map[string]interface{}{"error": err.Error()})
		response.Error(c, http.StatusServiceUnavailable, "Katalog produk belum dapat ditampilkan. Silakan coba kembali.", "SERVICE_UNAVAILABLE", nil)
		return
	}
	response.Success(c, "Katalog resmi produk perbankan DMB berhasil diambil", catalog)
}
