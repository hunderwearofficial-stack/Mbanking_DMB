-- 0007 add dynamic branding, copywriting and document URLs for Server-Driven mobile CMS
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS login_bg_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS welcome_title character varying(150) DEFAULT 'Selamat Datang di DMB Mobile';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS welcome_subtitle character varying(255) DEFAULT 'Transaksi mudah, aman, dan tepercaya bersama BPR Dana Mandiri Bogor';
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS announcement_text text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS terms_pdf_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS privacy_pdf_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS quick_menu_config text;
