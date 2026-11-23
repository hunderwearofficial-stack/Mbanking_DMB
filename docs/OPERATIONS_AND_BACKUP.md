# Operasional, Monitoring, Backup, dan Pemulihan

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Status | Mekanisme teknis tersedia sebagian (health check, audit verify, skrip backup/restore). **Belum ada** operasional berjalan: tidak ada server, backup terjadwal, alerting, maupun DRC |
| Keputusan bank yang diperlukan | RPO, RTO, jadwal & retensi backup, retensi log, lokasi DRC, kewajiban & tenggat pelaporan insiden |

## 1. Operasional backend

| Kegiatan | Cara | Status |
|---|---|---|
| Start/stop | systemd: `systemctl start|stop|restart mbanking-api`; Docker: `docker compose up -d` / `stop app` | Prosedur |
| Graceful shutdown | SIGTERM; request berjalan diberi waktu hingga 10 detik | IMPLEMENTED (`cmd/api/main.go`) |
| Restart otomatis | systemd `Restart=on-failure`; compose `restart` policy | IMPLEMENTED (konfigurasi) |
| Maintenance mode | Konsol admin (SUPER_ADMIN) → konfigurasi → `maintenance_mode` | IMPLEMENTED |
| Cek CBS | `GET /api/v1/admin/cbs/health` (SUPER_ADMIN) | IMPLEMENTED |

## 2. Monitoring dan health check

| Sinyal | Sumber | Rekomendasi ambang |
|---|---|---|
| Liveness | `GET /health` | probe 30–60 detik; alert bila gagal 3× |
| Readiness | `GET /ready` (database & Redis) | idem |
| Integritas audit | `cmd/auditverify` (exit 2 = rusak) | harian; exit 2 = insiden |
| Lonjakan 401/429 | log aplikasi/proxy | indikasi brute force |

Status: **NOT IMPLEMENTED** sebagai sistem monitoring/alerting — belum ada SIEM, dashboard, atau
on-call.

## 3. Log

* Aplikasi menulis log terstruktur ke stdout/stderr dengan `request_id`; data sensitif dimasking
  (`pkg/logger`).
* Lokasi: `journalctl -u mbanking-api` atau `docker compose logs app`.
* Rotasi: journald (`SystemMaxUse`, `MaxRetentionSec`) atau opsi `logging` Docker
  (`max-size`, `max-file`) — **belum dikonfigurasi**.
* Retensi dan pengiriman ke SIEM: **keputusan bank / BLOCKED**.

## 4. Backup database

| Aset | Perlu backup | Catatan |
|---|---|---|
| PostgreSQL aplikasi | Ya | kredensial (hash), binding perangkat, sesi, audit trail, notifikasi, pengajuan, serta tabel legacy fitur transfer yang sudah dihapus (`transfer_requests`, `transactions`, `saved_beneficiaries`) sampai diarsipkan. Saldo resmi tetap di CBS |
| Dokumen SK (PDF per versi), metadata versi, catatan persetujuan nasabah, revisi konten | Ya (berada di PostgreSQL: `stored_files`, `legal_*`, `mobile_content_revisions`) | Bukti hukum persetujuan; retensi mengikuti kebijakan bank (belum ditetapkan). PDF beralamat SHA-256 sehingga integritas dapat diperiksa setelah restore |
| Kunci `DB_ENCRYPTION_KEY` (+ `_PREVIOUS`) | Ya, **terpisah** dari backup data | tanpa kunci, data pribadi di backup tidak dapat dibaca |
| Secret lain (JWT, CBS, Redis, gateway) | Tidak wajib | dapat diterbitkan ulang |
| `web/admin/uploads` | Opsional | logo/banner |
| Redis | Tidak | OTP & rate limit sementara |

Skrip (diuji 13-11-2026 terhadap database uji: hasil backup tidak mengandung plaintext; restore ke
database kosong menghasilkan jumlah baris sama; restore ke database berisi ditolak; backup yang
dimodifikasi ditolak):

