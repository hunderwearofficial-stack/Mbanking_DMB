-- 0023_role_privileges_current.sql
-- Konsolidasi GRANT role database untuk tabel aktif saat ini (pengganti 0004 untuk `migrate grants`,
-- tanpa mengubah checksum 0004). Hanya berisi GRANT/REVOKE (idempoten, tanpa DDL/DELETE).

DO $$
DECLARE
  tbl text;
  rw_tables text[] := ARRAY[
    'users', 'accounts', 'mutations', 'admin_users', 'banners', 'app_configs',
    'notifications', 'product_applications', 'user_sessions', 'otp_challenges',
    'device_keys', 'device_challenges', 'legal_documents', 'legal_document_versions',
    'legal_files', 'terms_acceptances', 'mobile_content_items', 'mobile_content_revisions',
    'push_credentials', 'push_campaigns', 'push_deliveries', 'approval_requests'
  ];
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT USAGE ON SCHEMA public TO mbanking_app;
    FOREACH tbl IN ARRAY rw_tables LOOP
      IF to_regclass('public.' || tbl) IS NOT NULL THEN
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I TO mbanking_app', tbl);
      END IF;
    END LOOP;
    IF to_regclass('public.audit_logs') IS NOT NULL THEN
      GRANT SELECT, INSERT ON audit_logs TO mbanking_app;
      REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON audit_logs FROM mbanking_app;
    END IF;
    IF to_regclass('public.schema_migrations') IS NOT NULL THEN
      GRANT SELECT ON schema_migrations TO mbanking_app;
    END IF;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mbanking_app;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT USAGE ON SCHEMA public TO mbanking_audit_reader;
    IF to_regclass('public.audit_logs') IS NOT NULL THEN
      GRANT SELECT ON audit_logs TO mbanking_audit_reader;
    END IF;
    IF to_regclass('public.mobile_content_revisions') IS NOT NULL THEN
      GRANT SELECT ON TABLE mobile_content_revisions TO mbanking_audit_reader;
    END IF;
  END IF;
END $$;
