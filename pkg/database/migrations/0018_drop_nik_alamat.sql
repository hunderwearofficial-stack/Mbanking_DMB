-- Migration 0018: Drop NIK and Alamat columns from users table
-- Sesuai arahan: penghapusan total NIK dan Alamat dari database

ALTER TABLE users DROP COLUMN IF EXISTS nik;
ALTER TABLE users DROP COLUMN IF EXISTS alamat;
