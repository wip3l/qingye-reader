// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database.
// The new rechargeRoutes.js must load next to the installed membership modules and mount the redeem route.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const recharge = await load('rechargeRoutes.js');
const credit = await load('pointCredit.js');
const service = await load('membershipService.js');
const policy = await load('membershipPolicy.js');

assert.equal(typeof recharge.redeemMembershipCode, 'function');
assert.equal(typeof service.quoteMembership, 'function');
assert.equal(typeof service.purchaseMembership, 'function');
// The code tool's face values must match the installed price list.
assert.deepEqual(policy.MEMBERSHIP_PRODUCTS.map(p => `${p.sku}:${p.points}`),
  ['MONTHLY:60', 'ANNUAL:480', 'LIFETIME:1290', 'SUPER_LIFETIME:2490']);

const app = Fastify();
const unused = async () => { throw new Error('unexpected database use in preflight'); };
recharge.registerRechargeRoutes(app, {
  alipay: null, transaction: unused, account: unused, limit: async () => {},
  authenticate: async (req, reply) => {
    if (req.headers.authorization !== 'Bearer preflight') await reply.code(401).send({ code: 'UNAUTHORIZED' });
  },
  userId: () => '00000000-0000-4000-8000-000000000001'
});
app.setErrorHandler((error, _req, reply) => reply.code(error instanceof credit.PointCreditError ? error.statusCode : 500)
  .send({ code: error instanceof credit.PointCreditError ? error.code : 'UNEXPECTED' }));
await app.ready();
assert(app.hasRoute({ method: 'POST', url: '/v1/recharge/redeem' }));
assert.equal((await app.inject({ method: 'POST', url: '/v1/recharge/redeem', payload: { code: 'x' } })).statusCode, 401);
const bad = await app.inject({ method: 'POST', url: '/v1/recharge/redeem', headers: { authorization: 'Bearer preflight' },
  payload: { code: '!' } });
assert.equal(bad.json().code, 'INVALID_CODE');
await app.close();

// The tool parses and refuses bad arguments before touching the database.
const tool = spawnSync(process.execPath, [resolve(root, 'redeem-codes.mjs'), 'create', '--batch', 'x', '--sku', 'NOPE'],
  { encoding: 'utf8', env: { PATH: process.env.PATH } });
assert.equal(tool.status, 2, tool.stderr);
assert.match(tool.stderr, /--sku/);
console.log('PASS: candidate rechargeRoutes.js loads with the installed membership modules; redeem route and code tool checked');
process.exit(0);
