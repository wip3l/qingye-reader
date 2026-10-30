/** Versioned business rules. No client-supplied membership or price is authoritative. */
// v2: quotes carry the charged price and promotion; v1 quotes are refused after deploy.
export const MEMBERSHIP_POLICY_VERSION = 2;
export type MembershipSku = 'MONTHLY' | 'ANNUAL' | 'LIFETIME' | 'SUPER_LIFETIME';
export type MembershipTier = 'STANDARD' | 'SUPER';
export type VoiceTier = 'STANDARD' | 'PREMIUM';

export interface MembershipProduct {
  sku: MembershipSku;
  name: string;
  points: number;
  months: number | null;
  tier: MembershipTier;
}

export const MEMBERSHIP_PRODUCTS: readonly MembershipProduct[] = Object.freeze([
  { sku: 'MONTHLY', name: '月度会员', points: 60, months: 1, tier: 'STANDARD' },
  { sku: 'ANNUAL', name: '年度会员', points: 480, months: 12, tier: 'STANDARD' },
  { sku: 'LIFETIME', name: '终身会员', points: 1290, months: null, tier: 'STANDARD' },
  { sku: 'SUPER_LIFETIME', name: '终身超级会员', points: 2490, months: null, tier: 'SUPER' }
] satisfies MembershipProduct[]);

export interface MembershipState {
  periodId: string;
  sku: MembershipSku;
  anchorAt: number;
  paidMonths: number;
  expiresAt: number | null;
  permanentCreditPoints: number;
  revision: number;
}

export interface MembershipTerm {
  startsAt: number;
  endsAt: number;
  points: number;
}

export class MembershipError extends Error {
  constructor(readonly statusCode: number, readonly code: string, message: string) {
    super(message);
  }
}

export function membershipProduct(sku: unknown): MembershipProduct {
  const product = MEMBERSHIP_PRODUCTS.find((item) => item.sku === sku);
  if (!product) throw new MembershipError(400, 'INVALID_MEMBERSHIP_SKU', '会员商品不存在');
  return product;
}

export function membershipActive(state: MembershipState | null, now: number): boolean {
  return state !== null && state.anchorAt <= now && (state.expiresAt === null || state.expiresAt > now);
}

const BEIJING_OFFSET_MS = 8 * 60 * 60 * 1000;

/** Add months from the original anchor, preserving the Beijing wall-clock time. */
export function membershipAnniversary(anchorAt: number, months: number): number {
  if (!Number.isFinite(anchorAt) || !Number.isSafeInteger(months) || months < 0) {
    throw new Error('Invalid membership anniversary');
  }
  const anchor = new Date(anchorAt + BEIJING_OFFSET_MS);
  const first = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + months, 1));
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  return Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), Math.min(anchor.getUTCDate(), lastDay),
    anchor.getUTCHours(), anchor.getUTCMinutes(), anchor.getUTCSeconds(), anchor.getUTCMilliseconds())
    - BEIJING_OFFSET_MS;
}

export function membershipCycle(state: MembershipState, now: number): {
  index: number; startsAt: number; endsAt: number;
} {
  if (!membershipActive(state, now)) {
    throw new MembershipError(403, 'MEMBERSHIP_INACTIVE', '请先开通有效会员');
  }
  const anchor = new Date(state.anchorAt + BEIJING_OFFSET_MS);
  const current = new Date(now + BEIJING_OFFSET_MS);
  let index = (current.getUTCFullYear() - anchor.getUTCFullYear()) * 12
    + current.getUTCMonth() - anchor.getUTCMonth();
  if (membershipAnniversary(state.anchorAt, index) > now) index--;
  return {
    index,
    startsAt: membershipAnniversary(state.anchorAt, index),
    endsAt: Math.min(membershipAnniversary(state.anchorAt, index + 1), state.expiresAt ?? Infinity)
  };
}

/** Allowance windows are Beijing calendar months, independent of paid-term anniversaries. */
export function membershipCalendarCycle(state: MembershipState, now: number): {
  index: number; startsAt: number; endsAt: number;
} {
  if (!membershipActive(state, now)) {
    throw new MembershipError(403, 'MEMBERSHIP_INACTIVE', '请先开通有效会员');
  }
  const current = new Date(now + BEIJING_OFFSET_MS);
  const year = current.getUTCFullYear(), month = current.getUTCMonth();
  return {
    index: year * 12 + month,
    startsAt: Date.UTC(year, month, 1) - BEIJING_OFFSET_MS,
    // Exclusive upper bound: the last millisecond belongs to the preceding calendar month.
    endsAt: Date.UTC(year, month + 1, 1) - BEIJING_OFFSET_MS
  };
}

export const membershipGiftCycle = membershipCalendarCycle;

/** Monthly terms carry no monthly reading gift; annual and permanent tiers do. */
export function membershipGiftChars(sku: MembershipSku, tier: VoiceTier): number {
  if (sku === 'MONTHLY') return 0;
  if (sku === 'ANNUAL') return tier === 'STANDARD' ? 5000 : 2500;
  if (sku === 'LIFETIME') return tier === 'STANDARD' ? 8000 : 4000;
  return tier === 'STANDARD' ? 12000 : 6000;
}

/** The price charged right now: the product's base price, or an active promotion's lower price. */
export interface MembershipPrice {
  pricePoints: number;
  promotionId: string | null;
  promotionLabel: string | null;
  promotionEndsAt: number | null;
}

