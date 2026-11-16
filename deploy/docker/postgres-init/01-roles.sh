#!/bin/sh
# Dijalankan otomatis oleh image postgres saat volume database dibuat PERTAMA KALI.
# POSTGRES_USER (pemilik skema, dipakai cmd/migrate) dibuat oleh image.
# Script ini membuat role aplikasi & pembaca audit dengan password dari environment
# container (APP_DB_PASS, AUDIT_DB_PASS) — tidak ada password di file.
set -eu
: "${APP_DB_PASS:?APP_DB_PASS wajib diisi}"
: "${AUDIT_DB_PASS:?AUDIT_DB_PASS wajib diisi}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pass="$APP_DB_PASS" -v audit_pass="$AUDIT_DB_PASS" <<'SQL'
SELECT format('CREATE ROLE mbanking_app LOGIN PASSWORD %L', :'app_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') \gexec
SELECT format('CREATE ROLE mbanking_audit_reader LOGIN PASSWORD %L', :'audit_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO mbanking_app, mbanking_audit_reader', current_database()) \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO mbanking_app, mbanking_audit_reader;
SQL
