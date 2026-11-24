// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root (or a preflight copy).
// Uses only the /tmp PostgreSQL socket, a newly created disposable database and a temporary NOLOGIN role.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const pg = require('pg');
const Fastify = require('fastify');
const load = name => import(pathToFileURL(resolve(root, name)).href);
const auth = await load('accountAuth.js');
const credit = await load('pointCredit.js');
const recharge = await load('rechargeRoutes.js');
const suffix = randomUUID().replaceAll('-', '');
const database = 'qingye_recharge_test_' + suffix;
// Stands in for the service account: owns the existing tables, so 034 must grant it the new ones.
const appRole = 'qingye_recharge_role_' + suffix;
// On the server: the postgres OS user over the /tmp socket. RECHARGE_PG_* only for running the check elsewhere.
const connection = { host: process.env.RECHARGE_PG_HOST || '/tmp', port: Number(process.env.RECHARGE_PG_PORT || 5432),
  user: 'postgres', password: process.env.RECHARGE_PG_PASSWORD || undefined,
  connectionTimeoutMillis: 10000, statement_timeout: 20000,
  lock_timeout: 10000, idle_in_transaction_session_timeout: 30000 };
const admin = new pg.Client({ ...connection, database: 'postgres' });
const CONTENDERS = 8;
let pool, created = false, roleCreated = false, step = 'connect local PostgreSQL';
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
const count = async (sql, params) => Number((await pool.query(sql, params)).rows[0].count);
const wallet = async id => {
  const row = (await pool.query('SELECT balance, paid_balance FROM point_wallets WHERE user_id=$1', [id])).rows[0];
  return { balance: Number(row.balance), paid: Number(row.paid_balance) };
};
const debtOf = async id => Number((await pool.query('SELECT iap_debt_points FROM account_debts WHERE user_id=$1', [id]))
  .rows[0]?.iap_debt_points || 0);
