# Dokumentasi Integrasi Core Banking System (CBS) OpenAPI — PT BPR Dana Mandiri Bogor

Dokumen ini merinci arsitektur integrasi **Live Core Banking System (CBS) OpenAPI v1.0.0** (`https://cbs-openapi-dev.bprdmb.id`) ke dalam **Go Middleware Backend** dan **Aplikasi Mobile Flutter M-Banking BPR DMB**, termasuk mekanisme **Backdoor Nomor HP di PostgreSQL** serta pemetaan transparan antara fitur **Live CBS**, **Database Middleware (PostgreSQL)**, dan **Simulasi UI (Fitur yang belum tersedia di CBS OpenAPI v1.0.0)**.

---

## 1. Standar Arsitektur & Keamanan (Bank-Grade & Zero Hardcoding)

Seluruh konfigurasi koneksi ke Core Banking System telah dipisahkan sepenuhnya dari kode sumber (*Zero Hardcoding*) dan dikelola melalui Environment Variables (`.env` -> [`config/config.go`](file:///d:/Freelance/MBanking_BPR/config/config.go)):

| Variabel `.env` | Nilai Konfigurasi (Dev) | Fungsi |
| :--- | :--- | :--- |
| `ENABLE_MOCK_CBS` | `false` | Mematikan mode mock dan mengaktifkan adapter Live CBS OpenAPI |
| `CBS_BASE_URL` | `https://cbs-openapi-dev.bprdmb.id` | Base URL server Core Banking OpenAPI BPR DMB |
| `CBS_CLIENT_ID` | `DEMO-CLIENT-001` | Client ID resmi untuk autentikasi OAuth2 & header `X-Client-ID` |
| `CBS_CLIENT_SECRET` | `s3cr3tK3yD3m0BNI2024#!` | Secret Key untuk OAuth2 & pembentukan tanda tangan kriptografi `X-Signature` |
| `CBS_TIMEOUT_SEC` | `15` | Batas waktu HTTP timeout ke server Core Banking (detik) |

### Mekanisme Keamanan Berlapis pada [`internal/cbsprovider/openapi_cbs.go`](file:///d:/Freelance/MBanking_BPR/internal/cbsprovider/openapi_cbs.go)
1. **OAuth2 Bearer Token Management (Thread-Safe)**:
   - Setiap kali backend membutuhkan komunikasi ke CBS, provider memeriksa masa berlaku `accessToken` di memori (dengan `sync.RWMutex`).
   - Apabila token hampir kedaluwarsa (`expiresIn: 900` detik), provider otomatis memanggil **`POST /api/oauth/refresh-token`** terlebih dahulu sebelum fallback ke **`POST /api/oauth/access-token`**.
   - Apabila CBS merespons `401 Unauthorized` (misalnya server CBS restart), provider otomatis melakukan *token re-fetch* dan mengulangi request tanpa gagal di sisi nasabah.
2. **Cryptographic Payload Signing (`X-Signature`)**:
   - Seluruh endpoint transaksi & informasi nasabah wajib menyertakan header `X-Client-ID` dan `X-Signature`.
   - Payload JSON di-marshal dalam format **compact (minified tanpa spasi/baris baru)**, lalu di-hash menggunakan algoritma **HMAC-SHA512** dengan kunci `CBS_CLIENT_SECRET` dan dikodekan ke format *lowercase hexadecimal*.

---

## 2. Pemetaan Seluruh Endpoint CBS OpenAPI (100% Terintegrasi)

Seluruh **7 endpoint** yang ada pada dokumentasi Swagger CBS OpenAPI (`https://cbs-openapi-dev.bprdmb.id/swagger/`) telah diimplementasikan seluruhnya:

| No | Endpoint CBS OpenAPI | Method | Endpoint Middleware Go | Digunakan pada Fitur Aplikasi |
| :-: | :--- | :---: | :--- | :--- |
| 1 | `/ping` | `GET` | `GET /health`<br>`GET /api/v1/cbs/health` | **Health Check System & Indikator Status CBS**: Memantau status konektivitas dan latensi (ms) ke server CBS secara *real-time* (tampil pada modal Profil Nasabah CBS di Home Screen). |
| 2 | `/api/oauth/access-token` | `POST` | Internal Auto-Auth pada `openapi_cbs.go` | **Autentikasi OAuth2 CBS**: Mengambil `accessToken` dan `refreshToken` secara otomatis menggunakan `clientId` dan `clientSecret`. |
| 3 | `/api/oauth/refresh-token` | `POST` | `POST /api/v1/cbs/refresh-token` + Auto-Refresh | **Pembaruan Token Otomatis**: Memperbarui sesi Bearer Token CBS sebelum masa aktif 15 menit habis tanpa memutus transaksi nasabah. |
| 4 | `/api/nasabah` | `POST` | `GET /api/v1/account/profile` | **Profil Nasabah CBS (berdasarkan CIF)**: Menampilkan data resmi CIF dari Core Banking (Nama Lengkap, NIK, Tempat/Tgl Lahir, Nama Ibu Kandung, Agama, Alamat, Kode Pos) ketika pengguna mengetuk sapaan `Hi, <Nama>!` di beranda. |
| 5 | `/api/savings-accounts` | `POST` | `GET /api/v1/account/list` | **Daftar Portofolio Rekening per CIF**: Menampilkan seluruh rekening tabungan yang dimiliki nasabah berdasarkan nomor CIF pada modal Profil Nasabah CBS. |
| 6 | `/api/savings-account-balance` | `POST` | `GET /api/v1/account/balance`<br>`GET /api/v1/account/inquiry` | 1. **Kartu Saldo Beranda & Modal Detail Rekening**: Menampilkan `nama`, `saldo_akhir`, `saldo_efektif`, `saldo_minimum`, `saldo_blokir`, dan `kode_produk` langsung dari CBS.<br>2. **Cek Rekening Tujuan Transfer (Inquiry)**: Memverifikasi nomor rekening penerima dan menampilkan nama asli pemilik rekening dari CBS saat tombol **Periksa** ditekan.<br>3. **Verifikasi Aktivasi & Sinkronisasi Nama Login**. |
| 7 | `/api/overbooking` | `POST` | `POST /api/v1/transaction/transfer` | **Transfer Dana Antar Rekening BPR (Overbooking)**: Memproses pemindahbukuan saldo secara *real-time* di Core Banking (`noRekDebit`, `noRekKredit`, `nominal`, `keterangan`), mengembalikan `ref_id` asli dari CBS, dan mencatat mutasi debit/kredit ke PostgreSQL. |

---

## 3. Skema Tabel Database (`users` & `accounts`) Sesuai JSON CBS OpenAPI & Tanpa Seeder Nasabah

1. **Zero Seeder Data Nasabah ([`pkg/database/seeder.go`](file:///d:/Freelance/MBanking_BPR/pkg/database/seeder.go))**:
   - Seluruh seeder data nasabah/rekening/mutasi buatan **telah dihapus** dari `seeder.go` agar siap dinaikkan ke server *staging/production*.
   - Data nasabah murni masuk dan tersinkronisasi secara *real-time* dari server CBS OpenAPI ketika nasabah melakukan **Aktivasi M-Banking** atau **Login**.

2. **Tabel `users` ([`internal/model/models.go`](file:///d:/Freelance/MBanking_BPR/internal/model/models.go)) Lengkap Sesuai JSON `/api/nasabah`**:
   Seluruh 12 atribut JSON dari endpoint `POST /api/nasabah` tersimpan utuh di tabel `users` PostgreSQL melalui GORM AutoMigrate:

| Field JSON CBS (`/api/nasabah`) | Kolom Tabel `users` PostgreSQL | Tipe Data | Contoh Nilai (Live CBS) |
| :--- | :--- | :--- | :--- |
| `nik` | `nik` | `varchar(30)` | `"3201194101050003"` |
| `cif` | `cif` *(Unique Index)* | `varchar(20)` | `"001000336406"` |
| `nama` | `full_name` | `varchar(100)` | `"IPAT"` |
| `nohp` | `phone_number` *(Unique Index)* | `varchar(20)` | `"081413491403"` |
| `email` | `email` | `varchar(100)` | `""` |
| `alamat` | `alamat` | `text` | `"KP LEBAK DESA RT 005 RW 002"` |
| `kode_pos` | `kode_pos` | `varchar(15)` | `"16670"` |
| `jenis_kelamin` | `jenis_kelamin` | `varchar(5)` | `"P"` |
| `agama` | `agama` | `varchar(30)` | `"Islam"` |
| `tgl_lahir` | `tgl_lahir` | `varchar(40)` | `"2005-01-01T00:00:00Z"` |
| `tempat_lahir` | `tempat_lahir` | `varchar(100)` | `"BOGOR"` |
| `nama_ibu_kandung` | `nama_ibu_kandung` | `varchar(100)` | `"U.RUMSAH"` |

3. **Tabel `accounts` ([`internal/model/models.go`](file:///d:/Freelance/MBanking_BPR/internal/model/models.go)) Lengkap Sesuai JSON `/api/savings-account-balance`**:
   - `account_number` (`nomor_rekening` / `no_rek`)
   - `holder_name` (`nama`)
   - `product_code` (`produk_tabungan` / `kode_produk`)
   - `balance` (`saldo` / `saldo_akhir`)
   - `minimum_balance` (`saldo_minimum`)
   - `blocked_balance` (`saldo_tertahan` / `saldo_blokir`)
   - `effective_balance` (`saldo_efektif`)

4. **Alur Aktivasi & Validasi Nomor HP (`POST /api/v1/auth/activate/verify`)**:
   - Jika data nasabah di CBS memiliki `nohp` asli (contoh: CIF `001000336406` a.n. **IPAT** dengan `nohp: "081413491403"`), maka sistem memvalidasi nomor HP yang diinput harus cocok dengan `nohp` CBS tersebut.
   - Jika data nasabah di CBS masih bernilai `"nohp": "0"`, maka nomor HP dapat di-mapping/di-override langsung melalui tabel `users.phone_number` di PostgreSQL.

---

## 4. Matriks Transparansi: Fitur Live CBS vs PostgreSQL vs Static/Simulasi UI

Untuk kebutuhan *showing* / presentasi hari Senin, berikut adalah rincian jujur mengenai sumber data setiap komponen di aplikasi:

### A. 100% Live dari Server CBS OpenAPI (`https://cbs-openapi-dev.bprdmb.id`)
| Fitur / Layar | Data yang Ditampilkan | Endpoint CBS Sumber |
| :--- | :--- | :--- |
| **Header Sapaan (`Hi, BAMBANG!`)** | Nama depan nasabah otomatis mengikuti pemilik rekening di CBS | `POST /api/savings-account-balance` |
| **Modal Profil Nasabah (Ketuk `Hi, BAMBANG!`)** | Status koneksi CBS (ms), CIF, Nama Lengkap, NIK, Tempat/Tgl Lahir, Nama Ibu Kandung, Agama, Alamat, dan Daftar Rekening per CIF | `GET /ping`<br>`POST /api/nasabah`<br>`POST /api/savings-accounts` |
| **Kartu Utama Tabungan (Slide 1)** | Total Saldo, Nomor Rekening (`0500103000003289`), Kode Produk | `POST /api/savings-account-balance` |
| **Modal Detail Rekening Tabungan** | Nama Pemilik CBS, Kode Produk CBS (`05`), Saldo Akhir, Saldo Efektif, Saldo Minimum, Saldo Blokir, Ref ID CBS | `POST /api/savings-account-balance` |
| **Cek Rekening Tujuan Transfer (`Periksa`)** | Nama asli pemilik rekening tujuan (contoh: ketik `0500103000003364` -> muncul **`REZA FAZRIA RAHMAWAN`**) | `POST /api/savings-account-balance` |
| **Eksekusi Transfer Antar Rekening BPR** | Pemindahbukuan saldo riil (memotong saldo rekening pengirim & menambah saldo rekening penerima di server CBS) | `POST /api/overbooking` |

### B. Live dari Database PostgreSQL Middleware (`mbanking_bpr`)
*(Digunakan karena CBS OpenAPI v1.0.0 hanya menyediakan fungsi Core Ledger dasar dan tidak menyimpan kredensial aplikasi mobile)*
| Fitur / Layar | Penjelasan Teknis | Tabel PostgreSQL |
| :--- | :--- | :--- |
| **Login & Nomor HP (Phone Backdoor)** | Menyimpan mapping Nomor HP (`081234567890`), bcrypt Password, bcrypt PIN 6 digit, dan `device_id` (Device Binding) karena `nohp` di CBS bernilai `"0"`. | `users`, `accounts` |
| **Riwayat Mutasi Rekening (`/api/v1/account/mutations`)** | CBS OpenAPI v1.0.0 belum memiliki endpoint mutasi rekening. Oleh karena itu, setiap transaksi Overbooking yang sukses di CBS otomatis dicatat (beserta `ref_id` dan saldo akhir CBS) ke tabel `mutations` di PostgreSQL. | `mutations`, `transactions` |
| **Banner Promosi Beranda & Web Admin** | Dikelola secara dinamis melalui portal Backoffice Admin (`/admin`) dan diambil dari PostgreSQL. | `banners`, `app_configs` |

### C. Masih Static / Simulasi UI di Aplikasi Mobile
*(Karena belum ada endpoint-nya pada spesifikasi Swagger CBS OpenAPI v1.0.0 saat ini)*
| Fitur / Komponen UI | Lokasi File | Alasan & Nilai yang Ditampilkan |
| :--- | :--- | :--- |
| **Kartu Slide 2 & Menu: Pinjaman (`KREDIT MODAL KERJA`)** | [`loan_model.dart`](file:///d:/Freelance/MBanking_BPR/m_banking_bpr/lib/data/models/loan_model.dart)<br>[`balance_card.dart`](file:///d:/Freelance/MBanking_BPR/m_banking_bpr/lib/presentation/screens/home/widgets/balance_card.dart) | Swagger CBS v1.0.0 baru menyediakan endpoint Tabungan (`savings-accounts`), belum menyediakan endpoint Pinjaman/Kredit (`loan-accounts`). Ditampilkan sebagai simulasi UI eksekutif (`PK-2026-DMB-0988`, Baki Debet `Rp 35.200.000`). |
| **Kartu Slide 3: Deposito (`DEPOSITO BERJANGKA DMB`)** | [`balance_card.dart`](file:///d:/Freelance/MBanking_BPR/m_banking_bpr/lib/presentation/screens/home/widgets/balance_card.dart) | Swagger CBS v1.0.0 belum menyediakan endpoint Deposito (`time-deposits`). Ditampilkan sebagai simulasi kartu ke-3 (`No. Bilyet 5001008009`, `Rp 50.000.000`, Bunga `6.25% p.a.`). |
| **Tombol QRIS, Bayar & Beli, E-Wallet, e-Statement** | [`home_screen.dart`](file:///d:/Freelance/MBanking_BPR/m_banking_bpr/lib/presentation/screens/home/home_screen.dart)<br>[`quick_menu_grid.dart`](file:///d:/Freelance/MBanking_BPR/m_banking_bpr/lib/presentation/screens/home/widgets/quick_menu_grid.dart) | Merupakan fitur pengembangan tahap berikutnya (Phase 2 Biller/Switching). Menampilkan tampilan pemindai QRIS interaktif atau modal informasi peningkatan layanan. |
| **Kode OTP Aktivasi (`123456`)** | [`usecase.go`](file:///d:/Freelance/MBanking_BPR/internal/module/auth/service/usecase.go) | Karena belum terhubung ke SMS/WhatsApp Gateway berbayar di environment development, kode OTP diset ke `123456` untuk kemudahan pengujian. |

---

## 5. Koleksi Postman Siap Pakai (Tanpa Perlu Export Berbayar)
File koleksi Postman standar v2.1 telah dibuatkan langsung di dalam repositori proyek pada lokasi:
- [`docs/CBS_OpenAPI_BPR_DMB.postman_collection.json`](file:///d:/Freelance/MBanking_BPR/docs/CBS_OpenAPI_BPR_DMB.postman_collection.json)

Anda maupun tim IT BPR dapat langsung melakukan **Import** file `.json` tersebut ke aplikasi Postman kapan saja tanpa perlu fitur export berbayar.

