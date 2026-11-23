-- 0001 baseline schema (DMB Mobile Banking).
-- Idempotent: creates missing tables/columns/indexes/constraints so that databases
-- created by the former GORM AutoMigrate are adopted without data loss.
-- Generated from the AutoMigrate schema of the models on 13-11-2026, then reviewed.

CREATE SEQUENCE IF NOT EXISTS audit_logs_seq_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    account_number character varying(30) NOT NULL,
    holder_name character varying(100),
    product_code character varying(20),
    account_type character varying(50) DEFAULT 'Savings'::character varying,
    balance numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    minimum_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    blocked_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    effective_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    status character varying(20) DEFAULT 'Active'::character varying,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT accounts_pkey PRIMARY KEY (id)
);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS account_number character varying(30);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS holder_name character varying(100);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS product_code character varying(20);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS account_type character varying(50) DEFAULT 'Savings'::character varying;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS balance numeric(15,2) DEFAULT '0'::numeric NOT NULL;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS minimum_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS blocked_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS effective_balance numeric(15,2) DEFAULT '0'::numeric NOT NULL;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS status character varying(20) DEFAULT 'Active'::character varying;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS admin_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username character varying(50) NOT NULL,
    full_name character varying(100) NOT NULL,
    email character varying(100),
    password_hash character varying(255) NOT NULL,
    role character varying(30) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT admin_users_pkey PRIMARY KEY (id)
);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS username character varying(50);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS full_name character varying(100);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS email character varying(100);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS password_hash character varying(255);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS role character varying(30);
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS app_configs (
    id character varying(50) DEFAULT 'DEFAULT'::character varying NOT NULL,
    bank_name character varying(120) DEFAULT 'PT BPR DANA MANDIRI BOGOR'::character varying,
    bank_short_name character varying(50) DEFAULT 'Bank DMB'::character varying,
    tagline character varying(255) DEFAULT 'Mitra Terpercaya Menuju Sejahtera'::character varying,
    logo_url text,
    call_center character varying(50),
    whats_app_cs character varying(50),
    email_cs character varying(100),
    website_url character varying(255),
    head_office_address text,
    maintenance_mode boolean DEFAULT false,
    maintenance_message character varying(255) DEFAULT 'Sistem sedang dalam peningkatan layanan berkala.'::character varying,
    min_transfer_amount numeric(15,2) DEFAULT '10000'::numeric,
    daily_transfer_limit numeric(15,2) DEFAULT '25000000'::numeric,
    interbank_transfer_fee numeric(15,2) DEFAULT '2500'::numeric,
    enforce_device_binding boolean DEFAULT true,
    max_login_attempts bigint DEFAULT 3,
    otp_provider character varying(40) DEFAULT 'SANDBOX'::character varying,
    otp_gateway_url character varying(255),
    otp_gateway_token character varying(255),
    fcm_server_key text,
    updated_at timestamp with time zone,
    CONSTRAINT app_configs_pkey PRIMARY KEY (id)
);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS id character varying(50) DEFAULT 'DEFAULT'::character varying NOT NULL;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS bank_name character varying(120) DEFAULT 'PT BPR DANA MANDIRI BOGOR'::character varying;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS bank_short_name character varying(50) DEFAULT 'Bank DMB'::character varying;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS tagline character varying(255) DEFAULT 'Mitra Terpercaya Menuju Sejahtera'::character varying;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS call_center character varying(50);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS whats_app_cs character varying(50);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS email_cs character varying(100);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS website_url character varying(255);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS head_office_address text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS maintenance_mode boolean DEFAULT false;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS maintenance_message character varying(255) DEFAULT 'Sistem sedang dalam peningkatan layanan berkala.'::character varying;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS min_transfer_amount numeric(15,2) DEFAULT '10000'::numeric;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS daily_transfer_limit numeric(15,2) DEFAULT '25000000'::numeric;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS interbank_transfer_fee numeric(15,2) DEFAULT '2500'::numeric;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS enforce_device_binding boolean DEFAULT true;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS max_login_attempts bigint DEFAULT 3;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS otp_provider character varying(40) DEFAULT 'SANDBOX'::character varying;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS otp_gateway_url character varying(255);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS otp_gateway_token character varying(255);
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS fcm_server_key text;
ALTER TABLE app_configs ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;
ALTER TABLE app_configs ALTER COLUMN call_center DROP DEFAULT;
ALTER TABLE app_configs ALTER COLUMN whats_app_cs DROP DEFAULT;
ALTER TABLE app_configs ALTER COLUMN email_cs DROP DEFAULT;
ALTER TABLE app_configs ALTER COLUMN website_url DROP DEFAULT;
ALTER TABLE app_configs ALTER COLUMN head_office_address DROP DEFAULT;
ALTER TABLE app_configs ALTER COLUMN otp_gateway_url DROP DEFAULT;

