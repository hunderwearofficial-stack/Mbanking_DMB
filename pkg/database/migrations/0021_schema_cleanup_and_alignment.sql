-- 0021 Schema cleanup and alignment with actual M-Banking scope (no fund transfer,
-- consistent column widths, banners schema fix, case-insensitive username uniqueness,
-- audit reader privilege for mobile_content_revisions, and accurate Terms draft seed).
-- Rollback: pkg/database/rollback/0021_schema_cleanup_and_alignment_down.sql.

-- 1. Drop unused transfer tables.
DROP TABLE IF EXISTS transfer_requests;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS saved_beneficiaries;

-- 2. Drop unused transfer and legacy columns from app_configs.
ALTER TABLE app_configs
    DROP COLUMN IF EXISTS min_transfer_amount,
    DROP COLUMN IF EXISTS daily_transfer_limit,
    DROP COLUMN IF EXISTS interbank_transfer_fee,
    DROP COLUMN IF EXISTS fcm_server_key;

-- 3. Drop unused columns from users.
ALTER TABLE users
    DROP COLUMN IF EXISTS device_rebound_at,
    DROP COLUMN IF EXISTS fcm_token;

-- 4. Align device_challenges_purpose_check with active device challenge purposes.
ALTER TABLE device_challenges DROP CONSTRAINT IF EXISTS device_challenges_purpose_check;
DELETE FROM device_challenges WHERE purpose NOT IN ('LOGIN', 'REFRESH', 'CHANGE_PASSWORD', 'CHANGE_PIN', 'PROFILE_REVEAL', 'ENROLL', 'ROTATE');
ALTER TABLE device_challenges ADD CONSTRAINT device_challenges_purpose_check
    CHECK (purpose IN ('LOGIN', 'REFRESH', 'CHANGE_PASSWORD', 'CHANGE_PIN', 'PROFILE_REVEAL', 'ENROLL', 'ROTATE'));

-- 5. Fix banners table schema bug (missing image_url column, non-null tag/highlight without default).
ALTER TABLE banners ADD COLUMN IF NOT EXISTS image_url text NOT NULL DEFAULT '';
ALTER TABLE banners ALTER COLUMN tag SET DEFAULT '';
ALTER TABLE banners ALTER COLUMN highlight SET DEFAULT '';

-- 6. Case-insensitive unique index on users.username.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_lower ON users (LOWER(username)) WHERE username IS NOT NULL;

-- 7. Grant audit reader access to mobile_content_revisions.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    EXECUTE 'GRANT SELECT ON TABLE mobile_content_revisions TO mbanking_audit_reader';
  END IF;
END $$;

-- 8. Update seeded DRAFT of MOBILE_BANKING_TERMS (only if still v1 DRAFT) to remove
--    transfer/BI-FAST/bill-payment/e-wallet claims and accurately reflect actual scope.
UPDATE legal_document_versions
SET change_summary = 'Penyesuaian ruang lingkup layanan DMB Mobile (informasi saldo, riwayat mutasi, portofolio deposito & pinjaman, serta pengajuan produk perbankan).',
    content = c.content,
    content_sha256 = encode(sha256(convert_to(c.content::text, 'UTF8')), 'hex'),
    updated_at = now()