* `deploy/scripts/backup_postgres.sh` — `pg_dump -Fc` → enkripsi GPG (kunci publik penerima) →
  checksum SHA-256 → hapus backup lebih lama dari `BACKUP_RETENTION_DAYS` (default 30).
  Variabel wajib: `PGHOST`, `PGUSER`, `PGDATABASE`, `BACKUP_DIR`, `BACKUP_GPG_RECIPIENT`.
* `deploy/scripts/restore_postgres.sh` — verifikasi checksum, **menolak** database tujuan yang tidak
  kosong, meminta konfirmasi nama database.

| Persyaratan | Status |
|---|---|
| Enkripsi backup | IMPLEMENTED (skrip) |
| Penyimpanan terpisah dari server database | Prosedur — **BLOCKED** (storage bank) |
| Jadwal otomatis (cron/systemd timer) + pemantauan keberhasilan | **NOT IMPLEMENTED** |
| Retensi resmi | **Keputusan bank** (default skrip 30 hari bukan kebijakan) |
| WAL archiving / PITR | **NOT IMPLEMENTED** |
| Uji restore berkala | **NOT IMPLEMENTED** (baru satu kali uji teknis) |

## 5. Prosedur restore dan uji restore

1. Hentikan layanan (`systemctl stop mbanking-api` / `docker compose stop app`) agar tidak ada
   transaksi baru.
2. Restore ke database **baru/kosong** dengan `restore_postgres.sh`; siapkan kunci enkripsi yang sesuai.
3. Verifikasi: `cmd/auditverify` = "audit chain utuh"; `cmd/rekey` (dry run) = `decrypt_errors=0`;
   jumlah baris tabel utama sesuai. Integritas PDF SK: `SELECT count(*) FROM stored_files WHERE encode(sha256(content),'hex') <> sha256;` harus 0, dan `GET /api/v1/terms/active` mengembalikan versi yang sama seperti sebelum insiden.
4. Bila ada indikasi kompromi: cabut seluruh sesi (rotasi `JWT_SECRET` membatalkan semua token).
5. Alihkan aplikasi ke database hasil restore, buka layanan bertahap, catat hasil.

Uji restore dilakukan di lingkungan terisolasi dengan jadwal yang ditetapkan bank.

## 6. Disaster recovery

| Elemen | Status |
|---|---|
| RPO / RTO | **Belum ditetapkan** — keputusan bank |
| Lokasi DRC & prosedur failover | **Belum ada** |
| DRP tertulis dan uji DRP | **Belum ada** (dipersyaratkan dalam kerangka POJK 34/2025 — lihat [SECURITY_AND_OJK.md](SECURITY_AND_OJK.md)) |

## 7. Penanganan insiden

| Peran | Tanggung jawab |
|---|---|
| Pelapor | Melapor ke kanal resmi TI bank |
| Koordinator insiden (TI/Keamanan) | Klasifikasi, koordinasi, keputusan teknis |
| Pemilik sistem / Direksi | Penghentian layanan, komunikasi nasabah |
| Kepatuhan & Hukum | Kewajiban pelaporan ke OJK dan berdasarkan UU PDP (tenggat ditetapkan Kepatuhan) |
| Vendor CBS | Investigasi sisi core banking, rotasi kredensial CBS |

Alur: deteksi & catat (waktu, sumber, `request_id`) → klasifikasi (data/dana terdampak) →
penahanan → amankan bukti (log aplikasi, `audit_logs`, log proxy; catat hash file bukti; jangan
menghapus data) → pemulihan → pelaporan → review pasca-insiden.

