# Konfigurasi Environment: Local, Development, Staging, Production

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Status | Loader konfigurasi **IMPLEMENTED** dan diuji (`config/config_test.go`). Server development/staging/production **belum tersedia** |
| Sumber kebenaran | `config/config.go`, `cmd/migrate/main.go`, `.env.example`, `m_banking_bpr/lib/core/config/app_environment.dart` |

## 1. Prinsip

* Hanya ada **satu** template: `.env.example`. Hanya ada **satu** file konfigurasi lokal: `.env`
  (tidak masuk Git). Tidak ada `.env.local`, `.env.staging`, dan sejenisnya.
* `.env` hanya dibaca bila `APP_ENV=local`. Bila `APP_ENV` lain dan file `.env` ada di working
  directory, backend **menolak start** — mencegah konfigurasi local terbawa ke server.
* Development, staging, dan production membaca konfigurasi dari **environment proses** (systemd
  `EnvironmentFile`, variabel Docker Compose) yang diisi dari **secret manager** atau file di luar
  repository (`/etc/mbanking/*.env`, milik root, permission 0600).
* Nilai di environment proses mengalahkan `.env`.
* Konfigurasi wajib tidak memiliki nilai bawaan; nilai kosong atau format salah menghentikan
  startup dengan daftar kesalahan. Nilai secret tidak pernah dicetak.
* Periksa konfigurasi kapan saja: `go run ./cmd/api -check-config`.
* Aplikasi Flutter **tidak pernah** menyimpan secret backend, kredensial database, kunci JWT,
  atau kunci enkripsi.

## 2. Pemisahan environment

| Aspek | LOCAL | DEVELOPMENT | STAGING | PRODUCTION |
|---|---|---|---|---|
| Lokasi | Komputer developer | Server pengembangan | Pra-produksi | Infrastruktur resmi bank |
| Sumber konfigurasi backend | `.env` | environment server | environment server / secret manager | secret manager |
| Database | `mbanking_local` (Docker, 127.0.0.1:5433) | database dev tersendiri | database staging tersendiri | database production |
| Credential | acak, khusus local | terpisah | terpisah | terpisah; tidak pernah dipakai di environment lain |
| Core banking | ledger local (`ENABLE_MOCK_CBS=true`) | CBS dev resmi (ledger local diizinkan) | CBS resmi; mock **ditolak** | CBS resmi; mock **ditolak** |
| Redis | memori (kosong) | disarankan | **wajib** | **wajib** |
| OTP | SANDBOX (kode di konsol) | SANDBOX diizinkan | gateway wajib (SANDBOX ditolak) | gateway wajib |
| Transport aplikasi | HTTP ke IP LAN, build debug saja | HTTPS | HTTPS + pin sertifikat | HTTPS + pin sertifikat wajib |
| `DB_SSL` | `disable` | `require` / `verify-full` | `verify-full` | `verify-full` |
| Status | Tersedia | **BLOCKED** (server belum ada) | **BLOCKED** | **BLOCKED** |

Aturan staging = production untuk keamanan (`Config.IsProductionLike()`).

## 3. Variabel backend (`cmd/api`)

Kolom environment: L = local, D = development, S = staging, P = production.
"Secret" berarti nilai hanya boleh berasal dari `.env` (local) atau secret manager (server).

