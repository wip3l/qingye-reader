import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import Fastify from 'fastify';
import { createObsStore } from './cloudObjectStore.js';
import { registerCloudFileRoutes } from './cloudFileRoutes.js';
import { PGlite } from '@electric-sql/pglite';
import { CloudFileService, CLOUD_CHUNK_BYTES, CLOUD_QUOTA_BYTES } from './cloudFileService.js';
import { MembershipDb, purchaseMembership, quoteMembership } from './membershipService.js';
import { sourceQuotaError } from './sourceQuota.js';
import { membershipAnniversary } from './membershipPolicy.js';

test('OBS presigned URLs bind method, object, upload MD5 and expiry without network IO', () => {
  const options = { endpoint: 'https://obs.cn-north-4.myhuaweicloud.com', bucket: 'test-private',
    region: 'cn-north-4', ak: 'test-ak', sk: 'test-signing-secret' };
  const store = createObsStore(options);
  const key = 'qingye/staging/v1/user/file/0', md5 = createHash('md5').update('abc').digest('base64');
  const before = Math.floor(Date.now() / 1000);
  const put = new URL(store.signUpload(key, md5, 120));
  assert.equal(put.protocol, 'https:');
  assert.equal(put.hostname, 'test-private.obs.cn-north-4.myhuaweicloud.com');
  assert.equal(put.pathname, `/${key}`);
  const expiry = Number(put.searchParams.get('Expires'));
  assert.ok(expiry >= before + 120 && expiry <= Math.floor(Date.now() / 1000) + 120);
  const expected = createHmac('sha1', options.sk).update(`PUT\n${md5}\napplication/octet-stream\n${expiry}\n/${options.bucket}/${key}`).digest('base64');
  assert.equal(put.searchParams.get('Signature'), expected);
  assert.equal(put.searchParams.get('AccessKeyId'), options.ak);
  const get = new URL(store.signDownload('qingye/v1/user/file/0', 60));
  assert.equal(get.searchParams.get('response-cache-control'), 'no-store');
  const getExpected = createHmac('sha1', options.sk).update(`GET\n\n\n${get.searchParams.get('Expires')}\n/${options.bucket}/qingye/v1/user/file/0?response-cache-control=no-store`).digest('base64');
  assert.equal(get.searchParams.get('Signature'), getExpected);
  assert.throws(() => createObsStore({ ...options, endpoint: 'http://obs.example.test' }));
});

test('OBS copy rejects HTTP 200 without a success body', async t => {
  const ObsClient = createRequire(import.meta.url)('esdk-obs-nodejs');
  let response: { CommonMsg: { Status: number }; InterfaceResult?: { ETag: string } } = { CommonMsg: { Status: 200 } };
  t.mock.method(ObsClient.prototype, 'copyObject', async () => response);
  const store = createObsStore({ endpoint: 'https://obs.cn-south-1.myhuaweicloud.com',
    bucket: 'test-private', region: 'cn-south-1', ak: 'test-ak', sk: 'test-secret' });
  const etag = createHash('md5').update('test').digest('hex');
  await assert.rejects(store.copy('source', 'destination', etag), /no object ETag/);
  response = { CommonMsg: { Status: 200 }, InterfaceResult: { ETag: '"etag"' } };
  await store.copy('source', 'destination', etag);
  response = { CommonMsg: { Status: 412 } };
  await assert.rejects(store.copy('source', 'destination', etag), /412/);
});

test('OBS copy serializes a bare MD5 condition and refuses wildcard or ambiguous ETags', async t => {
  const ObsClient = createRequire(import.meta.url)('esdk-obs-nodejs');
  const headers: Array<Record<string, string>> = [];
  t.mock.method(ObsClient.prototype, 'copyObject', function(this: {
    util: { makeParam(method: string, params: object): { headers: Record<string, string> } }
  }, params: object) {
    headers.push(this.util.makeParam('CopyObject', params).headers);
    return Promise.resolve({ CommonMsg: { Status: 200 }, InterfaceResult: { ETag: 'result' } });
  });
  const store = createObsStore({ endpoint: 'https://obs.cn-south-1.myhuaweicloud.com',
    bucket: 'test-private', region: 'cn-south-1', ak: 'test-ak', sk: 'test-secret' });
  const etag = createHash('md5').update('test').digest('hex');
  await store.copy('source', 'destination', `"${etag}"`);
  await store.copy('source', 'destination', etag);
  assert.deepEqual(headers.map(h => h['x-obs-copy-source-if-match']), [etag, etag]);
  for (const invalid of ['', '*', `W/"${etag}"`, `"${etag}`, `${etag}-2`, `${etag},${etag}`]) {
    await assert.rejects(store.copy('source', 'destination', invalid), /single-PUT MD5 ETag/);
  }
  assert.equal(headers.length, 2);
});

