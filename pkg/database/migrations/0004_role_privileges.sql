-- 0004 least-privilege grants for the separated database roles.
-- Roles are created by the DBA (deploy/sql/create_roles.sql); this migration only
-- grants privileges when the roles exist, so it is safe on a developer database.
--
--   mbanking_app           application runtime role (NOT the table owner)
--   mbanking_audit_reader  read-only access to the audit trail (compliance / auditverify)
--
-- The application may INSERT and SELECT audit_logs but never UPDATE/DELETE/TRUNCATE it,
-- and because it does not own the table it cannot disable the append-only triggers.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT USAGE ON SCHEMA public TO mbanking_app;
    GRANT SELECT, INSERT, UPDATE, DELETE ON
      users, accounts, mutations, transactions, admin_users, banners, app_configs,
      notifications, saved_beneficiaries, product_applications, user_sessions, transfer_requests
      TO mbanking_app;
    GRANT SELECT, INSERT ON audit_logs TO mbanking_app;
    REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON audit_logs FROM mbanking_app;
    GRANT SELECT ON schema_migrations TO mbanking_app;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mbanking_app;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT USAGE ON SCHEMA public TO mbanking_audit_reader;
    GRANT SELECT ON audit_logs TO mbanking_audit_reader;
  END IF;
END $$;
