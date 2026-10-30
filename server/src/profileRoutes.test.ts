import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import type { PoolClient } from 'pg';
import sharp from 'sharp';
import { registerProfileRoutes } from './profileRoutes.js';
import { MembershipError, MembershipSku } from './membershipPolicy.js';
import { prepareAvatarBase64, InvalidAvatarError, MAX_ANIMATED_AVATAR_BYTES } from './imageSecurity.js';

const id = 'd105489a-3d17-4f18-af36-7a15e5e1b3ae';
async function animation(format: 'gif' | 'webp' = 'gif', frames = 2, width = 32, height = 16) {
  const raw = Buffer.alloc(width * height * frames * 3);
  for (let frame = 0; frame < frames; frame++) {
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
      // Left stays green; right alternates red/blue to verify cropping on every frame.
      const channel = x < width / 2 ? 1 : frame % 2 === 0 ? 0 : 2;
      raw[((frame * height + y) * width + x) * 3 + channel] = 255;
    }
  }
  const image = sharp(raw, { raw: { width, height: height * frames, pageHeight: height, channels: 3 } });
  const options = { loop: 3, delay: Array.from({ length: frames }, (_, i) => i % 2 ? 130 : 70) };
  return format === 'gif' ? image.gif(options).toBuffer() : image.webp(options).toBuffer();
}

test('animation crop preserves every frame, timing and loop count for GIF and WebP', async () => {
  for (const format of ['gif', 'webp'] as const) {
    const input = await animation(format);
    const output = await prepareAvatarBase64(input.toString('base64'), true, { left: 16, top: 0, size: 16 });
    assert.equal(output.mime, 'image/gif');
    const metadata = await sharp(output.data, { animated: true }).metadata();
    assert.equal(metadata.pages, 2);
    assert.equal(metadata.width, 256);
    assert.equal(metadata.pageHeight, 256);
    assert.deepEqual(metadata.delay, [70, 130]);
    assert.equal(metadata.loop, 3);
    for (const page of [0, 1]) {
      const pixel = await sharp(output.data, { page, pages: 1 }).resize(1, 1).removeAlpha().raw().toBuffer();
      assert.ok(pixel[page === 0 ? 0 : 2]! > 240, 'right-side colour survives on each frame');
      assert.ok(pixel[1]! < 20, 'left-side green must be cropped out');
    }
  }
});

test('animation rejects malformed crop, excessive frames, pixels and upload bytes', async () => {
  const gif = (await animation()).toString('base64');
  for (const crop of [{ left: -1, top: 0, size: 10 }, { left: 0, top: 0, size: 100 },
    { left: 0, top: 0, size: 1.5 }, { left: 0, top: 0, size: NaN }]) {
    await assert.rejects(prepareAvatarBase64(gif, true, crop), InvalidAvatarError);
  }
  await assert.rejects(prepareAvatarBase64((await animation('gif', 121)).toString('base64'), true), InvalidAvatarError);
  await assert.rejects(prepareAvatarBase64((await animation('gif', 2, 1025, 2)).toString('base64'), true), InvalidAvatarError);
  const largeCanvas = await animation('gif', 33, 2, 2);
  largeCanvas.writeUInt16LE(1024, 6);
  largeCanvas.writeUInt16LE(1024, 8);
  await assert.rejects(prepareAvatarBase64(largeCanvas.toString('base64'), true), InvalidAvatarError);
  await assert.rejects(prepareAvatarBase64(Buffer.alloc(MAX_ANIMATED_AVATAR_BYTES + 1).toString('base64'), true), InvalidAvatarError);
  await assert.rejects(prepareAvatarBase64('not a picture', true), InvalidAvatarError);
});

