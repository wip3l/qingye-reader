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

test('custom theme schemes may grow to 960KB', () => {
  const scheme = (size: number) => ({
    opId: OP_ID,
    entityType: 'custom_theme_schemes',
    entityId: 'global',
    operation: 'upsert' as const,
    baseRevision: 0,
    payload: { schemes: 'x'.repeat(size) }
  });
  assert.equal(normalizeOperation(scheme(900 * 1024)).entityType, 'custom_theme_schemes');
  assert.throws(() => normalizeOperation(scheme(970 * 1024)), (error: unknown) =>
    error instanceof SyncApiError && error.message === '单项同步数据不能超过 960KB');
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

test('payload strings jsonb cannot store are cleaned instead of failing the batch', async t => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'bookmark',
    entityId: 'bookmark_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { title: 'a\u0000b', note: ['x\ud83d', '\ude00y', '😀'], ['k\u0000']: 1 }
  });
  const payload = normalized.payload as Record<string, unknown>;
  assert.equal(payload.title, 'ab');
  assert.deepEqual(payload.note, ['x\ufffd', '\ufffdy', '😀']);
  assert.equal(payload.k, 1);
  assert.equal(normalized.payloadBytes, Buffer.byteLength(JSON.stringify(payload), 'utf8'));
  const db = new PGlite(); t.after(() => db.close());
  const stored = await db.query<{ j: unknown }>('SELECT $1::jsonb AS j', [JSON.stringify(payload)]);
  assert.deepEqual(stored.rows[0]!.j, payload);
});

test('reader annotations are accepted as a sync entity type', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'book_annotation',
    entityId: 'annotation_0123456789abcdef',
    operation: 'upsert',
    baseRevision: 0,
    payload: { bookUrl: 'https://book.test/1', quote: '原文', note: '想法', style: 'wavy', createTime: 1 }
  });
  assert.equal(normalized.entityType, 'book_annotation');
  assert.equal((normalized.payload as Record<string, unknown>).note, '想法');
});

test('book marks are accepted as a sync entity type', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'book_mark',
    entityId: 'mark_0123456789abcdef',
    operation: 'upsert',
    baseRevision: 0,
    payload: { workKey: 'novel|活着|余华', bookName: '活着', rating: 9, categories: ['文学'], review: '短评' }
  });
  assert.equal(normalized.entityType, 'book_mark');
  assert.equal((normalized.payload as Record<string, unknown>).review, '短评');
});

test('a "__proto__" payload key stays data after cleaning', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'bookmark',
    entityId: 'bookmark_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: JSON.parse('{"__proto__":{"polluted":"a\\u0000"}}') as object
  });
  const payload = normalized.payload as Record<string, unknown>;
  assert.equal(Object.getPrototypeOf(payload), Object.prototype);
  assert.deepEqual(Object.getOwnPropertyDescriptor(payload, '__proto__')?.value, { polluted: 'a' });
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

