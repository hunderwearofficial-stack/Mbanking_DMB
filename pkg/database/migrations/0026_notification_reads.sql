-- 0026_notification_reads.sql
-- Menyimpan status baca per nasabah untuk notifikasi broadcast (user_id = 'ALL')
-- sehingga "Tandai Semua Dibaca" tidak memengaruhi nasabah lain.

CREATE TABLE IF NOT EXISTS notification_reads (
    user_id         text NOT NULL,
    notification_id uuid NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    read_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, notification_id)
);

CREATE INDEX IF NOT EXISTS idx_notification_reads_user ON notification_reads (user_id);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mbanking_app') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE notification_reads TO mbanking_app;
  END IF;
END $$;
