-- 0008 versioned legal documents (Syarat dan Ketentuan), recorded customer consent,
-- versioned mobile content (draft → published → archived) and the app_configs columns
-- used by the mobile content model that earlier migrations never created.
-- Additive only: no existing table, column or row is dropped or rewritten.

-- 1. app_configs columns referenced by internal/model.AppConfig but missing from 0001/0007.
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS splash_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS onboarding_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_title character varying(150);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_subtitle character varying(255);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS terms_version character varying(50);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS home_greeting character varying(150);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS content_version integer NOT NULL DEFAULT 0;

-- 2. Immutable file storage (content-addressed by SHA-256). PDFs are kept in the
--    database so they are covered by the regular database backup together with their
--    metadata; no filesystem path is ever exposed to clients.
CREATE TABLE IF NOT EXISTS stored_files (
    sha256 character(64) PRIMARY KEY,
    content_type character varying(100) NOT NULL,
    size_bytes integer NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 10485760),
    content bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (sha256 ~ '^[0-9a-f]{64}$')
);

CREATE OR REPLACE FUNCTION stored_files_block_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'stored_files bersifat immutable: % tidak diizinkan', TG_OP;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_stored_files_immutable ON stored_files;
CREATE TRIGGER trg_stored_files_immutable BEFORE UPDATE OR DELETE ON stored_files
  FOR EACH ROW EXECUTE FUNCTION stored_files_block_mutation();

