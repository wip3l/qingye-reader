// Run via stdin as the PostgreSQL OS user with the service environment loaded (config.js needs it at import),
// cwd = deployed application root or a preflight copy. Uses only the /tmp PostgreSQL socket and a newly created,
// empty disposable database; the production database is never connected.
// SYNC_HISTORY_PG_HOST / SYNC_HISTORY_PG_PORT / SYNC_HISTORY_PG_PASSWORD only for running the check elsewhere.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const pg = require('pg');
const sync = await import(pathToFileURL(resolve(root, 'sync.js')).href);
const database = 'qingye_sync_history_test_' + randomUUID().replaceAll('-', '');
const connection = { host: process.env.SYNC_HISTORY_PG_HOST || '/tmp', port: Number(process.env.SYNC_HISTORY_PG_PORT || 5432),
  user: 'postgres', password: process.env.SYNC_HISTORY_PG_PASSWORD || undefined,
  connectionTimeoutMillis: 10000, statement_timeout: 30000,
  lock_timeout: 15000, idle_in_transaction_session_timeout: 30000 };
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
const quota = () => ({ entityCount: 0, entityBytes: 0, changeCount: 0, changeBytes: 0, dailyWrites: 0 });
// Writes go straight through applyOperation; keep the account's usage row in line with the stored entities the way
// the exchange would, so the restore path's quota accounting starts from real numbers.
const write = async (userId, deviceId, entityType, payload, baseRevision, policy) => {
  const ack = await tx(c => sync.applyOperation(c, userId, deviceId, { opId: randomUUID(), entityType,
    entityId: 'global', operation: 'upsert', baseRevision, payload,
    payloadBytes: Buffer.byteLength(JSON.stringify(payload)) }, policy, quota()));
  await pool.query(`INSERT INTO sync_user_usage (user_id, entity_count, entity_bytes, change_count)
    SELECT $1, count(*), COALESCE(sum(octet_length(payload::text)), 0), count(*) FROM sync_entities WHERE user_id = $1
    ON CONFLICT (user_id) DO UPDATE SET entity_count = EXCLUDED.entity_count, entity_bytes = EXCLUDED.entity_bytes,
      change_count = EXCLUDED.change_count`, [userId]);
  return ack;
};
const history = async (userId, entityType = 'reader_settings') => (await pool.query(
  `SELECT id, revision, reason, payload FROM sync_entity_history WHERE user_id=$1 AND entity_type=$2 ORDER BY id`,
  [userId, entityType])).rows;
const current = async (userId, entityType = 'reader_settings') => (await pool.query(
  `SELECT revision, payload FROM sync_entities WHERE user_id=$1 AND entity_type=$2 AND entity_id='global'`,
  [userId, entityType])).rows[0];
async function account(devices) {
  const userId = randomUUID();
  await pool.query('INSERT INTO app_users(id, huawei_open_id) VALUES ($1, $2)', [userId, 'hw-' + userId]);
  const ids = [];
  for (let i = 0; i < devices; i++) {
    const id = randomUUID();
    await tx(c => sync.registerDevice(c, userId, id, '设备' + i, 'HarmonyOS', '4.6.047', 'phone', 0));
    ids.push(id);
  }
  return { userId, devices: ids };
}

