import { createHash } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { MembershipDb } from './membershipService.js';
import {
  burnPasswordCheck,
  CredentialError,
  generateRecoveryCodes,
  hashPassword,
  loginLockMinutes,
  normalizeRecoveryCode,
  normalizeUsername,
  randomReaderName,
  validatePassword,
  verifyPassword
} from './accountCredentials.js';

export const ACCOUNT_DELETION_GRACE_DAYS = 7;
export const USERNAME_CHANGE_INTERVAL_DAYS = 30;
const WELCOME_POINTS = 300;
const REGISTRATIONS_PER_IP_PER_DAY = 20;

export class AccountAuthError extends Error {
  constructor(readonly statusCode: number, readonly code: string, message: string, readonly retryAfter = 0) {
    super(message);
  }
}

type Transaction = <T>(work: (client: MembershipDb) => Promise<T>) => Promise<T>;
type RecoveryHasher = (code: string) => string;

function fromCredential(error: unknown): never {
  if (error instanceof CredentialError) throw new AccountAuthError(400, error.code, error.message);
  throw error;
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === 'object' && error !== null && (error as { code?: string }).code === '23505';
}

const huaweiSubjectHash = (openId: string) => createHash('sha256').update(openId, 'utf8').digest('hex');

async function storeRecoveryCodes(db: MembershipDb, userId: string, hasher: RecoveryHasher): Promise<string[]> {
  const codes = generateRecoveryCodes();
  await db.query('DELETE FROM account_recovery_codes WHERE user_id = $1', [userId]);
  for (const code of codes) {
    await db.query('INSERT INTO account_recovery_codes (user_id, code_hash) VALUES ($1, $2)', [userId, hasher(code)]);
  }
  return codes;
}

/** 登录成功即撤销冷静期内的注销申请。 */
export async function cancelAccountDeletion(db: MembershipDb, userId: string): Promise<boolean> {
  const result = await db.query(`UPDATE app_users SET deletion_requested_at = NULL, updated_at = now()
    WHERE id = $1 AND deletion_requested_at IS NOT NULL AND deleted_at IS NULL`, [userId]);
  return (result.rowCount ?? 0) > 0;
}

/**
 * 每个华为账号只送一次 300 点：先占华为账号的领取记录，再按账号幂等记账。
 * 用户名注册的账号不送，绑定一个没领过的华为账号时补发。
 */
export async function grantHuaweiWelcome(db: MembershipDb, userId: string, openId: string): Promise<boolean> {
  const claim = await db.query(`INSERT INTO huawei_welcome_claims (huawei_subject_hash, user_id) VALUES ($1, $2)
    ON CONFLICT (huawei_subject_hash) DO NOTHING RETURNING huawei_subject_hash`, [huaweiSubjectHash(openId), userId]);
  if (!claim.rowCount) return false;
  await db.query(`INSERT INTO point_wallets (user_id, balance, paid_balance, promo_balance)
    VALUES ($1, 0, 0, 0) ON CONFLICT (user_id) DO NOTHING`, [userId]);
  const wallet = await db.query<{ balance: string }>(
    'SELECT balance FROM point_wallets WHERE user_id = $1 FOR UPDATE', [userId]);
  const balance = Number(wallet.rows[0]!.balance);
  const granted = await db.query(`INSERT INTO point_ledger (
      user_id, delta, balance_after, reason, reference_id, idempotency_key
    ) VALUES ($1, $2, $3, 'WELCOME_GRANT', $4, $5)
    ON CONFLICT (idempotency_key) DO NOTHING RETURNING id`,
  [userId, WELCOME_POINTS, balance + WELCOME_POINTS, userId, `welcome:${userId}`]);
  if (!granted.rowCount) return false;
  await db.query(`UPDATE point_wallets SET balance = balance + $2, promo_balance = promo_balance + $2,
    updated_at = now() WHERE user_id = $1`, [userId, WELCOME_POINTS]);
  return true;
}

export interface RegisterInput { username?: unknown; password?: unknown; ip?: string; }

