-- 0017 Add username column to users table for customer login and identification.
-- Rollback: ALTER TABLE users DROP COLUMN IF EXISTS username;

ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE username IS NOT NULL;
