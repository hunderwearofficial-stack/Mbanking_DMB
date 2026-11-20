-- Rollback 0019 + 0020. DESTRUCTIVE for the data held in these objects (approval history,
-- officer TOTP enrolment and lockout state): take a verified backup and get approval first.
-- otp_gateway_token stays `text` (narrowing could truncate encrypted values).
-- After running it, delete versions 0019 and 0020 from schema_migrations.
BEGIN;
DROP INDEX IF EXISTS idx_users_cif_prefix;
DROP INDEX IF EXISTS idx_users_phone_prefix;
DROP TABLE IF EXISTS approval_requests;
ALTER TABLE admin_users DROP COLUMN IF EXISTS locked_until;
ALTER TABLE admin_users DROP COLUMN IF EXISTS failed_login_attempts;
ALTER TABLE admin_users DROP COLUMN IF EXISTS totp_last_step;
ALTER TABLE admin_users DROP COLUMN IF EXISTS totp_enabled;
ALTER TABLE admin_users DROP COLUMN IF EXISTS totp_secret;
DELETE FROM schema_migrations WHERE version IN (19, 20);
COMMIT;
