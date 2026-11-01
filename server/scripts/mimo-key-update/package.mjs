// Builds release/qingye-mimo-shared-key-20261101(.zip). Run from server/ after `npm run build` and `npm test`.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const release = 'qingye-mimo-shared-key-20261101';
const output = resolve(server, 'release', release);
const replaced = ['membershipRoutes'];
const migrations = ['029_shared_provider_keys.sql'];
// membershipRoutes.ts did not change from the super theme update (e4cc75b9) until this one, so compiling
// the sources of a commit in between reproduces the live module. Built in an ignored folder with real tsc.
const baselineCommit = '722d1f67';
const normalize = text => text.replace(/\r\n/g, '\n');
const sha = text => createHash('sha256').update(text).digest('hex');
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
assert.equal(git('diff', '--stat', 'e4cc75b9', baselineCommit, '--', 'src/membershipRoutes.ts').trim(), '');

const baselineDir = resolve(server, 'release', '.mimo-key-baseline');
rmSync(baselineDir, { recursive: true, force: true });
for (const path of git('ls-tree', '-r', '--name-only', baselineCommit, '--', 'src').split('\n').filter(p => p.endsWith('.ts'))) {
  const target = resolve(baselineDir, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, git('show', `${baselineCommit}:server/${path}`));
}
writeFileSync(resolve(baselineDir, 'tsconfig.json'), JSON.stringify({ extends: '../../tsconfig.json',
  compilerOptions: { outDir: 'dist', rootDir: 'src' }, include: ['src/**/*.ts'] }));
execFileSync(process.execPath, [resolve(server, 'node_modules/typescript/bin/tsc'), '-p', resolve(baselineDir, 'tsconfig.json')],
  { cwd: server, stdio: 'inherit' });

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations', 'test-migrations']) mkdirSync(resolve(output, dir), { recursive: true });
const baseline = [];
for (const name of replaced) {
  const before = normalize(readFileSync(resolve(baselineDir, `dist/${name}.js`), 'utf8'));
  const after = normalize(readFileSync(resolve(server, `dist/${name}.js`), 'utf8'));
  assert.notEqual(before, after, `${name}: nothing to update`);
  assert.ok(after.includes("'/v1/membership/mimo-key'"), `${name}: dist is not the current build`);
  baseline.push(`baseline ${name}.js ${sha(before)}`, `target ${name}.js ${sha(after)}`);
  writeFileSync(resolve(output, `runtime/${name}.js`), after);
  copyFileSync(resolve(server, `src/${name}.ts`), resolve(output, `src/${name}.ts`));
}
rmSync(baselineDir, { recursive: true, force: true });
writeFileSync(resolve(output, 'BASELINE'), baseline.join('\n') + '\n');
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
// The server's own migrations folder is stale; the disposable test database uses the complete set.
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'mimo-key-pg-check.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/mimo-key-pg-check.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, sourceCommit: commit, uncommittedChanges: dirty,
  replaced: replaced.map(n => n + '.js'), migrations }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${sha(readFileSync(resolve(output, name)))}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log(readFileSync(resolve(output, 'BASELINE'), 'utf8').trim());
console.log(output);