| Variabel | Fungsi | Wajib | Format | L/D/S/P | Pengisian aman |
|---|---|---|---|---|---|
| `APP_ENV` | Nama environment | Ya | `local`/`development`/`staging`/`production` | semua | local di `.env`; server di environment |
| `APP_HOST` | Alamat bind HTTP | Tidak | IP; kosong = semua antarmuka | semua | local kosong (HP di LAN); server `127.0.0.1` di balik reverse proxy |
| `APP_PORT` | Port HTTP | Tidak (8080) | 1–65535 | semua | — |
| `APP_NAME` | Nama aplikasi di log | Tidak | teks | semua | — |
| `APP_VERSION` | Versi rilis (jejak audit rilis) | **Wajib di S/P** (L/D: `unversioned`) | teks | semua | tag rilis dari pipeline |
| `DB_HOST` | Host PostgreSQL | Ya | host/IP | semua | — |
| `DB_PORT` | Port PostgreSQL | Tidak (5432) | 1–65535 | semua | local `5433` |
| `DB_NAME` | Nama database | Ya | teks | semua | local `mbanking_local` |
| `DB_USER` | Role aplikasi | Ya | teks | semua | `mbanking_app` (bukan pemilik tabel) |
| `DB_PASS` | Password role aplikasi | Wajib di S/P (local: wajib untuk compose) | secret | semua | acak, per environment |
| `DB_SSL` | Mode TLS database | Ya | `disable`/`require`/`verify-ca`/`verify-full` | semua | server minimal `require`, disarankan `verify-full` |
| `DB_MAX_OPEN_CONNS` / `DB_MAX_IDLE_CONNS` | Pool koneksi | Tidak (25 / 10) | angka | semua | — |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_DB` | Redis (OTP, rate limit) | Wajib di S/P | host; 1–65535; 0–15 | S/P (opsional L/D) | local kosong = memori |
| `REDIS_PASS` | Password Redis | **Wajib di S/P** | secret | S/P | secret manager |
| `JWT_SECRET` | Kunci token nasabah | Ya | ≥ 32 karakter, berbeda dari kunci admin | semua | acak 64 hex |
| `JWT_EXPIRY_MINUTES` | Masa berlaku access token nasabah | Tidak (15) | 1–60 | semua | — |
| `REFRESH_TOKEN_DAYS` | Masa berlaku refresh token | Tidak (7) | 1–30 | semua | — |
| `ADMIN_JWT_SECRET` | Kunci token petugas | Ya | ≥ 32 karakter | semua | acak 64 hex |
| `ADMIN_JWT_EXPIRY_MINUTES` | Masa berlaku token petugas | Tidak (60) | 1–480 | semua | — |
| `ADMIN_BOOTSTRAP_USERNAME` / `_PASSWORD` | Membuat SUPER_ADMIN pertama bila belum ada | Tidak | password ≥ 12 karakter | semua | isi sekali, lalu hapus dari environment |
| `DB_ENCRYPTION_KEY` | Kunci AES-256-GCM data pribadi | Ya | 64 hex atau base64 32 byte | semua | secret manager; backup kunci terpisah dari backup data |
| `DB_ENCRYPTION_KEY_PREVIOUS` | Kunci lama (decrypt-only) saat rotasi | Tidak | idem | semua | hanya selama rotasi (`cmd/rekey`) |
| `TRUSTED_PROXIES` | Proxy yang dipercaya untuk `X-Forwarded-For` | Tidak | daftar IP/CIDR dipisah koma | S/P | alamat reverse proxy |
| `CORS_ALLOWED_ORIGINS` | Origin lintas domain yang diizinkan | Tidak (tidak ada) | daftar URL | — | biarkan kosong bila konsol same-origin |
| `ENABLE_MOCK_CBS` | Memakai ledger PostgreSQL local sebagai pengganti CBS | Tidak (false) | `true`/`false` | L/D saja; **ditolak** di S/P | — |
| `CBS_BASE_URL` | Alamat CBS OpenAPI | Ya bila mock tidak aktif | `https://…` | D/S/P | — |
| `CBS_CLIENT_ID` | Client ID CBS | Ya bila `CBS_BASE_URL` diisi | teks | D/S/P | — |
| `CBS_CLIENT_SECRET` | Secret OAuth + kunci HMAC signature CBS | Ya bila `CBS_BASE_URL` diisi | secret | D/S/P | secret manager; rotasi via vendor CBS |
| `CBS_TIMEOUT_SEC` | Timeout per panggilan CBS | Tidak (15) | 1–60 | semua | — |
| `STANDALONE_CORE` | Dinonaktifkan | — | — | **ditolak di semua environment** | jangan diisi (startup gagal) |

### Variabel tambahan di luar `cmd/api`

| Variabel | Dipakai oleh | Fungsi |
|---|---|---|
| `MIGRATION_DB_USER` / `MIGRATION_DB_PASS` | `cmd/migrate`, `docker-compose.local.yml` | Role pemilik skema (DDL); berbeda dari `DB_USER` |
| `AUDIT_DB_PASS` | compose local & server | Password role `mbanking_audit_reader` |
| `DB_OWNER_USER` / `DB_OWNER_PASS` / `APP_DB_PASS` | `docker-compose.yml` (server) | Role pemilik skema dan role aplikasi di compose server |
| `DMB_IT_DB_*` | `test/integration` | Database uji sekali pakai (nama wajib berakhiran `_test`) |
| `PGHOST` … `BACKUP_DIR`, `BACKUP_GPG_RECIPIENT`, `BACKUP_RETENTION_DAYS` | `deploy/scripts/backup_postgres.sh` | Backup terenkripsi (lihat [OPERATIONS_AND_BACKUP.md](OPERATIONS_AND_BACKUP.md)) |

### Konfigurasi yang disimpan di database (konsol admin, SUPER_ADMIN)

Tabel `app_configs` (default dari migrasi `0003_default_app_config.sql`): mode maintenance,
`enforce_device_binding`, batas gagal login, penyedia OTP (`SANDBOX`/`FONNTE`/`WABLAS`/webhook),
token gateway OTP, dan FCM server key. Token dan key bersifat write-only (tidak dikirim kembali ke
konsol atau aplikasi).

Syarat dan Ketentuan, PDF, persetujuan nasabah, dan revisi konten aplikasi disimpan di database dan
dikelola melalui backoffice — **tidak ada variabel environment baru** untuk fitur ini (tidak ada
path penyimpanan, URL bertanda tangan, atau secret tambahan).

Variabel yang **tidak didukung** (jangan ditambahkan): `LOG_LEVEL`, `LOG_FORMAT`, `FCM_*`,
`RATE_LIMIT_*`.

## 4. Konfigurasi aplikasi Flutter (build time)

