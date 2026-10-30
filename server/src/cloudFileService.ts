import { createHash, randomUUID } from 'node:crypto';
import { MembershipDb, cloudQuotaBytes, membershipSnapshot } from './membershipService.js';
import { MembershipError, membershipCalendarCycle } from './membershipPolicy.js';
import { CloudObjectStore } from './cloudObjectStore.js';

export const CLOUD_CHUNK_BYTES = 1024 ** 2;
/** Largest single file and the monthly download allowance; storage per account comes from cloudQuotaBytes. */
export const CLOUD_QUOTA_BYTES = 1024 ** 3;
type Transaction = <T>(fn: (db: MembershipDb) => Promise<T>) => Promise<T>;
interface FileRow { id: string; user_id: string; kind: string; name: string; bytes: string; state: string; manifest_hash: string | null; expected_manifest_hash: string | null; meta: CloudFileMeta | null; }
interface ChunkRow { chunk_index: number; bytes: number; sha256: string; object_key: string; ready: boolean; upload_md5: string | null; upload_expires_at: Date | null; }
export interface CloudPrepare { requestId: string; kind: string; name: string; bytes: number; manifestHash?: string; meta?: unknown; }
export type CloudFileMeta = Record<string, string>;
export type CloudRemoveReason = 'REMOVED' | 'DETACHED';
const META_KEYS = new Set(['title', 'author', 'format', 'contentHash', 'fontName', 'mediaCategory']);
const TOMBSTONE_DAYS = 180;

/** Only short display strings and a fingerprint; anything else is rejected rather than stored. */
function normalizeMeta(value: unknown): CloudFileMeta | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'object' || Array.isArray(value)) fail(400, 'CLOUD_INVALID_FILE', '文件附加信息无效');
  const meta: CloudFileMeta = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (!META_KEYS.has(key) || typeof item !== 'string' || item.length > 200 || /[\x00-\x1f]/.test(item)) {
      fail(400, 'CLOUD_INVALID_FILE', '文件附加信息无效');
    }
    if (item) meta[key] = item as string;
    if (key === 'mediaCategory' && !['novel', 'comic'].includes(item as string)) {
      fail(400, 'CLOUD_INVALID_FILE', '书籍内容分类无效');
    }
  }
  return Object.keys(meta).length ? meta : null;
}
const fail = (status: number, code: string, message: string): never => { throw new MembershipError(status, code, message); };
const digest = (body: Buffer) => createHash('sha256').update(body).digest('hex');
export interface CloudUploadChunk { index: number; bytes: number; sha256: string; md5: string; }
const UPLOAD_SECONDS = 120;
const DOWNLOAD_SECONDS = 60;
const CLEANUP_GRACE_MS = 5 * 60 * 1000;
const stagingKey = (key: string) => key.replace('qingye/v1/', 'qingye/staging/v1/');
const validId = (id: string) => /^[0-9a-f-]{36}$/i.test(id);

export class CloudFileService {
  private activeTransfers = 0;
  private cleaning = false;
  constructor(private readonly tx: Transaction, private readonly store: CloudObjectStore | null,
    private readonly now: () => number = Date.now) {}

