-- 0014 grants for the device binding tables (idempotent; re-applied by `migrate grants`).
-- The application role never deletes keys or challenges: revocation is a status change,
-- so the history of every bound device stays auditable.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE ON device_keys, device_challenges TO mbanking_app;
    REVOKE DELETE, TRUNCATE, TRIGGER ON device_keys, device_challenges FROM mbanking_app;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT SELECT ON device_keys TO mbanking_audit_reader;
  END IF;
END $$;
