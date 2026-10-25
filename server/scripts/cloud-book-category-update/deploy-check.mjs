// Exercise the real shell flow against temporary files and fake service/health commands.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const stage = resolve(here, '../../release/qingye-cloud-book-category-20261025');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const shellPath = path => path.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => `/${drive.toLowerCase()}`);
const quote = text => `'${text.replaceAll("'", "'\\''")}'`;
const patches = JSON.parse(readFileSync(resolve(stage, 'patch.json'), 'utf8'));
const names = Object.keys(patches);
const current = Object.fromEntries(names.map(name => [name, readFileSync(resolve(stage, 'runtime', name), 'utf8')]));
const previous = Object.fromEntries(names.map(name => {
  let source = current[name];
  for (const { before, after } of patches[name].toReversed()) source = source.replace(after, () => before);
  return [name, source];
}));

function fixture() {
  const root = mkdtempSync(resolve(tmpdir(), 'cloud-category-deploy-'));
  const live = resolve(root, 'live'); mkdirSync(live);
  for (const name of names) writeFileSync(resolve(live, name), previous[name]);
  writeFileSync(resolve(root, 'state'), 'active');
  writeFileSync(resolve(root, 'actions'), '');
  const prelude = `
testroot=${quote(shellPath(root))}
id() { echo 0; }
flock() { :; }
sleep() { :; }
systemctl() {
  case "$1" in
    is-active) [ "$(cat "$testroot/state")" = active ] ;;
    stop) echo stop >> "$testroot/actions"; echo inactive > "$testroot/state" ;;
    start)
      echo start >> "$testroot/actions"
      if [ -f "$testroot/fail-start" ]; then rm "$testroot/fail-start"; return 1; fi
      echo active > "$testroot/state" ;;
    show)
      case "$4" in
        WorkingDirectory) echo "$testroot/live" ;;
        MainPID) if [ "$(cat "$testroot/state")" = active ]; then echo 123; else echo 0; fi ;;
        NRestarts) echo 0 ;;
        *) echo 'ActiveState=active' ;;
      esac ;;
    *) return 1 ;;
  esac
}
curl() { for curl_arg in "$@"; do :; done; if [[ "$curl_arg" == */metadata ]]; then printf 401; else printf '{"ok":true}'; fi; }
`;
  function run(script, args = []) {
    const source = readFileSync(resolve(stage, script), 'utf8')
      .replace('live=/www/wwwroot/qingye.icynol.com', `live=${quote(shellPath(live))}`)
      .replace('node=/www/server/nodejs/v22.23.1/bin/node', `node=${quote(shellPath(process.execPath))}`)
      .replaceAll('/root/', `${shellPath(root)}/`);
    return spawnSync(bash, ['-c', prelude + source, shellPath(resolve(stage, script)), ...args], { encoding: 'utf8' });
  }
  function verify(files) { for (const name of names) assert.equal(readFileSync(resolve(live, name), 'utf8'), files[name]); }
  return { root, live, run, verify, actions: () => readFileSync(resolve(root, 'actions'), 'utf8') };
}
const f = fixture();
let result = f.run('update.sh', ['--check']);
assert.equal(result.status, 0, result.stdout + result.stderr); f.verify(previous); assert.equal(f.actions(), '');
result = f.run('update.sh');
assert.equal(result.status, 0, result.stdout + result.stderr); f.verify(current);
const backup = result.stdout.match(/Backup: (.+)/)[1].trim();
assert.equal(f.actions(), 'stop\nstart\n');
result = f.run('update.sh');
assert.equal(result.status, 0, result.stdout + result.stderr);
assert.equal(f.actions(), 'stop\nstart\n');
result = f.run('rollback.sh', [backup]);
assert.equal(result.status, 0, result.stdout + result.stderr); f.verify(previous);
const failed = fixture();
writeFileSync(resolve(failed.root, 'fail-start'), '1');
result = failed.run('update.sh');
assert.notEqual(result.status, 0); failed.verify(previous);
assert.equal(readFileSync(resolve(failed.root, 'state'), 'utf8').trim(), 'active');
assert.equal(failed.actions(), 'stop\nstart\nstop\nstart\n');
const incompatible = fixture();
writeFileSync(resolve(incompatible.live, names[0]), 'incompatible code');
result = incompatible.run('update.sh');
assert.notEqual(result.status, 0); assert.equal(incompatible.actions(), '');
const newer = fixture();
result = newer.run('update.sh'); assert.equal(result.status, 0, result.stdout + result.stderr);
const newerBackup = result.stdout.match(/Backup: (.+)/)[1].trim();
writeFileSync(resolve(newer.live, names[0]), current[names[0]] + '\n// later update\n');
result = newer.run('rollback.sh', [newerBackup]);
assert.notEqual(result.status, 0); assert.equal(newer.actions(), 'stop\nstart\n');
console.log('PASS: preflight, install, idempotence, rollback, failed-start recovery, incompatible baseline and newer-version protection');
