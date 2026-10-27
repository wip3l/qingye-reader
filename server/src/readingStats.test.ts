import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import type { PoolClient } from 'pg';
import type { ReadingStatsRequest, ReadingStatsPayload } from './readingStats.js';

for (const name of ['DATABASE_URL', 'SESSION_SECRET', 'HUAWEI_CLIENT_ID', 'HUAWEI_CLIENT_SECRET',
  'HUAWEI_APP_ID', 'HUAWEI_IAP_KEY_ID', 'HUAWEI_IAP_ISSUER_ID', 'HUAWEI_IAP_PRIVATE_KEY_PATH',
  'HUAWEI_IAP_ROOT_CA_PATH', 'HUAWEI_IAP_ROOT_URL', 'HUAWEI_IAP_DELIVERABLE_STATUSES']) process.env[name] ||= 'test';
const { exchangeReadingStats, normalizeReadingStats } = await import('./readingStats.js');
const phone = randomUUID(), tablet = randomUUID(), outsider = randomUUID();
const start = Date.parse('2026-10-26T10:00:00Z');
const payload = (deviceId = phone): ReadingStatsPayload => ({ deviceId, deviceName: '手机',
  bookKey: 'https://source.test\nhttps://book.test/1', name: '删除后仍保留书名', author: '作者', coverUrl: '',
  dayKey: '2026-10-26', durationMs: 60000, startedAt: start, lastReadAt: start + 60000, timezoneOffset: 0 });
const operation = (deviceId = phone) => ({ recordId: randomUUID(), deleted: false, payload: payload(deviceId) });
const request = (deviceId = phone, operations: ReadingStatsRequest['operations'] = [], cursor = 0): ReadingStatsRequest =>
  ({ protocolVersion: 1, deviceId, operations, cursor });

test('reading stats validate identities, timestamps, bounds and portable metadata', () => {
  assert.doesNotThrow(() => normalizeReadingStats(request(phone, [operation()])));
  for (const change of [{ durationMs: -1 }, { durationMs: 60001 }, { dayKey: '2026-02-30' },
    { dayKey: '2026-10-25' }, { timezoneOffset: 9999 }, { coverUrl: 'file:///data/private.jpg' },
    { bookKey: 'local\n/data/private.epub' }, { deviceId: tablet }, { name: 'x'.repeat(513) }]) {
    const op = operation(); Object.assign(op.payload, change);
    assert.throws(() => normalizeReadingStats(request(phone, [op])), { code: 'INVALID_READING_STATS' });
  }
  assert.throws(() => normalizeReadingStats(request(phone, Array.from({ length: 101 }, () => operation()))));
  const op = operation();
  assert.throws(() => normalizeReadingStats(request(phone, [op, op])));
  const deletion = normalizeReadingStats(request(phone, [{ ...op, deleted: true }]));
  assert.equal(deletion.operations[0]!.payload, null);
});

