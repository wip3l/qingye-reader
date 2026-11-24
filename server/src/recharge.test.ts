import assert from 'node:assert/strict';
import test from 'node:test';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import { AlipayClient, AlipayFetch, extractResponseNode, loadPrivateKey, loadPublicKey, rsa2Sign, rsa2Verify,
  signContent, yuanToFen } from './alipay.js';
import { PointCreditError, PointDb } from './pointCredit.js';
import { outTradeNo, redeemCodeHash, registerRechargeRoutes } from './rechargeRoutes.js';
import { MembershipError } from './membershipPolicy.js';

// 测试用密钥：appKey 代表商户应用私钥，alipayKey 代表“支付宝”的签名私钥。
function keyPair() {
  return generateKeyPairSync('rsa', { modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' } });
}
const appKey = keyPair();
const alipayKey = keyPair();
const APP_ID = '2021000000000000';
const SELLER = '2088000000000000';

function alipaySigned(params: Record<string, string>): Record<string, string> {
  const withType = { ...params, app_id: APP_ID, seller_id: SELLER, sign_type: 'RSA2' };
  return { ...withType, sign: rsa2Sign(signContent(withType, ['sign', 'sign_type']), loadPrivateKey(alipayKey.privateKey)) };
}

async function setup(t: test.TestContext, fetcher?: AlipayFetch) {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(name => /^\d{3}_.+\.sql$/.test(name)).sort()) {
    await db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  }
  // node-postgres 返回 rowCount；PGlite 没有，补上。
  const adapter = (connection: Pick<PGlite, 'query'>): PointDb => ({
    query: (async (text: string, values?: unknown[]) => {
      const result = await connection.query(text, values);
      // SELECT 时 PGlite 的 affectedRows 是 0，按行数算；UPDATE/INSERT 时用 affectedRows。
      return { ...result, rowCount: result.rows.length || result.affectedRows || 0 };
    }) as unknown as PointDb['query']
  });
  const transaction = <T>(work: (client: PointDb) => Promise<T>) => db.transaction(client => work(adapter(client)));
  const alipay = new AlipayClient({
    appId: APP_ID, privateKey: appKey.privateKey, alipayPublicKey: alipayKey.publicKey,
    gateway: 'https://openapi.alipay.example/gateway.do', notifyUrl: 'https://api.example/v1/recharge/notify/alipay',
    returnUrl: 'https://api.example/recharge/done', quitUrl: '', sellerId: SELLER
  }, fetcher);
  const app = Fastify();
  t.after(() => app.close());
  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof PointCreditError || error instanceof MembershipError) {
      return reply.code(error.statusCode).send({ code: error.code });
    }
    return reply.code(500).send({ code: 'UNEXPECTED', message: String(error) });
  });
  registerRechargeRoutes(app, {
    alipay,
    authenticate: async (req, reply) => { if (!req.headers.authorization) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers.authorization).slice(7),
    transaction, limit: async () => {},
    account: async (client, userId) => (await client.query(
      'SELECT balance::integer AS balance, paid_balance::integer AS "paidBalance" FROM point_wallets WHERE user_id=$1',
      [userId])).rows[0]
  });
  async function user(paid = 0, debt = 0) {
    const id = randomUUID();
    await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES ($1,$2)', [id, id]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES ($1,$2,$2,0)', [id, paid]);
    if (debt) await db.query('INSERT INTO account_debts(user_id,iap_debt_points) VALUES ($1,$2)', [id, debt]);
    return id;
  }
  async function wallet(id: string) {
    const row = (await db.query<{ balance: number; paid: number; debt: number | null }>(
      `SELECT w.balance::integer AS balance, w.paid_balance::integer AS paid, d.iap_debt_points::integer AS debt
       FROM point_wallets w LEFT JOIN account_debts d ON d.user_id = w.user_id WHERE w.user_id=$1`, [id])).rows[0]!;
    return { balance: row.balance, paid: row.paid, debt: row.debt ?? 0 };
  }
  const auth = (id: string) => ({ authorization: `Bearer ${id}` });
  const notify = (params: Record<string, string>) => app.inject({ method: 'POST', url: '/v1/recharge/notify/alipay',
    headers: { 'content-type': 'application/x-www-form-urlencoded' }, payload: new URLSearchParams(params).toString() });
  return { db, app, alipay, user, wallet, auth, notify };
}

