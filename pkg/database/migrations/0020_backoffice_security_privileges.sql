-- 0020 grants for approval_requests (idempotent; re-applied by `migrate grants`).
-- Approval history is never deleted by the application: decisions are status changes.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE ON approval_requests TO mbanking_app;
    REVOKE DELETE, TRUNCATE, TRIGGER ON approval_requests FROM mbanking_app;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT SELECT ON approval_requests TO mbanking_audit_reader;
  END IF;
END $$;