export async function registerPasswordAccount(tx: Transaction, input: RegisterInput,
  hasher: RecoveryHasher): Promise<{ userId: string; recoveryCodes: string[] }> {
  let name;
  let password;
  try {
    name = normalizeUsername(input.username);
    password = validatePassword(input.password, name.username);
  } catch (error) {
    fromCredential(error);
  }
  const passwordHash = await hashPassword(password);
  return tx(async db => {
    if (input.ip) {
      const recent = await db.query<{ count: string }>(`SELECT count(*)::bigint AS count FROM app_users
        WHERE registration_ip = $1 AND created_at > now() - interval '1 day'`, [input.ip]);
      if (Number(recent.rows[0]?.count || 0) >= REGISTRATIONS_PER_IP_PER_DAY) {
        throw new AccountAuthError(429, 'REGISTRATION_LIMITED', '这个网络今天注册的账号太多了，请明天再试', 3600);
      }
    }
    const inserted = await db.query<{ id: string }>(`INSERT INTO app_users (
        display_name, username, username_key, password_hash, password_changed_at, registration_ip
      ) VALUES ($1, $2, $3, $4, now(), $5)
      ON CONFLICT DO NOTHING RETURNING id`,
    [randomReaderName(), name.username, name.key, passwordHash, input.ip || null]);
    const userId = inserted.rows[0]?.id;
    if (!userId) throw new AccountAuthError(409, 'USERNAME_TAKEN', '这个用户名已被使用，换一个试试');
    await db.query(`INSERT INTO point_wallets (user_id, balance, paid_balance, promo_balance)
      VALUES ($1, 0, 0, 0) ON CONFLICT (user_id) DO NOTHING`, [userId]);
    const recoveryCodes = await storeRecoveryCodes(db, userId, hasher);
    return { userId, recoveryCodes };
  });
}

interface CredentialRow {
  id: string;
  username: string | null;
  password_hash: string | null;
  failed_login_count: number;
  locked_seconds: number;
}

function lockedError(seconds: number): AccountAuthError {
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  return new AccountAuthError(429, 'LOGIN_LOCKED', `密码错误次数过多，请 ${minutes} 分钟后再试`, Math.max(1, Math.ceil(seconds)));
}

async function credentialRow(db: MembershipDb, where: string, value: string, lock = false): Promise<CredentialRow | null> {
  const result = await db.query<CredentialRow>(`SELECT id, username, password_hash, failed_login_count,
      GREATEST(0, ceil(extract(epoch FROM (login_locked_until - now()))))::integer AS locked_seconds
    FROM app_users WHERE ${where} = $1 AND deleted_at IS NULL${lock ? ' FOR UPDATE' : ''}`, [value]);
  const row = result.rows[0];
  return row ? { ...row, locked_seconds: Number(row.locked_seconds || 0) } : null;
}

async function recordLoginFailure(db: MembershipDb, userId: string): Promise<void> {
  const result = await db.query<{ failed_login_count: number }>(`UPDATE app_users
    SET failed_login_count = failed_login_count + 1 WHERE id = $1 RETURNING failed_login_count`, [userId]);
  const minutes = loginLockMinutes(Number(result.rows[0]?.failed_login_count || 0));
  if (minutes > 0) {
    await db.query(`UPDATE app_users SET login_locked_until = now() + make_interval(mins => $2) WHERE id = $1`,
      [userId, minutes]);
  }
}

async function clearLoginFailures(db: MembershipDb, userId: string): Promise<void> {
  await db.query(`UPDATE app_users SET failed_login_count = 0, login_locked_until = NULL
    WHERE id = $1 AND (failed_login_count <> 0 OR login_locked_until IS NOT NULL)`, [userId]);
}

const invalidCredentials = () => new AccountAuthError(401, 'INVALID_CREDENTIALS', '用户名或密码不正确');

export async function passwordLogin(tx: Transaction, input: { username?: unknown; password?: unknown })
  : Promise<{ userId: string; deletionCancelled: boolean }> {
  const password = typeof input.password === 'string' ? input.password : '';
  let key = '';
  try {
    key = normalizeUsername(input.username).key;
  } catch {
    await burnPasswordCheck(password);
    throw invalidCredentials();
  }
  return tx(async db => {
    const row = await credentialRow(db, 'username_key', key, true);
    if (!row || !row.password_hash) {
      await burnPasswordCheck(password);
      throw invalidCredentials();
    }
    if (row.locked_seconds > 0) throw lockedError(row.locked_seconds);
    if (!await verifyPassword(password, row.password_hash)) {
      await recordLoginFailure(db, row.id);
      return null;
    }
    await clearLoginFailures(db, row.id);
    return { userId: row.id, deletionCancelled: await cancelAccountDeletion(db, row.id) };
  }).then(result => {
    // 失败次数要提交后再报错，放在事务里抛出会被回滚。
    if (!result) throw invalidCredentials();
    return result;
  });
}

