-- Rollback 0021: Schema cleanup and alignment.
-- Manual only, run with migration owner role.
BEGIN;

DROP INDEX IF EXISTS idx_users_username_lower;

ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_rebound_at timestamptz;

ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS min_transfer_amount numeric(15,2) DEFAULT 10000;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS daily_transfer_limit numeric(15,2) DEFAULT 25000000;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS interbank_transfer_fee numeric(15,2) DEFAULT 2500;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS fcm_server_key text;

CREATE TABLE IF NOT EXISTS saved_beneficiaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    user_id character varying(60) NOT NULL,
    bank_code character varying(20) DEFAULT 'BPR'::character varying,
    bank_name character varying(100) DEFAULT 'Bank DMB'::character varying,
    account_number character varying(100) NOT NULL,
    account_name character varying(100) NOT NULL,
    nickname character varying(60),
    created_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id),
    from_account character varying(100) NOT NULL,
    to_account character varying(100) NOT NULL,
    amount numeric(15,2) NOT NULL,
    transaction_type character varying(30) NOT NULL,
    status character varying(20) NOT NULL,
    cbs_ref_no character varying(50),
    created_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS transfer_requests (
    id uuid NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL,
    idempotency_key character varying(80) NOT NULL,
    request_hash character varying(64) NOT NULL,
    from_account character varying(100) NOT NULL,
    to_account character varying(100) NOT NULL,
    to_bank_code character varying(20),
    amount numeric(15,2) NOT NULL,
    status character varying(20) NOT NULL,
    cbs_reference_no character varying(60),
    response_json text,
    failure_reason character varying(255),
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);

DELETE FROM schema_migrations WHERE version = 21;
COMMIT;
