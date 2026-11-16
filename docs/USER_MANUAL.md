# Buku Panduan Pengguna DMB Mobile

| Atribut | Nilai |
|---|---|
| Diperbarui | 14 November 2026 |
| Berlaku untuk | Aplikasi DMB Mobile (kode `m_banking_bpr`) versi saat ini |
| Status | **Draf.** Disusun dari layar aplikasi yang ada di kode. Aplikasi **belum dirilis** dan belum diuji di HP nasabah. Bagian bertanda ⚠ harus ditinjau bank sebelum buku ini dibagikan |
| Gambar layar | Belum disertakan; ditambahkan dari aplikasi rilis resmi setelah UAT |

Bagian 1–12 ditujukan untuk nasabah. Bagian 13 adalah catatan internal untuk bank.

---

## 1. Persyaratan

* Anda adalah nasabah PT BPR Dana Mandiri Bogor (Bank DMB) yang memiliki **nomor CIF** (tertera
  di buku tabungan) dan rekening tabungan aktif.
* Nomor HP Anda **terdaftar di bank** dan aktif untuk menerima kode OTP.
* HP Android dengan koneksi internet. (Versi iPhone belum tersedia.)
* Satu akun DMB Mobile hanya dapat aktif di **satu HP** pada satu waktu.

## 2. Memasang aplikasi

⚠ Aplikasi belum dipublikasikan. Kanal resmi pengunduhan (mis. Google Play) akan diumumkan
bank. **Jangan memasang aplikasi DMB Mobile dari tautan, pesan WhatsApp, atau file APK kiriman
siapa pun.**

Setiap kali aplikasi dibuka sebelum masuk, aplikasi menampilkan layar pengenalan. Tekan
**Mulai Sekarang** untuk membuka halaman **Syarat dan Ketentuan**:

1. Dokumen ditampilkan dalam bentuk PDF resmi bank. Geser ke kiri/kanan untuk berpindah halaman
   ("Halaman 1 dari …"), cubit layar untuk memperbesar. Nomor versi dan tanggal mulai berlaku
   tertera di bagian atas.
2. Setelah dokumen tampil, centang setiap pernyataan persetujuan.
3. Tekan **Setuju & Lanjutkan**. Persetujuan Anda dicatat oleh sistem bank; bila pencatatan gagal
   (misalnya koneksi terputus), aplikasi menampilkan pesan dan Anda dapat mencoba lagi.

Bila bank memperbarui Syarat dan Ketentuan, aplikasi akan meminta Anda membaca dan menyetujui
versi terbaru sebelum dapat masuk kembali. Membuka dokumen saja tidak dianggap sebagai persetujuan.

## 3. Aktivasi akun (pertama kali)

Di layar masuk, tekan **Daftar Akun**. Aktivasi terdiri atas tiga langkah:

1. **Verifikasi Nomor CIF** — isi *Nomor CIF Nasabah* (12 digit, lihat buku tabungan) dan
   *Nomor Handphone Terdaftar*, lalu lanjutkan. Nomor HP harus sama dengan yang tercatat di bank.
2. **Verifikasi Kode OTP** — masukkan 6 digit kode yang dikirim ke nomor HP Anda. Kode berlaku
   **3 menit**. Bila tidak menerima kode, tekan **Kirim Ulang Kode OTP** setelah hitungan mundur
   selesai.
3. **Buat Kata Sandi & PIN** —
   * *Kata sandi* untuk masuk aplikasi: minimal 8 karakter, berisi huruf **dan** angka.
   * *PIN Transaksi 6 digit* untuk menyetujui transaksi. PIN yang mudah ditebak (mis. `123456`,
     `111111`) ditolak.
   Tekan **Selesaikan Aktivasi**. Layar **Aktivasi Berhasil!** muncul dan HP ini menjadi HP
   terdaftar untuk akun Anda.

## 4. Masuk (login) dan keluar

