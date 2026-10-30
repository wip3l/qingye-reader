import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { MembershipSalesPilot, pilotAllows } from './membershipSales.js';
import {
  MEMBERSHIP_POLICY_VERSION, MEMBERSHIP_PRODUCTS, MembershipError, MembershipPrice, MembershipState, basePrice,
  MembershipPurchasePlan, MembershipSku, VoiceTier, membershipActive, membershipBenefits,
  membershipCouponPoints, membershipCycle, membershipGiftCycle, membershipGiftChars, membershipProduct,
  planMembershipPurchase
} from './membershipPolicy.js';

export interface MembershipDb { query: PoolClient['query']; }

/** Standard super-member cloud storage; a campaign bonus can raise an account above it. */
export const CLOUD_BASE_QUOTA_BYTES = 1024 ** 3;

export async function cloudQuotaBytes(db: MembershipDb, userId: string): Promise<number> {
  const bonus = await db.query<{ quota_bytes: string }>(
    'SELECT quota_bytes FROM cloud_quota_bonuses WHERE user_id = $1', [userId]);
  return Math.max(CLOUD_BASE_QUOTA_BYTES, Number(bonus.rows[0]?.quota_bytes ?? 0));
}

interface CouponRow { id: string; discounts: unknown; expires_at: Date | null; }

/** The available coupon taking the most off this quote; a super purchase skips coupons traded for cloud space. */
async function bestCoupon(db: MembershipDb, userId: string, sku: MembershipSku, payablePoints: number, now: number) {
  const coupons = await db.query<CouponRow>(`SELECT id, discounts, expires_at FROM membership_coupons
    WHERE user_id = $1 AND status = 'AVAILABLE' AND (expires_at IS NULL OR expires_at > $2)
      AND discounts ->> $3 IS NOT NULL AND NOT ($3 = 'SUPER_LIFETIME' AND super_choice = 'CLOUD')
    ORDER BY created_at, id`, [userId, new Date(now), sku]);
  let best: { id: string; points: number; expiresAt: number | null } | null = null;
  for (const row of coupons.rows) {
    const points = membershipCouponPoints(row.discounts, sku, payablePoints);
    if (points > (best?.points ?? 0)) best = { id: row.id, points, expiresAt: row.expires_at?.getTime() ?? null };
  }
  return best;
}

/** A super membership paid without a coupon during an enabled campaign raises the account's cloud quota. */
async function grantCampaignCloudQuota(db: MembershipDb, userId: string, orderId: string, now: number) {
  const campaign = await db.query<{ id: string; quota: string }>(`SELECT id, super_no_coupon_quota_bytes AS quota
    FROM lottery_campaigns WHERE enabled AND starts_at <= $1 AND ends_at > $1
      AND super_no_coupon_quota_bytes IS NOT NULL
    ORDER BY super_no_coupon_quota_bytes DESC, id LIMIT 1`, [new Date(now)]);
  const row = campaign.rows[0];
  if (!row) return;
  await db.query(`INSERT INTO cloud_quota_bonuses(user_id, quota_bytes, campaign_id, order_id)
    VALUES ($1, $2, $3, $4) ON CONFLICT (user_id) DO UPDATE SET
      quota_bytes = EXCLUDED.quota_bytes, campaign_id = EXCLUDED.campaign_id, order_id = EXCLUDED.order_id
    WHERE cloud_quota_bonuses.quota_bytes < EXCLUDED.quota_bytes`, [userId, row.quota, row.id, orderId]);
}

export async function readMembership(db: MembershipDb, userId: string): Promise<MembershipState | null> {
  const result = await db.query<{
    id: string; sku: MembershipSku; anchor_at: Date; expires_at: Date | null;
    paid_months: number; permanent_credit_points: string; revision: number;
  }>(`SELECT p.*, a.revision FROM membership_accounts a
      JOIN membership_periods p ON p.id = a.period_id WHERE a.user_id = $1`, [userId]);
  const row = result.rows[0];
  return row ? {
    periodId: row.id, sku: row.sku, anchorAt: row.anchor_at.getTime(),
    expiresAt: row.expires_at?.getTime() ?? null, paidMonths: row.paid_months,
    permanentCreditPoints: Number(row.permanent_credit_points), revision: row.revision
  } : null;
}

