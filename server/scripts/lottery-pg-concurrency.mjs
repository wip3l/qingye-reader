// Run via stdin as the PostgreSQL OS user, with cwd = deployed application root.
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
const { quoteMembership, purchaseMembership, cloudQuotaBytes } =
  await import(pathToFileURL(resolve(root, 'membershipService.js')).href);
const { drawLottery, setSuperChoice } = await import(pathToFileURL(resolve(root, 'lotteryService.js')).href);
const database = 'qingye_lottery_test_' + randomUUID().replaceAll('-', '');
const connection = { host: '/tmp', port: 5432, user: 'postgres',
  connectionTimeoutMillis: 10000, statement_timeout: 20000,
  lock_timeout: 10000, idle_in_transaction_session_timeout: 30000 };
const admin = new pg.Client({ ...connection, database: 'postgres' });
const CONTENDERS = 16;
const campaign = 'concurrency-test';
let pool, created = false, step = 'connect local PostgreSQL';
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
// Hold one separate session per contender before releasing the start barrier.
async function race(jobs) {
  let arrived = 0, release;
  const gate = new Promise(resolveGate => { release = resolveGate; });
  const timer = setTimeout(() => release(), 12000);
  try {
    return await Promise.allSettled(jobs.map(job => tx(async c => {
      if (++arrived === jobs.length) release();
      await gate;
      assert.equal(arrived, jobs.length, 'not all concurrent sessions connected');
      return job(c);
    })));
  } finally { clearTimeout(timer); }
}
async function user(paid = 10000) {
  const id = randomUUID();
  await pool.query('INSERT INTO app_users(id,huawei_open_id,created_at) VALUES($1,$2,$3)', [id, id, new Date(now - 86400000)]);
  await pool.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES($1,$2,$2,0)', [id, paid]);
  return id;
}
const grand = () => 0; // first weighted ticket: the limited prize
const lucky = max => max - 1; // last ticket: the fallback
const count = async (sql, args) => Number((await pool.query(sql, args)).rows[0].count);

