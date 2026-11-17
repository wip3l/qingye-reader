// Runs the candidate cloudFileService.js in memory: theme metadata rules, prepare and list (no network/database).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';

const runtime = resolve(process.argv[2] || '.');
const inserted = [];
const created = new Date('2026-11-16T08:00:00Z');
const db = { query: async (sql, params) => {
  if (sql.includes('pg_advisory_xact_lock')) return { rows: [] };
  if (sql.startsWith('SELECT * FROM cloud_files WHERE user_id=$1 AND request_id=$2')) return { rows: [] };
  if (sql.includes("state='UPLOADING'") && sql.startsWith('SELECT count(*)')) return { rows: [{ count: '0' }] };
  if (sql.includes('AS bytes')) return { rows: [{ bytes: '0' }] };
  if (sql.startsWith('INSERT INTO cloud_files')) { inserted.push(params); return { rows: [], rowCount: 1 }; }
  if (sql.startsWith('SELECT * FROM cloud_files WHERE user_id=$1') && sql.includes('ORDER BY id')) {
    return { rows: inserted.map(row => ({ id: row[0], user_id: row[1], kind: row[3], name: row[4], bytes: String(row[5]),
      state: 'UPLOADING', manifest_hash: null, meta: row[7] ? JSON.parse(row[7]) : null, created_at: created })) };
  }
  throw new Error(`Unexpected database operation: ${sql}`);
} };
class MembershipError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
let ids = 0;
const context = vm.createContext({
  MembershipError, Buffer, console,
  membershipSnapshot: async () => ({ active: true, state: { sku: 'SUPER_LIFETIME' } }),
  cloudQuotaBytes: async () => 1024 ** 3,
  membershipCalendarCycle: () => ({ index: 0, endsAt: 0 }),
  createHash: () => { throw new Error('No hashing expected'); },
  randomUUID: () => `00000000-0000-4000-8000-00000000000${ids++}`
});
const source = readFileSync(resolve(runtime, 'cloudFileService.js'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
vm.runInContext(source, context, { filename: 'cloudFileService.js' });
const normalize = vm.runInContext('normalizeMeta', context);
assert.equal(normalize({ packageId: 'custom-0a1b2c' }).packageId, 'custom-0a1b2c');
assert.equal(normalize({ schemeId: 'custom_1731234567_import' }).schemeId, 'custom_1731234567_import');
for (const bad of ['../x', 'a/b', '', 'x'.repeat(161)]) {
  assert.throws(() => normalize({ packageId: bad }), { code: 'CLOUD_INVALID_FILE' });
}
assert.equal(normalize({ mediaCategory: 'comic' }).mediaCategory, 'comic'); // Earlier rules unchanged.
assert.throws(() => normalize({ secret: 'no' }), { code: 'CLOUD_INVALID_FILE' });
const Service = vm.runInContext('CloudFileService', context);
const service = new Service(async work => work(db), {});
const base = { name: 'theme-custom-0a1b2c.zip', kind: 'THEME', bytes: 3 };
await assert.rejects(service.prepare('owner', { ...base, requestId: 'request-1' }), { code: 'CLOUD_INVALID_FILE' });
await assert.rejects(service.prepare('owner', { ...base, requestId: 'request-2',
  meta: { packageId: 'custom-1', schemeId: 'custom_1' } }), { code: 'CLOUD_INVALID_FILE' });
await assert.rejects(service.prepare('owner', { ...base, kind: 'OTHER', requestId: 'request-3',
  meta: { packageId: 'custom-1' } }), { code: 'CLOUD_INVALID_FILE' });
const theme = await service.prepare('owner', { ...base, requestId: 'request-4',
  meta: { packageId: 'custom-0a1b2c', contentHash: 'b'.repeat(64) } });
assert.equal(theme.state, 'UPLOADING');
assert.equal(inserted.length, 1);
assert.equal(inserted[0][3], 'THEME');
const book = await service.prepare('owner', { requestId: 'request-5', name: 'a.txt', kind: 'BOOK', bytes: 3 });
assert.equal(book.state, 'UPLOADING');
const listed = await service.list('owner');
assert.equal(listed.files[0].kind, 'THEME');
assert.equal(listed.files[0].meta.packageId, 'custom-0a1b2c');
assert.equal(listed.files[0].createdAt, created.getTime());
console.log('PASS: theme metadata, prepare rules, book uploads and listed creation time (no network/database access)');
