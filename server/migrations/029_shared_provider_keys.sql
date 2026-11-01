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

COMMIT;
