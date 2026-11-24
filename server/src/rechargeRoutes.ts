import { createHash, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { AlipayClient } from './alipay.js';
import { yuanToFen } from './alipay.js';
import { creditPaidPoints, PointCreditError, PointDb, reversePaidCredit } from './pointCredit.js';
import { MembershipSku, membershipProduct } from './membershipPolicy.js';
import { purchaseMembership, quoteMembership } from './membershipService.js';

/**
 * 安卓端充值（docs/android-recharge.md）：支付宝手机网站支付和兑换码。鸿蒙端不走这里，仍用 /v1/iap/credit。
 * 金额只由服务端按商品算（1 元 = 10 点）；入账、抵扣欠款、退款冲正都用 pointCredit.ts 里与 IAP 相同的规则。
 */
export const RECHARGE_PRODUCTS: ReadonlyArray<{ productId: string; points: number }> = [
  { productId: 'legado_points_10', points: 10 },
  { productId: 'legado_points_60', points: 60 },
  { productId: 'legado_points_100', points: 100 },
  { productId: 'legado_points_300', points: 300 },
  { productId: 'legado_points_500', points: 500 },
  { productId: 'legado_points_1000', points: 1000 }
];
const FEN_PER_POINT = 10;
const ORDER_EXPIRE_MINUTES = 30;
const PAID_STATUSES = new Set(['TRADE_SUCCESS', 'TRADE_FINISHED']);

export class RechargeError extends PointCreditError {}

interface RechargeRouteDependencies {
  alipay: AlipayClient | null;
  authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  userId: (request: FastifyRequest) => string;
  transaction: <T>(work: (client: PointDb) => Promise<T>) => Promise<T>;
  /** 按账号限流；key 区分下单、查单和兑换。 */
  limit: (userId: string, key: string, perMinute: number) => Promise<void>;
  account: (client: PointDb, userId: string) => Promise<unknown>;
  log?: { warn: (obj: unknown, msg: string) => void; error: (obj: unknown, msg: string) => void };
}

interface OrderRow {
  id: string;
  user_id: string;
  product_id: string;
  amount_fen: number;
  points: number;
  status: string;
  credited_points: number;
  debt_offset_points: number;
  created_at: Date;
}

/** 支付宝 out_trade_no：订单 UUID 去掉连字符（32 位，只含字母数字）。 */
export function outTradeNo(orderId: string): string {
  return orderId.replace(/-/g, '');
}

function orderIdFromOutTradeNo(value: string): string | null {
  if (!/^[0-9a-f]{32}$/i.test(value || '')) return null;
  const v = value.toLowerCase();
  return `${v.slice(0, 8)}-${v.slice(8, 12)}-${v.slice(12, 16)}-${v.slice(16, 20)}-${v.slice(20)}`;
}

/** 兑换码规范化：去掉空格和连字符，转大写。 */
export function normalizeRedeemCode(code: string): string {
  return (code || '').replace(/[\s-]/g, '').toUpperCase();
}

export function redeemCodeHash(code: string): string {
  return createHash('sha256').update(normalizeRedeemCode(code), 'utf8').digest('hex');
}

export interface AlipayTradeEvent {
  outTradeNo: string;
  tradeStatus: string;
  tradeNo: string;
  totalAmount: string;
  /** 通知里的累计退款金额（元）；查单结果不带。 */
  refundFee?: string;
  payload: Record<string, unknown>;
}

/**
 * 按支付宝的交易状态推进订单（通知和主动查单都走这里，可重复调用）：
 * 付款成功 → 入账（幂等键 recharge:<订单号>）；全额退款 → 冲正；未付款就关闭 → CLOSED。
 * 部分退款不自动处理（本应用只会全额退款），记日志由运营手工核对。
 */
export async function applyAlipayTrade(db: PointDb, event: AlipayTradeEvent,
  log?: RechargeRouteDependencies['log']): Promise<'credited' | 'refunded' | 'closed' | 'unchanged' | 'ignored'> {
  const orderId = orderIdFromOutTradeNo(event.outTradeNo);
  if (!orderId) return 'ignored';
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`recharge:${orderId}`]);
  const found = await db.query<OrderRow>(
    `SELECT id, user_id, product_id, amount_fen, points, status, credited_points, debt_offset_points, created_at
     FROM recharge_orders WHERE id = $1 AND channel = 'ALIPAY' FOR UPDATE`, [orderId]);
  if (!found.rowCount) return 'ignored';
  const order = found.rows[0]!;
  const totalFen = yuanToFen(event.totalAmount);
  if (totalFen !== order.amount_fen) {
    log?.error({ orderId, totalAmount: event.totalAmount }, 'Alipay amount does not match order');
    return 'ignored';
  }
  const refundFen = event.refundFee ? yuanToFen(event.refundFee) : 0;
  const fullyRefunded = refundFen >= order.amount_fen;
  if (refundFen > 0 && !fullyRefunded) {
    log?.warn({ orderId, refundFee: event.refundFee }, 'Alipay partial refund needs manual handling');
  }

  if (fullyRefunded) {
    if (order.status !== 'PAID') return 'unchanged';
    const reversal = await reversePaidCredit(db, order.user_id, order.points, order.debt_offset_points,
      'ALIPAY_REVERSAL', order.id, `recharge-reversal:${order.id}`);
    await db.query(
      `UPDATE recharge_orders SET status = 'REFUNDED', refunded_at = now(), reversed_points = $2, debt_points = $3,
         provider_payload = $4::jsonb, updated_at = now() WHERE id = $1`,
      [order.id, reversal.reversedPoints, reversal.debtPoints, JSON.stringify(event.payload)]);
    return 'refunded';
  }
  if (PAID_STATUSES.has(event.tradeStatus)) {
    if (order.status === 'PAID' || order.status === 'REFUNDED') return 'unchanged';
    // 订单可能已被标成 CLOSED（超时后才付款）：只要支付宝说付了就入账。
    const credit = await creditPaidPoints(db, order.user_id, order.points, 'ALIPAY_RECHARGE', order.id,
      `recharge:${order.id}`);
    await db.query(
      `UPDATE recharge_orders SET status = 'PAID', provider_trade_no = $2, paid_at = now(), credited_points = $3,
         debt_offset_points = $4, provider_payload = $5::jsonb, updated_at = now() WHERE id = $1`,
      [order.id, event.tradeNo, credit.creditedPoints, credit.debtOffsetPoints, JSON.stringify(event.payload)]);
    return 'credited';
  }
  if ((event.tradeStatus === 'TRADE_CLOSED' || event.tradeStatus === 'NOT_FOUND') && order.status === 'PENDING') {
    // 查无此单只在过了支付期限后才算关闭（用户可能还没打开收银台）。
    if (event.tradeStatus === 'NOT_FOUND' &&
      order.created_at.getTime() + ORDER_EXPIRE_MINUTES * 60 * 1000 > Date.now()) return 'unchanged';
    await db.query(`UPDATE recharge_orders SET status = 'CLOSED', updated_at = now() WHERE id = $1`, [order.id]);
    return 'closed';
  }
  return 'unchanged';
}

