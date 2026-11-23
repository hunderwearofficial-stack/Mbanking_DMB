# Instalasi Server dan CI/CD

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Status deployment | **Belum pernah di-deploy** ke development, staging, maupun production. Aplikasi **belum siap production** (§6) |
| Status CI/CD | `.gitlab-ci.yml` ada, tetapi **tidak berjalan** (repository remote di GitHub) — **NOT IMPLEMENTED** sebagai pipeline aktif |
| Artefak deployment | `Dockerfile`, `docker-compose.yml`, `deploy/sql/create_roles.sql`, `deploy/systemd/mbanking-api.service`, `deploy/nginx/mbanking.conf.example`, `deploy/scripts/*.sh` |

Semua `<…>` diganti nilai resmi saat pelaksanaan. Jangan menulis secret di dokumen, repository,
atau tiket.

## 1. Persiapan server

### Spesifikasi (rekomendasi awal, belum diukur dengan uji beban)

| Komponen | Rekomendasi | Catatan |
|---|---|---|
| Server aplikasi | 2 vCPU, 4 GB RAM, 40 GB SSD | Lokasi pusat data sesuai ketentuan bank |
| Server database | 2 vCPU, 4 GB RAM, 100 GB SSD + storage backup terpisah | Disarankan terpisah dari server aplikasi |
| OS | Linux server LTS dengan dukungan patch keamanan (mis. Ubuntu Server 24.04 LTS) | NTP aktif, zona waktu Asia/Jakarta |
| Perangkat lunak | Docker Engine + Compose v2, **atau** PostgreSQL 16 + Redis 7 + nginx | Go hanya di mesin build |

Kapasitas final ditetapkan setelah uji beban (**belum dilakukan**).

### Akun, SSH, dan direktori

```bash
sudo useradd --system --home /opt/mbanking --shell /usr/sbin/nologin mbanking   # user khusus aplikasi
sudo install -d -o root -g root -m 755 /opt/mbanking
sudo install -d -m 700 /etc/mbanking                                           # konfigurasi/secret
sudo install -d -o mbanking -g mbanking /opt/mbanking/web/admin/uploads        # satu-satunya direktori tulis
```

SSH: login root dimatikan (`PermitRootLogin no`), autentikasi kunci saja
(`PasswordAuthentication no`), akses hanya dari IP admin/VPN bank, akun admin bernama per orang.

### Firewall dan jaringan

| Port | Arah | Sumber/tujuan |
|---|---|---|
| 443/tcp | masuk | internet (nginx) |
| 80/tcp | masuk | redirect ke 443 |
| 22/tcp | masuk | IP admin/VPN bank saja |
| 8080/tcp | lokal | 127.0.0.1 saja (backend di balik nginx) |
| 5432/tcp, 6379/tcp | privat | dari server aplikasi saja |
| 443/tcp | keluar | CBS, gateway OTP, FCM |

`/admin` dan `/api/v1/admin` dibatasi ke IP kantor/VPN di nginx. Satu subdomain resmi per
environment; sertifikat TLS dari CA tepercaya; catat SHA-256 sertifikat leaf **aktif dan cadangan**
untuk pinning aplikasi.

### Secret

Secret disimpan di secret manager bank dan di-inject saat runtime ke
`/etc/mbanking/mbanking.env` (systemd) atau `/etc/mbanking/compose.env` (Docker) — milik root,
permission 0600, di luar repository. Credential **berbeda per environment**. Daftar variabel:
[ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md).

**Wajib dirotasi sebelum production** (pernah terpapar di repository publik): CBS client secret
(diterbitkan ulang vendor), `JWT_SECRET`/`ADMIN_JWT_SECRET`, kunci enkripsi database (`cmd/rekey`),
password PostgreSQL, akun admin bawaan, token gateway OTP, dan FCM server key.

## 2. Database

```bash
# DBA (superuser) membuat role; password diberikan sebagai variabel psql, tidak ditulis ke file
psql -v owner_pass="..." -v app_pass="..." -v audit_pass="..." -v dbname=<nama_db> \
     -f deploy/sql/create_roles.sql
```

Migration dijalankan **sebagai job terpisah** dengan role pemilik skema, **setelah backup**:

```bash
./migrate status
./migrate up        # environment: APP_ENV, DB_HOST, DB_NAME, DB_SSL, DB_ENCRYPTION_KEY, MIGRATION_DB_USER, MIGRATION_DB_PASS
```

Migrasi bersifat additive dan tidak memiliki *down*. Migrasi yang menghapus/mengubah data
memerlukan backup terverifikasi dan persetujuan tertulis.

## 3. Instalasi backend

