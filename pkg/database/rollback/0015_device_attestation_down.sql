-- ROLLBACK of migration 0015 (device attestation). Manual only, migration role,
-- together with redeploying the previous backend release. Run BEFORE
-- 0013_0014_device_key_binding_down.sql when rolling back further.
--
-- The additional columns and widened CHECK constraints are harmless for the previous
-- release (it neither reads nor writes them), so they are LEFT IN PLACE: no key row is
-- deleted. Only App Attest keys, which the previous release cannot verify, are revoked;
-- those customers re-bind through Lupa Password (OTP). Re-applying 0015 later is
-- idempotent.
BEGIN;
UPDATE device_keys SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'ROLLBACK_0015'
 WHERE algorithm = 'APPATTEST' AND status = 'ACTIVE';
DELETE FROM schema_migrations WHERE version = 15;
COMMIT;