export async function recoverWithCode(tx: Transaction, input: { username?: unknown; recoveryCode?: unknown;
  newPassword?: unknown }, hasher: RecoveryHasher): Promise<{ userId: string; remainingCodes: number }> {
  let name;
  let code = '';
  let password = '';
  try {
    name = normalizeUsername(input.username);
    code = normalizeRecoveryCode(input.recoveryCode);
    password = validatePassword(input.newPassword, name.username);
  } catch (error) {
    fromCredential(error);
  }
  const passwordHash = await hashPassword(password);
  const result = await tx(async db => {
    const row = await credentialRow(db, 'username_key', name.key, true);
    if (!row) return { failed: true as const };
    if (row.locked_seconds > 0) throw lockedError(row.locked_seconds);
    const used = await db.query(`UPDATE account_recovery_codes SET used_at = now()
      WHERE user_id = $1 AND code_hash = $2 AND used_at IS NULL`, [row.id, hasher(code)]);
    if (!used.rowCount) {
      await recordLoginFailure(db, row.id);
      return { failed: true as const };
    }
    await db.query(`UPDATE app_users SET password_hash = $2, password_changed_at = now(),
      failed_login_count = 0, login_locked_until = NULL, updated_at = now() WHERE id = $1`, [row.id, passwordHash]);
    await db.query(`UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now())
      WHERE user_id = $1 AND revoked_at IS NULL`, [row.id]);
    await cancelAccountDeletion(db, row.id);
    const remaining = await db.query<{ count: string }>(`SELECT count(*)::bigint AS count
      FROM account_recovery_codes WHERE user_id = $1 AND used_at IS NULL`, [row.id]);
    return { failed: false as const, userId: row.id, remainingCodes: Number(remaining.rows[0]?.count || 0) };
  });
  if (result.failed) throw new AccountAuthError(401, 'INVALID_RECOVERY', '用户名或恢复码不正确');
  return { userId: result.userId, remainingCodes: result.remainingCodes };
}

export interface LoginMethods {
  username: string;
  hasPassword: boolean;
  huaweiBound: boolean;
  recoveryCodesRemaining: number;
  deletionRequestedAt: number | null;
  /** 冷却期内下次能改用户名的时间（毫秒）；现在就能改时为 null。 */
  usernameChangeAvailableAt: number | null;
}

/** 上次改名在冷却期内时返回下次能改的时间（毫秒），否则 null。 */
const USERNAME_NEXT_CHANGE_SQL = `CASE WHEN u.username_changed_at > now() - make_interval(days => ${USERNAME_CHANGE_INTERVAL_DAYS})
  THEN (extract(epoch FROM u.username_changed_at + make_interval(days => ${USERNAME_CHANGE_INTERVAL_DAYS})) * 1000)::bigint
  END`;

export async function loginMethods(db: MembershipDb, userId: string): Promise<LoginMethods> {
  const result = await db.query<{ username: string | null; has_password: boolean; huawei_bound: boolean;
    remaining: string; deletion_ms: string | null; next_change_ms: string | null }>(`SELECT u.username,
      u.password_hash IS NOT NULL AS has_password,
      u.huawei_open_id IS NOT NULL AS huawei_bound,
      (SELECT count(*) FROM account_recovery_codes c WHERE c.user_id = u.id AND c.used_at IS NULL)::bigint AS remaining,
      (extract(epoch FROM u.deletion_requested_at) * 1000)::bigint AS deletion_ms,
      ${USERNAME_NEXT_CHANGE_SQL} AS next_change_ms
    FROM app_users u WHERE u.id = $1 AND u.deleted_at IS NULL`, [userId]);
  const row = result.rows[0];
  if (!row) throw new AccountAuthError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
  return {
    username: row.username || '',
    hasPassword: row.has_password,
    huaweiBound: row.huawei_bound,
    recoveryCodesRemaining: Number(row.remaining || 0),
    deletionRequestedAt: row.deletion_ms === null ? null : Number(row.deletion_ms),
    usernameChangeAvailableAt: row.next_change_ms === null ? null : Number(row.next_change_ms)
  };
}

