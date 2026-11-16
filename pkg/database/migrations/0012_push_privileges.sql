-- 0012 grants for the push notification tables (idempotent; re-applied by `migrate grants`).
-- The application role never deletes devices, campaigns or delivery records.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE ON push_settings, push_devices, notification_campaigns, push_deliveries TO mbanking_app;
    REVOKE DELETE, TRUNCATE, TRIGGER ON push_settings, push_devices, notification_campaigns, push_deliveries FROM mbanking_app;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT SELECT ON notification_campaigns, push_deliveries TO mbanking_audit_reader;
  END IF;
END $$;
