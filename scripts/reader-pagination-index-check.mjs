import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/core/reader/ReaderPaginationIndex.ts', import.meta.url), 'utf8');
const Index = vm.runInNewContext(stripTypeScriptTypes(source.replace(/^export /gm, ''), { mode: 'strip' }) + '\nReaderPaginationIndex');
for (const text of ['甲😀乙\n丙丁\n\n最后。', 'a'.repeat(1000), '\n正文\n', '']) {
  const result = { source: text, pages: [], starts: [], ends: [] };
  const bounds = [];
  const expected = { pages: [], starts: [], ends: [] };
  for (let end = 1; end <= text.length; end++) {
    bounds.push({ sourceStart: end - 1, sourceEnd: end });
    Index.append(result, bounds, false);
    assert.equal(result.pages.join(''), text.substring(0, end));
    assert.equal(result.cursor, end);
    assert.equal(result.complete, false);
    if (end > 1) assert.equal(result.starts[end - 1], end - 1);
  }
  Index.append(result, bounds, true);
  assert.equal(result.pages.join(''), text);
  assert.equal(result.cursor, text.length);
  assert.equal(result.complete, true);
  for (let i = 0; i < result.pages.length; i++) {
    assert.equal(result.pages[i], text.substring(result.starts[i], result.ends[i]));
    if (i) assert.equal(result.starts[i], result.ends[i - 1]);
  }
}
const partial = { source: '甲乙\n\n丙丁\n\n', pages: [], starts: [], ends: [] };
const boundaries = [{ sourceStart: 0, sourceEnd: 2 }];
Index.append(partial, boundaries, false);
assert.equal(partial.pages[0], '甲乙');
boundaries.push({ sourceStart: 4, sourceEnd: 6 });
Index.append(partial, boundaries, false);
assert.equal(partial.pages[0], '甲乙\n\n', 'the previous tail owns whitespace before the next page');
Index.append(partial, boundaries, true);
assert.equal(partial.pages[1], '丙丁\n\n', 'completion extends the last page to source end');
const before = JSON.stringify(partial);
Index.append(partial, boundaries, true);
assert.equal(JSON.stringify(partial), before, 'repeated completion is idempotent');

// Touching at most the former tail plus one new boundary makes repeated single-page appends linear.
let reads = 0;
const large = { source: '字'.repeat(2000), pages: [], starts: [], ends: [] };
const measured = [];
for (let i = 0; i < 2000; i++) {
  let from = i, to = i + 1;
  measured.push({ get sourceStart() { reads++; return from; }, set sourceStart(value) { from = value; },
    get sourceEnd() { reads++; return to; }, set sourceEnd(value) { to = value; } });
  Index.append(large, measured, false);
}
assert(reads < 2000 * 12, `incremental index revisited old pages (${reads} reads)`);
console.log('PASS: incremental pagination offsets, Unicode, whitespace ownership, completion and linear append work');
