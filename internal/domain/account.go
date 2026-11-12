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
	StartDate     string `form:"start_date"`
	EndDate       string `form:"end_date"`
	Limit         int    `form:"limit,default=20"`
}

// DMBHealthStatus represents response from Core Banking GET /ping
type DMBHealthStatus struct {
	Connected bool   `json:"connected"`
	Status    string `json:"status"`
	Code      int    `json:"code"`
	RefID     string `json:"ref_id"`
	Timestamp string `json:"timestamp"`
	Message   string `json:"message"`
	LatencyMs int64  `json:"latency_ms"`
}
type CBSHealthStatus = DMBHealthStatus

// DMBNasabahData represents customer data from Core Banking POST /api/nasabah
type DMBNasabahData struct {
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
type CBSNasabahData = DMBNasabahData

// DMBSavingsAccountItem represents savings account item from Core Banking POST /api/savings-accounts
type DMBSavingsAccountItem struct {
	NomorRekening           string  `json:"nomor_rekening"`
	Nama                    string  `json:"nama"`
	KodeProduk              string  `json:"kode_produk,omitempty"`
	NamaProduk              string  `json:"nama_produk,omitempty"`
	ProdukTabungan          string  `json:"produk_tabungan,omitempty"`
	StatusRekening          int     `json:"status_rekening,omitempty"`
	StatusRekeningKeterangan string `json:"status_rekening_keterangan,omitempty"`
	Saldo                   float64 `json:"saldo"`
}
type CBSSavingsAccountItem = DMBSavingsAccountItem

// DMBLoanAccountItem represents a loan account item from POST /api/loan-accounts
type DMBLoanAccountItem struct {
	NomorRekening           string `json:"nomor_rekening"`
	KodeProduk              string `json:"kode_produk"`
	NamaProduk              string `json:"nama_produk"`
	StatusRekening          int    `json:"status_rekening"`
	StatusRekeningKeterangan string `json:"status_rekening_keterangan"`
	Plafon                  int64  `json:"plafon"`
	BakiDebet               int64  `json:"baki_debet"`
	Kolektibilitas          int    `json:"kolektibilitas"`
	KolektibilitasKeterangan string `json:"kolektibilitas_keterangan"`
}

// DMBLoanAccountDetail represents detailed loan info from POST /api/loan-account-detail
type DMBLoanAccountDetail struct {
	NomorRekening           string  `json:"nomor_rekening"`
	KodeProduk              string  `json:"kode_produk"`
	NamaProduk              string  `json:"nama_produk"`
	StatusRekening          int     `json:"status_rekening"`
	StatusRekeningKeterangan string  `json:"status_rekening_keterangan"`
	Plafon                  int64   `json:"plafon"`
	BakiDebet               int64   `json:"baki_debet"`
	Kolektibilitas          int     `json:"kolektibilitas"`
	KolektibilitasKeterangan string  `json:"kolektibilitas_keterangan"`
	NomorPerjanjian         string  `json:"nomor_perjanjian"`
	Angsuran                int64   `json:"angsuran"`
	JatuhTempoBerikutnya    string  `json:"jatuh_tempo_berikutnya"`
	JangkaWaktu             int     `json:"jangka_waktu"`
	SisaJangkaWaktu         int     `json:"sisa_jangka_waktu"`
	SatuanWaktu             string  `json:"satuan_waktu"`
	TanggalJatuhTempo       string  `json:"tanggal_jatuh_tempo"`
	SukuBungaTahunan        float64 `json:"suku_bunga_tahunan"`
	MetodeBunga             string  `json:"metode_bunga"`
	Agunan                  string  `json:"agunan"`
	SandiKantor             string  `json:"sandi_kantor"`
	NamaKantor              string  `json:"nama_kantor"`
}

// DMBDepositAccountItem represents a deposit account item from POST /api/deposit-accounts
type DMBDepositAccountItem struct {
	NomorRekening           string  `json:"nomor_rekening"`
	KodeProduk              string  `json:"kode_produk"`
	NamaProduk              string  `json:"nama_produk"`
	StatusRekening          int     `json:"status_rekening"`
	StatusRekeningKeterangan string  `json:"status_rekening_keterangan"`
	Nominal                 int64   `json:"nominal"`
	SukuBungaTahunan        float64 `json:"suku_bunga_tahunan"`
	TanggalJatuhTempo       string  `json:"tanggal_jatuh_tempo"`
}

// DMBDepositAccountDetail represents detailed deposit info from POST /api/deposit-account-detail
type DMBDepositAccountDetail struct {
	NomorRekening           string  `json:"nomor_rekening"`
	KodeProduk              string  `json:"kode_produk"`
	NamaProduk              string  `json:"nama_produk"`
	StatusRekening          int     `json:"status_rekening"`
	StatusRekeningKeterangan string  `json:"status_rekening_keterangan"`
	Nominal                 int64   `json:"nominal"`
	SukuBungaTahunan        float64 `json:"suku_bunga_tahunan"`
	TanggalJatuhTempo       string  `json:"tanggal_jatuh_tempo"`
	NomorBilyet             string  `json:"nomor_bilyet"`
	JangkaWaktuBulan        int     `json:"jangka_waktu_bulan"`
	TanggalBuka             string  `json:"tanggal_buka"`
	TanggalEfektif          string  `json:"tanggal_efektif"`
	ARO                     bool    `json:"aro"`
	JenisARO                string  `json:"jenis_aro"`
	BungaBerjalan           int64   `json:"bunga_berjalan"`
	SaldoTertahan           int64   `json:"saldo_tertahan"`
	RekeningPencairanBunga  string  `json:"rekening_pencairan_bunga"`
	SandiKantor             string  `json:"sandi_kantor"`
	NamaKantor              string  `json:"nama_kantor"`
}

// DMBProductsCatalog represents product catalog from POST /api/products
type DMBProductsCatalog struct {
	Tabungan []DMBProductItem `json:"tabungan"`
	Kredit   []DMBProductItem `json:"kredit"`
	Deposito []DMBProductItem `json:"deposito"`
}

type DMBProductItem struct {
	KodeProduk string `json:"kode_produk"`
	NamaProduk string `json:"nama_produk"`
	Aktif      bool   `json:"aktif"`
}

