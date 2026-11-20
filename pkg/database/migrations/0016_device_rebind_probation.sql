-- 0016 Post re-binding probation and signed beneficiary changes (residual risks of the
-- device binding review: OTP / SIM-swap takeover, stolen session tokens). Additive.
-- Rollback: pkg/database/rollback/0016_device_rebind_probation_down.sql.

-- Time of the last OTP-verified (re)binding: transfers are capped for
-- DEVICE_REBIND_PROBATION_HOURS afterwards.
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_rebound_at timestamptz;

ALTER TABLE device_challenges DROP CONSTRAINT IF EXISTS device_challenges_purpose_check;
ALTER TABLE device_challenges ADD CONSTRAINT device_challenges_purpose_check
    CHECK (purpose IN ('LOGIN', 'REFRESH', 'ENROLL', 'ROTATE', 'TRANSFER', 'CHANGE_PIN', 'CHANGE_PASSWORD',
                       'BENEFICIARY_SAVE', 'BENEFICIARY_DELETE'));
