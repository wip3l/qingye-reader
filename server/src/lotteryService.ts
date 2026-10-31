import { createHash, randomBytes, randomInt } from 'node:crypto';
import { MembershipError, MembershipSku } from './membershipPolicy.js';
import { MembershipDb, cloudQuotaBytes } from './membershipService.js';

/**
 * Web lottery. The page has no Huawei sign-in: an account proves ownership by adding a short code to
 * its nickname from the app, which only a signed-in owner can do. Prizes are coupons that the
 * membership quote applies by itself, so the app needs no change.
 */
export const VERIFY_TTL_MS = 10 * 60 * 1000;
export const WEB_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_VERIFY_CHECKS = 60;
// No 0/O, 1/I/L: the code is read off a screen and typed into the app.
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 6;
const DEFAULT_DISPLAY_NAME = '华为用户';

export type SuperChoice = 'COUPON' | 'CLOUD';
export type RandomInt = (max: number) => number;

const fail = (status: number, code: string, message: string): never => {
  throw new MembershipError(status, code, message);
};
export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
const newToken = () => randomBytes(32).toString('base64url');

function newCode(random: RandomInt): string {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[random(CODE_ALPHABET.length)];
  return code;
}

/** Removes every occurrence of the code, ignoring case, and tidies the spaces it leaves behind. */
export function stripVerificationCode(displayName: string, code: string): string {
  const escaped = code.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const stripped = displayName.replace(new RegExp(escaped, 'gi'), ' ').replace(/\s+/g, ' ').trim();
  return stripped || DEFAULT_DISPLAY_NAME;
}

export async function startVerification(db: MembershipDb, clientIp: string, now = Date.now(),
  random: RandomInt = randomInt) {
  let code = newCode(random);
  // Two pending codes must never match the same nickname.
  for (let attempt = 0; attempt < 5; attempt++) {
    const clash = await db.query(`SELECT 1 FROM lottery_web_verifications
      WHERE code = $1 AND expires_at > $2 AND user_id IS NULL`, [code, new Date(now)]);
    if (!clash.rowCount) break;
    if (attempt === 4) fail(503, 'LOTTERY_BUSY', '验证码生成失败，请稍后重试');
    code = newCode(random);
  }
  const token = newToken();
  const expiresAt = now + VERIFY_TTL_MS;
  await db.query(`INSERT INTO lottery_web_verifications(token_hash, code, client_ip, created_at, expires_at)
    VALUES ($1, $2, $3, $4, $5)`, [hashToken(token), code, clientIp, new Date(now), new Date(expiresAt)]);
  return { token, code, expiresAt };
}

export type VerificationResult =
  | { verified: false; expiresAt: number }
  | { verified: true; userId: string; sessionToken: string; sessionExpiresAt: number; displayName: string };

/** Binds the browser to the one account whose nickname gained the code after it was issued. */
export async function checkVerification(db: MembershipDb, token: string, now = Date.now()): Promise<VerificationResult> {
  const rows = await db.query<{ id: string; code: string; attempts: number; created_at: Date; expires_at: Date }>(
    `SELECT id, code, attempts, created_at, expires_at FROM lottery_web_verifications
     WHERE token_hash = $1 AND user_id IS NULL FOR UPDATE`, [hashToken(token)]);
  const verification = rows.rows[0];
  if (!verification || verification.expires_at.getTime() <= now || verification.attempts >= MAX_VERIFY_CHECKS) {
    return fail(410, 'LOTTERY_VERIFY_EXPIRED', '验证码已失效，请重新获取');
  }
  await db.query('UPDATE lottery_web_verifications SET attempts = attempts + 1 WHERE id = $1', [verification.id]);
  const matches = await db.query<{ id: string; display_name: string }>(`SELECT id, display_name FROM app_users
    WHERE updated_at >= $1 AND position($2 IN upper(display_name)) > 0 LIMIT 2`,
  [verification.created_at, verification.code]);
  if (matches.rows.length === 0) return { verified: false, expiresAt: verification.expires_at.getTime() };
  if (matches.rows.length > 1) {
    await db.query('UPDATE lottery_web_verifications SET expires_at = $2 WHERE id = $1', [verification.id, new Date(now)]);
    return fail(409, 'LOTTERY_VERIFY_AMBIGUOUS', '验证码匹配到多个账号，请重新获取验证码');
  }
  const user = matches.rows[0]!;
  const displayName = stripVerificationCode(user.display_name, verification.code);
  // profile_customized was already set by the app's edit, so a later sign-in keeps this name.
  await db.query('UPDATE app_users SET display_name = $2, updated_at = now() WHERE id = $1', [user.id, displayName]);
  await db.query('UPDATE lottery_web_verifications SET user_id = $2, verified_at = $3 WHERE id = $1',
    [verification.id, user.id, new Date(now)]);
  const sessionToken = newToken();
  const sessionExpiresAt = now + WEB_SESSION_TTL_MS;
  await db.query(`INSERT INTO lottery_web_sessions(token_hash, user_id, created_at, expires_at)
    VALUES ($1, $2, $3, $4)`, [hashToken(sessionToken), user.id, new Date(now), new Date(sessionExpiresAt)]);
  return { verified: true, userId: user.id, sessionToken, sessionExpiresAt, displayName };
}

