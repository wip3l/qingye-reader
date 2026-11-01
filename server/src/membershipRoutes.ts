import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { PoolClient } from 'pg';
import type { MembershipSalesPilot } from './membershipSales.js';
import { claimSuperTheme } from './superThemeService.js';
import { MEMBERSHIP_PRODUCTS, MembershipError, MembershipSku, VoiceTier } from './membershipPolicy.js';
import { claimMembershipGift, membershipCatalog, membershipPriority, membershipSnapshot, purchaseMembership, quoteMembership,
  readMembership } from './membershipService.js';

interface MembershipRouteDependencies {
  enabled: boolean;
  superEnabled: boolean;
  salesPilot?: MembershipSalesPilot;
  authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  userId: (request: FastifyRequest) => string;
  transaction: <T>(work: (client: PoolClient) => Promise<T>) => Promise<T>;
  limit: (userId: string) => Promise<void>;
  account: (client: PoolClient, userId: string) => Promise<unknown>;
  wallet: (client: PoolClient, userId: string) => Promise<unknown>;
}

export function registerMembershipRoutes(app: FastifyInstance, deps: MembershipRouteDependencies): void {
  function requireEnabled() {
    if (!deps.enabled) throw new MembershipError(503, 'MEMBERSHIP_UNAVAILABLE', '会员服务正在准备中');
  }
  const catalog = async (userId?: string) => ({
    products: deps.enabled
      ? (await deps.transaction(client => membershipCatalog(client, userId, Date.now(), deps.salesPilot))).map(product => ({ ...product,
        salesEnabled: product.salesEnabled && (product.sku !== 'SUPER_LIFETIME' || deps.superEnabled) }))
      : MEMBERSHIP_PRODUCTS.map(product => ({ ...product, salesEnabled: false })),
    paidPointsOnly: true,
    autoRenew: false
  });
  app.get('/v1/membership/catalog', async (_request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    return catalog();
  });
  app.get('/v1/membership/catalog/account', { preHandler: deps.authenticate }, async (request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    return catalog(deps.userId(request));
  });
  app.get('/v1/membership', { preHandler: deps.authenticate }, async request => {
    requireEnabled();
    return deps.transaction(client => membershipSnapshot(client, deps.userId(request)));
  });
  app.get('/v1/membership/orders', { preHandler: deps.authenticate }, async request => {
    requireEnabled();
    return deps.transaction(async client => {
      const result = await client.query(`SELECT id,sku,list_points::integer AS "listPoints",
        credit_points::integer AS "creditPoints",points_spent::integer AS "pointsSpent",
        (extract(epoch FROM created_at)*1000)::bigint AS "createdAt"
        FROM membership_orders WHERE user_id=$1 ORDER BY created_at DESC,id DESC LIMIT 50`, [deps.userId(request)]);
      return { orders: result.rows };
    });
  });
  app.post<{ Body: { sku: MembershipSku } }>('/v1/membership/quote', { preHandler: deps.authenticate }, async request => {
    requireEnabled();
    const userId = deps.userId(request);
    await deps.limit(userId);
    if (request.body?.sku === 'SUPER_LIFETIME' && !deps.superEnabled) {
      throw new MembershipError(503, 'CLOUD_NOT_CONFIGURED', '超级会员云服务尚未启用，暂不开放购买');
    }
    return deps.transaction(client => quoteMembership(client, userId, request.body?.sku, Date.now(), deps.salesPilot));
  });
  app.post<{ Body: { quoteId: string; requestId: string } }>('/v1/membership/purchase',
    { preHandler: deps.authenticate }, async request => {
      requireEnabled();
      const userId = deps.userId(request);
      await deps.limit(userId);
      return deps.transaction(async client => {
        if (!deps.superEnabled && typeof request.body?.quoteId === 'string') {
          const pending = await client.query(`SELECT 1 FROM membership_quotes q WHERE q.id::text=$1
            AND q.user_id=$2 AND q.plan->>'sku'='SUPER_LIFETIME'
            AND NOT EXISTS(SELECT 1 FROM membership_orders o WHERE o.quote_id=q.id)`, [request.body.quoteId, userId]);
          if (pending.rowCount) throw new MembershipError(503, 'CLOUD_NOT_CONFIGURED', '超级会员云服务尚未启用，暂不开放购买');
        }
        const order = await purchaseMembership(client, userId, request.body?.quoteId, request.body?.requestId,
          Date.now(), deps.salesPilot);
        return { ...order, account: await deps.account(client, userId), membership: await membershipSnapshot(client, userId) };
      });
    });
  app.post<{ Body: { tier: VoiceTier } }>('/v1/membership/gift', { preHandler: deps.authenticate }, async request => {
    requireEnabled();
    const userId = deps.userId(request);
    await deps.limit(userId);
    return deps.transaction(async client => ({
      claim: await claimMembershipGift(client, userId, request.body?.tier),
      membership: await membershipSnapshot(client, userId),
      ttsWallet: await deps.wallet(client, userId)
    }));
  });
  // The operator's own MiMo key, filled into the app for lifetime members. It is handed to the device
  // as-is (the operator chose this over a proxy), so every grant is recorded for leak tracing.
  app.post('/v1/membership/mimo-key', { preHandler: deps.authenticate, bodyLimit: 1024 }, async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    requireEnabled();
    const userId = deps.userId(request);
    await deps.limit(userId);
    return deps.transaction(async client => {
      const state = await readMembership(client, userId);
      // A null expiry is a lifetime period; membershipPriority also rejects refund debt.
      if (!state || state.expiresAt !== null || !(await membershipPriority(client, userId))) {
        throw new MembershipError(403, 'LIFETIME_MEMBERSHIP_REQUIRED', '一键填充仅限终身会员');
      }
      const key = await client.query<{ api_key: string }>(
        `SELECT api_key FROM shared_provider_keys WHERE provider = 'mimo' AND enabled`);
      const apiKey = key.rows[0]?.api_key;
      if (!apiKey) throw new MembershipError(503, 'SHARED_KEY_UNAVAILABLE', '暂未提供共享密钥，请稍后再试');
      await client.query(`INSERT INTO shared_provider_key_grants(provider, user_id) VALUES ('mimo', $1)
        ON CONFLICT (provider, user_id) DO UPDATE SET last_granted_at = now(),
          grant_count = shared_provider_key_grants.grant_count + 1`, [userId]);
      return { apiKey };
    });
  });
  app.post<{ Params: { themeId: string }; Body: { requestId: string } }>(
    '/v1/membership/themes/:themeId/claim', { preHandler: deps.authenticate }, async request => {
      requireEnabled();
      const userId = deps.userId(request);
      await deps.limit(userId);
      return deps.transaction(async client => {
        const claim = await claimSuperTheme(client, userId, request.params.themeId, request.body?.requestId);
        return { claim, account: await deps.account(client, userId) };
      });
    });
}
