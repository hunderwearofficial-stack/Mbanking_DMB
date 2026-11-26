package domain

import (
	"mbanking-bpr/pkg/money"
	"time"

	"mbanking-bpr/internal/model"
)

type Account = model.Account
type Mutation = model.Mutation

type BalanceResponse struct {
	AccountNumber    string       `json:"account_number"`
	HolderName       string       `json:"holder_name,omitempty"`
	ProductCode      string       `json:"product_code,omitempty"`
	AccountType      string       `json:"account_type"`
	Balance          money.Amount `json:"balance"`
	MinimumBalance   money.Amount `json:"minimum_balance"`
	BlockedBalance   money.Amount `json:"blocked_balance"`
	EffectiveBalance money.Amount `json:"effective_balance"`
	Status           string       `json:"status"`
	OpenedDate       string       `json:"opened_date,omitempty"`
	CBSRefID         string       `json:"cbs_ref_id,omitempty"`
	UpdatedAt        time.Time    `json:"updated_at"`
}

type MutationQueryParam struct {
	AccountNumber string `form:"account_number"`
	StartDate     string `form:"start_date"`
	EndDate       string `form:"end_date"`
	Limit         int    `form:"limit,default=20"`
}

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

type DMBNasabahData struct {
	CIF            string `json:"cif"`
	Nama           string `json:"nama"`
	NoHP           string `json:"nohp"`
	Email          string `json:"email"`
	KodePos        string `json:"kode_pos"`
	JenisKelamin   string `json:"jenis_kelamin"`
	Agama          string `json:"agama"`
	TglLahir       string `json:"tgl_lahir"`
	TempatLahir    string `json:"tempat_lahir"`
	NamaIbuKandung string `json:"nama_ibu_kandung"`
}
type CBSNasabahData = DMBNasabahData

type DMBSavingsAccountItem struct {
	NomorRekening            string       `json:"nomor_rekening"`
	Nama                     string       `json:"nama"`
	KodeProduk               string       `json:"kode_produk,omitempty"`
	NamaProduk               string       `json:"nama_produk,omitempty"`
	ProdukTabungan           string       `json:"produk_tabungan,omitempty"`
	StatusRekening           int          `json:"status_rekening,omitempty"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan,omitempty"`
	Saldo                    money.Amount `json:"saldo"`
}
type CBSSavingsAccountItem = DMBSavingsAccountItem

type DMBLoanAccountItem struct {
	NomorRekening            string       `json:"nomor_rekening"`
	KodeProduk               string       `json:"kode_produk"`
	NamaProduk               string       `json:"nama_produk"`
	StatusRekening           int          `json:"status_rekening"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan"`
	Plafon                   money.Amount `json:"plafon"`
	BakiDebet                money.Amount `json:"baki_debet"`
	Kolektibilitas           int          `json:"kolektibilitas"`
	KolektibilitasKeterangan string       `json:"kolektibilitas_keterangan"`
}

type DMBLoanAccountDetail struct {
	NomorRekening            string       `json:"nomor_rekening"`
	KodeProduk               string       `json:"kode_produk"`
	NamaProduk               string       `json:"nama_produk"`
	StatusRekening           int          `json:"status_rekening"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan"`
	Plafon                   money.Amount `json:"plafon"`
	BakiDebet                money.Amount `json:"baki_debet"`
	Kolektibilitas           int          `json:"kolektibilitas"`
	KolektibilitasKeterangan string       `json:"kolektibilitas_keterangan"`
	NomorPerjanjian          string       `json:"nomor_perjanjian"`
	Angsuran                 money.Amount `json:"angsuran"`
	JatuhTempoBerikutnya     string       `json:"jatuh_tempo_berikutnya"`
	JangkaWaktu              int          `json:"jangka_waktu"`
	SisaJangkaWaktu          int          `json:"sisa_jangka_waktu"`
	SatuanWaktu              string       `json:"satuan_waktu"`
	TanggalJatuhTempo        string       `json:"tanggal_jatuh_tempo"`
	SukuBungaTahunan         float64      `json:"suku_bunga_tahunan"`
	MetodeBunga              string       `json:"metode_bunga"`
	Agunan                   string       `json:"agunan"`
	SandiKantor              string       `json:"sandi_kantor"`
	NamaKantor               string       `json:"nama_kantor"`
}

type DMBDepositAccountItem struct {
	NomorRekening            string       `json:"nomor_rekening"`
	KodeProduk               string       `json:"kode_produk"`
	NamaProduk               string       `json:"nama_produk"`
	StatusRekening           int          `json:"status_rekening"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan"`
	Nominal                  money.Amount `json:"nominal"`
	SukuBungaTahunan         float64      `json:"suku_bunga_tahunan"`
	TanggalJatuhTempo        string       `json:"tanggal_jatuh_tempo"`
}

type DMBDepositAccountDetail struct {
	NomorRekening            string       `json:"nomor_rekening"`
	KodeProduk               string       `json:"kode_produk"`
	NamaProduk               string       `json:"nama_produk"`
	StatusRekening           int          `json:"status_rekening"`
	StatusRekeningKeterangan string       `json:"status_rekening_keterangan"`
	Nominal                  money.Amount `json:"nominal"`
	SukuBungaTahunan         float64      `json:"suku_bunga_tahunan"`
	TanggalJatuhTempo        string       `json:"tanggal_jatuh_tempo"`
	NomorBilyet              string       `json:"nomor_bilyet"`
	JangkaWaktuBulan         int          `json:"jangka_waktu_bulan"`
	TanggalBuka              string       `json:"tanggal_buka"`
	TanggalEfektif           string       `json:"tanggal_efektif"`
	ARO                      bool         `json:"aro"`
	JenisARO                 string       `json:"jenis_aro"`
	BungaBerjalan            money.Amount `json:"bunga_berjalan"`
	SaldoTertahan            money.Amount `json:"saldo_tertahan"`
	RekeningPencairanBunga   string       `json:"rekening_pencairan_bunga"`
	SandiKantor              string       `json:"sandi_kantor"`
	NamaKantor               string       `json:"nama_kantor"`
}

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

type CBSRegistrationCheckData struct {
	CIF       string `json:"cif"`
	NoHP      string `json:"nohp"`
	Terdaftar bool   `json:"terdaftar"`
}

type CBSRegistrationCompleteData struct {
	CIF       string `json:"cif"`
	Terdaftar bool   `json:"terdaftar"`
}