export async function sessionUserId(db: MembershipDb, token: string, now = Date.now()): Promise<string | null> {
  const row = await db.query<{ user_id: string }>(`SELECT user_id FROM lottery_web_sessions
    WHERE token_hash = $1 AND expires_at > $2`, [hashToken(token), new Date(now)]);
  return row.rows[0]?.user_id ?? null;
}

export async function endSession(db: MembershipDb, token: string): Promise<void> {
  await db.query('DELETE FROM lottery_web_sessions WHERE token_hash = $1', [hashToken(token)]);
}

interface CampaignRow {
  id: string; title: string; starts_at: Date; ends_at: Date; registered_before: Date; enabled: boolean;
  super_no_coupon_quota_bytes: string | null; draws_per_user: number;
}
interface PrizeRow {
  id: string; label: string; weight: number; stock: number | null; issued: number;
  discounts: Partial<Record<MembershipSku, number>>; is_fallback: boolean; sort_order: number;
}

async function campaign(db: MembershipDb, campaignId: string): Promise<CampaignRow> {
  const row = await db.query<CampaignRow>('SELECT * FROM lottery_campaigns WHERE id = $1', [campaignId]);
  return row.rows[0] ?? fail(404, 'LOTTERY_NOT_FOUND', '活动不存在');
}

const campaignStatus = (row: CampaignRow, now: number) =>
  !row.enabled ? 'CLOSED' : now < row.starts_at.getTime() ? 'NOT_STARTED' : now >= row.ends_at.getTime() ? 'ENDED' : 'OPEN';

async function prizes(db: MembershipDb, campaignId: string): Promise<PrizeRow[]> {
  return (await db.query<PrizeRow>('SELECT * FROM lottery_prizes WHERE campaign_id = $1 ORDER BY sort_order, id',
    [campaignId])).rows;
}

async function ineligibleReason(db: MembershipDb, row: CampaignRow, userId: string): Promise<string | null> {
  const user = await db.query<{ created_at: Date }>('SELECT created_at FROM app_users WHERE id = $1', [userId]);
  if (!user.rows[0]) return fail(401, 'LOTTERY_SIGNED_OUT', '账号不存在，请重新验证');
  if (user.rows[0].created_at.getTime() >= row.registered_before.getTime()) return 'REGISTERED_TOO_LATE';
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  if (Number(debt.rows[0]?.iap_debt_points ?? 0) > 0) return 'PAYMENT_RESTRICTED';
  return null;
}

interface CouponRow {
  id: string; prize_id: string; discounts: Record<string, number>; status: string; super_choice: SuperChoice;
  used_at: Date | null;
}

/** The account's coupon for a campaign: the newest one not retired by an upgrade. */
async function currentCoupon(db: MembershipDb, campaignId: string, userId: string): Promise<CouponRow | null> {
  const row = await db.query<CouponRow>(`SELECT id, prize_id, discounts, status, super_choice, used_at
    FROM membership_coupons WHERE campaign_id = $1 AND user_id = $2 AND status <> 'REPLACED'
    ORDER BY created_at DESC, id DESC LIMIT 1`, [campaignId, userId]);
  return row.rows[0] ?? null;
}

const couponView = (coupon: CouponRow | null) => coupon && {
  id: coupon.id, prizeId: coupon.prize_id, discounts: coupon.discounts, status: coupon.status,
  superChoice: coupon.super_choice, usedAt: coupon.used_at?.getTime() ?? null
};

async function drawHistory(db: MembershipDb, campaignId: string, userId: string) {
  const rows = await db.query<{ draw_no: number; prize_id: string; label: string; kept: boolean; created_at: Date }>(
    `SELECT d.draw_no, d.prize_id, p.label, d.kept, d.created_at FROM lottery_draws d
     JOIN lottery_prizes p ON p.id = d.prize_id
     WHERE d.campaign_id = $1 AND d.user_id = $2 ORDER BY d.draw_no`, [campaignId, userId]);
  return rows.rows.map(row => ({ drawNo: row.draw_no, prizeId: row.prize_id, label: row.label, kept: row.kept,
    drawnAt: row.created_at.getTime() }));
}

