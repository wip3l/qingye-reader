// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root (or a preflight copy).
// Uses only the PostgreSQL socket, a newly created disposable database and a temporary NOLOGIN role.
// Exercises membership redeem codes through the real route and the code tool (redeem-codes.mjs) end to end.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const pg = require('pg');
const Fastify = require('fastify');
const load = name => import(pathToFileURL(resolve(root, name)).href);
const credit = await load('pointCredit.js');
const recharge = await load('rechargeRoutes.js');
const { MembershipError } = await load('membershipPolicy.js');
const suffix = randomUUID().replaceAll('-', '');
const database = 'qingye_codes_test_' + suffix;
const appRole = 'qingye_codes_role_' + suffix;
// On the server: the postgres OS user over the /tmp socket. CODES_PG_* only for running the check elsewhere.
const host = process.env.CODES_PG_HOST || '/tmp';
const port = Number(process.env.CODES_PG_PORT || 5432);
const password = process.env.CODES_PG_PASSWORD || '';
const connection = { host, port, user: 'postgres', password: password || undefined,
  connectionTimeoutMillis: 10000, statement_timeout: 20000,
  lock_timeout: 10000, idle_in_transaction_session_timeout: 30000 };
const databaseUrl = host.startsWith('/')
  ? `postgresql://postgres@/${database}?host=${encodeURIComponent(host)}&port=${port}`
  : `postgresql://postgres:${encodeURIComponent(password)}@${host}:${port}/${database}`;
const admin = new pg.Client({ ...connection, database: 'postgres' });
const CONTENDERS = 8;
const outDir = mkdtempSync(join(tmpdir(), 'qingye-codes-check-'));
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
function tool(...args) {
  const result = spawnSync(process.execPath, [resolve(root, 'redeem-codes.mjs'), ...args],
    { cwd: root, encoding: 'utf8', env: { PATH: process.env.PATH, DATABASE_URL: databaseUrl, TZ: 'UTC' } });
  return { status: result.status, out: `${result.stdout}${result.stderr}` };
}
const codesIn = batch => readFileSync(join(outDir, `${batch}.txt`), 'utf8').trim().split('\n');
async function newUser(name) {
  const id = randomUUID();
  await pool.query(`INSERT INTO app_users(id, huawei_open_id, display_name) VALUES ($1, $2, $3)`, [id, 'open-' + id, name]);
  await pool.query('INSERT INTO point_wallets(user_id, balance, paid_balance, promo_balance) VALUES ($1, 0, 0, 0)', [id]);
  return id;
}
const membershipOf = async id => (await pool.query(`SELECT p.sku FROM membership_accounts a
  JOIN membership_periods p ON p.id = a.period_id WHERE a.user_id = $1`, [id])).rows[0]?.sku;
const paidOf = async id => Number((await pool.query('SELECT paid_balance FROM point_wallets WHERE user_id=$1', [id])).rows[0].paid_balance);
const tally = values => values.reduce((map, v) => ({ ...map, [v]: (map[v] || 0) + 1 }), {});