test('profile HTTP enforces permanent entitlement, stores GIF MIME, and falls back after restriction', async t => {
  const app = Fastify({ bodyLimit: 512 * 1024 });
  t.after(() => app.close());
  let sku: MembershipSku | null = null;
  let debt = 0;
  let expired = false;
  let future = false;
  let revokeBeforeWrite = false;
  let saved: { avatar_data: Buffer; avatar_mime: string } | null = null;
  let name = '';
  let writes = 0;
  const db = { query: async (sql: string, args: unknown[]) => {
    if (sql.includes('FROM membership_accounts')) return { rows: sku ? [{ id: 'period', sku,
      anchor_at: new Date(Date.now() + (future ? 60000 : -1000)),
      expires_at: expired ? new Date(0) : ['LIFETIME', 'SUPER_LIFETIME'].includes(sku) ? null : new Date(Date.now() + 60000),
      paid_months: 1, permanent_credit_points: '1290', revision: 1 }] : [] };
    if (sql.includes('FROM account_debts')) return { rows: [{ iap_debt_points: String(debt) }] };
    if (sql.includes('FROM membership_orders')) return { rows: [{ sku }] };
    if (sql.includes('FROM membership_gift_claims') || sql.includes('FROM cloud_quota_bonuses') ||
      sql.includes('pg_advisory_xact_lock')) return { rows: [] };
    if (sql.includes('SELECT avatar_data')) return { rows: saved ? [saved] : [] };
    if (sql.startsWith('UPDATE app_users')) {
      writes++;
      name = args[1] as string;
      if (sql.includes('avatar_data = NULL')) saved = null;
      else if (sql.includes('avatar_data = $3')) saved = { avatar_data: args[2] as Buffer, avatar_mime: args[3] as string };
      return { rows: [] };
    }
    throw new Error('Unexpected query: ' + sql);
  } } as unknown as PoolClient;
  registerProfileRoutes(app, { db, membershipEnabled: true,
    authenticate: async (req, reply) => { if (req.headers.authorization !== 'Bearer test') await reply.code(401).send(); },
    userId: () => id, limit: async () => {}, account: async () => ({ displayName: name }),
    transaction: async work => { if (revokeBeforeWrite) debt = 1; return work(db); }
  });
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
    throw error;
  });
  const gif = (await animation()).toString('base64');
  const post = (body: Record<string, unknown>, authorized = true) => app.inject({ method: 'POST', url: '/v1/me/profile',
    headers: authorized ? { authorization: 'Bearer test' } : {}, payload: { displayName: '读者', ...body } });
  assert.equal((await post({ avatarBase64: gif }, false)).statusCode, 401);
  for (const tier of [null, 'MONTHLY', 'ANNUAL'] as const) {
    sku = tier;
    const response = await post({ avatarBase64: gif, membership: { sku: 'SUPER_LIFETIME' }, allowAnimated: true });
    assert.equal(response.statusCode, 403);
    assert.equal(response.json().code, 'ANIMATED_AVATAR_MEMBERSHIP_REQUIRED');
  }
  assert.equal(writes, 0);
  for (const tier of ['LIFETIME', 'SUPER_LIFETIME'] as const) {
    sku = tier;
    assert.equal((await post({ avatarBase64: gif, avatarCrop: { left: 16, top: 0, size: 16 } })).statusCode, 200);
    const response = await app.inject('/v1/avatars/' + id);
    assert.equal(response.headers['content-type'], 'image/gif');
    assert.equal((await sharp(response.rawPayload).metadata()).pages, 2);
  }
  // Valid GIF comments exceed the app-wide 512KB request limit, without costly test imagery.
  // The profile route must accept its own larger limit and strip non-image metadata.
  const sourceGif = Buffer.from(gif, 'base64');
  const padded = Buffer.concat([sourceGif.subarray(0, -1), Buffer.from([0x21, 0xfe]),
    ...Array.from({ length: 2200 }, () => Buffer.concat([Buffer.from([255]), Buffer.alloc(255, 65)])),
    Buffer.from([0, 0x3b])]);
  assert.equal((await post({ avatarBase64: padded.toString('base64') })).statusCode, 200);
  assert.ok((await app.inject('/v1/avatars/' + id)).rawPayload.length < 10000);
  assert.equal((await post({ avatarBase64: 'A'.repeat(3 * 1024 * 1024) })).statusCode, 413);
  debt = 1;
  assert.equal((await post({ avatarBase64: gif })).statusCode, 403);
  const fallback = await app.inject('/v1/avatars/' + id);
  assert.equal(fallback.headers['content-type'], 'image/jpeg');
  assert.equal(fallback.headers['cache-control'], 'no-store');
  assert.equal((await sharp(fallback.rawPayload).metadata()).format, 'jpeg');
  debt = 0;
  expired = true;
  assert.equal((await post({ avatarBase64: gif })).statusCode, 403);
  expired = false;
  future = true;
  assert.equal((await post({ avatarBase64: gif })).statusCode, 403);
  future = false;
  revokeBeforeWrite = true;
  const before = writes;
  assert.equal((await post({ avatarBase64: gif })).statusCode, 403);
  assert.equal(writes, before, 'entitlement is rechecked after encoding and before writing');
  revokeBeforeWrite = false;
  const png = await sharp({ create: { width: 16, height: 16, channels: 3, background: 'red' } }).png().toBuffer();
  assert.equal((await post({ avatarBase64: png.toString('base64') })).statusCode, 200, 'static upload still works with debt');
  assert.equal((await app.inject('/v1/avatars/' + id)).headers['content-type'], 'image/jpeg');
  assert.equal((await post({ displayName: '改名' })).json().displayName, '改名');
  assert.equal((await post({ removeAvatar: true })).statusCode, 200);
  assert.equal((await app.inject('/v1/avatars/' + id)).statusCode, 404);
  assert.equal((await app.inject('/v1/avatars/not-a-uuid')).statusCode, 404);
});

test('disabling membership fails closed for animation while keeping static uploads', async t => {
  const app = Fastify();
  t.after(() => app.close());
  const db = { query: async () => ({ rows: [] }) } as unknown as PoolClient;
  registerProfileRoutes(app, { db, membershipEnabled: false, authenticate: async () => {},
    userId: () => id, limit: async () => {}, account: async () => ({}), transaction: async work => work(db) });
  const response = await app.inject({ method: 'POST', url: '/v1/me/profile', payload: {
    displayName: '读者', avatarBase64: (await animation()).toString('base64')
  } });
  assert.equal(response.statusCode, 403);
});