**Masuk:** isi *Nomor Handphone* dan *Kata Sandi*, lalu tekan tombol masuk.

* Bila Anda pernah mengaktifkan **Masuk dengan biometrik** (sidik jari/wajah), Anda dapat masuk
  dengan memindai biometrik di HP yang sama.
* Masuk dari **HP lain** akan ditolak. Untuk memindahkan akun ke HP baru, gunakan **Lupa Password?**
  di HP baru (verifikasi OTP), atau hubungi bank untuk reset perangkat.
* Salah kata sandi **3 kali** membuat akun diblokir otomatis. Hubungi bank untuk membuka blokir.

**Keamanan sesi:** aplikasi keluar otomatis bila tidak digunakan selama **3 menit**.

**Keluar:** buka **Profil** → **Keluar dari Aplikasi** → **Ya, Keluar**.

## 5. Lupa kata sandi

1. Di layar masuk, tekan **Lupa Password?**.
2. Isi *Nomor Handphone Terdaftar* → **Kirim Kode OTP**.
3. Masukkan kode OTP.
4. Buat kata sandi baru (minimal 8 karakter, huruf dan angka) → **Simpan Kata Sandi Baru**.

Setelah berhasil, semua sesi lama diakhiri dan HP yang dipakai menjadi HP terdaftar.

**Lupa PIN transaksi:** fitur reset PIN mandiri **belum tersedia**. Hubungi kantor Bank DMB.

## 6. Beranda, rekening, dan saldo

**Beranda** menampilkan *Rekening Utama* dan *Saldo Tersedia*. Saldo diambil langsung dari sistem
inti bank. Tarik layar ke bawah untuk memperbarui.

* Bila saldo tidak dapat diambil, aplikasi menampilkan **"Saldo belum dapat ditampilkan"** atau
  **"Saldo belum dapat diperbarui"** — bukan Rp 0. Coba kembali beberapa saat lagi.
* Menu utama di Beranda: **Transfer DMB**, **Mutasi Tabungan**, **Fasilitas Pinjaman**,
  **Portofolio Deposito**, **Katalog Produk**.
* Ikon di bagian atas: **Pusat Bantuan**, **Pengaturan Keamanan**, **Notifikasi**.
* Navigasi bawah: **Beranda**, **Riwayat**, **Profil**.

Data identitas di **Profil** (NIK, alamat, dan lainnya) disembunyikan. Tekan **Buka Proteksi** dan
masukkan PIN transaksi untuk melihatnya; tekan **Kunci Data** untuk menyembunyikan kembali.

## 7. Mutasi dan riwayat transaksi

1. Buka **Mutasi Tabungan** (Beranda) atau **Riwayat** (navigasi bawah).
2. Pilih periode: *7 Hari Terakhir*, *30 Hari Terakhir*, *Bulan Ini*, *Bulan Lalu*, atau rentang
   tanggal sendiri (**maksimal 31 hari** per permintaan).
3. Setiap baris menunjukkan **Uang Masuk** atau **Uang Keluar**, nominal, dan waktu. Tekan baris
   untuk melihat rincian (nomor referensi, saldo setelah transaksi).

Bila tidak ada transaksi pada periode itu, tampil **"Belum Ada Transaksi"**.

## 8. Transfer antar rekening Bank DMB

1. Beranda → **Transfer DMB**.
2. Isi *Nomor rekening tujuan (Bank DMB)*, *Nominal* (rupiah bulat, tanpa desimal), dan *Berita*
   (opsional). Rekening sumber adalah rekening utama Anda.
3. Aplikasi menampilkan **nama pemilik rekening tujuan** dari sistem bank (*inquiry*).
   **Pastikan nama penerima benar.** Bila salah, tekan **Ubah data**.
4. Pada **Konfirmasi Transfer**, periksa kembali, lalu tekan **Transfer Sekarang**.
5. Masukkan **PIN Transaksi**.

Hasil yang mungkin:

