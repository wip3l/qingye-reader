BEGIN;

-- Separate from sync_entities: minute-sized reading segments must not consume the bookshelf quota.
CREATE SEQUENCE IF NOT EXISTS reading_stats_sequence;
CREATE TABLE IF NOT EXISTS reading_stats_usage (
  user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
  record_count BIGINT NOT NULL DEFAULT 0,
  payload_bytes BIGINT NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS reading_stats_records (
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  record_id UUID NOT NULL,
  source_device_id UUID,
  payload JSONB,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  sequence_id BIGINT NOT NULL DEFAULT nextval('reading_stats_sequence'),
  payload_bytes INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, record_id),
  CHECK ((deleted AND payload IS NULL) OR (NOT deleted AND payload IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS reading_stats_owner_sequence ON reading_stats_records(user_id, sequence_id);

-- Also support migrations run by an administrator, matching the existing account service role.
DO $$
DECLARE application_role NAME;
BEGIN
  SELECT tableowner INTO application_role FROM pg_tables
    WHERE schemaname='public' AND tablename='point_wallets';
  IF application_role IS NOT NULL AND application_role <> current_user THEN
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE reading_stats_records, reading_stats_usage TO %I', application_role);
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE reading_stats_sequence TO %I', application_role);
  END IF;
END
$$;

COMMIT;