### Opsi A — Docker Compose (`docker-compose.yml`)

Berisi PostgreSQL, Redis (berpassword), job `migrate`, dan `app` (role `mbanking_app`); port
terikat 127.0.0.1; healthcheck; batas resource; container non-root.

```bash
git clone <URL-REPO-RESMI> /opt/mbanking && cd /opt/mbanking && git checkout <tag-rilis>
sudo install -m 600 /dev/null /etc/mbanking/compose.env     # isi dari secret manager
sudo docker compose --env-file /etc/mbanking/compose.env config -q
sudo docker compose --env-file /etc/mbanking/compose.env up -d --build
curl -fsS http://127.0.0.1:8080/health && curl -fsS http://127.0.0.1:8080/ready
```

### Opsi B — systemd (`deploy/systemd/mbanking-api.service`)

```bash
# Mesin build
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o server ./cmd/api
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o migrate ./cmd/migrate
sha256sum server migrate > SHA256SUMS
# Server
sudo install -m 755 server migrate /opt/mbanking/ && sudo cp -r web /opt/mbanking/
sudo install -m 600 /dev/null /etc/mbanking/mbanking.env    # isi dari secret manager; APP_HOST=127.0.0.1
sudo cp deploy/systemd/mbanking-api.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now mbanking-api
```

Unit systemd: berjalan sebagai `mbanking`, `Restart=on-failure` (5 detik, maks. 5× per 120 detik),
`SIGTERM` + `TimeoutStopSec=20s` (graceful shutdown), `NoNewPrivileges`, `ProtectSystem=strict`.
Log: `journalctl -u mbanking-api` (data sensitif dimasking aplikasi).

### Reverse proxy

`deploy/nginx/mbanking.conf.example` → `/etc/nginx/conf.d/mbanking.conf` (ganti `<DOMAIN-API>` dan
path sertifikat). Isi `TRUSTED_PROXIES` dengan alamat nginx yang terlihat oleh backend.

### Health check

`GET /health` (proses hidup) dan `GET /ready` (database & Redis). Startup gagal bila konfigurasi
tidak valid atau skema belum sesuai migrasi.

## 4. Aplikasi Flutter (Android)

| Aspek | Kondisi | Status |
|---|---|---|
| Release build | `flutter build appbundle --release --dart-define-from-file=config/production.json --obfuscate --split-debug-info=build/symbols` | Gagal tanpa konfigurasi resmi (sengaja) |
| Signing | Wajib `android/key.properties` + keystore rilis bank (tidak pernah di repository; di CI dari secret store) | **BLOCKED** |
| `applicationId` | Masih `com.example.m_banking_bpr` | **BLOCKED** (keputusan bank) |
| Versioning | `version:` di `pubspec.yaml` (`name+buildNumber`), dinaikkan setiap rilis | Prosedur |
| Artefak | AAB/APK + `build/symbols` (disimpan di penyimpanan terlindungi untuk membaca crash) + checksum | Prosedur |
| Distribusi | Google Play Console atas nama bank | **BLOCKED** |
| Firebase | Konfigurasi saat ini dari proyek pengembangan; backend memakai FCM legacy | **BLOCKED** |
| iOS | Belum disiapkan (signing, konfigurasi, pengujian) | **NOT IMPLEMENTED** |

## 5. CI/CD

### Kondisi aktual

`.gitlab-ci.yml` mendefinisikan: `secret-scan` (gitleaks) → `backend-test` (`go vet`, `go test`,
`govulncheck`) → `build-apk-release` (manual/tag) → `deploy-backend-to-vps` (manual, SSH dengan
host key terverifikasi). Repository remote berada di GitHub sehingga pipeline ini **tidak pernah
berjalan**. Selain itu: job build APK belum memakai `--dart-define-from-file=config/production.json`,
job deploy memakai `docker compose` tanpa `--env-file` dan tanpa langkah backup sebelum migrasi,
serta belum ada environment development/staging.

### Rancangan pipeline yang aman (belum diimplementasikan)

