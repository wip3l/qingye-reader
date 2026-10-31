BEGIN;

-- Several draws per account; the account keeps one coupon, upgraded whenever a draw beats it.
ALTER TABLE lottery_campaigns
  ADD COLUMN IF NOT EXISTS draws_per_user INTEGER NOT NULL DEFAULT 1 CHECK (draws_per_user BETWEEN 1 AND 10);

ALTER TABLE lottery_draws
  ADD COLUMN IF NOT EXISTS draw_no INTEGER NOT NULL DEFAULT 1 CHECK (draw_no >= 1),
  -- Whether this draw became the account's coupon; a draw that did not beat it is only a record.
  ADD COLUMN IF NOT EXISTS kept BOOLEAN NOT NULL DEFAULT true;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'lottery_draws'::regclass AND contype = 'p'
        AND pg_get_constraintdef(oid) NOT LIKE '%draw_no%') THEN
    EXECUTE (SELECT format('ALTER TABLE lottery_draws DROP CONSTRAINT %I', conname) FROM pg_constraint
      WHERE conrelid = 'lottery_draws'::regclass AND contype = 'p');
    ALTER TABLE lottery_draws ADD PRIMARY KEY (campaign_id, user_id, draw_no);
  END IF;
END
$$;

-- An upgraded coupon is retired as REPLACED and a new one issued, so a quote still holding the old
-- coupon fails at purchase instead of charging the old amount.
DO $$
DECLARE name TEXT;
BEGIN
  FOR name IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'membership_coupons'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%status%' AND pg_get_constraintdef(oid) NOT LIKE '%REPLACED%'
  LOOP
    EXECUTE format('ALTER TABLE membership_coupons DROP CONSTRAINT %I', name);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'membership_coupons_status_check_v2') THEN
    ALTER TABLE membership_coupons ADD CONSTRAINT membership_coupons_status_check_v2
      CHECK (status IN ('AVAILABLE', 'USED', 'REVOKED', 'REPLACED'));
  END IF;
END
$$;

-- Double 11: three draws, best coupon kept. Existing single draws stay as draw 1.
UPDATE lottery_campaigns SET draws_per_user = 3 WHERE id = 'double11-2026' AND draws_per_user = 1;

COMMIT;
