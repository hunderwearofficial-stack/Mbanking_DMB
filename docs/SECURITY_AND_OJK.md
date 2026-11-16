# Keamanan Sistem dan Bahan Pemeriksaan OJK

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Sifat dokumen | **Bahan persiapan verifikasi** untuk pemeriksa internal (SKAI, Manajemen Risiko, Kepatuhan) dan OJK. **Bukan** sertifikat kepatuhan dan **bukan** jaminan persetujuan OJK |
| Status sistem | Belum di-deploy ke server mana pun; **belum siap production** |
| Dasar bukti | Kode dan test di repository ini, serta hasil uji di komputer pengembang tanggal 13-11-2026 |

Status kontrol: **IMPLEMENTED** (ada di kode dan diuji otomatis) · **PARTIAL** (sebagian) ·
**NOT IMPLEMENTED** · **NOT VERIFIED** (ada, tetapi belum dibuktikan dengan pengujian/operasi
nyata) · **BLOCKED** (menunggu keputusan atau infrastruktur bank/pihak ketiga).

## 1. Kerangka regulasi yang relevan

Daftar berikut diidentifikasi dari situs resmi OJK. **Fungsi Kepatuhan bank wajib memverifikasi
teks resmi, versi yang berlaku, dan pasal yang mengikat** sebelum dipakai dalam pemeriksaan.
Dokumen ini tidak mengutip nomor pasal.

| Ketentuan | Pokok relevansi untuk DMB Mobile |
|---|---|
| **POJK Nomor 34 Tahun 2025** tentang Penyelenggaraan Teknologi Informasi oleh BPR dan BPR Syariah, dengan ketentuan pelaksanaan **PADK Nomor 43/PADK.03/2025** (menggantikan POJK 75/POJK.03/2016 dan SEOJK 15/SEOJK.03/2017) | Tata kelola TI, arsitektur TI, manajemen risiko TI, pengamanan informasi, layanan digital (mis. mobile banking), kerja sama dengan penyedia jasa TI, pengelolaan data & pelindungan data pribadi, DRP, pelaporan insiden TI |
| **POJK Nomor 9 Tahun 2024** tentang Penerapan Tata Kelola bagi BPR dan BPRS | Tata kelola, peran direksi/komisaris, persetujuan dan pengawasan |
| **POJK Nomor 22 Tahun 2023** tentang Pelindungan Konsumen dan Masyarakat di Sektor Jasa Keuangan | Informasi produk yang benar dan tidak menyesatkan (RIPLAY), layanan pengaduan, keamanan data konsumen |
| **POJK Nomor 12 Tahun 2024** tentang Penerapan Strategi Anti Fraud bagi Lembaga Jasa Keuangan | Pencegahan, deteksi, investigasi, pelaporan fraud; jejak audit |
| **UU Nomor 27 Tahun 2022** tentang Pelindungan Data Pribadi | Dasar pemrosesan, keamanan, retensi, dan pemberitahuan kegagalan pelindungan data pribadi |

