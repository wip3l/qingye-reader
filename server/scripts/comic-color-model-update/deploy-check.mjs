// Run the real updater with a fake service and mocked OBS publication; no network or production writes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const server=fileURLToPath(new URL('../../',import.meta.url));
const stage=path.join(server,'release/qingye-comic-color-models');
const bash=process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash';
const shell=p=>p.replaceAll('\\','/').replace(/^([A-Za-z]):/,(_,d)=>`/${d.toLowerCase()}`);
const quote=s=>`'${s.replaceAll("'","'\\''")}'`;
const names=['index.js','comicColorModels.js','comicColorModelRoutes.js'];
// Minimal compatible baseline with an unrelated statement that must survive.
const baseline="import { createObsStore } from './cloudObjectStore.js';\nconst unrelated = 42;\nconst obs = config.cloudFiles;\n";
function fixture() {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'color-model-deploy-'));
  const live=path.join(root,'live');fs.mkdirSync(live);fs.mkdirSync(path.join(live,'node_modules'));
  fs.writeFileSync(path.join(live,'index.js'),baseline);fs.writeFileSync(path.join(root,'state'),'active');fs.writeFileSync(path.join(root,'actions'),'');
  const prelude=`
testroot=${quote(shell(root))}
id() { echo 0; }
flock() { :; }
sleep() { :; }
systemctl() {
  case "$1" in
    is-active) [ "$(cat "$testroot/state")" = active ] ;;
    stop) echo stop >> "$testroot/actions"; echo inactive > "$testroot/state" ;;
    start) echo start >> "$testroot/actions"; if [ -f "$testroot/fail-start" ]; then rm "$testroot/fail-start"; return 1; fi; echo active > "$testroot/state" ;;
    show) case "$4" in WorkingDirectory) echo "$testroot/live" ;; MainPID) if [ "$(cat "$testroot/state")" = active ]; then echo 123; else echo 0; fi ;; esac ;;
  esac
}
curl() { for arg in "$@"; do :; done; if [[ "$arg" == */download-ticket ]]; then printf 401; else printf '{"ok":true}'; fi; }
`;
  const source=fs.readFileSync(path.join(stage,'scripts/comic-color-model-update/update.sh'),'utf8')
    .replace('live=/www/wwwroot/qingye.icynol.com',`live=${quote(shell(live))}`)
    .replace('node=/www/server/nodejs/v22.23.1/bin/node',`node=${quote(shell(process.execPath))}`)
    .replaceAll('/root/',shell(root)+'/')
    // Keep file checks, patching, syntax checks, model validation and rollback real.
    .replace('test ! -e "$stage/node_modules" || test -L "$stage/node_modules"',':')
    .replace('if [ ! -e "$stage/node_modules" ]; then ln -s "$live/node_modules" "$stage/node_modules"; fi',':')
    .replace('"$node" "$stage/scripts/comic-color-model-update/with-obs-env.mjs" "$pid" "$stage/models" --upload',
      'if [ -f "$testroot/fail-upload" ]; then exit 1; fi; echo upload >> "$testroot/actions"');
  const run=args=>spawnSync(bash,['-c',prelude+source,shell(path.join(stage,'scripts/comic-color-model-update/update.sh')),...args],{encoding:'utf8'});
  return {root,live,run,actions:()=>fs.readFileSync(path.join(root,'actions'),'utf8')};
}
const f=fixture();let r=f.run(['--check']);assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(f.actions(),'');
r=f.run([]);assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(f.actions(),'upload\nstop\nstart\n');
assert.match(fs.readFileSync(path.join(f.live,'index.js'),'utf8'),/const unrelated = 42/);
r=f.run([]);assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(f.actions(),'upload\nstop\nstart\nupload\n');
const failed=fixture();fs.writeFileSync(path.join(failed.root,'fail-start'),'1');r=failed.run([]);assert.notEqual(r.status,0);
assert.equal(fs.readFileSync(path.join(failed.live,'index.js'),'utf8'),baseline);
for(const name of names.slice(1))assert.equal(fs.existsSync(path.join(failed.live,name)),false);
assert.equal(fs.readFileSync(path.join(failed.root,'state'),'utf8').trim(),'active');
const unavailable=fixture();fs.writeFileSync(path.join(unavailable.root,'fail-upload'),'1');r=unavailable.run([]);
assert.notEqual(r.status,0);assert.equal(unavailable.actions(),'');
const incompatible=fixture();fs.writeFileSync(path.join(incompatible.live,'index.js'),'unexpected');r=incompatible.run([]);
assert.notEqual(r.status,0);assert.equal(incompatible.actions(),'');
console.log('PASS: updater preflight, publish-before-switch, preserved baseline, idempotence, upload failure, failed-start recovery and incompatible baseline');
