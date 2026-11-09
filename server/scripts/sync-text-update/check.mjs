// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded.
// Loads the patched modules and checks the cleaning on both sync paths; touches no database.
// argv[2]: where to write a cleaned payload for the read-only jsonb check in update.sh.
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const load = name => import(pathToFileURL(resolve(root, name)).href);
const NUL = String.fromCharCode(0);
const HIGH = String.fromCharCode(0xd83d);
const LOW = String.fromCharCode(0xde00);
const REPLACEMENT = String.fromCharCode(0xfffd);

const sync = await load('sync.js');
const operation = sync.normalizeOperation({
  opId: '123e4567-e89b-42d3-a456-426614174000',
  entityType: 'bookmark',
  entityId: 'bookmark_preflight',
  operation: 'upsert',
  baseRevision: 0,
  payload: { title: `a${NUL}b`, note: [`x${HIGH}`, `${LOW}y`, `${HIGH}${LOW}`], [`k${NUL}`]: 1 }
});
assert.deepEqual(operation.payload,
  { title: 'ab', note: [`x${REPLACEMENT}`, `${REPLACEMENT}y`, `${HIGH}${LOW}`], k: 1 });
const serialized = JSON.stringify(operation.payload);
assert.equal(operation.payloadBytes, Buffer.byteLength(serialized, 'utf8'));
assert(!serialized.includes(NUL) && !serialized.includes('\\u0000') && serialized.isWellFormed());

const stats = await load('readingStats.js');
const deviceId = randomUUID();
const start = Date.parse('2026-10-26T10:00:00Z');
const request = stats.normalizeReadingStats({ protocolVersion: 1, deviceId, cursor: 0, operations: [{
  recordId: randomUUID(), deleted: false, payload: { deviceId, deviceName: '手机',
    bookKey: 'https://source.test\nhttps://book.test/1', name: `书${NUL}名`, author: `作${HIGH}者`, coverUrl: '',
    dayKey: '2026-10-26', durationMs: 60000, startedAt: start, lastReadAt: start + 60000, timezoneOffset: 0 } }] });
assert.equal(request.operations[0].payload.name, '书名');
assert.equal(request.operations[0].payload.author, `作${REPLACEMENT}者`);

writeFileSync(process.argv[2], serialized);
console.log('PASS: candidate modules load; sync and reading-stats payload text is cleaned');
process.exit(0);
