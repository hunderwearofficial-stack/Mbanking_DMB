# Instalasi dan Pengujian Local (Windows + HP Android Fisik)

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Status | Skrip tersedia dan diuji di komputer pengembang (backend + API via IP LAN). Pengujian di HP Android fisik: **NOT TESTED** |
| Pembaca | Developer (termasuk yang baru mengenal Go/Flutter) |

> **Aturan utama:** seluruh pengujian local hanya memakai **database local** (`mbanking_local`,
> port 5433) dan **nasabah uji rekaan** (CIF/rekening berawalan `99…`). Jangan memakai database
> lama, server development/production, atau data nasabah sungguhan.

```
HP Android ──Wi-Fi──► http://<IP-LAN-komputer>:8080  (backend Go, cmd/api)
                                  │
                                  └──► 127.0.0.1:5433  PostgreSQL local (Docker) — tidak terbuka ke jaringan
```

Semua perintah dijalankan di **PowerShell** dari folder root repository, kecuali disebutkan lain.

## 1. Persyaratan

| Alat | Versi | Cek |
|---|---|---|
| Go | 1.25.x (sesuai `go.mod`) | `go version` |
| Flutter | 3.35.x | `flutter --version` |
| Docker Desktop | berjalan (ikon paus aktif) | `docker version` |
| Android SDK + `adb` | — | `adb devices` |
| HP Android | *Developer options* → *USB debugging* aktif | muncul di `adb devices` |

PostgreSQL tidak perlu dipasang di Windows; database local dijalankan Docker
(`docker-compose.local.yml`). Redis tidak diperlukan di local (`REDIS_HOST` kosong = memori).

## 2. Membuka repository

```powershell
cd D:\Freelance\MBanking_BPR
```

## 3. Menyiapkan `.env`

`.env` adalah konfigurasi **khusus local** dan tidak masuk Git (`.gitignore`). Bila sudah ada
`.env` lama, buat cadangan terlebih dahulu — jangan ditimpa:

```powershell
Copy-Item .env .env.backup-lama      # hanya bila .env lama ada; cadangan juga di-ignore Git
Copy-Item .env.example .env
notepad .env
```

Isi nilai yang kosong (penjelasan setiap variabel: [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md)):

| Variabel | Isi |
|---|---|
| `APP_ENV` | `local` (wajib; `.env` hanya untuk local) |
| `DB_PASS`, `MIGRATION_DB_PASS`, `AUDIT_DB_PASS` | string acak, berbeda satu sama lain |
| `JWT_SECRET`, `ADMIN_JWT_SECRET` | 64 karakter hex acak, berbeda |
| `DB_ENCRYPTION_KEY` | 64 karakter hex acak |
| `ADMIN_BOOTSTRAP_USERNAME/PASSWORD` | opsional, untuk login pertama konsol admin |

Membuat 64 karakter hex acak (jalankan sekali per variabel, tempel hasilnya ke `.env`, jangan
dibagikan):

