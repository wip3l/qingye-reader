// Builds release/qingye-sync-text-20261109(.zip source folder): exact compiled hunks that make sync payload
// text storable as jsonb. Run from server/ after `npm run build` and `npm test`.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync, mkdtempSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import ts from 'typescript';
import { patchModule } from './patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
// Last commit before this change. sync.ts is unchanged since the lottery update (797d4ff3) and
// readingStats.ts since the reading-stats update (9f19961d), the builds installed on the server.
const baseline = 'b1cd26b3';
const release = 'qingye-sync-text-20261109';
const output = resolve(server, 'release', release);
const patched = ['sync', 'readingStats'];
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
assert.equal(git('diff', '--stat', '797d4ff3', baseline, '--', 'src/sync.ts').trim(), '');
assert.equal(git('diff', '--stat', '9f19961d', baseline, '--', 'src/readingStats.ts').trim(), '');
const normalize = text => text.replace(/\r\n/g, '\n');
const compile = source => normalize(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText);

/** Unified-diff hunks of two texts, each widened until its before/after text is unique. */
function hunks(before, after, context) {
  const dir = mkdtempSync(join(tmpdir(), 'sync-text-diff-'));
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
  current[name] = compile(readFileSync(resolve(server, `src/${name}.ts`), 'utf8'));
  assert.equal(current[name], normalize(readFileSync(resolve(server, `dist/${name}.js`), 'utf8')),
    `${name}: dist is stale or differs from transpileModule; run npm run build`);
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

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src']) mkdirSync(resolve(output, dir), { recursive: true });
for (const name of patched) {
  writeFileSync(resolve(output, `runtime/${name}.js`), current[name]);
  copyFileSync(resolve(server, `src/${name}.ts`), resolve(output, `src/${name}.ts`));
}
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
writeFileSync(resolve(output, 'patch.json'), JSON.stringify(patches, null, 2) + '\n');
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, baseline, sourceCommit: commit,
  uncommittedChanges: dirty, patched: patched.map(n => n + '.js') }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log('PASS: exact build parity, idempotence, unrelated code preservation and incompatible baseline rejection');
console.log('Hunks:', Object.entries(patches).map(([n, c]) => `${n} ${c.length}`).join(', '));
console.log(output);