| Tampilan | Arti | Yang perlu Anda lakukan |
|---|---|---|
| **Transfer Berhasil** + No. Referensi | Dana telah dipindahkan | Simpan nomor referensi. Transfer berhasil **tidak dapat dibatalkan** |
| Pesan penolakan | Transfer tidak diproses; **dana tidak terdebet** | Periksa pesan (mis. rekening tidak ditemukan, di bawah minimum, melebihi limit harian) |
| **Status Transaksi Sedang Diverifikasi** | Sistem belum mendapat kepastian dari bank | **Jangan mengulang transfer.** Tekan **Periksa Status**. Bila tetap belum pasti, hubungi bank dengan menyebut *No. Permintaan* |
| "Layanan sedang mengalami gangguan" | Layanan tidak tersedia | Coba kembali nanti |

Ketentuan:

* Nominal minimum dan limit transfer harian ditetapkan bank (pengaturan awal sistem: minimum
  Rp 10.000, limit Rp 25.000.000 per hari). ⚠ Nilai resmi wajib dikonfirmasi bank.
* Salah PIN **3 kali** membuat akun diblokir otomatis. Hubungi bank untuk membuka blokir.
* Transfer ke **bank lain belum tersedia**.

## 9. Pinjaman, deposito, dan katalog produk

* **Fasilitas Pinjaman** — daftar pinjaman Anda (plafon, sisa pokok, status kolektibilitas).
* **Portofolio Deposito** — daftar bilyet deposito (nominal, suku bunga, jatuh tempo).
* **Katalog Produk** — produk tabungan, deposito, dan pinjaman Bank DMB.
* Dari katalog Anda dapat membuat **simulasi** lalu **mengajukan** pinjaman atau pembukaan deposito.
  Pengajuan dikirim ke bank dan akan ditindaklanjuti petugas; pengajuan **bukan** persetujuan.
  ⚠ Angka pada simulasi adalah ilustrasi; suku bunga resmi mengikuti ketentuan bank.

Bila data tidak dapat diambil dari sistem bank, tampil pesan gangguan dan tombol **Coba Lagi**.

## 10. Notifikasi

Ikon lonceng di Beranda membuka **Kotak Masuk & Notifikasi** (aktivitas akun, keamanan, serta
informasi dari bank). Titik merah menandakan ada pesan belum dibaca. Tekan **Tandai Dibaca** untuk
menandai semua pesan sebagai telah dibaca. Pemberitahuan *pop-up* di HP bergantung pada izin
notifikasi HP Anda.

## 11. Pengaturan keamanan

Buka ikon perisai di Beranda atau **Profil** → **Pengaturan & Keamanan Akun**:

* **Ganti Password Login** — masukkan kata sandi saat ini dan kata sandi baru.
* **Ganti PIN Transaksi** — masukkan PIN saat ini dan PIN baru (6 digit, tidak berurutan).
* **Masuk dengan biometrik** — aktif/nonaktif.
* **Perlindungan Privasi Layar** — selalu aktif; tangkapan layar tidak dapat dibuat di aplikasi.
* **Keamanan Sistem Ponsel** — aplikasi memberi peringatan bila sistem HP terdeteksi dimodifikasi
  (*root*). Sebaiknya jangan memakai DMB Mobile di HP yang dimodifikasi.

## 12. Tips keamanan dan bila terjadi transaksi mencurigakan

**Petugas Bank DMB tidak pernah meminta kata sandi, PIN, atau kode OTP Anda melalui kanal apa pun.**

* Jangan memberitahukan kata sandi, PIN, atau OTP kepada siapa pun, termasuk orang yang mengaku
  petugas bank.
* Jangan memakai tanggal lahir atau angka berurutan sebagai PIN.
* Pasang aplikasi hanya dari kanal resmi yang diumumkan bank.
* Kunci layar HP Anda; jangan meminjamkan HP yang terdaftar.
* Selalu periksa nama penerima sebelum menekan **Transfer Sekarang**.

