-- 0019 Backoffice security and governance (audit E-01, E-03, E-07, E-08, H-3). Additive only:
-- no column or table is dropped and no existing data is rewritten.
-- Rollback: pkg/database/rollback/0019_backoffice_security_down.sql.

-- Officer MFA (TOTP, RFC 6238) and per-account lockout. totp_secret is AES-GCM encrypted
-- by the application (pkg/crypto).
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS totp_secret text;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS totp_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS totp_last_step bigint NOT NULL DEFAULT 0;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS failed_login_attempts integer NOT NULL DEFAULT 0;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS locked_until timestamptz;

-- The OTP gateway token is now stored AES-GCM encrypted (longer than 255 characters).
-- Widening only; existing plaintext values stay readable and are encrypted on next save.
ALTER TABLE app_configs ALTER COLUMN otp_gateway_token TYPE text;

-- Maker-checker for sensitive backoffice actions. payload is AES-GCM encrypted because a
-- security configuration change may carry the OTP gateway token.
CREATE TABLE IF NOT EXISTS approval_requests (
    id                uuid PRIMARY KEY,
    kind              varchar(40)  NOT NULL,
    target_id         varchar(64)  NOT NULL DEFAULT '',
    summary           text         NOT NULL DEFAULT '',
    payload           text         NOT NULL DEFAULT '',
    status            varchar(20)  NOT NULL DEFAULT 'PENDING',
    requested_by      varchar(64)  NOT NULL,
    requested_by_name varchar(120) NOT NULL DEFAULT '',
    requested_by_role varchar(30)  NOT NULL DEFAULT '',
    requested_at      timestamptz  NOT NULL DEFAULT now(),
    decided_by        varchar(64),
    decided_by_name   varchar(120),
    decided_at        timestamptz,
    decision_note     text,
    CONSTRAINT approval_requests_status_check CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'FAILED')),
    CONSTRAINT approval_requests_kind_check CHECK (kind IN ('CONFIG_SECURITY', 'DEVICE_RESET', 'CUSTOMER_UNBLOCK', 'BANNER_PUBLISH'))
);
CREATE INDEX IF NOT EXISTS idx_approval_requests_status ON approval_requests (status, requested_at DESC);
-- One pending request per kind and target: the checker queue cannot be flooded.
CREATE UNIQUE INDEX IF NOT EXISTS idx_approval_requests_pending_target
    ON approval_requests (kind, target_id) WHERE status = 'PENDING';

-- Customer search in the backoffice: prefix search on phone number / CIF uses an index.
CREATE INDEX IF NOT EXISTS idx_users_phone_prefix ON users (phone_number varchar_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_users_cif_prefix ON users (cif varchar_pattern_ops);
