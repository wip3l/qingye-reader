import type { PoolClient } from 'pg';
import { SyncApiError } from './sync.js';

interface ReadingStatsDb { query: PoolClient['query']; }
export interface ReadingStatsPayload {
  deviceId: string;
  deviceName: string;
  bookKey: string;
  name: string;
  author: string;
  coverUrl: string;
  dayKey: string;
  durationMs: number;
  startedAt: number;
  lastReadAt: number;
  timezoneOffset: number;
}
interface ReadingStatsOperation { recordId: string; deleted: boolean; payload: ReadingStatsPayload | null; }
export interface ReadingStatsRequest {
  protocolVersion: number;
  deviceId: string;
  cursor: number;
  operations: ReadingStatsOperation[];
}
interface ReadingStatsStored {
  record_id: string;
  source_device_id: string | null;
  payload: ReadingStatsPayload | null;
  deleted: boolean;
  sequence_id: string;
  payload_bytes: number;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BATCH_SIZE = 100;
const MAX_RECORDS = 1_000_000;
const MAX_BYTES = 512 * 1024 * 1024;

function invalid(): never { throw new SyncApiError(400, 'INVALID_READING_STATS', '阅读统计同步数据无效'); }
function text(input: unknown, max: number, required = false): string {
  if (typeof input !== 'string' || input.length > max || (required && !input.trim())) invalid();
  return input;
}
function integer(input: unknown, min: number, max: number): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < min || input > max) invalid();
  return input;
}
export function normalizeReadingStats(body: ReadingStatsRequest): ReadingStatsRequest {
  if (!body || body.protocolVersion !== 1 || typeof body.deviceId !== 'string' || !UUID.test(body.deviceId) ||
    !Array.isArray(body.operations) || body.operations.length > BATCH_SIZE) invalid();
  const deviceId = body.deviceId.toLowerCase();
  const cursor = integer(body.cursor, 0, Number.MAX_SAFE_INTEGER);
  const ids = new Set<string>();
  const operations = body.operations.map(op => {
    if (!op || typeof op.recordId !== 'string' || !UUID.test(op.recordId) || typeof op.deleted !== 'boolean') invalid();
    const recordId = op.recordId.toLowerCase();
    if (ids.has(recordId)) invalid();
    ids.add(recordId);
    // Deletions send only an identity, never private book metadata.
    if (op.deleted) return { recordId, deleted: true, payload: null };
    const p = op.payload;
    if (!p || typeof p.deviceId !== 'string' || p.deviceId.toLowerCase() !== deviceId) invalid();
    const dayKey = text(p.dayKey, 10, true);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey) || !Number.isFinite(Date.parse(dayKey)) ||
      new Date(dayKey).toISOString().slice(0, 10) !== dayKey) invalid();
    const startedAt = integer(p.startedAt, 1, 253_402_214_400_000);
    const lastReadAt = integer(p.lastReadAt, startedAt + 1, 253_402_300_799_999);
    const durationMs = integer(p.durationMs, 1, 26 * 60 * 60 * 1000);
    if (durationMs !== lastReadAt - startedAt) invalid();
    const timezoneOffset = integer(p.timezoneOffset, -14 * 60, 14 * 60);
    if (new Date(startedAt - timezoneOffset * 60000).toISOString().slice(0, 10) !== dayKey) invalid();
    const bookKey = text(p.bookKey, 4096, true);
    // Local files without a content fingerprint cannot identify the same book across installations.
    if (/^(local\n|local:|file:|\/)/i.test(bookKey)) invalid();
    const coverUrl = text(p.coverUrl, 2048);
    if (coverUrl && !/^https?:\/\//i.test(coverUrl)) invalid();
    const payload: ReadingStatsPayload = { deviceId, deviceName: text(p.deviceName, 128), bookKey,
      name: text(p.name, 512), author: text(p.author, 512), coverUrl, dayKey, durationMs,
      startedAt, lastReadAt, timezoneOffset };
    if (Buffer.byteLength(JSON.stringify(payload)) > 8192) invalid();
    return { recordId, deleted: false, payload };
  });
  return { protocolVersion: 1, deviceId, cursor, operations };
}