/**
 * 会员兑换码：在调用方的事务里先报价（会锁账号、检查欠款与是否在售、是否已有更高的终身权益），
 * 再记入充值点（码面值与实付取大，涨价后码仍能开通该档），最后按报价购买。任何一步失败整笔回滚，码不作废。
 * 实付少于码面值（升级抵扣、促销价、自动用券）时差额留作充值点。流水：REDEEM_CODE 加点（幂等键 redeem:<哈希>），
 * MEMBERSHIP_PURCHASE 扣点（购买请求号 redeem:<哈希前 32 位>，同一个码只能买一次）。
 */
export async function redeemMembershipCode(db: PointDb, userId: string, hash: string, sku: MembershipSku,
  codePoints: number, now = Date.now()) {
  const product = membershipProduct(sku);
  const quote = await quoteMembership(db, userId, sku, now);
  const points = Math.max(codePoints, quote.payablePoints);
  await creditPaidPoints(db, userId, points, 'REDEEM_CODE', hash.slice(0, 16), `redeem:${hash}`);
  const order = await purchaseMembership(db, userId, quote.quoteId, `redeem:${hash.slice(0, 32)}`, now);
  if (order.duplicate) throw new RechargeError(409, 'CODE_USED', '兑换码已被使用');
  return {
    kind: 'membership', sku, membershipName: product.name, orderId: order.orderId, points,
    // 留作充值点的差额。
    creditedPoints: points - quote.payablePoints, debtOffsetPoints: 0
  };
}

