// Builds <releases>/qingye-membership-tier-20261124 (folder, .zip and .zip.sha256): one anchored edit for
// membershipService.js, no migration. Run from server/ after `npm run build` and `npm test`:
//   node scripts/membership-tier-update/package.mjs [RELEASES_DIR]
// RELEASES_DIR (default server/release) must hold qingye-lottery-20261030, the last build that shipped this module.
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
const releases = resolve(process.argv[2] || resolve(server, 'release'));
const release = 'qingye-membership-tier-20261124';
const output = resolve(releases, release);
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const dist = resolve(server, 'dist');
const check = dir => execFileSync(process.execPath, [resolve(here, 'check.mjs'), dir, dist], { stdio: 'inherit' });

const baseline = normalize(readFileSync(resolve(releases, 'qingye-lottery-20261030/runtime/membershipService.js'), 'utf8'));
const variants = [baseline,
  // Line endings and a hand-edited doc comment must not matter.
  baseline.replace(/\n/g, '\r\n'),
  baseline.replace(/ \* The product that pays for `now`[^\n]*\n/, ' * Edited by hand.\n')];
assert.notEqual(variants[2], baseline);
const scratch = mkdtempSync(join(tmpdir(), 'membership-tier-variants-'));
try {
  variants.forEach((source, index) => {
    const patched = patchModule(source);
    assert.notEqual(patched, source, `variant ${index}: nothing patched`);
    assert.equal(patchModule(patched), patched, `variant ${index}: patch must be idempotent`);
    assert.equal(patchModule('// unrelated\n' + source), '// unrelated\n' + patched, `variant ${index}: keeps unrelated code`);
    const dir = resolve(scratch, String(index));
    mkdirSync(dir);
    writeFileSync(resolve(dir, 'membershipService.js'), patched);
    check(dir);
  });
} finally { rmSync(scratch, { recursive: true, force: true }); }
assert.throws(() => patchModule(''), /BASELINE_MISMATCH/);
// The patched lottery build is the current compiled module, so the package matches what the tests ran.
assert.equal(patchModule(baseline), normalize(readFileSync(resolve(dist, 'membershipService.js'), 'utf8')),
  'patched baseline differs from dist/membershipService.js');

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src']) mkdirSync(resolve(output, dir), { recursive: true });
// Reference result on the lottery build, for reading only; update.sh patches the live file itself.
writeFileSync(resolve(output, 'runtime/membershipService.js'), patchModule(baseline));
copyFileSync(resolve(server, 'src/membershipService.ts'), resolve(output, 'src/membershipService.ts'));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, sourceCommit: commit,
  uncommittedChanges: dirty, patched: ['membershipService.js'], migrations: [] }, null, 2) + '\n');

function list(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? list(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = list(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');

const zipPath = resolve(releases, `${release}.zip`);
rmSync(zipPath, { force: true });
execFileSync('python', ['-I', '-c', `
import os, sys, zipfile
root, target = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(sys.argv[3:]):
        info = zipfile.ZipInfo(name, (2026, 11, 24, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(os.path.join(root, name), 'rb') as f:
            z.writestr(info, f.read())
`, output, zipPath, ...list(output)]);
const zipSum = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
writeFileSync(`${zipPath}.sha256`, `${zipSum} *${release}.zip\n`);
console.log(`PASS: ${variants.length} baseline variants patched, idempotent, verified by running them; empty input rejected`);
console.log(zipPath, zipSum, dirty ? '(built from uncommitted changes)' : '');
