BEGIN;

-- Double 11 lottery (UTC+8). Inserted disabled; set enabled after the live check to start it.
-- Coupons apply to the two permanent memberships only and never expire. 1 yuan = 10 points.
INSERT INTO lottery_campaigns(id, title, starts_at, ends_at, registered_before, enabled,
    super_no_coupon_quota_bytes) VALUES
  ('double11-2026', '永久会员抵扣券抽奖',
    TIMESTAMPTZ '2026-10-30 00:00:00+08', TIMESTAMPTZ '2026-11-12 00:00:00+08',
    TIMESTAMPTZ '2026-11-11 00:00:00+08', false, 5368709120) -- 5 GiB
ON CONFLICT (id) DO NOTHING;

INSERT INTO lottery_prizes(id, campaign_id, label, weight, stock, discounts, is_fallback, sort_order) VALUES
  ('double11-2026-grand',  'double11-2026', '特等奖', 1,  20,   '{"LIFETIME":300,"SUPER_LIFETIME":600}', false, 1),
  ('double11-2026-first',  'double11-2026', '一等奖', 5,  100,  '{"LIFETIME":200,"SUPER_LIFETIME":400}', false, 2),
  ('double11-2026-second', 'double11-2026', '二等奖', 20, NULL, '{"LIFETIME":100,"SUPER_LIFETIME":200}', false, 3),
  ('double11-2026-third',  'double11-2026', '三等奖', 34, NULL, '{"LIFETIME":60,"SUPER_LIFETIME":120}',  false, 4),
  ('double11-2026-lucky',  'double11-2026', '幸运奖', 40, NULL, '{"LIFETIME":30,"SUPER_LIFETIME":60}',   true,  5)
ON CONFLICT (id) DO NOTHING;

COMMIT;
