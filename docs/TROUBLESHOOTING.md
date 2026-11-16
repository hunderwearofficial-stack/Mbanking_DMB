# Troubleshooting

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Cakupan | Local (Windows + HP Android) dan server. Pesan di bawah berasal dari kode saat ini |

Prinsip: jangan mematikan kontrol keamanan (firewall, HTTPS, pinning, validasi konfigurasi) sebagai
solusi permanen. Perbaiki penyebabnya.

## 1. Backend tidak bisa start / `.env` tidak valid

Jalankan dulu `go run ./cmd/api -check-config` — pesan menyebut variabel yang salah tanpa mencetak
nilai secret.

| Pesan | Penyebab | Solusi |
|---|---|---|
| `file .env ditemukan tetapi APP_ENV=…` | `.env` berisi environment selain local, atau `.env` ada di server | Local: buat `.env` baru dari `.env.example` dengan `APP_ENV=local` ([ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md) §6). Server: hapus `.env` dari direktori kerja, pakai environment server |
| `APP_ENV wajib diisi` | `.env` belum ada | `Copy-Item .env.example .env`, lalu isi |
| `… wajib diisi` / `… tidak valid` | Variabel kosong atau format salah | Perbaiki variabel yang disebut |
| `STANDALONE_CORE tidak diizinkan` | Variabel lama | Hapus `STANDALONE_CORE` |
| `ENABLE_MOCK_CBS tidak boleh aktif di staging/production` | Mock CBS di server | Isi `CBS_BASE_URL`, `CBS_CLIENT_ID`, `CBS_CLIENT_SECRET` |
| `REDIS_HOST dan REDIS_PASS wajib diisi …` | Staging/production tanpa Redis | Siapkan Redis berpassword |
| `APP_VERSION wajib diisi …` | Staging/production tanpa versi | Isi tag rilis |
| `Redis wajib tersedia` | `REDIS_HOST` diisi tetapi Redis mati | Local: kosongkan `REDIS_HOST` |

## 2. Port 8080 sudah dipakai

Gejala: `bind: address already in use` / `Only one usage of each socket address`.

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen | Select-Object OwningProcess
Get-Process -Id <PID>
```

Hentikan proses lama **bila memang milik Anda** (mis. backend versi lama), atau ubah `APP_PORT`.

## 3. Database tidak tersedia

| Gejala | Solusi |
|---|---|
| `PostgreSQL wajib tersedia` / `connection refused` | `.\scripts\local\start-db.ps1`; pastikan `DB_HOST=127.0.0.1`, `DB_PORT=5433`, `DB_USER=mbanking_app` |
| `password authentication failed` setelah mengubah password di `.env` | Role local dibuat sekali saat volume pertama dibuat. Ubah password role di container (data tetap aman) — perintah di bawah |
| `/ready` → `NOT_READY` | Database/Redis putus; lihat log `Readiness check gagal` |

```powershell
docker exec -it mbanking_local_postgres psql -U mbanking_local_owner -d mbanking_local -c "ALTER ROLE mbanking_app PASSWORD '<DB_PASS-baru>';"
```

Ketik password langsung di terminal Anda sendiri; jangan menyalinnya ke tiket/chat. Menghapus volume
`mbanking_local_pg` menghapus semua data local — hanya dengan sengaja.

## 4. Docker hang

| Gejala | Solusi |
|---|---|
| `docker ps` / `docker info` tidak merespons | Pastikan drive C: punya ruang kosong cukup (Docker Desktop hang bila disk penuh); restart Docker Desktop; `wsl --shutdown` lalu buka Docker Desktop lagi |
| Container local tidak sehat | `docker logs mbanking_local_postgres` |

Jangan menjalankan `docker system prune --volumes` atau `docker volume rm` untuk "memperbaiki" —
keduanya menghapus data.

## 5. Migration gagal

| Pesan | Penyebab | Solusi |
|---|---|---|
| `skema database tidak valid … belum diterapkan` (saat start backend) | Migrasi belum dijalankan | `.\scripts\local\migrate.ps1` |
| `checksum migrasi … berbeda` | File migrasi diubah setelah diterapkan | Kembalikan file; perubahan skema = file migrasi baru |
| Database lebih baru dari binary | Binary lama | Pakai binary versi yang sesuai |
| `MIGRATION_DB_USER dan MIGRATION_DB_PASS wajib diisi` | Variabel migrasi kosong | Isi role pemilik skema (bukan `mbanking_app`) |
| Error SQL di tengah migrasi | — | Transaksi migrasi dibatalkan otomatis; perbaiki lalu jalankan ulang. Di server: **backup dulu** |

## 6. Flutter / HP tidak dapat mengakses backend

Periksa berurutan:

1. Backend berjalan: `Invoke-RestMethod http://127.0.0.1:8080/health`.
2. `APP_HOST` di `.env` **kosong** (bind ke semua antarmuka, bukan 127.0.0.1).
3. HP dan komputer di **Wi-Fi yang sama**; IP benar ([LOCAL_SETUP.md](LOCAL_SETUP.md) §9). Beberapa
   Wi-Fi publik/tamu memblokir komunikasi antarperangkat (*client isolation*).