  private async lock(db: MembershipDb, userId: string) {
    // Shared with inline source sync: both compete for the same storage budget.
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`sync-user:${userId}`]);
  }
  private configured(): CloudObjectStore {
    return this.store ?? fail(503, 'CLOUD_NOT_CONFIGURED', '云文件服务尚未启用');
  }
  private async member(db: MembershipDb, userId: string, now = this.now()) {
    const member = await membershipSnapshot(db, userId, now);
    if (!member.active || member.state?.sku !== 'SUPER_LIFETIME') {
      fail(403, 'CLOUD_SUPER_REQUIRED', '此功能需要有效的终身超级会员');
    }
    return member;
  }
  private async file(db: MembershipDb, userId: string, id: string): Promise<FileRow> {
    if (!validId(id)) fail(404, 'CLOUD_FILE_NOT_FOUND', '云文件不存在');
    const row = (await db.query<FileRow>('SELECT * FROM cloud_files WHERE id=$1 AND user_id=$2', [id, userId])).rows[0];
    return row ?? fail(404, 'CLOUD_FILE_NOT_FOUND', '云文件不存在');
  }
  private async used(db: MembershipDb, userId: string): Promise<number> {
    const result = await db.query(`SELECT
      COALESCE((SELECT sum(bytes) FROM cloud_files WHERE user_id=$1),0)
      + COALESCE((SELECT sum(octet_length(payload::text)) FROM sync_entities
          WHERE user_id=$1 AND entity_type='book_source' AND deleted_at IS NULL),0) AS bytes`, [userId]);
    return Number(result.rows[0].bytes);
  }

  async summary(userId: string) {
    if (!this.store) return { configured: false, eligible: false, usedBytes: 0, quotaBytes: CLOUD_QUOTA_BYTES,
      downloadBytes: 0, downloadQuotaBytes: CLOUD_QUOTA_BYTES, chunkBytes: CLOUD_CHUNK_BYTES, cycleEndsAt: null };
    return this.tx(async db => {
      const now = this.now();
      const member = await membershipSnapshot(db, userId, now);
      const cycle = member.active ? membershipCalendarCycle(member.state!, now) : null;
      const usage = cycle ? await db.query(`SELECT bytes FROM cloud_download_monthly_usage
        WHERE user_id=$1 AND month_index=$2`, [userId, cycle.index]) : null;
      return { configured: true, eligible: member.active && member.state?.sku === 'SUPER_LIFETIME',
        usedBytes: await this.used(db, userId), quotaBytes: await cloudQuotaBytes(db, userId),
        downloadBytes: Number(usage?.rows[0]?.bytes ?? 0), downloadQuotaBytes: CLOUD_QUOTA_BYTES,
        chunkBytes: CLOUD_CHUNK_BYTES, cycleEndsAt: cycle?.endsAt ?? null };
    });
  }

  async list(userId: string, after = '') {
    this.configured();
    if (after && !validId(after)) fail(400, 'CLOUD_INVALID_CURSOR', '分页游标无效');
    return this.tx(async db => {
      // Metadata and deletion remain available after suspension; bytes require an active membership.
      const rows = (await db.query<FileRow>(`SELECT * FROM cloud_files WHERE user_id=$1
        AND ($2='' OR id::text>$2) ORDER BY id LIMIT 101`, [userId, after])).rows;
      const page = rows.slice(0, 100);
      return { files: page.map(row => ({ id: row.id, kind: row.kind, name: row.name,
        bytes: Number(row.bytes), state: row.state, manifestHash: row.manifest_hash, meta: row.meta ?? null })),
        nextCursor: rows.length > 100 ? page[99]!.id : '' };
    });
  }

  async prepare(userId: string, input: CloudPrepare) {
    this.configured();
    if (input?.kind === 'SOURCE') fail(400, 'CLOUD_SOURCE_SYNC_ONLY', '书源请通过数据同步管理，无需上传到云文件');
    if (!input || !/^[a-zA-Z0-9_-]{8,100}$/.test(input.requestId) || !['BOOK','FONT','SOURCE'].includes(input.kind)
      || typeof input.name !== 'string' || !input.name.trim() || input.name.length > 200
      || /[\\/\x00-\x1f]/.test(input.name) || !Number.isSafeInteger(input.bytes) || input.bytes < 1 || input.bytes > CLOUD_QUOTA_BYTES) {
      fail(400, 'CLOUD_INVALID_FILE', '文件名称、大小或上传标识无效');
    }
    if (input.manifestHash !== undefined && !/^[0-9a-f]{64}$/.test(input.manifestHash)) fail(400, 'CLOUD_INVALID_FILE', '文件校验标识无效');
    const meta = normalizeMeta(input.meta);
    return this.tx(async db => {
      await this.lock(db, userId); await this.member(db, userId);
      const old = (await db.query<FileRow>('SELECT * FROM cloud_files WHERE user_id=$1 AND request_id=$2', [userId, input.requestId])).rows[0];
      if (old) {
        if (old.kind !== input.kind || old.name !== input.name || Number(old.bytes) !== input.bytes ||
          old.expected_manifest_hash !== (input.manifestHash ?? null) || old.state === 'DELETING') {
          fail(409, 'CLOUD_UPLOAD_CHANGED', '上传任务已改变，请创建新的上传任务');
        }
        return { id: old.id, chunkBytes: CLOUD_CHUNK_BYTES, state: old.state };
      }
      if (input.manifestHash) {
        const duplicate = (await db.query<FileRow>(`SELECT * FROM cloud_files WHERE user_id=$1 AND kind=$2
          AND state='READY' AND manifest_hash=$3 AND bytes=$4 LIMIT 1`, [userId, input.kind, input.manifestHash, input.bytes])).rows[0];
        if (duplicate) {
          // Same content uploaded again from another device: keep one copy, fill in missing metadata.
          if (meta && !duplicate.meta) await db.query('UPDATE cloud_files SET meta=$2 WHERE id=$1', [duplicate.id, JSON.stringify(meta)]);
          return { id: duplicate.id, chunkBytes: CLOUD_CHUNK_BYTES, state: duplicate.state };
        }
      }
      const pending = await db.query("SELECT count(*) FROM cloud_files WHERE user_id=$1 AND state='UPLOADING'", [userId]);
      if (Number(pending.rows[0].count) >= 10) fail(409, 'CLOUD_PENDING_LIMIT', '请先完成或取消已有上传任务');
      if (await this.used(db, userId) + input.bytes > await cloudQuotaBytes(db, userId)) fail(409, 'CLOUD_STORAGE_LIMIT', '云空间不足，请先删除不需要的文件');
      const id = randomUUID();
      await db.query('INSERT INTO cloud_files(id,user_id,request_id,kind,name,bytes,expected_manifest_hash,meta) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',
        [id, userId, input.requestId, input.kind, input.name, input.bytes, input.manifestHash ?? null, meta ? JSON.stringify(meta) : null]);
      return { id, chunkBytes: CLOUD_CHUNK_BYTES, state: 'UPLOADING' };
    });
  }

  async manifest(userId: string, id: string) {
    this.configured();
    return this.tx(async db => {
      const file = await this.file(db, userId, id);
      const chunks = (await db.query<ChunkRow>('SELECT * FROM cloud_chunks WHERE file_id=$1 ORDER BY chunk_index', [id])).rows;
      return { id, name: file.name, kind: file.kind, state: file.state, bytes: Number(file.bytes),
        manifestHash: file.manifest_hash, meta: file.meta ?? null, chunkBytes: CLOUD_CHUNK_BYTES,
        chunks: chunks.filter(c => c.ready).map(c => ({ index: c.chunk_index, bytes: c.bytes, sha256: c.sha256 })) };
    });
  }

  /** Backfill legacy metadata without reserving storage or transferring the file again. */
  async fillMetadata(userId: string, id: string, value: unknown) {
    this.configured();
    const meta = normalizeMeta(value);
    if (!meta) fail(400, 'CLOUD_INVALID_FILE', '文件附加信息无效');
    return this.tx(async db => {
      await this.lock(db, userId);
      await this.member(db, userId);
      const file = await this.file(db, userId, id);
      if (file.state !== 'READY') fail(409, 'CLOUD_FILE_NOT_READY', '文件尚未上传完成');
      // Existing values win, so older devices cannot erase or change a known classification.
      await db.query('UPDATE cloud_files SET meta=$2,updated_at=now() WHERE id=$1',
        [id, JSON.stringify({ ...meta, ...file.meta })]);
      return { accepted: true };
    });
  }

  async uploadTicket(userId: string, id: string, input: CloudUploadChunk) {
    const store = this.configured();
    if (!input || !Number.isInteger(input.index) || input.index < 0 || input.index >= 1024
      || !Number.isInteger(input.bytes) || input.bytes < 1 || input.bytes > CLOUD_CHUNK_BYTES
      || !/^[0-9a-f]{64}$/.test(input.sha256) || !/^[A-Za-z0-9+/]{22}==$/.test(input.md5)
      || Buffer.from(input.md5, 'base64').toString('base64') !== input.md5) {
      fail(400, 'CLOUD_INVALID_CHUNK', '上传分块信息无效');
    }
    return this.tx(async db => {
      await this.lock(db, userId); await this.member(db, userId);
      const file = await this.file(db, userId, id);
      if (file.state !== 'UPLOADING') fail(409, 'CLOUD_UPLOAD_CLOSED', '上传任务已结束');
      const expected = Math.min(CLOUD_CHUNK_BYTES, Number(file.bytes) - input.index * CLOUD_CHUNK_BYTES);
      if (input.bytes !== expected) fail(400, 'CLOUD_CHUNK_SIZE', '分块长度与声明文件大小不一致');
      const key = `qingye/v1/${userId}/${id}/${input.index}`;
      await db.query(`INSERT INTO cloud_chunks(file_id,chunk_index,bytes,sha256,object_key,upload_md5)
        VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING`, [id, input.index, input.bytes, input.sha256, key, input.md5]);
      const chunk = (await db.query<ChunkRow>('SELECT * FROM cloud_chunks WHERE file_id=$1 AND chunk_index=$2', [id, input.index])).rows[0]!;
      if (chunk.sha256 !== input.sha256 || chunk.bytes !== input.bytes || (chunk.upload_md5 && chunk.upload_md5 !== input.md5)) {
        fail(409, 'CLOUD_CHUNK_CHANGED', '文件内容已改变，请重新创建上传任务');
      }
      if (chunk.ready) return { ready: true, index: input.index, bytes: chunk.bytes, sha256: chunk.sha256 };
      const expiresAt = this.now() + UPLOAD_SECONDS * 1000;
      const url = store.signUpload(stagingKey(key), input.md5, UPLOAD_SECONDS);
      // Persist before issuing a URL so every possible object has a cleanup record.
      await db.query('UPDATE cloud_chunks SET upload_md5=$3,upload_expires_at=$4 WHERE file_id=$1 AND chunk_index=$2',
        [id, input.index, input.md5, new Date(expiresAt)]);
      await db.query('UPDATE cloud_files SET updated_at=now() WHERE id=$1', [id]);
      return { ready: false, url, expiresAt, md5: input.md5, index: input.index, bytes: chunk.bytes, sha256: chunk.sha256 };
    });
  }

  async confirmChunk(userId: string, id: string, index: number) {
    const store = this.configured();
    if (!Number.isInteger(index) || index < 0 || index >= 1024) fail(400, 'CLOUD_INVALID_CHUNK', '分块编号无效');
    return this.transfer(async () => this.tx(async db => {
      await this.lock(db, userId); await this.member(db, userId);
      if ((await this.file(db, userId, id)).state !== 'UPLOADING') fail(409, 'CLOUD_UPLOAD_CLOSED', '上传任务已结束');
      const chunk = (await db.query<ChunkRow>('SELECT * FROM cloud_chunks WHERE file_id=$1 AND chunk_index=$2', [id, index])).rows[0];
      if (!chunk) return fail(404, 'CLOUD_CHUNK_NOT_FOUND', '请先申请分块上传');
      if (!chunk.ready) {
        const stage = stagingKey(chunk.object_key);
        const metadata = await store.head(stage);
        if (metadata.bytes !== chunk.bytes || metadata.etag.replace(/^"|"$/g, '').toLowerCase() !== Buffer.from(chunk.upload_md5!, 'base64').toString('hex')) {
          fail(409, 'CLOUD_CHUNK_INTEGRITY', '云端分块校验失败，请重新上传');
        }
        // Only the backend writes published keys. Replaying PUT can only change staging data.
        await db.query('SELECT 1'); // Refresh the DB idle timeout between bounded OBS calls.
        await store.copy(stage, chunk.object_key, metadata.etag);
        await db.query('UPDATE cloud_chunks SET ready=true WHERE file_id=$1 AND chunk_index=$2', [id, index]);
      }
      await db.query('UPDATE cloud_files SET updated_at=now() WHERE id=$1', [id]);
      return { index, sha256: chunk.sha256, bytes: chunk.bytes };
    }));
  }

  async complete(userId: string, id: string) {
    this.configured();
    return this.tx(async db => {
      await this.lock(db, userId); await this.member(db, userId);
      const file = await this.file(db, userId, id);
      if (file.state === 'READY') return { id, manifestHash: file.manifest_hash };
      if (file.state !== 'UPLOADING') fail(409, 'CLOUD_UPLOAD_CLOSED', '上传任务已结束');
      const chunks = (await db.query<ChunkRow>('SELECT * FROM cloud_chunks WHERE file_id=$1 ORDER BY chunk_index', [id])).rows;
      if (chunks.length !== Math.ceil(Number(file.bytes) / CLOUD_CHUNK_BYTES) || chunks.some((c, i) => !c.ready || c.chunk_index !== i)
        || chunks.reduce((sum, c) => sum + c.bytes, 0) !== Number(file.bytes)) fail(409, 'CLOUD_UPLOAD_INCOMPLETE', '还有分块未上传完成');
      const hash = digest(Buffer.from(chunks.map(c => `${c.chunk_index}:${c.bytes}:${c.sha256}`).join('\n')));
      if (file.expected_manifest_hash && file.expected_manifest_hash !== hash) fail(409, 'CLOUD_CONTENT_CHANGED', '文件完整性校验失败，请重新上传');
      await db.query("UPDATE cloud_files SET state='READY',manifest_hash=$2,updated_at=now() WHERE id=$1", [id, hash]);
      // Re-adding content that was removed earlier revives it everywhere.
      await db.query('DELETE FROM cloud_file_tombstones WHERE user_id=$1 AND kind=$2 AND manifest_hash=$3', [userId, file.kind, hash]);
      return { id, manifestHash: hash };
    });
  }

  async downloadTicket(userId: string, id: string, index: number, requestId: string) {
    const store = this.configured();
    if (!Number.isInteger(index) || index < 0 || index >= 1024 || typeof requestId !== 'string'
      || !/^[a-zA-Z0-9_-]{8,100}$/.test(requestId)) fail(400, 'CLOUD_INVALID_CHUNK', '下载请求无效');
    return this.tx(async db => {
      await this.lock(db, userId);
      const now = this.now();
      const member = await this.member(db, userId, now);
      const month = membershipCalendarCycle(member.state!, now);
      if ((await this.file(db, userId, id)).state !== 'READY') fail(409, 'CLOUD_FILE_NOT_READY', '文件尚未上传完成');
      const chunk = (await db.query<ChunkRow>('SELECT * FROM cloud_chunks WHERE file_id=$1 AND chunk_index=$2 AND ready=true', [id, index])).rows[0];
      if (!chunk) return fail(404, 'CLOUD_CHUNK_NOT_FOUND', '分块不存在');
      const period = member.state!.periodId, cycle = month.index;
      const old = (await db.query<{ file_id: string; chunk_index: number; period_id: string; download_month: number | null; expires_at: Date }>(
        'SELECT * FROM cloud_download_tickets WHERE user_id=$1 AND request_id=$2', [userId, requestId])).rows[0];
      let expiresAt = Math.min(now + DOWNLOAD_SECONDS * 1000, month.endsAt);
      if (old) {
        if (old.file_id !== id || old.chunk_index !== index) fail(409, 'CLOUD_TICKET_CHANGED', '下载请求已改变');
        expiresAt = new Date(old.expires_at).getTime();
        // Pre-rollout tickets (NULL month) can finish their original short-lived authorization.
        if (expiresAt - this.now() < 1000 || old.period_id !== period ||
            (old.download_month !== null && old.download_month !== cycle)) {
          fail(409, 'CLOUD_TICKET_EXPIRED', '下载授权已过期，请重新下载');
        }
      } else {
        const reserved = await db.query(`INSERT INTO cloud_download_monthly_usage(user_id,month_index,bytes)
          VALUES($1,$2,$3) ON CONFLICT(user_id,month_index) DO UPDATE
          SET bytes=cloud_download_monthly_usage.bytes+EXCLUDED.bytes
          WHERE cloud_download_monthly_usage.bytes+EXCLUDED.bytes<=$4 RETURNING bytes`, [userId, cycle, chunk.bytes, CLOUD_QUOTA_BYTES]);
        if (!reserved.rowCount) fail(409, 'CLOUD_TRAFFIC_LIMIT', '本自然月下载额度已用完，下月1日北京时间零点重置');
        await db.query(`INSERT INTO cloud_download_tickets
          (user_id,request_id,file_id,chunk_index,period_id,cycle_index,expires_at,download_month)
          VALUES($1,$2,$3,$4,$5,$6,$7,$6)`, [userId, requestId, id, index, period, cycle, new Date(expiresAt)]);
      }
      // Sign inside the quota transaction: signing failure rolls back both charge and ticket.
      // Once issued, a capability cannot be refunded based on an untrusted client report.
      const seconds = Math.floor((expiresAt - this.now()) / 1000);
      if (seconds < 1) fail(409, 'CLOUD_TICKET_EXPIRED', '下载授权已过期，请重新下载');
      const url = store.signDownload(chunk.object_key, seconds);
      return { url, expiresAt, index, bytes: chunk.bytes, sha256: chunk.sha256 };
    });
  }

  /**
   * REMOVED: the user removed the book/font itself, so other devices remove their copies too.
   * DETACHED: only the cloud copy is dropped (e.g. from the cloud files page); local copies stay.
   */
  async remove(userId: string, id: string, reason: CloudRemoveReason = 'DETACHED') {
    this.configured();
    if (!validId(id)) fail(404, 'CLOUD_FILE_NOT_FOUND', '云文件不存在');
    if (reason !== 'REMOVED' && reason !== 'DETACHED') fail(400, 'CLOUD_INVALID_REASON', '删除原因无效');
    await this.tx(async db => {
      await this.lock(db, userId);
      const marked = await db.query<FileRow>(`UPDATE cloud_files SET state='DELETING',updated_at=now()
        WHERE id=$1 AND user_id=$2 AND state<>'DELETING' RETURNING *`, [id, userId]);
      const file = marked.rows[0];
      if (file && file.state !== 'UPLOADING' && file.manifest_hash) {
        await db.query(`INSERT INTO cloud_file_tombstones(id,user_id,kind,manifest_hash,meta,reason)
          VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING`,
          [id, userId, file.kind, file.manifest_hash, file.meta ? JSON.stringify(file.meta) : null, reason]);
      }
    });
    await this.cleanFile(userId, id);
    return { accepted: true };
  }
  private async cleanFile(userId: string, id: string) {
    // Bounded transactions keep each batch short; continuing until the file is gone (or the time
    // budget ends) releases deleted space promptly instead of a few chunks per maintenance minute.
    const deadline = this.now() + 20_000;
    while (!(await this.cleanFileBatch(userId, id)) && this.now() < deadline) { /* next batch */ }
  }
  /** Returns true when nothing more can be removed now (file gone, or only in-flight staging remains). */
  private async cleanFileBatch(userId: string, id: string): Promise<boolean> {
    return this.tx(async db => {
      await this.lock(db, userId);
      const file = (await db.query<FileRow>("SELECT * FROM cloud_files WHERE user_id=$1 AND id=$2 AND state='DELETING'", [userId, id])).rows[0];
      if (!file) return true;
      const chunks = (await db.query<ChunkRow>(`SELECT * FROM cloud_chunks WHERE file_id=$1
        AND (upload_expires_at IS NULL OR upload_expires_at<$2) LIMIT 16`, [id, new Date(this.now() - CLEANUP_GRACE_MS)])).rows;
      await Promise.all(chunks.filter(chunk => chunk.upload_md5).map(chunk => this.configured().delete(stagingKey(chunk.object_key))));
      await db.query('SELECT 1');
      await Promise.all(chunks.map(chunk => this.configured().delete(chunk.object_key)));
      for (const chunk of chunks) {
        await db.query('DELETE FROM cloud_chunks WHERE file_id=$1 AND chunk_index=$2', [id, chunk.chunk_index]);
      }
      const removed = await db.query('DELETE FROM cloud_files WHERE id=$1 AND NOT EXISTS(SELECT 1 FROM cloud_chunks WHERE file_id=$1)', [id]);
      return chunks.length === 0 || (removed.rowCount ?? 0) > 0;
    });
  }
  /** Recent removal markers; devices compare them with their local copies. */
  async tombstones(userId: string) {
    this.configured();
    return this.tx(async db => {
      const rows = (await db.query<{ id: string; kind: string; manifest_hash: string | null; meta: CloudFileMeta | null;
        reason: string; removed_at: Date }>(`SELECT id,kind,manifest_hash,meta,reason,removed_at FROM cloud_file_tombstones
        WHERE user_id=$1 AND removed_at > now() - make_interval(days => $2) ORDER BY removed_at DESC LIMIT 2000`,
        [userId, TOMBSTONE_DAYS])).rows;
      return { tombstones: rows.map(row => ({ id: row.id, kind: row.kind, manifestHash: row.manifest_hash,
        meta: row.meta ?? null, reason: row.reason, removedAt: row.removed_at.getTime() })) };
    });
  }

  async maintenance() {
    if (!this.store || this.cleaning) return;
    this.cleaning = true;
    try {
    // Bound maintenance work. Keep staging records until URL expiry plus an in-flight grace period.
    // A one-day bucket lifecycle on qingye/staging/ catches PUTs completing unusually late.
    const failures: unknown[] = [];
    const expiredStages = await this.tx(db => db.query<{ user_id: string; file_id: string; chunk_index: number }>(`
      SELECT f.user_id,c.file_id,c.chunk_index FROM cloud_chunks c JOIN cloud_files f ON f.id=c.file_id
      WHERE c.ready=true AND c.upload_expires_at<$1 ORDER BY c.upload_expires_at LIMIT 20`, [new Date(this.now() - CLEANUP_GRACE_MS)]));
    for (const stage of expiredStages.rows) {
      try { await this.tx(async db => {
        await this.lock(db, stage.user_id);
        const chunk = (await db.query<ChunkRow>(`SELECT * FROM cloud_chunks WHERE file_id=$1 AND chunk_index=$2
          AND ready=true AND upload_expires_at<$3`, [stage.file_id, stage.chunk_index, new Date(this.now() - CLEANUP_GRACE_MS)])).rows[0];
        if (chunk) {
          await this.configured().delete(stagingKey(chunk.object_key));
          await db.query('UPDATE cloud_chunks SET upload_expires_at=NULL WHERE file_id=$1 AND chunk_index=$2', [stage.file_id, stage.chunk_index]);
        }
      }); } catch (error) { failures.push(error); }
    }
    const files = await this.tx(async db => {
      await db.query(`DELETE FROM cloud_download_tickets WHERE (user_id,request_id) IN
        (SELECT user_id,request_id FROM cloud_download_tickets WHERE expires_at<now()-interval '1 day' LIMIT 1000)`);
      await db.query("UPDATE cloud_files SET state='DELETING' WHERE state='UPLOADING' AND updated_at<now()-interval '24 hours'");
      await db.query(`DELETE FROM cloud_file_tombstones WHERE id IN (SELECT id FROM cloud_file_tombstones
        WHERE removed_at < now() - make_interval(days => $1) LIMIT 1000)`, [TOMBSTONE_DAYS]);
      return (await db.query<FileRow>("SELECT * FROM cloud_files WHERE state='DELETING' ORDER BY updated_at LIMIT 20")).rows;
    });
    for (const file of files) {
      try { await this.cleanFile(file.user_id, file.id); } catch (error) { failures.push(error); }
    }
    if (failures.length) throw new AggregateError(failures, 'Cloud file cleanup incomplete');
    } finally { this.cleaning = false; }
  }
  private async transfer<T>(work: () => Promise<T>): Promise<T> {
    // Bound metadata verification/copy requests, leaving pool capacity for account and TTS traffic.
    if (this.activeTransfers >= 3) fail(429, 'CLOUD_BUSY', '云文件传输繁忙，请稍后重试');
    this.activeTransfers++;
    try { return await work(); } finally { this.activeTransfers--; }
  }
}