test('signing helpers follow Alipay rules', () => {
  assert.equal(signContent({ b: '2', a: '1', sign: 'x', empty: '', sign_type: 'RSA2' }, ['sign', 'sign_type']), 'a=1&b=2');
  const priv = loadPrivateKey(appKey.privateKey);
  const pub = loadPublicKey(appKey.publicKey);
  assert.ok(rsa2Verify('a=1', rsa2Sign('a=1', priv), pub));
  assert.ok(!rsa2Verify('a=2', rsa2Sign('a=1', priv), pub));
  // 支付宝工具导出的一行 base64 也要能读
  const oneLine = appKey.publicKey.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  assert.ok(rsa2Verify('a=1', rsa2Sign('a=1', priv), loadPublicKey(oneLine)));
  assert.equal(yuanToFen('6.00'), 600);
  assert.equal(yuanToFen('0.1'), 10);
  assert.equal(yuanToFen('1.234'), -1);
  assert.equal(extractResponseNode('{"x_response":{"a":"}{\\"","b":{"c":1}},"sign":"s"}', 'x_response'),
    '{"a":"}{\\"","b":{"c":1}}');
});

test('order → signed checkout URL → notify credits paid points once', async t => {
  const { app, user, wallet, auth, notify } = await setup(t);
  const id = await user(5);
  const channels = await app.inject({ url: '/v1/recharge/channels', headers: auth(id) });
  assert.equal(channels.json().alipay, true);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/recharge/orders', headers: auth(id),
    payload: { productId: 'legado_points_9999' } })).statusCode, 400, 'unknown product');

  const created = await app.inject({ method: 'POST', url: '/v1/recharge/orders', headers: auth(id),
    payload: { productId: 'legado_points_60' } });
  assert.equal(created.statusCode, 200);
  const { orderId, checkoutUrl, amountFen } = created.json();
  assert.equal(amountFen, 600);
  const query = Object.fromEntries(new URL(checkoutUrl).searchParams);
  assert.equal(query.method, 'alipay.trade.wap.pay');
  const biz = JSON.parse(query.biz_content!);
  assert.equal(biz.total_amount, '6.00');
  assert.equal(biz.out_trade_no, outTradeNo(orderId));
  assert.equal(biz.product_code, 'QUICK_WAP_WAY');
  assert.ok(rsa2Verify(signContent(query, ['sign']), query.sign!, loadPublicKey(appKey.publicKey)),
    'checkout URL is signed with the app key');

  const paid = alipaySigned({ out_trade_no: outTradeNo(orderId), trade_no: '2026112422001', trade_status: 'TRADE_SUCCESS',
    total_amount: '6.00' });
  // 篡改金额、伪造签名都不入账
  assert.equal((await notify({ ...paid, total_amount: '0.01' })).body, 'failure');
  assert.equal((await notify(alipaySigned({ ...paid, total_amount: '0.01', sign: '' }))).body, 'success');
  assert.deepEqual(await wallet(id), { balance: 5, paid: 5, debt: 0 }, 'signed but mismatched amount is ignored');
  assert.equal((await notify(paid)).body, 'success');
  assert.equal((await notify(paid)).body, 'success', 'duplicate notify is acknowledged');
  assert.deepEqual(await wallet(id), { balance: 65, paid: 65, debt: 0 }, 'credited exactly once');

  const status = await app.inject({ url: `/v1/recharge/orders/${orderId}`, headers: auth(id) });
  assert.equal(status.json().status, 'PAID');
  const other = await user();
  assert.equal((await app.inject({ url: `/v1/recharge/orders/${orderId}`, headers: auth(other) })).statusCode, 404,
    'orders are private');
});