async function requirePassword(db: MembershipDb, userId: string, hash: string, password: unknown): Promise<void> {
  if (typeof password !== 'string' || !password || !await verifyPassword(password, hash)) {
    throw new AccountAuthError(403, 'WRONG_PASSWORD', '当前密码不正确');
  }
  await clearLoginFailures(db, userId);
}

/**
 * 设置或修改密码。没有用户名的账号（华为账号注册）第一次设置时同时定下用户名，之后改名走 changeUsername；
 * 第一次设置会生成恢复码。修改后其他设备退出登录。
 */
export async function setAccountPassword(tx: Transaction, userId: string, sessionId: string,
  input: { username?: unknown; newPassword?: unknown; currentPassword?: unknown },
  hasher: RecoveryHasher): Promise<{ recoveryCodes: string[] }> {
  return tx(async db => {
    const row = await credentialRow(db, 'id', userId, true);
    if (!row) throw new AccountAuthError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
    let username = row.username || '';
    let usernameKey = '';
    let password = '';
    try {
      if (!username) {
        const name = normalizeUsername(input.username);
        username = name.username;
        usernameKey = name.key;
      }
      password = validatePassword(input.newPassword, username);
    } catch (error) {
      fromCredential(error);
    }
    if (row.password_hash) await requirePassword(db, userId, row.password_hash, input.currentPassword);
    const passwordHash = await hashPassword(password);
    if (usernameKey) {
      try {
        await db.query('SAVEPOINT set_username');
        await db.query(`UPDATE app_users SET username = $2, username_key = $3 WHERE id = $1`,
          [userId, username, usernameKey]);
        await db.query('RELEASE SAVEPOINT set_username');
      } catch (error) {
        if (!isUniqueViolation(error)) throw error;
        throw new AccountAuthError(409, 'USERNAME_TAKEN', '这个用户名已被使用，换一个试试');
      }
    }
    await db.query(`UPDATE app_users SET password_hash = $2, password_changed_at = now(), updated_at = now()
      WHERE id = $1`, [userId, passwordHash]);
    await db.query(`UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now())
      WHERE user_id = $1 AND id <> $2 AND revoked_at IS NULL`, [userId, sessionId]);
    return { recoveryCodes: row.password_hash ? [] : await storeRecoveryCodes(db, userId, hasher) };
  });
}

/**
 * 修改用户名：要验证当前密码，30 天一次（只改大小写也算）。旧用户名立即释放；
 * 密码、恢复码和已登录的设备都不受影响。
 */
export async function changeUsername(tx: Transaction, userId: string,
  input: { username?: unknown; currentPassword?: unknown }): Promise<void> {
  let name: { username: string; key: string };
  try {
    name = normalizeUsername(input.username);
  } catch (error) {
    fromCredential(error);
  }
  await tx(async db => {
    const result = await db.query<{ username: string | null; password_hash: string | null; next_change_ms: string | null }>(
      `SELECT u.username, u.password_hash, ${USERNAME_NEXT_CHANGE_SQL} AS next_change_ms
      FROM app_users u WHERE u.id = $1 AND u.deleted_at IS NULL FOR UPDATE`, [userId]);
    const row = result.rows[0];
    if (!row) throw new AccountAuthError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
    if (!row.username || !row.password_hash) throw new AccountAuthError(409, 'PASSWORD_NOT_SET', '请先设置用户名和密码');
    if (row.username === name.username) throw new AccountAuthError(400, 'SAME_USERNAME', '新用户名和当前用户名相同');
    if (row.next_change_ms !== null) {
      // 日期由客户端按 loginMethods.usernameChangeAvailableAt 在本地时区显示，这里不写具体日子。
      throw new AccountAuthError(429, 'USERNAME_CHANGE_TOO_SOON',
        `用户名 ${USERNAME_CHANGE_INTERVAL_DAYS} 天内只能改一次`,
        Math.max(1, Math.ceil((Number(row.next_change_ms) - Date.now()) / 1000)));
    }
    await requirePassword(db, userId, row.password_hash, input.currentPassword);
    try {
      await db.query('SAVEPOINT change_username');
      await db.query(`UPDATE app_users SET username = $2, username_key = $3, username_changed_at = now(),
        updated_at = now() WHERE id = $1`, [userId, name.username, name.key]);
      await db.query('RELEASE SAVEPOINT change_username');
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      throw new AccountAuthError(409, 'USERNAME_TAKEN', '这个用户名已被使用，换一个试试');
    }
  });
}

