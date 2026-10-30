import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import {
  CLOUD_BASE_QUOTA_BYTES, MembershipDb, cloudQuotaBytes, membershipSnapshot, purchaseMembership, quoteMembership
} from './membershipService.js';
import { MembershipError, MembershipSku, membershipCouponPoints } from './membershipPolicy.js';
import {
  checkVerification, drawLottery, lotteryState, setSuperChoice, startVerification, stripVerificationCode
} from './lotteryService.js';
import { registerLotteryRoutes } from './lotteryRoutes.js';

test('verification codes are removed from nicknames without leaving stray spaces', () => {
  assert.equal(stripVerificationCode('阿青 7KQ3XM', '7KQ3XM'), '阿青');
  assert.equal(stripVerificationCode('阿7kq3xm青', '7KQ3XM'), '阿 青');
  assert.equal(stripVerificationCode('7KQ3XM', '7KQ3XM'), '华为用户');
  assert.equal(stripVerificationCode('  A  7KQ3XM  B ', '7KQ3XM'), 'A B');
});

test('coupon points cover the SKU only, at most half of what is payable and never all of it', () => {
  const discounts = { LIFETIME: 100, SUPER_LIFETIME: 600 };
  assert.equal(membershipCouponPoints(discounts, 'MONTHLY', 60), 0);
  assert.equal(membershipCouponPoints(discounts, 'LIFETIME', 645), 100);
  assert.equal(membershipCouponPoints(discounts, 'SUPER_LIFETIME', 1245), 600);
  // Upgrading a half-price lifetime member leaves 600 payable; the coupon may take only half.
  assert.equal(membershipCouponPoints(discounts, 'SUPER_LIFETIME', 600), 300);
  assert.equal(membershipCouponPoints(discounts, 'LIFETIME', 1), 0);
  assert.equal(membershipCouponPoints({ LIFETIME: -5 }, 'LIFETIME', 645), 0);
  assert.equal(membershipCouponPoints(null, 'LIFETIME', 645), 0);
});

