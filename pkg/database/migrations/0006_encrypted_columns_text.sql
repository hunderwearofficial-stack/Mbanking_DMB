-- 0006 alter encrypted columns in users to TEXT for AES-256-GCM ciphertexts
ALTER TABLE users ALTER COLUMN nik TYPE text;
ALTER TABLE users ALTER COLUMN email TYPE text;
ALTER TABLE users ALTER COLUMN alamat TYPE text;
ALTER TABLE users ALTER COLUMN tgl_lahir TYPE text;
ALTER TABLE users ALTER COLUMN tempat_lahir TYPE text;
ALTER TABLE users ALTER COLUMN nama_ibu_kandung TYPE text;