| Skenario | Tindakan yang tersedia di sistem |
|---|---|
| Pengambilalihan akun nasabah | Konsol: blokir nasabah (`/admin/customers/:id/status`) dan reset perangkat (`reset-device`) |
| Akun petugas disalahgunakan | Nonaktifkan petugas (`/admin/users/:id/status`); tinjau `audit_logs` |
| Manipulasi audit trail | `auditverify` exit 2 → bekukan akses DB, amankan backup & log, investigasi dari `seq` yang dilaporkan |
| Brute force | Rate limit aktif; blokir IP di reverse proxy/WAF |

## 8. Kebocoran credential

1. Identifikasi secret yang terpapar dan cakupannya.
2. Rotasi segera di secret manager, lalu restart layanan:
   * `JWT_SECRET` / `ADMIN_JWT_SECRET` → seluruh token dan sesi batal (nasabah login ulang);
   * `DB_ENCRYPTION_KEY` → set kunci baru, kunci lama di `DB_ENCRYPTION_KEY_PREVIOUS`, jalankan
     `cmd/rekey` (dry run lalu eksekusi), hapus kunci lama setelah `decrypt_errors=0`;
   * password database/Redis → ubah role lalu environment;
   * `CBS_CLIENT_SECRET`, token gateway OTP, FCM key → minta penyedia menerbitkan ulang dan mencabut
     yang lama.
3. Tinjau `audit_logs` dan log akses selama periode paparan.
4. Bila secret masuk Git: rotasi tetap wajib; pembersihan riwayat Git dilakukan terpisah dengan
   persetujuan pemilik repository.

## 9. Gangguan CBS

| Gejala | Perilaku sistem | Tindakan operasional |
|---|---|---|
| CBS timeout/error | Saldo, mutasi, pinjaman, deposito, katalog → 503 "… belum dapat ditampilkan"; tidak ada data pengganti | Cek `/api/v1/admin/cbs/health`, jaringan keluar 443, kredensial; hubungi vendor CBS |
| Kepemilikan rekening tidak dapat diperiksa | Saldo/mutasi ditolak 503 (fail-closed) | idem |

## Device binding: operasional

* **Purge challenge** (role aplikasi tidak memiliki DELETE): jalankan terjadwal dengan role migrasi
  `migrate purge-challenges` (`DEVICE_CHALLENGE_RETENTION_DAYS`, default 30). Kunci perangkat tidak
  pernah dihapus; pencabutan adalah perubahan status yang tetap tercatat.
* **Daftar status attestation Google**: bila dipakai, perbarui file
  `DEVICE_ATTESTATION_ANDROID_REVOCATION_FILE` minimal harian lalu restart / rolling deploy backend.
* **Pembaruan root attestation**: ganti file PEM (gabungkan root lama + baru selama transisi), restart.
* **Pemantauan**: Backoffice → Nasabah & Perangkat → Kunci Keamanan Perangkat. Lonjakan
  *attestation gagal*, *tanda tangan ditolak*, atau *replay* adalah indikator serangan atau klien rusak;
  detail di Audit Trail (`DEVICE_ATTESTATION_FAILED`, `DEVICE_SIGNATURE_REJECTED`, `DEVICE_CHALLENGE_REPLAY`).
* **HP nasabah hilang / diganti**: petugas CS/SA → *Unbind Device* (mencabut kunci + seluruh sesi);
  nasabah mengikat ulang melalui Lupa Password (OTP).

### Rollback device binding

1. Rollback perilaku (tanpa database): `DEVICE_BINDING_MODE=off`, restart backend.
2. Rollback skema (hanya bersama redeploy rilis backend sebelumnya, dengan role migrasi, setelah backup):
   `psql -f pkg/database/rollback/0015_device_attestation_down.sql` (mencabut kunci App Attest,
   kolom dibiarkan), lalu bila perlu `0013_0014_device_key_binding_down.sql` (menghapus tabel kunci
   dan challenge — ekspor `device_keys` terlebih dahulu). Binding `users.device_id` tidak diubah.
   Prosedur ini diuji oleh `TestIntegration_DeviceBindingRollback` (rollback lalu migrate up ulang).