FROM (SELECT $sk${
  "title": "Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor",
  "date_note": "Diperbarui pada 19 November 2026",
  "intro": "Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor.",
  "sections": [
    {
      "heading": "Ringkasan Informasi Produk dan Layanan (RIPLAY) Versi Personal",
      "fields": [
        {"label": "Nama Penerbit", "value": "PT BPR Dana Mandiri Bogor"},
        {"label": "Nama Produk", "value": "DMB Mobile"},
        {"label": "Jenis Produk", "value": "Mobile Banking"},
        {"label": "Deskripsi", "value": "Fasilitas layanan perbankan elektronik yang disediakan oleh Bank bagi Nasabah untuk memantau informasi saldo, riwayat mutasi rekening, portofolio deposito berjangka dan fasilitas pinjaman, serta pengajuan produk perbankan melalui Smartphone."}
      ]
    },
    {
      "heading": "I. Fitur Utama Layanan",
      "blocks": [
        {"text": "1. Informasi Rekening Simpanan Tabungan meliputi:", "items": ["a. Informasi Saldo Real-Time 24 Jam (Saldo Efektif, Saldo Minimum, dan Saldo Tertahan)", "b. Daftar Rekening Tabungan Nasabah", "c. Riwayat Mutasi Rekening Tabungan berdasarkan rentang tanggal"]},
        {"text": "2. Pemantauan Portofolio Deposito & Pinjaman meliputi:", "items": ["a. Daftar dan Rincian Bilyet Deposito Berjangka beserta Riwayat Bagi Hasil/Bunga", "b. Daftar dan Rincian Fasilitas Pinjaman/Kredit beserta Riwayat Angsuran", "c. Katalog Resmi Produk Tabungan, Deposito, dan Kredit Bank DMB"]},
        {"text": "3. Pengajuan Produk Perbankan meliputi:", "items": ["a. Simulasi dan Pengajuan Pembukaan Deposito Berjangka", "b. Simulasi dan Pengajuan Fasilitas Pinjaman/Kredit", "c. Pemantauan Status Pengajuan Produk secara langsung di aplikasi"]},
        {"text": "4. Keamanan & Pengaturan Akun meliputi:", "items": ["a. Pengikatan Perangkat Tunggal (Single Hardware Device Binding)", "b. Perlindungan Data Identitas dengan Verifikasi PIN 6 Digit", "c. Pengaturan Kata Sandi Login, PIN 6 Digit, dan Pusat Bantuan Resmi"]}
      ]
    },
    {
      "heading": "II. Manfaat & Keuntungan",
      "blocks": [
        {"text": "1. Kemudahan memantau rekening tabungan, deposito, dan pinjaman 24/7 di mana saja dan kapan saja tanpa perlu antre di kantor cabang."},
        {"text": "2. Perlindungan keamanan bertingkat dengan enkripsi data AES-256 dan pengikatan perangkat tunggal (Single Device Binding)."},
        {"text": "3. Suku bunga tabungan dan deposito kompetitif serta dijamin oleh Lembaga Penjamin Simpanan (LPS) sesuai ketentuan yang berlaku."},
        {"text": "4. Bebas biaya administrasi bulanan untuk penggunaan fasilitas layanan DMB Mobile."}
      ]
    },
    {
      "heading": "III. Biaya Layanan",
      "blocks": [
        {"text": "1. Struktur Biaya Layanan DMB Mobile:", "items": ["a. Biaya Pendaftaran & Aktivasi Aplikasi: Gratis (Rp 0)", "b. Biaya Administrasi Bulanan DMB Mobile: Gratis (Rp 0)", "c. Biaya Informasi Saldo & Mutasi Rekening: Gratis (Rp 0)", "d. Biaya Pengiriman OTP dan Data Internet: Mengikuti kebijakan tarif masing-masing operator seluler"]}
      ]
    },
    {
      "heading": "IV. Syarat & Ketentuan Penggunaan",
      "blocks": [
        {"text": "1. Kepesertaan: Nasabah wajib memiliki rekening aktif di PT BPR Dana Mandiri Bogor dan nomor telepon seluler aktif yang terdaftar di sistem Bank."},
        {"text": "2. Kerahasiaan Akses: Nasabah bertanggung jawab penuh atas kerahasiaan Kata Sandi, PIN 6 digit, dan Kode OTP. Petugas Bank DMB TIDAK PERNAH meminta data rahasia tersebut."},
        {"text": "3. Larangan Perangkat Dimodifikasi: Nasabah dilarang menggunakan DMB Mobile pada perangkat yang sistem operasinya telah dimodifikasi (Root / Jailbreak) demi menjaga keamanan data nasabah."},
        {"text": "4. Otorisasi Elektronik (UU ITE): Setiap aktivitas dan pengajuan yang diotorisasi dengan Kata Sandi, PIN, atau OTP yang sah tercatat sebagai bukti elektronik yang mengikat secara hukum."},
        {"text": "5. Pemblokiran Akun Otomatis: Akses akun akan dikunci otomatis apabila salah memasukkan Kata Sandi atau PIN melampaui batas percobaan maksimum untuk mencegah penyalahgunaan."}
      ]
    },
    {
      "heading": "V. Pelindungan Data Pribadi (UU No. 27 Tahun 2022)",
      "blocks": [
        {"text": "1. Bank memproses data pribadi nasabah semata-mata untuk verifikasi identitas, keamanan perangkat, dan penyediaan layanan perbankan."},
        {"text": "2. Data pribadi sensitif nasabah disimpan terenkripsi dengan standar AES-256-GCM dan ditransmisikan melalui jalur terenkripsi TLS."},
        {"text": "3. Bank berkomitmen penuh tidak membagikan atau mengalihkan data nasabah kepada pihak ketiga tanpa persetujuan eksplisit nasabah atau perintah peraturan perundang-undangan yang sah."}
      ]
    },
    {
      "heading": "VI. Layanan Pengaduan Konsumen & Penyelesaian Sengketa",
      "blocks": [
        {"text": "1. Layanan pengaduan resmi Bank DMB dapat dihubungi melalui Call Center (0251) 832-1234, WhatsApp 0811-9988-7766, atau Kantor Cabang PT BPR Dana Mandiri Bogor."},
        {"text": "2. Nasabah berhak menyampaikan sengketa kepada Lembaga Alternatif Penyelesaian Sengketa Sektor Jasa Keuangan (LAPS SJK) atau Otoritas Jasa Keuangan (OJK)."}
      ]
    }
  ],
  "consent_heading": "Persetujuan Layanan Nasabah",
  "consent_instruction": "Silakan centang satu per satu seluruh poin persetujuan di bawah ini untuk melanjutkan:",
  "consent_statements": [
    "Saya telah membaca, memahami, dan menyetujui seluruh isi Syarat & Ketentuan Layanan DMB Mobile PT BPR Dana Mandiri Bogor.",
    "Saya menyetujui Pemrosesan Data Pribadi (UU PDP No. 27/2022) untuk keperluan layanan perbankan dan verifikasi keamanan akun.",
    "Saya menyatakan bahwa data yang didaftarkan adalah benar milik saya, serta saya bertanggung jawab penuh menjaga kerahasiaan Kata Sandi, PIN, dan Kode OTP saya."
  ]
}$sk$::jsonb AS content) c
WHERE document_id = 'MOBILE_BANKING_TERMS' AND version_number = 1 AND status = 'DRAFT';