async function newUser(name, balance = 0, paid = 0) {
  const id = randomUUID();
  await pool.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, $2, $3)`, [id, 'open-' + id, name]);
  await pool.query('INSERT INTO point_wallets(user_id, balance, paid_balance, promo_balance) VALUES ($1, $2, $3, $4)',
    [id, balance, paid, balance - paid]);
  return id;
}
async function newOrder(userId, points) {
  const id = randomUUID();
  await pool.query(`INSERT INTO recharge_orders (id, user_id, channel, product_id, amount_fen, points)
    VALUES ($1, $2, 'ALIPAY', $3, $4, $5)`, [id, userId, 'legado_points_' + points, points * 10, points]);
  return id;
}
const trade = (orderId, points, status, extra = {}) => ({ outTradeNo: recharge.outTradeNo(orderId), tradeStatus: status,
  tradeNo: 'T' + orderId.slice(0, 8), totalAmount: (points / 10).toFixed(2), payload: { check: true }, ...extra });
const tally = values => values.reduce((map, v) => ({ ...map, [v]: (map[v] || 0) + 1 }), {});

try {
  await admin.connect();
  step = 'create disposable database and role';
  assert.match(database, /^qingye_recharge_test_[a-f0-9]{32}$/);
  assert.match(appRole, /^qingye_recharge_role_[a-f0-9]{32}$/);
  await admin.query(`CREATE ROLE "${appRole}" NOLOGIN`);
  roleCreated = true;
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate up to 033';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('034_recharge.sql'));
  for (const file of files.filter(f => f < '034')) { step = 'migrate ' + file; await run(file); }
  await pool.query(`ALTER TABLE point_wallets OWNER TO "${appRole}"`);
  const before = await newUser('老用户', 50, 20);
  await pool.query('INSERT INTO account_debts(user_id, iap_debt_points) VALUES ($1, 30)', [before]);
  for (const file of files.filter(f => f >= '034')) { step = 'migrate ' + file; await run(file); }
  step = 'rerun migration 034';
  await run('034_recharge.sql');
  assert.deepEqual(await wallet(before), { balance: 50, paid: 20 });
  pass('034 applies on top of existing data and is rerunnable');

  step = '034 grants the service role the new tables';
  const grants = (await pool.query(`SELECT has_table_privilege($1, 'recharge_orders', 'SELECT,INSERT,UPDATE') AS orders,
    has_table_privilege($1, 'redeem_codes', 'SELECT,INSERT,UPDATE') AS codes`, [appRole])).rows[0];
  assert.deepEqual(grants, { orders: true, codes: true });
  pass(step);

  step = 'IAP credit through creditPaidPoints offsets debt first';
  const iap = await tx(c => credit.creditPaidPoints(c, before, 100, 'IAP_RECHARGE', 'order-1', 'iap:order-1'));
  assert.deepEqual([iap.creditedPoints, iap.debtOffsetPoints], [70, 30]);
  assert.deepEqual(await wallet(before), { balance: 120, paid: 90 });
  assert.equal(await debtOf(before), 0);
  await assert.rejects(tx(c => credit.creditPaidPoints(c, before, 100, 'IAP_RECHARGE', 'order-1', 'iap:order-1')),
    e => e.code === '23505');
  assert.deepEqual(await wallet(before), { balance: 120, paid: 90 });
  pass(step + '; a repeated idempotency key is rejected');

  step = `${CONTENDERS} concurrent Alipay paid notifications credit once`;
  const buyer = await newUser('买家', 0, 0);
  const paidOrder = await newOrder(buyer, 300);
  const outcomes = await Promise.all(Array.from({ length: CONTENDERS }, () =>
    tx(c => recharge.applyAlipayTrade(c, trade(paidOrder, 300, 'TRADE_SUCCESS')))));
  assert.deepEqual(tally(outcomes), { credited: 1, unchanged: CONTENDERS - 1 });
  assert.deepEqual(await wallet(buyer), { balance: 300, paid: 300 });
  assert.equal(await count(`SELECT count(*) FROM point_ledger WHERE idempotency_key=$1`, ['recharge:' + paidOrder]), 1);
  assert.equal((await pool.query('SELECT status FROM recharge_orders WHERE id=$1', [paidOrder])).rows[0].status, 'PAID');
  pass(step);

  step = 'amount mismatch is ignored; NOT_FOUND waits for expiry; TRADE_CLOSED closes; late payment still credits';
  const other = await newOrder(buyer, 60);
  assert.equal(await tx(c => recharge.applyAlipayTrade(c, trade(other, 60, 'TRADE_SUCCESS', { totalAmount: '0.01' }))), 'ignored');
  assert.equal(await tx(c => recharge.applyAlipayTrade(c, trade(other, 60, 'NOT_FOUND'))), 'unchanged');
  assert.equal(await tx(c => recharge.applyAlipayTrade(c, trade(other, 60, 'TRADE_CLOSED'))), 'closed');
  assert.equal(await tx(c => recharge.applyAlipayTrade(c, trade(other, 60, 'TRADE_SUCCESS'))), 'credited');
  assert.deepEqual(await wallet(buyer), { balance: 360, paid: 360 });
  assert.equal(await tx(c => recharge.applyAlipayTrade(c, trade(randomUUID(), 60, 'TRADE_SUCCESS'))), 'ignored');
  pass(step);

  step = 'concurrent full-refund notifications reverse once and record the spent part as debt';
  await pool.query('UPDATE point_wallets SET balance = balance - 250, paid_balance = paid_balance - 250 WHERE user_id=$1', [buyer]);
  const refunds = await Promise.all(Array.from({ length: 4 }, () =>
    tx(c => recharge.applyAlipayTrade(c, trade(paidOrder, 300, 'TRADE_CLOSED', { refundFee: '30.00' })))));
  assert.deepEqual(tally(refunds), { refunded: 1, unchanged: 3 });
  assert.deepEqual(await wallet(buyer), { balance: 0, paid: 0 });
  assert.equal(await debtOf(buyer), 190);
  assert.equal(await count(`SELECT count(*) FROM point_ledger WHERE idempotency_key=$1`, ['recharge-reversal:' + paidOrder]), 1);
  pass(step);

  step = 'redeem route against PostgreSQL';
  const app = Fastify();
  recharge.registerRechargeRoutes(app, {
    alipay: null, transaction: tx, limit: async () => {},
    authenticate: async (req, reply) => { if (!req.headers['x-user']) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers['x-user']),
    account: async (c, id) => (await c.query('SELECT balance FROM point_wallets WHERE user_id=$1', [id])).rows[0]
  });
  app.setErrorHandler((error, _req, reply) => reply.code(error instanceof credit.PointCreditError ? error.statusCode : 500)
    .send({ code: error instanceof credit.PointCreditError ? error.code : 'UNEXPECTED', detail: String(error.message) }));
  await app.ready();
  const redeem = (user, code) => app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers: { 'x-user': user },
    payload: { code } });
  // scripts/redeem-codes.mjs stores sha256 of the code without spaces/dashes, upper-cased: same as the route.
  const toolHash = code => createHash('sha256').update(code.replace(/[\s-]/g, '').toUpperCase(), 'utf8').digest('hex');
  const code = 'ABCD-EFGH-JKLM-NPQR';
  assert.equal(toolHash(code), recharge.redeemCodeHash('abcd efgh jklm npqr'));
  await pool.query(`INSERT INTO redeem_codes(code_hash, batch, points) VALUES ($1, 'check', 100)`, [toolHash(code)]);
  const racers = await Promise.all(Array.from({ length: CONTENDERS }, (_, i) => newUser('兑换' + i)));
  const answers = await Promise.all(racers.map(user => redeem(user, code.toLowerCase())));
  assert.deepEqual(tally(answers.map(r => r.statusCode === 200 ? 'OK' : r.json().code)), { OK: 1, CODE_USED: CONTENDERS - 1 });
  const winner = racers[answers.findIndex(r => r.statusCode === 200)];
  assert.deepEqual(await wallet(winner), { balance: 100, paid: 100 });
  assert.equal(await count(`SELECT count(*) FROM point_ledger WHERE reason='REDEEM_CODE'`), 1);
  await pool.query(`INSERT INTO redeem_codes(code_hash, batch, points, expires_at) VALUES ($1, 'check', 10, now() - interval '1 day')`,
    [toolHash('EXPI-REDC-ODEX-XXXX')]);
  assert.equal((await redeem(racers[1], 'EXPI-REDC-ODEX-XXXX')).json().code, 'CODE_EXPIRED');
  assert.equal((await redeem(racers[1], 'NOPE-NOPE-NOPE-NOPE')).json().code, 'INVALID_CODE');
  assert.deepEqual(await wallet(racers[1]), { balance: 0, paid: 0 });
  await app.close();
  pass(`${CONTENDERS} users racing for one redeem code: one credit; expired and unknown codes rejected`);

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
      assert.match(database, /^qingye_recharge_test_[a-f0-9]{32}$/);
      await admin.query(`DROP DATABASE "${database}"`);
      console.log('PASS temporary database removed');
    } catch {
      console.error('FAIL temporary database cleanup; retained database:', database);
      process.exitCode = 1;
    }
  }
  if (roleCreated) {
    try {
      assert.match(appRole, /^qingye_recharge_role_[a-f0-9]{32}$/);
      await admin.query(`DROP ROLE "${appRole}"`);
    } catch {
      console.error('FAIL temporary role cleanup; retained role:', appRole);
      process.exitCode = 1;
    }
  }
  await admin.end();
}
if (!process.exitCode) console.log(`PASS ALL: ${passed} PostgreSQL checks; production database was not connected`);
