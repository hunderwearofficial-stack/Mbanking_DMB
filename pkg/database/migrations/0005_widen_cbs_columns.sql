-- 0005 widen column lengths for live CBS synchronization
ALTER TABLE users ALTER COLUMN agama TYPE character varying(255);
ALTER TABLE users ALTER COLUMN jenis_kelamin TYPE character varying(50);
ALTER TABLE users ALTER COLUMN kode_pos TYPE character varying(50);

ALTER TABLE accounts ALTER COLUMN account_type TYPE character varying(255);
ALTER TABLE accounts ALTER COLUMN product_code TYPE character varying(50);

ALTER TABLE mutations ALTER COLUMN account_number TYPE character varying(100);
ALTER TABLE accounts ALTER COLUMN account_number TYPE character varying(100);
ALTER TABLE saved_beneficiaries ALTER COLUMN account_number TYPE character varying(100);
ALTER TABLE transactions ALTER COLUMN from_account TYPE character varying(100);
ALTER TABLE transactions ALTER COLUMN to_account TYPE character varying(100);
ALTER TABLE transfer_requests ALTER COLUMN from_account TYPE character varying(100);
ALTER TABLE transfer_requests ALTER COLUMN to_account TYPE character varying(100);

