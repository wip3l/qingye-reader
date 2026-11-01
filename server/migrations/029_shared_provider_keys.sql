BEGIN;

-- Provider API keys the operator hands to lifetime members (one-click fill in the app). Set by SQL,
-- see OPERATIONS.md; the key is never logged.
CREATE TABLE IF NOT EXISTS shared_provider_keys (
  provider TEXT PRIMARY KEY CHECK (provider ~ '^[a-z0-9_-]{1,32}$'),
  api_key TEXT NOT NULL CHECK (length(api_key) BETWEEN 8 AND 4096),
  enabled BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Who fetched a shared key and when, to trace a leak and to see how widely it is used.
CREATE TABLE IF NOT EXISTS shared_provider_key_grants (
  provider TEXT NOT NULL REFERENCES shared_provider_keys(provider) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  first_granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  grant_count INTEGER NOT NULL DEFAULT 1 CHECK (grant_count >= 1),
  PRIMARY KEY (provider, user_id)
);

-- Also support migrations run by an administrator, matching the existing account service role.
DO $$
DECLARE application_role NAME;
BEGIN
  SELECT tableowner INTO application_role FROM pg_tables
    WHERE schemaname='public' AND tablename='point_wallets';
  IF application_role IS NOT NULL AND application_role <> current_user THEN
    EXECUTE format('GRANT SELECT ON TABLE shared_provider_keys TO %I', application_role);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE shared_provider_key_grants TO %I', application_role);
  END IF;
END
$$;

COMMIT;