```powershell
-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

Periksa konfigurasi tanpa menjalankan server:

```powershell
go run ./cmd/api -check-config
```

Hasil yang benar diawali `Konfigurasi VALID (APP_ENV=local, ...)`. Bila salah, pesan menyebut
variabel yang harus diperbaiki (nilai secret tidak pernah dicetak).

## 4. Menyiapkan database local

```powershell
.\scripts\local\start-db.ps1
```

Membuat/menjalankan container `mbanking_local_postgres` (127.0.0.1:5433, volume
`mbanking_local_pg`) beserta role `mbanking_app` dan `mbanking_audit_reader`
(`deploy/docker/postgres-init/01-roles.sh`). Role dibuat **hanya saat volume pertama kali
dibuat** — bila password di `.env` berubah setelahnya, lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §3.

Menghentikan (data tetap tersimpan): `.\scripts\local\stop-db.ps1`.

## 5. Menjalankan migration

```powershell
.\scripts\local\migrate.ps1           # menerapkan migrasi (role MIGRATION_DB_USER)
.\scripts\local\migrate.ps1 status    # semua versi harus "applied"
```

## 6. Membuat nasabah uji

Dengan `ENABLE_MOCK_CBS=true`, core banking diganti ledger PostgreSQL local yang **kosong**.
Buat nasabah uji rekaan (`cmd/localfixture`, hanya berjalan bila `APP_ENV=local`, mock CBS aktif,
dan nama database mengandung `local`/`test`):

```powershell
.\scripts\local\create-test-customer.ps1 -Cif 990000000001 -Phone 081200000001 -Account 9900000000001 -Name "Nasabah Uji Satu" -Balance 1000000
.\scripts\local\create-test-customer.ps1 -Cif 990000000002 -Phone 081200000002 -Account 9900000000002 -Name "Nasabah Uji Dua" -Balance 0
```

## 7. Menjalankan backend

```powershell
.\scripts\local\run-api.ps1
```

Skrip menjalankan `-check-config` lalu `go run ./cmd/api`. Biarkan jendela terbuka: log backend
dan **kode OTP uji** (`[SANDBOX OTP - HANYA LOCAL/DEVELOPMENT] ...`) tampil di sini. Saat pertama
kali dijalankan Windows dapat menampilkan pop-up firewall — pilih **Allow** (lihat §10).

## 8. Memeriksa backend

Di jendela PowerShell lain:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/health    # status UP
Invoke-RestMethod http://127.0.0.1:8080/ready     # status READY (database tersambung)
```

### 8.1 Menerbitkan Syarat dan Ketentuan (wajib, sekali per database)

Login dan aktivasi nasabah **ditolak** sampai ada versi Syarat dan Ketentuan (SK) yang terbit
(pesan "Syarat dan Ketentuan layanan belum tersedia"). Migrasi 0008 menyediakan versi 1 berstatus
**DRAFT** berisi teks SK lama dari aplikasi (apa adanya). Penerbitan memakai **maker-checker**, jadi
perlu dua akun petugas:

1. Isi `ADMIN_BOOTSTRAP_USERNAME`/`ADMIN_BOOTSTRAP_PASSWORD` di `.env` (akun SUPER_ADMIN pertama),
   jalankan ulang backend, buka `http://127.0.0.1:8080/admin` (gunakan Chrome/Edge), login.
2. Menu **Manajemen Petugas & Hak Akses** → buat petugas kedua dengan peran **COMPLIANCE**.
3. Login sebagai COMPLIANCE → menu **Syarat & Ketentuan** →
   **Buat PDF Draf** → **Unduh PDF Draf** (periksa isinya) → **Ajukan Persetujuan** (tanggal berlaku
   dapat dikosongkan = berlaku saat disetujui).
4. Logout, login sebagai SUPER_ADMIN → menu yang sama → **Setujui & Terbitkan**.

### 8.2 Mengubah konten aplikasi (tanpa build APK)

1. Login sebagai SUPER_ADMIN atau MARKETING → menu **Konten Aplikasi** → pilih layar (mis.
   **Tampilan Awal**) → ubah nilai (teks, gambar via **Unggah gambar**, tampil/sembunyi banner) →
   **Simpan Draf** → **Ajukan Persetujuan**.
2. Login sebagai petugas lain (SUPER_ADMIN/MARKETING/COMPLIANCE) → **Setujui & Publikasikan**.
3. Periksa: `Invoke-RestMethod http://127.0.0.1:8080/api/v1/content` → `version` naik dan nilai baru.
4. Di HP: tutup aplikasi ke latar lalu buka kembali (atau buka ulang) → layar menampilkan konten baru.
   **Riwayat Versi** menampilkan siapa membuat, mengajukan, menyetujui, beserta perubahan; **Pulihkan
   ke draf** untuk rollback (melalui persetujuan lagi).
5. Periksa: `Invoke-RestMethod http://127.0.0.1:8080/api/v1/terms/active` → `version_number` 1.

