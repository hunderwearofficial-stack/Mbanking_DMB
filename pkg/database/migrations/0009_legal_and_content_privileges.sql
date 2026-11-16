-- 0009 least-privilege grants for the tables added in 0008 (idempotent; re-applied by
-- `migrate grants` together with 0004). The application role may read and insert
-- consent records and stored files, but never update or delete them; legal document
-- versions can be updated only within the limits enforced by the 0008 triggers.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT ON stored_files, legal_acceptances TO mbanking_app;
    REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON stored_files, legal_acceptances FROM mbanking_app;
    GRANT SELECT ON legal_documents TO mbanking_app;
    GRANT SELECT, INSERT, UPDATE ON legal_document_versions TO mbanking_app;
    REVOKE DELETE, TRUNCATE, TRIGGER ON legal_document_versions FROM mbanking_app;
    -- DELETE is needed to discard an open draft; the 0008 trigger refuses deleting
    -- published or archived revisions.
    GRANT SELECT, INSERT, UPDATE, DELETE ON mobile_content_revisions TO mbanking_app;
    REVOKE TRUNCATE, TRIGGER ON mobile_content_revisions FROM mbanking_app;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_audit_reader') THEN
    GRANT SELECT ON legal_documents, legal_document_versions, legal_acceptances TO mbanking_audit_reader;
  END IF;
END $$;
