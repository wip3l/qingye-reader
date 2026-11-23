import assert from 'node:assert/strict';
import test from 'node:test';
import sharp from 'sharp';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';

process.env.DATABASE_URL ||= 'postgresql://test:test@127.0.0.1:5432/test';
process.env.SESSION_SECRET ||= 'test-session-secret-that-is-long-enough';
process.env.HUAWEI_CLIENT_ID ||= 'test-client';
process.env.HUAWEI_CLIENT_SECRET ||= 'test-secret';
process.env.HUAWEI_APP_ID ||= 'test-app';
process.env.HUAWEI_IAP_KEY_ID ||= 'test-key';
process.env.HUAWEI_IAP_ISSUER_ID ||= 'test-issuer';
process.env.HUAWEI_IAP_PRIVATE_KEY_PATH ||= 'test-private-key.pem';
process.env.HUAWEI_IAP_ROOT_CA_PATH ||= 'test-root-ca.pem';
process.env.HUAWEI_IAP_ROOT_URL ||= 'https://example.invalid';
process.env.HUAWEI_IAP_DELIVERABLE_STATUSES = '0,PAID';
process.env.HUAWEI_IAP_REVOCATION_STATUSES = '2,REFUNDED';

const {
  isDeliverablePurchaseState,
  isRevokedPurchaseState
} = await import('./iap.js');
const { InvalidAvatarError, sanitizeAvatarBase64 } = await import('./imageSecurity.js');
const { calculateIapReversal } = await import('./iapReconciliation.js');
const { AccountRateLimitError } = await import('./security.js');

test('production global limiter and error handler return numeric 429 retry guidance, not 500', async t => {
  const app = Fastify();
  t.after(() => app.close());
  const source = await readFile(new URL('./index.js', import.meta.url), 'utf8');
  const registrationStart = source.indexOf('await app.register(rateLimit, {');
  const registration = source.slice(registrationStart + 6, source.indexOf('\n});', registrationStart) + 4);
  const handlerStart = source.indexOf('app.setErrorHandler(');
  const handler = source.slice(handlerStart, source.indexOf('\n});', handlerStart) + 4);
  assert.ok(registrationStart >= 0 && handlerStart >= 0);
  const sandbox = vm.createContext({ app, rateLimit, AccountRateLimitError,
    config: { http: { globalRateLimitPerMinute: 2 } },
    ApiError: class extends Error {}, MembershipError: class extends Error {}, SyncApiError: class extends Error {},
    AccountAuthError: class extends Error {}, PointCreditError: class extends Error {},
    Error });
  await vm.runInContext(registration, sandbox);
  vm.runInContext(handler, sandbox);
  app.post('/v1/cloud-files/test/upload-ticket', async () => ({ ready: false }));
  for (let n = 0; n < 2; n++) {
    assert.equal((await app.inject({ method: 'POST', url: '/v1/cloud-files/test/upload-ticket' })).statusCode, 200);
  }
  const limited = await app.inject({ method: 'POST', url: '/v1/cloud-files/test/upload-ticket' });
  assert.equal(limited.statusCode, 429);
  const body = limited.json();
  assert.equal(body.code, 'RATE_LIMITED');
  assert.equal(typeof body.retryAfter, 'number');
  assert.ok(body.retryAfter >= 1 && body.retryAfter <= 60);
  assert.equal(Number(limited.headers['retry-after']), body.retryAfter);
});

test('IAP purchase states fail closed', () => {
  assert.equal(isDeliverablePurchaseState({ purchaseState: 0 }), true);
  assert.equal(isDeliverablePurchaseState({ purchaseState: -1 }), false);
  assert.equal(isDeliverablePurchaseState({ purchaseState: 1 }), false);
  assert.equal(isDeliverablePurchaseState({ purchaseState: 2 }), false);
  assert.equal(isDeliverablePurchaseState({ purchaseState: 3 }), false);
  assert.equal(isRevokedPurchaseState({ purchaseState: 2 }), true);
  assert.equal(isDeliverablePurchaseState({ purchaseState: 1, purchaseStatus: 0 }), false);

  // Keep accepting legacy payload aliases, but only when purchaseState is absent.
  assert.equal(isDeliverablePurchaseState({ purchaseStatus: 0 }), true);
  assert.equal(isDeliverablePurchaseState({ purchaseStatus: 'PAID' }), true);
  assert.equal(isDeliverablePurchaseState({}), false);
  assert.equal(isDeliverablePurchaseState({ purchaseStatus: 'UNKNOWN' }), false);
  assert.equal(isDeliverablePurchaseState({ finishStatus: 0 }), true);
  assert.equal(isDeliverablePurchaseState({ finishStatus: '0' }), true);
  assert.equal(isDeliverablePurchaseState({ finishStatus: 2 }), true);
  assert.equal(isDeliverablePurchaseState({ finishStatus: '2' }), true);
  assert.equal(isDeliverablePurchaseState({ finishStatus: 1 }), false);
  assert.equal(isDeliverablePurchaseState({ finishStatus: 3 }), false);
  assert.equal(isDeliverablePurchaseState({ finishStatus: 0, purchaseState: 1 }), false);
  assert.equal(isDeliverablePurchaseState({
    finishStatus: 2,
    purchaseOrderRevocationReasonCode: 7
  }), false);
  assert.equal(isRevokedPurchaseState({
    finishStatus: 2,
    purchaseOrderRevocationReasonCode: '7'
  }), true);
  assert.equal(isRevokedPurchaseState({ purchaseStatus: 2 }), true);
});

test('IAP reversal restores prior debt without taking unrelated paid points', () => {
  assert.deepEqual(calculateIapReversal(100, 50, 100), {
    reversedPoints: 50,
    debtPoints: 50
  });
  assert.deepEqual(calculateIapReversal(100, 0, 20), {
    reversedPoints: 20,
    debtPoints: 80
  });
});

test('avatar uploads are decoded, resized and re-encoded as metadata-free JPEG', async () => {
  const input = await sharp({
    create: { width: 32, height: 24, channels: 3, background: '#336699' }
  }).png().toBuffer();
  const output = await sanitizeAvatarBase64(input.toString('base64'));
  const metadata = await sharp(output).metadata();
  assert.equal(metadata.format, 'jpeg');
  assert.equal(metadata.width, 32);
  assert.equal(metadata.height, 24);
});

test('avatar uploads reject non-images', async () => {
  await assert.rejects(
    sanitizeAvatarBase64(Buffer.from('not an image').toString('base64')),
    InvalidAvatarError
  );
});
