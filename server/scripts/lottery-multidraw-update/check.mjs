// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);

const lottery = await load('lotteryService.js');
assert.equal(lottery.drawLottery.length >= 5, true, 'drawLottery takes a draw number');
await assert.rejects(lottery.drawLottery({ query: async () => { throw new Error('no database'); } }, 'c', 'u', 0, '127.0.0.1'),
  { code: 'LOTTERY_INVALID_DRAW' });
assert.equal(lottery.stripVerificationCode('读者 7KQ3XM', '7KQ3XM'), '读者');

const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const { registerLotteryRoutes } = await load('lotteryRoutes.js');
const app = Fastify();
registerLotteryRoutes(app, { campaignId: 'check', pageOrigin: 'https://example.invalid',
  transaction: async () => { throw new Error('no database in preflight'); } });
await app.ready();
assert(app.hasRoute({ method: 'POST', url: '/lottery/api/draw' }));
const forged = await app.inject({ method: 'POST', url: '/lottery/api/draw', payload: { drawNo: 1 },
  headers: { origin: 'https://evil.invalid' } });
assert.equal(forged.statusCode, 403);
await app.close();
await load('config.js');
console.log('PASS: candidate lottery modules load; draw-number and route checks passed');
process.exit(0);
