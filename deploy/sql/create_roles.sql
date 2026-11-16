-- Pemisahan role database DMB Mobile Banking (dijalankan DBA dengan superuser).
--
--   mbanking_owner         pemilik skema; HANYA dipakai cmd/migrate (MIGRATION_DB_USER)
--   mbanking_app           role runtime aplikasi (DB_USER); bukan pemilik tabel
--   mbanking_audit_reader  baca-saja audit_logs (fungsi kepatuhan, cmd/auditverify)
--
-- Password diberikan sebagai variabel psql — tidak pernah ditulis di file ini:
--   psql -v owner_pass="..." -v app_pass="..." -v audit_pass="..." \
--        -v dbname=mbanking_prod -f deploy/sql/create_roles.sql
-- Setelah itu jalankan migrasi sebagai mbanking_owner:  go run ./cmd/migrate up
-- (migrasi 0004 memberi privilege minimum ke mbanking_app & mbanking_audit_reader).

\set ON_ERROR_STOP on

SELECT format('CREATE ROLE mbanking_owner LOGIN PASSWORD %L', :'owner_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_owner') \gexec
SELECT format('CREATE ROLE mbanking_app LOGIN PASSWORD %L', :'app_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') \gexec
SELECT format('CREATE ROLE mbanking_audit_reader LOGIN PASSWORD %L', :'audit_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') \gexec

-- Database dimiliki owner; role lain hanya CONNECT.
SELECT format('CREATE DATABASE %I OWNER mbanking_owner', :'dbname')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'dbname') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'dbname') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO mbanking_app, mbanking_audit_reader', :'dbname') \gexec

\connect :dbname
ALTER SCHEMA public OWNER TO mbanking_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO mbanking_app, mbanking_audit_reader;