4. Browser HP membuka `http://<IP-LAN>:8080/health`.
5. Firewall: aturan `MBankingBPR - Backend 8080 dari LAN` ada dan aktif
   (`Get-NetFirewallRule -DisplayName "MBankingBPR*"`). Bila pernah menekan **Cancel** pada pop-up
   Windows Defender untuk `go`/`api.exe`, Windows dapat membuat aturan blokir per program yang
   mengalahkan aturan izin — cari di *Windows Defender Firewall → Inbound Rules* dan hapus aturan
   blokir untuk program tersebut.

| Pesan di aplikasi | Penyebab | Solusi |
|---|---|---|
| "Konfigurasi aplikasi tidak valid" | Build tanpa `APP_FLAVOR`/`API_BASE_URL`, memakai `localhost`, atau HTTP di flavor selain local | Jalankan lewat `.\scripts\local\run-flutter.ps1` |
| "Tidak dapat terhubung ke server …" | Langkah 1–5 di atas | — |

## 7. Login gagal

| Gejala | Penyebab | Solusi |
|---|---|---|
| Kata sandi salah | — | Setelah 3× salah akun diblokir; buka via konsol admin (CS/SUPER_ADMIN) |
| Ditolak dari HP lain | Device binding | Lupa Password (OTP) di HP baru, atau reset perangkat oleh CS |
| Login dengan kredensial bawaan ditolak | Kredensial default terpublikasi diblokir | Aktivasi ulang / reset kata sandi |
| Akun belum aktif | Belum aktivasi | Daftar Akun (aktivasi) |

## 8. Token kedaluwarsa

Access token nasabah berlaku 15 menit dan diperbarui otomatis dengan refresh token (7 hari).
Refresh gagal (sesi dicabut, logout di perangkat lain, refresh token dipakai ulang, rotasi
`JWT_SECRET`) → aplikasi kembali ke layar login; ini perilaku yang diharapkan. Bila terjadi terus
menerus, periksa jam HP/server (NTP) dan log `refresh`.

## 9. CBS timeout

| Gejala | Solusi |
|---|---|
| Saldo/mutasi "belum dapat ditampilkan" (503) | Local: pastikan `ENABLE_MOCK_CBS=true`. Server: `GET /api/v1/admin/cbs/health`, cek jaringan keluar 443, kredensial CBS, `CBS_TIMEOUT_SEC`; hubungi vendor |
| Transfer "Status Transaksi Sedang Diverifikasi" | Jangan transfer ulang; **Periksa Status** (kunci idempotensi sama); rekonsiliasi dengan CBS |
| Transfer `UNKNOWN` menumpuk | Aktifkan `maintenance_mode`; rekonsiliasi |

## 10. OTP gagal

| Gejala | Penyebab | Solusi |
|---|---|---|
| Local: OTP tidak diterima di HP | Mode SANDBOX — kode tidak dikirim | Baca baris `[SANDBOX OTP - HANYA LOCAL/DEVELOPMENT]` di jendela backend |
| Staging/production: `gateway OTP belum dikonfigurasi` | `otp_provider`/token kosong | SUPER_ADMIN mengisi penyedia & token gateway di konsol |
| `Gateway OTP menolak permintaan` / gagal kirim | Token salah, saldo vendor habis, URL bukan https | Periksa di dashboard vendor; URL gateway wajib `https://` |
| "Kode OTP salah" berulang | Maks. 5 percobaan, TTL 3 menit, terikat perangkat & tujuan | Minta kode baru di perangkat yang sama |

## 11. FCM (push notification) gagal