| Define | Fungsi | Aturan |
|---|---|---|
| `APP_FLAVOR` | `local` / `development` / `staging` / `production` | wajib; dari `config/<flavor>.json` |
| `API_BASE_URL` | Alamat backend | wajib; local: `http://<IP-LAN>:8080` (debug saja, bukan localhost); lainnya: `https://` |
| `API_CERT_PINS` | SHA-256 sertifikat leaf (aktif + cadangan, dipisah koma) | wajib untuk build rilis production; disarankan staging |

File: `m_banking_bpr/config/local.json`, `development.json`, `staging.json`, `production.json`
(hanya URL publik dan pin, tanpa secret). Domain development/staging/production belum ada, sehingga
nilainya sengaja kosong — build dengan nilai kosong menampilkan layar **"Konfigurasi aplikasi
tidak valid"** dan tidak pernah memakai server lain secara diam-diam.

```powershell
cd m_banking_bpr
flutter run --debug --dart-define-from-file=config/local.json --dart-define=API_BASE_URL=http://<IP-LAN>:8080
flutter build appbundle --release --dart-define-from-file=config/production.json --obfuscate --split-debug-info=build/symbols
```

## 5. Menjalankan per environment

| Environment | Cara |
|---|---|
| Local | `.\scripts\local\run-api.ps1` (membaca `.env`) — lihat [LOCAL_SETUP.md](LOCAL_SETUP.md) |
| Development / staging / production | binary `server` + environment dari secret manager, melalui systemd atau Docker Compose — lihat [DEPLOYMENT_AND_CICD.md](DEPLOYMENT_AND_CICD.md). Tidak ada file `.env` di direktori kerja |

## 6. Memperbarui `.env` lama

`.env` versi lama (mis. `APP_ENV=development`, database `mbanking_bpr` di port 5432, tanpa
`ADMIN_JWT_SECRET`/`DB_ENCRYPTION_KEY`) ditolak backend dengan pesan
`file .env ditemukan tetapi APP_ENV=development`. Simpan cadangan (`Copy-Item .env .env.backup-lama`)
lalu buat `.env` baru dari `.env.example` ([LOCAL_SETUP.md](LOCAL_SETUP.md) §3). Database lama
`mbanking_bpr` tidak dipakai untuk pengujian local.

## 7. Device binding & attestation

Di **staging/production** semua nilai bertanda * wajib diisi eksplisit; backend menolak start bila
kosong atau tidak valid (tidak ada default keamanan). Default hanya berlaku untuk local/development/test.

| Variabel | Nilai | Default (non-production) |
|---|---|---|
| `DEVICE_BINDING_MODE` * | `off` / `dual` / `enforced` | `dual` |
| `DEVICE_ATTESTATION_MODE` * | `off` / `observe` / `enforce` | `observe` |
| `DEVICE_ATTESTATION_ANDROID_REQUIRE_VERIFIED_BOOT` * | `true` / `false` | `true` |
| `DEVICE_ATTESTATION_ANDROID_ROOTS_FILE` | path PEM root attestation Google (wajib bila attestation bukan off di production) | — |
| `DEVICE_ATTESTATION_ANDROID_REVOCATION_FILE` | path JSON daftar status attestation Google (opsional, diperbarui berkala) | — |
| `DEVICE_ATTESTATION_ANDROID_PACKAGE` | applicationId resmi (bukan `com.example…`) | — |
| `DEVICE_ATTESTATION_ANDROID_CERT_SHA256` | SHA-256 sertifikat app signing resmi (hex, boleh dengan `:`; beberapa nilai dipisah koma) | — |
| `DEVICE_ATTESTATION_APPLE_ROOT_FILE` | path PEM Apple App Attestation Root CA | — |
| `DEVICE_ATTESTATION_APPLE_APP_ID` | `<TeamID>.<bundleID>` resmi | — |
| `DEVICE_ATTESTATION_APPLE_ENVIRONMENT` | `production` (wajib di production) / `development` | `production` |
| `DEVICE_CHALLENGE_RETENTION_DAYS` | retensi `migrate purge-challenges` (1–3650) | 30 |
| `DEVICE_BINDING_OFF_REASON` | wajib di staging/production bila binding atau attestation `off` (min. 10 karakter, mis. nomor tiket) | — |
| `DEVICE_BINDING_OFF_UNTIL` | wajib bersama alasan di atas: RFC3339, di masa depan, maks. 72 jam; setelahnya binding kembali `dual` | — |

File root **tidak** disertakan di repository dan tidak boleh diketik ulang dari ingatan: unduh dari
sumber resmi, verifikasi fingerprint bersama tim keamanan bank, simpan read-only di server. File yang
tidak dapat dibaca/diparse menghentikan start backend (fail-closed).

### Kontrol tambahan (mitigasi risiko residual)

| Variabel | Nilai | Default (non-production) |
|---|---|---|
| `JWT_EXPIRY_MINUTES` | Di staging/production maksimal 10 menit (masa pakai token akses yang dicuri) | 15 |