**Bila melihat transaksi yang tidak Anda lakukan, HP hilang, atau menerima OTP yang tidak Anda minta:**

1. Segera hubungi Bank DMB melalui kontak resmi di menu **Pusat Bantuan**, atau datang ke kantor
   Bank DMB. ⚠ Kontak resmi wajib dikonfirmasi bank sebelum buku ini dibagikan.
2. Minta petugas **memblokir akun** dan **mereset perangkat** Anda.
3. Siapkan nomor referensi transaksi dan waktu kejadian.
4. Setelah akun dibuka kembali, ganti kata sandi dan PIN.

**Fitur yang belum tersedia:** transfer antarbank/BI-FAST, pembayaran tagihan, pembelian pulsa
atau token listrik, top up dompet digital, reset PIN mandiri, berbagi bukti transfer, aplikasi
iPhone, dan e-Statement PDF (lihat bagian 13).

---

## 13. Catatan internal untuk bank (bukan untuk nasabah)

Ketidaksesuaian antara tampilan aplikasi dan sistem yang ditemukan saat penyusunan buku ini. Harus
diselesaikan atau diputuskan bank sebelum rilis:

| No | Temuan | Lokasi | Dampak |
|---|---|---|---|
| 1 | Layar **e-Statement Rekening** hanya menampilkan animasi lalu pesan "berhasil diunduh"; tidak ada endpoint backend dan tidak ada file yang dibuat | `lib/presentation/screens/statement/estatement_screen.dart` | Menyesatkan nasabah; fitur dinyatakan **belum tersedia** |
| 2 | Layar **Ganti PIN** dan **Ganti Password** menampilkan langkah "Verifikasi OTP", tetapi backend tidak mengirim maupun memeriksa OTP untuk kedua fitur ini (hanya kata sandi/PIN lama) | `profile/change_pin_screen.dart`, `profile/change_password_screen.dart`; `ChangePINRequest`/`ChangePasswordRequest` di `internal/domain/user.go` | Buku ini tidak menyebut OTP untuk kedua fitur tersebut |
| 3 | Layar lupa kata sandi berjudul **"Lupa PIN / Kata Sandi"**, tetapi alurnya hanya mereset kata sandi | `auth/forgot_password_screen.dart`, `reset_password_screen.dart` | Reset PIN mandiri dinyatakan belum tersedia |
| 4 | Isi **Syarat & Ketentuan/RIPLAY** (kini PDF versi 1, dimigrasikan apa adanya dari aplikasi) menyebut fitur yang belum ada (antarbank, BI-FAST, tagihan, pulsa, dompet digital), limit (Rp 50.000.000/hari) yang berbeda dengan konfigurasi sistem (default Rp 25.000.000), dan nomor kontak yang belum diverifikasi | SK versi 1 di backoffice; `pkg/database/migrations/0008_legal_documents_and_content_revisions.sql` | Wajib ditinjau Kepatuhan/Hukum sebelum diterbitkan untuk nasabah |
| 5 | Teks aplikasi menyebut OTP dikirim melalui **SMS**, sedangkan penyedia yang didukung backend adalah gateway WhatsApp (Fonnte/Wablas) atau webhook | `activation_screen.dart`; `internal/otp/sender.go` | Sesuaikan teks setelah vendor OTP ditetapkan |
| 6 | Kontak layanan (nilai bawaan aplikasi) dan suku bunga belum diverifikasi bank | Kontak: backoffice **Konten Aplikasi → Kontak Layanan** (dapat diperbaiki tanpa build APK); suku bunga: `product_rates.dart` | Bank wajib menerbitkan kontak resmi sebelum rilis |
| 7 | Teks "DMB Mobile v1.0.0 (Production Build)" di Profil tidak mencerminkan build sebenarnya | `profile/profile_screen.dart` | Kosmetik; hindari klaim "production" |
