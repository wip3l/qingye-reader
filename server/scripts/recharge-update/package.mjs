// Builds <releases>/qingye-recharge-20261123 (folder, .zip and .zip.sha256): exact compiled hunks for index.js,
// config.js and accountAuth.js, three new modules, the redeem-code tool and migration 034.
// Run from server/ after `npm run build` and `npm test`:
//   node scripts/recharge-update/package.mjs [RELEASES_DIR]
// RELEASES_DIR (default server/release) must hold the earlier releases whose runtime/ files are installed:
// qingye-password-account-20261114 (index.js, accountAuth.js) and qingye-lottery-20261030 (config.js).
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
// Last commit before the recharge work (#6); the three patched modules compile to exactly what is installed.
const baseline = 'a26ed457';
const installedFrom = {
  index: 'qingye-password-account-20261114',
  accountAuth: 'qingye-password-account-20261114',
  config: 'qingye-lottery-20261030'
};
const release = 'qingye-recharge-20261123';
const output = resolve(releases, release);
const patched = ['index', 'config', 'accountAuth'];
const added = ['alipay', 'pointCredit', 'rechargeRoutes'];
const tools = ['redeem-codes.mjs'];
const migrations = ['034_recharge.sql'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const compile = source => normalize(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText);
const built = name => {
  const current = compile(readFileSync(resolve(server, `src/${name}.ts`), 'utf8'));
  assert.equal(current, normalize(readFileSync(resolve(server, `dist/${name}.js`), 'utf8')),
    `${name}: dist is stale or differs from transpileModule; run npm run build`);
  return current;
};

/** Unified-diff hunks of two texts, each widened until its before/after text is unique. */
function hunks(before, after, context) {
  const dir = mkdtempSync(join(tmpdir(), 'recharge-diff-'));
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

const patches = {};
const current = {};
for (const name of patched) {
  const old = compile(git('show', `${baseline}:server/src/${name}.ts`));
  // What the server runs now is the runtime file of the release that last replaced it.
  const installed = resolve(releases, installedFrom[name], 'runtime', `${name}.js`);
  assert(existsSync(installed), `${installed} missing; pass the folder holding earlier releases`);
  assert.equal(normalize(readFileSync(installed, 'utf8')), old, `${name}: baseline differs from ${installedFrom[name]}`);
  current[name] = built(name);
  let changes = null;
  for (const context of [3, 6, 10, 16]) {
    const candidate = hunks(old, current[name], context);
    try {
      assert.equal(patchModule(old, candidate), current[name]);
      changes = candidate;
      break;
    } catch { /* widen the context */ }
  }
  assert(changes, `${name}: no unambiguous patch`);
  assert.equal(patchModule(current[name], changes), current[name], `${name}: patch must be idempotent`);
  assert.equal(patchModule('// unrelated\n' + old, changes), '// unrelated\n' + current[name], `${name}: keeps unrelated code`);
  assert.throws(() => patchModule('', changes), /BASELINE_MISMATCH/);
  patches[`${name}.js`] = changes;
}
for (const name of added) current[name] = built(name);

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations', 'test-migrations']) mkdirSync(resolve(output, dir), { recursive: true });
for (const name of [...patched, ...added]) {
  writeFileSync(resolve(output, `runtime/${name}.js`), current[name]);
  copyFileSync(resolve(server, `src/${name}.ts`), resolve(output, `src/${name}.ts`));
}
for (const name of tools) {
  writeFileSync(resolve(output, 'runtime', name), normalize(readFileSync(resolve(server, 'scripts', name), 'utf8')));
}
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
// The server's own migrations folder is stale; the disposable test database uses the complete set.
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'recharge-pg-check.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/recharge-pg-check.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
writeFileSync(resolve(output, 'patch.json'), JSON.stringify(patches, null, 2) + '\n');
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, baseline, installedFrom, sourceCommit: commit,
  uncommittedChanges: dirty, patched: patched.map(n => n + '.js'), added: [...added.map(n => n + '.js'), ...tools],
  migrations }, null, 2) + '\n');

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
        info = zipfile.ZipInfo(name, (2026, 11, 23, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(os.path.join(root, name), 'rb') as f:
            z.writestr(info, f.read())
`, output, zipPath, ...files(output)]);
const zipSum = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
writeFileSync(`${zipPath}.sha256`, `${zipSum} *${release}.zip\n`);
console.log('PASS: exact build parity, idempotence, baseline rejection, installed runtime baselines');
console.log('Hunks:', Object.entries(patches).map(([n, c]) => `${n} ${c.length}`).join(', '));
console.log(zipPath, zipSum, dirty ? '(built from uncommitted changes)' : '');
