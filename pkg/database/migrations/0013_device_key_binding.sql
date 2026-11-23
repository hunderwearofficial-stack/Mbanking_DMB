-- 0013 Cryptographic device binding (audit DID-04, DID-09).
--
-- Backward compatible and additive:
--   * existing bindings (users.device_id) are NOT modified: legacy identifiers keep
--     working until the device enrolls a hardware-backed key;
--   * device_id columns are widened to one consistent length (128); widening a
--     varchar is a metadata-only change and never rewrites or truncates data;
--   * new tables hold only PUBLIC keys and single-use challenges. Private keys never
--     leave the device (Android Keystore / iOS Secure Enclave).
-- Rollback: pkg/database/rollback/0013_0014_device_key_binding_down.sql (see
-- docs/OPERATIONS_AND_BACKUP.md).

-- 1. One consistent device identifier length (was 100 / 120 / 128).
ALTER TABLE users         ALTER COLUMN device_id TYPE character varying(128);
ALTER TABLE user_sessions ALTER COLUMN device_id TYPE character varying(128);
ALTER TABLE audit_logs    ALTER COLUMN device_id TYPE character varying(128);

-- 2. Enrollment window opened by an OTP-verified (re)binding: activation or
--    Lupa Password. NULL = no window.
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_enroll_until timestamptz;

-- 3. Device public keys (ES256 = ECDSA P-256 / SHA-256). At most one ACTIVE key per
--    customer, matching the single-bound-device policy.
CREATE TABLE IF NOT EXISTS device_keys (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id),
    device_id character varying(128) NOT NULL,
    platform character varying(10) NOT NULL CHECK (platform IN ('android', 'ios')),
    algorithm character varying(16) NOT NULL DEFAULT 'ES256' CHECK (algorithm = 'ES256'),
    public_key text NOT NULL,                       -- SubjectPublicKeyInfo DER, base64 (public data)
    key_fingerprint character(64) NOT NULL,         -- SHA-256 hex of the SPKI DER
    security_level character varying(20) NOT NULL
        CHECK (security_level IN ('STRONGBOX', 'TEE', 'SECURE_ENCLAVE')),
    status character varying(10) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ROTATED', 'REVOKED')),
    enrolled_via character varying(24) NOT NULL
        CHECK (enrolled_via IN ('LEGACY_MIGRATION', 'OTP_ENROLLMENT', 'SESSION_ENROLLMENT', 'ROTATION')),
    previous_device_id character varying(128),      -- legacy identifier replaced at migration
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    revoked_at timestamptz,
    revoked_reason character varying(40),
    CHECK (status = 'ACTIVE' OR revoked_at IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_keys_fingerprint ON device_keys (key_fingerprint);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_keys_active_user ON device_keys (user_id) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_device_keys_user ON device_keys (user_id, created_at DESC);

-- 4. Single-use challenges. A challenge is bound to purpose, customer, device, key
--    (or the key being enrolled), a random nonce and an expiry. used_at is set
--    atomically on first use; a second use is a replay.
CREATE TABLE IF NOT EXISTS device_challenges (
    id uuid PRIMARY KEY,
    purpose character varying(16) NOT NULL
        CHECK (purpose IN ('LOGIN', 'REFRESH', 'ENROLL', 'ROTATE', 'TRANSFER')),
    user_id uuid REFERENCES users(id),              -- NULL = decoy for an unknown identifier
    device_id character varying(128) NOT NULL,
    key_id uuid REFERENCES device_keys(id),
    key_fingerprint character(64),
    nonce character varying(64) NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_ip character varying(64),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_challenges_expires ON device_challenges (expires_at);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE ON device_keys, device_challenges TO mbanking_app;
  END IF;
END $$;
