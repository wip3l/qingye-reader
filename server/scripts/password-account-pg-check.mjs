// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root (or a preflight copy).
// Uses only the /tmp PostgreSQL socket and a newly created, empty disposable database.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const pg = require('pg');
const load = name => import(pathToFileURL(resolve(root, name)).href);
const auth = await load('accountAuth.js');
const { recoveryCodeHasher } = await load('accountCredentials.js');
const hasher = recoveryCodeHasher('preflight-secret-preflight-secret-000000');
const database = 'qingye_password_test_' + randomUUID().replaceAll('-', '');
const connection = { host: '/tmp', port: 5432, user: 'postgres',
  connectionTimeoutMillis: 10000, statement_timeout: 20000,
  lock_timeout: 10000, idle_in_transaction_session_timeout: 30000 };
const admin = new pg.Client({ ...connection, database: 'postgres' });
const CONTENDERS = 8;
let pool, created = false, step = 'connect local PostgreSQL';
let passed = 0;
function pass(label) { passed++; console.log('PASS', label); }
async function tx(work) {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const value = await work(c);
    await c.query('COMMIT');
    return value;
  } catch (e) { await c.query('ROLLBACK').catch(() => {}); throw e; }
  finally { c.release(); }
}
async function run(file) {
  const sql = (await readFile(resolve(root, 'migrations', file), 'utf8')).replace(/^VACUUM[^;]*;/gm, '');
  const c = await pool.connect();
  try { await c.query(sql); } finally { c.release(); }
}
const codeOf = result => result.status === 'fulfilled' ? 'OK' : String(result.reason?.code || result.reason?.message);
const tally = results => results.map(codeOf).reduce((map, code) => ({ ...map, [code]: (map[code] || 0) + 1 }), {});
const balance = async id => Number((await pool.query('SELECT balance FROM point_wallets WHERE user_id=$1', [id])).rows[0]?.balance);

