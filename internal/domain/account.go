package domain

import (
	"time"

	"mbanking-bpr/internal/model"
)

type Account = model.Account
type Mutation = model.Mutation

type BalanceResponse struct {
	AccountNumber    string    `json:"account_number"`
	HolderName       string    `json:"holder_name,omitempty"`
	ProductCode      string    `json:"product_code,omitempty"`
	AccountType      string    `json:"account_type"`
	Balance          float64   `json:"balance"`
	MinimumBalance   float64   `json:"minimum_balance"`
	BlockedBalance   float64   `json:"blocked_balance"`
	EffectiveBalance float64   `json:"effective_balance"`
	Status           string    `json:"status"`
	CBSRefID         string    `json:"cbs_ref_id,omitempty"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type MutationQueryParam struct {
	AccountNumber string `form:"account_number"`
	Limit         int    `form:"limit,default=20"`
}

// CBSHealthStatus represents response from CBS GET /ping
type CBSHealthStatus struct {
	Connected bool   `json:"connected"`
	Status    string `json:"status"`
	Code      int    `json:"code"`
	RefID     string `json:"ref_id"`
	Timestamp string `json:"timestamp"`
	Message   string `json:"message"`
	LatencyMs int64  `json:"latency_ms"`
}

// CBSNasabahData represents customer data from CBS POST /api/nasabah
type CBSNasabahData struct {
	NIK            string `json:"nik"`
	CIF            string `json:"cif"`
	Nama           string `json:"nama"`
	NoHP           string `json:"nohp"`
	Email          string `json:"email"`
	Alamat         string `json:"alamat"`
	KodePos        string `json:"kode_pos"`
	JenisKelamin   string `json:"jenis_kelamin"`
	Agama          string `json:"agama"`
	TglLahir       string `json:"tgl_lahir"`
	TempatLahir    string `json:"tempat_lahir"`
	NamaIbuKandung string `json:"nama_ibu_kandung"`
}

// CBSSavingsAccountItem represents savings account item from CBS POST /api/savings-accounts
type CBSSavingsAccountItem struct {
	NomorRekening  string  `json:"nomor_rekening"`
	Nama           string  `json:"nama"`
	ProdukTabungan string  `json:"produk_tabungan"`
	Saldo          float64 `json:"saldo"`
}

