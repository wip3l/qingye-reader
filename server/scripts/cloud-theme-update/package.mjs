// Builds release/qingye-cloud-theme-20261116 (.zip source folder): anchored edits for cloudFileService.js
// and migration 032. Run from server/ after `npm run build` and `npm test`.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync, mkdtempSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { patchModule } from './patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const release = 'qingye-cloud-theme-20261116';
const output = resolve(server, 'release', release);
const migrations = ['032_cloud_theme_files.sql'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const check = dir => execFileSync(process.execPath, [resolve(here, 'check.mjs'), dir], { stdio: 'inherit' });

// Earlier installed reference builds; the live file descends from them through hunk patches.
const baselines = ['qingye-lottery-20261030', 'qingye-cloud-book-category-20261025'].map(name =>
  normalize(readFileSync(resolve(server, `release/${name}/runtime/cloudFileService.js`), 'utf8')));
const variants = [...baselines,
  // Whitespace drift from older patches must not matter.
  baselines[0].replace("['BOOK', 'FONT', 'SOURCE']", "['BOOK','FONT','SOURCE']").replace(/\n/g, '\r\n'),
  baselines[0].replace('meta: row.meta ?? null })),', 'meta: row.meta ?? null\n            })),')];
const scratch = mkdtempSync(join(tmpdir(), 'cloud-theme-variants-'));
try {
  variants.forEach((source, index) => {
    const patched = patchModule(source);
    assert.notEqual(patched, source, `variant ${index}: nothing patched`);
    assert.equal(patchModule(patched), patched, `variant ${index}: patch must be idempotent`);
    assert.equal(patchModule('// unrelated\n' + source), '// unrelated\n' + patched, `variant ${index}: keeps unrelated code`);
    const dir = resolve(scratch, String(index));
    mkdirSync(dir);
    writeFileSync(resolve(dir, 'cloudFileService.js'), patched);
    check(dir);
  });
} finally { rmSync(scratch, { recursive: true, force: true }); }
assert.throws(() => patchModule(''), /BASELINE_MISMATCH/);

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations']) mkdirSync(resolve(output, dir), { recursive: true });
// Reference result on the lottery build, for reading only; update.sh patches the live file itself.
writeFileSync(resolve(output, 'runtime/cloudFileService.js'), patchModule(baselines[0]));
copyFileSync(resolve(server, 'src/cloudFileService.ts'), resolve(output, 'src/cloudFileService.ts'));
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, sourceCommit: commit,
  uncommittedChanges: dirty, patched: ['cloudFileService.js'], migrations }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log(`PASS: ${variants.length} baseline variants patched, idempotent, verified by running them; empty input rejected`);
console.log(output);
