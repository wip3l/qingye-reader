-- 安卓端点数充值：支付宝手机网站支付订单与兑换码（见 docs/android-recharge.md）。
-- 鸿蒙端仍只走华为应用内支付（iap_orders），两条渠道入账都记到 point_wallets.paid_balance。

BEGIN;

CREATE TABLE IF NOT EXISTS recharge_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('ALIPAY')),
  product_id TEXT NOT NULL,
  -- 金额只由服务端按商品算，单位分；1 元 = 10 点。
  amount_fen INTEGER NOT NULL CHECK (amount_fen > 0),
  points INTEGER NOT NULL CHECK (points > 0),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID', 'CLOSED', 'REFUNDED')),
  provider_trade_no TEXT,
  credited_points INTEGER NOT NULL DEFAULT 0,
  debt_offset_points INTEGER NOT NULL DEFAULT 0,
  reversed_points INTEGER NOT NULL DEFAULT 0,
  debt_points INTEGER NOT NULL DEFAULT 0,
  provider_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS recharge_orders_provider_trade_idx
  ON recharge_orders(channel, provider_trade_no) WHERE provider_trade_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS recharge_orders_user_created_idx
  ON recharge_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS recharge_orders_pending_idx
  ON recharge_orders(created_at) WHERE status = 'PENDING';

-- 兑换码只存 SHA-256，明文只在生成时打印一次。
CREATE TABLE IF NOT EXISTS redeem_codes (
  code_hash TEXT PRIMARY KEY,
  batch TEXT NOT NULL,
  points INTEGER NOT NULL CHECK (points > 0),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  redeemed_by UUID REFERENCES app_users(id) ON DELETE SET NULL,
  redeemed_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS redeem_codes_batch_idx ON redeem_codes(batch);

-- 迁移以 postgres 执行，新表归 postgres 所有；服务账号（现有表的属主）要能读写。
-- redeem_codes 的 INSERT 给 scripts/redeem-codes.mjs（用服务的 DATABASE_URL 写库）。
DO $$
DECLARE application_role NAME;
BEGIN
  SELECT tableowner INTO application_role FROM pg_tables
    WHERE schemaname='public' AND tablename='point_wallets';
  IF application_role IS NOT NULL AND application_role <> current_user THEN
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE recharge_orders TO %I', application_role);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE redeem_codes TO %I', application_role);
  END IF;
END
$$;

COMMIT;
