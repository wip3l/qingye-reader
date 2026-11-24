// Builds <releases>/qingye-membership-codes-20261123 (folder, .zip and .zip.sha256): rechargeRoutes.js and the
// code tool replaced whole, migration 035 and the qingye-codes command. Run from server/ after `npm run build`
// and `npm test`:
//   node scripts/membership-codes-update/package.mjs [RELEASES_DIR]
// RELEASES_DIR (default server/release) must hold qingye-recharge-20261123, whose runtime files are installed.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync, copyFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import ts from 'typescript';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const releases = resolve(process.argv[2] || resolve(server, 'release'));
const previousRelease = 'qingye-recharge-20261123';
const release = 'qingye-membership-codes-20261123';
const output = resolve(releases, release);
const migrations = ['035_membership_redeem_codes.sql'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const compile = source => normalize(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText);

const built = compile(readFileSync(resolve(server, 'src/rechargeRoutes.ts'), 'utf8'));
assert.equal(built, normalize(readFileSync(resolve(server, 'dist/rechargeRoutes.js'), 'utf8')),
  'rechargeRoutes: dist is stale or differs from transpileModule; run npm run build');
const files = {
  'rechargeRoutes.js': built,
  'redeem-codes.mjs': normalize(readFileSync(resolve(server, 'scripts/redeem-codes.mjs'), 'utf8'))
};
const previous = {};
for (const name of Object.keys(files)) {
  const path = resolve(releases, previousRelease, 'runtime', name);
  assert(existsSync(path), `${path} missing; pass the folder holding earlier releases`);
  previous[name] = normalize(readFileSync(path, 'utf8'));
  assert.notEqual(previous[name], files[name], `${name}: nothing to update`);
}

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime/previous', 'src', 'migrations', 'test-migrations']) mkdirSync(resolve(output, dir), { recursive: true });
for (const [name, text] of Object.entries(files)) {
  writeFileSync(resolve(output, 'runtime', name), text);
  writeFileSync(resolve(output, 'runtime/previous', name), previous[name]);
}
copyFileSync(resolve(server, 'src/rechargeRoutes.ts'), resolve(output, 'src/rechargeRoutes.ts'));
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'membership-codes-pg-check.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/membership-codes-pg-check.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'check.mjs', 'qingye-codes', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, previousRelease, sourceCommit: commit,
  uncommittedChanges: dirty, replaced: Object.keys(files), added: ['/usr/local/bin/qingye-codes'], migrations },
null, 2) + '\n');

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
        info = zipfile.ZipInfo(name, (2026, 11, 23, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(os.path.join(root, name), 'rb') as f:
            z.writestr(info, f.read())
`, output, zipPath, ...list(output)]);
const zipSum = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
writeFileSync(`${zipPath}.sha256`, `${zipSum} *${release}.zip\n`);
console.log('PASS: build parity; installed files taken from', previousRelease);
console.log(zipPath, zipSum, dirty ? '(built from uncommitted changes)' : '');
