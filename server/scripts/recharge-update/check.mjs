// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database.
// Loads the new recharge modules, registers their routes, and checks the Alipay keys when Alipay is configured.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const { config, readSecretFile } = await load('config.js');
const alipayModule = await load('alipay.js');
const credit = await load('pointCredit.js');
const recharge = await load('rechargeRoutes.js');
const auth = await load('accountAuth.js');

// Same rule as index.js: Alipay ordering is on only when all four required settings are present.
const a = config.alipay;
assert(a && typeof a.gateway === 'string', 'config.alipay missing from config.js');
const alipayOn = !!(a.appId && a.privateKeyPath && a.publicKeyPath && a.notifyUrl);
let alipay = null;
if (alipayOn) {
  alipay = new alipayModule.AlipayClient({
    appId: a.appId, privateKey: await readSecretFile(a.privateKeyPath),
    alipayPublicKey: await readSecretFile(a.publicKeyPath), gateway: a.gateway, notifyUrl: a.notifyUrl,
    returnUrl: a.returnUrl, quitUrl: a.quitUrl || a.returnUrl, sellerId: a.sellerId
  });
  const url = new URL(alipay.wapPayUrl({ outTradeNo: recharge.outTradeNo('00000000-0000-4000-8000-000000000000'),
    amountFen: 100, subject: 'preflight', expireMinutes: 30 }));
  assert.equal(url.origin + url.pathname, new URL(a.gateway).origin + new URL(a.gateway).pathname);
  assert(url.searchParams.get('sign'), 'checkout URL is signed');
  if (!/^https:\/\/.+\/v1\/recharge\/notify\/alipay$/.test(a.notifyUrl)) {
    console.log(`WARN: ALIPAY_NOTIFY_URL=${a.notifyUrl} is not an https://…/v1/recharge/notify/alipay address`);
  }
} else if (a.appId || a.privateKeyPath || a.publicKeyPath || a.notifyUrl) {
  console.log('WARN: Alipay partly configured (needs ALIPAY_APP_ID, ALIPAY_PRIVATE_KEY_PATH, ALIPAY_PUBLIC_KEY_PATH, ' +
    'ALIPAY_NOTIFY_URL); it stays off');
}

assert.equal(credit.calculatePaidReversal(100, 0, 30).debtPoints, 70);
assert.equal(recharge.redeemCodeHash('abcd-efgh ijkl-mnpq'), recharge.redeemCodeHash('ABCDEFGHIJKLMNPQ'));
assert(auth.DELETION_KEEPS_TABLES.includes('recharge_orders'), 'recharge_orders classified for account deletion');

const app = Fastify();
const unused = async () => { throw new Error('unexpected database use in preflight'); };
recharge.registerRechargeRoutes(app, {
  alipay, transaction: unused, account: unused, limit: async () => {},
  authenticate: async (req, reply) => {
    if (req.headers.authorization !== 'Bearer preflight') await reply.code(401).send({ code: 'UNAUTHORIZED' });
  },
  userId: () => '00000000-0000-4000-8000-000000000001'
});
app.setErrorHandler((error, _req, reply) => reply.code(error instanceof credit.PointCreditError ? error.statusCode : 500)
  .send({ code: error instanceof credit.PointCreditError ? error.code : 'UNEXPECTED' }));
await app.ready();
for (const [method, url] of [['GET', '/v1/recharge/channels'], ['POST', '/v1/recharge/orders'],
  ['GET', '/v1/recharge/orders/:id'], ['POST', '/v1/recharge/redeem'], ['POST', '/v1/recharge/notify/alipay']]) {
  assert(app.hasRoute({ method, url }), `${method} ${url}`);
}
const headers = { authorization: 'Bearer preflight' };
assert.equal((await app.inject({ method: 'GET', url: '/v1/recharge/channels' })).statusCode, 401);
const channels = (await app.inject({ method: 'GET', url: '/v1/recharge/channels', headers })).json();
assert.equal(channels.alipay, alipayOn);
assert.deepEqual(channels.products.map(p => p.points), [10, 60, 100, 300, 500, 1000]);
assert(channels.products.every(p => p.amountFen === p.points * 10), '1 元 = 10 点');
// Validation answers before any database access.
const bad = await app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers, payload: { code: '!' } });
assert.equal(bad.json().code, 'INVALID_CODE');
if (!alipayOn) {
  const order = await app.inject({ method: 'POST', url: '/v1/recharge/orders', headers, payload: { productId: 'legado_points_10' } });
  assert.equal(order.json().code, 'RECHARGE_UNAVAILABLE');
}
// An unsigned notify is rejected without touching the database.
const notify = await app.inject({ method: 'POST', url: '/v1/recharge/notify/alipay',
  headers: { 'content-type': 'application/x-www-form-urlencoded' }, payload: 'out_trade_no=x&trade_status=TRADE_SUCCESS' });
assert.equal(notify.body, 'failure');
await app.close();

const index = readFileSync(resolve(root, 'index.js'), 'utf8');
assert(index.includes("from './rechargeRoutes.js'") && index.includes('registerRechargeRoutes(app, {'));
assert(index.includes("client, userId, points, 'IAP_RECHARGE', orderId, `iap:${orderId}`)"), 'IAP credit uses creditPaidPoints');
assert(!index.includes("VALUES ($1, $2, $3, 'IAP_RECHARGE', $4, $5)"), 'old inline IAP credit is gone');
console.log(`PASS: candidate recharge modules load with the live environment; routes checked; Alipay ${alipayOn ? 'ON (keys load, checkout URL signed)' : 'OFF (redeem codes only)'}`);
process.exit(0);
