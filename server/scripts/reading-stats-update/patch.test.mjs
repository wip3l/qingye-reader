import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { patchIndex, route } from './patch.mjs';

const compiled = readFileSync(new URL('../../dist/index.js', import.meta.url), 'utf8');
const importLine = "import { exchangeReadingStats } from './readingStats.js';\n";
const baseline = compiled.replace(importLine, '').replace(route, '');
test('patch matches compiled route and preserves unrelated deployed changes', () => {
  assert.equal(patchIndex(baseline), compiled);
  const customized = baseline.replace("app.post('/v1/auth/logout'", "// deployed hotfix\napp.post('/v1/auth/logout'");
  assert(patchIndex(customized).includes('// deployed hotfix'));
  assert.equal(patchIndex(patchIndex(customized)), patchIndex(customized));
});
test('handles CRLF and does not rewrite an installed module', () => {
  assert.equal(patchIndex(baseline.replace(/\n/g, '\r\n')), compiled);
  const installed = compiled.replace(/\n/g, '\r\n');
  assert.equal(patchIndex(installed), installed);
});
test('rejects missing anchors, duplicate routes and partial installations', () => {
  assert.throws(() => patchIndex(baseline.replace('/v1/auth/logout', '/v2/auth/logout')));
  assert.throws(() => patchIndex(compiled + route));
  assert.throws(() => patchIndex(compiled.replace(importLine, '')));
  assert.throws(() => patchIndex(compiled.replace('bodyLimit: 1024 * 1024', 'bodyLimit: 2048')));
});
test('packaged runtime passes offline validation', () => {
  const dir = mkdtempSync(join(tmpdir(), 'reading-stats-package-'));
  try {
    writeFileSync(join(dir, 'index.js'), patchIndex(baseline));
    writeFileSync(join(dir, 'readingStats.js'), readFileSync(new URL('../../dist/readingStats.js', import.meta.url)));
    const result = execFileSync(process.execPath, [fileURLToPath(new URL('./check.mjs', import.meta.url)), dir], { encoding: 'utf8' });
    assert.match(result, /PASS:/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
