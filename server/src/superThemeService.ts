import type { MembershipDb } from './membershipService.js';
import { membershipSnapshot } from './membershipService.js';
import { MembershipError, membershipAnniversary } from './membershipPolicy.js';
import { SUPER_CLAIM_THEME_IDS } from './themeCatalog.js';

export const SUPER_THEME_ID = 'obsidian-archive';

/** Run in a transaction. One live annual grant per theme; repeated requests never extend it. */
export async function claimSuperTheme(db: MembershipDb, userId: string, themeId: string,
  requestId: string, now = Date.now()) {
  if (!SUPER_CLAIM_THEME_IDS.includes(themeId)) throw new MembershipError(404, 'THEME_NOT_FOUND', '专属主题不存在');
  if (typeof requestId !== 'string' || !requestId.trim() || requestId.length > 128) {
    throw new MembershipError(400, 'INVALID_REQUEST_ID', '请求标识无效');
  }
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`membership:${userId}`]);
  const member = await membershipSnapshot(db, userId, now);
  if (!member.active || member.state?.sku !== 'SUPER_LIFETIME') {
    throw new MembershipError(403, 'SUPER_THEME_REQUIRED', '仅有效的终身超级会员可领取专属主题');
  }
  // The catalog is administrator-owned in production; application access is SELECT-only.
  // Claim serialization uses the user advisory lock, not a catalog row lock (which needs UPDATE).
  const theme = await db.query(`SELECT 1 FROM theme_catalog WHERE theme_id=$1 AND enabled=TRUE
    AND acquisition='SUPER_CLAIM' AND member_included=FALSE AND price_points=0`, [themeId]);
  if (!theme.rowCount) throw new MembershipError(404, 'THEME_NOT_FOUND', '专属主题暂未开放领取');
  const oldRequest = (await db.query<{ theme_id: string; expires_at: Date }>(
    'SELECT theme_id,expires_at FROM membership_theme_claims WHERE user_id=$1 AND request_id=$2',
    [userId, requestId.trim()])).rows[0];
  if (oldRequest) {
    if (oldRequest.theme_id !== themeId) throw new MembershipError(409, 'REQUEST_CONFLICT', '请求标识已用于其他主题');
    return { themeId, expiresAt: oldRequest.expires_at.getTime(), duplicate: true };
  }
  const current = (await db.query<{ expires_at: Date }>(
    'SELECT expires_at FROM theme_entitlements WHERE user_id=$1 AND theme_id=$2 FOR UPDATE',
    [userId, themeId])).rows[0];
  const duplicate = !!current && current.expires_at.getTime() > now;
  // A year follows the Beijing calendar anniversary, including Feb 29 -> Feb 28.
  const expiresAt = duplicate ? current!.expires_at.getTime() : membershipAnniversary(now, 12);
  if (!duplicate) {
    await db.query(`INSERT INTO theme_entitlements(user_id,theme_id,expires_at) VALUES($1,$2,$3)
      ON CONFLICT(user_id,theme_id) DO UPDATE SET expires_at=EXCLUDED.expires_at,updated_at=now()`,
      [userId, themeId, new Date(expiresAt)]);
  }
  // Remember no-op requests too: a delayed retry after expiry must not silently renew.
  await db.query(`INSERT INTO membership_theme_claims(user_id,theme_id,request_id,claimed_at,expires_at)
    VALUES($1,$2,$3,$4,$5)`, [userId, themeId, requestId.trim(), new Date(now), new Date(expiresAt)]);
  return { themeId, expiresAt, duplicate };
}
