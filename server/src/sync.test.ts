import assert from 'node:assert/strict';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';

process.env.DATABASE_URL ||= 'postgresql://test:test@127.0.0.1:5432/test';
process.env.SESSION_SECRET ||= 'test-session-secret-that-is-long-enough';
process.env.HUAWEI_CLIENT_ID ||= 'test-client';
process.env.HUAWEI_CLIENT_SECRET ||= 'test-secret';
process.env.HUAWEI_APP_ID ||= 'test-app';
process.env.HUAWEI_IAP_KEY_ID ||= 'test-key';
process.env.HUAWEI_IAP_ISSUER_ID ||= 'test-issuer';
process.env.HUAWEI_IAP_PRIVATE_KEY_PATH ||= 'test-private-key.pem';
process.env.HUAWEI_IAP_ROOT_CA_PATH ||= 'test-root-ca.pem';
process.env.HUAWEI_IAP_ROOT_URL ||= 'https://example.com';
process.env.HUAWEI_IAP_DELIVERABLE_STATUSES ||= '0,PAID';

const {
  calculateNextSyncQuota,
  ensureSyncQuota,
  normalizeOperation,
  registerDevice,
  MAX_SUPER_BOOK_SOURCE_PAYLOAD_BYTES,
  SyncApiError
} = await import('./sync.js');

const OP_ID = '123e4567-e89b-42d3-a456-426614174000';

test('app upgrades update the same device; identical model names do not collapse different devices', async t => {
  const db = new PGlite(); t.after(() => db.close());
  for (const migration of ['001_account_commerce.sql', '005_data_sync.sql',
    '006_sync_device_metadata.sql', '007_sync_performance.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${migration}`, import.meta.url), 'utf8'));
  }
  const userId = randomUUID(), otherUserId = randomUUID(), deviceId = randomUUID();
  for (const id of [userId, otherUserId]) {
    await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [id, id]);
  }
  const register = (id: string, version: string, owner = userId) => db.transaction(client =>
    registerDevice(client as unknown as PoolClient, owner, id, '同型号手机', 'HarmonyOS', version, 'phone', 0));
  await register(deviceId, '4.4.932');
  await db.query('UPDATE sync_devices SET device_name=$2,name_customized=TRUE WHERE id=$1', [deviceId, '我的手机']);
  await register(deviceId, '4.4.934');
  await register(deviceId, '5.0.0');
  const rows = (await db.query<{ id: string; app_version: string; device_name: string }>(
    'SELECT id,app_version,device_name FROM sync_devices WHERE user_id=$1', [userId])).rows;
  assert.equal(rows.length, 1);
  assert.equal(rows[0]!.id, deviceId);
  assert.equal(rows[0]!.app_version, '5.0.0');
  assert.equal(rows[0]!.device_name, '我的手机');
  await register(randomUUID(), '5.0.0');
  assert.equal((await db.query('SELECT id FROM sync_devices WHERE user_id=$1', [userId])).rows.length, 2);
  await assert.rejects(register(deviceId, '5.0.1', otherUserId), { code: 'SYNC_DEVICE_ACCOUNT_MISMATCH' });
  await db.query('UPDATE sync_devices SET revoked_at=now() WHERE id=$1', [deviceId]);
  await assert.rejects(register(deviceId, '5.0.1'), { code: 'SYNC_DEVICE_REVOKED' });
});

test('book source payloads may exceed the default 64KB limit', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(96 * 1024) }
  });
  assert.equal(normalized.entityType, 'book_source');
});

test('non-book-source payloads keep the 64KB limit', () => {
  assert.throws(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'reader_settings',
    entityId: 'global',
    operation: 'upsert',
    baseRevision: 0,
    payload: { settings: 'x'.repeat(96 * 1024) }
  }), (error: unknown) =>
    error instanceof SyncApiError &&
    error.statusCode === 413 &&
    error.code === 'SYNC_PAYLOAD_TOO_LARGE');
});

