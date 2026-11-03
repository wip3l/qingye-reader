import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';
const read=path=>fs.readFileSync(new URL('../entry/src/main/ets/'+path,import.meta.url),'utf8');
const clean=source=>source.replace(/^import [\s\S]*?;\r?\n/gm,'').replace(/^export \{.*;\r?\n/gm,'').replaceAll('export ','');
const files=new Map(),heard=[],requests=[];
let hold=false,held,fail=false;
const context=vm.createContext({
  AppStorage:{get:()=>'/cache'},
  ReaderTtsFloatingSession:{stop:async()=>{}},
  MimoStore:{onCredentialsChanged:[],key:async()=>'fake-key',load:()=>({namespace:'test'}),hash:text=>createHash('sha256').update(text).digest('hex')},
  MimoClient:class{stop(){} async synthesize(key,text,voice,style){requests.push({text,voice,style});if(fail)throw Error('offline');if(hold){hold=false;await new Promise(resolve=>held=resolve)}return Uint8Array.from([1,0,2,0]).buffer;}},
  TtsPcmAudioPlayer:class{stop(){}release(){}async play(pcm,rate){heard.push({pcm:[...new Uint8Array(pcm)],rate})}},
  fs:{accessSync:path=>files.has(path),mkdirSync(){},listFileSync:dir=>[...files.keys()].filter(p=>p.startsWith(dir+'/')).map(p=>p.slice(dir.length+1)),
    statSync:path=>{if(!files.has(path))throw Error('missing');return{size:files.get(path).byteLength}},
    openSync:path=>({fd:path}),closeSync(){},writeSync:(path,data)=>files.set(path,data.slice(0)),
    readSync:(path,data)=>{new Uint8Array(data).set(new Uint8Array(files.get(path)));return data.byteLength},unlinkSync:path=>files.delete(path),
    OpenMode:{READ_ONLY:1,CREATE:2,WRITE_ONLY:4,TRUNC:8}}
});
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/MimoPolicy.ts'))),context);
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/MimoVoicePolicy.ts'))),context);
vm.runInContext(stripTypeScriptTypes(clean(read('utils/mimo/MimoPreviewSession.ets'))),context);
const {MimoPreviewSession:Session,MimoVoicePolicy:policy,MimoStore:store}=vm.runInContext('({MimoPreviewSession,MimoVoicePolicy,MimoStore})',context);
const p=policy.preset('test','自定义','冰糖','轻快好奇','child'),session=new Session();
await assert.rejects(session.play(p,''),/1～300/);
await assert.rejects(session.play(p,'字'.repeat(301)),/1～300/);
await session.play(p,'我们回家吧。');assert.equal(requests.length,1);assert.match(requests[0].style,/轻快好奇/);assert.equal(heard.length,1);
await session.play(p,'我们回家吧。');assert.equal(requests.length,1,'identical auditions reuse cache');assert.equal(heard.length,2);
await session.play(p,'我们回家吧。',true);assert.equal(requests.length,2);assert.ok(!requests[1].style.includes('轻快好奇'));assert.equal(requests[1].text,requests[0].text);
await session.play(p,'我们回家吧。');assert.equal(requests.length,2,'A/B comparisons retain both cached clips');
hold=true;const old=session.play(p,'旧试听。');while(!held)await new Promise(setImmediate);session.stop();
await session.play(p,'新试听。');const played=heard.length;held();await old;assert.equal(heard.length,played,'late canceled request never plays');
hold=true;held=null;const credentialChanged=session.play(p,'密钥变更时。');while(!held)await new Promise(setImmediate);
store.onCredentialsChanged.forEach(cancel=>cancel());held();await credentialChanged;assert.equal(heard.length,played,'credential invalidation stops the audition');
fail=true;await assert.rejects(session.play(p,'网络故障。'),/offline/);fail=false;await session.play(p,'故障后重试。');
assert.equal(store.onCredentialsChanged.length,0,'all completion paths remove credential listeners');
assert.ok(heard.every(p=>p.rate===24000));session.release();
console.log('MiMo audition checks passed: text bounds, real synthesis orchestration, original comparison, cache reuse, stale-request cancellation, credential invalidation and network recovery.');
