import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import test from 'node:test';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import type { MembershipDb } from './membershipService.js';
import {
  AccountAuthError,
  bindHuaweiAccount,
  cancelAccountDeletion,
  changeUsername,
  DELETION_KEEPS_TABLES,
  DELETION_PURGES_TABLES,
  grantHuaweiWelcome,
  loginMethods,
  passwordLogin,
  purgeDueAccountDeletions,
  recoverWithCode,
  registerAccountAuthRoutes,
  registerPasswordAccount,
  regenerateRecoveryCodes,
  requestAccountDeletion,
  setAccountPassword
} from './accountAuth.js';
import {
  generateRecoveryCodes,
  hashPassword,
  loginLockMinutes,
  normalizeRecoveryCode,
  normalizeUsername,
  recoveryCodeHasher,
  validatePassword,
  verifyPassword
} from './accountCredentials.js';

const hasher = recoveryCodeHasher('test-secret-test-secret-test-secret-0000');
const rejectedCode = (code: string) => (error: unknown) => error instanceof AccountAuthError && error.code === code;

async function database() {
  const db = new PGlite();
  const migrations = new URL('../migrations/', import.meta.url);
  const files = (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort();
  const run = async (file: string) =>
    db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  for (const file of files.filter(file => file < '031')) await run(file);
  // 迁移前已有的华为用户领过赠点，迁移后要占住领取记录。
  const legacyUser = randomUUID();
  await db.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, 'legacy-open-id', '老用户')`, [legacyUser]);
  await db.query(`INSERT INTO point_wallets(user_id, balance, paid_balance, promo_balance) VALUES ($1, 300, 0, 300)`, [legacyUser]);
  await db.query(`INSERT INTO point_ledger(user_id, delta, balance_after, reason, reference_id, idempotency_key)
    VALUES ($1, 300, 300, 'WELCOME_GRANT', $2, $3)`, [legacyUser, legacyUser, `welcome:${legacyUser}`]);
  for (const file of files.filter(file => file >= '031')) await run(file);
  await run('031_password_accounts.sql'); // 重跑不出错
  const adapter = (connection: Pick<PGlite, 'query'>): MembershipDb => ({
    query: connection.query.bind(connection) as unknown as MembershipDb['query']
  });
  const tx = <T>(work: (client: MembershipDb) => Promise<T>) => db.transaction(client => work(adapter(client)));
  return { db, tx, query: adapter(db), legacyUser };
}

async function session(db: PGlite, userId: string): Promise<string> {
  const id = randomUUID();
  await db.query(`INSERT INTO auth_sessions(id, user_id, expires_at) VALUES ($1, $2, now() + interval '30 days')`, [id, userId]);
  return id;
}

async function activeSessions(db: PGlite, userId: string): Promise<string[]> {
  const rows = await db.query<{ id: string }>(
    'SELECT id FROM auth_sessions WHERE user_id = $1 AND revoked_at IS NULL ORDER BY id', [userId]);
  return rows.rows.map(row => row.id);
}

async function points(db: PGlite, userId: string): Promise<number> {
  return Number((await db.query<{ balance: string }>('SELECT balance FROM point_wallets WHERE user_id = $1', [userId])).rows[0]?.balance);
}

test('credential rules: username, password strength, recovery codes and lock schedule', async () => {
  assert.deepEqual(normalizeUsername('  Reader_01 '), { username: 'Reader_01', key: 'reader_01' });
  for (const bad of ['ab', '1reader', 'reader-01', '读者abc', 'a'.repeat(21), 42]) {
    assert.throws(() => normalizeUsername(bad));
  }
  assert.equal(validatePassword('abcd1234'), 'abcd1234');
  for (const bad of ['short1', '12345678', 'abcdefgh', 'x'.repeat(65) + '1']) assert.throws(() => validatePassword(bad));
  assert.throws(() => validatePassword('Reader_01', 'reader_01'));
  const codes = generateRecoveryCodes();
  assert.equal(codes.length, 8);
  assert.equal(new Set(codes).size, 8);
  for (const code of codes) assert.match(code, /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
  assert.equal(hasher(codes[0]!.toLowerCase().replace(/-/g, ' ')), hasher(codes[0]!));
  assert.throws(() => normalizeRecoveryCode('ABCD-EFGH'));
  assert.deepEqual([4, 5, 6, 7, 11, 12].map(loginLockMinutes), [0, 1, 2, 4, 60, 60]);
  const stored = await hashPassword('密码abc123');
  assert.match(stored, /^scrypt\$32768\$8\$1\$/);
  assert.equal(await verifyPassword('密码abc123', stored), true);
  assert.equal(await verifyPassword('密码abc124', stored), false);
  assert.equal(await verifyPassword('密码abc123', 'scrypt$999999999$8$1$AAAA$BBBB'), false);
});

test('register, password login, lockout and recovery (embedded PostgreSQL)', async t => {
  const { db, tx, query } = await database();
  t.after(() => db.close());

  const registered = await registerPasswordAccount(tx, { username: 'Reader01', password: 'abcd1234', ip: '10.0.0.1' }, hasher);
  assert.equal(registered.recoveryCodes.length, 8);
  assert.equal(await points(db, registered.userId), 0, '用户名注册不送赠点');
  const profile = (await db.query<{ display_name: string; huawei_open_id: string | null }>(
    'SELECT display_name, huawei_open_id FROM app_users WHERE id = $1', [registered.userId])).rows[0]!;
  assert.match(profile.display_name, /^读者\d{4}$/);
  assert.equal(profile.huawei_open_id, null);
  await assert.rejects(registerPasswordAccount(tx, { username: 'reader01', password: 'abcd1234' }, hasher),
    rejectedCode('USERNAME_TAKEN'));
  await assert.rejects(registerPasswordAccount(tx, { username: 'Reader02', password: '12345678' }, hasher),
    rejectedCode('WEAK_PASSWORD'));

  assert.deepEqual(await passwordLogin(tx, { username: 'READER01', password: 'abcd1234' }),
    { userId: registered.userId, deletionCancelled: false });
  await assert.rejects(passwordLogin(tx, { username: 'nobody', password: 'abcd1234' }), rejectedCode('INVALID_CREDENTIALS'));
  await assert.rejects(passwordLogin(tx, { username: '!!', password: 'abcd1234' }), rejectedCode('INVALID_CREDENTIALS'));

  for (let attempt = 0; attempt < 5; attempt++) {
    await assert.rejects(passwordLogin(tx, { username: 'reader01', password: 'wrong-pass1' }), rejectedCode('INVALID_CREDENTIALS'));
  }
  await assert.rejects(passwordLogin(tx, { username: 'reader01', password: 'abcd1234' }), (error: unknown) =>
    error instanceof AccountAuthError && error.code === 'LOGIN_LOCKED' && error.retryAfter > 0 && error.retryAfter <= 60);
  await db.query(`UPDATE app_users SET login_locked_until = now() - interval '1 second' WHERE id = $1`, [registered.userId]);
  await passwordLogin(tx, { username: 'reader01', password: 'abcd1234' });
  assert.equal((await db.query<{ failed_login_count: number }>('SELECT failed_login_count FROM app_users WHERE id = $1',
    [registered.userId])).rows[0]!.failed_login_count, 0, '登录成功清零失败次数');

  const first = await session(db, registered.userId);
  await assert.rejects(recoverWithCode(tx, { username: 'reader01', recoveryCode: 'AAAA-BBBB-CCCC', newPassword: 'newpass99' }, hasher),
    rejectedCode('INVALID_RECOVERY'));
  const recovered = await recoverWithCode(tx,
    { username: 'reader01', recoveryCode: registered.recoveryCodes[2]!.toLowerCase(), newPassword: 'newpass99' }, hasher);
  assert.deepEqual(recovered, { userId: registered.userId, remainingCodes: 7 });
  assert.deepEqual(await activeSessions(db, registered.userId), [], '找回密码后其他设备全部退出');
  assert.ok(first);
  await assert.rejects(passwordLogin(tx, { username: 'reader01', password: 'abcd1234' }), rejectedCode('INVALID_CREDENTIALS'));
  await passwordLogin(tx, { username: 'reader01', password: 'newpass99' });
  await assert.rejects(recoverWithCode(tx,
    { username: 'reader01', recoveryCode: registered.recoveryCodes[2]!, newPassword: 'again1234' }, hasher),
  rejectedCode('INVALID_RECOVERY'), '恢复码只能用一次');

  await db.query(`UPDATE app_users SET created_at = now() - interval '3 days' WHERE id = $1`, [registered.userId]);
  await db.query(`UPDATE app_users SET registration_ip = '10.9.9.9'`);
  for (let index = 0; index < 20; index++) {
    await db.query(`INSERT INTO app_users(display_name, registration_ip) VALUES ('读者', '10.9.9.9')`);
  }
  await assert.rejects(registerPasswordAccount(tx, { username: 'Crowded1', password: 'abcd1234', ip: '10.9.9.9' }, hasher),
    rejectedCode('REGISTRATION_LIMITED'));
  await purgeDueAccountDeletions(tx);
  assert.equal((await query.query('SELECT 1 FROM app_users WHERE id = $1 AND registration_ip IS NULL', [registered.userId])).rowCount, 1,
    '超过两天的注册 IP 被清掉');
});

test('password setup for Huawei accounts, Huawei binding and one welcome grant per Huawei account', async t => {
  const { db, tx, query, legacyUser } = await database();
  t.after(() => db.close());

  // 华为账号注册的用户第一次设置用户名和密码，同时拿到恢复码。
  const current = await session(db, legacyUser);
  const other = await session(db, legacyUser);
  await assert.rejects(setAccountPassword(tx, legacyUser, current, { newPassword: 'abcd1234' }, hasher),
    rejectedCode('INVALID_USERNAME'));
  const setup = await setAccountPassword(tx, legacyUser, current, { username: 'OldFriend', newPassword: 'abcd1234' }, hasher);
  assert.equal(setup.recoveryCodes.length, 8);
  assert.deepEqual(await activeSessions(db, legacyUser), [current], '改密码只保留当前设备');
  assert.ok(other);
  let methods = await loginMethods(query, legacyUser);
  assert.deepEqual(methods, { username: 'OldFriend', hasPassword: true, huaweiBound: true, recoveryCodesRemaining: 8,
    deletionRequestedAt: null, usernameChangeAvailableAt: null });
  await assert.rejects(setAccountPassword(tx, legacyUser, current, { newPassword: 'efgh5678' }, hasher),
    rejectedCode('WRONG_PASSWORD'));
  const changed = await setAccountPassword(tx, legacyUser, current,
    { username: 'Ignored', newPassword: 'efgh5678', currentPassword: 'abcd1234' }, hasher);
  assert.deepEqual(changed.recoveryCodes, [], '修改密码不重发恢复码');
  assert.equal((await loginMethods(query, legacyUser)).username, 'OldFriend', '修改密码不会顺带改用户名');
  await assert.rejects(regenerateRecoveryCodes(tx, legacyUser, 'abcd1234', hasher), rejectedCode('WRONG_PASSWORD'));
  assert.equal((await regenerateRecoveryCodes(tx, legacyUser, 'efgh5678', hasher)).length, 8);

  const taken = await registerPasswordAccount(tx, { username: 'Taken01', password: 'abcd1234' }, hasher);
  const huaweiOnly = randomUUID();
  await db.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, 'hw-only', '华为用户')`, [huaweiOnly]);
  const huaweiSession = await session(db, huaweiOnly);
  await assert.rejects(setAccountPassword(tx, huaweiOnly, huaweiSession, { username: 'taken01', newPassword: 'abcd1234' }, hasher),
    rejectedCode('USERNAME_TAKEN'));
  assert.equal((await loginMethods(query, huaweiOnly)).username, '', '用户名冲突时整笔回滚');

  // 用户名账号绑定一个从没领过的华为账号：补发 300 点；再绑一次不重复发。
  const reader = await registerPasswordAccount(tx, { username: 'Reader02', password: 'abcd1234' }, hasher);
  assert.deepEqual(await bindHuaweiAccount(tx, reader.userId, 'fresh-open-id', 'union-1'), { welcomeGranted: true });
  assert.equal(await points(db, reader.userId), 300);
  assert.deepEqual(await bindHuaweiAccount(tx, reader.userId, 'fresh-open-id', null), { welcomeGranted: false });
  assert.equal(await points(db, reader.userId), 300);
  await assert.rejects(bindHuaweiAccount(tx, reader.userId, 'another-open-id', null), rejectedCode('HUAWEI_ALREADY_LINKED'));
  await assert.rejects(bindHuaweiAccount(tx, taken.userId, 'legacy-open-id', null), rejectedCode('HUAWEI_IN_USE'));
  await assert.rejects(bindHuaweiAccount(tx, taken.userId, 'fresh-open-id', null), rejectedCode('HUAWEI_IN_USE'));
  assert.equal((await loginMethods(query, reader.userId)).huaweiBound, true);

  // 迁移前领过的华为账号已占住领取记录：挪到别的账号也不会再领。
  assert.equal(await grantHuaweiWelcome(query, taken.userId, 'legacy-open-id'), false);
  assert.equal(await points(db, legacyUser), 300);
  assert.equal(await grantHuaweiWelcome(query, taken.userId, 'fresh-open-id'), false);
  assert.equal(await points(db, taken.userId), 0);
});

