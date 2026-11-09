// Preflight in a candidate copy of the runtime (cwd), with the service environment loaded.
// Loads the patched sync module and checks that annotations are accepted while unknown types are still refused.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sync = await import(pathToFileURL(resolve(process.cwd(), 'sync.js')).href);
const operation = entityType => ({
  opId: '123e4567-e89b-42d3-a456-426614174000',
  entityType,
  entityId: 'annotation_preflight',
  operation: 'upsert',
  baseRevision: 0,
  payload: { bookUrl: 'https://book.test/1', quote: '原文', note: '想法', style: 'wavy', createTime: 1 }
});
assert.equal(sync.normalizeOperation(operation('book_annotation')).entityType, 'book_annotation');
assert.equal(sync.normalizeOperation(operation('bookmark')).entityType, 'bookmark');
assert.throws(() => sync.normalizeOperation(operation('not_a_type')), error => error?.code === 'INVALID_ENTITY_TYPE');
console.log('PASS: candidate module loads; book_annotation accepted, unknown types still refused');
process.exit(0);
