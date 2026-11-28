-- 0028_rebrand_bank_dmb.sql
-- Memperbarui default nama & identitas resmi dari PT BPR Dana Mandiri Bogor menjadi Bank DMB
-- serta menyelaraskan konten bawaan Onboarding & Tentang DMB saat setup awal / migrasi.

UPDATE app_configs
SET bank_name        = 'BANK DMB',
    welcome_title    = 'Selamat Datang di Bank DMB',
    welcome_subtitle = 'Transaksi mudah, aman, dan tepercaya bersama Bank DMB'
WHERE id = 'DEFAULT'
  AND (bank_name ILIKE '%Dana Mandiri Bogor%' OR welcome_subtitle ILIKE '%Dana Mandiri Bogor%');

UPDATE mobile_content_items
SET value = 'Bank DMB berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).'
WHERE key = 'app.footer' AND value ILIKE '%Dana Mandiri Bogor%';

UPDATE mobile_content_items
SET value = 'Selamat datang di Bank DMB'
WHERE key = 'onboarding.title' AND value = 'Solusi Finansial Terpercaya untuk Keluarga & UMKM';

UPDATE mobile_content_items
SET value = 'Ringkasan Informasi dan Syarat Ketentuan Mobile Banking Bank DMB'
WHERE key = 'terms.headline' AND value ILIKE '%Dana Mandiri Bogor%';

UPDATE mobile_content_items
SET value = 'Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan Mobile Banking Bank DMB.'
WHERE key = 'terms.instruction' AND value ILIKE '%Dana Mandiri Bogor%';

UPDATE mobile_content_items
SET value = 'Bank DMB berawal di Bogor sebagai BPR yang melayani pedagang pasar dan pengusaha mikro. Fokus kami tetap sama hingga kini: Akses modal usaha yang mudah dan simpanan yang aman, diawasi OJK dan dijamin LPS.'
WHERE key = 'company.about_description';

UPDATE mobile_content_items
SET value = 'Menjadi penyedia layanan keuangan mikro yang terpercaya bagi bangsa, menjadikan kehidupan dan masa depan yang lebih baik.'
WHERE key = 'company.vision';

UPDATE mobile_content_items
SET value = 'Menjadi mitra pilihan bagi micro-productive segmen yang menjunjung nilai-nilai organisasi dalam memberikan kualitas pelayanan yang handal dan secara bersama menciptakan kesempatan tumbuh dan berkembang.'
WHERE key = 'company.mission';
