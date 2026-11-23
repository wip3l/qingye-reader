// Raises the single-item limit for custom_theme_schemes from 64KB to 960KB in the live sync.js.
// Anchors only the statements being changed and tolerates whitespace drift from earlier patches.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const CONSTANT = 'const MAX_THEME_SCHEMES_PAYLOAD_BYTES = 960 * 1024;';
const SELECTOR = "entityType === 'custom_theme_schemes' ? MAX_THEME_SCHEMES_PAYLOAD_BYTES : MAX_PAYLOAD_BYTES";

function replaceOnce(source, pattern, replacement) {
  const matches = source.match(new RegExp(pattern.source, pattern.flags.includes('g') ? pattern.flags : pattern.flags + 'g'));
  assert.equal(matches?.length ?? 0, 1, 'BASELINE_MISMATCH: installed sync.js differs; no live files changed');
  return source.replace(pattern, replacement);
}

/** Returns the patched module; an already patched module comes back unchanged. */
export function patchModule(source) {
  const text = source.replace(/\r\n/g, '\n');
  const hasConstant = text.includes(CONSTANT);
  const hasSelector = text.includes(SELECTOR);
  if (hasConstant && hasSelector) return source;
  assert(!hasConstant && !hasSelector, 'BASELINE_MISMATCH: partially patched sync.js; no live files changed');
  let result = replaceOnce(text, /^(const MAX_PAYLOAD_BYTES\s*=\s*64\s*\*\s*1024;)$/m,
    (_, line) => `${line}\n${CONSTANT}`);
  result = replaceOnce(result,
    /(const maxPayloadBytes\s*=\s*entityType\s*===\s*'book_source'\s*\?\s*maxBookSourceBytes\s*:)\s*MAX_PAYLOAD_BYTES\s*;/,
    (_, head) => `${head} ${SELECTOR};`);
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [input, output] = process.argv.slice(2);
  assert(input && output && resolve(input) !== resolve(output), 'Usage: node patch.mjs INPUT_DIR OUTPUT_DIR');
  writeFileSync(resolve(output, 'sync.js'), patchModule(readFileSync(resolve(input, 'sync.js'), 'utf8')));
  console.log('PASS: prepared custom theme sync limit patch for sync.js');
}
