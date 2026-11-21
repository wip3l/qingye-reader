BEGIN;

-- A lifetime membership bought with a coupon used to record its upgrade credit net of the coupon, so
-- upgrading to the super membership charged the coupon back. Credit the price it sold at instead.
-- Only rows still holding the old net value change, so rerunning this and hand-adjusted credits are safe.
UPDATE membership_periods p SET permanent_credit_points = o.list_points
FROM membership_orders o
WHERE o.period_id = p.id AND o.sku = 'LIFETIME' AND o.coupon_points > 0
  AND p.sku = 'LIFETIME' AND p.expires_at IS NULL
  AND p.permanent_credit_points = o.list_points - o.coupon_points;

COMMIT;
