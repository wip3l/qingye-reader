// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database.
// Loads the two new account modules, registers their routes and checks the credential helpers.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const auth = await load('accountAuth.js');
const credentials = await load('accountCredentials.js');
const { config } = await load('config.js');

const hash = await credentials.hashPassword('preflight1');
assert.equal(await credentials.verifyPassword('preflight1', hash), true);
assert.equal(await credentials.verifyPassword('preflight2', hash), false);
const hasher = credentials.recoveryCodeHasher(config.sessionSecret);
const [code] = credentials.generateRecoveryCodes(1);
assert.equal(hasher(code.toLowerCase()), hasher(code));
assert.throws(() => credentials.normalizeUsername('1bad'));

const app = Fastify();
const unused = async () => { throw new Error('unexpected database use in preflight'); };
auth.registerAccountAuthRoutes(app, {
  db: { query: unused }, transaction: unused,
  authenticate: async (_req, reply) => { await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
  userId: () => '', sessionId: () => '', issueSession: unused, account: unused,
  limit: async () => {}, exchangeHuawei: unused, recoveryHasher: hasher, authRateLimitPerMinute: 100
});
app.setErrorHandler((error, _req, reply) => reply.code(error instanceof auth.AccountAuthError ? error.statusCode : 500)
  .send({ code: error instanceof auth.AccountAuthError ? error.code : 'UNEXPECTED' }));
await app.ready();
for (const [method, url] of [['POST', '/v1/auth/register'], ['POST', '/v1/auth/password'], ['POST', '/v1/auth/recover'],
  ['GET', '/v1/account/login-methods'], ['POST', '/v1/account/password'], ['POST', '/v1/account/recovery-codes'],
  ['POST', '/v1/account/huawei'], ['POST', '/v1/account/deletion']]) {
  assert(app.hasRoute({ method, url }), `${method} ${url}`);
}
// Input validation answers before any database access.
const weak = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { username: 'Preflight1', password: '12345678' } });
assert.equal(weak.json().code, 'WEAK_PASSWORD');
assert.equal((await app.inject({ method: 'GET', url: '/v1/account/login-methods' })).statusCode, 401);
await app.close();

const index = readFileSync(resolve(root, 'index.js'), 'utf8');
assert(index.includes("from './accountAuth.js'") && index.includes('registerAccountAuthRoutes(app, {'));
assert(index.includes('await grantHuaweiWelcome(client, userId, huaweiUser.openID)'));
assert(!index.includes("'WELCOME_GRANT', $4, $3"), 'old inline welcome grant is gone');
console.log('PASS: candidate account modules load with the live environment; routes and credential helpers checked');
process.exit(0);