Versi 1 hanya untuk pengujian local; isinya belum ditinjau bank (lihat
[SECURITY_AND_OJK.md](SECURITY_AND_OJK.md) §9).

## 9. Mendapatkan IP LAN Windows

```powershell
Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object InterfaceAlias, @{n='IPv4';e={$_.IPv4Address.IPAddress}}
```

Pakai IP adaptor **Wi-Fi** yang satu jaringan dengan HP (contoh format: `192.168.1.20`).

## 10. Pengaturan firewall (sekali, PowerShell **Run as Administrator**)

```powershell
cd D:\Freelance\MBanking_BPR
powershell -ExecutionPolicy Bypass -File .\scripts\local\secure-firewall.ps1
```

`scripts/local/secure-firewall.ps1`:

1. memblokir koneksi masuk TCP 5432 dan 5433 (PostgreSQL) dari komputer lain;
2. mengizinkan TCP 8080 hanya dari subnet lokal (`LocalSubnet`) agar HP di Wi-Fi yang sama bisa
   mengakses backend;
3. mengaktifkan Windows Firewall pada profil Domain, Private, dan Public.

Dampak: koneksi keluar/internet tidak terpengaruh; akses `127.0.0.1` tidak terpengaruh; layanan
lain yang menerima koneksi masuk dari jaringan (mis. akses database lewat Tailscale) ikut
terblokir. Membatalkan aturan: `Get-NetFirewallRule -DisplayName "MBankingBPR*" | Remove-NetFirewallRule`.

Verifikasi:

```powershell
Get-NetFirewallRule -DisplayName "MBankingBPR*" | Select-Object DisplayName, Enabled, Action
Get-NetFirewallProfile | Select-Object Name, Enabled
```

## 11. Menjalankan Flutter di HP Android

HP tersambung USB dan ke Wi-Fi yang sama dengan komputer.

```powershell
.\scripts\local\run-flutter.ps1                     # IP LAN dideteksi otomatis
.\scripts\local\run-flutter.ps1 -LanIp 192.168.1.20  # bila deteksi salah (ganti dengan IP Anda)
```

Setara dengan:

```powershell
cd m_banking_bpr
flutter run --debug --dart-define-from-file=config/local.json --dart-define=API_BASE_URL=http://<IP-LAN>:8080
```

Flavor `local` hanya mengizinkan HTTP pada build **debug** dan menolak `localhost`/`127.0.0.1`
(HP fisik tidak dapat menjangkau localhost komputer).

## 12. Menguji koneksi API dari HP

| Langkah | Hasil yang diharapkan |
|---|---|
| Browser HP: `http://<IP-LAN>:8080/health` | `"status":"UP"` |
| Browser HP: `http://<IP-LAN>:8080/ready` | `"status":"READY"` |
| Buka aplikasi | Splash → onboarding/login. Bila muncul **"Konfigurasi aplikasi tidak valid"**, jalankan ulang lewat `run-flutter.ps1` |

## 13. Menguji fitur aplikasi

Catat hasil sebagai PASS / FAIL / BLOCKED / NOT TESTED. Jangan menandai PASS sebelum benar-benar
dilakukan di HP.