/** Lightweight queue-priority check; refund debt suspends every paid benefit. */
export async function membershipPriority(db: MembershipDb, userId: string, now = Date.now()): Promise<boolean> {
  if (!membershipActive(await readMembership(db, userId), now)) return false;
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  return Number(debt.rows[0]?.iap_debt_points ?? 0) <= 0;
}

/**
 * The product that pays for `now`. A periodic period keeps the SKU of its latest purchase, so an annual
 * member who adds a month would otherwise look monthly; the covering order decides benefits instead.
 */
export async function membershipTierSku(db: MembershipDb, state: MembershipState, now = Date.now()): Promise<MembershipSku> {
  if (state.expiresAt === null) return state.sku;
  const covering = await db.query<{ sku: MembershipSku }>(`SELECT sku FROM membership_orders
    WHERE period_id = $1 AND term_starts_at <= $2 AND term_ends_at > $2
    ORDER BY term_starts_at DESC LIMIT 1`, [state.periodId, new Date(now)]);
  return covering.rows[0]?.sku ?? state.sku;
}

async function lockAccount(db: MembershipDb, userId: string): Promise<void> {
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`membership:${userId}`]);
}

async function assertNoDebt(db: MembershipDb, userId: string): Promise<void> {
  const result = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  if (Number(result.rows[0]?.iap_debt_points ?? 0) > 0) {
    throw new MembershipError(403, 'ACCOUNT_PAYMENT_RESTRICTED', '账号存在退款欠款，请先补齐');
  }
}

interface ProductRow { sku: MembershipSku; sales_enabled: boolean; sales_starts_at: Date | null; }

/** On sale when opened by hand, when the scheduled start has passed, or for a pilot account. */
function productOnSale(row: ProductRow | undefined, userId: string | undefined, now: number,
  pilot?: MembershipSalesPilot): boolean {
  if (!row) return false;
  return row.sales_enabled || (row.sales_starts_at != null && row.sales_starts_at.getTime() <= now) ||
    pilotAllows(pilot, userId, row.sku, now);
}

async function assertOnSale(db: MembershipDb, sku: MembershipSku, userId: string,
  now: number, pilot?: MembershipSalesPilot): Promise<void> {
  const result = await db.query<ProductRow>(
    'SELECT sku, sales_enabled, sales_starts_at FROM membership_products WHERE sku = $1 FOR SHARE', [sku]);
  if (!productOnSale(result.rows[0], userId, now, pilot)) {
    throw new MembershipError(409, 'MEMBERSHIP_NOT_ON_SALE', '该会员尚未开放购买');
  }
}

/** Active promotion prices; the lowest valid one per SKU wins. Never above the base price. */
async function activePrices(db: MembershipDb, now: number): Promise<Map<MembershipSku, MembershipPrice>> {
  const result = await db.query<{ id: string; sku: MembershipSku; price_points: string; label: string; ends_at: Date }>(
    `SELECT id, sku, price_points, label, ends_at FROM membership_promotions
     WHERE starts_at <= $1 AND ends_at > $1 ORDER BY price_points, id`, [new Date(now)]);
  const prices = new Map<MembershipSku, MembershipPrice>();
  for (const row of result.rows) {
    const product = MEMBERSHIP_PRODUCTS.find(item => item.sku === row.sku);
    const points = Number(row.price_points);
    if (!product || prices.has(row.sku) || !Number.isSafeInteger(points) || points <= 0 || points >= product.points) continue;
    prices.set(row.sku, { pricePoints: points, promotionId: row.id, promotionLabel: row.label,
      promotionEndsAt: row.ends_at.getTime() });
  }
  return prices;
}

