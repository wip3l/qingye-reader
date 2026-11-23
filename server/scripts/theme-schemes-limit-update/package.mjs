// Builds release/qingye-theme-schemes-limit-20261117 (.zip source folder). Run from server/ after `npm test`.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, mkdtempSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { patchModule } from './patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
const release = 'qingye-theme-schemes-limit-20261117';
const output = resolve(server, 'release', release);
const git = (...args) => execFileSync('git', args, { cwd: server, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const normalize = text => text.replace(/\r\n/g, '\n');
// config.js insists on these at import; the check never connects to anything.
const testEnv = { DATABASE_URL: 'postgresql://test:test@127.0.0.1:5432/test',
  SESSION_SECRET: 'test-session-secret-that-is-long-enough', HUAWEI_CLIENT_ID: 'test-client',
  HUAWEI_CLIENT_SECRET: 'test-secret', HUAWEI_APP_ID: 'test-app', HUAWEI_IAP_KEY_ID: 'test-key',
  HUAWEI_IAP_ISSUER_ID: 'test-issuer', HUAWEI_IAP_PRIVATE_KEY_PATH: 'test-private-key.pem',
  HUAWEI_IAP_ROOT_CA_PATH: 'test-root-ca.pem', HUAWEI_IAP_ROOT_URL: 'https://example.com',
  HUAWEI_IAP_DELIVERABLE_STATUSES: '0,PAID' };

// The live sync.js descends from these installed builds; the newest one is the expected state.
const baselines = ['qingye-book-mark-sync-20261114', 'qingye-annotation-sync-20261110', 'qingye-sync-text-20261109']
  .map(name => normalize(readFileSync(resolve(server, `release/${name}/runtime/sync.js`), 'utf8')));
const variants = [...baselines,
  baselines[0].replace(/\n/g, '\r\n'),
  baselines[0].replace("? maxBookSourceBytes : MAX_PAYLOAD_BYTES;", "? maxBookSourceBytes :\n            MAX_PAYLOAD_BYTES;")];
const scratch = mkdtempSync(join(tmpdir(), 'theme-schemes-limit-'));
try {
  variants.forEach((source, index) => {
    const patched = patchModule(source);
    assert.notEqual(patched, source, `variant ${index}: nothing patched`);
    assert.equal(patchModule(patched), patched, `variant ${index}: patch must be idempotent`);
    // Run the candidate through check.mjs with the compiled runtime around it.
    const dir = resolve(scratch, String(index));
    mkdirSync(dir);
    for (const name of readdirSync(resolve(server, 'dist'))) {
      if (name.endsWith('.js') && !name.endsWith('.test.js')) {
        writeFileSync(resolve(dir, name), readFileSync(resolve(server, 'dist', name)));
      }
    }
    writeFileSync(resolve(dir, 'package.json'), readFileSync(resolve(server, 'package.json')));
    writeFileSync(resolve(dir, 'sync.js'), patched);
    execFileSync('cmd', ['/c', 'mklink', '/J', resolve(dir, 'node_modules'), resolve(server, 'node_modules')], { stdio: 'ignore' });
    try {
      execFileSync(process.execPath, [resolve(here, 'check.mjs')], { cwd: dir, stdio: 'inherit',
        env: { ...testEnv, ...process.env } });
    } finally {
      // Remove the junction itself first so cleanup never walks into the real node_modules.
      execFileSync('cmd', ['/c', 'rmdir', resolve(dir, 'node_modules')]);
    }
  });
} finally { rmSync(scratch, { recursive: true, force: true }); }
assert.throws(() => patchModule(''), /BASELINE_MISMATCH/);

rmSync(output, { recursive: true, force: true });
mkdirSync(resolve(output, 'runtime'), { recursive: true });
mkdirSync(resolve(output, 'src'), { recursive: true });
// Reference result on the newest build, for reading only; update.sh patches the live file itself.
writeFileSync(resolve(output, 'runtime/sync.js'), patchModule(baselines[0]));
writeFileSync(resolve(output, 'src/sync.ts'), normalize(readFileSync(resolve(server, 'src/sync.ts'), 'utf8')));
for (const name of ['update.sh', 'rollback.sh', 'common.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
const commit = git('rev-parse', '--short=8', 'HEAD').trim();
const dirty = git('status', '--porcelain', '--', '.').trim() !== '';
writeFileSync(resolve(output, 'RELEASE.json'), JSON.stringify({ release, baseline: 'qingye-book-mark-sync-20261114',
  sourceCommit: commit, uncommittedChanges: dirty, patched: ['sync.js'] }, null, 2) + '\n');

function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log(`PASS: ${variants.length} baseline variants patched, idempotent, verified by running them; empty input rejected`);
console.log(output);
