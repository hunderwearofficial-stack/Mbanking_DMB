-- Rollback 0022/0023/0024 (run with the schema owner role, after 0025_admin_password_lifecycle_down.sql).
-- 0023 only contains GRANT/REVOKE and needs no schema rollback. 0020 is not touched: it
-- belongs to 0019_backoffice_security_down.sql.
BEGIN;

-- 0024 -> constraints as defined by 0019 / 0021. NOT VALID keeps rows written meanwhile
-- (e.g. ADMIN_MANAGE approval history, kept as audit evidence) while new rows are checked;
-- a plain ADD CONSTRAINT would fail on them and abort the rollback (audit MA-18).
ALTER TABLE approval_requests DROP CONSTRAINT IF EXISTS approval_requests_kind_check;
ALTER TABLE approval_requests
  ADD CONSTRAINT approval_requests_kind_check CHECK (
    kind IN ('CONFIG_SECURITY', 'DEVICE_RESET', 'CUSTOMER_UNBLOCK', 'BANNER_PUBLISH')
  ) NOT VALID;

ALTER TABLE device_challenges DROP CONSTRAINT IF EXISTS device_challenges_purpose_check;
ALTER TABLE device_challenges
  ADD CONSTRAINT device_challenges_purpose_check CHECK (
    purpose IN ('LOGIN', 'REFRESH', 'CHANGE_PASSWORD', 'CHANGE_PIN', 'PROFILE_REVEAL', 'ENROLL', 'ROTATE')
  ) NOT VALID;

-- 0022: extra encrypted columns (never read by the application; plaintext columns remain).
ALTER TABLE users
  DROP COLUMN IF EXISTS account_number_encrypted,
  DROP COLUMN IF EXISTS cif_encrypted;

DELETE FROM schema_migrations WHERE version IN (22, 23, 24);

COMMIT;
