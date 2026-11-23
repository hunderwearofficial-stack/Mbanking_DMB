-- Rollback 0017: Remove username column and its index
BEGIN;
DROP INDEX IF EXISTS idx_users_username;
ALTER TABLE users DROP COLUMN IF EXISTS username;
DELETE FROM schema_migrations WHERE version = 17;
COMMIT;