test('username change: password check, 30-day interval, old name released (embedded PostgreSQL)', async t => {
  const { db, tx, query } = await database();
  t.after(() => db.close());

  const reader = await registerPasswordAccount(tx, { username: 'First01', password: 'abcd1234' }, hasher);
  const other = await registerPasswordAccount(tx, { username: 'Other01', password: 'abcd1234' }, hasher);
  const device = await session(db, reader.userId);
  const huaweiOnly = randomUUID();
  await db.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, 'hw-rename', '华为用户')`, [huaweiOnly]);
  await assert.rejects(changeUsername(tx, huaweiOnly, { username: 'Newbie01', currentPassword: 'abcd1234' }),
    rejectedCode('PASSWORD_NOT_SET'));

  await assert.rejects(changeUsername(tx, reader.userId, { username: '1bad', currentPassword: 'abcd1234' }),
    rejectedCode('INVALID_USERNAME'));
  await assert.rejects(changeUsername(tx, reader.userId, { username: 'First01', currentPassword: 'abcd1234' }),
    rejectedCode('SAME_USERNAME'));
  await assert.rejects(changeUsername(tx, reader.userId, { username: 'Second01', currentPassword: 'wrong-pass1' }),
    rejectedCode('WRONG_PASSWORD'));
  await assert.rejects(changeUsername(tx, reader.userId, { username: 'other01', currentPassword: 'abcd1234' }),
    rejectedCode('USERNAME_TAKEN'));
  assert.equal((await loginMethods(query, reader.userId)).username, 'First01', '失败时用户名不变');
  assert.equal((await loginMethods(query, reader.userId)).usernameChangeAvailableAt, null, '失败不占冷却期');

  await changeUsername(tx, reader.userId, { username: 'Second01', currentPassword: 'abcd1234' });
  const methods = await loginMethods(query, reader.userId);
  assert.equal(methods.username, 'Second01');
  assert.equal(methods.recoveryCodesRemaining, 8, '恢复码不受影响');
  assert.ok(methods.usernameChangeAvailableAt! > Date.now() + 29.9 * 86400000);
  assert.deepEqual(await activeSessions(db, reader.userId), [device], '改名不让设备退出');
  await assert.rejects(passwordLogin(tx, { username: 'first01', password: 'abcd1234' }), rejectedCode('INVALID_CREDENTIALS'));
  assert.equal((await passwordLogin(tx, { username: 'SECOND01', password: 'abcd1234' })).userId, reader.userId);
  await recoverWithCode(tx, { username: 'second01', recoveryCode: reader.recoveryCodes[0]!, newPassword: 'abcd1234' }, hasher);

  // 旧用户名立即释放。
  assert.ok((await registerPasswordAccount(tx, { username: 'first01', password: 'abcd1234' }, hasher)).userId);

  // 30 天内不能再改，只改大小写也算。
  await assert.rejects(changeUsername(tx, reader.userId, { username: 'SECOND01', currentPassword: 'abcd1234' }),
    (error: unknown) => error instanceof AccountAuthError && error.code === 'USERNAME_CHANGE_TOO_SOON' && error.retryAfter > 0);
  await db.query(`UPDATE app_users SET username_changed_at = now() - interval '31 days' WHERE id = $1`, [reader.userId]);
  assert.equal((await loginMethods(query, reader.userId)).usernameChangeAvailableAt, null);
  await changeUsername(tx, reader.userId, { username: 'SECOND01', currentPassword: 'abcd1234' });
  assert.equal((await loginMethods(query, reader.userId)).username, 'SECOND01');
  assert.ok(other.userId);
});

test('account deletion: grace period, cancel on login, purge of personal data (embedded PostgreSQL)', async t => {
  const { db, tx, query } = await database();
  t.after(() => db.close());

  const tables = await db.query<{ table_name: string }>(`SELECT table_name FROM information_schema.columns
    WHERE column_name = 'user_id' AND table_schema = 'public' ORDER BY table_name`);
  const registered = new Set<string>([...DELETION_PURGES_TABLES, ...DELETION_KEEPS_TABLES]);
  assert.deepEqual(tables.rows.map(row => row.table_name).filter(name => !registered.has(name)), [],
    '新增带 user_id 的表要在注销清单里登记');

  const reader = await registerPasswordAccount(tx, { username: 'Leaving1', password: 'abcd1234' }, hasher);
  await bindHuaweiAccount(tx, reader.userId, 'leaving-open-id', null);
  await session(db, reader.userId);
  await db.query(`INSERT INTO sync_devices(id, user_id, device_name) VALUES ($1, $2, '手机')`, [randomUUID(), reader.userId]);
  const fileId = randomUUID();
  await db.query(`INSERT INTO cloud_files(id, user_id, request_id, kind, name, bytes, state)
    VALUES ($1, $2, 'r1', 'BOOK', '书.epub', 10, 'READY')`, [fileId, reader.userId]);

  await assert.rejects(requestAccountDeletion(tx, reader.userId, 'wrong-pass1'), rejectedCode('WRONG_PASSWORD'));
  const requested = await requestAccountDeletion(tx, reader.userId, 'abcd1234');
  assert.ok(requested.scheduledAt > Date.now() + 6.9 * 86400000);
  assert.deepEqual(await activeSessions(db, reader.userId), [], '申请注销后所有设备退出');
  assert.notEqual((await loginMethods(query, reader.userId)).deletionRequestedAt, null);

  // 冷静期内登录即撤销。
  assert.deepEqual(await passwordLogin(tx, { username: 'leaving1', password: 'abcd1234' }),
    { userId: reader.userId, deletionCancelled: true });
  assert.equal(await cancelAccountDeletion(query, reader.userId), false);
  await requestAccountDeletion(tx, reader.userId, 'abcd1234');
  assert.equal(await purgeDueAccountDeletions(tx), 0, '冷静期没满不处理');

  await db.query(`UPDATE app_users SET deletion_requested_at = now() - interval '8 days' WHERE id = $1`, [reader.userId]);
  assert.equal(await purgeDueAccountDeletions(tx), 1);
  const row = (await db.query<Record<string, unknown>>(`SELECT huawei_open_id, username, password_hash, display_name,
    deleted_at FROM app_users WHERE id = $1`, [reader.userId])).rows[0]!;
  assert.equal(row.huawei_open_id, null);
  assert.equal(row.username, null);
  assert.equal(row.password_hash, null);
  assert.equal(row.display_name, '已注销用户');
  assert.ok(row.deleted_at);
  assert.equal((await db.query('SELECT 1 FROM account_recovery_codes WHERE user_id = $1', [reader.userId])).rows.length, 0);
  assert.equal((await db.query('SELECT 1 FROM sync_devices WHERE user_id = $1', [reader.userId])).rows.length, 0);
  assert.equal((await db.query<{ state: string }>('SELECT state FROM cloud_files WHERE id = $1', [fileId])).rows[0]!.state,
    'DELETING', '云文件交给云空间维护任务删除');
  assert.equal(await points(db, reader.userId), 300, '交易记录保留');
  await assert.rejects(passwordLogin(tx, { username: 'leaving1', password: 'abcd1234' }), rejectedCode('INVALID_CREDENTIALS'));
  await assert.rejects(loginMethods(query, reader.userId), rejectedCode('ACCOUNT_NOT_FOUND'));
  assert.equal(await purgeDueAccountDeletions(tx), 0, '已处理过的账号不再处理');

  // 用户名和华为账号都放出来了：可以重新注册，但同一个华为账号不再送点。
  const again = await registerPasswordAccount(tx, { username: 'Leaving1', password: 'abcd1234' }, hasher);
  assert.deepEqual(await bindHuaweiAccount(tx, again.userId, 'leaving-open-id', null), { welcomeGranted: false });
  assert.equal(await points(db, again.userId), 0);
});

test('HTTP routes wire credentials, sessions and error mapping', async t => {
  const { db, tx, query } = await database();
  t.after(() => db.close());
  const app = Fastify();
  t.after(() => app.close());
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AccountAuthError) {
      void reply.status(error.statusCode).send({ code: error.code, message: error.message });
      return;
    }
    void reply.status(500).send({ code: 'INTERNAL_ERROR', message: String(error) });
  });
  const sessions = new Map<string, string>();
  const limited: string[] = [];
  registerAccountAuthRoutes(app, {
    db: query,
    transaction: tx,
    authenticate: async request => {
      const token = (request.headers.authorization || '').replace('Bearer ', '');
      const userId = sessions.get(token);
      if (!userId) throw new AccountAuthError(401, 'UNAUTHORIZED', '请先登录');
      (request as unknown as { userId: string; sessionId: string }).userId = userId;
      (request as unknown as { userId: string; sessionId: string }).sessionId = token;
    },
    userId: request => (request as unknown as { userId: string }).userId,
    sessionId: request => (request as unknown as { sessionId: string }).sessionId,
    issueSession: async userId => {
      const id = await session(db, userId);
      sessions.set(id, userId);
      return id;
    },
    account: async (_db, userId) => ({ userId }),
    limit: async (scope, subject) => { limited.push(`${scope}:${subject}`); },
    exchangeHuawei: async code => ({ openID: `open-${code}` }),
    recoveryHasher: hasher,
    authRateLimitPerMinute: 1000
  });

  const register = await app.inject({ method: 'POST', url: '/v1/auth/register',
    payload: { username: 'WebUser1', password: 'abcd1234' } });
  assert.equal(register.statusCode, 200);
  const body = register.json() as { sessionToken: string; account: { userId: string }; recoveryCodes: string[] };
  assert.equal(body.recoveryCodes.length, 8);
  assert.equal(sessions.get(body.sessionToken), body.account.userId);
  const auth = { authorization: `Bearer ${body.sessionToken}` };

  const wrong = await app.inject({ method: 'POST', url: '/v1/auth/password', payload: { username: 'webuser1', password: 'nope12345' } });
  assert.equal(wrong.statusCode, 401);
  assert.equal(wrong.json().code, 'INVALID_CREDENTIALS');
  assert.ok(limited.includes('auth-password-user:webuser1'));

  const methods = await app.inject({ method: 'GET', url: '/v1/account/login-methods', headers: auth });
  assert.equal(methods.json().username, 'WebUser1');
  const bind = await app.inject({ method: 'POST', url: '/v1/account/huawei', headers: auth, payload: { authorizationCode: 'abc' } });
  assert.equal(bind.statusCode, 200);
  assert.equal(bind.json().welcomeGranted, true);
  assert.equal(bind.json().loginMethods.huaweiBound, true);
  const rename = await app.inject({ method: 'POST', url: '/v1/account/username', headers: auth,
    payload: { username: 'WebUser2', currentPassword: 'abcd1234' } });
  assert.equal(rename.statusCode, 200);
  assert.equal(rename.json().loginMethods.username, 'WebUser2');
  assert.ok(rename.json().loginMethods.usernameChangeAvailableAt > Date.now());
  const again = await app.inject({ method: 'POST', url: '/v1/account/username', headers: auth,
    payload: { username: 'WebUser3', currentPassword: 'abcd1234' } });
  assert.equal(again.statusCode, 429);
  assert.equal(again.json().code, 'USERNAME_CHANGE_TOO_SOON');
  const codes = await app.inject({ method: 'POST', url: '/v1/account/recovery-codes', headers: auth,
    payload: { currentPassword: 'abcd1234' } });
  assert.equal(codes.json().recoveryCodes.length, 8);
  const deletion = await app.inject({ method: 'POST', url: '/v1/account/deletion', headers: auth,
    payload: { currentPassword: 'abcd1234' } });
  assert.equal(deletion.statusCode, 200);
  const login = await app.inject({ method: 'POST', url: '/v1/auth/password', payload: { username: 'WebUser2', password: 'abcd1234' } });
  assert.equal(login.json().deletionCancelled, true);
});