export function basePrice(sku: MembershipSku): MembershipPrice {
  return { pricePoints: membershipProduct(sku).points, promotionId: null, promotionLabel: null, promotionEndsAt: null };
}

export interface MembershipPurchasePlan {
  sku: MembershipSku;
  listPoints: number;
  promotionId: string | null;
  creditPoints: number;
  payablePoints: number;
  /** Absent on quotes issued before coupons existed; treat as no coupon. */
  couponId?: string | null;
  couponPoints?: number;
  expectedRevision: number;
  newPeriod: boolean;
  next: MembershipState;
  term: MembershipTerm | null;
}

export interface MembershipCouponUse { id: string; points: number; }

/**
 * Points a coupon takes off a quote: its per-SKU amount, at most half of what is still payable after
 * any upgrade credit, and never the whole order. Zero when the coupon does not cover the SKU.
 */
export function membershipCouponPoints(discounts: unknown, sku: MembershipSku, payablePoints: number): number {
  const points = discounts && typeof discounts === 'object' ? (discounts as Record<string, unknown>)[sku] : undefined;
  if (typeof points !== 'number' || !Number.isSafeInteger(points) || points <= 0) return 0;
  return Math.max(0, Math.min(points, Math.floor(payablePoints / 2), payablePoints - 1));
}

export function planMembershipPurchase(
  current: MembershipState | null,
  terms: readonly MembershipTerm[],
  sku: MembershipSku,
  now: number,
  newPeriodId: string,
  price: MembershipPrice = basePrice(sku),
  coupon: MembershipCouponUse | null = null
): MembershipPurchasePlan {
  const product = membershipProduct(sku);
  const pricePoints = price.pricePoints;
  if (!Number.isSafeInteger(pricePoints) || pricePoints <= 0 || pricePoints > product.points) {
    throw new Error('Invalid membership price');
  }
  const active = membershipActive(current, now) ? current : null;
  if (active?.expiresAt === null &&
      (active.sku === 'SUPER_LIFETIME' || sku !== 'SUPER_LIFETIME')) {
    throw new MembershipError(409, 'MEMBERSHIP_ALREADY_OWNED', '已拥有终身权益，无需重复购买或降级');
  }
  let creditPoints = 0;
  if (active && product.months === null) {
    creditPoints = active.expiresAt === null
      ? active.permanentCreditPoints
      : Math.floor(terms.reduce((sum, term) => {
        if (term.endsAt <= now || term.endsAt <= term.startsAt) return sum;
        const ratio = Math.min(1, (term.endsAt - now) / (term.endsAt - term.startsAt));
        return sum + term.points * ratio;
      }, 0));
    // Upgrade credits are not cash and cannot make an order negative.
    creditPoints = Math.min(pricePoints, Math.max(0, creditPoints));
  }
  const couponPoints = coupon?.points ?? 0;
  if (!Number.isSafeInteger(couponPoints) || couponPoints < 0 || couponPoints >= Math.max(1, pricePoints - creditPoints)) {
    throw new Error('Invalid membership coupon');
  }
  const anchorAt = active?.anchorAt ?? now;
  const paidMonths = product.months === null ? 0 : (active?.paidMonths ?? 0) + product.months;
  const expiresAt = product.months === null ? null : membershipAnniversary(anchorAt, paidMonths);
  return {
    sku,
    listPoints: pricePoints,
    promotionId: price.promotionId,
    creditPoints,
    payablePoints: pricePoints - creditPoints - couponPoints,
    couponId: coupon?.id ?? null,
    couponPoints,
    expectedRevision: current?.revision ?? 0,
    newPeriod: active === null,
    next: {
      periodId: active?.periodId ?? newPeriodId,
      sku,
      anchorAt,
      paidMonths,
      expiresAt,
      // A later upgrade credits what this permanent product actually cost, promotion and coupon included.
      permanentCreditPoints: product.months === null ? pricePoints - couponPoints : 0,
      revision: (current?.revision ?? 0) + 1
    },
    term: expiresAt === null ? null : {
      startsAt: active?.expiresAt ?? now,
      endsAt: expiresAt,
      points: pricePoints
    }
  };
}

/** tierSku is the product covering `now` (see membershipTierSku); it defaults to the period's last SKU. */
export function membershipBenefits(state: MembershipState | null, now: number, tierSku?: MembershipSku) {
  const active = membershipActive(state, now);
  const giftSku = tierSku ?? state?.sku;
  const superMember = active && state?.sku === 'SUPER_LIFETIME';
  return {
    memberThemes: active,
    animatedAvatar: active && state?.expiresAt === null &&
      (state.sku === 'LIFETIME' || state.sku === 'SUPER_LIFETIME'),
    ttsPriority: active,
    sourceCount: superMember ? null : active ? 500 : 50,
    sourceBytes: superMember ? null : (active ? 512 : 50) * 1024,
    cloudStorageBytes: superMember ? 1024 ** 3 : 0,
    monthlyDownloadBytes: superMember ? 1024 ** 3 : 0,
    standardGiftChars: active && giftSku ? membershipGiftChars(giftSku, 'STANDARD') : 0,
    premiumGiftChars: active && giftSku ? membershipGiftChars(giftSku, 'PREMIUM') : 0
  };
}
