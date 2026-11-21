// Builds release/qingye-coupon-upgrade-credit-20261119 (.zip source folder): anchored edits for
// membershipPolicy.js and migration 033. Run from server/ after `npm run build` and `npm test`.
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
const release = 'qingye-coupon-upgrade-credit-20261119';
const output = resolve(server, 'release', release);
const migrations = ['033_coupon_upgrade_credit.sql'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const check = dir => execFileSync(process.execPath, [resolve(here, 'check.mjs'), dir], { stdio: 'inherit' });

// The installed lottery build; the live file descends from it.
const baseline = normalize(readFileSync(resolve(server, 'release/qingye-lottery-20261030/runtime/membershipPolicy.js'), 'utf8'));
const variants = [baseline,
  // Line endings and a missing comment must not matter.
  baseline.replace(/\n/g, '\r\n'),
  baseline.replace(/ *\/\/ A later upgrade credits what this permanent product actually cost[^\n]*\n/, '')];
assert.notEqual(variants[2], baseline);
const scratch = mkdtempSync(join(tmpdir(), 'coupon-upgrade-credit-variants-'));
try {
  variants.forEach((source, index) => {
    const patched = patchModule(source);
    assert.notEqual(patched, source, `variant ${index}: nothing patched`);
    assert.equal(patchModule(patched), patched, `variant ${index}: patch must be idempotent`);
    assert.equal(patchModule('// unrelated\n' + source), '// unrelated\n' + patched, `variant ${index}: keeps unrelated code`);
    const dir = resolve(scratch, String(index));
    mkdirSync(dir);
    writeFileSync(resolve(dir, 'membershipPolicy.js'), patched);
    check(dir);
  });
} finally { rmSync(scratch, { recursive: true, force: true }); }
assert.throws(() => patchModule(''), /BASELINE_MISMATCH/);
// The patched lottery build is the current compiled module, so the package matches what the tests ran.
assert.equal(patchModule(baseline), normalize(readFileSync(resolve(server, 'dist/membershipPolicy.js'), 'utf8')),
  'patched baseline differs from dist/membershipPolicy.js');

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations']) mkdirSync(resolve(output, dir), { recursive: true });
// Reference result on the lottery build, for reading only; update.sh patches the live file itself.
writeFileSync(resolve(output, 'runtime/membershipPolicy.js'), patchModule(baseline));
copyFileSync(resolve(server, 'src/membershipPolicy.ts'), resolve(output, 'src/membershipPolicy.ts'));
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, sourceCommit: commit,
  uncommittedChanges: dirty, patched: ['membershipPolicy.js'], migrations }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log(`PASS: ${variants.length} baseline variants patched, idempotent, verified by running them; empty input rejected`);
console.log(output);
