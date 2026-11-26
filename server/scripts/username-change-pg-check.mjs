// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root (or a preflight copy).
// Uses only the /tmp PostgreSQL socket and a newly created, empty disposable database.
// USERNAME_PG_HOST / USERNAME_PG_PORT / USERNAME_PG_PASSWORD only for running the check elsewhere.
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
const database = 'qingye_username_test_' + randomUUID().replaceAll('-', '');
const connection = { host: process.env.USERNAME_PG_HOST || '/tmp', port: Number(process.env.USERNAME_PG_PORT || 5432),
  user: 'postgres', password: process.env.USERNAME_PG_PASSWORD || undefined,
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
const usernameOf = async id => (await pool.query('SELECT username FROM app_users WHERE id=$1', [id])).rows[0]?.username;
const rejectsWith = code => e => e?.code === code;

try {
  await admin.connect();
  step = 'create disposable database';
  assert.match(database, /^qingye_username_test_[a-f0-9]{32}$/);
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('036_username_change.sql'));
  for (const file of files.filter(f => f < '036')) { step = 'migrate ' + file; await run(file); }
  step = 'account set up before 036';
  const before = await auth.registerPasswordAccount(tx, { username: 'Early01', password: 'abcd1234' }, hasher);
  step = 'migrate 036 and rerun it';
  for (const file of files.filter(f => f >= '036')) { step = 'migrate ' + file; await run(file); }
  await run('036_username_change.sql');
  assert.equal((await pool.query('SELECT username_changed_at FROM app_users WHERE id=$1', [before.userId])).rows[0]
    .username_changed_at, null);
  assert.equal((await auth.loginMethods(pool, before.userId)).usernameChangeAvailableAt, null);
  pass('036 applies on top of existing accounts, is rerunnable, and existing accounts can rename right away');

  step = 'rename: refusals leave the name and the interval untouched';
  const reader = await auth.registerPasswordAccount(tx, { username: 'First01', password: 'abcd1234' }, hasher);
  await assert.rejects(auth.changeUsername(tx, reader.userId, { username: 'Second01', currentPassword: 'wrong-pass1' }),
    rejectsWith('WRONG_PASSWORD'));
  await assert.rejects(auth.changeUsername(tx, reader.userId, { username: 'first01x', currentPassword: '' }),
    rejectsWith('WRONG_PASSWORD'));
  await assert.rejects(auth.changeUsername(tx, reader.userId, { username: 'First01', currentPassword: 'abcd1234' }),
    rejectsWith('SAME_USERNAME'));
  await assert.rejects(auth.changeUsername(tx, reader.userId, { username: 'early01', currentPassword: 'abcd1234' }),
    rejectsWith('USERNAME_TAKEN'));
  assert.equal(await usernameOf(reader.userId), 'First01');
  assert.equal((await auth.loginMethods(pool, reader.userId)).usernameChangeAvailableAt, null);
  pass(step);

  step = 'rename: new name logs in, old name is released, interval starts';
  await auth.changeUsername(tx, reader.userId, { username: 'Second01', currentPassword: 'abcd1234' });
  const methods = await auth.loginMethods(pool, reader.userId);
  assert.equal(methods.username, 'Second01');
  assert.equal(methods.recoveryCodesRemaining, 8);
  assert.ok(methods.usernameChangeAvailableAt > Date.now() + 29.9 * 86400000);
  assert.ok(methods.usernameChangeAvailableAt < Date.now() + 30.1 * 86400000);
  assert.equal((await auth.passwordLogin(tx, { username: 'SECOND01', password: 'abcd1234' })).userId, reader.userId);
  await assert.rejects(auth.passwordLogin(tx, { username: 'first01', password: 'abcd1234' }), rejectsWith('INVALID_CREDENTIALS'));
  assert.ok((await auth.registerPasswordAccount(tx, { username: 'first01', password: 'abcd1234' }, hasher)).userId);
  await assert.rejects(auth.changeUsername(tx, reader.userId, { username: 'SECOND01', currentPassword: 'abcd1234' }),
    e => e?.code === 'USERNAME_CHANGE_TOO_SOON' && e.retryAfter > 29 * 86400);
  await pool.query(`UPDATE app_users SET username_changed_at = now() - interval '30 days 1 minute' WHERE id=$1`, [reader.userId]);
  await auth.changeUsername(tx, reader.userId, { username: 'SECOND01', currentPassword: 'abcd1234' });
  assert.equal(await usernameOf(reader.userId), 'SECOND01');
  pass(step);

  step = 'accounts racing for one new name: exactly one gets it';
  const racers = [];
  for (let i = 0; i < CONTENDERS; i++) {
    racers.push((await auth.registerPasswordAccount(tx, { username: 'Racer' + i, password: 'abcd1234' }, hasher)).userId);
  }
  const race = await Promise.allSettled(racers.map(id =>
    auth.changeUsername(tx, id, { username: 'Winner01', currentPassword: 'abcd1234' })));
  assert.deepEqual(tally(race), { OK: 1, USERNAME_TAKEN: CONTENDERS - 1 });
  const winner = racers[race.findIndex(r => r.status === 'fulfilled')];
  assert.equal(await usernameOf(winner), 'Winner01');
  const losers = racers.filter(id => id !== winner);
  for (const id of losers) assert.equal((await auth.loginMethods(pool, id)).usernameChangeAvailableAt, null);
  pass(step);

  step = 'one account renaming concurrently: one change inside the interval';
  const solo = losers[0];
  const burst = await Promise.allSettled(Array.from({ length: CONTENDERS }, (_, i) =>
    auth.changeUsername(tx, solo, { username: 'Burst' + i, currentPassword: 'abcd1234' })));
  assert.deepEqual(tally(burst), { OK: 1, USERNAME_CHANGE_TOO_SOON: CONTENDERS - 1 });
  assert.equal(await usernameOf(solo), 'Burst' + burst.findIndex(r => r.status === 'fulfilled'));
  pass(step);

  step = 'Huawei-only account: no rename before a username exists; first setup does not start the interval';
  const huawei = randomUUID();
  await pool.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, $2, '华为用户')`, [huawei, 'hw-' + huawei]);
  await assert.rejects(auth.changeUsername(tx, huawei, { username: 'Hw01', currentPassword: 'abcd1234' }),
    rejectsWith('PASSWORD_NOT_SET'));
  await auth.setAccountPassword(tx, huawei, randomUUID(), { username: 'Hw01', newPassword: 'abcd1234' }, hasher);
  assert.equal((await auth.loginMethods(pool, huawei)).usernameChangeAvailableAt, null);
  pass(step);

  step = 'deletion purge clears the rename time with the username';
  await auth.requestAccountDeletion(tx, winner, 'abcd1234');
  await pool.query(`UPDATE app_users SET deletion_requested_at = now() - interval '8 days' WHERE id=$1`, [winner]);
  assert.equal(await auth.purgeDueAccountDeletions(tx), 1);
  const gone = (await pool.query('SELECT username, username_changed_at, deleted_at FROM app_users WHERE id=$1', [winner])).rows[0];
  assert.equal(gone.username, null);
  assert.equal(gone.username_changed_at, null);
  assert.ok(gone.deleted_at);
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
      assert.match(database, /^qingye_username_test_[a-f0-9]{32}$/);
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