export async function regenerateRecoveryCodes(tx: Transaction, userId: string, currentPassword: unknown,
  hasher: RecoveryHasher): Promise<string[]> {
  return tx(async db => {
    const row = await credentialRow(db, 'id', userId, true);
    if (!row?.password_hash) throw new AccountAuthError(409, 'PASSWORD_NOT_SET', '请先设置用户名和密码');
    await requirePassword(db, userId, row.password_hash, currentPassword);
    return storeRecoveryCodes(db, userId, hasher);
  });
}

/** 给当前账号绑定华为账号；华为账号已属于别的账号时拒绝，不转移也不合并。 */
export async function bindHuaweiAccount(tx: Transaction, userId: string, openId: string, unionId: string | null)
  : Promise<{ welcomeGranted: boolean }> {
  return tx(async db => {
    const current = await db.query<{ huawei_open_id: string | null }>(
      'SELECT huawei_open_id FROM app_users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [userId]);
    const row = current.rows[0];
    if (!row) throw new AccountAuthError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
    if (row.huawei_open_id === openId) return { welcomeGranted: false };
    if (row.huawei_open_id) throw new AccountAuthError(409, 'HUAWEI_ALREADY_LINKED', '这个账号已绑定其他华为账号');
    const owner = await db.query('SELECT 1 FROM app_users WHERE huawei_open_id = $1 AND id <> $2', [openId, userId]);
    if (owner.rowCount) {
      throw new AccountAuthError(409, 'HUAWEI_IN_USE', '这个华为账号已经有自己的轻页账号，请直接用华为账号登录');
    }
    try {
      await db.query('SAVEPOINT bind_huawei');
      await db.query(`UPDATE app_users SET huawei_open_id = $2, huawei_union_id = COALESCE($3, huawei_union_id),
        updated_at = now() WHERE id = $1`, [userId, openId, unionId]);
      await db.query('RELEASE SAVEPOINT bind_huawei');
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      throw new AccountAuthError(409, 'HUAWEI_IN_USE', '这个华为账号已经有自己的轻页账号，请直接用华为账号登录');
    }
    return { welcomeGranted: await grantHuaweiWelcome(db, userId, openId) };
  });
}

/** 申请注销：所有设备退出登录，冷静期内任意方式登录即撤销。有密码的账号要验证密码。 */
export async function requestAccountDeletion(tx: Transaction, userId: string, currentPassword: unknown)
  : Promise<{ scheduledAt: number }> {
  return tx(async db => {
    const row = await credentialRow(db, 'id', userId, true);
    if (!row) throw new AccountAuthError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
    if (row.password_hash) await requirePassword(db, userId, row.password_hash, currentPassword);
    const updated = await db.query<{ scheduled_ms: string }>(`UPDATE app_users
      SET deletion_requested_at = now(), updated_at = now() WHERE id = $1
      RETURNING (extract(epoch FROM deletion_requested_at + make_interval(days => $2)) * 1000)::bigint AS scheduled_ms`,
    [userId, ACCOUNT_DELETION_GRACE_DAYS]);
    await db.query(`UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now())
      WHERE user_id = $1 AND revoked_at IS NULL`, [userId]);
    return { scheduledAt: Number(updated.rows[0]!.scheduled_ms) };
  });
}

/**
 * 注销时删掉的个人数据。点数、会员、订单等交易记录只按账号 ID 保留，不再能对应到任何登录方式。
 * 新增带 user_id 的表时要在这里或 DELETION_KEEPS_TABLES 里登记（测试会检查）。
 */
export const DELETION_PURGES_TABLES = [
  'auth_sessions', 'account_recovery_codes', 'sync_changes', 'sync_devices', 'sync_entities',
  'sync_operation_receipts', 'sync_user_usage', 'reading_stats_records', 'reading_stats_usage',
  'lottery_web_sessions', 'lottery_web_verifications', 'cloud_download_tickets', 'cloud_file_tombstones',
  'shared_provider_key_grants'
] as const;
export const DELETION_KEEPS_TABLES = [
  'account_debts', 'cloud_download_monthly_usage', 'cloud_download_usage', 'cloud_quota_bonuses', 'iap_orders',
  'lottery_draws', 'membership_accounts', 'membership_coupons', 'membership_gift_claims', 'membership_orders',
  'membership_periods', 'membership_quotes', 'membership_theme_claims', 'point_ledger', 'point_wallets',
  // 安卓支付宝充值订单，与 iap_orders 一样是交易记录。
  'recharge_orders',
  'theme_entitlements', 'tts_package_redemptions', 'tts_quota_grants', 'tts_quota_ledger', 'tts_usage',
  // 云文件交给云空间维护任务连同对象存储一起删，见 purgeDueAccountDeletions。
  'cloud_files',
  // 只剩 openId 的哈希，用来防止注销后重新登录再领一次赠点。
  'huawei_welcome_claims'
] as const;

/** 冷静期满的账号：清掉登录方式和个人数据，资料改为“已注销用户”。返回处理的账号数。 */
export async function purgeDueAccountDeletions(tx: Transaction, limit = 20): Promise<number> {
  return tx(async db => {
    const due = await db.query<{ id: string }>(`SELECT id FROM app_users
      WHERE deletion_requested_at < now() - make_interval(days => $1) AND deleted_at IS NULL
      ORDER BY deletion_requested_at LIMIT $2 FOR UPDATE SKIP LOCKED`, [ACCOUNT_DELETION_GRACE_DAYS, limit]);
    for (const { id } of due.rows) {
      await db.query(`UPDATE cloud_files SET state = 'DELETING', updated_at = now()
        WHERE user_id = $1 AND state <> 'DELETING'`, [id]);
      for (const table of DELETION_PURGES_TABLES) {
        await db.query(`DELETE FROM ${table} WHERE user_id = $1`, [id]);
      }
      await db.query(`UPDATE app_users SET huawei_open_id = NULL, huawei_union_id = NULL,
        username = NULL, username_key = NULL, username_changed_at = NULL, password_hash = NULL, password_changed_at = NULL,
        failed_login_count = 0, login_locked_until = NULL, registration_ip = NULL,
        display_name = '已注销用户', avatar_url = '', avatar_data = NULL, avatar_mime = NULL,
        profile_customized = TRUE, deleted_at = now(), updated_at = now() WHERE id = $1`, [id]);
    }
    // 注册 IP 只用于限制同一网络一天的注册数，过两天就不再保留。
    await db.query(`UPDATE app_users SET registration_ip = NULL
      WHERE registration_ip IS NOT NULL AND created_at < now() - interval '2 days'`);
    return due.rows.length;
  });
}

interface AccountAuthDependencies {
  db: MembershipDb;
  transaction: Transaction;
  authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  userId: (request: FastifyRequest) => string;
  sessionId: (request: FastifyRequest) => string;
  issueSession: (userId: string, ip: string) => Promise<string>;
  account: (db: MembershipDb, userId: string) => Promise<unknown>;
  /** 按 subject 计数的每分钟限流；subject 可以是 IP 或用户名。 */
  limit: (scope: string, subject: string, maxPerMinute: number) => Promise<void>;
  exchangeHuawei: (authorizationCode: string) => Promise<{ openID?: string; unionID?: string }>;
  recoveryHasher: RecoveryHasher;
  authRateLimitPerMinute: number;
}

interface CredentialBody {
  username?: unknown;
  password?: unknown;
  recoveryCode?: unknown;
  newPassword?: unknown;
  currentPassword?: unknown;
  authorizationCode?: unknown;
}

export function registerAccountAuthRoutes(app: FastifyInstance, deps: AccountAuthDependencies): void {
  const publicRoute = {
    bodyLimit: 4 * 1024,
    config: { rateLimit: { max: deps.authRateLimitPerMinute, timeWindow: 60_000 } }
  };
  const usernameKey = (value: unknown) => typeof value === 'string' ? value.trim().toLowerCase().substring(0, 40) : '';

  async function signedIn(userId: string, ip: string) {
    return { sessionToken: await deps.issueSession(userId, ip), account: await deps.account(deps.db, userId) };
  }

  app.post<{ Body: CredentialBody }>('/v1/auth/register', publicRoute, async request => {
    await deps.limit('auth-register-ip', request.ip, 3);
    const result = await registerPasswordAccount(deps.transaction,
      { username: request.body?.username, password: request.body?.password, ip: request.ip }, deps.recoveryHasher);
    return { ...await signedIn(result.userId, request.ip), recoveryCodes: result.recoveryCodes };
  });

  app.post<{ Body: CredentialBody }>('/v1/auth/password', publicRoute, async request => {
    await deps.limit('auth-password-ip', request.ip, 20);
    await deps.limit('auth-password-user', usernameKey(request.body?.username), 10);
    const result = await passwordLogin(deps.transaction,
      { username: request.body?.username, password: request.body?.password });
    return { ...await signedIn(result.userId, request.ip), deletionCancelled: result.deletionCancelled };
  });

  app.post<{ Body: CredentialBody }>('/v1/auth/recover', publicRoute, async request => {
    await deps.limit('auth-recover-ip', request.ip, 10);
    await deps.limit('auth-recover-user', usernameKey(request.body?.username), 5);
    const result = await recoverWithCode(deps.transaction, {
      username: request.body?.username, recoveryCode: request.body?.recoveryCode,
      newPassword: request.body?.newPassword
    }, deps.recoveryHasher);
    return { ...await signedIn(result.userId, request.ip), remainingRecoveryCodes: result.remainingCodes };
  });

  app.get('/v1/account/login-methods', { preHandler: deps.authenticate }, async request =>
    loginMethods(deps.db, deps.userId(request)));

  app.post<{ Body: CredentialBody }>('/v1/account/password',
    { preHandler: deps.authenticate, bodyLimit: 4 * 1024 }, async request => {
      const userId = deps.userId(request);
      await deps.limit('account-credentials', userId, 10);
      const result = await setAccountPassword(deps.transaction, userId, deps.sessionId(request), {
        username: request.body?.username, newPassword: request.body?.newPassword,
        currentPassword: request.body?.currentPassword
      }, deps.recoveryHasher);
      return { ...result, loginMethods: await loginMethods(deps.db, userId) };
    });

  app.post<{ Body: CredentialBody }>('/v1/account/username',
    { preHandler: deps.authenticate, bodyLimit: 4 * 1024 }, async request => {
      const userId = deps.userId(request);
      await deps.limit('account-credentials', userId, 10);
      await changeUsername(deps.transaction, userId,
        { username: request.body?.username, currentPassword: request.body?.currentPassword });
      return { loginMethods: await loginMethods(deps.db, userId) };
    });

  app.post<{ Body: CredentialBody }>('/v1/account/recovery-codes',
    { preHandler: deps.authenticate, bodyLimit: 4 * 1024 }, async request => {
      const userId = deps.userId(request);
      await deps.limit('account-credentials', userId, 10);
      const recoveryCodes = await regenerateRecoveryCodes(deps.transaction, userId,
        request.body?.currentPassword, deps.recoveryHasher);
      return { recoveryCodes, loginMethods: await loginMethods(deps.db, userId) };
    });

  app.post<{ Body: CredentialBody }>('/v1/account/huawei',
    { preHandler: deps.authenticate, bodyLimit: 16 * 1024 }, async request => {
      const userId = deps.userId(request);
      await deps.limit('account-credentials', userId, 10);
      const code = typeof request.body?.authorizationCode === 'string' ? request.body.authorizationCode.trim() : '';
      if (!code || code.length > 4096) throw new AccountAuthError(400, 'INVALID_AUTHORIZATION_CODE', '缺少华为账号授权码');
      const huawei = await deps.exchangeHuawei(code);
      if (!huawei.openID) throw new AccountAuthError(502, 'HUAWEI_IDENTITY_MISSING', '华为账号没有返回身份信息');
      const result = await bindHuaweiAccount(deps.transaction, userId, huawei.openID, huawei.unionID || null);
      return { ...result, account: await deps.account(deps.db, userId), loginMethods: await loginMethods(deps.db, userId) };
    });

  app.post<{ Body: CredentialBody }>('/v1/account/deletion',
    { preHandler: deps.authenticate, bodyLimit: 4 * 1024 }, async request => {
      const userId = deps.userId(request);
      await deps.limit('account-credentials', userId, 10);
      return requestAccountDeletion(deps.transaction, userId, request.body?.currentPassword);
    });
}