try {
  await admin.connect();
  step = 'create disposable database';
  assert.match(database, /^qingye_lottery_test_[a-f0-9]{32}$/);
  await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
  created = true;
  console.log('Temporary database:', database);
  pool = new pg.Pool({ ...connection, database, max: CONTENDERS + 4 });
  pool.on('error', () => { console.error('FAIL idle test connection'); process.exitCode = 1; });
  assert.equal((await pool.query('SELECT current_database() AS name')).rows[0].name, database);

  step = 'migrate empty test database';
  const files = (await readdir(resolve(root, 'migrations'))).filter(n => /^\d{3}_.+\.sql$/.test(n)).sort();
  assert.ok(files.includes('026_lottery_coupons.sql'));
  for (const file of files) {
    const sql = (await readFile(resolve(root, 'migrations', file), 'utf8')).replace(/^VACUUM[^;]*;/gm, '');
    const c = await pool.connect();
    try { await c.query(sql); } finally { c.release(); }
  }
  await pool.query('UPDATE membership_products SET sales_enabled=true, sales_starts_at=NULL');
  await pool.query(`INSERT INTO lottery_campaigns(id,title,starts_at,ends_at,registered_before,enabled,super_no_coupon_quota_bytes)
    VALUES ($1,'并发测试',$2,$3,$4,true,5368709120)`,
  [campaign, new Date(now - 3600000), new Date(now + 3600000), new Date(now)]);
  await pool.query(`INSERT INTO lottery_prizes(id,campaign_id,label,weight,stock,discounts,is_fallback,sort_order) VALUES
    ('c-grand',$1,'特等奖',1,5,'{"LIFETIME":300,"SUPER_LIFETIME":600}',false,1),
    ('c-lucky',$1,'幸运奖',9,NULL,'{"LIFETIME":30,"SUPER_LIFETIME":60}',true,2)`, [campaign]);

  step = `${CONTENDERS} simultaneous draws by one account issue one coupon`;
  const single = await user();
  const draws = await race(Array.from({ length: CONTENDERS }, () =>
    c => drawLottery(c, campaign, single, '127.0.0.1', now, lucky)));
  assert.ok(draws.every(r => r.status === 'fulfilled'));
  assert.equal(new Set(draws.map(r => r.value.draw.coupon.id)).size, 1);
  assert.equal(draws.filter(r => !r.value.duplicate).length, 1);
  assert.equal(await count('SELECT count(*) FROM lottery_draws WHERE user_id=$1', [single]), 1);
  assert.equal(await count('SELECT count(*) FROM membership_coupons WHERE user_id=$1', [single]), 1);
  pass(step);

  step = 'a limited prize of 5 is never over-issued across 48 accounts';
  for (let round = 0; round < 3; round++) {
    const users = [];
    for (let i = 0; i < CONTENDERS; i++) users.push(await user());
    const results = await race(users.map(id => c => drawLottery(c, campaign, id, '127.0.0.1', now, grand)));
    assert.ok(results.every(r => r.status === 'fulfilled'));
  }
  const issued = (await pool.query("SELECT issued FROM lottery_prizes WHERE id='c-grand'")).rows[0];
  assert.equal(Number(issued.issued), 5);
  assert.equal(await count("SELECT count(*) FROM membership_coupons WHERE prize_id='c-grand'"), 5);
  assert.equal(await count("SELECT count(*) FROM membership_coupons WHERE prize_id='c-lucky'"), 48 - 5 + 1);
  pass(step);

  step = 'two quotes holding the same coupon spend it once';
  const twice = await user();
  await tx(c => drawLottery(c, campaign, twice, '127.0.0.1', now, lucky));
  const quotes = await Promise.all([0, 1].map(() => tx(c => quoteMembership(c, twice, 'LIFETIME', now))));
  assert.ok(quotes.every(q => q.couponPoints === 30));
  const purchases = await race(quotes.map((q, i) => c => purchaseMembership(c, twice, q.quoteId, 'twice-' + i, now)));
  assert.equal(purchases.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(purchases.find(r => r.status === 'rejected').reason.code, 'MEMBERSHIP_OFFER_CHANGED');
  assert.equal(await count("SELECT count(*) FROM membership_coupons WHERE user_id=$1 AND status='USED'", [twice]), 1);
  const paid = (await pool.query('SELECT paid_balance FROM point_wallets WHERE user_id=$1', [twice])).rows[0];
  assert.equal(Number(paid.paid_balance), 10000 - 1260);
  pass(step);

  step = 'switching to cloud space while paying with the coupon resolves to exactly one';
  for (let attempt = 0; attempt < 4; attempt++) {
    const id = await user();
    await tx(c => drawLottery(c, campaign, id, '127.0.0.1', now, lucky));
    const q = await tx(c => quoteMembership(c, id, 'SUPER_LIFETIME', now));
    assert.equal(q.couponPoints, 60);
    const [purchase, choice] = await race([
      c => purchaseMembership(c, id, q.quoteId, 'choice-race', now),
      c => setSuperChoice(c, campaign, id, 'CLOUD')
    ]);
    assert.equal([purchase, choice].filter(r => r.status === 'fulfilled').length, 1);
    const coupon = (await pool.query('SELECT status, super_choice FROM membership_coupons WHERE user_id=$1', [id])).rows[0];
    if (purchase.status === 'fulfilled') {
      assert.equal(coupon.status, 'USED');
      assert.equal(await cloudQuotaBytes(pool, id), 1024 ** 3);
    } else {
      assert.equal(purchase.reason.code, 'MEMBERSHIP_OFFER_CHANGED');
      assert.deepEqual([coupon.status, coupon.super_choice], ['AVAILABLE', 'CLOUD']);
    }
  }
  pass(step);

  step = 'a super purchase without a coupon raises cloud space to 5 GiB once';
  const cloud = await user();
  const cq = await tx(c => quoteMembership(c, cloud, 'SUPER_LIFETIME', now));
  const cloudResults = await race(Array.from({ length: 8 }, (_, i) =>
    c => purchaseMembership(c, cloud, cq.quoteId, 'cloud-' + i, now)));
  assert.ok(cloudResults.every(r => r.status === 'fulfilled'));
  assert.equal(await cloudQuotaBytes(pool, cloud), 5 * 1024 ** 3);
  assert.equal(await count('SELECT count(*) FROM cloud_quota_bonuses WHERE user_id=$1', [cloud]), 1);
  pass(step);
} catch (e) {
  const code = String(e.code || 'CHECK_FAILED');
  console.error('FAIL', step, /^[A-Z0-9_]+$/.test(code) ? code : 'CHECK_FAILED');
  process.exitCode = 1;
} finally {
  if (pool) await pool.end();
  if (created) {
    try {
      assert.match(database, /^qingye_lottery_test_[a-f0-9]{32}$/);
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
