// Builds <releases>/qingye-sync-history-20261126 (folder, .zip and .zip.sha256): exact compiled hunks for sync.js,
// index.js and accountAuth.js plus migration 037. Run from server/ after `npm run build` and `npm test`:
//   node scripts/sync-history-update/package.mjs [RELEASES_DIR]
// RELEASES_DIR (default server/release) must hold the installed builds: qingye-theme-schemes-limit-20261117
// (sync.js, itself patched from qingye-book-mark-sync-20261114), qingye-recharge-20261123 (index.js) and
// qingye-username-change-20261125 (accountAuth.js).
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync, mkdtempSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import ts from 'typescript';
import { patchModule } from './patch.mjs';
import { patchModule as themeSchemesPatch } from '../theme-schemes-limit-update/patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const releases = resolve(process.argv[2] || resolve(server, 'release'));
const release = 'qingye-sync-history-20261126';
const output = resolve(releases, release);
const migrations = ['037_sync_entity_history.sql'];
// Last commits that changed each source before this work, and the release whose runtime file is installed.
const modules = [
  { name: 'sync.js', source: 'src/sync.ts', baseline: '045e2896', installed: 'qingye-theme-schemes-limit-20261117' },
  { name: 'index.js', source: 'src/index.ts', baseline: 'eea2e935', installed: 'qingye-recharge-20261123' },
  // Account deletion also purges the new history table.
  { name: 'accountAuth.js', source: 'src/accountAuth.ts', baseline: 'f4f25457', installed: 'qingye-username-change-20261125' }
];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
const squash = text => text.replace(/[ \t\r\n]/g, '');
const compile = source => normalize(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText);
const runtimeOf = (releaseName, name) => {
  const file = resolve(releases, releaseName, 'runtime', name);
  assert(existsSync(file), `${file} missing; pass the folder holding earlier releases`);
  return normalize(readFileSync(file, 'utf8'));
};

/** Unified-diff hunks of two texts. */
function hunks(before, after, context) {
  const dir = mkdtempSync(join(tmpdir(), 'sync-history-diff-'));
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
const references = {};
for (const module of modules) {
  const old = compile(git('show', `${module.baseline}:server/${module.source}`));
  const current = compile(readFileSync(resolve(server, module.source), 'utf8'));
  assert.equal(current, normalize(readFileSync(resolve(server, 'dist', module.name), 'utf8')),
    `${module.name}: dist is stale or differs from transpileModule; run npm run build`);
  const installed = runtimeOf(module.installed, module.name);
  let changes = null;
  for (const context of [3, 6, 10, 16]) {
    const candidate = hunks(old, current, context);
    try {
      assert.equal(patchModule(old, candidate), current);
      patchModule(installed, candidate);
      changes = candidate;
      break;
    } catch { /* widen the context */ }
  }
  assert(changes, `${module.name}: no unambiguous patch for both the baseline build and the installed runtime`);
  const reference = patchModule(installed, changes);
  assert.notEqual(reference, installed, `${module.name}: nothing patched`);
  assert.equal(patchModule(reference, changes), reference, `${module.name}: patch must be idempotent`);
  assert.equal(patchModule(current, changes), current, `${module.name}: patch must be idempotent on the new build`);
  assert.throws(() => patchModule('', changes), /BASELINE_MISMATCH/);
  // The installed runtime may differ from the baseline build (sync.js lost some comments and line breaks when the
  // theme-schemes package was patched in); the patch must carry exactly those differences over and nothing else.
  const removed = (a, b) => { const kept = new Set(b.split('\n')); return a.split('\n').filter(line => !kept.has(line)); };
  assert.deepEqual(removed(current, reference), removed(old, installed), `${module.name}: unexpected drift`);
  assert.deepEqual(removed(reference, current), removed(installed, old), `${module.name}: unexpected drift`);
  patches[module.name] = changes;
  references[module.name] = reference;
}

// The live sync.js (checked on the server 2026-11-27) is the theme-schemes build without `export` on registerDevice:
// an earlier package compiled it from source that predates the export. The checks call it, so the patch adds it back.
const EXPORT_REGISTER_DEVICE = { before: '\nasync function registerDevice(', after: '\nexport async function registerDevice(' };
patches['sync.js'] = [EXPORT_REGISTER_DEVICE, ...patches['sync.js']];
assert.equal(patchModule(references['sync.js'], patches['sync.js']), references['sync.js'], 'export hunk is a no-op on the reference');
const withoutExport = source => {
  const stripped = source.replace(/\nexport async function registerDevice\(/, '\nasync function registerDevice(');
  assert.notEqual(stripped, source);
  return stripped;
};
// The live sync.js is the theme-schemes patch applied to the book-mark build; that package also accepted the
// CRLF and the line-wrapped variants. Each, with or without the export, must take this patch and match the
// reference beyond whitespace.
const bookMark = runtimeOf('qingye-book-mark-sync-20261114', 'sync.js');
const themeVariants = [bookMark, bookMark.replace(/\n/g, '\r\n'),
  bookMark.replace('? maxBookSourceBytes : MAX_PAYLOAD_BYTES;', '? maxBookSourceBytes :\n            MAX_PAYLOAD_BYTES;')]
  .map(source => themeSchemesPatch(source));
const liveVariants = [...themeVariants, ...themeVariants.map(source => withoutExport(normalize(source)))];
const liveOnServer = withoutExport(runtimeOf('qingye-theme-schemes-limit-20261117', 'sync.js'));
assert.equal(createHash('sha256').update(liveOnServer).digest('hex'),
  'cbb0abc06e5ab94d3d9da70a5f09a3b50516046e3ba743ed37d737389d67c77a', 'the file seen on the server');
liveVariants.push(liveOnServer);
liveVariants.forEach((source, index) => {
  const patched = patchModule(source, patches['sync.js']);
  assert.equal(squash(patched), squash(references['sync.js']), `live sync.js variant ${index}: differs beyond whitespace`);
  assert(patched.includes('\nexport async function registerDevice('), `live sync.js variant ${index}: registerDevice export`);
  assert.equal(patchModule(patched, patches['sync.js']), patched, `live sync.js variant ${index}: not idempotent`);
});

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations', 'test-migrations']) mkdirSync(resolve(output, dir), { recursive: true });
for (const module of modules) {
  writeFileSync(resolve(output, 'runtime', module.name), references[module.name]);
  copyFileSync(resolve(server, module.source), resolve(output, 'src', module.source.replace(/^src\//, '')));
}
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
// The server's own migrations folder is stale; the disposable test database uses the complete set.
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'sync-history-pg-check.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/sync-history-pg-check.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
writeFileSync(resolve(output, 'patch.json'), JSON.stringify(patches, null, 2) + '\n');
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release,
  baselines: Object.fromEntries(modules.map(m => [m.name, { commit: m.baseline, installedFrom: m.installed }])),
  sourceCommit: commit, uncommittedChanges: dirty, patched: modules.map(m => m.name), added: [], migrations }, null, 2) + '\n');

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
        info = zipfile.ZipInfo(name, (2026, 11, 26, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(os.path.join(root, name), 'rb') as f:
            z.writestr(info, f.read())
`, output, zipPath, ...files(output)]);
const zipSum = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
writeFileSync(`${zipPath}.sha256`, `${zipSum} *${release}.zip\n`);
console.log('PASS: build parity, idempotence, baseline rejection, installed runtimes and live sync.js variants patch cleanly');
console.log('Hunks:', Object.entries(patches).map(([name, changes]) => `${name} ${changes.length}`).join(', '));
console.log(zipPath, zipSum, dirty ? '(built from uncommitted changes)' : '');