CREATE TABLE IF NOT EXISTS audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_type character varying(20) NOT NULL,
    actor_id character varying(60),
    actor_name character varying(100),
    action character varying(60) NOT NULL,
    target character varying(100),
    status character varying(20) DEFAULT 'SUCCESS'::character varying,
    ip_address character varying(50),
    user_agent character varying(255),
    device_id character varying(120),
    details text,
    seq bigint NOT NULL DEFAULT nextval('audit_logs_seq_seq'::regclass),
    prev_hash character varying(64),
    hash character varying(64),
    created_at timestamp with time zone,
    CONSTRAINT audit_logs_pkey PRIMARY KEY (id)
);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_type character varying(20);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_id character varying(60);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_name character varying(100);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS action character varying(60);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target character varying(100);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS status character varying(20) DEFAULT 'SUCCESS'::character varying;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS ip_address character varying(50);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS user_agent character varying(255);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS device_id character varying(120);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS details text;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS seq bigint NOT NULL DEFAULT nextval('audit_logs_seq_seq'::regclass);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS prev_hash character varying(64);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS hash character varying(64);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS banners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tag character varying(60) NOT NULL,
    title character varying(120) NOT NULL,
    highlight character varying(255) NOT NULL,
    badge_text character varying(50),
    bg_color character varying(30) DEFAULT '#1E293B'::character varying,
    accent_color character varying(30) DEFAULT '#16984B'::character varying,
    icon_name character varying(50) DEFAULT 'savings'::character varying,
    target_url character varying(255),
    is_active boolean DEFAULT true,
    display_order bigint DEFAULT 0,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT banners_pkey PRIMARY KEY (id)
);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS tag character varying(60);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS title character varying(120);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS highlight character varying(255);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS badge_text character varying(50);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS bg_color character varying(30) DEFAULT '#1E293B'::character varying;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS accent_color character varying(30) DEFAULT '#16984B'::character varying;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS icon_name character varying(50) DEFAULT 'savings'::character varying;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS target_url character varying(255);
ALTER TABLE banners ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS display_order bigint DEFAULT 0;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS mutations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_number character varying(30) NOT NULL,
    transaction_type character varying(10) NOT NULL,
    amount numeric(15,2) NOT NULL,
    balance_after numeric(15,2) NOT NULL,
    description character varying(255) NOT NULL,
    reference_number character varying(50) NOT NULL,
    created_at timestamp with time zone,
    CONSTRAINT mutations_pkey PRIMARY KEY (id)
);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS account_number character varying(30);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS transaction_type character varying(10);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS amount numeric(15,2);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS balance_after numeric(15,2);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS description character varying(255);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS reference_number character varying(50);
ALTER TABLE mutations ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id character varying(60) NOT NULL,
    title character varying(150) NOT NULL,
    message text NOT NULL,
    category character varying(30) DEFAULT 'INFO'::character varying,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone,
    CONSTRAINT notifications_pkey PRIMARY KEY (id)
);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS user_id character varying(60);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS title character varying(150);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS message text;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS category character varying(30) DEFAULT 'INFO'::character varying;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS is_read boolean DEFAULT false;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS product_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id character varying(60) NOT NULL,
    cif character varying(30),
    full_name character varying(100) NOT NULL,
    phone_number character varying(30) NOT NULL,
    product_type character varying(30) NOT NULL,
    product_name character varying(100) NOT NULL,
    amount numeric(15,2) NOT NULL,
    tenor_months bigint NOT NULL,
    interest_rate character varying(50),
    estimated_return numeric(15,2),
    purpose_or_source character varying(255),
    status character varying(30) DEFAULT 'PENDING'::character varying,
    admin_notes text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT product_applications_pkey PRIMARY KEY (id)
);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS user_id character varying(60);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS cif character varying(30);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS full_name character varying(100);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS phone_number character varying(30);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS product_type character varying(30);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS product_name character varying(100);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS amount numeric(15,2);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS tenor_months bigint;
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS interest_rate character varying(50);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS estimated_return numeric(15,2);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS purpose_or_source character varying(255);
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS status character varying(30) DEFAULT 'PENDING'::character varying;
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS admin_notes text;
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE product_applications ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS saved_beneficiaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id character varying(60) NOT NULL,
    bank_code character varying(20) DEFAULT 'BPR'::character varying,
    bank_name character varying(100) DEFAULT 'Bank DMB'::character varying,
    account_number character varying(30) NOT NULL,
    account_name character varying(100) NOT NULL,
    nickname character varying(60),
    created_at timestamp with time zone,
    CONSTRAINT saved_beneficiaries_pkey PRIMARY KEY (id)
);
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS user_id character varying(60);
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS bank_code character varying(20) DEFAULT 'BPR'::character varying;
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS bank_name character varying(100) DEFAULT 'Bank DMB'::character varying;
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS account_number character varying(30);
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS account_name character varying(100);
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS nickname character varying(60);
ALTER TABLE saved_beneficiaries ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    from_account character varying(30) NOT NULL,
    to_account character varying(30) NOT NULL,
    amount numeric(15,2) NOT NULL,
    transaction_type character varying(30) NOT NULL,
    status character varying(20) NOT NULL,
    cbs_ref_no character varying(50),
    created_at timestamp with time zone,
    CONSTRAINT transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS from_account character varying(30);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS to_account character varying(30);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS amount numeric(15,2);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS transaction_type character varying(30);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS status character varying(20);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cbs_ref_no character varying(50);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS transfer_requests (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    idempotency_key character varying(80) NOT NULL,
    request_hash character varying(64) NOT NULL,
    from_account character varying(30) NOT NULL,
    to_account character varying(30) NOT NULL,
    to_bank_code character varying(20),
    amount numeric(15,2) NOT NULL,
    status character varying(20) NOT NULL,
    cbs_reference_no character varying(60),
    response_json text,
    failure_reason character varying(255),
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT transfer_requests_pkey PRIMARY KEY (id)
);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS id uuid;
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS idempotency_key character varying(80);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS request_hash character varying(64);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS from_account character varying(30);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS to_account character varying(30);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS to_bank_code character varying(20);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS amount numeric(15,2);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS status character varying(20);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS cbs_reference_no character varying(60);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS response_json text;
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS failure_reason character varying(255);
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE transfer_requests ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS user_sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    device_id character varying(120),
    refresh_token_hash character varying(64) NOT NULL,
    prev_refresh_hash character varying(64),
    rotated_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    revoked_reason character varying(60),
    ip_address character varying(64),
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT user_sessions_pkey PRIMARY KEY (id)
);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS id uuid;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_id character varying(120);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS refresh_token_hash character varying(64);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS prev_refresh_hash character varying(64);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS rotated_at timestamp with time zone;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS expires_at timestamp with time zone;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS revoked_at timestamp with time zone;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS revoked_reason character varying(60);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS ip_address character varying(64);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nik text,
    cif character varying(20) NOT NULL,
    full_name character varying(100) NOT NULL,
    phone_number character varying(20) NOT NULL,
    email text,
    alamat text,
    kode_pos character varying(15),
    jenis_kelamin character varying(5),
    agama character varying(30),
    tgl_lahir text,
    tempat_lahir text,
    nama_ibu_kandung text,
    password_hash character varying(255) NOT NULL,
    pin_hash character varying(255) NOT NULL,
    device_id character varying(100),
    fcm_token text,
    failed_login_attempts bigint DEFAULT 0,
    failed_pin_attempts bigint DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT users_pkey PRIMARY KEY (id)
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS nik text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS cif character varying(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name character varying(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number character varying(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS alamat text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS kode_pos character varying(15);
ALTER TABLE users ADD COLUMN IF NOT EXISTS jenis_kelamin character varying(5);
ALTER TABLE users ADD COLUMN IF NOT EXISTS agama character varying(30);
ALTER TABLE users ADD COLUMN IF NOT EXISTS tgl_lahir text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS tempat_lahir text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS nama_ibu_kandung text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash character varying(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_hash character varying(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_id character varying(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts bigint DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_pin_attempts bigint DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

ALTER SEQUENCE audit_logs_seq_seq OWNED BY audit_logs.seq;

-- Legacy databases defaulted new admin rows to SUPER_ADMIN (audit DMB-009): role must be explicit.
ALTER TABLE admin_users ALTER COLUMN role DROP DEFAULT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_account_number ON accounts (account_number);
CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON accounts (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users (username);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs (action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_id ON audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_type ON audit_logs (actor_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_hash ON audit_logs (hash);
CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_logs_seq ON audit_logs (seq);
CREATE INDEX IF NOT EXISTS idx_mutations_account_number ON mutations (account_number);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mutations_reference_number ON mutations (reference_number);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications (created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_product_applications_created_at ON product_applications (created_at);
CREATE INDEX IF NOT EXISTS idx_product_applications_product_type ON product_applications (product_type);
CREATE INDEX IF NOT EXISTS idx_product_applications_user_id ON product_applications (user_id);
CREATE INDEX IF NOT EXISTS idx_saved_beneficiaries_user_id ON saved_beneficiaries (user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_from_account ON transactions (from_account);
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_transfer_idem ON transfer_requests (user_id, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_transfer_requests_created_at ON transfer_requests (created_at);
CREATE INDEX IF NOT EXISTS idx_transfer_requests_from_account ON transfer_requests (from_account);
CREATE INDEX IF NOT EXISTS idx_transfer_requests_status ON transfer_requests (status);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions (expires_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_prev_refresh_hash ON user_sessions (prev_refresh_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_refresh_token_hash ON user_sessions (refresh_token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_revoked_at ON user_sessions (revoked_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_cif ON users (cif);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users (device_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_number ON users (phone_number);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_accounts_mutations') THEN
    ALTER TABLE mutations ADD CONSTRAINT fk_accounts_mutations FOREIGN KEY (account_number) REFERENCES accounts(account_number);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_transactions_user') THEN
    ALTER TABLE transactions ADD CONSTRAINT fk_transactions_user FOREIGN KEY (user_id) REFERENCES users(id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_accounts') THEN
    ALTER TABLE accounts ADD CONSTRAINT fk_users_accounts FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
  END IF;
END $$;
