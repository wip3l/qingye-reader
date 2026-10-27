import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {readEtsModule} from './lib/ets-module-staging.mjs';
import {loadNativeSourceModules} from '../harmony-book-source-engine/scripts/lib/load-native-source-modules.mjs';
import deviceFixtures from './source-media-performance-device-fixture.cjs';

const mods=await loadNativeSourceModules();
try {
  const fixtureContext=vm.createContext({console,process:{argv:[]},require:name=>name==='http'?
    {createServer:()=>({listen(){}})}:{mkdirSync(){},appendFileSync(){}}});
  vm.runInContext(fs.readFileSync(new URL('./source-followup-device-fixture.cjs',import.meta.url),'utf8'),fixtureContext);
  assert.equal(mods.NativeSourceSpec.fromObject(vm.runInContext('source',fixtureContext)).name,'Codex网络验收临时源');
  const deviceSources=deviceFixtures.createSources();
  for(const source of deviceSources) assert.equal(mods.NativeSourceSpec.fromObject(source).name,source.name);
  for(const count of [600,1000,3000]) {
    const perfContext=vm.createContext({log(){},http:{get(url){
      assert.equal(new URL(url).searchParams.get('count'),String(count));
      return {ok:true,json:()=>Array.from({length:count},(_,i)=>({name:'Chapter '+i,url:'/chapter/'+i}))};
    }}});
    vm.runInContext(deviceSources[1].js,perfContext);
    const chapters=vm.runInContext(`toc({vars:{chapters:'${count}'}})`,perfContext);
    assert.equal(chapters.length,count);
    assert.equal(chapters[count-1].url,'/chapter/'+(count-1));
  }
  const {BookSourceDebugContext,BookSourceDebugNetworkTrace}=mods;
  const debug=new BookSourceDebugContext('https://example.com','test','search');
  debug.beginStep('search','test');
  const trace=new BookSourceDebugNetworkTrace();
  trace.requestId='http-1'; trace.responseChars=2;
  trace.url='https://example.com/list?token=private';
  trace.requestHeaders={'X-Media-Token':'private',Cookie:'id=private',Authorization:'Bearer private',Accept:'text/html'};
  trace.responseHeaders={'Set-Cookie':'id=private','Retry-After':'2',Location:'https://example.com/?token=private'};
  trace.headersAvailable=true;
  debug.addNetwork(trace);
  const report=JSON.stringify(debug.finish());
  assert.ok(!report.includes('private'),'header credentials and URL tokens must be redacted before export');
  assert.equal(debug.session.steps[0].requests[0].responseBytes,-1,'decoded characters are not wire bytes');
  assert.equal(trace.requestHeaders.Accept,'text/html');
  assert.equal(trace.responseHeaders['Retry-After'],'2');
  // CPU timing is delivered by the production QuickJS session adapter on success AND timeout.
  let outcome={success:true,value:'[]',cpuMs:37,timedOut:false};
  const context=vm.createContext({console,setInterval,clearInterval,setTimeout,clearTimeout,
    NativeJsPrelude:mods.NativeJsPrelude,NativeExpr:mods.NativeExpr,
    JSScriptSessionOptions:class {},
    JSScriptSession:class {
      constructor(){this.id=1;}
      async evaluate(code,name){return name.startsWith('script:')?outcome:{success:true,value:'null',cpuMs:1};}
      cancel(){} dispose(){} close(){}
    }});
  vm.runInContext(stripTypeScriptTypes(readEtsModule('core/nativesource/NativeScriptSessions.ts')
    .replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),context);
  const Sessions=vm.runInContext('NativeScriptSessions',context);
  const measured=[];
  const options={cpuMs:2000,wallMs:60000,cancelled:()=>false,timing:(cpu,wall)=>measured.push([cpu,wall])};
  await Sessions.forCode('function search(){}').run('search',{},()=>null,options);
  assert.equal(measured[0][0],37);
  outcome={success:false,value:'',cpuMs:2001,timedOut:true,error:'timeout'};
  await assert.rejects(Sessions.forCode('function search(){}').run('search',{},()=>null,options),/已用 2001 ms/);
  assert.equal(measured[1][0],2001);
  console.log('source-followup-diagnostics-check: bounded/redacted headers, size units, QuickJS success/timeout CPU diagnostics passed');
} finally {mods.cleanup();}
