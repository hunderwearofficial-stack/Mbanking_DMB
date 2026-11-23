-- 0015 Device attestation, App Attest keys and signed sensitive operations
-- (audit DB-H6, DB-M4). Additive and backward compatible:
--   * existing keys keep working and are marked UNVERIFIED (no attestation was checked);
--   * new columns are nullable or have defaults; no row is rewritten except the default;
--   * CHECK constraints are only widened (new algorithm / purposes).
-- Rollback: pkg/database/rollback/0015_device_attestation_down.sql.

ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS attestation_status character varying(20) NOT NULL DEFAULT 'UNVERIFIED';
ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS attestation_summary character varying(200);
ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS attestation_checked_at timestamptz;
-- App Attest: Apple key identifier (base64 of sha256(public key)) and assertion counter.
ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS app_attest_key_id character varying(64);
ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS sign_count bigint NOT NULL DEFAULT 0;

ALTER TABLE device_keys DROP CONSTRAINT IF EXISTS device_keys_attestation_status_check;
ALTER TABLE device_keys ADD CONSTRAINT device_keys_attestation_status_check
    CHECK (attestation_status IN ('HARDWARE_VERIFIED', 'UNVERIFIED', 'FAILED'));
ALTER TABLE device_keys DROP CONSTRAINT IF EXISTS device_keys_sign_count_check;
ALTER TABLE device_keys ADD CONSTRAINT device_keys_sign_count_check CHECK (sign_count >= 0 AND sign_count <= 4294967295);
ALTER TABLE device_keys DROP CONSTRAINT IF EXISTS device_keys_algorithm_check;
ALTER TABLE device_keys ADD CONSTRAINT device_keys_algorithm_check CHECK (algorithm IN ('ES256', 'APPATTEST'));
ALTER TABLE device_keys DROP CONSTRAINT IF EXISTS device_keys_appattest_check;
ALTER TABLE device_keys ADD CONSTRAINT device_keys_appattest_check
    CHECK ((algorithm = 'APPATTEST') = (app_attest_key_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_keys_app_attest_key ON device_keys (app_attest_key_id) WHERE app_attest_key_id IS NOT NULL;

-- Signed sensitive operations besides login/refresh/transfer.
ALTER TABLE device_challenges DROP CONSTRAINT IF EXISTS device_challenges_purpose_check;
ALTER TABLE device_challenges ADD CONSTRAINT device_challenges_purpose_check
    CHECK (purpose IN ('LOGIN', 'REFRESH', 'ENROLL', 'ROTATE', 'TRANSFER', 'CHANGE_PIN', 'CHANGE_PASSWORD'));