export async function membershipPrice(db: MembershipDb, sku: MembershipSku, now = Date.now()): Promise<MembershipPrice> {
  membershipProduct(sku);
  return (await activePrices(db, now)).get(sku) ?? basePrice(sku);
}

/** The running or next promotion per SKU, so the store can announce a launch price before it starts. */
async function nextPromotions(db: MembershipDb, now: number) {
  const result = await db.query<{ sku: MembershipSku; price_points: string; label: string; starts_at: Date; ends_at: Date }>(
    `SELECT sku, price_points, label, starts_at, ends_at FROM membership_promotions
     WHERE ends_at > $1 ORDER BY starts_at, price_points, id`, [new Date(now)]);
  const promotions = new Map<MembershipSku, { pricePoints: number; label: string; startsAt: number; endsAt: number }>();
  for (const row of result.rows) {
    const product = MEMBERSHIP_PRODUCTS.find(item => item.sku === row.sku);
    const points = Number(row.price_points);
    if (!product || promotions.has(row.sku) || !Number.isSafeInteger(points) || points <= 0 || points >= product.points) continue;
    promotions.set(row.sku, { pricePoints: points, label: row.label, startsAt: row.starts_at.getTime(), endsAt: row.ends_at.getTime() });
  }
  return promotions;
}

export async function membershipCatalog(db: MembershipDb, userId?: string,
  now = Date.now(), pilot?: MembershipSalesPilot) {
  const result = await db.query<ProductRow>('SELECT sku, sales_enabled, sales_starts_at FROM membership_products');
  const prices = await activePrices(db, now);
  const promotions = await nextPromotions(db, now);
  return MEMBERSHIP_PRODUCTS.map((product) => {
    const row = result.rows.find(item => item.sku === product.sku);
    const price = prices.get(product.sku) ?? basePrice(product.sku);
    return {
      ...product,
      salesEnabled: productOnSale(row, userId, now, pilot),
      salesStartsAt: row?.sales_starts_at?.getTime() ?? null,
      // The price a quote would charge now; `points` stays the regular price.
      pricePoints: price.pricePoints,
      promotion: promotions.get(product.sku) ?? null
    };
  });
}

/** The account can claim once per calendar month, even after an upgrade or a new paid period. */
async function readGiftClaim(db: MembershipDb, userId: string, cycle: ReturnType<typeof membershipGiftCycle>) {
  const result = await db.query<{ tier: VoiceTier; chars: number }>(
    `SELECT tier, chars FROM membership_gift_claims WHERE user_id=$1 AND
      (gift_month=$2 OR (gift_month IS NULL AND created_at >= $3 AND created_at < $4))
     ORDER BY created_at, period_id, cycle_index LIMIT 1`,
    [userId, cycle.index, new Date(cycle.startsAt), new Date(cycle.endsAt)]);
  return result.rows[0] ?? null;
}

export async function membershipSnapshot(db: MembershipDb, userId: string, now = Date.now()) {
  const state = await readMembership(db, userId);
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  const restricted = Number(debt.rows[0]?.iap_debt_points ?? 0) > 0;
  const active = !restricted && membershipActive(state, now);
  const cycle = active ? membershipCycle(state!, now) : null;
  const giftCycle = active ? membershipGiftCycle(state!, now) : null;
  const tierSku = active ? await membershipTierSku(db, state!, now) : null;
  const claim = giftCycle ? await readGiftClaim(db, userId, giftCycle) : null;
  const benefits = membershipBenefits(active ? state : null, now, tierSku ?? undefined);
  if (benefits.cloudStorageBytes > 0) benefits.cloudStorageBytes = await cloudQuotaBytes(db, userId);
  return {
    state, active, restricted, cycle, giftCycle, tierSku, claim, benefits,
    serverNow: now
  };
}