| No | Tahap | Kontrol |
|---|---|---|
| 1 | Developer membuat perubahan di branch | Tidak ada commit langsung ke `main` |
| 2 | Pull request | Branch protection; template PR (risiko, migrasi, rollback) |
| 3 | Code review | Minimal 1 reviewer selain penulis; perubahan keamanan oleh reviewer senior |
| 4 | Automated tests | `go build`, `go vet`, `go test ./...`, integration test (DB uji sekali pakai), `flutter analyze`, `flutter test` |
| 5 | Static analysis | `gofmt -l`, `go vet`, `flutter analyze` (tanpa error/warning) |
| 6 | Dependency/security scanning | `govulncheck`, `gitleaks`, audit dependensi Flutter |
| 7 | Build artifact | Image container/binary dan AAB **sekali build**, diberi tag versi + checksum; tidak di-build ulang antar environment |
| 8 | Approval | Persetujuan pemilik sistem untuk deploy |
| 9 | Deploy Development | Otomatis setelah approval; credential development saja |
| 10 | Pengujian Development | Smoke test `/health`, `/ready`, skenario utama |
| 11 | Approval Staging | Pemilik sistem + TI |
| 12 | UAT & security verification | UAT bank, uji integrasi CBS, pentest sebelum rilis besar |
| 13 | Approval Production | Change Advisory/direksi sesuai kebijakan; dicatat siapa menyetujui |
| 14 | Deploy Production | **Manual dengan approval**; backup terverifikasi → migrate → deploy artefak yang sama |
| 15 | Health check | `/health`, `/ready`, `auditverify` |
| 16 | Rollback | Lihat di bawah |

Ketentuan: secret hanya di CI/CD secret store (masked + protected); tidak ada private key di
repository; credential terpisah per environment; runner/deploy key dengan hak minimum; log
pipeline menyimpan siapa menyetujui dan siapa men-deploy.

### Rollback

1. Deploy ulang artefak versi sebelumnya (tag/digest yang tercatat).
2. Skema additive: aplikasi versi sebelumnya tetap berjalan pada skema baru selama kolom baru tidak
   wajib.
3. Bila skema harus dikembalikan: restore backup ke database **baru**, rekonsiliasi transaksi
   setelah titik backup dengan CBS, lalu alihkan aplikasi
   ([OPERATIONS_AND_BACKUP.md](OPERATIONS_AND_BACKUP.md)).

## 5a. Rilis Syarat dan Ketentuan dan konten aplikasi

* Perubahan isi SK, template PDF di backend, dan konten aplikasi (CMS) **tidak memerlukan build
  APK**: SK diterbitkan melalui backoffice dengan maker-checker; konten melalui draf → terbit.
* Perubahan kode Flutter (viewer PDF `pdfx`, alur persetujuan), dependency, atau layar
  **memerlukan build dan distribusi APK baru**.
* Sebelum go-live: minimal satu versi SK harus **PUBLISHED** (login/aktivasi ditolak tanpa SK
  berlaku), isinya disetujui Kepatuhan/Hukum, dan dua petugas berbeda tersedia untuk maker-checker.
* Migrasi 0008 (tabel SK, persetujuan, revisi konten) dan 0009 (grants) bersifat additive; jalankan
  `migrate grants` bila role dibuat setelah migrasi.

## 6. Prasyarat production yang belum terpenuhi (BLOCKED)

Server dan jaringan resmi · domain, sertifikat TLS, dan pin · kredensial CBS hasil rotasi dan uji
integrasi resmi · rotasi semua secret yang pernah terpapar · secret manager · keystore,
`applicationId`, Play Integrity · proyek Firebase resmi dan FCM HTTP v1 · vendor gateway OTP ·
firewall/WAF/SIEM/monitoring · backup terjadwal, DRC, RPO/RTO · penetration test independen ·
pipeline CI/CD aktif dengan approval · persetujuan manajemen perubahan bank.

## 7. Device binding: signing, attestation, dan deployment

### 7.1 Android: signing release (DB-H8)

