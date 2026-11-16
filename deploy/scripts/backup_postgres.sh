#!/usr/bin/env bash
# Backup PostgreSQL terenkripsi untuk DMB Mobile Banking.
#
# Wajib (environment, dari secret manager — tidak ada default):
#   PGHOST PGPORT PGUSER PGDATABASE  (+ PGPASSWORD atau ~/.pgpass)
#   BACKUP_DIR            direktori tujuan (storage terpisah dari server DB)
#   BACKUP_GPG_RECIPIENT  key id/email GPG publik penerima backup
# Opsional:
#   BACKUP_RETENTION_DAYS (default 30)
#
# Hasil: <BACKUP_DIR>/mbanking_<db>_<UTC>.dump.gpg + .sha256
# Status: FIXED BUT NOT VERIFIED — uji di staging dan sertakan uji restore berkala.
set -euo pipefail

: "${PGHOST:?PGHOST wajib diisi}" "${PGUSER:?PGUSER wajib diisi}" "${PGDATABASE:?PGDATABASE wajib diisi}"
: "${BACKUP_DIR:?BACKUP_DIR wajib diisi}" "${BACKUP_GPG_RECIPIENT:?BACKUP_GPG_RECIPIENT wajib diisi}"
RETENTION="${BACKUP_RETENTION_DAYS:-30}"
[[ "$RETENTION" =~ ^[0-9]+$ ]] || { echo "BACKUP_RETENTION_DAYS harus angka" >&2; exit 1; }

command -v pg_dump >/dev/null || { echo "pg_dump tidak ditemukan" >&2; exit 1; }
command -v gpg >/dev/null || { echo "gpg tidak ditemukan" >&2; exit 1; }

umask 077
mkdir -p "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/mbanking_${PGDATABASE}_${stamp}.dump.gpg"
tmp="$out.partial"

# Format custom (-Fc) agar dapat dipulihkan selektif; data tidak pernah tertulis plaintext ke disk.
pg_dump --format=custom --no-owner --no-privileges | gpg --batch --yes --encrypt --recipient "$BACKUP_GPG_RECIPIENT" --output "$tmp"
mv "$tmp" "$out"
sha256sum "$out" > "$out.sha256"

# Retensi
find "$BACKUP_DIR" -name 'mbanking_*.dump.gpg*' -type f -mtime +"$RETENTION" -delete

echo "Backup selesai: $out"
