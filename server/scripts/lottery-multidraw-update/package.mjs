// Builds release/qingye-lottery-multidraw-20261030. Run from server/ after `npm run build` and `npm test`.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const release = 'qingye-lottery-multidraw-20261030';
const output = resolve(server, 'release', release);
// What the first lottery package installed; the live modules must still be exactly these.
const installed = resolve(server, 'release/qingye-lottery-20261030/runtime');
const replaced = ['lotteryService', 'lotteryRoutes'];
const migrations = ['028_lottery_multi_draw.sql'];
const normalize = text => text.replace(/\r\n/g, '\n');
const sha = text => createHash('sha256').update(text).digest('hex');

rmSync(output, { recursive: true, force: true });
for (const dir of ['runtime', 'src', 'migrations', 'test-migrations', 'web']) mkdirSync(resolve(output, dir), { recursive: true });
const baseline = [];
for (const name of replaced) {
  const before = readFileSync(resolve(installed, `${name}.js`), 'utf8');
  const after = normalize(readFileSync(resolve(server, `dist/${name}.js`), 'utf8'));
  assert.notEqual(before, after, `${name}: nothing to update`);
  baseline.push(`baseline ${name}.js ${sha(before)}`, `target ${name}.js ${sha(after)}`);
  writeFileSync(resolve(output, `runtime/${name}.js`), after);
  copyFileSync(resolve(server, `src/${name}.ts`), resolve(output, `src/${name}.ts`));
}
writeFileSync(resolve(output, 'BASELINE'), baseline.join('\n') + '\n');
for (const file of migrations) {
  writeFileSync(resolve(output, 'migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
// The server's own migrations folder is stale; the disposable test database uses the complete set.
for (const file of readdirSync(resolve(server, 'migrations')).filter(name => /^\d{3}_.+\.sql$/.test(name))) {
  writeFileSync(resolve(output, 'test-migrations', file), normalize(readFileSync(resolve(server, 'migrations', file), 'utf8')));
}
writeFileSync(resolve(output, 'web/index.html'), normalize(readFileSync(resolve(server, 'lottery-web/index.html'), 'utf8')));
writeFileSync(resolve(output, 'lottery-pg-concurrency.mjs'),
  normalize(readFileSync(resolve(server, 'scripts/lottery-pg-concurrency.mjs'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = execFileSync('git', ['rev-parse', '--short=8', 'HEAD'], { cwd: server, encoding: 'utf8' }).trim();
const dirty = execFileSync('git', ['status', '--porcelain', '--', '.'], { cwd: server, encoding: 'utf8' }).trim() !== '';
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
