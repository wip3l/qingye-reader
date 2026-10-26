import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import { registerComicColorModelRoutes } from './comicColorModelRoutes.js';
import { COMIC_COLOR_MODELS, comicColorObjectKey } from './comicColorModels.js';
import type { CloudObjectStore } from './cloudObjectStore.js';

test('model tickets authenticate, constrain object keys, check availability and never expose secrets', async () => {
  let calls = 0, size = COMIC_COLOR_MODELS[0].bytes as number;
  const store: CloudObjectStore = {
    signDownload(key, seconds) { assert.equal(key, comicColorObjectKey(COMIC_COLOR_MODELS[0]));
      assert.equal(seconds, 1800); return 'https://models.example/signed'; },
    async head() { calls++; return { bytes: size, etag: 'etag' }; },
    signUpload() { throw new Error('Unused'); }, async copy() {}, async delete() {}
  };
  const app = Fastify();
  let limits = 0;
  registerComicColorModelRoutes(app, store, {
    async authenticate(request, reply) { if (request.headers.authorization !== 'Bearer test') reply.code(401).send({}); },
    userId: () => 'test', limit: async () => { limits++; }
  });
  const url = '/v1/ai/color-models/alac.ms/download-ticket';
  assert.equal((await app.inject({ method: 'POST', url })).statusCode, 401);
  assert.equal(calls, 0); assert.equal(limits, 0);
  const headers = { authorization: 'Bearer test' };
  assert.equal((await app.inject({ method: 'POST', url: url.replace('alac.ms', 'other.ms'), headers })).statusCode, 404);
  assert.equal(calls, 0);
  const response = await app.inject({ method: 'POST', url, headers });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.equal(response.json().sha256, COMIC_COLOR_MODELS[0].sha256);
  size = 0;
  assert.equal((await app.inject({ method: 'POST', url, headers })).statusCode, 503);
  await app.close();
  const unavailable = Fastify();
  registerComicColorModelRoutes(unavailable, null, { async authenticate() {}, userId: () => 'test', async limit() {} });
  assert.equal((await unavailable.inject({ method: 'POST', url })).statusCode, 503);
  await unavailable.close();
});
