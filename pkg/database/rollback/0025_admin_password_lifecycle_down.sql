-- Rollback 0025_admin_password_lifecycle.sql (run with the schema owner role).
-- Officers flagged must_change_password lose that requirement after rollback: review them
-- first with: SELECT username FROM admin_users WHERE must_change_password;
ALTER TABLE admin_users
    DROP COLUMN IF EXISTS must_change_password,
    DROP COLUMN IF EXISTS password_changed_at;

DELETE FROM schema_migrations WHERE version = 25;
