import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

let client, timer, active=true, closed=0, output=[], ticketCalls=0;
const scope=vm.createContext({Promise,Error,Date,Math,JSON,ArrayBuffer,
  setInterval(fn){timer=fn;return 1;},clearInterval(){timer=null;},
  fs:{OpenMode:{CREATE:1,WRITE_ONLY:2,TRUNC:4},async open(){output=[];return {fd:1};},
    writeSync(_fd,chunk){const bytes=new Uint8Array(chunk);output.push(bytes[0]);return 1;},async close(){closed++;}},
  AccountSessionStore:{token:()=> 'account-token'},
  AccountCommerceApi:{async colorModelTicket(){ticketCalls++;return JSON.stringify({url:'https://obs.example/model',bytes:3});}},
  http:{RequestMethod:{GET:'GET'},createHttp(){client={events:{},destroyed:false,
    on(event,fn){this.events[event]=fn;},off(event){delete this.events[event];},destroy(){this.destroyed=true;},
    requestInStream(url,options){assert.equal(options.header,undefined);assert.equal(options.usingProxy,false);
      return new Promise((resolve,reject)=>{this.respond=resolve;this.fail=reject;});}};return client;}}
});
function load(path){const source=fs.readFileSync(new URL(path,import.meta.url),'utf8');vm.runInContext(
  stripTypeScriptTypes(source.replace(/^import [^;]*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),scope);}
load('../entry/src/main/ets/account/ComicColorModelDownload.ets');
const Download=vm.runInContext('ComicColorModelDownload',scope);
const start=()=>Download.download('alac.ms','/part',3,()=>active,()=>{});
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const chunk=()=>new Uint8Array([1,2,3]).buffer;
let done=false;
let pending=start().then(()=>done=true);await tick();
client.respond(200);await tick();assert.equal(done,false,'headers alone must not finish download');
client.events.dataReceive(chunk());client.events.dataEnd();await pending;
assert.deepEqual(output,[1,2,3]);assert.equal(closed,1);assert.equal(timer,null);
pending=start();await tick();client.events.dataReceive(chunk());client.events.dataEnd();client.respond(200);await pending;
pending=start();await tick();client.respond(403);await assert.rejects(pending,/下载失败/);
pending=start();await tick();client.events.dataReceive(new Uint8Array([1]).buffer);client.events.dataEnd();client.respond(200);
await assert.rejects(pending,/不完整/);
pending=start();await tick();client.events.dataReceive(new Uint8Array(4).buffer);await assert.rejects(pending,/大小异常/);
pending=start();await tick();active=false;timer();await assert.rejects(pending,/取消/);assert.equal(client.destroyed,true);
const before=ticketCalls;await assert.rejects(start(),/取消/);assert.equal(ticketCalls,before);
assert.equal(closed,6,'all opened downloads close their file');

let missing=100, downloads=0, consent=0, dialogs=0;
Object.assign(scope,{ComicColorModels:{missingBytes:()=>missing,async download(_context,_active,_status,onBytes){downloads++;onBytes(25,100);}},
  ComicColorizer:{memberAllowed:()=>true},ThemeRuntime:{subTextColor:()=>'',primaryTextColor:()=>''},AppStorage:{get:()=>false}});
load('../entry/src/main/ets/utils/ComicColorDownloadPrompt.ets');
const Prompt=vm.runInContext('ComicColorDownloadPrompt',scope);
const ui={getPromptAction:()=>({async showDialog(){dialogs++;return {index:consent};}})};
active=true;
assert.equal(await Prompt.ensure({},ui,()=>active,()=>{}),false);assert.equal(downloads,0);
consent=1;const byteUpdates=[];
assert.equal(await Prompt.ensure({},ui,()=>active,()=>{},(received,total)=>byteUpdates.push([received,total])),true);
assert.equal(downloads,1);assert.deepEqual(byteUpdates,[[25,100]],'prompt forwards byte progress');
missing=0;await Prompt.ensure({},ui,()=>active,()=>{});assert.equal(dialogs,2);assert.equal(downloads,1);
missing=100;active=false;assert.equal(await Prompt.ensure({},ui,()=>active,()=>{}),false);assert.equal(dialogs,2);
console.log('Model UI/transport: explicit consent, offline reuse, header/body ordering, short writes, HTTP/truncation/oversize rejection and cancellation passed.');
