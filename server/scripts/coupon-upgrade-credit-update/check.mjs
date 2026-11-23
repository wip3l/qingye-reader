// Runs the candidate membershipPolicy.js in memory: upgrade credit with and without a coupon (no network/database).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const runtime = resolve(process.argv[2] || '.');
const source = readFileSync(resolve(runtime, 'membershipPolicy.js'), 'utf8');
assert(!/^import /m.test(source), 'membershipPolicy.js is expected to have no imports');
// Loaded from memory so the check does not depend on a package.json next to the candidate.
const policy = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const now = Date.parse('2028-03-10T12:00:00+08:00');
const plan = (state, sku, price, coupon) => policy.planMembershipPurchase(state, [], sku, now, 'period', price, coupon);

assert.equal(policy.MEMBERSHIP_POLICY_VERSION, 3);
// A coupon lowers what the lifetime membership costs, and the upgrade no longer charges it back.
const withCoupon = plan(null, 'LIFETIME', undefined, { id: 'coupon', points: 100 });
assert.equal(withCoupon.payablePoints, 1190);
assert.equal(withCoupon.couponPoints, 100);
assert.equal(withCoupon.next.permanentCreditPoints, 1290);
assert.equal(plan(withCoupon.next, 'SUPER_LIFETIME').payablePoints, 1200);
// Without a coupon nothing changes, and a promotion price is still credited as paid.
const plain = plan(null, 'LIFETIME');
assert.equal(plain.next.permanentCreditPoints, 1290);
assert.equal(plan(plain.next, 'SUPER_LIFETIME').payablePoints, 1200);
const promoted = plan(null, 'LIFETIME', { pricePoints: 645, promotionId: 'p', promotionLabel: null, promotionEndsAt: null },
  { id: 'coupon', points: 100 });
assert.equal(promoted.payablePoints, 545);
assert.equal(promoted.next.permanentCreditPoints, 645);
assert.equal(plan(promoted.next, 'SUPER_LIFETIME').payablePoints, 1845);
// Earlier coupon rules unchanged.
assert.equal(policy.membershipCouponPoints({ LIFETIME: 100, SUPER_LIFETIME: 200 }, 'LIFETIME', 645), 100);
assert.equal(policy.membershipCouponPoints({ SUPER_LIFETIME: 600 }, 'SUPER_LIFETIME', 600), 300);
assert.equal(policy.membershipCouponPoints({ LIFETIME: 100 }, 'MONTHLY', 60), 0);
assert.equal(plan(null, 'MONTHLY').next.permanentCreditPoints, 0);
console.log('PASS: upgrade credit with coupon, without coupon and at a promotion price (no network/database access)');
