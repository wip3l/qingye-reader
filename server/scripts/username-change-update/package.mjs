// Builds <releases>/qingye-username-change-20261125 (folder, .zip and .zip.sha256): exact compiled hunks for
// accountAuth.js and migration 036. Run from server/ after `npm run build` and `npm test`:
//   node scripts/username-change-update/package.mjs [RELEASES_DIR]
// RELEASES_DIR (default server/release) must hold the releases whose runtime/accountAuth.js may be installed:
// qingye-recharge-20261123 and, before it, qingye-password-account-20261114.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync, mkdtempSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import ts from 'typescript';
import { patchModule } from './patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const releases = resolve(process.argv[2] || resolve(server, 'release'));
// Last commit that changed accountAuth.ts before this work; it compiles to the recharge release's runtime file.
const baseline = 'eea2e935';
const installed = { current: 'qingye-recharge-20261123', previous: 'qingye-password-account-20261114' };
const release = 'qingye-username-change-20261125';
const output = resolve(releases, release);
const migrations = ['036_username_change.sql'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const compile = source => normalize(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText);
const runtimeOf = name => {
  const file = resolve(releases, name, 'runtime/accountAuth.js');
  assert(existsSync(file), `${file} missing; pass the folder holding earlier releases`);
  return normalize(readFileSync(file, 'utf8'));
};

/** Unified-diff hunks of two texts, each widened until its before/after text is unique. */
function hunks(before, after, context) {
  const dir = mkdtempSync(join(tmpdir(), 'username-diff-'));
  try {
    writeFileSync(join(dir, 'a'), before);
    writeFileSync(join(dir, 'b'), after);
    const diff = spawnSync('git', ['diff', '--no-index', '--no-color', `-U${context}`, 'a', 'b'], { cwd: dir, encoding: 'utf8' });
    assert(diff.status === 1, 'expected differences');
    const result = [];
    let current = null;
    for (const line of diff.stdout.split('\n')) {
      if (line.startsWith('@@')) { current = { before: [], after: [] }; result.push(current); continue; }
      if (!current || line.startsWith('\\')) continue;
      const body = line.slice(1);
      if (line[0] === ' ') { current.before.push(body); current.after.push(body); }
      else if (line[0] === '-') current.before.push(body);
      else if (line[0] === '+') current.after.push(body);
    }
    return result.map(h => ({ before: h.before.join('\n') + '\n', after: h.after.join('\n') + '\n' }));
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

const old = compile(git('show', `${baseline}:server/src/accountAuth.ts`));
assert.equal(runtimeOf(installed.current), old, `baseline differs from ${installed.current}`);
const current = compile(readFileSync(resolve(server, 'src/accountAuth.ts'), 'utf8'));
assert.equal(current, normalize(readFileSync(resolve(server, 'dist/accountAuth.js'), 'utf8')),
  'accountAuth: dist is stale or differs from transpileModule; run npm run build');
let changes = null;
for (const context of [3, 6, 10, 16]) {
  const candidate = hunks(old, current, context);
  try {
    assert.equal(patchModule(old, candidate), current);
    changes = candidate;
    break;
  } catch { /* widen the context */ }
}
assert(changes, 'accountAuth: no unambiguous patch');
assert.equal(patchModule(current, changes), current, 'patch must be idempotent');
assert.equal(patchModule('// unrelated\n' + old, changes), '// unrelated\n' + current, 'keeps unrelated code');
assert.throws(() => patchModule('', changes), /BASELINE_MISMATCH/);
// A server that never installed the recharge package still runs the password-account build; the same hunks
// apply there and leave its one difference (recharge_orders in the deletion keep list) alone.
const previous = runtimeOf(installed.previous);
const previousPatched = patchModule(previous, changes);
assert.notEqual(previousPatched, previous);
assert.equal(patchModule(previousPatched, changes), previousPatched);
assert(!previousPatched.includes("'recharge_orders'") && previousPatched.includes('export async function changeUsername('));

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations', 'test-migrations']) mkdirSync(resolve(output, dir), { recursive: true });
writeFileSync(resolve(output, 'runtime/accountAuth.js'), current);
writeFileSync(resolve(output, 'runtime/accountAuth.pre-recharge.js'), previousPatched);
copyFileSync(resolve(server, 'src/accountAuth.ts'), resolve(output, 'src/accountAuth.ts'));
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
// The server's own migrations folder is stale; the disposable test database uses the complete set.
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'username-change-pg-check.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/username-change-pg-check.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
writeFileSync(resolve(output, 'patch.json'), JSON.stringify({ 'accountAuth.js': changes }, null, 2) + '\n');
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, baseline, installedFrom: installed,
  sourceCommit: commit, uncommittedChanges: dirty, patched: ['accountAuth.js'], added: [], migrations }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');

// ZIP with the files at its root (README: unzip -d "$stage"); stored with fixed timestamps.
const zipPath = resolve(releases, `${release}.zip`);
rmSync(zipPath, { force: true });
execFileSync('python', ['-I', '-c', `
import os, sys, zipfile
root, target = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(sys.argv[3:]):
        info = zipfile.ZipInfo(name, (2026, 11, 25, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(os.path.join(root, name), 'rb') as f:
            z.writestr(info, f.read())
`, output, zipPath, ...files(output)]);
const zipSum = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
writeFileSync(`${zipPath}.sha256`, `${zipSum} *${release}.zip\n`);
console.log('PASS: exact build parity, idempotence, baseline rejection, both installed runtime baselines patch cleanly');
console.log('Hunks: accountAuth.js', changes.length);
console.log(zipPath, zipSum, dirty ? '(built from uncommitted changes)' : '');