try {
  await admin.connect();
  step = 'create disposable database and role';
  assert.match(database, /^qingye_codes_test_[a-f0-9]{32}$/);
  assert.match(appRole, /^qingye_codes_role_[a-f0-9]{32}$/);
  await admin.query(`CREATE ROLE "${appRole}" NOLOGIN`);
  roleCreated = true;
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });

  step = 'migrate up to 034';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('035_membership_redeem_codes.sql'));
  for (const file of files.filter(f => f < '034')) { step = 'migrate ' + file; await run(file); }
  await pool.query(`ALTER TABLE point_wallets OWNER TO "${appRole}"`);
  for (const file of files.filter(f => f >= '034' && f < '035')) { step = 'migrate ' + file; await run(file); }
  await pool.query(`INSERT INTO redeem_codes(code_hash, batch, points) VALUES ('old', 'before-035', 60)`);
  for (const file of files.filter(f => f >= '035')) { step = 'migrate ' + file; await run(file); }
  step = 'rerun migration 035';
  await run('035_membership_redeem_codes.sql');
  assert.equal((await pool.query(`SELECT membership_sku FROM redeem_codes WHERE code_hash='old'`)).rows[0].membership_sku, null);
  await assert.rejects(pool.query(`INSERT INTO redeem_codes(code_hash, batch, points, membership_sku) VALUES ('x','x',1,'WEEKLY')`));
  assert.equal((await pool.query(`SELECT has_column_privilege($1, 'redeem_codes', 'membership_sku', 'SELECT,INSERT') AS ok`,
    [appRole])).rows[0].ok, true);
  pass('035 applies on top of existing codes, is rerunnable, rejects unknown tiers and is readable by the service role');

  step = 'qingye-codes create / list / status / revoke against PostgreSQL';
  let r = tool('create', '--batch', 'shop-annual', '--sku', 'annual', '--count', '3', '--out-dir', outDir);
  assert.equal(r.status, 0, r.out);
  r = tool('create', '--batch', 'shop-p60', '--points', '60', '--count', '2', '--expires', '2099-12-31', '--out-dir', outDir);
  assert.equal(r.status, 0, r.out);
  r = tool('create', '--batch', 'shop-annual', '--sku', 'ANNUAL', '--count', '1', '--out-dir', join(outDir, 'second'));
  assert.notEqual(r.status, 0, 'an existing batch name is refused');
  const annualCodes = codesIn('shop-annual');
  const pointCodes = codesIn('shop-p60');
  assert.equal(annualCodes.length, 3);
  assert.equal(new Set(annualCodes).size, 3);
  annualCodes.forEach(code => assert.match(code, /^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}$/));
  assert.equal((await pool.query(`SELECT count(*)::int AS n FROM redeem_codes WHERE batch='shop-annual'
    AND membership_sku='ANNUAL' AND points=480`)).rows[0].n, 3);
  r = tool('list');
  assert.equal(r.status, 0, r.out);
  assert.match(r.out, /shop-annual/);
  assert.match(r.out, /年度会员码/);
  r = tool('status', annualCodes[0].toLowerCase());
  assert.match(r.out, /可用/, r.out);
  r = tool('revoke', '--code', annualCodes[2]);
  assert.match(r.out, /已作废 1 个/, r.out);
  r = tool('revoke', '--batch', 'shop-p60');
  assert.notEqual(r.status, 0, 'batch revoke needs --yes');
  pass(step);

  step = 'redeem route against PostgreSQL';
  const app = Fastify();
  recharge.registerRechargeRoutes(app, {
    alipay: null, transaction: tx, limit: async () => {},
    authenticate: async (req, reply) => { if (!req.headers['x-user']) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers['x-user']),
    account: async (c, id) => (await c.query('SELECT balance FROM point_wallets WHERE user_id=$1', [id])).rows[0]
  });
  app.setErrorHandler((error, _req, reply) => {
    const known = error instanceof credit.PointCreditError || error instanceof MembershipError;
    reply.code(known ? error.statusCode : 500).send({ code: known ? error.code : 'UNEXPECTED', detail: String(error.message) });
  });
  await app.ready();
  const redeem = (user, code) => app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers: { 'x-user': user },
    payload: { code } });

  step = `${CONTENDERS} users racing for one membership code`;
  const racers = await Promise.all(Array.from({ length: CONTENDERS }, (_, i) => newUser('会员' + i)));
  const answers = await Promise.all(racers.map(user => redeem(user, annualCodes[0])));
  assert.deepEqual(tally(answers.map(a => a.statusCode === 200 ? a.json().kind : a.json().code)),
    { membership: 1, CODE_USED: CONTENDERS - 1 }, answers.map(a => a.body).join('\n'));
  const winner = racers[answers.findIndex(a => a.statusCode === 200)];
  assert.equal(await membershipOf(winner), 'ANNUAL');
  for (const loser of racers.filter(id => id !== winner)) assert.equal(await membershipOf(loser), undefined);
  assert.equal((await pool.query(`SELECT count(*)::int AS n FROM point_ledger WHERE user_id=$1
    AND reason IN ('REDEEM_CODE','MEMBERSHIP_PURCHASE')`, [winner])).rows[0].n, 2);
  assert.equal((await pool.query(`SELECT count(*)::int AS n FROM membership_orders WHERE user_id=$1`, [winner])).rows[0].n, 1);
  assert.match(tool('status', annualCodes[0]).out, /已兑换/);
  pass(step + ': one membership, one order, one credit and one charge');

  step = 'revoked membership code and points code from the tool';
  assert.equal((await redeem(racers[1], annualCodes[2])).json().code, 'CODE_EXPIRED');
  const points = await redeem(racers[1], pointCodes[0]);
  assert.equal(points.json().kind, 'points');
  assert.equal(await paidOf(racers[1]), 60);
  pass(step);

  step = 'lifetime owner: lower code refused and left usable';
  await pool.query(`INSERT INTO redeem_codes(code_hash, batch, points, membership_sku) VALUES ($1, 'm', 1290, 'LIFETIME')`,
    [recharge.redeemCodeHash('LIFE-LIFE-LIFE-LIFE')]);
  assert.equal((await redeem(racers[2], 'LIFE-LIFE-LIFE-LIFE')).statusCode, 200);
  assert.equal(await membershipOf(racers[2]), 'LIFETIME');
  const refused = await redeem(racers[2], annualCodes[1]);
  assert.equal(refused.json().code, 'MEMBERSHIP_ALREADY_OWNED');
  assert.match(tool('status', annualCodes[1]).out, /可用/);
  assert.equal((await redeem(racers[3], annualCodes[1])).statusCode, 200);
  await app.close();
  pass(step);
} catch (e) {
  const code = String(e.code || 'CHECK_FAILED');
  const detail = /^[0-9A-Z]{5}$/.test(code) || code === 'ERR_ASSERTION' ? ' ' + String(e.message).slice(0, 600) : '';
  console.error('FAIL', step, (/^[A-Z0-9_]+$/.test(code) ? code : 'CHECK_FAILED') + detail);
  process.exitCode = 1;
} finally {
  rmSync(outDir, { recursive: true, force: true });
  if (pool) await pool.end();
  if (created) {
    try {
      assert.match(database, /^qingye_codes_test_[a-f0-9]{32}$/);
      await admin.query(`DROP DATABASE "${database}"`);
      console.log('PASS temporary database removed');
    } catch {
      console.error('FAIL temporary database cleanup; retained database:', database);
      process.exitCode = 1;
    }
  }
  if (roleCreated) {
    try {
      assert.match(appRole, /^qingye_codes_role_[a-f0-9]{32}$/);
      await admin.query(`DROP ROLE "${appRole}"`);
    } catch {
      console.error('FAIL temporary role cleanup; retained role:', appRole);
      process.exitCode = 1;
    }
  }
  await admin.end();
}
if (!process.exitCode) console.log(`PASS ALL: ${passed} PostgreSQL checks; production database was not connected`);