test('recharge pays off refund debt first; full refund reverses and records debt for spent points', async t => {
  const { app, db, user, wallet, auth, notify } = await setup(t);
  const id = await user(0, 30);
  const { orderId } = (await app.inject({ method: 'POST', url: '/v1/recharge/orders', headers: auth(id),
    payload: { productId: 'legado_points_100' } })).json();
  const base = { out_trade_no: outTradeNo(orderId), trade_no: 'T1', total_amount: '10.00' };
  await notify(alipaySigned({ ...base, trade_status: 'TRADE_SUCCESS' }));
  assert.deepEqual(await wallet(id), { balance: 70, paid: 70, debt: 0 });

  // 花掉 50 点后全额退款：只能扣回 20 点，其余 80 点（含当初抵掉的 30）记成欠款
  await db.query('UPDATE point_wallets SET balance=20, paid_balance=20 WHERE user_id=$1', [id]);
  const refund = alipaySigned({ ...base, trade_status: 'TRADE_CLOSED', refund_fee: '10.00', gmt_refund: '2026-11-24 10:00:00' });
  assert.equal((await notify(refund)).body, 'success');
  assert.equal((await notify(refund)).body, 'success');
  assert.deepEqual(await wallet(id), { balance: 0, paid: 0, debt: 80 }, 'reversed once');
  const ledger = (await db.query<{ reason: string; delta: number }>(
    'SELECT reason, delta::integer AS delta FROM point_ledger WHERE user_id=$1 ORDER BY created_at', [id])).rows;
  assert.deepEqual(ledger.map(row => [row.reason, row.delta]), [['ALIPAY_RECHARGE', 70], ['ALIPAY_REVERSAL', -20]]);
});

test('returning to the app queries Alipay and credits a paid order whose notify is late', async t => {
  let tradeStatus = 'WAIT_BUYER_PAY';
  const fetcher: AlipayFetch = async (_url, init) => {
    const params = Object.fromEntries(new URLSearchParams(init.body));
    assert.ok(rsa2Verify(signContent(params, ['sign']), params.sign!, loadPublicKey(appKey.publicKey)));
    const out = JSON.parse(params.biz_content!).out_trade_no;
    const node = JSON.stringify({ code: '10000', msg: 'Success', out_trade_no: out, trade_no: 'T9',
      trade_status: tradeStatus, total_amount: '1.00' });
    const sign = rsa2Sign(node, loadPrivateKey(alipayKey.privateKey));
    return { ok: true, status: 200, text: async () => `{"alipay_trade_query_response":${node},"sign":"${sign}"}` };
  };
  const { app, user, wallet, auth } = await setup(t, fetcher);
  const id = await user();
  const { orderId } = (await app.inject({ method: 'POST', url: '/v1/recharge/orders', headers: auth(id),
    payload: { productId: 'legado_points_10' } })).json();
  assert.equal((await app.inject({ url: `/v1/recharge/orders/${orderId}`, headers: auth(id) })).json().status, 'PENDING');
  tradeStatus = 'TRADE_SUCCESS';
  const done = (await app.inject({ url: `/v1/recharge/orders/${orderId}`, headers: auth(id) })).json();
  assert.equal(done.status, 'PAID');
  assert.equal(done.creditedPoints, 10);
  assert.deepEqual(await wallet(id), { balance: 10, paid: 10, debt: 0 });
});

test('redeem codes credit paid points once and respect expiry and revocation', async t => {
  const { app, db, user, wallet, auth } = await setup(t);
  const id = await user();
  await db.query(`INSERT INTO redeem_codes(code_hash,batch,points) VALUES ($1,'t',300)`, [redeemCodeHash('ABCD-EFGH-JKLM-NPQR')]);
  await db.query(`INSERT INTO redeem_codes(code_hash,batch,points,expires_at) VALUES ($1,'t',100,now()-interval '1 day')`,
    [redeemCodeHash('OLDOLDOLDOLD')]);
  const redeem = (code: string, who = id) => app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers: auth(who),
    payload: { code } });
  assert.equal((await redeem('nope')).statusCode, 400);
  assert.equal((await redeem('ZZZZZZZZZZZZ')).statusCode, 404);
  assert.equal((await redeem('OLDOLDOLDOLD')).statusCode, 410);
  const ok = await redeem('abcd efgh-jklm npqr');
  assert.equal(ok.statusCode, 200, ok.body);
  assert.equal(ok.json().creditedPoints, 300);
  assert.equal((await redeem('ABCDEFGHJKLMNPQR')).statusCode, 409);
  assert.equal((await redeem('ABCDEFGHJKLMNPQR', await user())).statusCode, 409);
  assert.deepEqual(await wallet(id), { balance: 300, paid: 300, debt: 0 });
});

