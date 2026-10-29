import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';
import { loadNativeSourceModules, createTestHost } from '../harmony-book-source-engine/scripts/lib/load-native-source-modules.mjs';
import { createNodeScriptEngine } from '../harmony-book-source-engine/scripts/lib/node-script-engine.mjs';

function fixture({explicit=true, missingEnd=true, stale=false, html='<html><body>business</body></html>',
  ready='interactive', matched=true, maxAttempts=40, timeout=1800, changing=false, viaHttp=false}={}) {
  let now=1000, sequence=0, reads=0, evaluations=0, marker='', url='about:blank', result;
  const timers=new Map();
  const timer=(fn,ms,repeat=false)=>{const id=++sequence;timers.set(id,{fn,at:now+ms,repeat,ms});return id;};
  const context=vm.createContext({console, Date:class extends Date {static now(){return now;}},
    setTimeout:(fn,ms)=>timer(fn,ms), clearTimeout:id=>timers.delete(id),
    setInterval:(fn,ms)=>timer(fn,ms,true), clearInterval:id=>timers.delete(id),
    WebJsAwaitScript:{start:()=> 'fixture-selector',PENDING:'pending',BLOCKED:'blocked',FAILED_PREFIX:'failed:'}});
  vm.runInContext(stripTypeScriptTypes(readEtsModule('core/book/WebBookFetchRuntime.ts')
    .replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),context);
  const Runtime=vm.runInContext('WebBookFetchRuntime',context), runtime=new Runtime();
  Runtime.instance=runtime;
  const controller={stop(){},setCustomUserAgent(){},loadUrl(value){
    url=value;
    if(value==='about:blank')return;
    runtime.onPageBegin(controller,value);
    if(!stale)marker='';
    if(!missingEnd)runtime.onPageEnd(controller,value);
  },runJavaScript:async code=>{
    if(code.startsWith('globalThis.__legadoPreviousDocument=')){
      marker=JSON.parse(code.split('=')[1].split(';')[0]);return '';
    }
    if(code==='fixture-selector'){evaluations++;return matched?html:'';}
    reads++;
    return JSON.stringify({url,stale:String(marker!==''),title:'fixture',ready,
      html:html+(changing?String(reads):'')});
  }};
  runtime.attach(controller);
  const request={requestId:'probe',url:'https://fixture.invalid/page',method:'GET',headers:{},
    deadlineAt:now+timeout,webWaitFor:explicit?'body':undefined,webJs:explicit?'document.body.outerHTML':undefined,
    webJsAcceptPattern:explicit?'\\S':undefined,webJsMaxAttempts:maxAttempts};
  let work;
  if(viaHttp){
    context.WebBookFetchRuntime={get:()=>runtime};
    context.SourceEngineHost={withWeb:(_source,callback)=>callback()};
    vm.runInContext(stripTypeScriptTypes(readEtsModule('core/http/HttpClient.ts')
      .replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),context);
    const HttpClient=vm.runInContext('HttpClient',context);
    work=new HttpClient().execute({...request,useWebView:true});
  }else work=runtime.fetch(request);
  const promise=work.then(value=>{result=value;return value;});
  async function tick(untilResult=true){
    for(let count=0;count<500;count++){
      for(let j=0;j<10;j++)await Promise.resolve();
      if(result)return result;
      const next=[...timers].sort((a,b)=>a[1].at-b[1].at)[0];
      assert.ok(next,'work must have a bounded timer');
      const [id,t]=next;timers.delete(id);now=t.at;
      if(t.repeat)timers.set(id,{...t,at:now+t.ms});
      t.fn();
      if(!untilResult){for(let j=0;j<10;j++)await Promise.resolve();return result;}
    }
    throw new Error('fixture did not settle');
  }
  return {runtime,controller,promise,tick,stats:()=>({reads,evaluations}),timers};
}

