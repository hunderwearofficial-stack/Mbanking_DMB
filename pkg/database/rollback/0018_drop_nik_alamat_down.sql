-- Rollback 0018: Kembalikan kolom nik dan alamat pada tabel users
BEGIN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS nik text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS alamat text;
DELETE FROM schema_migrations WHERE version = 18;
COMMIT;