* Backend memakai endpoint FCM *legacy* (`fcm.googleapis.com/fcm/send`) dengan FCM server key dari
  konsol. Endpoint ini perlu dimigrasi ke FCM HTTP v1 (service account); sebelum itu push dari
  server dianggap **tidak berfungsi**. Notifikasi tetap tersimpan di kotak masuk aplikasi.
* Di HP: izin notifikasi aplikasi harus aktif. Kegagalan inisialisasi Firebase tidak menghentikan
  aplikasi.
* Konfigurasi `google-services.json` saat ini berasal dari proyek Firebase pengembangan.

## 12. Certificate pinning gagal

| Gejala | Penyebab | Solusi |
|---|---|---|
| Semua request gagal setelah perpanjangan sertifikat server | Pin di aplikasi tidak cocok dengan sertifikat leaf baru | Selalu sertakan pin **cadangan** saat rilis; rilis aplikasi dengan pin baru **sebelum** sertifikat diganti |
| Build production ditolak | `API_CERT_PINS` kosong | Isi pin SHA-256 (aktif + cadangan) |

Menghitung pin (sertifikat leaf):

```bash
openssl x509 -in cert.pem -outform der | openssl dgst -sha256
```

Jangan menonaktifkan pinning di build production sebagai solusi.

## 13. Syarat dan Ketentuan (SK) dan persetujuan

| Gejala | Penyebab | Solusi |
|---|---|---|
| Login/aktivasi: "Syarat dan Ketentuan layanan belum tersedia" (503, kode `11`) | Belum ada versi SK yang terbit | Terbitkan SK melalui backoffice dengan dua petugas ([LOCAL_SETUP.md](LOCAL_SETUP.md) §8.1). Jangan menonaktifkan pemeriksaan ini |
| Login: aplikasi kembali ke halaman SK (403, kode `10`) | Persetujuan versi yang berlaku belum tercatat: nasabah baru, versi baru sudah berlaku, persetujuan perangkat > 24 jam, atau persetujuan dari perangkat/nasabah lain | Normal: baca PDF, centang, **Setuju & Lanjutkan**, lalu login |
| "versi … bukan versi yang sedang berlaku" (409, kode `12`) | Versi baru terbit saat halaman SK terbuka | Aplikasi memuat ulang dokumen otomatis; setujui versi terbaru |
| Halaman SK: "Dokumen yang diterima tidak sesuai dengan versi…" | Hash SHA-256 PDF tidak cocok (berkas rusak/terpotong/diubah di jaringan) | Coba Lagi; bila berulang, periksa proxy/jaringan. Dokumen tidak pernah ditampilkan bila hash berbeda |
| Halaman SK: "Dokumen PDF tidak dapat ditampilkan" | Renderer PDF Android gagal membuka berkas | Coba Lagi; periksa `GET /api/v1/terms/versions/<id>/pdf` dari browser |
| Backoffice: "persetujuan harus dilakukan petugas yang berbeda…" | Maker-checker: penyetuju sama dengan pembuat/pengaju | Login sebagai petugas lain (SUPER_ADMIN/COMPLIANCE) |
| Backoffice: "masih ada draf atau versi yang menunggu persetujuan" | Hanya satu draf terbuka | Selesaikan, ajukan, atau kembalikan draf yang ada |
| Backoffice: "Unggah PDF tidak didukung" | Unggah PDF bebas dinonaktifkan | Kelola SK di menu **Syarat & Ketentuan** (PDF dibuat backend) |
| Konten aplikasi tidak berubah setelah disimpan | Baru tersimpan sebagai draf atau belum disetujui | **Ajukan Persetujuan**, lalu petugas lain **Setujui & Publikasikan**; aplikasi mengambil versi baru saat dibuka atau kembali ke depan (maks. sekali per menit) |
| "Setujui & Publikasikan" nonaktif | Anda pembuat/pengaju revisi (maker-checker) atau peran tidak berwenang | Minta petugas lain (SUPER_ADMIN/MARKETING/COMPLIANCE) menyetujui |
| Nilai konten ditolak (422) | Tidak sesuai aturan elemen (panjang, `<`/`>`, gambar bukan unggahan/https, nomor/email tidak valid) | Perbaiki sesuai pesan; nilai tidak valid juga diabaikan aplikasi |
| Backoffice di port selain 8080 gagal memanggil API | (diperbaiki) konsol kini selalu memanggil API pada origin yang sama | Muat ulang halaman (Ctrl+F5) |