{
  const f=fixture({changing:true});const r=await f.tick();
  assert.equal(r.success,true,'explicit selector works on an interactive, changing DOM without onPageEnd');
  assert.equal(f.stats().evaluations,1);assert.equal(r.bodyIsSnapshot,false);
}
{
  const f=fixture({explicit:false,missingEnd:false,ready:'complete',changing:true});const r=await f.tick();
  assert.equal(r.success,false,'plain DOM extraction still requires stability');
  assert.equal(r.bodyIsSnapshot,true);assert.equal(r.waitStage,'stability');
}
{
  const f=fixture({stale:true});const r=await f.tick();
  assert.equal(r.success,false);assert.equal(r.body,'');assert.equal(f.stats().evaluations,0,
    'same-URL previous document must not satisfy the new request');
}
{
  const f=fixture({matched:false,html:'<body>'+ 'x'.repeat(100000)+'</body>'});const r=await f.tick();
  assert.equal(r.errorCode,'REQUEST_DEADLINE');assert.equal(r.waitStage,'selector');
  assert.equal(r.body.length,65536);assert.equal(r.snapshotTruncated,true);assert.equal(r.bodyIsSnapshot,true);
  assert.equal(r.statusCodeAvailable,false);assert.equal(r.success,false);
}
{
  const f=fixture({matched:false,maxAttempts:2});const r=await f.tick();
  assert.equal(r.errorCode,'WEB_WAIT_UNMET');assert.equal(r.bodyIsSnapshot,true);assert.match(r.body,/business/);
}
{
  const f=fixture({matched:false});await f.tick(false);
  const r=f.runtime.timeoutRequest('probe');const completed=await f.promise;
  assert.equal(r.body,completed.body);assert.match(r.body,/business/);
  assert.equal(r.waitStage,'selector');assert.equal(r.errorCode,'REQUEST_DEADLINE');
  assert.equal(f.runtime.timeoutRequest('other'),null,'request IDs isolate outer deadline cancellation');
}
{
  const f=fixture({matched:false});await f.tick(false);
  f.runtime.onPageBegin(f.controller,'https://fixture.invalid/redirect');
  const r=f.runtime.timeoutRequest('probe');await f.promise;
  assert.equal(r.body,'','navigation discards snapshots belonging to the previous document');
}
{
  const f=fixture({matched:false,viaHttp:true});const r=await f.tick();
  assert.equal(r.errorCode,'REQUEST_DEADLINE');assert.equal(r.waitStage,'selector');
  assert.equal(r.bodyIsSnapshot,true);assert.match(r.body,/business/);
  assert.equal(r.finalUrl,'https://fixture.invalid/page');assert.match(r.requestId,/^http-/);
  assert.equal(r.hostWaitMs,0,'zero host wait must not grow to include render time');
}
console.log('PASS Web fetch: early selector, ordinary stability, same-URL stale document, bounded failure snapshot, selector failure, outer deadline, navigation reset');

const mods=await loadNativeSourceModules();
try {
  const {NativeExpr,NativeSourceSpec,NativeSourceRunner,NativeJsPrelude,JsonPathEvaluator}=mods;
  const source=NativeSourceSpec.fromObject({sourceFormat:'native',version:1,name:'resilience probe',url:'https://fixture.invalid',
    search:{script:'probe'},explore:{menus:[{title:'test',url:'/same'}],script:'probe'},actions:[{label:'probe',script:'action'}],
    js:`function result(){
      var r=http.get('/same',{webView:{waitFor:'body',timeout:20},timeout:45000});
      var caught={};try{browser.render('/same',{waitFor:'body'});}catch(e){
        caught={code:e.errorCode,stage:e.errorStage,wait:e.waitStage,ms:e.renderMs,body:e.response.body};
      }
      return JSON.stringify({code:r.errorCode,stage:r.errorStage,wait:r.waitStage,host:r.hostWaitMs,queue:r.queueMs,
        render:r.renderMs,snapshot:r.bodyIsSnapshot,truncated:r.snapshotTruncated,caught:caught});
    }function probe(){return [{name:result(),bookUrl:'/book'}];}function action(){return result();}`});
  for(const stage of ['search','explore','action']){
    const host=createTestHost(JsonPathEvaluator,async()=>null);
    host.fetch=async r=>({ok:false,status:0,body:'challenge snapshot',url:r.url,error:'deadline',errorCode:'REQUEST_DEADLINE',
      errorStage:'deadline',waitStage:'selector',hostWaitMs:1,queueMs:2,renderMs:3,bodyIsSnapshot:true,snapshotTruncated:true});
    host.scriptEngine=code=>createNodeScriptEngine(NativeJsPrelude,NativeExpr.scriptBuiltinNames(),code);
    const runner=new NativeSourceRunner(source,host,{});
    const value=stage==='search'?(await runner.search('x',1))[0].name:stage==='explore'?
      (await runner.explore((await runner.exploreMenus())[0].target,1))[0].name:await runner.runAction(0);
    assert.deepEqual(JSON.parse(value),{code:'REQUEST_DEADLINE',stage:'deadline',wait:'selector',host:1,queue:2,render:3,
      snapshot:true,truncated:true,caught:{code:'REQUEST_DEADLINE',stage:'deadline',wait:'selector',ms:3,body:'challenge snapshot'}});
  }
  console.log('PASS search/explore/action worker bridge: HTTP diagnostics and browser.render structured errors');
}finally{mods.cleanup();}
