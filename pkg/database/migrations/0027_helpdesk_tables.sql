-- 0027_helpdesk_tables.sql
-- Membuat tabel helpdesk_faqs & helpdesk_inquiries secara resmi lewat migrasi
-- (karena role runtime mbanking_app tidak memiliki hak DDL untuk AutoMigrate).

CREATE TABLE IF NOT EXISTS helpdesk_faqs (
    id         uuid PRIMARY KEY,
    topic      varchar(120) NOT NULL,
    keywords   text NOT NULL,
    answer     text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS helpdesk_inquiries (
    id             uuid PRIMARY KEY,
    user_id        varchar(60),
    cif            varchar(30),
    full_name      varchar(100),
    phone_number   varchar(30),
    question       text NOT NULL,
    matched_faq_id varchar(64),
    is_answered    boolean NOT NULL DEFAULT false,
    status         varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_helpdesk_inquiries_user_id ON helpdesk_inquiries (user_id);
CREATE INDEX IF NOT EXISTS idx_helpdesk_inquiries_created_at ON helpdesk_inquiries (created_at DESC);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE helpdesk_faqs TO mbanking_app;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE helpdesk_inquiries TO mbanking_app;
  END IF;
END $$;
