BEGIN;

-- Web lottery: an account proves ownership by putting a short code into its nickname from the app,
-- then draws once per campaign. Prizes are coupons that lower a permanent membership quote.

CREATE INDEX IF NOT EXISTS app_users_updated_idx ON app_users(updated_at);

CREATE TABLE IF NOT EXISTS lottery_web_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL,
  client_ip TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  user_id UUID REFERENCES app_users(id) ON DELETE CASCADE,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS lottery_web_verifications_code_idx
  ON lottery_web_verifications(code, expires_at);

CREATE TABLE IF NOT EXISTS lottery_web_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS lottery_campaigns (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  -- Only accounts created before this instant may draw.
  registered_before TIMESTAMPTZ NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT false,
  -- Cloud quota granted for a super membership bought without a coupon during the campaign; NULL grants none.
  super_no_coupon_quota_bytes BIGINT CHECK (super_no_coupon_quota_bytes > 0),
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS lottery_prizes (
  id TEXT PRIMARY KEY,
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  label TEXT NOT NULL,
  weight INTEGER NOT NULL CHECK (weight > 0),
  stock INTEGER CHECK (stock >= 0), -- NULL is unlimited
  issued INTEGER NOT NULL DEFAULT 0,
  -- Points off per SKU, e.g. {"LIFETIME": 100, "SUPER_LIFETIME": 200}.
  discounts JSONB NOT NULL,
  is_fallback BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL,
  CHECK (stock IS NULL OR issued <= stock),
  CHECK (NOT is_fallback OR stock IS NULL)
);
CREATE INDEX IF NOT EXISTS lottery_prizes_campaign_idx ON lottery_prizes(campaign_id, sort_order);

CREATE TABLE IF NOT EXISTS membership_coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  prize_id TEXT NOT NULL REFERENCES lottery_prizes(id),
  -- Copied from the prize so later prize edits never change an issued coupon.
  discounts JSONB NOT NULL,
  -- For SUPER_LIFETIME: COUPON spends it, CLOUD skips it so the purchase earns the cloud quota instead.
  super_choice TEXT NOT NULL DEFAULT 'COUPON' CHECK (super_choice IN ('COUPON', 'CLOUD')),
  expires_at TIMESTAMPTZ, -- NULL never expires
  status TEXT NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'USED', 'REVOKED')),
  used_order_id UUID,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS membership_coupons_user_idx ON membership_coupons(user_id, status);

CREATE TABLE IF NOT EXISTS lottery_draws (
  campaign_id TEXT NOT NULL REFERENCES lottery_campaigns(id),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  prize_id TEXT NOT NULL REFERENCES lottery_prizes(id),
  coupon_id UUID NOT NULL REFERENCES membership_coupons(id),
  client_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, user_id)
);

ALTER TABLE membership_orders
  ADD COLUMN IF NOT EXISTS coupon_id UUID REFERENCES membership_coupons(id),
  ADD COLUMN IF NOT EXISTS coupon_points BIGINT NOT NULL DEFAULT 0 CHECK (coupon_points >= 0);

-- Orders balanced as spent + credit = list; a coupon is now a third part of the list price.
DO $$
DECLARE name TEXT;
BEGIN
  FOR name IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'membership_orders'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%points_spent + credit_points%'
      AND pg_get_constraintdef(oid) NOT LIKE '%coupon_points%'
  LOOP
    EXECUTE format('ALTER TABLE membership_orders DROP CONSTRAINT %I', name);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'membership_orders_points_balance') THEN
    ALTER TABLE membership_orders ADD CONSTRAINT membership_orders_points_balance
      CHECK (points_spent + credit_points + coupon_points = list_points);
  END IF;
END $$;

-- Total cloud quota for an account when above the standard 1 GiB; one row per account.
CREATE TABLE IF NOT EXISTS cloud_quota_bonuses (
  user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
  quota_bytes BIGINT NOT NULL CHECK (quota_bytes > 0),
  campaign_id TEXT REFERENCES lottery_campaigns(id),
  order_id UUID REFERENCES membership_orders(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
