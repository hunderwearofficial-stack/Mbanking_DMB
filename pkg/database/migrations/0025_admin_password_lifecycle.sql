-- 0025_admin_password_lifecycle.sql
-- MA-03: an officer password set by someone else (system-issued on approval) must be
--        changed by the officer at first login, before MFA enrolment.
-- MA-12: a password change invalidates backoffice sessions issued before it.
-- Additive only: no existing data is changed or removed.

ALTER TABLE admin_users
    ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS password_changed_at timestamptz;