test('source limits allow old data to shrink and reject growth/new excess sources', () => {
  const quota = { count: 60, maxCount: 50, maxBytes: 50 * 1024 };
  assert.equal(sourceQuotaError(quota, true, 100000, 90000), null);
  assert.equal(sourceQuotaError(quota, true, 100000, 0), null);
  assert.ok(sourceQuotaError(quota, true, 100000, 100001));
  assert.ok(sourceQuotaError(quota, false, 0, 1000));
  assert.equal(sourceQuotaError({ count: 10000, maxCount: null, maxBytes: null }, false, 0, 900000), null);
});

test('cloud files: isolation, reservations, integrity, retries and quota enforcement', async t => {
  const db = new PGlite(); t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const path of (await readdir(migrations)).filter(p => p.endsWith('.sql')).sort()) {
    await db.exec((await readFile(new URL(path, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  }
  const tx = <T>(fn: (client: MembershipDb) => Promise<T>) => db.transaction(client =>
    fn({ query: client.query.bind(client) as unknown as MembershipDb['query'] }));
  await db.exec('UPDATE membership_products SET sales_enabled=true');
  const now = Date.parse('2028-01-15T10:00:00+08:00');
  let clock = now + 1000;
  const users = [randomUUID(), randomUUID(), randomUUID()];
  for (const id of users) {
    await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [id, id]);
    await db.query('INSERT INTO point_wallets(user_id,balance,paid_balance) VALUES($1,10000,10000)', [id]);
  }
  for (const id of users.slice(0, 2)) {
    const quote = await tx(c => quoteMembership(c, id, 'SUPER_LIFETIME', now));
    await tx(c => purchaseMembership(c, id, quote.quoteId, randomUUID(), now));
  }
  const [owner, stranger, free] = users as [string, string, string];
  const objects = new Map<string, Buffer>();
  let failSign = false;
  const hash = (body: Buffer, algorithm = 'sha256') => createHash(algorithm).update(body).digest('hex');
  const keyOf = (url: string) => new URL(url).pathname.slice(1);
  const service = new CloudFileService(tx, {
    signUpload(key, md5, seconds) { return `https://obs.test/${key}?md5=${md5}&ttl=${seconds}`; },
    signDownload(key, seconds) { if (failSign) throw new Error('signing unavailable'); return `https://obs.test/${key}?ttl=${seconds}`; },
    async head(key) {
      const body = objects.get(key);
      if (!body) throw new Error('not found');
      return { bytes: body.length, etag: `"${hash(body, 'md5')}"` };
    },
    async copy(source, target, etag) {
      const body = objects.get(source)!;
      assert.equal(etag, `"${hash(body, 'md5')}"`);
      objects.set(target, Buffer.from(body));
    },
    async delete(key) { objects.delete(key); }
  }, () => clock);
  const chunkInput = (index: number, body: Buffer) => ({ index, bytes: body.length, sha256: hash(body),
    md5: createHash('md5').update(body).digest('base64') });
  const putChunk = async (user: string, id: string, index: number, body: Buffer) => {
    const ticket = await service.uploadTicket(user, id, chunkInput(index, body));
    if (!ticket.ready) objects.set(keyOf(ticket.url!), Buffer.from(body)); // Simulated App -> OBS PUT.
    return service.confirmChunk(user, id, index);
  };
  const downloadChunk = (user: string, id: string, index: number, requestId = randomUUID()) => service.downloadTicket(user, id, index, requestId);
  const input = { requestId: randomUUID(), kind: 'BOOK', name: '测试.txt', bytes: CLOUD_CHUNK_BYTES + 3 };
  await assert.rejects(service.prepare(owner, { ...input, kind: 'SOURCE', name: '书源.json' }),
    { code: 'CLOUD_SOURCE_SYNC_ONLY' });
  assert.equal((await service.summary(owner)).usedBytes, 0, 'source file rejection must not reserve storage');
  await assert.rejects(service.prepare(free, input), { code: 'CLOUD_SUPER_REQUIRED' });
  const upload = await service.prepare(owner, input);
  assert.equal((await service.prepare(owner, input)).id, upload.id);
  assert.equal((await service.summary(owner)).usedBytes, input.bytes);
  await assert.rejects(service.manifest(stranger, upload.id), { code: 'CLOUD_FILE_NOT_FOUND' });
  await assert.rejects(putChunk(owner, upload.id, 0, Buffer.alloc(2)), { code: 'CLOUD_CHUNK_SIZE' });
  const block = Buffer.alloc(CLOUD_CHUNK_BYTES, 42);
  await putChunk(owner, upload.id, 0, block);
  await putChunk(owner, upload.id, 0, block);
  assert.equal(objects.size, 2); // Staging and immutable published chunk.
  await assert.rejects(putChunk(owner, upload.id, 0, Buffer.alloc(CLOUD_CHUNK_BYTES, 43)), { code: 'CLOUD_CHUNK_CHANGED' });
  await assert.rejects(service.complete(owner, upload.id), { code: 'CLOUD_UPLOAD_INCOMPLETE' });
  await putChunk(owner, upload.id, 1, Buffer.from('abc'));
  const staged = (await db.query<{object_key: string}>('SELECT object_key FROM cloud_chunks WHERE file_id=$1 AND chunk_index=1', [upload.id])).rows[0]!.object_key.replace('qingye/v1/', 'qingye/staging/v1/');
  objects.set(staged, Buffer.from('bad')); // Even a changed temporary object cannot mutate already published bytes.
  await service.confirmChunk(owner, upload.id, 1);
  assert.equal(objects.get(staged.replace('qingye/staging/v1/', 'qingye/v1/'))!.toString(), 'abc');
  await assert.rejects(service.uploadTicket(stranger, upload.id, chunkInput(1, Buffer.from('abc'))), { code: 'CLOUD_FILE_NOT_FOUND' });
  const completed = await service.complete(owner, upload.id);
  assert.equal(completed.id, upload.id);
  const deduplicated = await service.prepare(owner, { ...input, requestId: randomUUID(), manifestHash: completed.manifestHash! });
  assert.equal(deduplicated.id, upload.id);
  const isolated = await service.prepare(stranger, { ...input, requestId: randomUUID(), manifestHash: completed.manifestHash! });
  assert.notEqual(isolated.id, upload.id);
  await service.remove(stranger, isolated.id);
  assert.equal((await service.complete(owner, upload.id)).id, upload.id);
  await assert.rejects(putChunk(owner, upload.id, 1, Buffer.from('abc')), { code: 'CLOUD_UPLOAD_CLOSED' });
  const app = Fastify(); t.after(() => app.close());
  registerCloudFileRoutes(app, service, { authenticate: async () => {}, userId: () => owner, limit: async () => {} });
  const beforeMetadata = await service.summary(owner);
  const metadataResponse = await app.inject({ method: 'POST', url: `/v1/cloud-files/${upload.id}/metadata`,
    payload: { meta: { mediaCategory: 'comic' } } });
  assert.equal(metadataResponse.statusCode, 200);
  assert.equal((await service.manifest(owner, upload.id)).meta?.mediaCategory, 'comic');
  await service.fillMetadata(owner, upload.id, { mediaCategory: 'novel' });
  assert.equal((await service.list(owner)).files.find(f => f.id === upload.id)!.meta?.mediaCategory, 'comic');
  assert.equal((await service.summary(owner)).usedBytes, beforeMetadata.usedBytes);
  assert.equal((await service.summary(owner)).downloadBytes, beforeMetadata.downloadBytes);
  await assert.rejects(service.fillMetadata(stranger, upload.id, { mediaCategory: 'comic' }), { code: 'CLOUD_FILE_NOT_FOUND' });
  await assert.rejects(service.fillMetadata(free, upload.id, { mediaCategory: 'comic' }), { code: 'CLOUD_SUPER_REQUIRED' });
  await assert.rejects(service.fillMetadata(owner, upload.id, { mediaCategory: 'audio' }), { code: 'CLOUD_INVALID_FILE' });
  await assert.rejects(service.fillMetadata(owner, upload.id, { secret: 'no' }), { code: 'CLOUD_INVALID_FILE' });
  await assert.rejects(service.fillMetadata(owner, upload.id, null), { code: 'CLOUD_INVALID_FILE' });
  assert.equal((await app.inject({ method: 'POST', url: `/v1/cloud-files/${upload.id}/chunks`, payload: { index: 1, data: 'YWJj' } })).statusCode, 404);
  assert.equal((await app.inject({ method: 'GET', url: `/v1/cloud-files/${upload.id}/chunks/1` })).statusCode, 404);
  const apiId = randomUUID();
  const oldPeriod = (await db.query<{ period_id: string }>(
    'SELECT period_id FROM membership_accounts WHERE user_id=$1', [owner])).rows[0]!.period_id;
  // Rollout deliberately gives a fresh 1 GiB; historical anniversary usage is retained for audit.
  await db.query('INSERT INTO cloud_download_usage(user_id,period_id,cycle_index,bytes) VALUES($1,$2,0,$3)',
    [owner, oldPeriod, CLOUD_QUOTA_BYTES]);
  assert.equal((await service.summary(owner)).downloadBytes, 0);
  assert.equal((await service.summary(owner)).cycleEndsAt, Date.parse('2028-02-01T00:00:00+08:00'));
  const legacyId = randomUUID();
  await db.query(`INSERT INTO cloud_download_tickets(user_id,request_id,file_id,chunk_index,period_id,cycle_index,expires_at)
    VALUES($1,$2,$3,1,$4,0,$5)`, [owner, legacyId, upload.id, oldPeriod, new Date(clock + 30000)]);
  // A still-valid old ticket may finish without charging the freshly reset allowance.
  await downloadChunk(owner, upload.id, 1, legacyId);
  assert.equal((await service.summary(owner)).downloadBytes, 0);
  const response = await app.inject({ method: 'POST', url: `/v1/cloud-files/${upload.id}/chunks/1/download-ticket`, payload: { requestId: apiId } });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.equal(response.json().data, undefined);
  assert.match(response.json().url, /^https:/);
  const first = await downloadChunk(owner, upload.id, 1, apiId);
  assert.equal(objects.get(keyOf(first.url))!.toString(), 'abc');
  assert.equal((await service.summary(owner)).downloadBytes, 3);
  const retryId = randomUUID();
  const retryTicket = await downloadChunk(owner, upload.id, 1, retryId);
  const retryExpiry = retryTicket.expiresAt;
  clock += 1000;
  assert.equal((await downloadChunk(owner, upload.id, 1, retryId)).expiresAt, retryExpiry);
  assert.equal((await service.summary(owner)).downloadBytes, 6);
  await assert.rejects(downloadChunk(owner, upload.id, 0, retryId), { code: 'CLOUD_TICKET_CHANGED' });
  await assert.rejects(downloadChunk(stranger, upload.id, 1), { code: 'CLOUD_FILE_NOT_FOUND' });
  clock += 60000;
  await assert.rejects(downloadChunk(owner, upload.id, 1, retryId), { code: 'CLOUD_TICKET_EXPIRED' });
  failSign = true;
  await assert.rejects(downloadChunk(owner, upload.id, 0));
  assert.equal((await service.summary(owner)).downloadBytes, 6);
  failSign = false;
  await db.exec(await readFile(new URL('022_cloud_calendar_downloads.sql', migrations), 'utf8'));
  assert.equal((await service.summary(owner)).downloadBytes, 6); // Rerunning migration never resets usage.
  await db.query('UPDATE cloud_download_monthly_usage SET bytes=$2 WHERE user_id=$1', [owner, CLOUD_QUOTA_BYTES - 2]);
  await assert.rejects(downloadChunk(owner, upload.id, 1), { code: 'CLOUD_TRAFFIC_LIMIT' });
  clock = Date.parse('2028-02-01T00:00:00+08:00');
  assert.equal((await service.summary(owner)).downloadBytes, 0);
  assert.equal((await service.summary(owner)).cycleEndsAt, Date.parse('2028-03-01T00:00:00+08:00'));
  await downloadChunk(owner, upload.id, 1);
  assert.equal((await service.summary(owner)).downloadBytes, 3);
  clock = membershipAnniversary(now, 1);
  assert.equal((await service.summary(owner)).downloadBytes, 3); // No reset on the old opening day.
  // Replacing the paid period cannot reset the account's calendar-month counter.
  const replacement = randomUUID();
  await db.query(`INSERT INTO membership_periods(id,user_id,sku,anchor_at,paid_months,permanent_credit_points)
    VALUES($1,$2,'SUPER_LIFETIME',$3,0,2490)`, [replacement, owner, new Date(clock)]);
  await db.query('UPDATE membership_accounts SET period_id=$2,revision=revision+1 WHERE user_id=$1', [owner,replacement]);
  assert.equal((await service.summary(owner)).downloadBytes, 3);
  clock = Date.parse('2028-03-01T00:00:00+08:00') - 1500;
  const lastId = randomUUID();
  const lastTicket = await downloadChunk(owner, upload.id, 1, lastId);
  assert.equal(lastTicket.expiresAt, Date.parse('2028-03-01T00:00:00+08:00'));
  assert.equal(new URL(lastTicket.url).searchParams.get('ttl'), '1');
  assert.equal((await service.summary(owner)).downloadBytes, 6);
  clock = lastTicket.expiresAt - 500;
  await assert.rejects(downloadChunk(owner, upload.id, 1), {code: 'CLOUD_TICKET_EXPIRED'});
  assert.equal((await service.summary(owner)).downloadBytes, 6); // Subsecond tickets roll back their charge.
  clock = lastTicket.expiresAt;
  await assert.rejects(downloadChunk(owner, upload.id, 1, lastId), {code: 'CLOUD_TICKET_EXPIRED'});
  assert.equal((await service.summary(owner)).downloadBytes, 0);
  await downloadChunk(owner, upload.id, 1);
  assert.equal((await service.summary(owner)).downloadBytes, 3);
  assert.equal(Number((await db.query<{bytes: string}>('SELECT bytes FROM cloud_download_usage WHERE user_id=$1', [owner])).rows[0]!.bytes), CLOUD_QUOTA_BYTES);
  await assert.rejects(service.prepare(owner, { ...input, requestId: randomUUID(), bytes: CLOUD_QUOTA_BYTES }), { code: 'CLOUD_STORAGE_LIMIT' });
  await db.query('INSERT INTO account_debts(user_id,iap_debt_points) VALUES($1,10)', [owner]);
  await assert.rejects(downloadChunk(owner, upload.id, 1), { code: 'CLOUD_SUPER_REQUIRED' });
  await service.remove(stranger, upload.id);
  assert.equal(objects.size, 4); // A foreign account cannot delete or discover this file.
  await service.remove(owner, upload.id);
  await service.remove(owner, upload.id); // Lost delete responses can be retried.
  assert.equal(objects.size, 0);
  assert.equal((await service.summary(owner)).usedBytes, 0);
  assert.equal((await service.list(owner)).files.length, 0);
  const corrupt = await service.prepare(stranger, { requestId: randomUUID(), name: '校验.txt', kind: 'BOOK', bytes: 3 });
  const corruptTicket = await service.uploadTicket(stranger, corrupt.id, chunkInput(0, Buffer.from('abc')));
  objects.set(keyOf(corruptTicket.url!), Buffer.from('bad'));
  await assert.rejects(service.confirmChunk(stranger, corrupt.id, 0), { code: 'CLOUD_CHUNK_INTEGRITY' });
  objects.set(keyOf(corruptTicket.url!), Buffer.from('abcd'));
  await assert.rejects(service.confirmChunk(stranger, corrupt.id, 0), { code: 'CLOUD_CHUNK_INTEGRITY' });
  await service.remove(stranger, corrupt.id);
  assert.equal((await service.summary(stranger)).usedBytes, 3); // Do not free storage while a PUT URL is live.
  await assert.rejects(service.confirmChunk(stranger, corrupt.id, 0), { code: 'CLOUD_UPLOAD_CLOSED' });
  clock += 8 * 60 * 1000;
  await service.maintenance();
  assert.equal((await service.summary(stranger)).usedBytes, 0);
  assert.equal(objects.size, 0);
  const abandoned = await service.prepare(stranger, { requestId: randomUUID(), name: '未完成.txt', kind: 'BOOK', bytes: 1 });
  await putChunk(stranger, abandoned.id, 0, Buffer.from('x'));
  clock += 8 * 60 * 1000;
  await db.query("UPDATE cloud_files SET updated_at=now()-interval '25 hours' WHERE id=$1", [abandoned.id]);
  await service.maintenance();
  assert.equal((await service.summary(stranger)).usedBytes, 0);
  assert.equal(objects.size, 0);
  const manyChunks = 20; // More than one cleanup batch: one delete request must still free all of it.
  const large = await service.prepare(stranger, { requestId: randomUUID(), name: '多块.txt', kind: 'BOOK',
    bytes: (manyChunks - 1) * CLOUD_CHUNK_BYTES + 1 });
  for (let index = 0; index < manyChunks; index++) {
    await putChunk(stranger, large.id, index, index < manyChunks - 1 ? block : Buffer.from('z'));
  }
  await service.complete(stranger, large.id);
  clock += 8 * 60 * 1000;
  await service.remove(stranger, large.id);
  assert.equal((await service.summary(stranger)).usedBytes, 0);
  assert.equal(objects.size, 0);
  // Auto-synced books carry metadata; removal leaves a marker that re-adding the same content clears.
  await assert.rejects(service.prepare(stranger, { requestId: randomUUID(), name: 'x.txt', kind: 'BOOK', bytes: 3,
    meta: { title: 'ok', secret: 'no' } }), { code: 'CLOUD_INVALID_FILE' });
  const bookMeta = { title: '三体', author: '刘慈欣', format: 'txt', contentHash: 'a'.repeat(64), mediaCategory: 'novel' };
  const synced = await service.prepare(stranger, { requestId: randomUUID(), name: '三体.txt', kind: 'BOOK', bytes: 3, meta: bookMeta });
  await putChunk(stranger, synced.id, 0, Buffer.from('xyz'));
  const syncedHash = (await service.complete(stranger, synced.id)).manifestHash!;
  assert.deepEqual((await service.list(stranger)).files.find(f => f.id === synced.id)!.meta, bookMeta);
  assert.deepEqual((await service.manifest(stranger, synced.id)).meta, bookMeta);
  await assert.rejects(service.remove(stranger, synced.id, 'GONE' as never), { code: 'CLOUD_INVALID_REASON' });
  clock += 8 * 60 * 1000;
  await service.remove(stranger, synced.id, 'REMOVED');
  const marker = (await service.tombstones(stranger)).tombstones.find(t => t.id === synced.id)!;
  assert.equal(marker.reason, 'REMOVED');
  assert.equal(marker.manifestHash, syncedHash);
  assert.deepEqual(marker.meta, bookMeta);
  assert.equal((await service.tombstones(owner)).tombstones.some(t => t.id === synced.id), false); // Markers are per account.
  const again = await service.prepare(stranger, { requestId: randomUUID(), name: '三体.txt', kind: 'BOOK', bytes: 3,
    manifestHash: syncedHash, meta: bookMeta });
  await putChunk(stranger, again.id, 0, Buffer.from('xyz'));
  await service.complete(stranger, again.id);
  assert.equal((await service.tombstones(stranger)).tombstones.some(t => t.manifestHash === syncedHash), false);
  clock += 8 * 60 * 1000;
  await service.remove(stranger, again.id); // The cloud files page only drops the cloud copy.
  assert.equal((await service.tombstones(stranger)).tombstones.find(t => t.id === again.id)!.reason, 'DETACHED');
  assert.equal((await new CloudFileService(tx, null).summary(owner)).configured, false);
  await assert.rejects(new CloudFileService(tx, null).prepare(owner, input), { code: 'CLOUD_NOT_CONFIGURED' });
});