test('membership codes open the membership directly; upgrades keep the difference as paid points', async t => {
  const { app, db, user, wallet, auth } = await setup(t);
  const id = await user();
  const code = async (sku: string, points: number) => {
    const plain = randomUUID().replaceAll('-', '').slice(0, 16).toUpperCase();
    await db.query(`INSERT INTO redeem_codes(code_hash,batch,points,membership_sku) VALUES ($1,'m',$2,$3)`,
      [redeemCodeHash(plain), points, sku]);
    return plain;
  };
  const redeem = (plain: string, who = id) => app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers: auth(who),
    payload: { code: plain } });
  const membershipOf = async (who: string) => (await db.query<{ sku: string; expires_at: Date | null }>(
    `SELECT p.sku, p.expires_at FROM membership_accounts a JOIN membership_periods p ON p.id = a.period_id
     WHERE a.user_id = $1`, [who])).rows[0];
  const used = async (plain: string) => (await db.query<{ redeemed_by: string | null }>(
    'SELECT redeemed_by FROM redeem_codes WHERE code_hash=$1', [redeemCodeHash(plain)])).rows[0]!.redeemed_by;

  // No points needed: the code pays for exactly the annual price (or less under a promotion).
  const annual = await code('ANNUAL', 480);
  const first = await redeem(annual);
  assert.equal(first.statusCode, 200, first.body);
  assert.equal(first.json().kind, 'membership');
  assert.equal(first.json().sku, 'ANNUAL');
  assert.equal((await membershipOf(id))!.sku, 'ANNUAL');
  assert.deepEqual(await wallet(id), { balance: first.json().creditedPoints, paid: first.json().creditedPoints, debt: 0 });
  const ledger = (await db.query<{ reason: string; delta: number }>(
    `SELECT reason, delta::integer AS delta FROM point_ledger WHERE user_id=$1 ORDER BY delta DESC`, [id])).rows;
  assert.deepEqual(ledger.map(r => r.reason), ['REDEEM_CODE', 'MEMBERSHIP_PURCHASE']);
  assert.equal(ledger[0]!.delta + ledger[1]!.delta, first.json().creditedPoints);
  assert.equal((await redeem(annual)).json().code, 'CODE_USED');

  // Upgrading to lifetime credits the unused annual term; the difference stays as paid points.
  const before = (await wallet(id)).paid;
  const lifetime = await code('LIFETIME', 1290);
  const upgrade = await redeem(lifetime);
  assert.equal(upgrade.statusCode, 200, upgrade.body);
  assert.equal((await membershipOf(id))!.sku, 'LIFETIME');
  assert.equal((await membershipOf(id))!.expires_at, null);
  assert.ok(upgrade.json().creditedPoints > 0, 'unused annual term comes back as paid points');
  assert.equal((await wallet(id)).paid, before + upgrade.json().creditedPoints);

  // A lifetime owner cannot redeem a lower code: refused, and the code stays usable by someone else.
  const monthly = await code('MONTHLY', 60);
  const owned = await redeem(monthly);
  assert.equal(owned.statusCode, 409);
  assert.equal(owned.json().code, 'MEMBERSHIP_ALREADY_OWNED');
  assert.equal(await used(monthly), null);
  assert.equal((await wallet(id)).paid, before + upgrade.json().creditedPoints);
  const other = await user();
  assert.equal((await redeem(monthly, other)).statusCode, 200);
  assert.equal((await membershipOf(other))!.sku, 'MONTHLY');

  // Refund debt blocks a membership code without consuming it.
  const debtor = await user(0, 50);
  const blocked = await code('MONTHLY', 60);
  assert.equal((await redeem(blocked, debtor)).json().code, 'ACCOUNT_PAYMENT_RESTRICTED');
  assert.equal(await used(blocked), null);
  assert.deepEqual(await wallet(debtor), { balance: 0, paid: 0, debt: 50 });
  assert.equal(await membershipOf(debtor), undefined);
});

test('without Alipay configuration orders are refused but redeem codes still work', async t => {
  const app = Fastify();
  t.after(() => app.close());
  app.setErrorHandler((error, _req, reply) => reply.code(error instanceof PointCreditError ? error.statusCode : 500)
    .send({ code: (error as PointCreditError).code }));
  registerRechargeRoutes(app, { alipay: null, authenticate: async () => {}, userId: () => randomUUID(),
    transaction: async () => { throw new Error('unused'); }, limit: async () => {}, account: async () => ({}) });
  assert.equal((await app.inject({ url: '/v1/recharge/channels' })).json().alipay, false);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/recharge/orders', payload: { productId: 'legado_points_10' } }))
    .statusCode, 503);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/recharge/notify/alipay',
    headers: { 'content-type': 'application/x-www-form-urlencoded' }, payload: 'a=1' })).body, 'failure');
});
