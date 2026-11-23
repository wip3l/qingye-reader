// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded.
// Loads the patched sync module and checks every per-type limit through its real normalization code.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sync = await import(pathToFileURL(resolve(process.cwd(), 'sync.js')).href);
const operation = (entityType, kib) => ({
  opId: '123e4567-e89b-42d3-a456-426614174000',
  entityType,
  entityId: 'global',
  operation: 'upsert',
  baseRevision: 0,
  payload: { value: 'x'.repeat(kib * 1024) }
});
const tooLarge = limit => error =>
  error?.code === 'SYNC_PAYLOAD_TOO_LARGE' && error.message === `单项同步数据不能超过 ${limit}KB`;
assert.equal(sync.normalizeOperation(operation('custom_theme_schemes', 900)).entityType, 'custom_theme_schemes');
assert.throws(() => sync.normalizeOperation(operation('custom_theme_schemes', 970)), tooLarge(960));
assert.throws(() => sync.normalizeOperation(operation('reader_settings', 70)), tooLarge(64));
assert.equal(sync.normalizeOperation(operation('book_source', 400)).entityType, 'book_source');
assert.throws(() => sync.normalizeOperation(operation('book_source', 600)), tooLarge(512));
console.log('PASS: candidate module loads; custom themes 960KB, book sources unchanged, other data 64KB');
process.exit(0);