export async function lotteryState(db: MembershipDb, campaignId: string, userId: string | null, now = Date.now()) {
  const row = await campaign(db, campaignId);
  const prizeRows = await prizes(db, campaignId);
  const totalWeight = prizeRows.reduce((sum, prize) => sum + prize.weight, 0);
  const result = {
    campaign: {
      id: row.id, title: row.title, status: campaignStatus(row, now), startsAt: row.starts_at.getTime(),
      endsAt: row.ends_at.getTime(), registeredBefore: row.registered_before.getTime(),
      drawsPerUser: row.draws_per_user,
      superCloudQuotaBytes: row.super_no_coupon_quota_bytes === null ? null : Number(row.super_no_coupon_quota_bytes)
    },
    prizes: prizeRows.map(prize => ({
      id: prize.id, label: prize.label, discounts: prize.discounts,
      probability: totalWeight > 0 ? prize.weight / totalWeight : 0,
      limited: prize.stock !== null, remaining: prize.stock === null ? null : Math.max(0, prize.stock - prize.issued)
    })),
    account: null as null | {
      displayName: string; ineligibleReason: string | null;
      draws: Awaited<ReturnType<typeof drawHistory>>; drawsLeft: number; coupon: ReturnType<typeof couponView>;
      cloudQuotaBytes: number; cloudBonus: boolean;
    }
  };
  if (userId) {
    const user = await db.query<{ display_name: string }>('SELECT display_name FROM app_users WHERE id = $1', [userId]);
    if (user.rows[0]) {
      const bonus = await db.query('SELECT 1 FROM cloud_quota_bonuses WHERE user_id = $1 AND campaign_id = $2',
        [userId, campaignId]);
      const draws = await drawHistory(db, campaignId, userId);
      const coupon = await currentCoupon(db, campaignId, userId);
      result.account = {
        displayName: user.rows[0].display_name,
        ineligibleReason: await ineligibleReason(db, row, userId),
        draws,
        // A spent coupon ends the account's draws: there is nothing left to upgrade.
        drawsLeft: coupon && coupon.status !== 'AVAILABLE' ? 0 : Math.max(0, row.draws_per_user - draws.length),
        coupon: couponView(coupon),
        cloudQuotaBytes: await cloudQuotaBytes(db, userId),
        cloudBonus: !!bonus.rowCount
      };
    }
  }
  return result;
}

/** Weighted pick; returns the index into prizes. */
function pickPrize(prizeRows: readonly PrizeRow[], random: RandomInt): number {
  const total = prizeRows.reduce((sum, prize) => sum + prize.weight, 0);
  let ticket = random(total);
  for (let i = 0; i < prizeRows.length; i++) {
    ticket -= prizeRows[i]!.weight;
    if (ticket < 0) return i;
  }
  return prizeRows.length - 1;
}

const soldOut = (prize: PrizeRow) => prize.stock !== null && prize.issued >= prize.stock;

/**
 * Draw number `drawNo` (1-based) for an account. Each campaign allows draws_per_user draws; the account keeps
 * one coupon, replaced whenever a draw beats it (lower sort_order is better). A limited prize's `issued`
 * counts current holders, so an upgrade returns the old prize to stock. Repeating a draw number, as a retry
 * does, returns that draw instead of drawing again.
 */
