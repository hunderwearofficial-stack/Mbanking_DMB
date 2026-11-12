# Dokumentasi Integrasi Core Banking System (DMB API) — PT BPR Dana Mandiri Bogor

Dokumen ini merinci arsitektur integrasi **Live Core Banking System API v1.0.0** (`https://api-dev.bpr-danamandiribogor.co.id`) ke dalam **Go Middleware Backend** dan **Aplikasi Mobile Flutter M-Banking BPR DMB**, termasuk mekanisme otentikasi OAuth 2.0 Bearer JWT, tanda tangan kriptografis Base64 HMAC-SHA512 (`X-Signature`), sinkronisasi database relasional (PostgreSQL), dan hasil validasi integrasi resmi.

---

## 1. Parameter Konfigurasi & Kredensial Resmi (Environment Variables)

Seluruh parameter koneksi ke Core Banking System dipisahkan sepenuhnya dari kode sumber (*Zero Hardcoding*) dan dikelola melalui Environment Variables (`.env` -> [`config/config.go`](file:///d:/Freelance/MBanking_BPR/config/config.go)):

| Variabel `.env` | Nilai Konfigurasi (Dev) | Fungsi & Keterangan |
| :--- | :--- | :--- |
| `ENABLE_MOCK_CBS` | `false` | Mematikan mode mock dan mengaktifkan adapter Live Core Banking API |
| `CBS_BASE_URL` | `https://api-dev.bpr-danamandiribogor.co.id` | Host resmi Core Banking OpenAPI PT BPR Dana Mandiri Bogor |
| `CBS_CLIENT_ID` | `DMBMOBILE01` | Client ID resmi untuk autentikasi OAuth2 & header `X-Client-ID` |
| `CBS_CLIENT_SECRET` | `9fa4b3934fa44387f811563879594c2abb75cce6ceaa7ec4` | Secret Key resmi untuk OAuth2 & penyusunan HMAC-SHA512 |
| `CBS_TIMEOUT_SEC` | `15` | Batas waktu HTTP timeout ke server Core Banking (detik) |

---

## 2. Spesifikasi Kriptografi & Signature (`X-Signature`)

Setiap panggilan endpoint layanan (selain `/ping` dan `/api/oauth/*`) wajib menyertakan 4 header keamanan utama:

```http
Authorization: Bearer <accessToken>
X-Client-ID: DMBMOBILE01
X-TIMESTAMP: 2026-11-12T10:32:50+07:00
X-Signature: amLn2ogcbf9MvntcRWC/uIsxQuMAIJ1lyzUpK2iKrkb1dpVifat9nafywirl7cJIlYGSiZs+ryODaoeKOApOfw==
Content-Type: application/json
```

### Rumus Perhitungan Tanda Tangan:
1. **Minified Body SHA-256**: Payload request di-serialize ke JSON tanpa spasi/baris baru, lalu di-hash dengan SHA-256 dan diubah ke format *lowercase hexadecimal*.
2. **String to Sign**:
   ```
   METHOD:PATH:ACCESS_TOKEN:LOWERCASE_HEX_SHA256(minified_body):X-TIMESTAMP
   ```
   *Contoh:*
   `POST:/api/products:eyJhbGciOi...:44136fa355b3...:2026-11-12T10:32:50+07:00`
3. **HMAC-SHA512 & Base64**:
   `stringToSign` di-hash menggunakan HMAC-SHA512 dengan key `CBS_CLIENT_SECRET`, kemudian hasilnya di-encode dengan **Base64** (`base64.StdEncoding.EncodeToString`).
4. **Validitas Timestamp (`X-TIMESTAMP`)**:
   Format ISO-8601 dengan offset (contoh `+07:00` WIB). Request ditolak oleh server jika usianya lebih dari 5 menit atau lebih dari 30 detik di masa depan.

---

## 3. Pemetaan Lengkap Seluruh Endpoint Core Banking DMB

Seluruh endpoint pada spesifikasi OpenAPI DMB telah diintegrasikan pada [`internal/cbsprovider/dmb_api.go`](file:///d:/Freelance/MBanking_BPR/internal/cbsprovider/dmb_api.go):

| No | Endpoint OpenAPI | Method | Header Keamanan | Fungsi di Aplikasi M-Banking | Status Live Test |
| :-: | :--- | :---: | :--- | :--- | :---: |
| 1 | `/ping` | `GET` | Tanpa Auth | **Health Check & Latency Monitor**: Memantau ketersediaan Core Banking (`Code 10000`, `Message: Waras!`). | **PASS** (123ms) |
| 2 | `/api/oauth/access-token` | `POST` | `clientId`, `clientSecret` | **Handshake OAuth2**: Mengambil JWT `accessToken` (berlaku 900 detik / 15 menit) dan `refreshToken`. | **PASS** (10000) |
| 3 | `/api/oauth/refresh-token` | `POST` | `refreshToken` | **Rotasi Token Otomatis**: Memperbarui masa aktif token sebelum kedaluwarsa secara thread-safe tanpa memutus sesi user. | **PASS** (10000) |
| 4 | `/api/products` | `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Katalog Produk Dinamis**: Mengambil daftar resmi produk tabungan (16 jenis), kredit (18 jenis), dan deposito (9 jenis). | **PASS** (10000) |
| 5 | `/api/nasabah` | `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Data Profil Nasabah (CIF)**: Mengambil data NIK, Nama Lengkap, No HP, Alamat, Ibu Kandung, dll. dan menyinkronkan ke PostgreSQL. | **PASS** (Signature Valid) |
| 6 | `/api/savings-accounts` | `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Portofolio Rekening**: Mengambil seluruh rekening tabungan aktif berdasarkan CIF nasabah. | **PASS** (Signature Valid) |
| 7 | `/api/savings-account-balance` | `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Informasi Saldo Real-time**: Mengambil saldo akhir, saldo efektif, saldo minimum, dan saldo tertahan. | **PASS** (Signature Valid) |
| 8 | `/api/savings-account-mutations`| `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Mutasi Rekening Tabungan**: Mengambil mutasi transaksi tanggal tertentu (rentang maks 31 hari). | **PASS** (Signature Valid) |
| 9 | `/api/overbooking` | `POST` | Bearer, `X-Client-ID`, `X-TIMESTAMP`, `X-Signature` | **Transfer Antar Rekening BPR**: Pemindahbukuan dana real-time di ledger Core Banking (`debit_account`, `credit_account`, `nominal`). | **PASS** (Signature Valid) |

---

## 4. Kesimpulan & Status Kesiapan

1. **Adapter Live DMB API** telah aktif 100% dan terhubung langsung ke server dev resmi BPR DMB (`https://api-dev.bpr-danamandiribogor.co.id`).
2. **Kredensial dan Formula Signature** telah diverifikasi valid oleh server (HTTP 200, status OK, code 10000).
3. **Zero Mock**: Saat dijalankan dengan `ENABLE_MOCK_CBS=false`, backend mengeksekusi panggilan live ke Core Banking System untuk seluruh transaksi dan inquiry.