/** Caller must wrap this in one transaction. Account lock orders cursor allocation and commit. */
export async function exchangeReadingStats(db: ReadingStatsDb, userId: string, body: ReadingStatsRequest) {
  const request = normalizeReadingStats(body);
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`sync-user:${userId}`]);
  const device = await db.query(`SELECT id FROM sync_devices WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL`,
    [request.deviceId, userId]);
  if (!device.rows.length) throw new SyncApiError(403, 'SYNC_DEVICE_REVOKED', '请先注册有效的同步设备');
  await db.query('INSERT INTO reading_stats_usage(user_id) VALUES($1) ON CONFLICT DO NOTHING', [userId]);
  const usage = await db.query<{ record_count: string; payload_bytes: string }>(
    'SELECT record_count,payload_bytes FROM reading_stats_usage WHERE user_id=$1 FOR UPDATE', [userId]);
  let count = Number(usage.rows[0]!.record_count), bytes = Number(usage.rows[0]!.payload_bytes);
  const existing = await db.query<ReadingStatsStored>(
    'SELECT * FROM reading_stats_records WHERE user_id=$1 AND record_id=ANY($2::uuid[])',
    [userId, request.operations.map(op => op.recordId)]);
  const records = new Map(existing.rows.map(row => [row.record_id, row]));
  const acknowledgements: Array<{ recordId: string; deleted: boolean }> = [];
  for (const op of request.operations) {
    const previous = records.get(op.recordId);
    if (previous?.deleted || (previous && !op.deleted)) {
      // Reading segments are immutable. A new operation ID or a retry cannot increment duration.
      if (!previous.deleted) {
        const immutable: Array<keyof ReadingStatsPayload> = ['bookKey', 'dayKey', 'durationMs',
          'startedAt', 'lastReadAt', 'timezoneOffset'];
        if (previous.source_device_id !== request.deviceId || immutable.some(key =>
          previous.payload![key] !== op.payload![key])) {
          throw new SyncApiError(409, 'READING_STATS_ID_CONFLICT', '阅读记录身份冲突，请保留本地数据后重试');
        }
      }
      acknowledgements.push({ recordId: op.recordId, deleted: previous.deleted });
      continue;
    }
    const payloadBytes = op.payload ? Buffer.byteLength(JSON.stringify(op.payload)) : 0;
    count += previous ? 0 : 1;
    bytes += payloadBytes - (previous?.payload_bytes || 0);
    // Always allow shrinking an existing record to a tombstone, even at the quota boundary.
    if ((!previous && count > MAX_RECORDS) || bytes > MAX_BYTES) {
      throw new SyncApiError(409, 'READING_STATS_QUOTA_EXCEEDED', '阅读统计云端存储已达上限');
    }
    await db.query(`INSERT INTO reading_stats_records
      (user_id,record_id,source_device_id,payload,deleted,payload_bytes) VALUES($1,$2,$3,$4::jsonb,$5,$6)
      ON CONFLICT (user_id,record_id) DO UPDATE SET payload=NULL,deleted=TRUE,payload_bytes=0,
        sequence_id=nextval('reading_stats_sequence')`,
    [userId, op.recordId, op.deleted ? previous?.source_device_id || null : request.deviceId,
      op.payload ? JSON.stringify(op.payload) : null, op.deleted, payloadBytes]);
    acknowledgements.push({ recordId: op.recordId, deleted: op.deleted });
  }
  await db.query('UPDATE reading_stats_usage SET record_count=$2,payload_bytes=$3 WHERE user_id=$1', [userId, count, bytes]);
  const result = await db.query<ReadingStatsStored>(`SELECT r.*,
    CASE WHEN d.device_name <> '' AND r.payload IS NOT NULL
      THEN jsonb_set(r.payload, '{deviceName}', to_jsonb(d.device_name)) ELSE r.payload END AS payload
    FROM reading_stats_records r LEFT JOIN sync_devices d ON d.id=r.source_device_id AND d.user_id=r.user_id
    WHERE r.user_id=$1 AND r.sequence_id>$2 ORDER BY r.sequence_id LIMIT $3`, [userId, request.cursor, BATCH_SIZE + 1]);
  const changes = result.rows.slice(0, BATCH_SIZE).map(row => ({ recordId: row.record_id,
    sequenceId: Number(row.sequence_id), deleted: row.deleted, payload: row.payload }));
  return { protocolVersion: 1, acknowledgements, changes,
    nextCursor: changes.at(-1)?.sequenceId ?? request.cursor, hasMore: result.rows.length > BATCH_SIZE };
}
