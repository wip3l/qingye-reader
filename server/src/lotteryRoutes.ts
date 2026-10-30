import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { MembershipError } from './membershipPolicy.js';
import { MembershipDb } from './membershipService.js';
import {
  VERIFY_TTL_MS, WEB_SESSION_TTL_MS, checkVerification, drawLottery, endSession, lotteryState,
  sessionUserId, setSuperChoice, startVerification
} from './lotteryService.js';

interface LotteryRouteDependencies {
  campaignId: string;
  /** Scheme and host of the page; POSTs from any other origin are refused. Empty refuses every POST. */
  pageOrigin: string;
  transaction: <T>(work: (db: MembershipDb) => Promise<T>) => Promise<T>;
}

const VERIFY_COOKIE = 'lottery_verify';
const SESSION_COOKIE = 'lottery_session';
const COOKIE_PATH = '/lottery/api';

function cookies(request: FastifyRequest): Map<string, string> {
  const result = new Map<string, string>();
  for (const part of (request.headers.cookie ?? '').split(';')) {
    const index = part.indexOf('=');
    if (index > 0) result.set(part.slice(0, index).trim(), part.slice(index + 1).trim());
  }
  return result;
}

function setCookie(reply: FastifyReply, name: string, value: string, maxAgeMs: number) {
  const cookie = `${name}=${value}; Path=${COOKIE_PATH}; Max-Age=${Math.max(0, Math.floor(maxAgeMs / 1000))}; ` +
    'HttpOnly; Secure; SameSite=Lax';
  const existing = reply.getHeader('set-cookie');
  const list = existing === undefined ? [] : Array.isArray(existing) ? existing.map(String) : [String(existing)];
  reply.header('set-cookie', [...list, cookie]);
}

export function registerLotteryRoutes(app: FastifyInstance, deps: LotteryRouteDependencies): void {
  const sameOrigin = async (request: FastifyRequest) => {
    if (!deps.pageOrigin || request.headers.origin !== deps.pageOrigin) {
      throw new MembershipError(403, 'LOTTERY_FORBIDDEN_ORIGIN', '请从活动页面操作');
    }
  };
  const signedIn = async (request: FastifyRequest, db: MembershipDb) => {
    const token = cookies(request).get(SESSION_COOKIE);
    return token ? sessionUserId(db, token) : null;
  };
  const requireUser = async (request: FastifyRequest, db: MembershipDb) =>
    await signedIn(request, db) ?? (() => { throw new MembershipError(401, 'LOTTERY_SIGNED_OUT', '请先验证账号'); })();
  const limited = (max: number) => ({ rateLimit: { max, timeWindow: 60_000 } });

  app.get('/lottery/api/state', async (request, reply) => {
    const state = await deps.transaction(async db =>
      lotteryState(db, deps.campaignId, await signedIn(request, db)));
    if (!state.account && cookies(request).has(SESSION_COOKIE)) setCookie(reply, SESSION_COOKIE, '', 0);
    return state;
  });

  app.post('/lottery/api/verify/start', { preHandler: sameOrigin, config: limited(5) }, async (request, reply) => {
    const verification = await deps.transaction(db => startVerification(db, request.ip));
    setCookie(reply, VERIFY_COOKIE, verification.token, VERIFY_TTL_MS);
    return { code: verification.code, expiresAt: verification.expiresAt };
  });

  app.post('/lottery/api/verify/check', { preHandler: sameOrigin, config: limited(30) }, async (request, reply) => {
    const token = cookies(request).get(VERIFY_COOKIE);
    if (!token) throw new MembershipError(410, 'LOTTERY_VERIFY_EXPIRED', '验证码已失效，请重新获取');
    let result;
    try {
      result = await deps.transaction(db => checkVerification(db, token));
    } catch (error) {
      if (error instanceof MembershipError && error.statusCode === 410) setCookie(reply, VERIFY_COOKIE, '', 0);
      throw error;
    }
    if (!result.verified) return { verified: false, expiresAt: result.expiresAt };
    setCookie(reply, VERIFY_COOKIE, '', 0);
    setCookie(reply, SESSION_COOKIE, result.sessionToken, WEB_SESSION_TTL_MS);
    return { verified: true, displayName: result.displayName };
  });

  app.post('/lottery/api/draw', { preHandler: sameOrigin, config: limited(20) }, async request =>
    deps.transaction(async db => {
      const userId = await requireUser(request, db);
      return drawLottery(db, deps.campaignId, userId, request.ip);
    }));

  app.post<{ Body: { choice?: unknown } }>('/lottery/api/coupon/super-choice',
    { preHandler: sameOrigin, config: limited(20) }, async request =>
      deps.transaction(async db => {
        const userId = await requireUser(request, db);
        await setSuperChoice(db, deps.campaignId, userId, request.body?.choice);
        return lotteryState(db, deps.campaignId, userId);
      }));

  app.post('/lottery/api/logout', { preHandler: sameOrigin }, async (request, reply) => {
    const token = cookies(request).get(SESSION_COOKIE);
    if (token) await deps.transaction(db => endSession(db, token));
    setCookie(reply, SESSION_COOKIE, '', 0);
    return { ok: true };
  });
}
