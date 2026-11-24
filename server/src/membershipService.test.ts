import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import {
  claimMembershipGift, MembershipDb, membershipSnapshot, purchaseMembership,
  quoteMembership, readMembership, membershipCatalog
} from './membershipService.js';
import { parseMembershipSalesPilot } from './membershipSales.js';
import { membershipAnniversary, MembershipError, MembershipSku } from './membershipPolicy.js';

test('membership SQL transactions and quota lifecycle (embedded PostgreSQL)', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort()) {
    const sql = await readFile(new URL(file, migrations), 'utf8');
    // Operational VACUUM in older migrations must run outside PGlite's multi-statement transaction.
    await db.exec(sql.replace(/^VACUUM[^;]*;/gm, ''));
  }
  // Rerunning the new migration cannot accidentally enable sales or reset data.
  await db.exec(await readFile(new URL('016_memberships.sql', migrations), 'utf8'));
  // These tests run in 2028, after the scheduled 2026 launch; exercise manual opening unless a test sets a start.
  await db.exec('UPDATE membership_products SET sales_starts_at=NULL');
  const adapter = (connection: Pick<PGlite, 'query'>): MembershipDb => ({
    query: connection.query.bind(connection) as unknown as MembershipDb['query']
  });
  const tx = <T>(fn: (client: MembershipDb) => Promise<T>) => db.transaction(client => fn(adapter(client)));
  const query = adapter(db);
  const now = Date.parse('2028-01-31T00:15:00+08:00');
  async function user(paid = 10000, promo = 300) {
    const id = randomUUID();
    await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES ($1,$2)', [id, id]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES ($1,$2,$3,$4)',
      [id, paid + promo, paid, promo]);
    return id;
  }
  async function buy(id: string, sku: MembershipSku, at = now) {
    const quote = await tx(client => quoteMembership(client, id, sku, at));
    const result = await tx(client => purchaseMembership(client, id, quote.quoteId, randomUUID(), at));
    return { quote, result };
  }
  const rejectedCode = (code: string) => (error: unknown) => error instanceof MembershipError && error.code === code;

  await t.test('new products are not for sale until explicitly enabled', async () => {
    const id = await user();
    await assert.rejects(tx(client => quoteMembership(client, id, 'MONTHLY', now)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
    await db.exec('UPDATE membership_products SET sales_enabled=TRUE');
  });
  await t.test('promotional points cannot pay; failure rolls back wallet and membership', async () => {
    const id = await user(59, 10000);
    const quote = await tx(client => quoteMembership(client, id, 'MONTHLY', now));
    await assert.rejects(tx(client => purchaseMembership(client, id, quote.quoteId, 'insufficient', now)),
      rejectedCode('INSUFFICIENT_PAID_POINTS'));
    assert.equal(await readMembership(query, id), null);
    const wallet = await db.query<{ paid_balance: number; promo_balance: number }>('SELECT paid_balance,promo_balance FROM point_wallets WHERE user_id=$1', [id]);
    assert.equal(Number(wallet.rows[0]!.paid_balance), 59);
    assert.equal(Number(wallet.rows[0]!.promo_balance), 10000);
  });
  await t.test('pilot isolates account/SKU, rechecks expiry and revocation, and preserves paid retries', async () => {
    await db.exec('UPDATE membership_products SET sales_enabled=FALSE');
    try {
      const id = await user();
      const other = await user();
      const pilot = parseMembershipSalesPilot(id, 'MONTHLY', new Date(now + 60000).toISOString());
      assert.ok((await membershipCatalog(query, undefined, now, pilot)).every(p => !p.salesEnabled));
      assert.ok((await membershipCatalog(query, other, now, pilot)).every(p => !p.salesEnabled));
      assert.deepEqual((await membershipCatalog(query, id, now, pilot)).filter(p => p.salesEnabled).map(p => p.sku), ['MONTHLY']);
      await assert.rejects(tx(c => quoteMembership(c, other, 'MONTHLY', now, pilot)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
      await assert.rejects(tx(c => quoteMembership(c, id, 'ANNUAL', now, pilot)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
      const quote = await tx(c => quoteMembership(c, id, 'MONTHLY', now, pilot));
      await assert.rejects(tx(c => purchaseMembership(c, id, quote.quoteId, 'pilot', now)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
      await assert.rejects(tx(c => purchaseMembership(c, id, quote.quoteId, 'pilot', now + 60000, pilot)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
      assert.equal(await readMembership(query, id), null);
      const order = await tx(c => purchaseMembership(c, id, quote.quoteId, 'pilot', now + 1000, pilot));
      const retry = await tx(c => purchaseMembership(c, id, quote.quoteId, 'pilot', now + 60000));
      assert.equal(retry.orderId, order.orderId);
      assert.equal(retry.duplicate, true);
      const balance = await db.query<{ paid_balance: number }>('SELECT paid_balance FROM point_wallets WHERE user_id=$1', [id]);
      assert.equal(Number(balance.rows[0]!.paid_balance), 9940);
      assert.ok((await membershipCatalog(query, id, now + 60000, pilot)).every(p => !p.salesEnabled));
    } finally { await db.exec('UPDATE membership_products SET sales_enabled=TRUE'); }
  });
  await t.test('scheduled start opens sales; a promotion prices quotes, orders and later upgrade credit', async () => {
    await db.exec('UPDATE membership_products SET sales_enabled=FALSE');
    try {
      await db.query('UPDATE membership_products SET sales_starts_at=$1', [new Date(now + 3600000)]);
      await db.query(`INSERT INTO membership_promotions(id,sku,price_points,label,starts_at,ends_at)
        VALUES ('test-half','LIFETIME',645,'首发半价',$1,$2)`, [new Date(now), new Date(now + 7200000)]);
      const id = await user();
      await assert.rejects(tx(c => quoteMembership(c, id, 'LIFETIME', now)), rejectedCode('MEMBERSHIP_NOT_ON_SALE'));
      const opening = now + 3600000;
      const catalog = await membershipCatalog(query, id, opening);
      const lifetime = catalog.find(p => p.sku === 'LIFETIME')!;
      assert.ok(catalog.every(p => p.salesEnabled));
      assert.equal(lifetime.pricePoints, 645);
      assert.equal(lifetime.points, 1290);
      assert.equal(lifetime.promotion!.endsAt, now + 7200000);
      const announced = (await membershipCatalog(query, id, now - 1000)).find(p => p.sku === 'LIFETIME')!;
      assert.equal(announced.pricePoints, 1290); // Not yet started: still the regular price,
      assert.equal(announced.promotion!.pricePoints, 645); // but the coming launch price is announced.
      assert.equal(catalog.find(p => p.sku === 'ANNUAL')!.pricePoints, 480);
      // A quote issued just before the promotion ends cannot be paid at the promotion price afterwards.
      const late = await tx(c => quoteMembership(c, id, 'LIFETIME', now + 7200000 - 1000));
      assert.equal(late.expiresAt, now + 7200000);
      await assert.rejects(tx(c => purchaseMembership(c, id, late.quoteId, 'late', now + 7200000)),
        rejectedCode('MEMBERSHIP_QUOTE_EXPIRED'));
      const { quote } = await buy(id, 'LIFETIME', opening);
      assert.equal(quote.listPoints, 645);
      assert.equal(quote.payablePoints, 645);
      const order = await db.query<{ list_points: string; promotion_id: string }>(
        'SELECT list_points,promotion_id FROM membership_orders WHERE user_id=$1', [id]);
      assert.equal(Number(order.rows[0]!.list_points), 645);
      assert.equal(order.rows[0]!.promotion_id, 'test-half');
      // After the promotion, upgrading credits what the permanent membership actually cost.
      const upgrade = await tx(c => quoteMembership(c, id, 'SUPER_LIFETIME', now + 7200000));
      assert.equal(upgrade.creditPoints, 645);
      assert.equal(upgrade.payablePoints, 2490 - 645);
    } finally {
      await db.exec('UPDATE membership_products SET sales_enabled=TRUE, sales_starts_at=NULL');
    }
  });
  await t.test('duplicate purchase and duplicate quote charge only once, even after quote expiry', async () => {
    const id = await user();
    const quote = await tx(client => quoteMembership(client, id, 'MONTHLY', now));
    const order = await tx(client => purchaseMembership(client, id, quote.quoteId, 'once', now));
    const retry = await tx(client => purchaseMembership(client, id, quote.quoteId, 'once', now + 3600000));
    const newId = await tx(client => purchaseMembership(client, id, quote.quoteId, 'new-id', now + 3600000));
    assert.equal(retry.orderId, order.orderId);
    assert.equal(newId.orderId, order.orderId);
    const wallet = await db.query<{ paid_balance: number; promo_balance: number }>('SELECT paid_balance,promo_balance FROM point_wallets WHERE user_id=$1', [id]);
    assert.equal(Number(wallet.rows[0]!.paid_balance), 9940);
    assert.equal(Number(wallet.rows[0]!.promo_balance), 300);
  });
  await t.test('old quotes cannot overwrite a renewal; cross-account quote cannot spend', async () => {
    const id = await user();
    const other = await user();
    const quote = await tx(client => quoteMembership(client, id, 'ANNUAL', now));
    await assert.rejects(tx(client => purchaseMembership(client, other, quote.quoteId, 'cross', now)), rejectedCode('MEMBERSHIP_QUOTE_EXPIRED'));
    await buy(id, 'MONTHLY');
    await assert.rejects(tx(client => purchaseMembership(client, id, quote.quoteId, 'stale', now)), rejectedCode('MEMBERSHIP_OFFER_CHANGED'));
  });
  await t.test('gifts are exclusive, idempotent, extend on renewal and remain in their own period', async () => {
    const id = await user();
    await buy(id, 'ANNUAL');
    const first = await tx(client => claimMembershipGift(client, id, 'STANDARD', now));
    const duplicate = await tx(client => claimMembershipGift(client, id, 'STANDARD', now));
    assert.equal(first.chars, 5000);
    assert.equal(duplicate.duplicate, true);
    await assert.rejects(tx(client => claimMembershipGift(client, id, 'PREMIUM', now)), rejectedCode('MEMBERSHIP_GIFT_ALREADY_CLAIMED'));
    await buy(id, 'ANNUAL', now + 1000);
    let grants = await db.query<{ expires_at: Date; remaining_chars: number }>(
      "SELECT expires_at,remaining_chars FROM tts_quota_grants WHERE user_id=$1 AND source='MEMBERSHIP'", [id]);
    assert.equal(grants.rows[0]!.expires_at.getTime(), membershipAnniversary(now, 24));
    await tx(client => claimMembershipGift(client, id, 'PREMIUM', membershipAnniversary(now, 1)));
    const oldExpiry = membershipAnniversary(now, 24);
    await buy(id, 'MONTHLY', oldExpiry);
    grants = await db.query<{ expires_at: Date; remaining_chars: number }>(
      "SELECT expires_at,remaining_chars FROM tts_quota_grants WHERE user_id=$1 AND source='MEMBERSHIP'", [id]);
    assert.ok(grants.rows.every(grant => grant.expires_at.getTime() === oldExpiry));
    assert.equal((await membershipSnapshot(query, id, oldExpiry)).claim, null);
  });
  await t.test('monthly terms carry no gift, even when they extend an annual period', async () => {
    const monthly = await user();
    await buy(monthly, 'MONTHLY');
    const snapshot = await membershipSnapshot(query, monthly, now);
    assert.equal(snapshot.tierSku, 'MONTHLY');
    assert.equal(snapshot.benefits.standardGiftChars, 0);
    await assert.rejects(tx(c => claimMembershipGift(c, monthly, 'STANDARD', now)), rejectedCode('MEMBERSHIP_GIFT_NOT_INCLUDED'));

    const annual = await user();
    await buy(annual, 'ANNUAL');
    await buy(annual, 'MONTHLY', now + 1000); // The period's latest SKU becomes MONTHLY.
    assert.equal((await readMembership(query, annual))!.sku, 'MONTHLY');
    const inAnnual = await membershipSnapshot(query, annual, membershipAnniversary(now, 11));
    assert.equal(inAnnual.tierSku, 'ANNUAL');
    assert.equal(inAnnual.benefits.standardGiftChars, 5000);
    await tx(c => claimMembershipGift(c, annual, 'STANDARD', membershipAnniversary(now, 11)));
    const inMonthly = await membershipSnapshot(query, annual, membershipAnniversary(now, 12));
    assert.equal(inMonthly.tierSku, 'MONTHLY');
    assert.equal(inMonthly.benefits.premiumGiftChars, 0);
    await assert.rejects(tx(c => claimMembershipGift(c, annual, 'PREMIUM', membershipAnniversary(now, 12))),
      rejectedCode('MEMBERSHIP_GIFT_NOT_INCLUDED'));
  });
  await t.test('every product and voice tier issues the exact gift or writes nothing when denied', async () => {
    const amounts: Record<MembershipSku, [number, number]> = {
      MONTHLY: [0, 0], ANNUAL: [5000, 2500], LIFETIME: [8000, 4000], SUPER_LIFETIME: [12000, 6000]
    };
    for (const sku of Object.keys(amounts) as MembershipSku[]) {
      for (const tier of ['STANDARD', 'PREMIUM'] as const) {
        const id = await user();
        await buy(id, sku);
        const chars = amounts[sku][tier === 'STANDARD' ? 0 : 1];
        if (chars === 0) {
          await assert.rejects(tx(c => claimMembershipGift(c, id, tier, now)), rejectedCode('MEMBERSHIP_GIFT_NOT_INCLUDED'));
        } else {
          assert.deepEqual(await tx(c => claimMembershipGift(c, id, tier, now)), { tier, chars, duplicate: false });
          assert.deepEqual(await tx(c => claimMembershipGift(c, id, tier, now)), { tier, chars, duplicate: true });
          const grant = await db.query<{ total_chars: number; remaining_chars: number }>(
            'SELECT total_chars,remaining_chars FROM tts_quota_grants WHERE user_id=$1', [id]);
          assert.equal(Number(grant.rows[0]!.total_chars), chars);
          assert.equal(Number(grant.rows[0]!.remaining_chars), chars);
        }
        for (const table of ['membership_gift_claims', 'tts_quota_grants', 'tts_quota_ledger']) {
          const rows = await db.query(`SELECT * FROM ${table} WHERE user_id=$1`, [id]);
          assert.equal(rows.rows.length, chars > 0 ? 1 : 0, `${sku}/${tier}/${table}`);
        }
      }
    }
  });
  await t.test('a prepaid annual term counts as annual immediately, while the monthly term still runs', async () => {
    const id = await user();
    await buy(id, 'MONTHLY');
    const monthlyEnd = (await readMembership(query, id))!.expiresAt!;
    await buy(id, 'ANNUAL', now + 1000);
    assert.equal((await readMembership(query, id))!.sku, 'ANNUAL');
    const before = await membershipSnapshot(query, id, now + 2000);
    assert.equal(before.tierSku, 'ANNUAL');
    assert.equal(before.benefits.premiumGiftChars, 2500);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'PREMIUM', now + 2000))).chars, 2500);
    const after = await membershipSnapshot(query, id, monthlyEnd);
    assert.equal(after.tierSku, 'ANNUAL');
    await assert.rejects(tx(c => claimMembershipGift(c, id, 'STANDARD', after.state!.expiresAt!)),
      rejectedCode('MEMBERSHIP_INACTIVE'));
  });
  await t.test('free users and invalid voice tiers cannot create gift records', async () => {
    const id = await user();
    await assert.rejects(tx(c => claimMembershipGift(c, id, 'STANDARD', now)), rejectedCode('MEMBERSHIP_INACTIVE'));
    await assert.rejects(tx(c => claimMembershipGift(c, id, 'INVALID' as 'STANDARD', now)), rejectedCode('INVALID_TTS_TIER'));
    for (const table of ['membership_gift_claims', 'tts_quota_grants', 'tts_quota_ledger']) {
      assert.equal((await db.query(`SELECT * FROM ${table} WHERE user_id=$1`, [id])).rows.length, 0);
    }
  });
  await t.test('lifetime upgrade makes existing gifts permanent without granting twice', async () => {
    const id = await user();
    await buy(id, 'ANNUAL');
    await tx(client => claimMembershipGift(client, id, 'STANDARD', now));
    await buy(id, 'SUPER_LIFETIME', now + 1000);
    const repeat = await tx(client => claimMembershipGift(client, id, 'STANDARD', now + 2000));
    assert.equal(repeat.chars, 5000);
    const grants = await db.query<{ forever: boolean }>(
      "SELECT NOT isfinite(expires_at) AS forever FROM tts_quota_grants WHERE user_id=$1 AND source='MEMBERSHIP'", [id]);
    assert.equal(grants.rows[0]!.forever, true);
    const next = await tx(client => claimMembershipGift(client, id, 'PREMIUM', membershipAnniversary(now, 1)));
    assert.equal(next.chars, 6000);
    const third = await tx(client => claimMembershipGift(client, id, 'STANDARD', membershipAnniversary(now, 2)));
    assert.equal(third.chars, 12000);
  });
  await t.test('first purchase starts at payment; pending quotes expire before an old membership does', async () => {
    const id = await user();
    const quote = await tx(client => quoteMembership(client, id, 'MONTHLY', now));
    await tx(client => purchaseMembership(client, id, quote.quoteId, 'delayed', now + 60000));
    const state = (await readMembership(query, id))!;
    assert.equal(state.anchorAt, now + 60000);
    const renewal = await tx(client => quoteMembership(client, id, 'ANNUAL', state.expiresAt! - 1000));
    await assert.rejects(tx(client => purchaseMembership(client, id, renewal.quoteId, 'late', state.expiresAt!)), rejectedCode('MEMBERSHIP_QUOTE_EXPIRED'));
  });
  await t.test('calendar boundary resets gifts and preserves balances and legacy cycle metadata', async () => {
    const id = await user();
    await buy(id, 'LIFETIME');
    const first = await tx(c => claimMembershipGift(c, id, 'STANDARD', now));
    assert.equal(first.chars, 8000);
    const feb = Date.parse('2028-02-01T00:00:00+08:00');
    const before = await membershipSnapshot(query, id, feb - 1);
    assert.equal(before.giftCycle!.startsAt, Date.parse('2028-01-01T00:00:00+08:00'));
    assert.equal(before.giftCycle!.endsAt, feb);
    assert.equal(before.claim!.chars, 8000);
    const after = await membershipSnapshot(query, id, feb);
    assert.equal(after.claim, null);
    assert.equal(after.cycle!.index, before.cycle!.index); // Legacy anniversary metadata remains stable.
    assert.equal(after.giftCycle!.index, before.giftCycle!.index + 1);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'STANDARD', feb))).chars, 8000);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'STANDARD', feb + 1))).duplicate, true);
    await assert.rejects(tx(c => claimMembershipGift(c, id, 'PREMIUM', feb + 1)), rejectedCode('MEMBERSHIP_GIFT_ALREADY_CLAIMED'));
    const balance = await db.query<{ chars: string; forever: boolean }>(
      `SELECT sum(remaining_chars) AS chars, bool_and(NOT isfinite(expires_at)) AS forever
       FROM tts_quota_grants WHERE user_id=$1`, [id]);
    assert.equal(Number(balance.rows[0]!.chars), 16000);
    assert.equal(balance.rows[0]!.forever, true);
  });
  await t.test('a new period in the same calendar month cannot collect again or revive old grants', async () => {
    const id = await user();
    const start = Date.parse('2027-01-15T10:00:00+08:00');
    await buy(id, 'ANNUAL', start);
    const old = (await readMembership(query, id))!;
    const claimAt = Date.parse('2028-01-10T10:00:00+08:00');
    await tx(c => claimMembershipGift(c, id, 'STANDARD', claimAt));
    await buy(id, 'LIFETIME', old.expiresAt!);
    assert.notEqual((await readMembership(query, id))!.periodId, old.periodId);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'STANDARD', old.expiresAt!))).duplicate, true);
    const snapshot = await membershipSnapshot(query, id, old.expiresAt!);
    assert.equal(snapshot.claim!.chars, 5000);
    assert.equal(snapshot.benefits.standardGiftChars, 8000);
    const grants = await db.query<{ expires_at: Date }>('SELECT expires_at FROM tts_quota_grants WHERE user_id=$1', [id]);
    assert.equal(grants.rows.length, 1);
    assert.equal(grants.rows[0]!.expires_at.getTime(), old.expiresAt);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'PREMIUM', Date.parse('2028-02-01T00:00:00+08:00')))).chars, 4000);
  });
  await t.test('legacy claims use their actual Beijing claim month, with no duplicate grant at rollout', async () => {
    const id = await user();
    await buy(id, 'SUPER_LIFETIME');
    await tx(c => claimMembershipGift(c, id, 'STANDARD', now));
    // Recreate a pre-rollout anniversary claim, retaining the actual claim date and older amount.
    await db.query('UPDATE membership_gift_claims SET gift_month=NULL,cycle_index=0,chars=3000 WHERE user_id=$1', [id]);
    await db.query('UPDATE tts_quota_grants SET total_chars=3000,remaining_chars=3000 WHERE user_id=$1', [id]);
    await db.query('UPDATE tts_quota_ledger SET delta_chars=3000,balance_after=3000 WHERE user_id=$1', [id]);
    // The additive migration is safe to rerun with both historical and current records present.
    await db.exec(await readFile(new URL('021_membership_calendar_gifts.sql', migrations), 'utf8'));
    assert.equal((await membershipSnapshot(query, id, now)).claim!.chars, 3000);
    assert.deepEqual(await tx(c => claimMembershipGift(c, id, 'STANDARD', now)), {tier: 'STANDARD', chars: 3000, duplicate: true});
    await assert.rejects(tx(c => claimMembershipGift(c, id, 'PREMIUM', now)), rejectedCode('MEMBERSHIP_GIFT_ALREADY_CLAIMED'));
    const feb = Date.parse('2028-02-01T00:00:00+08:00');
    assert.equal((await membershipSnapshot(query, id, feb)).claim, null);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'PREMIUM', feb))).chars, 6000);
    assert.equal((await db.query('SELECT * FROM tts_quota_grants WHERE user_id=$1', [id])).rows.length, 2);
    // A mistaken second insert in another period is also rejected by the unique monthly key.
    await assert.rejects(db.query(`INSERT INTO membership_gift_claims
      (period_id,cycle_index,user_id,tier,chars,quota_grant_id,gift_month)
      SELECT period_id,cycle_index+1,user_id,tier,chars,quota_grant_id,gift_month
      FROM membership_gift_claims WHERE user_id=$1 AND gift_month IS NOT NULL`, [id]), /duplicate key/);
  });
  await t.test('refund debt suspends paid membership and claims without deleting entitlement', async () => {
    const id = await user();
    await buy(id, 'LIFETIME');
    await db.query('INSERT INTO account_debts(user_id,iap_debt_points) VALUES ($1,10)', [id]);
    const snapshot = await membershipSnapshot(query, id, now);
    assert.equal(snapshot.active, false);
    assert.equal(snapshot.restricted, true);
    assert.equal(snapshot.benefits.memberThemes, false);
    assert.equal(snapshot.benefits.animatedAvatar, false);
    assert.equal(snapshot.benefits.ttsPriority, false);
    assert.equal(snapshot.benefits.standardGiftChars, 0);
    assert.equal(snapshot.benefits.premiumGiftChars, 0);
    assert.equal(snapshot.claim, null);
    await assert.rejects(tx(client => claimMembershipGift(client, id, 'STANDARD', now)), rejectedCode('ACCOUNT_PAYMENT_RESTRICTED'));
    await db.query('UPDATE account_debts SET iap_debt_points=0 WHERE user_id=$1', [id]);
    assert.equal((await membershipSnapshot(query, id, now)).benefits.animatedAvatar, true);
    assert.equal((await tx(c => claimMembershipGift(c, id, 'STANDARD', now))).chars, 8000);
  });
  await t.test('icyn revoke script preserves points/history, expires only test gift and refuses paid membership', async () => {
    const id = 'd105489a-3d17-4f18-af36-7a15e5e1b3ae';
    const period = '10537fff-4a2e-4663-93fd-7b2f7f4c24ff';
    await db.query("INSERT INTO app_users(id,huawei_open_id,display_name) VALUES ($1,$2,'icyn')", [id, id]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES ($1,7196,6896,300)', [id]);
    await db.query(`INSERT INTO membership_periods(id,user_id,sku,anchor_at,paid_months,permanent_credit_points)
      VALUES ($1,$2,'SUPER_LIFETIME',now()-interval '1 minute',0,0)`, [period, id]);
    await db.query('INSERT INTO membership_accounts(user_id,period_id,revision) VALUES ($1,$2,1)', [id, period]);
    await tx(c => claimMembershipGift(c, id, 'STANDARD'));
    const before = await db.query('SELECT * FROM point_wallets WHERE user_id=$1', [id]);
    const script = await readFile(new URL('../scripts/revoke-icyn-test-membership.sql', import.meta.url), 'utf8');
    await db.exec(script);
    await db.exec(script); // safe retry before any actual purchase
    assert.equal(await readMembership(query, id), null);
    assert.deepEqual((await db.query('SELECT * FROM point_wallets WHERE user_id=$1', [id])).rows, before.rows);
    assert.equal((await db.query('SELECT * FROM membership_gift_claims WHERE period_id=$1', [period])).rows.length, 1);
    assert.equal((await db.query('SELECT * FROM membership_periods WHERE id=$1', [period])).rows.length, 1);
    assert.equal((await db.query('SELECT * FROM tts_quota_grants WHERE membership_period_id=$1 AND expires_at>now()', [period])).rows.length, 0);
    await buy(id, 'MONTHLY');
    assert.notEqual((await readMembership(query, id))!.periodId, period);
    await assert.rejects(db.exec(script), /already has a purchase/);
    await db.exec('ROLLBACK');
    assert.equal((await readMembership(query, id))!.sku, 'MONTHLY');
  });
});
