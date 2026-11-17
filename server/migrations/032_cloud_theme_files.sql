BEGIN;

-- Custom themes sync as cloud files too: one file per theme pack (meta.packageId) and one per scheme
-- for its startup and preview images (meta.schemeId). They share the account's storage and download quota.
ALTER TABLE cloud_files DROP CONSTRAINT IF EXISTS cloud_files_kind_check;
ALTER TABLE cloud_files ADD CONSTRAINT cloud_files_kind_check
  CHECK (kind IN ('BOOK','FONT','SOURCE','THEME'));
ALTER TABLE cloud_file_tombstones DROP CONSTRAINT IF EXISTS cloud_file_tombstones_kind_check;
ALTER TABLE cloud_file_tombstones ADD CONSTRAINT cloud_file_tombstones_kind_check
  CHECK (kind IN ('BOOK','FONT','SOURCE','THEME'));

COMMIT;