try {
  await admin.connect();
  step = 'create disposable database';
  assert.match(database, /^qingye_password_test_[a-f0-9]{32}$/);
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate up to 030';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('031_password_accounts.sql'));
  for (const file of files.filter(f => f < '031')) { step = 'migrate ' + file; await run(file); }
  step = 'existing Huawei user who already received the welcome points';
  const legacy = randomUUID();
  await pool.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, 'legacy-open-id', '老用户')`, [legacy]);
  await pool.query('INSERT INTO point_wallets(user_id, balance, paid_balance, promo_balance) VALUES ($1, 300, 0, 300)', [legacy]);
  await pool.query(`INSERT INTO point_ledger(user_id, delta, balance_after, reason, reference_id, idempotency_key)
    VALUES ($1, 300, 300, 'WELCOME_GRANT', $2, $3)`, [legacy, legacy, 'welcome:' + legacy]);
  for (const file of files.filter(f => f >= '031')) { step = 'migrate ' + file; await run(file); }
  step = 'rerun migration 031';
  await run('031_password_accounts.sql');
  assert.equal(Number((await pool.query('SELECT count(*) FROM huawei_welcome_claims WHERE user_id=$1', [legacy])).rows[0].count), 1);
  pass('031 applies on top of existing data, backfills welcome claims and is rerunnable');

  step = 'Huawei login upsert still targets the openId constraint';
  const upsert = `INSERT INTO app_users (huawei_open_id, display_name) VALUES ($1, '华为用户')
    ON CONFLICT (huawei_open_id) DO UPDATE SET updated_at = now() RETURNING id`;
  assert.equal((await pool.query(upsert, ['legacy-open-id'])).rows[0].id, legacy);
  assert.equal(await auth.grantHuaweiWelcome(pool, legacy, 'legacy-open-id'), false);
  assert.equal(await balance(legacy), 300);
  pass(step);

  step = 'concurrent registrations of one username keep exactly one account';
  const registrations = await Promise.allSettled(Array.from({ length: CONTENDERS }, () =>
    auth.registerPasswordAccount(tx, { username: 'Racer01', password: 'abcd1234', ip: '10.0.0.1' }, hasher)));
  assert.deepEqual(tally(registrations), { OK: 1, USERNAME_TAKEN: CONTENDERS - 1 });
  const racer = registrations.find(r => r.status === 'fulfilled').value;
  assert.equal(racer.recoveryCodes.length, 8);
  assert.equal(await balance(racer.userId), 0);
  pass(step);

  step = 'password login, lockout after repeated failures';
  assert.equal((await auth.passwordLogin(tx, { username: 'racer01', password: 'abcd1234' })).userId, racer.userId);
  const wrong = await Promise.allSettled(Array.from({ length: 5 }, () =>
    auth.passwordLogin(tx, { username: 'racer01', password: 'wrong-pass1' })));
  assert.ok(wrong.every(r => r.status === 'rejected'));
  assert.equal(Number((await pool.query('SELECT failed_login_count FROM app_users WHERE id=$1', [racer.userId])).rows[0].failed_login_count), 5,
    'concurrent failures are all counted');
  await assert.rejects(auth.passwordLogin(tx, { username: 'racer01', password: 'abcd1234' }), e => e.code === 'LOGIN_LOCKED');
  await pool.query(`UPDATE app_users SET login_locked_until = now() - interval '1 second' WHERE id=$1`, [racer.userId]);
  pass(step);

  step = 'one recovery code used concurrently succeeds once';
  const recoveries = await Promise.allSettled(Array.from({ length: CONTENDERS }, (_, i) => auth.recoverWithCode(tx,
    { username: 'racer01', recoveryCode: racer.recoveryCodes[0], newPassword: 'newpass' + (10 + i) }, hasher)));
  assert.equal(tally(recoveries).OK, 1);
  assert.equal(Number((await pool.query(`SELECT count(*) FROM account_recovery_codes WHERE user_id=$1 AND used_at IS NULL`,
    [racer.userId])).rows[0].count), 7);
  await pool.query(`UPDATE app_users SET failed_login_count = 0, login_locked_until = NULL WHERE id=$1`, [racer.userId]);
  pass(step);

  step = 'one fresh Huawei account bound concurrently by different accounts: one owner, one welcome grant';
  const binders = [];
  for (let i = 0; i < CONTENDERS; i++) {
    binders.push((await auth.registerPasswordAccount(tx, { username: 'Binder' + i, password: 'abcd1234' }, hasher)).userId);
  }
  const binds = await Promise.allSettled(binders.map(id => auth.bindHuaweiAccount(tx, id, 'fresh-open-id', null)));
  assert.deepEqual(tally(binds), { OK: 1, HUAWEI_IN_USE: CONTENDERS - 1 });
  assert.equal(binds.find(r => r.status === 'fulfilled').value.welcomeGranted, true);
  const grants = await pool.query(`SELECT count(*) FROM point_ledger WHERE reason='WELCOME_GRANT' AND user_id = ANY($1::uuid[])`, [binders]);
  assert.equal(Number(grants.rows[0].count), 1);
  pass(step);

  step = 'deletion: request, then purge exactly once after the grace period';
  await auth.requestAccountDeletion(tx, racer.userId, 'newpass' + (10 + recoveries.findIndex(r => r.status === 'fulfilled')));
  await pool.query(`UPDATE app_users SET deletion_requested_at = now() - interval '8 days' WHERE id=$1`, [racer.userId]);
  const purges = await Promise.all([auth.purgeDueAccountDeletions(tx), auth.purgeDueAccountDeletions(tx)]);
  assert.equal(purges[0] + purges[1], 1);
  const gone = (await pool.query('SELECT username, password_hash, deleted_at FROM app_users WHERE id=$1', [racer.userId])).rows[0];
  assert.equal(gone.username, null);
  assert.equal(gone.password_hash, null);
  assert.ok(gone.deleted_at);
  assert.equal(Number((await pool.query('SELECT count(*) FROM account_recovery_codes WHERE user_id=$1', [racer.userId])).rows[0].count), 0);
  await assert.rejects(auth.passwordLogin(tx, { username: 'racer01', password: 'abcd1234' }), e => e.code === 'INVALID_CREDENTIALS');
  pass(step);

  step = 'every table with user_id is classified for account deletion';
  const tables = (await pool.query(`SELECT table_name FROM information_schema.columns
    WHERE column_name='user_id' AND table_schema='public'`)).rows.map(row => row.table_name);
  const known = new Set([...auth.DELETION_PURGES_TABLES, ...auth.DELETION_KEEPS_TABLES]);
  assert.deepEqual(tables.filter(name => !known.has(name)), []);
  pass(step);
} catch (e) {
  const code = String(e.code || 'CHECK_FAILED');
  const detail = /^[0-9A-Z]{5}$/.test(code) || code === 'ERR_ASSERTION' ? ' ' + String(e.message).slice(0, 300) : '';
  console.error('FAIL', step, (/^[A-Z0-9_]+$/.test(code) ? code : 'CHECK_FAILED') + detail);
  process.exitCode = 1;
} finally {
  if (pool) await pool.end();
  if (created) {
    try {
      assert.match(database, /^qingye_password_test_[a-f0-9]{32}$/);
      await admin.query(`DROP DATABASE "${database}"`);
      console.log('PASS temporary database removed');
    } catch {
      console.error('FAIL temporary database cleanup; retained database:', database);
      process.exitCode = 1;
    }
  }
  await admin.end();
}
if (!process.exitCode) console.log(`PASS ALL: ${passed} PostgreSQL checks; production database was not connected`);
