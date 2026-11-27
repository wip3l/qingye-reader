// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded; no database access.
// Loads the patched sync.js and accountAuth.js, checks the history exports, that account deletion purges the new
// table, and that index.js mounts the two history routes.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const sync = await import(pathToFileURL(resolve(root, 'sync.js')).href);
for (const name of ['exchangeSync', 'applyOperation', 'listSyncHistory', 'restoreSyncHistory', 'restoreSyncHistoryIn',
  'normalizeOperation', 'registerDevice']) {
  assert.equal(typeof sync[name], 'function', `${name} missing`);
}
assert.equal(sync.HISTORY_KEEP_PER_ENTITY, 10);
assert.equal(sync.HISTORY_KEEP_DAYS, 90);
assert.equal(sync.HISTORY_MAX_BYTES_PER_USER, 3 * 1024 * 1024);
assert.deepEqual([...sync.HISTORY_ENTITY_TYPES].sort(), ['appearance_mode', 'bookshelf_display', 'custom_theme_schemes',
  'reader_settings', 'replace_rule', 'search_preferences', 'theme_settings']);
// Invalid restore requests are refused before any database use.
const someone = '00000000-0000-4000-8000-000000000001';
await assert.rejects(sync.restoreSyncHistory(someone, { deviceId: 'x', historyIds: ['1'] }),
  e => e?.code === 'INVALID_DEVICE_ID');
await assert.rejects(sync.restoreSyncHistory(someone, { deviceId: '123e4567-e89b-42d3-a456-426614174000',
  historyIds: ['abc'] }), e => e?.code === 'INVALID_SYNC_HISTORY');
// The existing per-type size limits are unchanged.
assert.equal(sync.normalizeOperation({ opId: '123e4567-e89b-42d3-a456-426614174000', entityType: 'custom_theme_schemes',
  entityId: 'global', operation: 'upsert', baseRevision: 0, payload: { v: 'x'.repeat(900 * 1024) } }).entityType,
'custom_theme_schemes');

const auth = await import(pathToFileURL(resolve(root, 'accountAuth.js')).href);
assert(auth.DELETION_PURGES_TABLES.includes('sync_entity_history'), 'account deletion purges the history table');
assert.equal(typeof auth.registerAccountAuthRoutes, 'function');

const index = readFileSync(resolve(root, 'index.js'), 'utf8');
assert(index.includes("app.get('/v1/sync/history'"), 'index.js mounts GET /v1/sync/history');
assert(index.includes("app.post('/v1/sync/history/restore'"), 'index.js mounts POST /v1/sync/history/restore');
assert(/listSyncHistory,[\s\S]*restoreSyncHistory,[\s\S]*\} from '\.\/sync\.js'/.test(index), 'index.js imports both');
console.log('PASS: candidate sync.js loads with the live modules; index.js mounts the settings history routes');
process.exit(0);
