import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';

const runtime = resolve(process.argv[2] || '.');
let row = { id: '11111111-1111-1111-1111-111111111111', user_id: 'owner', state: 'READY',
  meta: { title: '旧漫画', format: 'epub', contentHash: 'a'.repeat(64) } };
let writes = 0;
const db = { query: async (sql, params) => {
  if (sql.includes('pg_advisory_xact_lock')) return { rows: [] };
  if (sql.startsWith('SELECT * FROM cloud_files WHERE id=')) {
    return { rows: row.id === params[0] && row.user_id === params[1] ? [row] : [] };
  }
  if (sql.startsWith('UPDATE cloud_files SET meta=')) {
    assert.equal(params[0], row.id);
    row.meta = JSON.parse(params[1]); writes++;
    return { rows: [], rowCount: 1 };
  }
  throw new Error(`Unexpected database operation: ${sql}`);
} };
class MembershipError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const context = vm.createContext({
  MembershipError, Buffer, console,
  membershipSnapshot: async (_db, user) => ({ active: user !== 'free', state: { sku: 'SUPER_LIFETIME' } }),
  createHash: () => { throw new Error('No file hashing expected'); },
  randomUUID: () => { throw new Error('No new file expected'); }
});
for (const name of ['cloudFileService.js', 'cloudFileRoutes.js']) {
  const source = readFileSync(resolve(runtime, name), 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(source, context, { filename: name });
}
const normalize = vm.runInContext('normalizeMeta', context);
for (const category of ['comic', 'novel']) assert.equal(normalize({ mediaCategory: category }).mediaCategory, category);
for (const category of ['audio', '', 1, null]) {
  assert.throws(() => normalize({ mediaCategory: category }), { code: 'CLOUD_INVALID_FILE' });
}
assert.throws(() => normalize({ secret: 'no' }), { code: 'CLOUD_INVALID_FILE' });
assert.equal(normalize({ title: '旧小说' }).title, '旧小说');
const Service = vm.runInContext('CloudFileService', context);
const service = new Service(async work => work(db), {});
await service.fillMetadata('owner', row.id, { mediaCategory: 'comic' });
assert.equal(row.meta.mediaCategory, 'comic');
assert.equal(row.meta.title, '旧漫画');
await service.fillMetadata('owner', row.id, { mediaCategory: 'novel', title: 'overwrite' });
assert.equal(row.meta.mediaCategory, 'comic');
assert.equal(row.meta.title, '旧漫画');
await assert.rejects(service.fillMetadata('stranger', row.id, { mediaCategory: 'comic' }), { code: 'CLOUD_FILE_NOT_FOUND' });
await assert.rejects(service.fillMetadata('free', row.id, { mediaCategory: 'comic' }), { code: 'CLOUD_SUPER_REQUIRED' });
row.state = 'UPLOADING';
await assert.rejects(service.fillMetadata('owner', row.id, { mediaCategory: 'comic' }), { code: 'CLOUD_FILE_NOT_READY' });
row.state = 'READY';
assert.equal(writes, 2);
const routes = new Map();
const app = { get() {}, post(path, options, handler) { assert(!routes.has(path)); routes.set(path, { options, handler }); } };
let authenticated = 0, limited = 0;
vm.runInContext('registerCloudFileRoutes', context)(app, service, {
  authenticate: async () => { authenticated++; }, userId: () => 'owner', limit: async () => { limited++; }
});
const route = routes.get('/v1/cloud-files/:id/metadata');
assert(route);
assert.equal(route.options.bodyLimit, 4096);
const request = { params: { id: row.id }, body: { meta: { mediaCategory: 'comic' } } };
await route.options.preHandler(request, { header() {}, sent: false });
await route.handler(request);
assert.equal(authenticated, 1); assert.equal(limited, 1); assert.equal(writes, 3);
console.log('PASS: category validation, legacy backfill, ownership, membership, state and guarded route (no network/database access)');
