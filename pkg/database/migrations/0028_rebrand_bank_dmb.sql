-- 0028_rebrand_bank_dmb.sql
-- Memperbarui default nama & identitas resmi dari PT BPR Dana Mandiri Bogor menjadi Bank DMB
-- pada app_configs saat setup awal / migrasi. Konten mobile bawaan (versi 0) mengikuti
-- internal/mobilecontent/registry.go secara langsung.

UPDATE app_configs
SET bank_name        = 'BANK DMB',
    welcome_title    = 'Selamat Datang di Bank DMB',
    welcome_subtitle = 'Transaksi mudah, aman, dan tepercaya bersama Bank DMB'
WHERE id = 'DEFAULT'
  AND (bank_name ILIKE '%Dana Mandiri Bogor%' OR welcome_subtitle ILIKE '%Dana Mandiri Bogor%');
