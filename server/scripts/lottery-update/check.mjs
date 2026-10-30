// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded.
// Imports every changed module except index.js (which would start the server); touches no database.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const expectedOrigin = process.argv[2] ?? '';

const { config } = await load('config.js');
assert.equal(typeof config.lottery?.campaignId, 'string');
if (expectedOrigin) assert.equal(config.lottery.pageOrigin, expectedOrigin, 'LOTTERY_PAGE_ORIGIN not loaded');

const policy = await load('membershipPolicy.js');
assert.equal(policy.membershipCouponPoints({ LIFETIME: 100, SUPER_LIFETIME: 200 }, 'LIFETIME', 645), 100);
assert.equal(policy.membershipCouponPoints({ SUPER_LIFETIME: 600 }, 'SUPER_LIFETIME', 600), 300);
assert.equal(policy.membershipCouponPoints({ LIFETIME: 100 }, 'MONTHLY', 60), 0);
const plan = policy.planMembershipPurchase(null, [], 'LIFETIME', Date.now(), 'p', undefined, { id: 'c', points: 100 });
assert.equal(plan.payablePoints, 1190);
assert.equal(plan.next.permanentCreditPoints, 1190);

const service = await load('membershipService.js');
assert.equal(service.CLOUD_BASE_QUOTA_BYTES, 1024 ** 3);
assert.equal(await service.cloudQuotaBytes({ query: async () => ({ rows: [{ quota_bytes: '5368709120' }] }) }, 'u'), 5 * 1024 ** 3);
assert.equal(await service.cloudQuotaBytes({ query: async () => ({ rows: [] }) }, 'u'), 1024 ** 3);

const lottery = await load('lotteryService.js');
assert.equal(lottery.stripVerificationCode('读者 7KQ3XM', '7KQ3XM'), '读者');
assert.equal(lottery.stripVerificationCode('7kq3xm', '7KQ3XM'), '华为用户');

const cloud = await load('cloudFileService.js');
assert.equal(cloud.CLOUD_QUOTA_BYTES, 1024 ** 3);
await load('sync.js');

const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const { registerLotteryRoutes } = await load('lotteryRoutes.js');
const app = Fastify();
registerLotteryRoutes(app, { campaignId: 'check', pageOrigin: 'https://example.invalid',
  transaction: async () => { throw new Error('no database in preflight'); } });
await app.ready();
for (const [method, url] of [['GET', '/lottery/api/state'], ['POST', '/lottery/api/verify/start'],
  ['POST', '/lottery/api/verify/check'], ['POST', '/lottery/api/draw'], ['POST', '/lottery/api/coupon/super-choice'],
  ['POST', '/lottery/api/logout']]) {
  assert(app.hasRoute({ method, url }), `${method} ${url} missing`);
}
const forged = await app.inject({ method: 'POST', url: '/lottery/api/draw', payload: {}, headers: { origin: 'https://evil.invalid' } });
assert.equal(forged.statusCode, 403);
await app.close();
console.log('PASS: candidate modules load; coupon, quota, verification and route checks passed');
process.exit(0);