export async function drawLottery(db: MembershipDb, campaignId: string, userId: string, drawNo: number,
  clientIp: string, now = Date.now(), random: RandomInt = randomInt) {
  if (!Number.isSafeInteger(drawNo) || drawNo < 1) fail(400, 'LOTTERY_INVALID_DRAW', '抽奖次序无效，请刷新页面');
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`lottery:${campaignId}:${userId}`]);
  const history = await drawHistory(db, campaignId, userId);
  const repeated = history[drawNo - 1];
  if (repeated) return { duplicate: true, draw: repeated, coupon: couponView(await currentCoupon(db, campaignId, userId)) };
  const row = await campaign(db, campaignId);
  if (history.length >= row.draws_per_user) fail(409, 'LOTTERY_NO_DRAWS_LEFT', '抽奖次数已用完');
  if (drawNo !== history.length + 1) fail(409, 'LOTTERY_DRAW_OUT_OF_ORDER', '抽奖状态已变化，请刷新页面');
  const status = campaignStatus(row, now);
  if (status === 'NOT_STARTED') fail(409, 'LOTTERY_NOT_STARTED', '活动尚未开始');
  if (status === 'ENDED') fail(409, 'LOTTERY_ENDED', '活动已结束');
  if (status !== 'OPEN') fail(409, 'LOTTERY_CLOSED', '活动暂未开放');
  const reason = await ineligibleReason(db, row, userId);
  if (reason === 'REGISTERED_TOO_LATE') fail(403, 'LOTTERY_INELIGIBLE', '本活动仅限活动截止日期前注册的账号参加');
  if (reason) fail(403, 'ACCOUNT_PAYMENT_RESTRICTED', '账号存在退款欠款，请先补齐');
  const coupon = await currentCoupon(db, campaignId, userId);
  if (coupon && coupon.status !== 'AVAILABLE') fail(409, 'LOTTERY_COUPON_USED', '抵扣券已经使用，不能继续抽奖');
  const prizeRows = await prizes(db, campaignId);
  const fallback = prizeRows.find(prize => prize.is_fallback);
  if (!prizeRows.length || !fallback) return fail(503, 'LOTTERY_MISCONFIGURED', '活动奖品尚未配置');
  const held = coupon ? prizeRows.find(prize => prize.id === coupon.prize_id) : undefined;
  const beats = (prize: PrizeRow) => !coupon || !held || prize.sort_order < held.sort_order;
  const picked = prizeRows[pickPrize(prizeRows, random)]!;
  let result = soldOut(picked) ? fallback : picked;
  let kept = false;
  if (beats(result)) {
    // Conditional increment: a limited prize sold out meanwhile falls through to the unlimited fallback.
    const claimed = (await db.query<PrizeRow>(`UPDATE lottery_prizes SET issued = issued + 1
      WHERE id = $1 AND (stock IS NULL OR issued < stock) RETURNING *`, [result.id])).rows[0];
    if (claimed) {
      result = claimed;
      kept = true;
    } else {
      result = fallback;
      if (beats(fallback)) {
        result = (await db.query<PrizeRow>('UPDATE lottery_prizes SET issued = issued + 1 WHERE id = $1 RETURNING *',
          [fallback.id])).rows[0]!;
        kept = true;
      }
    }
  }
  let couponId = coupon?.id;
  if (kept) {
    if (coupon) {
      const retired = await db.query(`UPDATE membership_coupons SET status = 'REPLACED'
        WHERE id = $1 AND status = 'AVAILABLE'`, [coupon.id]);
      // Spent by a purchase committed meanwhile; the whole draw rolls back.
      if (!retired.rowCount) fail(409, 'LOTTERY_COUPON_USED', '抵扣券已经使用，不能继续抽奖');
      await db.query('UPDATE lottery_prizes SET issued = issued - 1 WHERE id = $1 AND issued > 0', [coupon.prize_id]);
    }
    couponId = (await db.query<{ id: string }>(`INSERT INTO membership_coupons
      (user_id, campaign_id, prize_id, discounts, created_at) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [userId, campaignId, result.id, JSON.stringify(result.discounts), new Date(now)])).rows[0]!.id;
  }
  await db.query(`INSERT INTO lottery_draws(campaign_id, user_id, draw_no, prize_id, coupon_id, kept, client_ip, created_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`, [campaignId, userId, drawNo, result.id, couponId, kept, clientIp, new Date(now)]);
  return {
    duplicate: false,
    draw: { drawNo, prizeId: result.id, label: result.label, kept, drawnAt: now },
    coupon: couponView(await currentCoupon(db, campaignId, userId))
  };
}

/**
 * Chooses between the coupon and the campaign's cloud quota for a super membership. Shares the
 * membership purchase lock, so a quote and its purchase never see different choices unnoticed.
 */
export async function setSuperChoice(db: MembershipDb, campaignId: string, userId: string, choice: unknown) {
  if (choice !== 'COUPON' && choice !== 'CLOUD') fail(400, 'LOTTERY_INVALID_CHOICE', '请选择用券或提升云空间');
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`membership:${userId}`]);
  const updated = await db.query(`UPDATE membership_coupons SET super_choice = $3
    WHERE user_id = $1 AND campaign_id = $2 AND status = 'AVAILABLE'`, [userId, campaignId, choice]);
  if (!updated.rowCount) fail(409, 'LOTTERY_COUPON_UNAVAILABLE', '没有可修改的抵扣券，券可能已经使用');
}
