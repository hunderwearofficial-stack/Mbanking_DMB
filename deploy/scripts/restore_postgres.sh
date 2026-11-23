#!/usr/bin/env bash
# Restore backup PostgreSQL DMB Mobile Banking ke database TUJUAN yang KOSONG.
#
# Pemakaian:  restore_postgres.sh <file.dump.gpg>
# Wajib: PGHOST PGPORT PGUSER PGDATABASE (+ PGPASSWORD/.pgpass), kunci privat GPG penerima.
#
# Pengaman:
#   - menolak bila checksum .sha256 tidak cocok;
#   - menolak bila database tujuan sudah berisi tabel (tidak pernah menimpa data);
#   - wajib konfirmasi ketik nama database.
# Setelah restore jalankan: go run ./cmd/auditverify  dan  go run ./cmd/rekey (dry run).
set -euo pipefail

file="${1:?pemakaian: restore_postgres.sh <file.dump.gpg>}"
: "${PGHOST:?PGHOST wajib diisi}" "${PGUSER:?PGUSER wajib diisi}" "${PGDATABASE:?PGDATABASE wajib diisi}"
[[ -f "$file" && -f "$file.sha256" ]] || { echo "file backup atau checksum tidak ditemukan" >&2; exit 1; }

sha256sum --check --status "$file.sha256" || { echo "checksum TIDAK cocok — backup rusak/termanipulasi" >&2; exit 1; }

tables="$(psql -At -c "select count(*) from information_schema.tables where table_schema='public'")"
if [[ "$tables" != "0" ]]; then
  echo "Database $PGDATABASE tidak kosong ($tables tabel). Restore dibatalkan." >&2
  exit 1
fi

read -r -p "Ketik nama database tujuan ($PGDATABASE) untuk melanjutkan: " confirm
[[ "$confirm" == "$PGDATABASE" ]] || { echo "dibatalkan" >&2; exit 1; }

gpg --batch --decrypt "$file" | pg_restore --no-owner --no-privileges --exit-on-error --dbname="$PGDATABASE"
echo "Restore selesai. Lanjutkan verifikasi audit chain & enkripsi sebelum membuka layanan."
