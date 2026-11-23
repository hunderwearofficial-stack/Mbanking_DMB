-- 0010 maker-checker for mobile content: DRAFT → PENDING_APPROVAL → PUBLISHED → ARCHIVED.
-- Additive: existing revisions keep their status; the 0008 guard trigger still forbids
-- changing the values of any revision that is not a draft.
ALTER TABLE mobile_content_revisions DROP CONSTRAINT IF EXISTS mobile_content_revisions_status_check;
ALTER TABLE mobile_content_revisions ADD CONSTRAINT mobile_content_revisions_status_check
    CHECK (status IN ('DRAFT','PENDING_APPROVAL','PUBLISHED','ARCHIVED'));
ALTER TABLE mobile_content_revisions ADD COLUMN IF NOT EXISTS submitted_by character varying(60);
ALTER TABLE mobile_content_revisions ADD COLUMN IF NOT EXISTS submitted_by_name character varying(100);
ALTER TABLE mobile_content_revisions ADD COLUMN IF NOT EXISTS submitted_at timestamptz;

-- One open revision (draft or pending approval) at a time.
DROP INDEX IF EXISTS uq_mobile_content_one_draft;
CREATE UNIQUE INDEX IF NOT EXISTS uq_mobile_content_one_open
    ON mobile_content_revisions ((true)) WHERE status IN ('DRAFT','PENDING_APPROVAL');

-- The publisher must differ from the creator (enforced in the service as well).
ALTER TABLE mobile_content_revisions DROP CONSTRAINT IF EXISTS mobile_content_checker_differs;
ALTER TABLE mobile_content_revisions ADD CONSTRAINT mobile_content_checker_differs
    CHECK (status <> 'PUBLISHED' OR published_by IS NULL OR published_by <> created_by) NOT VALID;

-- Guard redefined for the approval workflow:
--   DRAFT            editable (values, note); identity fixed
--   PENDING_APPROVAL values fixed; may go back to DRAFT or be PUBLISHED
--   PUBLISHED        values and publication fixed; may only be ARCHIVED
--   ARCHIVED         immutable; only DRAFT rows may be deleted
CREATE OR REPLACE FUNCTION mobile_content_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'revisi konten berstatus % tidak boleh dihapus', OLD.status;
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.version_number IS DISTINCT FROM OLD.version_number OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'identitas revisi konten tidak boleh diubah';
  END IF;
  IF OLD.status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'revisi konten yang diarsipkan tidak boleh diubah';
  END IF;
  IF OLD.status = 'PUBLISHED' AND (NEW.status <> 'ARCHIVED' OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.published_at IS DISTINCT FROM OLD.published_at OR NEW.published_by IS DISTINCT FROM OLD.published_by) THEN
    RAISE EXCEPTION 'revisi konten yang sudah diterbitkan tidak boleh diubah (hanya dapat diarsipkan)';
  END IF;
  IF OLD.status = 'PENDING_APPROVAL' AND (NEW.content IS DISTINCT FROM OLD.content OR NEW.status NOT IN ('DRAFT','PUBLISHED','PENDING_APPROVAL')) THEN
    RAISE EXCEPTION 'revisi yang menunggu persetujuan tidak boleh diubah';
  END IF;
  IF OLD.status = 'DRAFT' AND NEW.status NOT IN ('DRAFT','PENDING_APPROVAL') THEN
    RAISE EXCEPTION 'draf harus diajukan sebelum diterbitkan';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
