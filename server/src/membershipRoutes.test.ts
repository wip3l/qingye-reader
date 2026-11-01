import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import type { PoolClient } from 'pg';
import { parseMembershipSalesPilot } from './membershipSales.js';
import { registerMembershipRoutes } from './membershipRoutes.js';
import { MEMBERSHIP_PRODUCTS, MembershipError, MembershipSku } from './membershipPolicy.js';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { MembershipDb, purchaseMembership, quoteMembership } from './membershipService.js';

const id = 'd105489a-3d17-4f18-af36-7a15e5e1b3ae';
test('pilot configuration requires explicit IDs, products and timezone expiry', () => {
  assert.equal(parseMembershipSalesPilot(), undefined);
  for (const args of [[id, '', ''], ['icyn', 'MONTHLY', '2030-01-01T00:00:00Z'],
    [id, '*', '2030-01-01T00:00:00Z'], [id, 'MONTHLY', '2030-01-01']]) {
    assert.throws(() => parseMembershipSalesPilot(...args));
  }
});

test('HTTP catalog uses authenticated identity and rejects request-supplied pilot privileges', async t => {
  const app = Fastify();
  t.after(() => app.close());
  const db = { query: async () => ({ rows: MEMBERSHIP_PRODUCTS.map(p => ({ sku: p.sku, sales_enabled: false, sales_starts_at: null })) }) } as unknown as PoolClient;
  registerMembershipRoutes(app, {
    enabled: true, superEnabled: false,
    salesPilot: parseMembershipSalesPilot(id, 'MONTHLY,SUPER_LIFETIME', new Date(Date.now() + 60000).toISOString()),
    authenticate: async (req, reply) => {
      if (!['Bearer pilot', 'Bearer other'].includes(req.headers.authorization || '')) {
        await reply.code(401).send({ code: 'UNAUTHORIZED' });
      }
    },
    userId: req => req.headers.authorization === 'Bearer pilot' ? id : '00000000-0000-0000-0000-000000000001',
    transaction: async work => work(db), limit: async () => {}, account: async () => ({}), wallet: async () => ({})
  });
  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
    return reply.code(500).send({ code: 'UNEXPECTED' });
  });
  const publicCatalog = await app.inject('/v1/membership/catalog?userId=' + id);
  assert.ok(publicCatalog.json().products.every((p: { salesEnabled: boolean }) => !p.salesEnabled));
  assert.equal((await app.inject('/v1/membership/catalog/account')).statusCode, 401);
  for (const [token, expected] of [['other', []], ['pilot', ['MONTHLY']]] as const) {
    const res = await app.inject({ url: '/v1/membership/catalog/account', headers: { authorization: 'Bearer ' + token } });
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['cache-control'], 'private, no-store');
    assert.deepEqual(res.json().products.filter((p: { salesEnabled: boolean }) => p.salesEnabled).map((p: { sku: string }) => p.sku), expected);
  }
  const forged = await app.inject({ method: 'POST', url: '/v1/membership/quote',
    headers: { authorization: 'Bearer other' }, payload: { sku: 'MONTHLY', userId: id, salesPilot: true } });
  assert.equal(forged.statusCode, 409);
  assert.equal(forged.json().code, 'MEMBERSHIP_NOT_ON_SALE');
  const superQuote = await app.inject({ method: 'POST', url: '/v1/membership/quote',
    headers: { authorization: 'Bearer pilot' }, payload: { sku: 'SUPER_LIFETIME' } });
  assert.equal(superQuote.json().code, 'CLOUD_NOT_CONFIGURED');
});