test('PostgreSQL exchange: two devices, replay, pagination, tombstones, privacy and account isolation', async t => {
  const db = new PGlite(); t.after(() => db.close());
  for (const migration of ['001_account_commerce.sql', '005_data_sync.sql', '006_sync_device_metadata.sql', '025_reading_statistics.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${migration}`, import.meta.url), 'utf8'));
  }
  // Migration is safe to run again on an already deployed database.
  await db.exec(await readFile(new URL('../migrations/025_reading_statistics.sql', import.meta.url), 'utf8'));
  const alice = randomUUID(), bob = randomUUID();
  for (const id of [alice, bob]) await db.query('INSERT INTO app_users(id,huawei_open_id) VALUES($1,$2)', [id, id]);
  for (const [id, user] of [[phone, alice], [tablet, alice], [outsider, bob]]) {
    await db.query('INSERT INTO sync_devices(id,user_id,device_name) VALUES($1,$2,$3)', [id, user, id === phone ? '我的手机' : '平板']);
  }
  const exchange = (user: string, req: ReadingStatsRequest) => db.transaction(client =>
    exchangeReadingStats({ query: client.query.bind(client) as unknown as PoolClient['query'] }, user, req));
  const one = operation();
  const first = await exchange(alice, request(phone, [one]));
  assert.equal(first.changes[0]!.payload?.deviceName, '我的手机');
  const replay = await exchange(alice, request(phone, [one], first.nextCursor));
  assert.equal(replay.changes.length, 0);
  // Metadata edits cannot alter a segment's time or identity, nor break replay after a lost response.
  await exchange(alice, request(phone, [{ ...one, payload: { ...one.payload, name: '新书名' } }]));
  await assert.rejects(exchange(alice, request(phone, [{ ...one, payload: { ...one.payload,
    durationMs: 120000, lastReadAt: start + 120000 } }])), { code: 'READING_STATS_ID_CONFLICT' });
  await assert.rejects(exchange(alice, request(tablet, [{ ...one, payload: payload(tablet) }])), { code: 'READING_STATS_ID_CONFLICT' });
  const second = operation(tablet);
  const twoDevices = await exchange(alice, request(tablet, [second]));
  assert.equal(twoDevices.changes.reduce((sum, row) => sum + (row.payload?.durationMs || 0), 0), 120000);
  assert.equal(new Set(twoDevices.changes.map(row => row.payload?.deviceId)).size, 2);
  assert.equal((await exchange(bob, request(outsider))).changes.length, 0);
  await assert.rejects(exchange(bob, request(phone)), { code: 'SYNC_DEVICE_REVOKED' });

  // An offline device may upload after another device has tombstoned the ID, but cannot resurrect it.
  const unseen = operation();
  await exchange(alice, request(tablet, [{ recordId: unseen.recordId, deleted: true, payload: null }]));
  const noResurrection = await exchange(alice, request(phone, [unseen]));
  assert.equal(noResurrection.acknowledgements[0]!.deleted, true);
  // Privacy retraction stores no title, URL or duration in the server tombstone.
  const deleted = await exchange(alice, request(tablet, [{ recordId: one.recordId, deleted: true, payload: null }], twoDevices.nextCursor));
  assert.equal(deleted.changes.find(row => row.recordId === one.recordId)?.payload, null);
  const afterDelete = await exchange(alice, request(phone, [one], deleted.nextCursor));
  assert.equal(afterDelete.acknowledgements[0]!.deleted, true);
  assert.equal(afterDelete.changes.length, 0);

  for (let i = 0; i < 3; i++) await exchange(alice, request(phone, Array.from({ length: 100 }, () => operation())));
  let cursor = 0, hasMore = true;
  const ids = new Set<string>();
  while (hasMore) {
    const page = await exchange(alice, request(tablet, [], cursor));
    assert.ok(page.nextCursor > cursor);
    for (const change of page.changes) { assert.ok(!ids.has(change.recordId)); ids.add(change.recordId); }
    cursor = page.nextCursor; hasMore = page.hasMore;
  }
  assert.equal(ids.size, 303);
  assert.equal((await exchange(alice, request(tablet, [], cursor))).changes.length, 0);
  const usage = (await db.query<{ record_count: number; payload_bytes: number }>(
    'SELECT record_count,payload_bytes FROM reading_stats_usage WHERE user_id=$1', [alice])).rows[0]!;
  assert.equal(Number(usage.record_count), 303);
  assert.ok(Number(usage.payload_bytes) > 0);
  await db.query('UPDATE reading_stats_usage SET record_count=1000000 WHERE user_id=$1', [alice]);
  await assert.rejects(exchange(alice, request(phone, [operation()])), { code: 'READING_STATS_QUOTA_EXCEEDED' });
  await exchange(alice, request(tablet, [{ recordId: second.recordId, deleted: true, payload: null }]));
  await db.query('UPDATE sync_devices SET revoked_at=now() WHERE id=$1', [phone]);
  await assert.rejects(exchange(alice, request(phone)), { code: 'SYNC_DEVICE_REVOKED' });
  assert.ok((await exchange(alice, request(tablet))).changes.some(row => row.payload?.deviceId === phone));
});