export function registerRechargeRoutes(app: FastifyInstance, deps: RechargeRouteDependencies): void {
  const products = RECHARGE_PRODUCTS.map(product => ({ ...product, amountFen: product.points * FEN_PER_POINT }));

  app.get('/v1/recharge/channels', { preHandler: deps.authenticate }, async (_request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    return { alipay: !!deps.alipay, redeem: true, products };
  });

  app.post<{ Body: { productId?: string; channel?: string } }>('/v1/recharge/orders',
    { preHandler: deps.authenticate }, async request => {
      const userId = deps.userId(request);
      await deps.limit(userId, 'recharge-order', 10);
      if (!deps.alipay || (request.body?.channel || 'ALIPAY') !== 'ALIPAY') {
        throw new RechargeError(503, 'RECHARGE_UNAVAILABLE', '支付宝充值暂未开放');
      }
      const product = products.find(item => item.productId === request.body?.productId);
      if (!product) throw new RechargeError(400, 'UNKNOWN_PRODUCT', '充值档位不存在');
      const orderId = randomUUID();
      await deps.transaction(db => db.query(
        `INSERT INTO recharge_orders (id, user_id, channel, product_id, amount_fen, points)
         VALUES ($1, $2, 'ALIPAY', $3, $4, $5)`,
        [orderId, userId, product.productId, product.amountFen, product.points]));
      const checkoutUrl = deps.alipay.wapPayUrl({
        outTradeNo: outTradeNo(orderId),
        amountFen: product.amountFen,
        subject: `开源轻页 ${product.points} 充值点`,
        expireMinutes: ORDER_EXPIRE_MINUTES
      });
      return { orderId, checkoutUrl, points: product.points, amountFen: product.amountFen };
    });

  app.get<{ Params: { id: string } }>('/v1/recharge/orders/:id', { preHandler: deps.authenticate }, async request => {
    const userId = deps.userId(request);
    await deps.limit(userId, 'recharge-query', 30);
    const orderId = request.params.id;
    if (!/^[0-9a-f-]{36}$/i.test(orderId)) throw new RechargeError(404, 'ORDER_NOT_FOUND', '订单不存在');
    const owned = await deps.transaction(db => db.query<{ status: string }>(
      `SELECT status FROM recharge_orders WHERE id = $1 AND user_id = $2`, [orderId, userId]));
    if (!owned.rowCount) throw new RechargeError(404, 'ORDER_NOT_FOUND', '订单不存在');
    // 回到前台时通知可能还没到：未完成的订单顺带向支付宝查一次。
    if (owned.rows[0]!.status === 'PENDING' && deps.alipay) {
      try {
        const trade = await deps.alipay.queryTrade(outTradeNo(orderId));
        await deps.transaction(db => applyAlipayTrade(db, {
          outTradeNo: outTradeNo(orderId), tradeStatus: trade.tradeStatus, tradeNo: trade.tradeNo,
          totalAmount: trade.totalAmount || '', payload: trade.raw
        }, deps.log));
      } catch (error) {
        deps.log?.warn({ err: error, orderId }, 'Alipay trade query failed');
      }
    }
    return deps.transaction(async db => {
      const order = await db.query<OrderRow>(
        `SELECT id, user_id, product_id, amount_fen, points, status, credited_points, debt_offset_points, created_at
         FROM recharge_orders WHERE id = $1`, [orderId]);
      const row = order.rows[0]!;
      return {
        orderId: row.id, status: row.status, points: row.points,
        creditedPoints: row.credited_points, debtOffsetPoints: row.debt_offset_points,
        account: await deps.account(db, userId)
      };
    });
  });

  app.post<{ Body: { code?: string } }>('/v1/recharge/redeem', { preHandler: deps.authenticate }, async request => {
    const userId = deps.userId(request);
    // 兑换码有 80 位随机性，限流只是为了挡住刷接口。
    await deps.limit(userId, 'recharge-redeem', 5);
    const code = normalizeRedeemCode(request.body?.code || '');
    if (!/^[A-Z0-9]{8,32}$/.test(code)) throw new RechargeError(400, 'INVALID_CODE', '兑换码格式不对');
    const hash = redeemCodeHash(code);
    return deps.transaction(async db => {
      const found = await db.query<{ points: number; expires_at: Date | null; redeemed_by: string | null;
        revoked_at: Date | null; membership_sku: MembershipSku | null }>(
        `SELECT points, expires_at, redeemed_by, revoked_at, membership_sku FROM redeem_codes
         WHERE code_hash = $1 FOR UPDATE`, [hash]);
      if (!found.rowCount) throw new RechargeError(404, 'INVALID_CODE', '兑换码不存在');
      const row = found.rows[0]!;
      if (row.revoked_at || (row.expires_at && row.expires_at.getTime() < Date.now())) {
        throw new RechargeError(410, 'CODE_EXPIRED', '兑换码已失效');
      }
      if (row.redeemed_by) throw new RechargeError(409, 'CODE_USED', '兑换码已被使用');
      if (row.membership_sku) {
        const result = await redeemMembershipCode(db, userId, hash, row.membership_sku, row.points);
        await db.query(`UPDATE redeem_codes SET redeemed_by = $2, redeemed_at = now() WHERE code_hash = $1`, [hash, userId]);
        return { ...result, account: await deps.account(db, userId) };
      }
      const credit = await creditPaidPoints(db, userId, row.points, 'REDEEM_CODE', hash.slice(0, 16), `redeem:${hash}`);
      await db.query(`UPDATE redeem_codes SET redeemed_by = $2, redeemed_at = now() WHERE code_hash = $1`, [hash, userId]);
      return {
        kind: 'points', points: row.points, creditedPoints: credit.creditedPoints, debtOffsetPoints: credit.debtOffsetPoints,
        account: await deps.account(db, userId)
      };
    });
  });

  // 支付宝异步通知：表单格式，不登录。验签通过且处理完才回 success，否则支付宝会按间隔重发。
  app.register(async scope => {
    scope.addContentTypeParser('application/x-www-form-urlencoded', { parseAs: 'string', bodyLimit: 64 * 1024 },
      (_request, body, done) => {
        done(null, Object.fromEntries(new URLSearchParams(String(body))));
      });
    scope.post('/v1/recharge/notify/alipay', async (request, reply) => {
      reply.type('text/plain');
      const params = (request.body || {}) as Record<string, string>;
      if (!deps.alipay || !deps.alipay.verifyNotify(params)) {
        deps.log?.warn({ outTradeNo: params.out_trade_no }, 'Alipay notify rejected');
        return 'failure';
      }
      try {
        await deps.transaction(db => applyAlipayTrade(db, {
          outTradeNo: params.out_trade_no || '', tradeStatus: params.trade_status || '', tradeNo: params.trade_no || '',
          totalAmount: params.total_amount || '', refundFee: params.refund_fee, payload: params
        }, deps.log));
        return 'success';
      } catch (error) {
        deps.log?.error({ err: error, outTradeNo: params.out_trade_no }, 'Alipay notify handling failed');
        return 'failure';
      }
    });
  });
}
