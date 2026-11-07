import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import Fastify from 'fastify';
import type { PoolClient } from 'pg';
import { registerMembershipRoutes } from './membershipRoutes.js';
import { MembershipError } from './membershipPolicy.js';
import type { MembershipDb } from './membershipService.js';
import { claimSuperTheme, SUPER_THEME_ID } from './superThemeService.js';
import { findRedeemableTheme, listPublishedThemes, themeOfferMatchesExpectation } from './themeCatalog.js';

test('exclusive annual theme claims enforce membership, idempotency and no point redemption', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const name of (await readdir(migrations)).filter(n => n.endsWith('.sql')).sort()) {
    await db.exec((await readFile(new URL(name,migrations),'utf8')).replace(/^VACUUM[^;]*;/gm,''));
  }
  const query = { query: db.query.bind(db) } as unknown as MembershipDb;
  const now = Date.parse('2028-02-29T15:20:00+08:00');
  const nextYear = Date.parse('2029-02-28T15:20:00+08:00');
  const tx = (id: string, requestId: string = randomUUID(), at = now, theme = SUPER_THEME_ID) =>
    db.transaction(client => claimSuperTheme(client as unknown as MembershipDb, id, theme, requestId, at));
  async function user(sku: string | null) {
    const id = randomUUID(), period = randomUUID();
    await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [id,id]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance) VALUES($1,1000,1000)', [id]);
    if (sku) {
      const permanent = sku.includes('LIFETIME');
      await db.query(`INSERT INTO membership_periods(id,user_id,sku,anchor_at,paid_months,expires_at)
        VALUES($1,$2,$3,$4,$5,$6)`,[period,id,sku,new Date(now-86400000),permanent?0:12,
        permanent?null:new Date(now+86400000)]);
      await db.query('INSERT INTO membership_accounts(user_id,period_id,revision) VALUES($1,$2,1)',[id,period]);
    }
    return id;
  }
  const owner = await user('SUPER_LIFETIME');
  await t.test('catalog marks claim-only; both old and new point clients are refused', async () => {
    const offer = (await listPublishedThemes(query)).find(x => x.themeId===SUPER_THEME_ID)!;
    assert.equal(offer.acquisition,'SUPER_CLAIM'); assert.equal(offer.pricePoints,0);
    assert.equal(await findRedeemableTheme(query,SUPER_THEME_ID),null);
    assert.equal(themeOfferMatchesExpectation(offer,0,365),false);
    assert.equal(themeOfferMatchesExpectation(offer,undefined,undefined),false);
    assert.equal((await db.query<{member_included:boolean}>('SELECT member_included FROM theme_catalog WHERE theme_id=$1',[SUPER_THEME_ID])).rows[0]!.member_included,false);
    assert(await findRedeemableTheme(query,'classic-blue'));
  });
  await t.test('free, monthly, annual and ordinary lifetime members cannot claim', async () => {
    for(const sku of [null,'MONTHLY','ANNUAL','LIFETIME']) {
      await assert.rejects(tx(await user(sku)),{code:'SUPER_THEME_REQUIRED'});
    }
  });
  const request = randomUUID();
  await t.test('super claim lasts a Beijing calendar year, including leap-day clamping', async () => {
    const claim = await tx(owner,request);
    assert.deepEqual(claim,{themeId:SUPER_THEME_ID,expiresAt:nextYear,duplicate:false});
    assert.equal(Number((await db.query<{balance:string}>('SELECT balance FROM point_wallets WHERE user_id=$1',[owner])).rows[0]!.balance),1000);
    assert.equal((await db.query('SELECT 1 FROM point_ledger WHERE user_id=$1',[owner])).rows.length,0);
  });
  let noOpRequest = '';
  await t.test('same and distinct requests during the year never extend the entitlement', async () => {
    assert.equal((await tx(owner,request,now+1000)).expiresAt,nextYear);
    noOpRequest=randomUUID();
    const repeated=await tx(owner,noOpRequest,nextYear-1);
    assert.equal(repeated.duplicate,true); assert.equal(repeated.expiresAt,nextYear);
    assert.equal((await db.query('SELECT 1 FROM theme_entitlements WHERE user_id=$1',[owner])).rows.length,1);
  });
  await t.test('expired request replay never renews; a fresh manual request grants one new year', async () => {
    assert.equal((await tx(owner,request,nextYear)).expiresAt,nextYear);
    assert.equal((await tx(owner,noOpRequest,nextYear)).expiresAt,nextYear);
    const renewal=await tx(owner,randomUUID(),nextYear);
    assert.equal(renewal.duplicate,false);
    assert.equal(renewal.expiresAt,Date.parse('2030-02-28T15:20:00+08:00'));
  });
  await t.test('refund debt denies claiming even with a previous request', async () => {
    await db.query('INSERT INTO account_debts(user_id,iap_debt_points) VALUES($1,1)',[owner]);
    await assert.rejects(tx(owner,request),{code:'SUPER_THEME_REQUIRED'});
    await db.query('DELETE FROM account_debts WHERE user_id=$1',[owner]);
  });
  await t.test('unpublished and malformed requests cannot create grants', async () => {
    await assert.rejects(tx(owner,''),{code:'INVALID_REQUEST_ID'});
    await assert.rejects(tx(owner,randomUUID(),now,'classic-blue'),{code:'THEME_NOT_FOUND'});
    await db.query('UPDATE theme_catalog SET enabled=FALSE WHERE theme_id=$1',[SUPER_THEME_ID]);
    await assert.rejects(tx(owner),{code:'THEME_NOT_FOUND'});
    await db.query('UPDATE theme_catalog SET enabled=TRUE WHERE theme_id=$1',[SUPER_THEME_ID]);
  });
  await t.test('each exclusive theme is claimed separately and never sold for points', async () => {
    const second = 'celestial-vault';
    const offer = (await listPublishedThemes(query)).find(x => x.themeId===second)!;
    assert.equal(offer.acquisition,'SUPER_CLAIM'); assert.equal(offer.pricePoints,0);
    assert.equal(await findRedeemableTheme(query,second),null);
    assert.equal(themeOfferMatchesExpectation(offer,0,365),false);
    const fresh = await user('SUPER_LIFETIME');
    await tx(fresh,randomUUID(),now);
    assert.equal((await db.query('SELECT 1 FROM theme_entitlements WHERE user_id=$1 AND theme_id=$2',[fresh,second])).rows.length,0);
    assert.deepEqual(await tx(fresh,randomUUID(),now,second),{themeId:second,expiresAt:nextYear,duplicate:false});
    assert.equal((await db.query('SELECT 1 FROM theme_entitlements WHERE user_id=$1',[fresh])).rows.length,2);
    await assert.rejects(tx(await user('LIFETIME'),randomUUID(),now,second),{code:'SUPER_THEME_REQUIRED'});
    // A request ID stays bound to the theme it first claimed.
    const shared = randomUUID();
    await tx(fresh,shared,now);
    await assert.rejects(tx(fresh,shared,now,second),{code:'REQUEST_CONFLICT'});
  });
  await t.test('rerunning migration preserves the already claimed year', async () => {
    const before = (await db.query('SELECT * FROM theme_entitlements WHERE user_id=$1',[owner])).rows;
    await db.exec(await readFile(new URL('023_super_exclusive_theme.sql',migrations),'utf8'));
    assert.deepEqual((await db.query('SELECT * FROM theme_entitlements WHERE user_id=$1',[owner])).rows,before);
  });
  await t.test('HTTP claim authenticates the owner and ignores forged membership/user fields', async () => {
    const app = Fastify(), outsider = await user(null), limited: string[] = [];
    await db.query('UPDATE membership_periods SET anchor_at=$1 WHERE user_id=$2', [new Date(Date.now()-86400000), owner]);
    registerMembershipRoutes(app, {
      enabled: true, superEnabled: true,
      authenticate: async (req, reply) => {
        if (!['Bearer owner','Bearer outsider'].includes(req.headers.authorization || '')) {
          await reply.code(401).send({ code: 'UNAUTHORIZED' });
        }
      },
      userId: req => req.headers.authorization === 'Bearer owner' ? owner : outsider,
      transaction: work => db.transaction(client => work(client as unknown as PoolClient)),
      limit: async id => { limited.push(id); }, account: async (_client, id) => ({ userId: id }), wallet: async () => ({})
    });
    app.setErrorHandler((error, _req, reply) => {
      if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
      return reply.code(500).send({ code: 'UNEXPECTED' });
    });
    try {
      const url = '/v1/membership/themes/obsidian-archive/claim';
      assert.equal((await app.inject({ method:'POST', url, payload:{requestId:randomUUID()} })).statusCode,401);
      const forged = await app.inject({ method:'POST', url, headers:{authorization:'Bearer outsider'},
        payload:{requestId:randomUUID(),userId:owner,sku:'SUPER_LIFETIME'} });
      assert.equal(forged.statusCode,403);
      assert.equal(forged.json().code,'SUPER_THEME_REQUIRED');
      const success = await app.inject({ method:'POST', url, headers:{authorization:'Bearer owner'},
        payload:{requestId:randomUUID(),userId:outsider} });
      assert.equal(success.statusCode,200);
      assert.equal(success.json().account.userId,owner);
      assert.deepEqual(limited,[outsider,owner]);
      assert.equal((await db.query('SELECT 1 FROM theme_entitlements WHERE user_id=$1',[outsider])).rows.length,0);
    } finally { await app.close(); }
  });
  await t.test('SELECT-only administrator-owned catalog supports claims without elevated application permissions', async () => {
    const restrictedOwner = await user('SUPER_LIFETIME');
    await db.exec(`CREATE ROLE qingye NOSUPERUSER;
      GRANT USAGE ON SCHEMA public TO qingye;
      GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO qingye;
      REVOKE ALL ON theme_catalog,membership_theme_claims FROM qingye;
      GRANT SELECT ON theme_catalog TO qingye;
      GRANT SELECT,INSERT ON membership_theme_claims TO qingye;`);
    const restrictedClaim = (requestId: string, at: number) => db.transaction(async client => {
      await client.query('SET LOCAL ROLE qingye');
      return claimSuperTheme(client as unknown as MembershipDb, restrictedOwner, SUPER_THEME_ID, requestId, at);
    });
    // Confirm the fixture reproduces the production failure of the old FOR SHARE query.
    await assert.rejects(db.transaction(async client => {
      await client.query('SET LOCAL ROLE qingye');
      await client.query('SELECT 1 FROM theme_catalog FOR SHARE');
    }), { code: '42501' });
    const requestId = randomUUID();
    const first = await restrictedClaim(requestId, now);
    assert.equal(first.expiresAt, nextYear);
    assert.equal((await restrictedClaim(requestId, now+1)).expiresAt, nextYear);
    assert.equal((await restrictedClaim(randomUUID(), now+2)).expiresAt, nextYear);
    assert.equal((await restrictedClaim(randomUUID(), nextYear)).expiresAt, Date.parse('2030-02-28T15:20:00+08:00'));
    assert.equal((await db.query<{ allowed: boolean }>("SELECT has_table_privilege('qingye','theme_catalog','UPDATE') AS allowed")).rows[0]!.allowed, false);
  });
});