/** Call inside a transaction; quote fixes proration for 15 minutes. */
export async function quoteMembership(db: MembershipDb, userId: string, sku: MembershipSku,
  now = Date.now(), pilot?: MembershipSalesPilot) {
  membershipProduct(sku);
  await lockAccount(db, userId);
  await assertNoDebt(db, userId);
  await assertOnSale(db, sku, userId, now, pilot);
  const state = await readMembership(db, userId);
  const price = await membershipPrice(db, sku, now);
  const terms = state ? await db.query<{ term_starts_at: Date; term_ends_at: Date; points_spent: string }>(
    `SELECT term_starts_at, term_ends_at, points_spent FROM membership_orders
     WHERE period_id = $1 AND term_ends_at > $2`, [state.periodId, new Date(now)]) : null;
  const priorTerms = (terms?.rows ?? []).map(row => ({
    startsAt: row.term_starts_at.getTime(), endsAt: row.term_ends_at.getTime(), points: Number(row.points_spent)
  }));
  const periodId = randomUUID();
  let plan = planMembershipPurchase(state, priorTerms, sku, now, periodId, price);
  // Coupons apply automatically: the app shows the charged points in its confirmation and has no coupon picker.
  const coupon = await bestCoupon(db, userId, sku, plan.payablePoints, now);
  if (coupon) plan = planMembershipPurchase(state, priorTerms, sku, now, periodId, price, coupon);
  const quoteId = randomUUID();
  // Do not let a renewal quote cross the old membership's expiry, nor a promotion price or coupon outlive it.
  const expiresAt = Math.min(now + 15 * 60 * 1000,
    membershipActive(state, now) ? state!.expiresAt ?? Infinity : Infinity,
    price.promotionEndsAt ?? Infinity, coupon?.expiresAt ?? Infinity);
  await db.query(`INSERT INTO membership_quotes(id, user_id, policy_version, plan, expires_at)
    VALUES ($1,$2,$3,$4::jsonb,$5)`, [quoteId, userId, MEMBERSHIP_POLICY_VERSION, JSON.stringify(plan), new Date(expiresAt)]);
  return { quoteId, expiresAt, ...plan };
}

