-- 0022_account_number_encrypted.sql
-- Menyimpan nomor rekening dan CIF terenkripsi AES-256-GCM pada tabel users saat registrasi.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS account_number_encrypted TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cif_encrypted TEXT NOT NULL DEFAULT '';
