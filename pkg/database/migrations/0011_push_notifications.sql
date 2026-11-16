-- 0011 push notifications through Firebase Cloud Messaging HTTP v1.
-- Additive only. The legacy columns users.fcm_token and app_configs.fcm_server_key are
-- kept (no data is dropped) but are no longer read or written by the application.

-- 1. Firebase integration settings (single row). The service-account credential is
--    stored ONLY encrypted (AES-256-GCM with the application key ring, enc:v2:…); the
--    fingerprint identifies a credential without revealing it.
CREATE TABLE IF NOT EXISTS push_settings (
    id character varying(20) PRIMARY KEY CHECK (id = 'DEFAULT'),
    enabled boolean NOT NULL DEFAULT false,
    project_id character varying(120),
    client_email character varying(255),
    credential_enc text,
    credential_fingerprint character(64),
    credential_updated_by character varying(100),
    credential_updated_at timestamptz,
    last_test_at timestamptz,
    last_test_ok boolean,
    last_test_error text,
    last_test_fingerprint character(64),
    updated_by character varying(100),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (credential_enc IS NULL OR credential_enc LIKE 'enc:%'),
    CHECK (NOT enabled OR credential_enc IS NOT NULL)
);
INSERT INTO push_settings (id) VALUES ('DEFAULT') ON CONFLICT (id) DO NOTHING;

-- 2. Device tokens: many devices per customer, one row per FCM registration token.
--    The token is stored encrypted; token_sha256 is used for lookups and uniqueness.
CREATE TABLE IF NOT EXISTS push_devices (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id),
    device_id character varying(128) NOT NULL,
    platform character varying(20) NOT NULL DEFAULT 'android',
    token_sha256 character(64) NOT NULL UNIQUE,
    token_enc text NOT NULL CHECK (token_enc LIKE 'enc:%'),
    is_active boolean NOT NULL DEFAULT true,
    deactivated_reason character varying(40),
    deactivated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_push_devices_user_active ON push_devices (user_id) WHERE is_active;

-- 3. Notifications created by officers (maker-checker before sending).
CREATE TABLE IF NOT EXISTS notification_campaigns (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    title character varying(150) NOT NULL,
    body text NOT NULL,
    category character varying(30) NOT NULL CHECK (category IN ('INFO','PROMO')),
    target_type character varying(20) NOT NULL CHECK (target_type IN ('ALL','USER')),
    target_user_id uuid REFERENCES users(id),
    status character varying(20) NOT NULL
        CHECK (status IN ('DRAFT','PENDING_APPROVAL','REJECTED','SENDING','SENT','PARTIAL','FAILED','NO_RECIPIENT')),
    created_by character varying(60) NOT NULL,
    created_by_name character varying(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    submitted_at timestamptz,
    approved_by character varying(60),
    approved_by_name character varying(100),
    approved_at timestamptz,
    reject_reason text,
    send_started_at timestamptz,
    send_finished_at timestamptz,
    target_devices integer NOT NULL DEFAULT 0,
    accepted_count integer NOT NULL DEFAULT 0,
    failed_count integer NOT NULL DEFAULT 0,
    invalid_token_count integer NOT NULL DEFAULT 0,
    last_error text,
    CHECK ((target_type = 'USER') = (target_user_id IS NOT NULL)),
    CHECK (approved_by IS NULL OR approved_by <> created_by)
);
CREATE INDEX IF NOT EXISTS idx_notification_campaigns_created ON notification_campaigns (created_at DESC);

-- 4. One delivery row per (message, device). Status meanings:
--      QUEUED         request recorded, not yet sent to FCM
--      ACCEPTED       FCM accepted the message for delivery (NOT proof of display)
--      FAILED         FCM refused or was unreachable after the allowed retries
--      INVALID_TOKEN  FCM reported the token as unregistered; the device was deactivated
--    opened_at is set only when the app on the device reports that the customer tapped
--    the notification — the only device-side confirmation available.
CREATE TABLE IF NOT EXISTS push_deliveries (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    campaign_id uuid REFERENCES notification_campaigns(id),
    notification_id uuid,
    user_id uuid NOT NULL REFERENCES users(id),
    device_id uuid NOT NULL REFERENCES push_devices(id),
    category character varying(30) NOT NULL,
    status character varying(20) NOT NULL CHECK (status IN ('QUEUED','ACCEPTED','FAILED','INVALID_TOKEN')),
    attempts integer NOT NULL DEFAULT 0,
    fcm_message_id character varying(255),
    error_code character varying(60),
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    opened_at timestamptz,
    CHECK (campaign_id IS NOT NULL OR notification_id IS NOT NULL)
);
-- No duplicate push of the same message to the same device.
CREATE UNIQUE INDEX IF NOT EXISTS uq_push_deliveries_campaign_device
    ON push_deliveries (campaign_id, device_id) WHERE campaign_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_push_deliveries_notification_device
    ON push_deliveries (notification_id, device_id) WHERE notification_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_push_deliveries_campaign ON push_deliveries (campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_created ON push_deliveries (created_at DESC);

-- 5. Least-privilege grants (re-applied by `migrate grants`: name ends with _privileges
--    in 0012; duplicated here so a single `migrate up` is enough when roles exist).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE ON push_settings, push_devices, notification_campaigns, push_deliveries TO mbanking_app;
  END IF;
END $$;