| No | Skenario | Langkah | Diharapkan |
|---|---|---|---|
| 0 | Syarat & Ketentuan | Buka aplikasi → Mulai Sekarang → halaman SK menampilkan PDF (geser antarhalaman, "Halaman 1 dari 3") → centang 3 pernyataan → Setuju & Lanjutkan | Tombol baru aktif setelah PDF tampil dan semua dicentang; lanjut ke Login |
| 1 | Aktivasi | Daftar Akun → CIF `990000000001`, HP `081200000001` → OTP dari jendela backend → buat kata sandi (huruf+angka, ≥ 8) & PIN 6 digit (tidak berurutan/berulang) | "Aktivasi Berhasil!" |
| 2 | Login | Nomor HP + kata sandi | Masuk ke Beranda |
| 3 | Saldo | Beranda | Saldo Rp 1.000.000 |
| 4 | Mutasi | Mutasi Tabungan / Riwayat | Kosong bila ledger local belum berisi mutasi |
| 5 | PIN salah 3× | Profil → Ganti PIN dengan PIN lama salah 3× | Akun diblokir otomatis (buka via konsol admin) |
| 6 | Pinjaman/Deposito | menu terkait | Kosong (ledger local tidak berisi data ini) |
| 7 | Katalog Produk | menu terkait | Pesan gangguan (katalog hanya dari CBS) |
| 8 | Backend mati | Ctrl+C di jendela `run-api.ps1`, tarik-segarkan Beranda | "Saldo belum dapat diperbarui…"; tidak tampil Rp 0 |
| 9 | Database mati | `.\scripts\local\stop-db.ps1` | Pesan gangguan; `/ready` = `NOT_READY`. Nyalakan lagi `start-db.ps1` |
| 10 | Logout | Profil → Keluar dari Aplikasi | Kembali ke layar login |
| 11 | SK gagal dimuat | Matikan backend lalu buka halaman SK | Pesan gangguan + **Coba Lagi**; tombol setuju tetap nonaktif |
| 12 | Persetujuan ulang | Terbitkan SK versi 2 di backoffice (draf baru → PDF → ajukan → setujui petugas lain), lalu login lagi di HP | Aplikasi membuka halaman SK versi 2; setelah disetujui, login berhasil; riwayat persetujuan v1 dan v2 terlihat di backoffice |

### Simulasi CBS tidak dapat dihubungi (tanpa mengubah `.env`)

Variabel di environment proses mengalahkan `.env`. Alamat `10.255.255.1` sengaja tidak dapat
dijangkau; nilai client ID/secret di bawah **bukan kredensial**:

```powershell
$env:ENABLE_MOCK_CBS="false"; $env:CBS_BASE_URL="https://10.255.255.1"
$env:CBS_CLIENT_ID="uji-timeout"; $env:CBS_CLIENT_SECRET="uji-timeout-bukan-kredensial"; $env:CBS_TIMEOUT_SEC="3"
go run ./cmd/api
```

Diharapkan: login berhasil; saldo dan mutasi menampilkan pesan gangguan (HTTP 503). Selesai: Ctrl+C lalu tutup jendela PowerShell.

## 14. Pengujian otomatis

```powershell
go build ./... ; go vet ./... ; go test ./...
cd m_banking_bpr
flutter analyze
flutter test --dart-define=APP_FLAVOR=local --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

Integration test backend membutuhkan PostgreSQL uji **sekali pakai** (skema di-drop; nama
database wajib berakhiran `_test`):

```powershell
docker run -d --name dmb_it_pg -e POSTGRES_PASSWORD=<acak> -e POSTGRES_DB=dmb_it_test -p 127.0.0.1:15433:5432 postgres:16-alpine
$env:DMB_IT_DB_HOST="127.0.0.1"; $env:DMB_IT_DB_PORT="15433"; $env:DMB_IT_DB_USER="postgres"
$env:DMB_IT_DB_PASS="<acak>"; $env:DMB_IT_DB_NAME="dmb_it_test"
go test ./test/integration/ -count=1 -p 1 -v
```

Race detector (`go test -race ./...`) membutuhkan cgo/gcc; di Windows tanpa gcc jalankan di
container `golang:1.25.1`.

## 15. Backup database local (opsional)

```powershell
New-Item -ItemType Directory -Force backups | Out-Null
docker exec mbanking_local_postgres pg_dump -U mbanking_local_owner -d mbanking_local -Fc -f /tmp/local.dump
docker cp mbanking_local_postgres:/tmp/local.dump "backups\mbanking_local_$(Get-Date -Format yyyyMMdd_HHmmss).dump"
```

Folder `backups/` diabaikan Git. Menghapus volume (`docker volume rm mbanking_local_pg`) menghapus
seluruh data local secara permanen; tidak ada skrip yang melakukannya otomatis.