test('MiMo shared key is handed only to lifetime members without refund debt, and every grant is recorded', async t => {
  const app = Fastify();
  t.after(() => app.close());
  const now = new Date();
  const members: Record<string, { expires: Date | null; debt: number }> = {
    lifetime: { expires: null, debt: 0 }, annual: { expires: new Date(Date.now() + 86400000), debt: 0 },
    indebted: { expires: null, debt: 60 }
  };
  let sharedKey: string | null = 'sk-operator-key';
  const grants: string[] = [];
  const dbFor = (user: string) => ({ query: async (sql: string) => {
    if (sql.includes('FROM membership_accounts')) {
      const member = members[user];
      return { rows: member ? [{ id: 'p', sku: member.expires ? 'ANNUAL' : 'LIFETIME', anchor_at: now,
        expires_at: member.expires, paid_months: 0, permanent_credit_points: '0', revision: 1 }] : [] };
    }
    if (sql.includes('FROM account_debts')) return { rows: [{ iap_debt_points: String(members[user]?.debt ?? 0) }] };
    if (sql.includes('FROM shared_provider_keys')) return { rows: sharedKey ? [{ api_key: sharedKey }] : [] };
    if (sql.includes('INSERT INTO shared_provider_key_grants')) { grants.push(user); return { rows: [] }; }
    throw new Error('unexpected query ' + sql);
  } }) as unknown as PoolClient;
  registerMembershipRoutes(app, {
    enabled: true, superEnabled: false,
    authenticate: async (req, reply) => { if (!req.headers.authorization) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers.authorization).slice(7),
    transaction: async work => work(dbFor(currentUser)), limit: async () => {}, account: async () => ({}), wallet: async () => ({})
  });
  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
    return reply.code(500).send({ code: 'UNEXPECTED' });
  });
  let currentUser = '';
  const fetchKey = (user: string) => { currentUser = user;
    return app.inject({ method: 'POST', url: '/v1/membership/mimo-key', headers: user ? { authorization: 'Bearer ' + user } : {} }); };
  assert.equal((await fetchKey('')).statusCode, 401);
  const granted = await fetchKey('lifetime');
  assert.equal(granted.statusCode, 200);
  assert.equal(granted.json().apiKey, 'sk-operator-key');
  assert.equal(granted.headers['cache-control'], 'no-store');
  for (const user of ['annual', 'indebted', 'nobody']) {
    const refused = await fetchKey(user);
    assert.equal(refused.statusCode, 403);
    assert.equal(refused.json().code, 'LIFETIME_MEMBERSHIP_REQUIRED');
  }
  sharedKey = null;
  assert.equal((await fetchKey('lifetime')).json().code, 'SHARED_KEY_UNAVAILABLE');
  assert.deepEqual(grants, ['lifetime'], 'only successful grants are recorded');
});

test('MiMo shared key route on the full schema (embedded PostgreSQL)', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort()) {
    await db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  }
  await db.exec(await readFile(new URL('029_shared_provider_keys.sql', migrations), 'utf8'));
  await db.exec('UPDATE membership_products SET sales_enabled=TRUE, sales_starts_at=NULL');
  const adapter = (connection: Pick<PGlite, 'query'>): MembershipDb => ({
    query: connection.query.bind(connection) as unknown as MembershipDb['query']
  });
  const tx = <T>(fn: (client: MembershipDb) => Promise<T>) => db.transaction(client => fn(adapter(client)));
  // The route checks membership against the real clock, so periods are bought against it too.
  const now = Date.now();
  async function user() {
    const id = randomUUID();
    await db.query('INSERT INTO app_users(id,huawei_open_id,created_at) VALUES ($1,$2,$3)', [id, id, new Date(now - 86400000)]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES ($1,10000,10000,0)', [id]);
    return id;
  }
  async function member(sku: MembershipSku) {
    const id = await user();
    const quote = await tx(c => quoteMembership(c, id, sku, now));
    await tx(c => purchaseMembership(c, id, quote.quoteId, randomUUID(), now));
    return id;
  }
  const app = Fastify();
  t.after(() => app.close());
  registerMembershipRoutes(app, {
    enabled: true, superEnabled: false,
    authenticate: async (req, reply) => { if (!req.headers.authorization) await reply.code(401).send({ code: 'UNAUTHORIZED' }); },
    userId: req => String(req.headers.authorization).slice(7),
    transaction: work => tx(client => work(client as unknown as PoolClient)),
    limit: async () => {}, account: async () => ({}), wallet: async () => ({})
  });
  app.setErrorHandler((error, _req, reply) => reply.code(error instanceof MembershipError ? error.statusCode : 500)
    .send({ code: error instanceof MembershipError ? error.code : 'UNEXPECTED' }));
  const fetchKey = (id: string) => app.inject({ method: 'POST', url: '/v1/membership/mimo-key',
    headers: { authorization: 'Bearer ' + id } });
  const lifetime = await member('LIFETIME');
  const superLifetime = await member('SUPER_LIFETIME');
  const nobody = await user();
  assert.equal((await fetchKey(lifetime)).json().code, 'SHARED_KEY_UNAVAILABLE');
  await db.query(`INSERT INTO shared_provider_keys(provider, api_key) VALUES ('mimo', 'sk-test-shared-key')`);
  for (let i = 0; i < 3; i++) assert.equal((await fetchKey(lifetime)).json().apiKey, 'sk-test-shared-key');
  assert.equal((await fetchKey(superLifetime)).json().apiKey, 'sk-test-shared-key');
  assert.equal((await fetchKey(nobody)).json().code, 'LIFETIME_MEMBERSHIP_REQUIRED');
  const grants = await db.query<{ grant_count: number }>(
    `SELECT grant_count FROM shared_provider_key_grants WHERE user_id=$1`, [lifetime]);
  assert.deepEqual(grants.rows.map(row => row.grant_count), [3]);
  await db.query(`UPDATE shared_provider_keys SET enabled=false WHERE provider='mimo'`);
  assert.equal((await fetchKey(lifetime)).json().code, 'SHARED_KEY_UNAVAILABLE');
});