/** Wallet, ledger, membership, order and grant expiry changes commit atomically. */
export async function purchaseMembership(
  db: MembershipDb, userId: string, quoteId: string, requestId: string, now = Date.now(),
  pilot?: MembershipSalesPilot
) {
  if (typeof requestId !== 'string' || !requestId.trim() || requestId.length > 128 ||
      typeof quoteId !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(quoteId)) {
    throw new MembershipError(400, 'INVALID_MEMBERSHIP_REQUEST', '购买请求标识无效');
  }
  await lockAccount(db, userId);
  const duplicate = await db.query<{ id: string; quote_id: string }>(
    'SELECT id, quote_id FROM membership_orders WHERE user_id = $1 AND request_id = $2', [userId, requestId]);
  if (duplicate.rows[0]) {
    if (duplicate.rows[0].quote_id !== quoteId) {
      throw new MembershipError(409, 'MEMBERSHIP_REQUEST_CONFLICT', '相同请求标识不能购买不同报价');
    }
    return { orderId: duplicate.rows[0].id, duplicate: true };
  }
  // A second request ID for a consumed quote also returns the original order.
  const consumed = await db.query<{ id: string }>(
    'SELECT id FROM membership_orders WHERE user_id = $1 AND quote_id = $2', [userId, quoteId]);
  if (consumed.rows[0]) return { orderId: consumed.rows[0].id, duplicate: true };
  const quotes = await db.query<{ plan: MembershipPurchasePlan; expires_at: Date; policy_version: number }>(
    'SELECT plan, expires_at, policy_version FROM membership_quotes WHERE id = $1 AND user_id = $2 FOR UPDATE',
    [quoteId, userId]);
  const quote = quotes.rows[0];
  if (!quote || quote.expires_at.getTime() <= now || quote.policy_version !== MEMBERSHIP_POLICY_VERSION) {
    throw new MembershipError(409, 'MEMBERSHIP_QUOTE_EXPIRED', '报价已过期，请重新查看价格');
  }
  const plan = quote.plan;
  await assertOnSale(db, plan.sku, userId, now, pilot);
  const state = await readMembership(db, userId);
  if ((state?.revision ?? 0) !== plan.expectedRevision) {
    throw new MembershipError(409, 'MEMBERSHIP_OFFER_CHANGED', '会员状态已变化，请重新查看价格');
  }
  const couponId = plan.couponId ?? null;
  const couponPoints = plan.couponPoints ?? 0;
  if (couponId) {
    const coupon = await db.query<{ status: string; expires_at: Date | null; super_choice: string }>(
      'SELECT status, expires_at, super_choice FROM membership_coupons WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [couponId, userId]);
    const row = coupon.rows[0];
    if (!row || row.status !== 'AVAILABLE' || (row.expires_at && row.expires_at.getTime() <= now) ||
        (plan.sku === 'SUPER_LIFETIME' && row.super_choice !== 'COUPON')) {
      throw new MembershipError(409, 'MEMBERSHIP_OFFER_CHANGED', '会员状态已变化，请重新查看价格');
    }
  }
  const wallets = await db.query<{ balance: string; paid_balance: string }>(
    'SELECT balance, paid_balance FROM point_wallets WHERE user_id = $1 FOR UPDATE', [userId]);
  await assertNoDebt(db, userId);
  const wallet = wallets.rows[0];
  if (!wallet || Number(wallet.paid_balance) < plan.payablePoints) {
    throw new MembershipError(409, 'INSUFFICIENT_PAID_POINTS', '充值点不足，赠送点不能用于购买会员');
  }
  const balanceAfter = Number(wallet.balance) - plan.payablePoints;
  await db.query(`UPDATE point_wallets SET balance = balance - $2, paid_balance = paid_balance - $2,
    updated_at = now() WHERE user_id = $1`, [userId, plan.payablePoints]);
  const ledger = await db.query<{ id: string }>(`INSERT INTO point_ledger
    (user_id, delta, balance_after, reason, reference_id, idempotency_key)
    VALUES ($1,$2,$3,'MEMBERSHIP_PURCHASE',$4,$5) RETURNING id`,
    [userId, -plan.payablePoints, balanceAfter, plan.sku, `membership:${userId}:${requestId}`]);
  // A new period starts at payment, rather than the potentially earlier quote time.
  const next = plan.newPeriod
    ? planMembershipPurchase(state, [], plan.sku, now, plan.next.periodId, {
      pricePoints: plan.listPoints, promotionId: plan.promotionId ?? null, promotionLabel: null, promotionEndsAt: null
    }, couponId ? { id: couponId, points: couponPoints } : null).next : plan.next;
  await db.query(`INSERT INTO membership_periods
    (id,user_id,sku,anchor_at,paid_months,expires_at,permanent_credit_points)
    VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO UPDATE SET
    sku=EXCLUDED.sku, paid_months=EXCLUDED.paid_months, expires_at=EXCLUDED.expires_at,
    permanent_credit_points=EXCLUDED.permanent_credit_points`,
    [next.periodId, userId, next.sku, new Date(next.anchorAt), next.paidMonths,
      next.expiresAt === null ? null : new Date(next.expiresAt), next.permanentCreditPoints]);
  await db.query(`INSERT INTO membership_accounts(user_id,period_id,revision) VALUES ($1,$2,$3)
    ON CONFLICT(user_id) DO UPDATE SET period_id=EXCLUDED.period_id,revision=EXCLUDED.revision`,
    [userId, next.periodId, next.revision]);
  // The same locks as synthesis/refunds keep balances and expiry changes consistent.
  for (const tier of ['STANDARD', 'PREMIUM']) {
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`tts-quota:${userId}:${tier}`]);
  }
  await db.query(`UPDATE tts_quota_grants SET expires_at=$2::timestamptz, updated_at=now()
    WHERE membership_period_id=$1`, [next.periodId,
    next.expiresAt === null ? 'infinity' : new Date(next.expiresAt).toISOString()]);
  const order = await db.query<{ id: string }>(`INSERT INTO membership_orders
    (user_id,period_id,sku,request_id,quote_id,list_points,credit_points,points_spent,
     term_starts_at,term_ends_at,point_ledger_id,promotion_id,coupon_id,coupon_points)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING id`,
    [userId,next.periodId,plan.sku,requestId,quoteId,plan.listPoints,plan.creditPoints,plan.payablePoints,
      plan.term ? new Date(plan.newPeriod ? now : plan.term.startsAt) : null,
      plan.term ? new Date(next.expiresAt!) : null,ledger.rows[0]!.id,plan.promotionId ?? null,
      couponId,couponPoints]);
  const orderId = order.rows[0]!.id;
  if (couponId) {
    await db.query(`UPDATE membership_coupons SET status = 'USED', used_order_id = $2, used_at = $3
      WHERE id = $1`, [couponId, orderId, new Date(now)]);
  } else if (plan.sku === 'SUPER_LIFETIME') {
    await grantCampaignCloudQuota(db, userId, orderId, now);
  }
  return { orderId, duplicate: false };
}