test('settings replaced by local-first sync or restore keep the previous version', async t => {
  const { readdir } = await import('node:fs/promises');
  const { applyOperation, listSyncHistory, restoreSyncHistoryIn, HISTORY_KEEP_PER_ENTITY } = await import('./sync.js');
  const db = new PGlite(); t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort()) {
    await db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  }
  const userId = randomUUID(), oldDevice = randomUUID(), newDevice = randomUUID();
  await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [userId, userId]);
  for (const [id, name] of [[oldDevice, '旧手机'], [newDevice, '新平板']] as const) {
    await db.transaction(client => registerDevice(client as unknown as PoolClient, userId, id, name,
      'HarmonyOS', '4.6.047', 'phone', 0));
  }
  const quota = { entityCount: 0, entityBytes: 0, changeCount: 0, changeBytes: 0, dailyWrites: 0 };
  const write = (device: string, entityType: string, payload: object, baseRevision: number,
    policy = 'cloud') => db.transaction(client => applyOperation(client as unknown as PoolClient, userId, device, {
    opId: randomUUID(), entityType, entityId: 'global', operation: 'upsert', baseRevision,
    payload, payloadBytes: JSON.stringify(payload).length
  }, policy, quota));
  const historyRows = async () => (await db.query<{ entity_type: string; reason: string; payload: { v: number } }>(
    'SELECT entity_type, reason, payload FROM sync_entity_history WHERE user_id=$1 ORDER BY id', [userId])).rows;

  await write(oldDevice, 'reader_settings', { v: 1 }, 0);
  await write(oldDevice, 'reader_settings', { v: 2 }, 1);
  await write(oldDevice, 'bookshelf_display', { v: 7 }, 0);
  assert.equal((await historyRows()).length, 0, 'ordinary edits keep no history');

  // 新装机首次同步选了“本地为主”，带着默认值和 0 号基础版本强制覆盖。
  assert.equal((await write(newDevice, 'reader_settings', { v: 0 }, 0, 'local')).accepted, true);
  assert.equal((await write(newDevice, 'bookshelf_display', { v: 7 }, 0, 'local')).accepted, true);
  let rows = await historyRows();
  assert.deepEqual(rows.map(row => [row.entity_type, row.reason, row.payload.v]),
    [['reader_settings', 'local_first', 2]], 'identical payloads are not recorded');

  const listed = await listSyncHistory(userId, db as unknown as { query: PoolClient['query'] });
  assert.equal(listed.groups.length, 1);
  assert.equal(listed.groups[0]!.deviceName, '新平板');
  assert.equal(listed.groups[0]!.reason, 'local_first');
  assert.deepEqual(listed.groups[0]!.items.map(item => item.entityType), ['reader_settings']);

  const restored = await db.transaction(client => restoreSyncHistoryIn(client as unknown as PoolClient, userId,
    oldDevice, [listed.groups[0]!.items[0]!.historyId]));
  assert.equal(restored.restored, 1);
  const current = (await db.query<{ revision: string; payload: { v: number } }>(
    `SELECT revision, payload FROM sync_entities WHERE user_id=$1 AND entity_type='reader_settings'`, [userId])).rows[0]!;
  assert.equal(current.payload.v, 2);
  assert.equal(Number(current.revision), 4);
  rows = await historyRows();
  assert.deepEqual(rows.map(row => [row.reason, row.payload.v]), [['local_first', 2], ['restore', 0]],
    'restoring also keeps the version it replaced');

  // 每项只留最近几份。
  for (let index = 0; index < HISTORY_KEEP_PER_ENTITY + 3; index++) {
    await write(newDevice, 'reader_settings', { v: 100 + index }, 0, 'local');
  }
  const kept = (await db.query<{ count: string }>(
    `SELECT count(*) FROM sync_entity_history WHERE user_id=$1 AND entity_type='reader_settings'`, [userId])).rows[0]!;
  assert.equal(Number(kept.count), HISTORY_KEEP_PER_ENTITY);
});

test('settings history for one account stays under the byte cap', async t => {
  const { readdir } = await import('node:fs/promises');
  const { applyOperation, HISTORY_MAX_BYTES_PER_USER } = await import('./sync.js');
  const db = new PGlite(); t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(file => file.endsWith('.sql')).sort()) {
    await db.exec((await readFile(new URL(file, migrations), 'utf8')).replace(/^VACUUM[^;]*;/gm, ''));
  }
  const userId = randomUUID(), deviceId = randomUUID();
  await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [userId, userId]);
  await db.transaction(client => registerDevice(client as unknown as PoolClient, userId, deviceId, '平板',
    'HarmonyOS', '4.6.047', 'tablet', 0));
  const quota = { entityCount: 0, entityBytes: 0, changeCount: 0, changeBytes: 0, dailyWrites: 0 };
  for (let index = 0; index < 7; index++) {
    const payload = { schemes: `${index}`.repeat(700 * 1024) };
    await db.transaction(client => applyOperation(client as unknown as PoolClient, userId, deviceId, {
      opId: randomUUID(), entityType: 'custom_theme_schemes', entityId: 'global', operation: 'upsert',
      baseRevision: 0, payload, payloadBytes: JSON.stringify(payload).length
    }, 'local', quota));
  }
  const usage = (await db.query<{ rows: string; bytes: string; newest: string }>(
    `SELECT count(*) AS rows, COALESCE(sum(octet_length(payload::text)), 0) AS bytes,
       max(revision) AS newest FROM sync_entity_history WHERE user_id=$1`, [userId])).rows[0]!;
  assert.ok(Number(usage.bytes) <= HISTORY_MAX_BYTES_PER_USER);
  assert.equal(Number(usage.rows), 4);
  assert.equal(Number(usage.newest), 6, 'the newest replaced version is kept');
});
