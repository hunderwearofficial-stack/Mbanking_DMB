package http

import (
	"errors"
	"net/http"
	"strconv"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/account/service"
	"mbanking-bpr/pkg/logger"
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

func caller(c *gin.Context) service.Caller {
	return service.Caller{
		UserID:       c.GetString(middleware.CtxUserID),
		CIF:          c.GetString(middleware.CtxCIF),
		TokenAccount: c.GetString(middleware.CtxAccountNo),
	}
}

func respondErr(c *gin.Context, err error, notFoundMsg, unavailableMsg string) {
	switch {
	case errors.Is(err, service.ErrInvalidQuery):
		response.BadRequest(c, err.Error(), nil)
	case errors.Is(err, service.ErrForbidden):
		response.Error(c, http.StatusForbidden, "Rekening tidak terdaftar atas nama Anda", "01", nil)
	case errors.Is(err, cbsprovider.ErrAccountNotFound):
		response.NotFound(c, notFoundMsg)
	default:
		logger.GetLogger().Warn("Data rekening tidak dapat diambil", map[string]interface{}{"path": c.FullPath(), "error": err.Error()})
		response.Error(c, http.StatusServiceUnavailable, unavailableMsg, "SERVICE_UNAVAILABLE", nil)
	}
}

func (h *AccountHandler) GetBalance(c *gin.Context) {
	res, err := h.accountService.GetBalance(c.Request.Context(), caller(c), c.Query("account_number"))
	if err != nil {
		respondErr(c, err, "Data saldo rekening tidak ditemukan", "Saldo belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Informasi saldo berhasil dimuat", res)
}

func (h *AccountHandler) GetMutations(c *gin.Context) {
	var query domain.MutationQueryParam
	if err := c.ShouldBindQuery(&query); err != nil {
		response.BadRequest(c, "Parameter pencarian riwayat mutasi tidak valid", nil)
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

func (h *AccountHandler) GetCustomerProfile(c *gin.Context) {
	data, err := h.accountService.GetCustomerProfile(c.Request.Context(), caller(c))
	if err != nil {
		respondErr(c, err, "Data profil nasabah tidak ditemukan", "Data profil belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Data profil nasabah Bank DMB berhasil diambil", data)
}

func (h *AccountHandler) GetSavingsAccounts(c *gin.Context) {
	cl := caller(c)
	items, err := h.accountService.GetSavingsAccounts(c.Request.Context(), cl)
	if err != nil {
		respondErr(c, err, "Daftar rekening tidak ditemukan", "Daftar rekening belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Daftar rekening tabungan Bank DMB berhasil diambil", gin.H{
		"cif_number":     cl.CIF,
		"total_accounts": len(items),
		"accounts":       items,
	})
}

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

func (h *AccountHandler) GetLoanDetail(c *gin.Context) {
	detail, err := h.accountService.GetLoanDetail(c.Request.Context(), caller(c), accountParam(c))
	if err != nil {
		respondErr(c, err, "Rincian pinjaman tidak ditemukan", "Rincian pinjaman belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Rincian pinjaman berhasil diambil", detail)
}

func parseMutationLimit(c *gin.Context) int {
	limit, err := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if err != nil || limit <= 0 {
		return 20
	}
	if limit > 50 {
		return 50
	}
	return limit
}

func (h *AccountHandler) GetLoanMutations(c *gin.Context) {
	accountNo := accountParam(c)
	muts, err := h.accountService.GetLoanMutations(c.Request.Context(), caller(c), accountNo, c.Query("start_date"), c.Query("end_date"), parseMutationLimit(c))
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

func (h *AccountHandler) GetDepositDetail(c *gin.Context) {
	detail, err := h.accountService.GetDepositDetail(c.Request.Context(), caller(c), accountParam(c))
	if err != nil {
		respondErr(c, err, "Rincian deposito tidak ditemukan", "Rincian deposito belum dapat ditampilkan. Silakan coba kembali.")
		return
	}
	response.Success(c, "Rincian bilyet deposito berhasil diambil", detail)
}

func (h *AccountHandler) GetDepositMutations(c *gin.Context) {
	accountNo := accountParam(c)
	muts, err := h.accountService.GetDepositMutations(c.Request.Context(), caller(c), accountNo, c.Query("start_date"), c.Query("end_date"), parseMutationLimit(c))
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

func (h *AccountHandler) GetProducts(c *gin.Context) {
	catalog, err := h.accountService.GetProductsCatalog(c.Request.Context())
	if err != nil {
		logger.GetLogger().Warn("Katalog produk tidak dapat diambil", map[string]interface{}{"error": err.Error()})
		response.Error(c, http.StatusServiceUnavailable, "Katalog produk belum dapat ditampilkan. Silakan coba kembali.", "SERVICE_UNAVAILABLE", nil)
		return
	}
	response.Success(c, "Katalog resmi produk perbankan DMB berhasil diambil", catalog)
}