-- 3. Legal documents and their versions.
CREATE TABLE IF NOT EXISTS legal_documents (
    id character varying(50) PRIMARY KEY,
    title character varying(200) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS legal_document_versions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    document_id character varying(50) NOT NULL REFERENCES legal_documents(id),
    version_number integer NOT NULL CHECK (version_number > 0),
    status character varying(20) NOT NULL
        CHECK (status IN ('DRAFT','PENDING_APPROVAL','PUBLISHED','ARCHIVED')),
    document_number character varying(100),
    change_summary text,
    content jsonb NOT NULL,
    content_sha256 character(64) NOT NULL,
    draft_pdf_sha256 character(64) REFERENCES stored_files(sha256),
    pdf_sha256 character(64) REFERENCES stored_files(sha256),
    effective_from timestamptz,
    created_by character varying(60) NOT NULL,
    created_by_name character varying(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    submitted_by character varying(60),
    submitted_at timestamptz,
    approved_by character varying(60),
    approved_by_name character varying(100),
    published_at timestamptz,
    archived_by character varying(60),
    archived_at timestamptz,
    UNIQUE (document_id, version_number),
    CHECK (status <> 'PUBLISHED' OR (pdf_sha256 IS NOT NULL AND effective_from IS NOT NULL AND published_at IS NOT NULL AND approved_by IS NOT NULL)),
    CHECK (approved_by IS NULL OR approved_by <> created_by)
);

-- Only one draft / pending version per document at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_legal_versions_one_open
    ON legal_document_versions (document_id) WHERE status IN ('DRAFT','PENDING_APPROVAL');
CREATE INDEX IF NOT EXISTS idx_legal_versions_active
    ON legal_document_versions (document_id, effective_from DESC, version_number DESC) WHERE status = 'PUBLISHED';

-- Published and archived versions are immutable. The only change allowed after
-- publication is PUBLISHED → ARCHIVED (recording who archived it and when).
CREATE OR REPLACE FUNCTION legal_versions_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'versi dokumen berstatus % tidak boleh dihapus', OLD.status;
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'versi dokumen yang diarsipkan tidak boleh diubah';
  END IF;
  IF OLD.status = 'PUBLISHED' THEN
    IF NEW.status <> 'ARCHIVED'
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
       OR NEW.pdf_sha256 IS DISTINCT FROM OLD.pdf_sha256
       OR NEW.draft_pdf_sha256 IS DISTINCT FROM OLD.draft_pdf_sha256
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.document_number IS DISTINCT FROM OLD.document_number
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.published_at IS DISTINCT FROM OLD.published_at
       OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.archived_by IS NULL OR NEW.archived_at IS NULL THEN
      RAISE EXCEPTION 'versi dokumen yang sudah diterbitkan tidak boleh diubah (hanya dapat diarsipkan)';
    END IF;
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by OR NEW.version_number IS DISTINCT FROM OLD.version_number
     OR NEW.document_id IS DISTINCT FROM OLD.document_id THEN
    RAISE EXCEPTION 'identitas versi dokumen tidak boleh diubah';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_legal_versions_guard ON legal_document_versions;
CREATE TRIGGER trg_legal_versions_guard BEFORE UPDATE OR DELETE ON legal_document_versions
  FOR EACH ROW EXECUTE FUNCTION legal_versions_guard();

-- 4. Consent records (append-only). A PRE_LOGIN record is made on the device before the
--    customer is identified; on login/activation it is linked to the customer through a
--    separate record (channel LOGIN / ACTIVATION / REFRESH is never used for linking).
CREATE TABLE IF NOT EXISTS legal_acceptances (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    document_id character varying(50) NOT NULL REFERENCES legal_documents(id),
    version_id uuid NOT NULL REFERENCES legal_document_versions(id),
    version_number integer NOT NULL,
    user_id uuid REFERENCES users(id),
    device_id character varying(128) NOT NULL,
    channel character varying(20) NOT NULL CHECK (channel IN ('PRE_LOGIN','LOGIN','ACTIVATION')),
    status character varying(20) NOT NULL DEFAULT 'ACCEPTED' CHECK (status = 'ACCEPTED'),
    pre_login_acceptance_id uuid REFERENCES legal_acceptances(id),
    pdf_sha256 character(64) NOT NULL,
    accepted_at timestamptz NOT NULL DEFAULT now(),
    ip_address character varying(64),
    user_agent character varying(255),
    CHECK ((channel = 'PRE_LOGIN') = (user_id IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_legal_acceptances_user_version
    ON legal_acceptances (version_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_legal_acceptances_prelogin_link
    ON legal_acceptances (pre_login_acceptance_id) WHERE pre_login_acceptance_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_legal_acceptances_device
    ON legal_acceptances (device_id, version_id, accepted_at DESC) WHERE user_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_legal_acceptances_user ON legal_acceptances (user_id, accepted_at DESC);

CREATE OR REPLACE FUNCTION legal_acceptances_block_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'legal_acceptances bersifat append-only: % tidak diizinkan', TG_OP;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_legal_acceptances_append_only ON legal_acceptances;
CREATE TRIGGER trg_legal_acceptances_append_only BEFORE UPDATE OR DELETE ON legal_acceptances
  FOR EACH ROW EXECUTE FUNCTION legal_acceptances_block_mutation();
DROP TRIGGER IF EXISTS trg_legal_acceptances_no_truncate ON legal_acceptances;
CREATE TRIGGER trg_legal_acceptances_no_truncate BEFORE TRUNCATE ON legal_acceptances
  FOR EACH STATEMENT EXECUTE FUNCTION legal_acceptances_block_mutation();

-- 5. Versioned mobile content (texts/images actually rendered by the Flutter app).
CREATE TABLE IF NOT EXISTS mobile_content_revisions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    version_number integer NOT NULL UNIQUE CHECK (version_number > 0),
    status character varying(20) NOT NULL CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
    content jsonb NOT NULL,
    note text,
    source_revision_id uuid REFERENCES mobile_content_revisions(id),
    created_by character varying(60) NOT NULL,
    created_by_name character varying(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    published_by character varying(60),
    published_by_name character varying(100),
    published_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mobile_content_one_draft
    ON mobile_content_revisions ((true)) WHERE status = 'DRAFT';
CREATE UNIQUE INDEX IF NOT EXISTS uq_mobile_content_one_published
    ON mobile_content_revisions ((true)) WHERE status = 'PUBLISHED';

CREATE OR REPLACE FUNCTION mobile_content_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'revisi konten berstatus % tidak boleh dihapus', OLD.status;
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status <> 'DRAFT' AND (NEW.content IS DISTINCT FROM OLD.content
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.published_at IS DISTINCT FROM OLD.published_at
       OR (OLD.status = 'ARCHIVED')
       OR (OLD.status = 'PUBLISHED' AND NEW.status <> 'ARCHIVED')) THEN
    RAISE EXCEPTION 'revisi konten yang sudah diterbitkan tidak boleh diubah';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_mobile_content_guard ON mobile_content_revisions;
CREATE TRIGGER trg_mobile_content_guard BEFORE UPDATE OR DELETE ON mobile_content_revisions
  FOR EACH ROW EXECUTE FUNCTION mobile_content_guard();

-- 6. The mobile banking Terms and Conditions document and the CURRENT in-app text as
--    version 1 (DRAFT). The text is migrated verbatim from the app screen
--    (m_banking_bpr/lib/presentation/screens/auth/terms_conditions_screen.dart) with the
--    contact numbers that screen displayed (lib/core/constants/bank_contact.dart).
--    It is NOT published automatically: an authorised officer must review it, generate
--    the PDF and submit it, and a second officer must approve it (maker-checker).
INSERT INTO legal_documents (id, title)
VALUES ('MOBILE_BANKING_TERMS', 'Syarat dan Ketentuan Layanan Mobile Banking')
ON CONFLICT (id) DO NOTHING;

INSERT INTO legal_document_versions (document_id, version_number, status, change_summary, content, content_sha256, created_by, created_by_name)
SELECT 'MOBILE_BANKING_TERMS', 1, 'DRAFT',
       'Migrasi apa adanya dari teks Syarat & Ketentuan yang sebelumnya ditanam di aplikasi (belum ditinjau bank).',
       c.content, encode(sha256(convert_to(c.content::text, 'UTF8')), 'hex'),
       'SYSTEM_MIGRATION', 'Migrasi 0008'
FROM (SELECT $sk${
  "title": "Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor",
  "date_note": "Diperbarui pada 10 November 2026",
  "intro": "Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor.",
  "sections": [
    {
      "heading": "Ringkasan Informasi Produk dan Layanan (RIPLAY) Versi Personal",
      "fields": [
        {"label": "Nama Penerbit", "value": "PT BPR Dana Mandiri Bogor"},
        {"label": "Nama Produk", "value": "DMB Mobile"},
        {"label": "Jenis Produk", "value": "Mobile Banking"},
        {"label": "Deskripsi", "value": "Fasilitas elektronik channel yang disediakan oleh Bank serta dapat diakses dan digunakan oleh Nasabah untuk melakukan Transaksi Finansial dan/atau Non-Finansial melalui Smartphone."}
      ]
    },
    {
      "heading": "I. Fitur Utama",
      "blocks": [
        {"text": "1. Pembukaan & Pengelolaan Rekening Simpanan meliputi:", "items": ["a. Tabungan DMB Utama", "b. Tabungan Mandiri Masa Depan", "c. Tabungan Simpanan Pelajar (SimPel)", "d. Deposito Berjangka DMB", "e. Tabungan Rencana Impian"]},
        {"text": "2. Transaksi Finansial & Pembayaran meliputi:", "items": ["a. Transfer Antar Rekening Bank DMB", "b. Transfer Online Antar Bank Nasional & BI-FAST", "c. Pembayaran Tagihan Rutin (PLN, PDAM, BPJS Kesehatan)", "d. Pembelian Pulsa, Paket Data & Token Listrik", "e. Top Up Dompet Digital (GoPay, OVO, Dana, ShopeePay)"]},
        {"text": "3. Pengajuan Produk Pinjaman & Kredit meliputi:", "items": ["a. Kredit Modal Kerja UMKM", "b. Kredit Konsumtif & Multiguna", "c. Kredit Pegawai & Payroll"]},
        {"text": "4. Layanan Informasi & Pengaturan Akun meliputi:", "items": ["a. Informasi Saldo Real-Time 24 Jam", "b. Riwayat Mutasi Rekening & E-Statement", "c. Single Hardware Device Binding Security", "d. Pembaruan Profil & Ubah PIN Transaksi"]}
      ]
    },
    {
      "heading": "II. Manfaat & Keuntungan",
      "blocks": [
        {"text": "1. Kemudahan bertransaksi 24/7 di mana saja dan kapan saja tanpa perlu antre di kantor cabang."},
        {"text": "2. Perlindungan keamanan bertingkat dengan enkripsi data AES-256 dan pengikatan perangkat tunggal (Single Device Binding)."},
        {"text": "3. Suku bunga tabungan dan deposito kompetitif serta dijamin oleh Lembaga Penjamin Simpanan (LPS) sesuai ketentuan yang berlaku."},
        {"text": "4. Bebas biaya administrasi bulanan untuk pengelolaan rekening mobile banking DMB Mobile."}
      ]
    },
    {
      "heading": "III. Biaya Layanan & Batas Limit Transaksi",
      "blocks": [
        {"text": "1. Struktur Biaya Transaksi:", "items": ["a. Biaya Administrasi Bulanan Mobile Banking: Gratis (Rp 0)", "b. Transfer Antar-Rekening Bank DMB: Gratis (Rp 0)", "c. Transfer Antar-Bank Online: Sesuai tarif switching nasional", "d. Biaya SMS OTP: Mengikuti tarif resmi masing-masing operator seluler"]},
        {"text": "2. Batas Limit Transaksi Harian (Harian Per Akun):", "items": ["a. Transfer Antar-Rekening DMB: Maksimal Rp 50.000.000 / hari", "b. Transfer Antar-Bank Online: Maksimal Rp 25.000.000 / hari", "c. Pembayaran & Pembelian: Maksimal Rp 10.000.000 / hari"]}
      ]
    },
    {
      "heading": "IV. Syarat & Ketentuan Penggunaan",
      "blocks": [
        {"text": "1. Kepesertaan: Nasabah wajib memiliki rekening simpanan aktif di PT BPR Dana Mandiri Bogor dan nomor telepon seluler aktif terverifikasi."},
        {"text": "2. Kerahasiaan Akses: Nasabah bertanggung jawab penuh atas kerahasiaan Kata Sandi, PIN 6 digit, dan Kode OTP. Petugas Bank DMB TIDAK PERNAH meminta data rahasia tersebut."},
        {"text": "3. Larangan Perangkat Root/Jailbreak: Nasabah dilarang menginstal DMB Mobile pada smartphone yang sistem operasinya telah dimodifikasi (Root / Jailbreak) demi menjaga keamanan dari malware."},
        {"text": "4. Otorisasi Hukum (UU ITE): Setiap instruksi transaksi yang diotorisasi dengan PIN/OTP yang sah bersifat final, mengikat secara hukum, dan diakui sebagai alat bukti yang sah di pengadilan."},
        {"text": "5. Pemblokiran Akun: Akses akun akan diblokir otomatis apabila salah memasukkan PIN sebanyak 3 (tiga) kali berturut-turut untuk mencegah tindak kejahatan."}
      ]
    },
    {
      "heading": "V. Pelindungan Data Pribadi (UU No. 27 Tahun 2022)",
      "blocks": [
        {"text": "1. Bank memproses data pribadi nasabah semata-mata untuk verifikasi identitas, mitigasi risiko fraud, dan pelaksanaan layanan perbankan."},
        {"text": "2. Data nasabah disimpan dalam Data Center domestik di Indonesia dengan standar enkripsi militer AES-256 dan protokol TLS 1.3."},
        {"text": "3. Bank berkomitmen penuh tidak membagikan atau mengalihkan data nasabah kepada pihak ketiga tanpa persetujuan eksplisit nasabah atau perintah regulator perbankan yang sah."}
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
    "Saya menyetujui Pemrosesan Data Pribadi (UU PDP No. 27/2022) untuk keperluan transaksi perbankan dan verifikasi layanan.",
    "Saya menyatakan bahwa data yang didaftarkan adalah benar milik saya, serta saya bertanggung jawab penuh menjaga kerahasiaan Kata Sandi, PIN, dan Kode OTP saya."
  ]
}$sk$::jsonb AS content) c
WHERE NOT EXISTS (SELECT 1 FROM legal_document_versions WHERE document_id = 'MOBILE_BANKING_TERMS');