Sumber: [POJK 34/2025](https://ojk.go.id/id/regulasi/Pages/POJK-34-Tahun-2025-Penyelenggaraan-Teknologi-Informasi-oleh-Bank-Perekonomian-Rakyat-dan-Bank-Perekonomian-Rakyat-Syariah.aspx) ·
[Siaran pers POJK 34/2025 & PADK 43/2025](https://www.ojk.go.id/id/berita-dan-kegiatan/siaran-pers/Pages/POJK-34-2025-dan-PADK-43-2025.aspx) ·
[POJK 9/2024](https://ojk.go.id/id/regulasi/Pages/POJK-9-2024-Penerapan-Tata-Kelola-bagi-BPR-dan-BPRS.aspx) ·
[POJK 22/2023](https://ojk.go.id/id/regulasi/Pages/Pelindungan-Konsumen-dan-Masyarakat-di-Sektor-Jasa-Keuangan.aspx) ·
[POJK 12/2024](https://ojk.go.id/id/berita-dan-kegiatan/siaran-pers/Pages/OJK-Terbitkan-Peraturan-Penerapan-Strategi-Anti-Fraud-Bagi-Lembaga-Jasa-Keuangan.aspx).

### Pembagian tanggung jawab

| Jenis | Contoh | Penanggung jawab |
|---|---|---|
| 1. Persyaratan regulasi | Ketentuan di atas | Kepatuhan bank |
| 2. Kontrol teknis aplikasi | Autentikasi, enkripsi, audit trail, idempotensi | Tim pengembang (dokumen ini §2–§7) |
| 3. Kontrol operasional | Firewall, monitoring, backup, manajemen perubahan, respons insiden | TI operasional bank |
| 4. Bukti yang harus disediakan bank | Kebijakan, SOP, DRP, hasil pentest, berita acara UAT, kontrak penyedia jasa TI, persetujuan direksi | Bank (§8) |

## 2. Pengelolaan akses (A)

| Kontrol | Implementasi | Bukti |
|---|---|---|
| Autentikasi nasabah | Nomor HP/CIF + kata sandi (bcrypt cost 12); OTP saat aktivasi dan lupa kata sandi | `internal/module/auth/service/usecase.go`; `pkg/security/password.go`; `TestPasswordHashing` |
| Kebijakan kata sandi & PIN | Kata sandi ≥ 8 huruf+angka; PIN 6 digit, PIN lemah/berurutan ditolak; kredensial bawaan terpublikasi ditolak | `TestPasswordPolicy`, `TestWeakPIN`, `TestCompromisedCredentialFingerprints` |
| Brute force | Blokir otomatis setelah 3× salah kata sandi atau PIN; rate limit per IP dan per identitas | `internal/module/transaction/service/usecase.go` (`maxPINAttempts = 3`); `internal/app/router.go` (`rl(...)`); IT `DMB-018` |
| OTP | 6 digit CSPRNG; disimpan HMAC-SHA256; TTL 3 menit; maks. 5 percobaan; sekali pakai; terikat perangkat & tujuan; mode SANDBOX ditolak di staging/production | `internal/otp/store.go`, `sender.go`; `TestNoMasterCode`, `TestAttemptLimit`, `TestDeviceAndPurposeBinding`, `TestCodeNotStoredInPlaintext` |
| JWT | HS256 saja; kunci, audience, dan tipe token nasabah ≠ petugas; access 15 mnt, refresh 7 hari, petugas 60 mnt | `pkg/security/token.go`; `TestRejectsAlgNoneAndOtherAlgorithms`, `TestExpiredTokenRejected`, `TestCustomerAndAdminTokensAreNotInterchangeable`; IT `DMB-001` |
| Sesi | Sesi server-side (`sid`) dicek tiap request; logout mencabut sesi; rotasi refresh + deteksi reuse | `internal/session`; IT `DMB-014` (2 subtest) |
| Device binding | `X-Device-ID` wajib cocok; perangkat baru hanya lewat OTP atau reset oleh CS | `pkg/middleware/auth.go`; IT `DMB-013` |
| Kepemilikan rekening | CIF dari token; rekening dari klien divalidasi terhadap CBS; fail-closed | `internal/ownership`; `ownership_test.go`; IT `DMB-004`, `DMB-005` |
| Otorisasi petugas | RBAC per route (SUPER_ADMIN, CS, MARKETING, COMPLIANCE); proteksi SUPER_ADMIN terakhir | `internal/app/router.go` (`roles(...)`); IT `DMB-021` |
| Fail-closed | Tanpa database, autentikasi menolak (503) | `TestAuthFailsClosedWithoutDatabase` |
| Persetujuan Syarat dan Ketentuan | Login, aktivasi, dan refresh token ditolak tanpa persetujuan versi SK yang berlaku; persetujuan dicatat backend (append-only), terikat versi + hash PDF + waktu server; persetujuan ulang saat versi baru berlaku | `internal/legaldoc/service.go` (`EnsureUserConsent`, `RequireUserConsent`, `AcceptPreLogin`); IT `TermsConsentLoginAndReconsent`, `TermsConsentAtActivation`, `TermsUnavailableBlocksLogin`; E2E 14-11-2026 |
| Dokumen SK berversi | Draf → pengajuan → persetujuan petugas lain (maker-checker) → terbit; versi terbit immutable (trigger); PDF tersimpan beralamat SHA-256 | `internal/legaldoc`, migrasi `0008`/`0009`; IT `TermsMakerCheckerAndImmutability`, `ApplicationRoleCannotTamperWithAuditTrail` (alur SK sebagai role aplikasi) |

## 3. Keamanan transaksi (B)

| Kontrol | Implementasi | Bukti |
|---|---|---|
| Validasi nominal | `money.Amount` (int64 sen, parsing eksak); rupiah bulat; pecahan/format salah ditolak | `pkg/money`; `money_test.go`; IT `DMB-015 fractional or malformed amounts…` |
| Inquiry | Nama pemilik rekening tujuan dari CBS; rate limit 30/menit | `GET /account/inquiry`; `router.go` |
| Validasi rekening | Rekening sumber milik nasabah; rekening tujuan tidak dikenal → ditolak tanpa debit | IT `DMB-004`, `DMB-015 transfer to an unknown account never debits the sender` |
| Saldo & limit | Minimum dan limit harian dari `app_configs`; reservasi atomik dengan row lock | IT `DMB-015 daily limit holds under concurrency` |
| Idempotensi | `Idempotency-Key` wajib; replay = hasil asli; payload berbeda = 409 | IT `DMB-015 idempotency, replay and conflict`; `transfer_repository_test.dart` |
| Transaksi gagal | Penolakan CBS → `FAILED`, 422 "dana tidak terdebet" | `internal/module/transaction/delivery/http/handler_test.go` |
| Status tidak diketahui | Timeout → `UNKNOWN`, 202, tidak di-retry; aplikasi "Periksa Status" dengan kunci sama | `handler_test.go`; `transfer_screen_test.dart` |
| Audit transaksi | Sukses, gagal, UNKNOWN, PIN salah, sumber bukan milik dicatat | `audit.Record` di `internal/module/transaction/service/usecase.go` |
| Rekonsiliasi | Rekonsiliasi otomatis UNKNOWN/EOD dengan CBS | **NOT IMPLEMENTED** |

## 4. Keamanan data (C)

| Kontrol | Implementasi | Bukti |
|---|---|---|
| Enkripsi data pribadi | NIK, email, alamat, tempat/tanggal lahir, nama ibu kandung: AES-256-GCM (`enc:v2`), key ring, rotasi `cmd/rekey` | `pkg/crypto`; `TestTamperedCiphertextRejected`, `TestNoDefaultKey_FailsClosed`; IT `DMB-008`, `RekeyLegacyPII` |
| Data belum terenkripsi | Nomor HP dan nama (dipakai untuk pencarian) | **PARTIAL** — keputusan bank |
| Kredensial | Kata sandi/PIN bcrypt; OTP HMAC; refresh token hanya fingerprint | `pkg/security`, `internal/otp`, `internal/session` |
| Pengelolaan secret | Tanpa default; `.env` hanya local; server menolak `.env`; secret tidak dicetak; token gateway OTP/FCM write-only | `config/config.go`; `TestMandatoryValuesHaveNoDefault`, `TestDotEnvIsRefusedOutsideLocal`, `TestSecretsNeverPrinted`; IT `DMB-006` |
| Respons ke klien | NIK dimasking; nama ibu kandung tidak dikirim; error internal generik | `internal/module/account`; `handler_test.go` |
| Logging tanpa data sensitif | Masking berbasis pola kunci (pass, pin, otp, token, secret, nik, …); body `/api/v1/auth/` tidak dilog | `pkg/logger`; `TestMaskJSONString_CoversVariants`, `TestMaskQuery` |
| Aplikasi mobile | Secure storage (Keychain ThisDeviceOnly), `allowBackup=false`, FLAG_SECURE, log hanya build debug | `lib/core/security/*`; `AndroidManifest.xml` |
| Backup & pemulihan | Skrip backup terenkripsi GPG + checksum; restore menolak database berisi | `deploy/scripts/*.sh`; diuji ke database uji 13-11-2026 — lihat [OPERATIONS_AND_BACKUP.md](OPERATIONS_AND_BACKUP.md) |

## 5. Keamanan infrastruktur (D)

| Kontrol | Implementasi | Bukti / status |
|---|---|---|
| HTTPS/TLS | Flutter: selain local wajib `https://`; build rilis menolak cleartext; TLS termination di reverse proxy | `app_environment_test.dart`; `deploy/nginx/mbanking.conf.example` — server belum ada (**BLOCKED**) |
| Certificate pinning | SHA-256 leaf via `API_CERT_PINS`; wajib di rilis production | `ssl_pinning_service_test.dart`; pin resmi **BLOCKED** (domain & sertifikat) |
| Database | Role terpisah; aplikasi tidak dapat mengubah audit/DDL; port terikat 127.0.0.1 di compose | IT `ApplicationRoleCannotTamperWithAuditTrail`; `docker-compose*.yml` |
| Firewall | Server: rancangan di [DEPLOYMENT_AND_CICD.md](DEPLOYMENT_AND_CICD.md); komputer pengembang: `scripts/local/secure-firewall.ps1` | **NOT VERIFIED** |
| Hardening aplikasi server | Security header, CORS allowlist, trusted proxies, batas upload 4 MB + cek magic bytes, container non-root, systemd hardening | `TestSecurityHeaders`, `TestHealthIsMinimal`; `Dockerfile`; `deploy/systemd/mbanking-api.service` |
| Hardening server OS / SSH | Rancangan saja | **BLOCKED** |
| Monitoring & alerting | `/health`, `/ready`; SIEM/alerting belum ada | **PARTIAL** |
| Patch management | `govulncheck` di pipeline (belum berjalan); dependency diperbarui manual | **NOT VERIFIED** |
| Root detection / Play Integrity | Root detection memberi peringatan (tidak memblokir); Play Integrity belum | **PARTIAL** |

## 6. Audit trail (E)

| Aspek | Implementasi | Bukti |
|---|---|---|
| Pencatatan | Login/gagal, blokir otomatis, aktivasi, reset/ganti kata sandi & PIN, transfer, pengajuan produk, seluruh aksi petugas (aktor dari token) | `internal/audit`; pemanggilan `audit.Record` di `internal/module/*` |
| Integritas (hash chain) | `Hash = SHA-256(PrevHash ‖ entri kanonik)`; penulisan diserialisasi `pg_advisory_xact_lock` | IT `DMB-016`, `AuditChainDetectsTampering` |
| Append-only | Trigger menolak UPDATE/DELETE/TRUNCATE (`0002_audit_append_only.sql`) | IT `DMB-016` |
| Hak akses | `mbanking_app`: SELECT/INSERT saja; `mbanking_audit_reader`: SELECT; konsol: SUPER_ADMIN & COMPLIANCE | IT `ApplicationRoleCannotTamperWithAuditTrail`; `router.go` |
| Kegagalan tulis | Dilog `AUDIT WRITE FAILED` | `internal/audit` |
| Verifikasi | `go run ./cmd/auditverify` (read-only; exit code 2 = rantai rusak) | Penjadwalan harian & anchoring hash eksternal: **NOT IMPLEMENTED** |

Prosedur verifikasi oleh pemeriksa: jalankan `auditverify` dengan role `mbanking_audit_reader`
terhadap salinan database (bukan production) → hasil "audit chain utuh" atau nomor `seq` pertama
yang rusak.

## 7. Secure software development (F)

| Aspek | Kondisi aktual | Status |
|---|---|---|
| Code review | Belum ada pull request/branch protection; repository remote di GitHub, pipeline berformat GitLab | **NOT IMPLEMENTED** |
| Unit & router test | `go test ./...` (13 paket) lulus; `flutter test` 31/31 lulus (13-11-2026, komputer pengembang) | IMPLEMENTED |
| Integration test | 4 berkas di `test/integration` (16 subtest regresi keamanan + audit, role DB, upgrade/migrasi) lulus terhadap database uji (13-11-2026) | IMPLEMENTED |
| Race test | `go test -race` belum dijalankan (butuh cgo/container) | **NOT VERIFIED** |
| Security testing | Tidak ada penetration test independen | **NOT IMPLEMENTED** |
| Dependency / secret scanning | `govulncheck` dan `gitleaks` didefinisikan di `.gitlab-ci.yml` tetapi pipeline tidak berjalan | **NOT VERIFIED** |
| Vulnerability management | Belum ada proses tercatat | **NOT IMPLEMENTED** |
| Release approval & change management | Rancangan di [DEPLOYMENT_AND_CICD.md](DEPLOYMENT_AND_CICD.md); belum dijalankan | **NOT IMPLEMENTED** |

## 8. Matriks kontrol dan bukti (G)

| Area kontrol | Implementasi aktual | Bukti teknis | Status | Gap |
|---|---|---|---|---|
| Autentikasi nasabah | Kata sandi bcrypt, OTP, blokir 3× | `pkg/security`, `internal/otp`; test §2 | IMPLEMENTED | Biometrik belum memakai CryptoObject |
| Token & sesi | JWT terpisah, sesi server-side, rotasi + deteksi reuse | IT `DMB-001`, `DMB-014` | IMPLEMENTED | Fitur "cabut semua sesi" massal belum ada |
| Device binding | `X-Device-ID` + OTP untuk perangkat baru | IT `DMB-013` | PARTIAL | Belum ada kunci perangkat berbasis Keystore/attestation |
| Otorisasi nasabah (anti IDOR) | `internal/ownership` fail-closed | IT `DMB-004/005`, `ownership_test.go` | IMPLEMENTED | — |
| Otorisasi petugas | RBAC per route; maker-checker untuk penerbitan SK | IT `DMB-021`, `TermsMakerCheckerAndImmutability` | PARTIAL | Maker-checker baru untuk SK (tidak untuk konfigurasi, banner, konten, user); MFA petugas belum ada |
| Validasi & limit transfer | `money.Amount`, minimum, limit harian atomik | IT `DMB-015` ×4 | IMPLEMENTED | Nilai resmi limit belum ditetapkan bank |
| Idempotensi & status UNKNOWN | Idempotency-Key, 202, tanpa retry buta | IT `DMB-015`, handler & widget test | IMPLEMENTED | Rekonsiliasi otomatis/EOD belum ada |
| Integrasi CBS | OAuth + HMAC-SHA512; kontrak `api/cbs/` | `internal/cbsprovider` | NOT VERIFIED | Belum ada berita acara uji integrasi dengan vendor CBS; secret CBS lama pernah terpapar dan wajib dirotasi |
| Enkripsi data pribadi | AES-256-GCM + rotasi kunci | `pkg/crypto` test, IT `DMB-008` | PARTIAL | Nomor HP & nama belum terenkripsi; kunci belum di KMS/HSM |
| Pengelolaan secret | Fail-fast, tanpa default, `.env` hanya local | `config_test.go` | PARTIAL | Secret manager belum ada; rotasi secret yang pernah terpapar belum dilakukan |
| Logging aman | Masking + request_id | `pkg/logger` test | IMPLEMENTED | Retensi log & SIEM belum ada |
| Audit trail | Hash chain + append-only + role terpisah | IT audit & role | IMPLEMENTED | Verifikasi terjadwal & anchoring eksternal belum ada |
| Persetujuan SK nasabah | Dicatat backend per versi (append-only), gerbang login/aktivasi/refresh, persetujuan ulang | IT SK (4 test), E2E 14-11-2026 | IMPLEMENTED | Uji di HP Android fisik NOT TESTED; kebijakan retensi bukti persetujuan belum ditetapkan bank |
| Versioning dokumen SK | Maker-checker, versi terbit immutable, PDF + hash, arsip | IT SK, `pdfdoc` test, perbandingan isi lama | IMPLEMENTED | Isi SK versi 1 (migrasi apa adanya) belum ditinjau/disetujui bank; nomor dokumen resmi belum ada |
| Konten dinamis aplikasi | Registri 55 elemen; draf → pengajuan → persetujuan petugas lain → publikasi; riwayat, diff, rollback; validasi server & aplikasi; audit | IT `MobileContentWorkflow`, `registry_test.go`, `app_content_test.dart`, UI E2E headless Chrome (14-11-2026) | IMPLEMENTED | Uji di HP fisik NOT TESTED; kontak bawaan belum diverifikasi bank |
| Transport & pinning | HTTPS wajib selain local; pinning | `app_environment_test.dart`, `ssl_pinning_service_test.dart` | BLOCKED | Domain, sertifikat, pin resmi |
| Hardening aplikasi mobile | FLAG_SECURE, allowBackup off, obfuscation, root warning | Manifest, `security_hardening_service.dart` | PARTIAL | `applicationId` resmi, Play Integrity, keystore rilis |
| Infrastruktur server | Contoh nginx/systemd/compose | `deploy/` | BLOCKED | Server, firewall, WAF, hardening OS |
| Backup & DRP | Skrip backup/restore terenkripsi | `deploy/scripts/`; uji 13-11-2026 | PARTIAL | Penjadwalan, DRC, RPO/RTO, uji DRP |
| Monitoring & insiden | `/health`, `/ready`, `auditverify`; prosedur insiden | [OPERATIONS_AND_BACKUP.md](OPERATIONS_AND_BACKUP.md) | PARTIAL | Alerting, on-call, kewajiban lapor insiden ke OJK (tenggat sesuai POJK 34/2025) belum dipetakan |
| Pelindungan konsumen | Data dummy & klaim tak terverifikasi dihapus; pesan gangguan jelas | `account_repository_test.dart`; [USER_MANUAL.md](USER_MANUAL.md) §13 | PARTIAL | Kontak layanan, suku bunga, isi RIPLAY/S&K (memuat fitur yang belum tersedia & limit yang berbeda dari sistem — lihat USER_MANUAL §13), layar e-Statement simulasi |
| Pelindungan data pribadi | Persetujuan PDP di aplikasi; enkripsi; masking | `terms_conditions_screen.dart`; §4 | PARTIAL | Kebijakan retensi, DPIA, prosedur hak subjek data |
| Secure SDLC & CI/CD | Test otomatis lokal; pipeline belum aktif | §7 | PARTIAL | Code review, branch protection, pentest, approval rilis |

## 9. Bukti yang masih harus disediakan bank

1. Kebijakan dan SOP keamanan informasi, manajemen perubahan, manajemen insiden, backup & DRP.
2. Penetapan RPO/RTO, lokasi DC/DRC, dan hasil uji DRP.
3. Hasil penetration test independen dan tindak lanjutnya.
4. Berita acara uji integrasi CBS dan UAT.
5. Perjanjian dengan penyedia jasa TI (vendor CBS, gateway OTP, Firebase, hosting) sesuai ketentuan.
6. Persetujuan direksi untuk layanan digital dan rilis production.
7. Tinjauan dan persetujuan isi Syarat & Ketentuan versi 1 (hasil migrasi apa adanya dari aplikasi), nomor dokumen resmi, kontak layanan nasabah, suku bunga, dan RIPLAY oleh Kepatuhan/Hukum; penerbitan SK melalui maker-checker di backoffice.
8. Bukti rotasi seluruh secret yang pernah terpapar di repository publik.
9. Kebijakan retensi log, audit trail, dan data pribadi.
10. Kebijakan retensi catatan persetujuan SK dan penerapan persetujuan ulang (nasabah lama dan baru).
