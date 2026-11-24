import type { PoolClient } from 'pg';

/** 能跑 SQL 的连接（node-postgres 的 PoolClient，或测试里的 PGlite 适配）。 */
export interface PointDb { query: PoolClient['query']; }

export class PointCreditError extends Error {
  constructor(readonly statusCode: number, readonly code: string, message: string) {
    super(message);
  }
}

export interface PaidCreditResult {
  /** 实际进入可用余额的点数（先抵扣欠款后剩下的部分）。 */
  creditedPoints: number;
  /** 用来抵扣退款欠款的点数。 */
  debtOffsetPoints: number;
  balanceAfter: number;
}

/**
 * 把一笔已付款的充值点记进钱包：先抵扣 account_debts 里的退款欠款，余下加到 balance 和 paid_balance，
 * 并写一条带幂等键的 point_ledger。必须在事务里调用；同一订单的并发由调用方的 advisory 锁或行锁挡住。
 * 华为应用内支付、支付宝和兑换码三条渠道都走这里，开通会员只认 paid_balance。
 */
export async function creditPaidPoints(db: PointDb, userId: string, points: number, reason: string,
  referenceId: string, idempotencyKey: string): Promise<PaidCreditResult> {
  if (!Number.isInteger(points) || points <= 0) {
    throw new PointCreditError(400, 'INVALID_POINTS', '充值点数无效');
  }
  const wallet = await db.query<{ balance: string; paid_balance: string }>(
    `SELECT balance, paid_balance FROM point_wallets WHERE user_id = $1 FOR UPDATE`, [userId]);
  if (!wallet.rowCount) {
    throw new PointCreditError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
  }
  const debt = await db.query<{ iap_debt_points: string }>(
    `SELECT iap_debt_points FROM account_debts WHERE user_id = $1 FOR UPDATE`, [userId]);
  const debtBefore = Number(debt.rows[0]?.iap_debt_points || 0);
  const debtOffsetPoints = Math.min(debtBefore, points);
  const creditedPoints = points - debtOffsetPoints;
  const balanceAfter = Number(wallet.rows[0]!.balance) + creditedPoints;
  await db.query(
    `UPDATE point_wallets SET balance = $2, paid_balance = $3, updated_at = now() WHERE user_id = $1`,
    [userId, balanceAfter, Number(wallet.rows[0]!.paid_balance) + creditedPoints]);
  if (debtOffsetPoints > 0) {
    await db.query(
      `UPDATE account_debts SET iap_debt_points = iap_debt_points - $2, updated_at = now() WHERE user_id = $1`,
      [userId, debtOffsetPoints]);
  }
  await db.query(
    `INSERT INTO point_ledger (user_id, delta, balance_after, reason, reference_id, idempotency_key)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [userId, creditedPoints, balanceAfter, reason, referenceId, idempotencyKey]);
  return { creditedPoints, debtOffsetPoints, balanceAfter };
}

/** 与 calculateIapReversal 相同：已经花掉、扣不回来的部分记成欠款，下次充值先抵扣。 */
export function calculatePaidReversal(creditedPoints: number, originalDebtOffset: number,
  currentPaidBalance: number): { reversedPoints: number; debtPoints: number } {
  const originallyAvailablePoints = Math.max(0, creditedPoints - originalDebtOffset);
  const reversedPoints = Math.min(Math.max(0, currentPaidBalance), originallyAvailablePoints);
  return { reversedPoints, debtPoints: originalDebtOffset + originallyAvailablePoints - reversedPoints };
}

/**
 * 退款冲正：按 calculatePaidReversal 扣回 paid_balance，扣不回的记欠款，写一条负数 point_ledger。
 * creditedPoints 是当初入账时的总点数（含抵扣欠款的部分），originalDebtOffset 是当初抵扣的欠款。
 */
export async function reversePaidCredit(db: PointDb, userId: string, creditedPoints: number,
  originalDebtOffset: number, reason: string, referenceId: string,
  idempotencyKey: string): Promise<{ reversedPoints: number; debtPoints: number; balanceAfter: number }> {
  const wallet = await db.query<{ balance: string; paid_balance: string }>(
    `SELECT balance, paid_balance FROM point_wallets WHERE user_id = $1 FOR UPDATE`, [userId]);
  if (!wallet.rowCount) return { reversedPoints: 0, debtPoints: 0, balanceAfter: 0 };
  const { reversedPoints, debtPoints } = calculatePaidReversal(creditedPoints, originalDebtOffset,
    Number(wallet.rows[0]!.paid_balance));
  const balanceAfter = Number(wallet.rows[0]!.balance) - reversedPoints;
  await db.query(
    `UPDATE point_wallets SET balance = $2, paid_balance = paid_balance - $3, updated_at = now() WHERE user_id = $1`,
    [userId, balanceAfter, reversedPoints]);
  await db.query(
    `INSERT INTO point_ledger (user_id, delta, balance_after, reason, reference_id, idempotency_key)
     VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (idempotency_key) DO NOTHING`,
    [userId, -reversedPoints, balanceAfter, reason, referenceId, idempotencyKey]);
  if (debtPoints > 0) {
    await db.query(
      `INSERT INTO account_debts (user_id, iap_debt_points) VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET
         iap_debt_points = account_debts.iap_debt_points + EXCLUDED.iap_debt_points, updated_at = now()`,
      [userId, debtPoints]);
  }
  return { reversedPoints, debtPoints, balanceAfter };
}
