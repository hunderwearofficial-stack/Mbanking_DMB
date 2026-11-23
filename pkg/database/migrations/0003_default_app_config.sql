-- 0003 default operational configuration row.
-- Only operational defaults. Contact data, banners and interest-rate claims are NOT
-- inserted: authorised officers must enter the bank's official data via the console.
INSERT INTO app_configs (
  id, bank_name, bank_short_name, tagline, logo_url,
  maintenance_mode, maintenance_message,
  min_transfer_amount, daily_transfer_limit, interbank_transfer_fee,
  enforce_device_binding, max_login_attempts, otp_provider, updated_at
) VALUES (
  'DEFAULT', 'PT BPR DANA MANDIRI BOGOR', 'Bank DMB', 'Mitra Terpercaya Menuju Sejahtera', '/admin/images/bank_logo.png',
  false, 'Sistem sedang dalam peningkatan layanan berkala.',
  10000.00, 25000000.00, 2500.00,
  true, 3, 'SANDBOX', now()
) ON CONFLICT (id) DO NOTHING;
