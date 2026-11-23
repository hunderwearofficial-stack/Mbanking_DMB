-- ROLLBACK of migration 0016. Manual only, migration role, together with redeploying the
-- previous backend release. The column and the widened CHECK are harmless for the previous
-- release and are left in place (no data is deleted). Run before 0015_device_attestation_down.sql.
BEGIN;
DELETE FROM schema_migrations WHERE version = 16;
COMMIT;
