import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function patchModule(source, changes) {
  let result = source.replace(/\r\n/g, '\n');
  let changed = false;
  for (const { before, after } of changes) {
    assert(before && after && before !== after, 'Invalid patch');
    const newCount = result.split(after).length - 1;
    if (newCount === 1) continue;
    assert.equal(newCount, 0, 'Ambiguous installed patch');
    assert.equal(result.split(before).length - 1, 1,
      'BASELINE_MISMATCH: installed module differs; no live files changed');
    result = result.replace(before, () => after);
    changed = true;
  }
  return changed ? result : source;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [input, output] = process.argv.slice(2);
  assert(input && output && resolve(input) !== resolve(output), 'Usage: node patch.mjs INPUT_DIR OUTPUT_DIR');
  const patches = JSON.parse(readFileSync(new URL('./patch.json', import.meta.url), 'utf8'));
  const candidates = Object.entries(patches).map(([name, changes]) => {
    assert(['cloudFileService.js', 'cloudFileRoutes.js'].includes(name));
    return [name, patchModule(readFileSync(resolve(input, name), 'utf8'), changes)];
  });
  for (const [name, source] of candidates) writeFileSync(resolve(output, name), source);
  console.log('PASS: prepared cloud book category patch');
}