export async function claimMembershipGift(db: MembershipDb, userId: string, tier: VoiceTier, now = Date.now()) {
  if (tier !== 'STANDARD' && tier !== 'PREMIUM') {
    throw new MembershipError(400, 'INVALID_TTS_TIER', '请选择标准或精品额度');
  }
  await lockAccount(db, userId);
  // Coordinate with IAP reconciliation before checking debt.
  await db.query('SELECT user_id FROM point_wallets WHERE user_id=$1 FOR UPDATE', [userId]);
  await assertNoDebt(db, userId);
  const state = await readMembership(db, userId);
  if (!state || !membershipActive(state, now)) {
    throw new MembershipError(403, 'MEMBERSHIP_INACTIVE', '请先开通有效会员');
  }
  const cycle = membershipGiftCycle(state, now);
  const prior = await readGiftClaim(db, userId, cycle);
  if (prior) {
    if (prior.tier !== tier) throw new MembershipError(409, 'MEMBERSHIP_GIFT_ALREADY_CLAIMED', '本月已领取另一档额度');
    return { ...prior, duplicate: true };
  }
  const chars = membershipGiftChars(await membershipTierSku(db, state, now), tier);
  if (chars <= 0) {
    throw new MembershipError(403, 'MEMBERSHIP_GIFT_NOT_INCLUDED', '月度会员不含每月朗读礼包，年度及终身会员可领取');
  }
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`tts-quota:${userId}:${tier}`]);
  const key = `membership-gift-month:${userId}:${cycle.index}`;
  const balance = await db.query<{ balance: string }>(`SELECT COALESCE(SUM(remaining_chars),0)::bigint AS balance
    FROM tts_quota_grants WHERE user_id=$1 AND tier=$2 AND remaining_chars>0 AND expires_at>$3`,
    [userId,tier,new Date(now)]);
  const grant = await db.query<{ id: string }>(`INSERT INTO tts_quota_grants
    (user_id,tier,source,total_chars,remaining_chars,expires_at,reference_id,membership_period_id)
    VALUES ($1,$2,'MEMBERSHIP',$3,$3,$4::timestamptz,$5,$6) RETURNING id`,
    [userId,tier,chars,state.expiresAt === null ? 'infinity' : new Date(state.expiresAt).toISOString(),key,state.periodId]);
  await db.query(`INSERT INTO tts_quota_ledger
    (user_id,grant_id,tier,delta_chars,balance_after,reason,reference_id,idempotency_key)
    VALUES ($1,$2,$3,$4,$5,'MEMBERSHIP_GIFT',$6,$6)`,
    [userId,grant.rows[0]!.id,tier,chars,Number(balance.rows[0]!.balance)+chars,key]);
  await db.query(`INSERT INTO membership_gift_claims
    (period_id,cycle_index,user_id,tier,chars,quota_grant_id,gift_month,created_at)
    VALUES ($1,$2,$3,$4,$5,$6,$2,$7)`,
    [state.periodId,cycle.index,userId,tier,chars,grant.rows[0]!.id,new Date(now)]);
  return { tier, chars, duplicate: false };
}
