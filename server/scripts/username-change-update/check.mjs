// Preflight in a candidate copy of the runtime (cwd); no database or network.
// Loads the patched accountAuth.js with the live accountCredentials.js, registers its routes and checks the new
// username route answers before any database access.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const require = createRequire(resolve(root, 'package.json'));
const Fastify = require('fastify');
const auth = await import(pathToFileURL(resolve(root, 'accountAuth.js')).href);

assert.equal(auth.USERNAME_CHANGE_INTERVAL_DAYS, 30);
for (const name of ['changeUsername', 'loginMethods', 'setAccountPassword', 'passwordLogin', 'registerAccountAuthRoutes',
  'purgeDueAccountDeletions']) {
  assert.equal(typeof auth[name], 'function', `${name} missing`);
}

const app = Fastify();
const unused = async () => { throw new Error('unexpected database use in preflight'); };
auth.registerAccountAuthRoutes(app, {
  db: { query: unused }, transaction: unused,
  authenticate: async (req, reply) => {
    if (req.headers.authorization !== 'Bearer preflight') await reply.code(401).send({ code: 'UNAUTHORIZED' });
  },
  userId: () => '00000000-0000-4000-8000-000000000001',
  sessionId: () => '00000000-0000-4000-8000-000000000002',
  issueSession: unused, account: unused, limit: async () => {}, exchangeHuawei: unused,
  recoveryHasher: () => 'x', authRateLimitPerMinute: 1000
});
app.setErrorHandler((error, _req, reply) => reply.code(error instanceof auth.AccountAuthError ? error.statusCode : 500)
  .send({ code: error instanceof auth.AccountAuthError ? error.code : 'UNEXPECTED' }));
await app.ready();
for (const [method, url] of [['POST', '/v1/account/username'], ['POST', '/v1/account/password'],
  ['GET', '/v1/account/login-methods'], ['POST', '/v1/account/deletion'], ['POST', '/v1/auth/password']]) {
  assert(app.hasRoute({ method, url }), `${method} ${url}`);
}
assert.equal((await app.inject({ method: 'POST', url: '/v1/account/username', payload: {} })).statusCode, 401);
// A malformed name is refused before the database is touched.
const bad = await app.inject({ method: 'POST', url: '/v1/account/username', headers: { authorization: 'Bearer preflight' },
  payload: { username: '1bad', currentPassword: 'abcd1234' } });
assert.equal(bad.statusCode, 400);
assert.equal(bad.json().code, 'INVALID_USERNAME');
await app.close();

const index = readFileSync(resolve(root, 'index.js'), 'utf8');
assert(index.includes('registerAccountAuthRoutes(app, {'), 'index.js still mounts the account routes');
console.log('PASS: candidate accountAuth.js loads with the live modules; username route mounted and validates input');
process.exit(0);