test('local reading progress payloads remain metadata-only JSON', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'reading_progress',
    entityId: 'book_local_content_fingerprint',
    operation: 'upsert',
    baseRevision: 0,
    payload: {
      origin: 'local',
      localContentHash: 'a'.repeat(64),
      chapterTitle: '第一章',
      chapterIndex: 3,
      chapterPos: 2,
      updatedAt: Date.now()
    }
  });
  assert.equal(normalized.entityType, 'reading_progress');
  assert.equal((normalized.payload as { localContentHash: string }).localContentHash.length, 64);
});

test('book source payloads up to 512KB are accepted', () => {
  assert.doesNotThrow(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(511 * 1024) }
  }));
});

test('book source payloads cannot exceed 512KB', () => {
  assert.throws(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(513 * 1024) }
  }), (error: unknown) =>
    error instanceof SyncApiError &&
    error.statusCode === 413 &&
    error.code === 'SYNC_PAYLOAD_TOO_LARGE');
});

test('the super-member book source ceiling is explicit and bounded', () => {
  const large = { opId: OP_ID, entityType: 'book_source', entityId: 'source_test', operation: 'upsert' as const,
    baseRevision: 0, payload: { rules: 'x'.repeat(900 * 1024) } };
  assert.equal(normalizeOperation(large, MAX_SUPER_BOOK_SOURCE_PAYLOAD_BYTES).payloadBytes > 512 * 1024, true);
  assert.throws(() => normalizeOperation({ ...large, payload: { rules: 'x'.repeat(961 * 1024) } },
    MAX_SUPER_BOOK_SOURCE_PAYLOAD_BYTES), (error: unknown) =>
    error instanceof SyncApiError && error.code === 'SYNC_PAYLOAD_TOO_LARGE');
});

test('deferring the account-specific source limit preserves validation of other sync entities', () => {
  const source = { opId: OP_ID, entityType: 'book_source', entityId: 'source_test', operation: 'upsert' as const,
    baseRevision: 0, payload: { rules: 'x'.repeat(1000 * 1024) } };
  assert.equal(normalizeOperation(source, null).payloadBytes, Buffer.byteLength(JSON.stringify(source.payload)));
  assert.throws(() => normalizeOperation({ ...source, entityType: 'reader_settings' }, null),
    { code: 'SYNC_PAYLOAD_TOO_LARGE', message: '单项同步数据不能超过 64KB' });
  assert.throws(() => normalizeOperation({ ...source, opId: 'invalid' }, null),
    { code: 'INVALID_OPERATION_ID' });
});

test('sync quotas reject unbounded daily writes and storage growth', () => {
  assert.throws(() => ensureSyncQuota({
    entityCount: 1,
    entityBytes: 1,
    changeCount: 1,
    changeBytes: 1,
    dailyWrites: 5001
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_DAILY_WRITE_LIMITED');
  assert.throws(() => ensureSyncQuota({
    entityCount: 20_001,
    entityBytes: 1,
    changeCount: 1,
    changeBytes: 1,
    dailyWrites: 1
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_STORAGE_QUOTA_EXCEEDED');
});

test('initial sync window allows a one-time 20000-write import', () => {
  assert.doesNotThrow(() => ensureSyncQuota({
    entityCount: 19_000,
    entityBytes: 1,
    changeCount: 19_000,
    changeBytes: 1,
    dailyWrites: 20_000,
    initialSyncActive: true
  }));
  assert.throws(() => ensureSyncQuota({
    entityCount: 19_000,
    entityBytes: 1,
    changeCount: 19_000,
    changeBytes: 1,
    dailyWrites: 20_001,
    initialSyncActive: true
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_DAILY_WRITE_LIMITED');
});

test('updating an entity reuses its lightweight change marker', () => {
  assert.deepEqual(calculateNextSyncQuota({
    entityCount: 10,
    entityBytes: 1000,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 2
  }, true, 100, 250), {
    entityCount: 10,
    entityBytes: 1150,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 3,
    initialSyncActive: undefined
  });
});

test('creating an entity adds exactly one lightweight change marker', () => {
  assert.deepEqual(calculateNextSyncQuota({
    entityCount: 10,
    entityBytes: 1000,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 2,
    initialSyncActive: true
  }, false, 0, 250), {
    entityCount: 11,
    entityBytes: 1250,
    changeCount: 11,
    changeBytes: 0,
    dailyWrites: 3,
    initialSyncActive: true
  });
});
