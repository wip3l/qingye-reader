import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import ts from 'typescript';
import { patchModule } from './patch.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, '../..');
// Keep the pre-fix baseline stable after this update is committed.
const baseline = 'f3d44f28a7e5ca7fc2248858828f85291bec40ae';
const output = resolve(server, 'release/qingye-cloud-book-category-20261025');
mkdirSync(output, { recursive: true });
const normalize = text => text.replace(/\r\n/g, '\n');
const old = {}, current = {};
for (const name of ['cloudFileService', 'cloudFileRoutes']) {
  const source = execFileSync('git', ['show', `${baseline}:server/src/${name}.ts`], { cwd: server, encoding: 'utf8' });
  old[name] = normalize(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ES2022 } }).outputText);
  current[name] = normalize(readFileSync(resolve(server, `dist/${name}.js`), 'utf8'));
}
function slice(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, `Missing patch anchor: ${start}`);
  return source.slice(a, b);
}
const patches = { 'cloudFileService.js': [
  { before: slice(old.cloudFileService, 'const META_KEYS', '\n'), after: slice(current.cloudFileService, 'const META_KEYS', '\n') },
  { before: slice(old.cloudFileService, 'function normalizeMeta', '\nconst fail'), after: slice(current.cloudFileService, 'function normalizeMeta', '\nconst fail') },
  { before: '    async uploadTicket(userId, id, input) {',
    after: slice(current.cloudFileService, '    /** Backfill legacy metadata', '    async uploadTicket') + '    async uploadTicket(userId, id, input) {' }
], 'cloudFileRoutes.js': [
  { before: slice(old.cloudFileRoutes, "    app.get('/v1/cloud-files/:id',", "    app.post('/v1/cloud-files/:id/upload-ticket'"),
    after: slice(current.cloudFileRoutes, "    app.get('/v1/cloud-files/:id',", "    app.post('/v1/cloud-files/:id/upload-ticket'") }
] };
for (const name of ['cloudFileService', 'cloudFileRoutes']) {
  const result = patchModule(old[name], patches[`${name}.js`]);
  assert.equal(result, current[name], `${name}: patch must reproduce the tested build exactly`);
  assert.equal(patchModule(result, patches[`${name}.js`]), result, 'Patch must be idempotent');
  assert.equal(patchModule('// preserve unrelated changes\n' + old[name], patches[`${name}.js`]),
    '// preserve unrelated changes\n' + current[name]);
  assert.throws(() => patchModule('', patches[`${name}.js`]), /BASELINE_MISMATCH/);
}
for (const dir of ['runtime', 'src']) mkdirSync(resolve(output, dir), { recursive: true });
for (const name of ['cloudFileService', 'cloudFileRoutes']) {
  writeFileSync(resolve(output, `runtime/${name}.js`), current[name]);
  copyFileSync(resolve(server, `src/${name}.ts`), resolve(output, `src/${name}.ts`));
}
for (const name of ['update.sh', 'rollback.sh', 'patch.mjs', 'check.mjs', 'README.md']) {
  writeFileSync(resolve(output, name), normalize(readFileSync(resolve(here, name), 'utf8')));
}
writeFileSync(resolve(output, 'patch.json'), JSON.stringify(patches, null, 2) + '\n');
execFileSync(process.execPath, [resolve(output, 'check.mjs'), resolve(output, 'runtime')], { stdio: 'inherit' });
function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? files(resolve(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}
const sums = files(output).filter(name => name !== 'SHA256SUMS').sort().map(name =>
  `${createHash('sha256').update(readFileSync(resolve(output, name))).digest('hex')}  ${name}`).join('\n');
writeFileSync(resolve(output, 'SHA256SUMS'), sums + '\n');
console.log('PASS: exact build parity, idempotence, unrelated code preservation and incompatible baseline rejection');
console.log(output);