* Build release **gagal** bila keystore resmi tidak tersedia; tidak ada lagi fallback debug key.
  Konfigurasi dibaca dari `android/key.properties` (git-ignored) atau dari file yang ditunjuk
  `DMB_ANDROID_KEY_PROPERTIES`, berisi `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
* Keystore dibuat dan disimpan oleh bank (key custodian); CI menerima keystore + properties sebagai
  secret base64 (`DMB_ANDROID_KEYSTORE_B64`, `DMB_ANDROID_KEY_PROPERTIES_B64`; `storeFile` di
  properties menunjuk `$RUNNER_TEMP/keys/release.jks`).
* Play Console: aktifkan **Play App Signing**. Digest yang dipakai server dan gate CI adalah SHA-256
  **sertifikat app signing** (Play Console → Setup → App integrity), bukan upload key.
* `applicationId`/`namespace` masih `com.example.m_banking_bpr` — **NEEDS BANK INPUT**. Saat
  diganti: daftarkan aplikasi Android baru di Firebase (unduh `google-services.json` baru), perbarui
  `DEVICE_ATTESTATION_ANDROID_PACKAGE`. ANDROID_ID dan kunci Keystore berubah untuk instalasi lama;
  pengguna uji mengikat ulang perangkat melalui OTP.

### 7.2 iOS: App Attest

* `ios/Runner/Runner.entitlements` berisi `com.apple.developer.devicecheck.appattest-environment =
  production` dan dipasang di konfigurasi Debug/Profile/Release.
* Apple Developer: App ID resmi dengan capability **App Attest**, provisioning profile yang memuat
  entitlement tersebut, Team ID. Nilai server `DEVICE_ATTESTATION_APPLE_APP_ID = <TeamID>.<bundleID>`.
  Bundle ID masih `com.example.mBankingBpr` — **NEEDS BANK INPUT**.
* iOS 13 / perangkat tanpa App Attest: kunci Secure Enclave `UNVERIFIED` (ditolak di `enforce`).
  Target minimum iOS 13 dipertahankan sampai ada data distribusi versi iOS nasabah.
* Build iOS hanya dapat dijalankan di macOS (workflow `build-ios.yml`); perubahan Swift di
  `AppDelegate.swift` **belum dikompilasi** di lingkungan pengembangan Windows.

### 7.3 CI security gates (`.github/workflows/security-gates.yml`)

| Gate | Script | Gagal bila |
|---|---|---|
| Backend | `gofmt`, `go vet`, `go test -p 1 ./...` (PostgreSQL sementara) | format, vet, test unit/migrasi/integrasi gagal |
| Mobile | `flutter analyze`, `flutter test` | error analyzer, test gagal |
| Jalur produksi | `scripts/ci/check_production_paths.sh` | paket CA uji diimpor kode produksi, material kunci tertanam, ID cadangan / penyimpanan memori, turunan ID lama, debug key untuk release |
| Konfigurasi iOS | `scripts/ci/verify_ios_config.sh` | `NSAllowsArbitraryLoads`, bundle ID template, entitlement App Attest tidak lengkap |
| Artefak Android | `scripts/ci/verify_android_release.sh <apk>` | bukan sertifikat resmi (`DMB_ANDROID_RELEASE_CERT_SHA256`), debug key, `debuggable`, `usesCleartextTraffic`, applicationId template / bukan `DMB_ANDROID_PACKAGE`, flavor artefak bukan `production`, API bukan `https://` |

Build Gradle juga menolak release tanpa `APP_FLAVOR`, dan release staging/production tanpa `API_BASE_URL`
`https://`. Status saat ini: gate konfigurasi iOS dan artefak Android **GAGAL hanya karena input bank**
(bundle ID / applicationId template, sertifikat signing resmi). Artefak flavor local/development tetap
ditolak gate (cleartext, flavor, HTTP). `build-ios.yml`: push ke `main` hanya compile check; IPA dibuat
lewat *workflow_dispatch* (`testing` = HTTP, berlabel NOT_FOR_PRODUCTION; `production` = gate iOS + https).

### 7.4 Urutan deployment device binding

1. Backup database (OPERATIONS_AND_BACKUP.md).
2. `migrate up` (0013, 0014, 0015) lalu `migrate grants` dengan role migrasi.
3. Siapkan file root attestation resmi di server (ENVIRONMENT_SETUP.md §7): root Google hardware
   attestation (dokumentasi Android "Key and ID attestation"), Apple App Attestation Root CA (Apple
   PKI), dan opsional daftar status attestation Google.
4. Deploy backend dengan `DEVICE_BINDING_MODE=dual`, `DEVICE_ATTESTATION_MODE=observe`, dan identitas
   aplikasi resmi. Backend menolak start bila variabel wajib tidak diisi eksplisit.
5. Rilis aplikasi. Pantau **Backoffice → Nasabah & Perangkat → Kunci Keamanan Perangkat**
   (`GET /api/v1/admin/device-binding/summary`).
6. Sebelum `DEVICE_ATTESTATION_MODE=enforce`: periksa angka *Belum terverifikasi* di panel. Saat
   `enforce` aktif, kunci tersebut langsung tidak dapat dipakai (nasabahnya mengikat ulang melalui OTP),
   jadi umumkan ke nasabah terdampak terlebih dahulu. Setelah seluruh nasabah aktif memiliki kunci
   terverifikasi: `DEVICE_BINDING_MODE=enforced`.
7. Rollback cepat tanpa mengubah database: `DEVICE_BINDING_MODE=off` dengan `DEVICE_BINDING_OFF_REASON`
   (nomor tiket) dan `DEVICE_BINDING_OFF_UNTIL` (≤ 72 jam; setelahnya otomatis kembali ke `dual`). Saat
   kembali ke `dual`, nasabah yang memiliki kunci login ulang satu kali (token tanpa klaim `dk`). Rollback skema:
   OPERATIONS_AND_BACKUP.md §Rollback device binding.
