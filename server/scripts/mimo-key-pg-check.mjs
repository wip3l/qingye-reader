// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root (or a preflight copy).
// Uses only /tmp PostgreSQL socket and a newly-created, empty disposable database.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const pg = require('pg');
const Fastify = require('fastify');
const load = name => import(pathToFileURL(resolve(root, name)).href);
const { quoteMembership, purchaseMembership } = await load('membershipService.js');
const { MembershipError } = await load('membershipPolicy.js');
const { registerMembershipRoutes } = await load('membershipRoutes.js');
const database = 'qingye_mimo_key_test_' + randomUUID().replaceAll('-', '');
const connection = { host: '/tmp', port: 5432, user: 'postgres',
  connectionTimeoutMillis: 10000, statement_timeout: 20000,
  lock_timeout: 10000, idle_in_transaction_session_timeout: 30000 };
const admin = new pg.Client({ ...connection, database: 'postgres' });
const CONTENDERS = 8;
let pool, app, created = false, step = 'connect local PostgreSQL';
const now = Date.now();
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
async function user(paid = 10000) {
  const id = randomUUID();
  await pool.query('INSERT INTO app_users(id,huawei_open_id,created_at) VALUES($1,$2,$3)', [id, id, new Date(now - 86400000)]);
  await pool.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES($1,$2,$2,0)', [id, paid]);
  return id;
}
async function member(sku) {
  const id = await user();
  const quote = await tx(c => quoteMembership(c, id, sku, now));
  await tx(c => purchaseMembership(c, id, quote.quoteId, 'buy-' + randomUUID(), now));
  return id;
}
const fetchKey = userId => app.inject({ method: 'POST', url: '/v1/membership/mimo-key',
  headers: userId ? { authorization: 'Bearer ' + userId } : {} });

try {
  await admin.connect();
  step = 'create disposable database';
  assert.match(database, /^qingye_mimo_key_test_[a-f0-9]{32}$/);
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate empty test database';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('029_shared_provider_keys.sql'));
  for (const file of files) {
    step = 'migrate ' + file;
    const sql = (await readFile(resolve(root, 'migrations', file), 'utf8')).replace(/^VACUUM[^;]*;/gm, '');
    const c = await pool.connect();
    try { await c.query(sql); } finally { c.release(); }
  }
  step = 'rerun migration 029';
  const c = await pool.connect();
  try { await c.query(await readFile(resolve(root, 'migrations', '029_shared_provider_keys.sql'), 'utf8')); }
  finally { c.release(); }
  await pool.query('UPDATE membership_products SET sales_enabled=true, sales_starts_at=NULL');
  pass('migrations apply to an empty database and 029 is rerunnable');

  step = 'register the real route on the test database';
  app = Fastify();
  registerMembershipRoutes(app, {
    enabled: true, superEnabled: false,
    authenticate: async (req, reply) => { if (!req.headers.authorization) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers.authorization).slice(7),
    transaction: tx, limit: async () => {}, account: async () => ({}), wallet: async () => ({})
  });
  app.setErrorHandler((error, _req, reply) => reply.code(error instanceof MembershipError ? error.statusCode : 500)
    .send({ code: error instanceof MembershipError ? error.code : 'UNEXPECTED' }));
  await app.ready();
  const lifetime = await member('LIFETIME');
  const annual = await member('ANNUAL');
  const nobody = await user();

  step = 'no key stored yet';
  assert.equal((await fetchKey(lifetime)).json().code, 'SHARED_KEY_UNAVAILABLE');
  pass(step);

  step = 'lifetime members get the key; concurrent fetches keep one grant row with an exact count';
  await pool.query(`INSERT INTO shared_provider_keys(provider, api_key) VALUES ('mimo', 'sk-test-shared-key')`);
  const results = await Promise.all(Array.from({ length: CONTENDERS }, () => fetchKey(lifetime)));
  assert.ok(results.every(r => r.statusCode === 200 && r.json().apiKey === 'sk-test-shared-key'));
  assert.equal(results[0].headers['cache-control'], 'no-store');
  const grant = (await pool.query(`SELECT grant_count FROM shared_provider_key_grants WHERE provider='mimo' AND user_id=$1`,
    [lifetime])).rows;
  assert.deepEqual(grant.map(row => row.grant_count), [CONTENDERS]);
  pass(step);

  step = 'annual members, non-members and indebted lifetime members are refused';
  for (const id of [annual, nobody]) assert.equal((await fetchKey(id)).json().code, 'LIFETIME_MEMBERSHIP_REQUIRED');
  await pool.query(`INSERT INTO account_debts(user_id, iap_debt_points) VALUES ($1, 60)
    ON CONFLICT (user_id) DO UPDATE SET iap_debt_points = 60`, [lifetime]);
  assert.equal((await fetchKey(lifetime)).json().code, 'LIFETIME_MEMBERSHIP_REQUIRED');
  await pool.query('DELETE FROM account_debts WHERE user_id=$1', [lifetime]);
  assert.equal(Number((await pool.query(`SELECT count(*) FROM shared_provider_key_grants`)).rows[0].count), 1);
  pass(step);

  step = 'disabling the key stops new grants';
  await pool.query(`UPDATE shared_provider_keys SET enabled=false WHERE provider='mimo'`);
  assert.equal((await fetchKey(lifetime)).json().code, 'SHARED_KEY_UNAVAILABLE');
  assert.equal((await fetchKey('')).statusCode, 401);
  pass(step);
} catch (e) {
  const code = String(e.code || 'CHECK_FAILED');
  // PostgreSQL errors from the disposable database name the missing object; nothing secret is involved.
  const detail = /^[0-9A-Z]{5}$/.test(code) ? ' ' + String(e.message).slice(0, 200) : '';
  console.error('FAIL', step, (/^[A-Z0-9_]+$/.test(code) ? code : 'CHECK_FAILED') + detail);
  process.exitCode = 1;
} finally {
  if (app) await app.close();
  if (pool) await pool.end();
  if (created) {
    try {
      assert.match(database, /^qingye_mimo_key_test_[a-f0-9]{32}$/);
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
