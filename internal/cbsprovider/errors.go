package cbsprovider

import "errors"

var (
	ErrAccountNotFound    = errors.New("nomor rekening tidak ditemukan")
	ErrInvalidCredentials = errors.New("nomor handphone, password, atau PIN salah")
	ErrInactiveAccount    = errors.New("rekening sedang tidak aktif / terblokir")

	ErrCBSUnavailable = errors.New("layanan perbankan sedang tidak dapat diakses")
)
