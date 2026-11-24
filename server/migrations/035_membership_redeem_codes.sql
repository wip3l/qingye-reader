-- 会员兑换码：membership_sku 不为空的兑换码兑换时直接开通该会员（服务端在同一事务里记入充值点再按正常流程购买，
-- 续费叠加、升级抵扣、促销价都与应用内购买一致；实付比码面值少时差额留作充值点）。为空的仍是点数兑换码。
-- 表级授权（034）已覆盖新列，无需另行授权。

BEGIN;

ALTER TABLE redeem_codes ADD COLUMN IF NOT EXISTS membership_sku TEXT
  CHECK (membership_sku IN ('MONTHLY', 'ANNUAL', 'LIFETIME', 'SUPER_LIFETIME'));

COMMIT;
