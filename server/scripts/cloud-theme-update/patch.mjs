import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * The live cloudFileService.js is the product of several earlier hunk patches (rename, cloud categories,
 * lottery), so its surrounding code is not byte-identical to any clean build. Each change below only
 * anchors on the exact statement it edits, tolerates whitespace differences, and is skipped when present.
 */
const steps = [
  {
    name: 'theme metadata keys and file kinds',
    done: source => source.includes('const FILE_KINDS = ') && source.includes('const THEME_KEY = '),
    find: /const META_KEYS = new Set\(\[([^\]]*)\]\);/,
    replace: (match, keys) => {
      const list = keys.split(',').map(key => key.trim()).filter(Boolean);
      for (const key of ["'packageId'", "'schemeId'"]) if (!list.includes(key)) list.push(key);
      return `const META_KEYS = new Set([${list.join(', ')}]);\n` +
        '/** Files a device uploads itself. SOURCE is listed for old rows only; sources sync as data. */\n' +
        "const FILE_KINDS = ['BOOK', 'FONT', 'SOURCE', 'THEME'];\n" +
        "/** Custom themes: a theme pack (packageId) or one scheme's startup/preview images (schemeId). */\n" +
        'const THEME_KEY = /^[a-zA-Z0-9:_-]{1,160}$/;';
    }
  },
  {
    name: 'theme identifier validation',
    done: source => source.includes("'主题标识无效'"),
    find: /( *)for \(const \[key, item\] of Object\.entries\(value\)\) \{\n/,
    replace: (match, indent) => match +
      `${indent}    if ((key === 'packageId' || key === 'schemeId') && (typeof item !== 'string' || !THEME_KEY.test(item))) {\n` +
      `${indent}        fail(400, 'CLOUD_INVALID_FILE', '主题标识无效');\n` +
      `${indent}    }\n`
  },
  {
    name: 'creation time in file list',
    done: source => source.includes('createdAt: new Date(row.created_at).getTime()'),
    find: /manifestHash: row\.manifest_hash,(\s*)meta: row\.meta \?\? null\s*\}\)\)/,
    replace: (match, space) => `manifestHash: row.manifest_hash,${space}meta: row.meta ?? null,` +
      ' createdAt: new Date(row.created_at).getTime() }))'
  },
  {
    name: 'accepted upload kinds',
    done: source => source.includes('FILE_KINDS.includes(input.kind)'),
    find: /\[\s*'BOOK'\s*,\s*'FONT'\s*,\s*'SOURCE'\s*\]\.includes\(input\.kind\)/,
    replace: () => 'FILE_KINDS.includes(input.kind)'
  },
  {
    name: 'theme upload identifier rule',
    done: source => source.includes("'主题文件需要主题包或方案标识'"),
    find: /( *)const meta = normalizeMeta\(input\.meta\);\n/,
    replace: (match, indent) => match +
      `${indent}if (input.kind === 'THEME' && !meta?.packageId === !meta?.schemeId) {\n` +
      `${indent}    fail(400, 'CLOUD_INVALID_FILE', '主题文件需要主题包或方案标识');\n` +
      `${indent}}\n`
  }
];

/** Applies each missing change once; throws BASELINE_MISMATCH naming the step whose anchor is absent or ambiguous. */
export function patchModule(source) {
  let result = source.replace(/\r\n/g, '\n');
  let changed = false;
  for (const step of steps) {
    if (step.done(result)) continue;
    const global = new RegExp(step.find.source, 'g');
    const count = (result.match(global) || []).length;
    assert.equal(count, 1, `BASELINE_MISMATCH: cannot place "${step.name}" (${count} anchors); no live files changed`);
    result = result.replace(step.find, step.replace);
    assert(step.done(result), `Patch step did not apply: ${step.name}`);
    changed = true;
  }
  return changed ? result : source;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [input, output] = process.argv.slice(2);
  assert(input && output && resolve(input) !== resolve(output), 'Usage: node patch.mjs INPUT_DIR OUTPUT_DIR');
  const name = 'cloudFileService.js';
  writeFileSync(resolve(output, name), patchModule(readFileSync(resolve(input, name), 'utf8')));
  console.log('PASS: prepared cloud theme patch for', name);
}