test('lottery, coupons and campaign cloud quota (embedded PostgreSQL)', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort()) {
    const sql = await readFile(new URL(file, migrations), 'utf8');
    await db.exec(sql.replace(/^VACUUM[^;]*;/gm, ''));
  }
  // Rerunning the lottery migrations keeps data and settings.
  await db.exec(await readFile(new URL('026_lottery_coupons.sql', migrations), 'utf8'));
  await db.exec(await readFile(new URL('027_double11_lottery.sql', migrations), 'utf8'));
  await db.exec('UPDATE membership_products SET sales_enabled=TRUE, sales_starts_at=NULL');
  const adapter = (connection: Pick<PGlite, 'query'>): MembershipDb => ({
    query: connection.query.bind(connection) as unknown as MembershipDb['query']
  });
  const tx = <T>(fn: (client: MembershipDb) => Promise<T>) => db.transaction(client => fn(adapter(client)));
  const query = adapter(db);
  const rejectedCode = (code: string) => (error: unknown) => error instanceof MembershipError && error.code === code;

  // Promotions from the launch migration ended in 2026; this campaign runs in 2028.
  const now = Date.parse('2028-03-10T12:00:00+08:00');
  const campaign = 'test-2028';
  await db.query(`INSERT INTO lottery_campaigns(id,title,starts_at,ends_at,registered_before,enabled,super_no_coupon_quota_bytes)
    VALUES ($1,'测试抽奖',$2,$3,$4,true,5368709120)`,
  [campaign, new Date(now - 86400000), new Date(now + 86400000), new Date(now)]);
  await db.query(`INSERT INTO lottery_prizes(id,campaign_id,label,weight,stock,discounts,is_fallback,sort_order) VALUES
    ('t-grand',$1,'特等奖',1,1,'{"LIFETIME":300,"SUPER_LIFETIME":600}',false,1),
    ('t-lucky',$1,'幸运奖',9,NULL,'{"LIFETIME":30,"SUPER_LIFETIME":60}',true,2)`, [campaign]);

  async function user(paid = 10000, createdAt = new Date(now - 86400000)) {
    const id = randomUUID();
    await db.query('INSERT INTO app_users(id,huawei_open_id,display_name,created_at) VALUES ($1,$2,$3,$4)',
      [id, id, '读者', createdAt]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance,promo_balance) VALUES ($1,$2,$2,0)', [id, paid]);
    return id;
  }
  const first = () => 0; // always the first weighted ticket: the grand prize
  const last = (max: number) => max - 1; // always the fallback
  async function buy(id: string, sku: MembershipSku, at = now) {
    const quote = await tx(c => quoteMembership(c, id, sku, at));
    const order = await tx(c => purchaseMembership(c, id, quote.quoteId, randomUUID(), at));
    return { quote, order };
  }

  await t.test('a nickname changed after the code was issued binds the browser, once', async () => {
    const id = await user();
    const started = Date.now();
    const verification = await tx(c => startVerification(c, '127.0.0.1', started));
    assert.match(verification.code, /^[2-9A-HJKMNP-Z]{6}$/);
    assert.deepEqual(await tx(c => checkVerification(c, verification.token, started)),
      { verified: false, expiresAt: verification.expiresAt });
    // An old nickname that happens to contain the code does not count.
    const stale = await user();
    await db.query('UPDATE app_users SET display_name=$2, updated_at=$3 WHERE id=$1',
      [stale, '旧' + verification.code, new Date(started - 60000)]);
    assert.equal((await tx(c => checkVerification(c, verification.token, started))).verified, false);
    await db.query('UPDATE app_users SET display_name=$2, profile_customized=TRUE, updated_at=now() WHERE id=$1',
      [id, '读者 ' + verification.code.toLowerCase()]);
    const result = await tx(c => checkVerification(c, verification.token, started));
    assert.equal(result.verified, true);
    assert.ok(result.verified && result.userId === id && result.displayName === '读者');
    const name = await db.query<{ display_name: string }>('SELECT display_name FROM app_users WHERE id=$1', [id]);
    assert.equal(name.rows[0]!.display_name, '读者');
    await assert.rejects(tx(c => checkVerification(c, verification.token, started)), rejectedCode('LOTTERY_VERIFY_EXPIRED'));
  });

  await t.test('expired codes and unknown tokens are refused', async () => {
    const started = Date.now();
    const verification = await tx(c => startVerification(c, '127.0.0.1', started));
    await assert.rejects(tx(c => checkVerification(c, verification.token, verification.expiresAt)),
      rejectedCode('LOTTERY_VERIFY_EXPIRED'));
    await assert.rejects(tx(c => checkVerification(c, 'not-a-token', started)), rejectedCode('LOTTERY_VERIFY_EXPIRED'));
  });

  await t.test('one draw per account; a sold-out prize falls back; late registrants are refused', async () => {
    const a = await user();
    const b = await user();
    const drawn = await tx(c => drawLottery(c, campaign, a, '1.1.1.1', now, first));
    assert.equal(drawn.duplicate, false);
    assert.equal(drawn.draw.prizeId, 't-grand');
    const again = await tx(c => drawLottery(c, campaign, a, '1.1.1.1', now, last));
    assert.equal(again.duplicate, true);
    assert.equal(again.draw.coupon.id, drawn.draw.coupon.id);
    // The only grand prize is gone, so the same lucky ticket yields the fallback.
    assert.equal((await tx(c => drawLottery(c, campaign, b, '1.1.1.1', now, first))).draw.prizeId, 't-lucky');
    const issued = await db.query<{ id: string; issued: number }>(
      'SELECT id, issued FROM lottery_prizes WHERE campaign_id=$1 ORDER BY sort_order', [campaign]);
    assert.deepEqual(issued.rows.map(r => [r.id, Number(r.issued)]), [['t-grand', 1], ['t-lucky', 1]]);
    const late = await user(0, new Date(now));
    await assert.rejects(tx(c => drawLottery(c, campaign, late, '1.1.1.1', now, first)), rejectedCode('LOTTERY_INELIGIBLE'));
    const state = await tx(c => lotteryState(c, campaign, late, now));
    assert.equal(state.account!.ineligibleReason, 'REGISTERED_TOO_LATE');
    assert.equal(state.prizes[0]!.remaining, 0);
    const tooLate = await user();
    await assert.rejects(tx(c => drawLottery(c, campaign, tooLate, '1.1.1.1', now + 86400000, first)),
      rejectedCode('LOTTERY_ENDED'));
  });

  await t.test('the quote applies the coupon automatically and the purchase spends it', async () => {
    const id = await user();
    await tx(c => drawLottery(c, campaign, id, '1.1.1.1', now, last)); // 30 / 60 points
    const monthly = await tx(c => quoteMembership(c, id, 'MONTHLY', now));
    assert.equal(monthly.couponId, null);
    const { quote, order } = await buy(id, 'LIFETIME');
    assert.equal(quote.listPoints, 1290);
    assert.equal(quote.couponPoints, 30);
    assert.equal(quote.payablePoints, 1260);
    const row = await db.query<{ coupon_points: string; points_spent: string }>(
      'SELECT coupon_points, points_spent FROM membership_orders WHERE id=$1', [order.orderId]);
    assert.equal(Number(row.rows[0]!.coupon_points), 30);
    assert.equal(Number(row.rows[0]!.points_spent), 1260);
    const coupon = await db.query<{ status: string; used_order_id: string }>(
      'SELECT status, used_order_id FROM membership_coupons WHERE user_id=$1', [id]);
    assert.equal(coupon.rows[0]!.status, 'USED');
    assert.equal(coupon.rows[0]!.used_order_id, order.orderId);
    // A later upgrade credits what the lifetime membership actually cost.
    const upgrade = await tx(c => quoteMembership(c, id, 'SUPER_LIFETIME', now));
    assert.equal(upgrade.creditPoints, 1260);
    assert.equal(upgrade.couponId, null);
    await assert.rejects(tx(c => setSuperChoice(c, campaign, id, 'CLOUD')), rejectedCode('LOTTERY_COUPON_UNAVAILABLE'));
  });

  await t.test('super with a coupon gets no bonus; super traded for cloud space gets 5 GiB', async () => {
    const withCoupon = await user();
    await tx(c => drawLottery(c, campaign, withCoupon, '1.1.1.1', now, last));
    const used = await buy(withCoupon, 'SUPER_LIFETIME');
    assert.equal(used.quote.couponPoints, 60);
    assert.equal(await cloudQuotaBytes(query, withCoupon), CLOUD_BASE_QUOTA_BYTES);

    const cloud = await user();
    await tx(c => drawLottery(c, campaign, cloud, '1.1.1.1', now, last));
    await assert.rejects(tx(c => setSuperChoice(c, campaign, cloud, 'FREE')), rejectedCode('LOTTERY_INVALID_CHOICE'));
    await tx(c => setSuperChoice(c, campaign, cloud, 'CLOUD'));
    // Trading the coupon only affects the super membership.
    assert.equal((await tx(c => quoteMembership(c, cloud, 'LIFETIME', now))).couponPoints, 30);
    const bought = await buy(cloud, 'SUPER_LIFETIME');
    assert.equal(bought.quote.couponId, null);
    assert.equal(bought.quote.payablePoints, 2490);
    assert.equal(await cloudQuotaBytes(query, cloud), 5 * 1024 ** 3);
    assert.equal((await membershipSnapshot(query, cloud, now)).benefits.cloudStorageBytes, 5 * 1024 ** 3);
    assert.equal((await tx(c => lotteryState(c, campaign, cloud, now))).account!.cloudBonus, true);

    const noLottery = await user();
    await buy(noLottery, 'SUPER_LIFETIME');
    assert.equal(await cloudQuotaBytes(query, noLottery), 5 * 1024 ** 3);
  });

  await t.test('no bonus outside the campaign or while it is disabled', async () => {
    const after = await user();
    await buy(after, 'SUPER_LIFETIME', now + 86400000);
    assert.equal(await cloudQuotaBytes(query, after), CLOUD_BASE_QUOTA_BYTES);
    await db.query('UPDATE lottery_campaigns SET enabled=FALSE WHERE id=$1', [campaign]);
    try {
      const disabled = await user();
      await buy(disabled, 'SUPER_LIFETIME');
      assert.equal(await cloudQuotaBytes(query, disabled), CLOUD_BASE_QUOTA_BYTES);
      assert.equal((await membershipSnapshot(query, disabled, now)).benefits.cloudStorageBytes, CLOUD_BASE_QUOTA_BYTES);
    } finally {
      await db.query('UPDATE lottery_campaigns SET enabled=TRUE WHERE id=$1', [campaign]);
    }
  });

  await t.test('changing the choice after quoting refuses the stale quote', async () => {
    const id = await user();
    await tx(c => drawLottery(c, campaign, id, '1.1.1.1', now, last));
    const quote = await tx(c => quoteMembership(c, id, 'SUPER_LIFETIME', now));
    assert.equal(quote.couponPoints, 60);
    await tx(c => setSuperChoice(c, campaign, id, 'CLOUD'));
    await assert.rejects(tx(c => purchaseMembership(c, id, quote.quoteId, 'stale', now)),
      rejectedCode('MEMBERSHIP_OFFER_CHANGED'));
    const wallet = await db.query<{ paid_balance: string }>('SELECT paid_balance FROM point_wallets WHERE user_id=$1', [id]);
    assert.equal(Number(wallet.rows[0]!.paid_balance), 10000);
  });

  await t.test('the largest coupon wins, capped at half; quotes from before coupons still buy', async () => {
    const id = await user();
    await db.query(`INSERT INTO membership_coupons(user_id,campaign_id,prize_id,discounts) VALUES
      ($1,$2,'t-lucky','{"LIFETIME":30}'), ($1,$2,'t-grand','{"LIFETIME":5000}')`, [id, campaign]);
    const quote = await tx(c => quoteMembership(c, id, 'LIFETIME', now));
    assert.equal(quote.couponPoints, 645);
    assert.equal(quote.payablePoints, 645);
    // Simulate a quote stored before this release: no coupon fields at all.
    await db.query(`UPDATE membership_quotes
      SET plan = jsonb_set(plan - 'couponId' - 'couponPoints', '{payablePoints}', '1290') WHERE id=$1`, [quote.quoteId]);
    await tx(c => purchaseMembership(c, id, quote.quoteId, 'legacy', now));
    const coupons = await db.query<{ status: string }>(
      'SELECT status FROM membership_coupons WHERE user_id=$1 ORDER BY created_at', [id]);
    assert.ok(coupons.rows.every(row => row.status === 'AVAILABLE'));
  });

  await t.test('routes require the page origin and carry the session in cookies', async t2 => {
    const app = Fastify();
    t2.after(() => app.close());
    const origin = 'https://huodong.example.com';
    registerLotteryRoutes(app, { campaignId: campaign, pageOrigin: origin, transaction: tx });
    app.setErrorHandler((error, _req, reply) => {
      if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
      return reply.code(500).send({ code: 'UNEXPECTED', message: String(error) });
    });
    const forged = await app.inject({ method: 'POST', url: '/lottery/api/verify/start', payload: {},
      headers: { origin: 'https://evil.example.com' } });
    assert.equal(forged.statusCode, 403);
    const start = await app.inject({ method: 'POST', url: '/lottery/api/verify/start', payload: {}, headers: { origin } });
    assert.equal(start.statusCode, 200);
    const verifyCookie = String(start.headers['set-cookie']).split(';')[0]!;
    assert.match(String(start.headers['set-cookie']), /HttpOnly; Secure; SameSite=Lax/);
    const id = await user();
    await db.query('UPDATE app_users SET display_name=$2, updated_at=now() WHERE id=$1', [id, '读者' + start.json().code]);
    const check = await app.inject({ method: 'POST', url: '/lottery/api/verify/check', payload: {},
      headers: { origin, cookie: verifyCookie } });
    assert.equal(check.json().verified, true);
    const sessionCookie = ([] as string[]).concat(check.headers['set-cookie'] as string | string[])
      .find(value => value.startsWith('lottery_session='))!.split(';')[0]!;
    const state = await app.inject({ url: '/lottery/api/state', headers: { cookie: sessionCookie } });
    assert.equal(state.json().account.displayName, '读者');
    const anonymous = await app.inject({ method: 'POST', url: '/lottery/api/draw', payload: {}, headers: { origin } });
    assert.equal(anonymous.statusCode, 401);
    const logout = await app.inject({ method: 'POST', url: '/lottery/api/logout', payload: {},
      headers: { origin, cookie: sessionCookie } });
    assert.equal(logout.statusCode, 200);
    const after = await app.inject({ url: '/lottery/api/state', headers: { cookie: sessionCookie } });
    assert.equal(after.json().account, null);
  });
});
