-- ROLLBACK of migrations 0013 + 0014 (cryptographic device binding).
--
-- NOT embedded in the binary and never run automatically. Run it manually with the
-- MIGRATION role, only together with redeploying the previous backend release (that
-- release refuses to start while schema_migrations lists versions it does not know).
-- Procedure: docs/OPERATIONS_AND_BACKUP.md "Rollback device binding".
-- If 0015 is applied, run 0015_device_attestation_down.sql first.
--
-- Effects:
--   * customer bindings (users.device_id) are kept: every customer keeps logging in
--     with the identifier the app sends today (legacy or and-/ios- format);
--   * enrolled public keys and challenges are removed (export them first, see docs);
--   * widened device_id columns are left at 128 (narrowing could truncate data and
--     the previous release works with the wider columns).
BEGIN;
DROP TABLE IF EXISTS device_challenges;
DROP TABLE IF EXISTS device_keys;
ALTER TABLE users DROP COLUMN IF EXISTS device_enroll_until;
DELETE FROM schema_migrations WHERE version IN (13, 14);
COMMIT;
