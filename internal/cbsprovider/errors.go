package cbsprovider

import "errors"

// Error kontrak yang dikembalikan seluruh implementasi CBSProvider.
var (
	ErrAccountNotFound     = errors.New("nomor rekening tidak ditemukan")
	ErrInvalidCredentials  = errors.New("nomor handphone, password, atau PIN salah")
	ErrInsufficientBalance = errors.New("saldo tidak mencukupi untuk melakukan transaksi")
	ErrInvalidPIN          = errors.New("PIN transaksi salah")
	ErrInactiveAccount     = errors.New("rekening sedang tidak aktif / terblokir")

	// ErrCBSUnavailable menandai data yang tidak dapat diambil dari Core Banking.
	// Provider TIDAK BOLEH menggantinya dengan data dummy (audit DMB-026 / DMB-035).
	ErrCBSUnavailable = errors.New("data Core Banking sedang tidak dapat diakses")

	// ErrCBSRejected marks a transfer definitively rejected by CBS (no funds moved).
	ErrCBSRejected = errors.New("transaksi ditolak oleh Core Banking")
	// ErrCBSOutcomeUnknown marks a transfer whose outcome cannot be determined
	// (timeout, transport error, malformed success response). Such transfers must be
	// reconciled with CBS and must NEVER be retried automatically (audit DMB-015).
	ErrCBSOutcomeUnknown = errors.New("status transaksi di Core Banking belum dapat dipastikan")
)
