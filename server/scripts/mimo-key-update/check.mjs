// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database.
// The candidate membershipRoutes.js runs on top of the live membershipService/membershipPolicy modules.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const { registerMembershipRoutes } = await load('membershipRoutes.js');
const { MembershipError } = await load('membershipPolicy.js');

const members = { lifetime: null, annual: new Date(Date.now() + 86400000) };
let current = '';
const db = { query: async sql => {
  if (sql.includes('FROM membership_accounts')) {
    if (!(current in members)) return { rows: [] };
    return { rows: [{ id: 'p', sku: members[current] ? 'ANNUAL' : 'LIFETIME', anchor_at: new Date(),
      expires_at: members[current], paid_months: 0, permanent_credit_points: '0', revision: 1 }] };
  }
  if (sql.includes('FROM account_debts')) return { rows: [] };
  if (sql.includes('FROM shared_provider_keys')) return { rows: [{ api_key: 'sk-preflight' }] };
  if (sql.includes('INSERT INTO shared_provider_key_grants')) return { rows: [] };
  throw new Error('unexpected query in preflight');
} };
const app = Fastify();
registerMembershipRoutes(app, {
  enabled: true, superEnabled: false,
  authenticate: async (req, reply) => { if (!req.headers.authorization) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
  userId: req => String(req.headers.authorization).slice(7),
  transaction: async work => work(db), limit: async () => {}, account: async () => ({}), wallet: async () => ({})
});
app.setErrorHandler((error, _req, reply) => reply.code(error instanceof MembershipError ? error.statusCode : 500)
  .send({ code: error instanceof MembershipError ? error.code : 'UNEXPECTED' }));
await app.ready();
assert(app.hasRoute({ method: 'POST', url: '/v1/membership/mimo-key' }));
assert(app.hasRoute({ method: 'GET', url: '/v1/membership' }), 'existing membership routes are kept');
const call = user => { current = user;
  return app.inject({ method: 'POST', url: '/v1/membership/mimo-key', headers: user ? { authorization: 'Bearer ' + user } : {} }); };
assert.equal((await call('')).statusCode, 401);
const granted = await call('lifetime');
assert.equal(granted.statusCode, 200);
assert.equal(granted.json().apiKey, 'sk-preflight');
assert.equal((await call('annual')).json().code, 'LIFETIME_MEMBERSHIP_REQUIRED');
assert.equal((await call('nobody')).statusCode, 403);
await app.close();
await load('config.js');
console.log('PASS: candidate membership routes load on the live modules; lifetime-only key route checked');
process.exit(0);
