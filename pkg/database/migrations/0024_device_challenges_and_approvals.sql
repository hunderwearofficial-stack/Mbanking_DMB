-- 0024_device_challenges_and_approvals.sql
-- L-05: selaraskan constraint device_challenges_purpose_check tanpa PROFILE_REVEAL.
-- H-01: tambahkan jenis persetujuan ADMIN_MANAGE untuk maker-checker manajemen petugas.

ALTER TABLE device_challenges DROP CONSTRAINT IF EXISTS device_challenges_purpose_check;
DELETE FROM device_challenges WHERE purpose NOT IN ('LOGIN', 'REFRESH', 'CHANGE_PASSWORD', 'CHANGE_PIN', 'ENROLL', 'ROTATE');
ALTER TABLE device_challenges ADD CONSTRAINT device_challenges_purpose_check
    CHECK (purpose IN ('LOGIN', 'REFRESH', 'CHANGE_PASSWORD', 'CHANGE_PIN', 'ENROLL', 'ROTATE'));

ALTER TABLE approval_requests DROP CONSTRAINT IF EXISTS approval_requests_kind_check;
ALTER TABLE approval_requests ADD CONSTRAINT approval_requests_kind_check
    CHECK (kind IN ('CONFIG_SECURITY', 'DEVICE_RESET', 'CUSTOMER_UNBLOCK', 'BANNER_PUBLISH', 'ADMIN_MANAGE'));