try {
  await admin.connect();
  step = 'create disposable database';
  assert.match(database, /^qingye_sync_history_test_[a-f0-9]{32}$/);
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('037_sync_entity_history.sql'));
  for (const file of files.filter(f => f < '037')) { step = 'migrate ' + file; await run(file); }
  step = 'settings synced before 037';
  const early = await account(2);
  await write(early.userId, early.devices[0], 'reader_settings', { font: 'early' }, 0, 'cloud');
  step = 'migrate 037 and rerun it';
  for (const file of files.filter(f => f >= '037')) { step = 'migrate ' + file; await run(file); }
  await run('037_sync_entity_history.sql');
  assert.equal((await write(early.userId, early.devices[1], 'reader_settings', { font: 'default' }, 0, 'local')).accepted, true);
  assert.deepEqual((await history(early.userId)).map(row => [row.reason, row.payload.font]), [['local_first', 'early']]);
  pass('037 applies on a database with synced settings, is rerunnable, and records the first forced overwrite');

  step = 'only forced overwrites and restores are recorded';
  const user = await account(2);
  const [phone, tablet] = user.devices;
  await write(user.userId, phone, 'reader_settings', { font: 'A' }, 0, 'cloud');
  await write(user.userId, phone, 'reader_settings', { font: 'B' }, 1, 'cloud');
  await write(user.userId, tablet, 'reader_settings', { font: 'C' }, 2, 'cloud');
  const stale = await write(user.userId, tablet, 'reader_settings', { font: 'stale' }, 1, 'cloud');
  assert.equal(stale.accepted, false);
  assert.equal((await history(user.userId)).length, 0);
  await write(user.userId, phone, 'bookshelf_display', { layout: 'grid' }, 0, 'cloud');
  await write(user.userId, tablet, 'bookshelf_display', { layout: 'grid' }, 0, 'local');
  assert.equal((await history(user.userId, 'bookshelf_display')).length, 0, 'identical content is not recorded');
  await write(user.userId, tablet, 'reader_settings', { font: 'default' }, 0, 'local');
  assert.deepEqual((await history(user.userId)).map(row => [row.reason, row.payload.font]), [['local_first', 'C']]);
  pass(step);

  step = 'list groups one forced sync and restore puts the old version back as a new revision';
  const listed = await sync.listSyncHistory(user.userId, pool);
  assert.equal(listed.groups.length, 1);
  assert.equal(listed.groups[0].deviceId, tablet);
  assert.equal(listed.groups[0].deviceName, '设备1');
  assert.equal(listed.groups[0].reason, 'local_first');
  const historyId = listed.groups[0].items[0].historyId;
  const restored = await tx(c => sync.restoreSyncHistoryIn(c, user.userId, phone, [historyId]));
  assert.equal(restored.restored, 1);
  const after = await current(user.userId);
  assert.equal(after.payload.font, 'C');
  assert.deepEqual((await history(user.userId)).map(row => [row.reason, row.payload.font]),
    [['local_first', 'C'], ['restore', 'default']]);
  const changed = (await pool.query(`SELECT count(*) FROM sync_changes WHERE user_id=$1 AND entity_type='reader_settings'`,
    [user.userId])).rows[0];
  assert.equal(Number(changed.count), 1, 'still one change marker, so other devices pull the restored version');
  pass(step);

  step = 'restore refuses foreign, unknown and unregistered requests without writing';
  const other = await account(1);
  const revisionBefore = (await current(user.userId)).revision;
  await assert.rejects(tx(c => sync.restoreSyncHistoryIn(c, other.userId, other.devices[0], [historyId])),
    e => e?.code === 'SYNC_HISTORY_NOT_FOUND');
  await assert.rejects(tx(c => sync.restoreSyncHistoryIn(c, user.userId, phone, ['999999999'])),
    e => e?.code === 'SYNC_HISTORY_NOT_FOUND');
  await assert.rejects(tx(c => sync.restoreSyncHistoryIn(c, user.userId, randomUUID(), [historyId])),
    e => e?.code === 'SYNC_DEVICE_NOT_READY');
  assert.equal((await current(user.userId)).revision, revisionBefore);
  pass(step);

  step = 'concurrent restores of the same version apply once';
  const target = (await history(user.userId)).find(row => row.reason === 'restore');
  const racing = await Promise.allSettled(Array.from({ length: CONTENDERS }, () =>
    tx(c => sync.restoreSyncHistoryIn(c, user.userId, phone, [String(target.id)]))));
  assert.deepEqual(racing.map(r => r.status), Array(CONTENDERS).fill('fulfilled'));
  assert.equal(racing.reduce((sum, r) => sum + r.value.restored, 0), 1);
  assert.equal((await current(user.userId)).payload.font, 'default');
  pass(step);

  step = 'devices forcing the same settings at once each leave the version they replaced';
  const crowd = await account(CONTENDERS);
  await write(crowd.userId, crowd.devices[0], 'reader_settings', { font: 'seed' }, 0, 'cloud');
  const forced = await Promise.allSettled(crowd.devices.map((device, i) =>
    write(crowd.userId, device, 'reader_settings', { font: 'device' + i }, 0, 'local')));
  assert.deepEqual(forced.map(r => r.status === 'fulfilled' && r.value.accepted), Array(CONTENDERS).fill(true));
  const crowdRows = await history(crowd.userId);
  assert.equal(crowdRows.length, CONTENDERS);
  assert.deepEqual(crowdRows.map(row => Number(row.revision)).sort((a, b) => a - b),
    Array.from({ length: CONTENDERS }, (_, i) => i + 1));
  assert.equal(Number((await current(crowd.userId)).revision), CONTENDERS + 1);
  pass(step);

  step = 'each item keeps the newest 10 versions';
  for (let i = 0; i < 12; i++) {
    await write(crowd.userId, crowd.devices[1], 'reader_settings', { font: 'more' + i }, 0, 'local');
  }
  assert.equal((await history(crowd.userId)).length, sync.HISTORY_KEEP_PER_ENTITY);
  pass(step);

  step = 'one account keeps at most 3MB of history, dropping the oldest';
  const big = await account(1);
  for (let i = 0; i < 7; i++) {
    await write(big.userId, big.devices[0], 'custom_theme_schemes', { schemes: String(i).repeat(700 * 1024) }, 0, 'local');
  }
  const usage = (await pool.query(`SELECT count(*) AS rows, sum(octet_length(payload::text)) AS bytes, max(revision) AS newest
    FROM sync_entity_history WHERE user_id=$1`, [big.userId])).rows[0];
  assert.ok(Number(usage.bytes) <= sync.HISTORY_MAX_BYTES_PER_USER);
  assert.equal(Number(usage.rows), 4);
  assert.equal(Number(usage.newest), 6);
  assert.equal((await history(crowd.userId)).length, sync.HISTORY_KEEP_PER_ENTITY, 'other accounts untouched');
  pass(step);

  step = 'account deletion purges the history table; every user_id table is registered';
  const auth = await import(pathToFileURL(resolve(root, 'accountAuth.js')).href);
  assert.ok(auth.DELETION_PURGES_TABLES.includes('sync_entity_history'));
  const registered = new Set([...auth.DELETION_PURGES_TABLES, ...auth.DELETION_KEEPS_TABLES]);
  const userTables = (await pool.query(`SELECT DISTINCT table_name FROM information_schema.columns
    WHERE table_schema='public' AND column_name='user_id' ORDER BY table_name`)).rows.map(row => row.table_name);
  assert.deepEqual(userTables.filter(name => !registered.has(name)), []);
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
      assert.match(database, /^qingye_sync_history_test_[a-f0-9]{32}$/);
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
