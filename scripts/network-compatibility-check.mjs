import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

function fixture(api = 26) {
  const calls = [], replies = [], cookies = [], traces = [];
  const state = { api, attach: true, destroyed: 0 };
  const http = {
    HttpProtocol: { HTTP1_1: 1 }, HttpDataType: { ARRAY_BUFFER: 0 },
    RequestMethod: { GET: 'GET', HEAD: 'HEAD', POST: 'POST' },
    InterceptorType: { FINAL_RESPONSE: 'final', REDIRECTION: 'redirect' },
    HttpInterceptorChain: class {
      addChain(chain) { this.chain = chain; return true; }
      apply(client) { if (!state.attach) return false; client.chain = this.chain; return true; }
    },
    createHttp() {
      return {
        events: {}, on(name, fn) { this.events[name] = fn; }, off(name) { delete this.events[name]; },
        destroy() { state.destroyed++; this.abort?.(new Error('transport destroyed')); },
        async request(url, options) {
          calls.push({ url, at: Date.now(), ...options });
          const reply = replies.shift();
          assert.ok(reply, 'unexpected request');
          if (reply.hang || reply.delay) {
            await new Promise((resolve, reject) => {
              let timer;
              this.abort = error => { clearTimeout(timer); reject(error); };
              if (!reply.hang) timer = setTimeout(resolve, reply.delay);
            });
            this.abort = null;
          }
          if (reply.error) throw reply.error;
          const response = { responseCode: reply.status || 200, header: reply.headers || {},
            result: reply.emptyResult ? undefined : new TextEncoder().encode(reply.body || 'ok').buffer };
          const requestContext = { url: reply.url || url, header: options.header };
          for (const interceptor of this.chain || []) {
            if (interceptor.interceptorType === 'redirect') {
              if (![301,302,303,307,308].includes(response.responseCode)) continue;
              assert.equal(await interceptor.interceptorHandle(requestContext, response), false,
                'protected requests must stop SDK redirects before the next network request');
              state.stoppedRedirects=(state.stoppedRedirects || 0)+1;
              break;
            }
            assert.equal(await interceptor.interceptorHandle(requestContext, response), true);
          }
          state.lastInterceptedHeaders = requestContext.header;
          return response;
        },
        async requestInStream(url, options) {
          calls.push({ url, ...options, stream: true });
          const reply = replies.shift();
          assert.ok(reply);
          this.events.headersReceive?.(reply.headers || {});
          this.events.dataReceive?.(new TextEncoder().encode(reply.body || 'ok').buffer);
          return reply.status || 200;
        }
      };
    }
  };
  const context = vm.createContext({
    console, ArrayBuffer, Uint8Array, setTimeout, clearTimeout, setInterval, clearInterval, http, url:{URL},
    deviceInfo: { get sdkApiVersion() { return state.api; } },
    util: { TextDecoder: { create: encoding => ({ decodeWithStream: bytes => new TextDecoder(encoding).decode(bytes) }) } },
    CookieStore: { forSource: () => ({ getCookie: () => state.cookie || '', getRequestCookie: () => state.requestCookie ?? state.cookie ?? '', setCookies: (url, value) => cookies.push({ url, value }), saveAsync() {} }) },
    TlsTrustStore: { isTrustedUrl: () => false, isCertificateError: () => false },
    SourceEngineHost: { withWeb: async (_, fn) => { if (state.webGate) await state.webGate; return fn(); }, id: () => 0,
      nativeScripts: () => undefined, nativeParsing: () => undefined, isCancelled: () => false },
    WebBookFetchRuntime: { get: () => ({ timeoutRequest: () => null, waitUntilAttached: async () => true,
      fetch: async req => { state.webRequests = (state.webRequests || 0) + 1; state.webRequest = req;
        return { url: 'https://web.example/final', success: true, statusCode: 200, body: 'web', headers: {} }; } }) },
    BookSourceDebugNetworkTrace: class {},
    RequestSessionSupport: { emptyConfig: () => ({}), apply() {} },
    VerificationSupport: { shouldRequestBrowserVerification: () => false, sourceCookieHeader: () => '' },
    RateLimitAcquireResult: { Acquired: 0, Cancelled: 1, RateLimited: 2 },
    BookSourceRateLimiter: { acquire: async (_source, _cancel, maxWait) => {
      state.rateWait = maxWait;
      if (state.rateLimited) { await new Promise(resolve => setTimeout(resolve, maxWait)); return 2; }
      return 0;
    } }
  });
  for (const file of ['http/HttpHeaderValues.ts', 'http/HttpRetryPolicy.ts', 'http/HttpProtocolPolicy.ts', 'http/HttpFinalUrlObserver.ts', 'http/NetworkErrorText.ts',
    'http/HttpClient.ts', 'book/BookUrlResolver.ts', 'rule/AnalyzeUrl.ts', 'nativesource/NativeCommentPage.ts']) {
    vm.runInContext(stripTypeScriptTypes(readEtsModule('core/' + file)
      .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  }
  const service = readEtsModule('core/nativesource/NativeSourceService.ts');
  vm.runInContext(stripTypeScriptTypes(service.slice(service.indexOf('class NativeHost '),
    service.indexOf('export class NativeSourceService')), {mode:'strip'}), context);
  const classes = vm.runInContext('({HttpClient,HttpProtocolPolicy,NetworkErrorText,AnalyzeUrl,NativeHost,HttpRetryPolicy})', context);
  return { ...classes, calls, replies, cookies, traces, state };
}
const request = (url = 'https://source.example/chapter') => ({ url, method: 'GET', headers: {} });
const internal = { code: 2300999, message: 'Internal error' };

// Actual HttpClient text and binary transports share a preference only AFTER a successful retry.
for (const binary of [false, true]) {
  const f = fixture(); const client = new f.HttpClient();
  const execute = req => binary ? client.executeBinary(req) : client.execute(req);
  f.replies.push({ error: internal }, {});
  assert.equal((await execute(request())).success, true);
  assert.deepEqual(f.calls.map(c => c.usingProtocol), [undefined, 1]);
  f.replies.push({}); await execute(request());
  assert.equal(f.calls.at(-1).usingProtocol, 1);
  f.replies.push({}); await execute(request('https://other.example/chapter'));
  assert.equal(f.calls.at(-1).usingProtocol, undefined);
  f.replies.push({ error: internal }); await execute(request());
  assert.equal(f.HttpProtocolPolicy.prefersHttp1(request().url), false, 'failed remembered route is forgotten');
  f.replies.push({ error: internal }, { error: internal }); await execute(request());
  assert.equal(f.HttpProtocolPolicy.prefersHttp1(request().url), false);
  const before = f.calls.length;
  f.replies.push({ error: internal }); await execute({ ...request(), method: 'POST', body: 'write' });
  assert.equal(f.calls.length, before + 1, 'POST must not be replayed');
  f.HttpClient.forceHttp1 = true;
  f.replies.push({}); await execute(request());
  assert.equal(f.calls.at(-1).usingProtocol, 1);
  const cancelledAt = f.calls.length;
  await execute({ ...request(), cancelCheck: () => true });
  assert.equal(f.calls.length, cancelledAt);
}
{
  const { HttpProtocolPolicy: p } = fixture();
  p.rememberSuccess('https://EXAMPLE.org:443/a', 1000);
  assert.equal(p.prefersHttp1('https://example.org/b', 2000), true);
  assert.equal(p.prefersHttp1('https://example.org:444/b', 2000), false);
  assert.equal(p.prefersHttp1('https://example.org/b', 601000), false);
  for (let i = 0; i < 129; i++) p.rememberSuccess(`https://h${i}.example/`, 1000);
  assert.equal(p.prefersHttp1('https://h0.example/', 1001), false);
  assert.equal(p.prefersHttp1('https://h128.example/', 1001), true);
  assert.equal(p.mayRetry('http://example.org', 'GET', '2300016'), false);
  assert.equal(p.mayRetry('https://example.org', 'GET', '2300028'), false);
}
// SDK automatic redirect: real observed URL reaches parsers, cookies and diagnostics, even with a byte budget.
{
  const f = fixture(); const client = new f.HttpClient();
  const final = 'https://cdn.example/real/chapter';
  f.replies.push({ url: final, headers: { 'set-cookie': 'id=1' } });
  const response = await client.execute({ ...request(), maxResponseBytes: 1024,
    debugContext: { addNetwork: trace => f.traces.push(trace) } });
  assert.equal(response.url, final); assert.equal(response.finalUrl, final);
  assert.equal(f.calls[0].maxLimit, 1024);
  assert.equal(f.cookies[0].url, final); assert.equal(f.traces[0].finalUrl, final);
  f.replies.push({ body: 'too large' });
  assert.match((await client.execute({ ...request(), maxResponseBytes: 2 })).error, /response too large/);
  f.replies.push({ url: final });
  assert.equal((await client.executeBinary(request())).finalUrl, final);
  assert.equal((await client.execute({ ...request(), useWebView: true })).finalUrl, 'https://web.example/final');
}
for (const api of [20, 26]) {
  const f = fixture(api); if (api === 26) f.state.attach = false;
  f.replies.push({ body: 'ok' });
  const response = await new f.HttpClient().execute({ ...request(), maxResponseBytes: 5,
    debugContext: { addNetwork: trace => f.traces.push(trace) } });
  assert.equal(response.success, true); assert.equal(response.finalUrl || '', '');
  assert.equal(f.calls[0].stream, true); assert.equal(f.traces[0].finalUrl, '');
}
// Explicit redirects preserve the returned final URL and handle query-only / dot-segment locations.
{
  const f = fixture(); const client = new f.HttpClient();
  const analyzer = new f.AnalyzeUrl(null, client);
  analyzer.acquireTimedSlot = async () => 0;
  const calls = [];
  analyzer.client = { execute: async req => {
    calls.push(req);
    if (calls.length === 1) return { statusCode: 302, headers: { location: '?page=2' }, url: req.url };
    return { statusCode: 200, headers: {}, url: req.url, finalUrl: req.url, success: true };
  } };
  const final = await analyzer.fetchFollowingRedirects(request('https://a.example/chap/1?page=1'));
  assert.equal(final.finalUrl, 'https://a.example/chap/1?page=2');
  assert.equal(calls.length, 2);
  const resolver = analyzer.resolveRedirectUrl.bind(analyzer);
  assert.equal(resolver('?page=2', 'https://a.example/chap/1?page=1'), 'https://a.example/chap/1?page=2');
  assert.equal(resolver('../2', 'https://a.example/chap/1'), 'https://a.example/2');
  assert.equal(resolver('javascript:alert(1)', 'https://a.example/'), '', 'non-http redirect rejected');
}
{
  const { NetworkErrorText: n } = fixture();
  assert.match(n.describe('2300999 Internal error', request().url), /内部错误/);
  assert.doesNotMatch(n.describe('2300999 Internal error', request().url), /HTTP\/2/);
  assert.match(n.describe('2300016', request().url), /HTTP\/2/);
  assert.match(n.describe('2300056 connection reset', request().url), /重置/);
  assert.doesNotMatch(n.describe('2300052', request().url), /污染/);
}
// A caller's deadline aborts the actual socket and cannot be extended by protocol fallback or redirects.
for (const binary of [false, true]) {
  const f = fixture(); const client = new f.HttpClient();
  f.replies.push({ hang: true });
  const start = Date.now(); const req = { ...request(), deadlineAt:start + 100 };
  const response = await (binary ? client.executeBinary(req) : client.execute(req));
  assert.match(response.error, /2300028/); assert.ok(Date.now() - start < 1000);
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.ok(f.state.destroyed > 0, 'deadline destroys the SDK request, not only the awaiting promise');
  assert.equal(f.calls.length, 1, 'timeout is not retried with a longer budget');
  assert.ok(f.calls[0].readTimeout <= 100); assert.ok(f.calls[0].connectTimeout <= 100);
}
{
  const f = fixture(); const client = new f.HttpClient();
  f.replies.push({delay:30, error:internal}, {hang:true});
  assert.match((await client.execute({...request(), deadlineAt:Date.now()+150})).error, /2300028/);
  assert.equal(f.calls.length, 2); assert.ok(f.calls[1].readTimeout < f.calls[0].readTimeout);
  assert.equal(f.HttpProtocolPolicy.prefersHttp1(request().url), false);
}
{
  const f = fixture(); const client = new f.HttpClient();
  const analyzer = new f.AnalyzeUrl(null, client).setRequestTimeout(150);
  analyzer.acquireTimedSlot = async () => 0;
  analyzer.config.retry = 3;
  f.replies.push({delay:30, status:302, headers:{location:'/final'}}, {hang:true});
  const req = {...request(), deadlineAt:analyzer.requestDeadlineAt, readTimeout:150};
  assert.match((await analyzer.fetchPrepared(req)).error, /2300028/);
  assert.equal(f.calls.length, 2, 'explicit redirects and retries share the original budget');
  assert.ok(f.calls[1].readTimeout < f.calls[0].readTimeout);
}
{
  const f = fixture(); const client = new f.HttpClient(); let release;
  f.state.webGate = new Promise(resolve => { release = resolve; });
  assert.match((await client.execute({...request(), useWebView:true, deadlineAt:Date.now()+50})).error, /2300028/);
  release(); await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(f.state.webRequests || 0, 0, 'expired request must not navigate after obtaining the browser session');
  const deadline = Date.now()+500;
  await client.execute({...request(), useWebView:true, deadlineAt:deadline});
  assert.equal(f.state.webRequest.deadlineAt, deadline);
  assert.ok(f.state.webRequest.timeoutMs <= 500, 'browser timeout must not be stretched to client default');
}
// Production NativeHost -> AnalyzeUrl -> HttpClient -> SDK receives the script timeout (not just its JSON field).
{
  const f = fixture(); const client = new f.HttpClient();
  f.replies.push({});
  client.decodeBody = () => { const until = Date.now()+30; while(Date.now()<until) {} return 'late decoded body'; };
  const response = await client.execute({...request(), deadlineAt:Date.now()+10});
  assert.match(response.error, /2300028/, 'late decode completion must not beat the overdue timer via a microtask');
}
for (const rateLimited of [false, true]) {
  const f = fixture(); f.state.rateLimited = rateLimited;
  const host = new f.NativeHost({bookSourceUrl:'https://source.example', enabledCookieJar:false},
    new f.HttpClient(), () => false, 1024);
  if (!rateLimited) f.replies.push({hang:true});
  const response = await host.fetch({...request(), body:'', charset:'', retry:3,
    webView:false, webTimeout:15, webWaitFor:'', primary:false, timeoutMs:100});
  assert.match(response.error, /超时/);
  assert.equal(f.calls.length, rateLimited ? 0 : 1);
  assert.ok(f.state.rateWait <= 100 && f.state.rateWait > 0);
  if (!rateLimited) assert.ok(f.calls[0].readTimeout <= 100);
}
// Inline comments share one operation budget, including cold-context reconstruction.
{
  const f = fixture();
  const host = new f.NativeHost({bookSourceUrl:'https://source.example', enabledCookieJar:false}, new f.HttpClient(), () => false, 1024*1024);
  host.limitCommentPage(Date.now()+1000);
  for (let i=0;i<8;i++) {
    f.replies.push({body:'{}'});
    await host.fetch({...request(),body:'',charset:'',retry:0,primary:false});
  }
  await assert.rejects(host.fetch({...request(),body:'',charset:'',retry:0,primary:false}),/8 次/);
  assert.equal(f.calls.length,8);
  assert(f.calls.every(call => call.readTimeout <= 1000 && call.connectTimeout <= 1000));
}
{
  const f = fixture();
  const host = new f.NativeHost({bookSourceUrl:'https://source.example', enabledCookieJar:false}, new f.HttpClient(), () => false, 1024*1024);
  host.limitCommentPage(Date.now()+3000);
  for (let i=0;i<3;i++) f.replies.push({body:'中'.repeat(300000)});
  for (let i=0;i<2;i++) await host.fetch({...request(),body:'',charset:'',retry:0,primary:false});
  await assert.rejects(host.fetch({...request(),body:'',charset:'',retry:0,primary:false}),/2 MiB/);
}
// Native scripts receive final response headers, even for failed HTTP status codes.
{
  const f = fixture();
  const host = new f.NativeHost({bookSourceUrl:'https://source.example',enabledCookieJar:false},new f.HttpClient(),()=>false);
  f.replies.push({status:429, body:'限流', headers:{'Retry-After':'1','Content-Type':'text/plain',
    'Set-Cookie':['a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT','b=2']}});
  const r = await host.fetch({...request(),headers:{'X-Test-Header':'value'},retry:0});
  assert.equal(r.ok,false); assert.equal(r.headersAvailable,true);
  assert.equal(r.headers['retry-after'],'1');
  assert.equal(r.headers['set-cookie'],'a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT\nb=2');
  assert.equal(f.calls[0].header['X-Test-Header'],'value');
  assert.match(f.calls[0].header['User-Agent'],/Mozilla/);
  const web = await host.fetch({...request(),retry:0,webView:true});
  assert.equal(web.headersAvailable,false); assert.equal(Object.keys(web.headers).length,0);
}
// Managed retry owns replay, honors server delay, and never stacks protocol/browser fallback.
for (const status of [429,503,403]) {
  const f=fixture(), client=new f.HttpClient(), analyzer=new f.AnalyzeUrl(null,client);
  analyzer.setRetryPolicy({times:2,base:20,maxDelay:100});
  f.replies.push({status},{status:200});
  const r=await analyzer.fetch('https://source.example/list');
  assert.equal(f.calls.length,status===403?1:2);
  assert.equal(r.statusCode,status===403?403:200);
  if(status!==403) assert.ok(f.calls[1].at-f.calls[0].at>=15);
}
{
  const f=fixture(), analyzer=new f.AnalyzeUrl(null,new f.HttpClient());
  analyzer.setRetryPolicy({times:3,base:1,maxDelay:5});
  f.replies.push({status:503,headers:{'Retry-After':'999'}});
  assert.equal((await analyzer.fetch('https://source.example/list')).statusCode,503);
  assert.equal(f.calls.length,1,'do not shorten Retry-After to the cap');
  f.replies.push({error:internal});
  assert.equal((await analyzer.fetch('https://source.example/list')).statusCode,0);
  assert.equal(f.calls.length,2,'managed policy disables implicit HTTP1/WebView fallback');
  assert.equal(f.state.webRequests||0,0);
  f.replies.push({status:503});
  await analyzer.fetch('https://source.example/update,{"method":"POST","body":"x"}');
  assert.equal(f.calls.length,3,'non-idempotent requests are never replayed by object policy');
}
{
  const f=fixture(), analyzer=new f.AnalyzeUrl(null,new f.HttpClient());
  let cancelled=false;
  analyzer.setCancelCheck(()=>cancelled).setRetryPolicy({times:3,base:100,maxDelay:100});
  f.replies.push({status:503});
  const pending=analyzer.fetch('https://source.example/list');
  setTimeout(()=>cancelled=true,10);
  assert.match((await pending).error,/取消/); assert.equal(f.calls.length,1);
  cancelled=false; analyzer.setRequestTimeout(20);
  f.replies.push({status:503});
  assert.match((await analyzer.fetch('https://source.example/list')).error,/超时/);
  assert.equal(f.calls.length,2);
}
{
  const f=fixture(), analyzer=new f.AnalyzeUrl(null,new f.HttpClient());
  analyzer.setRetryPolicy({times:2,base:1,maxDelay:10});
  f.replies.push({status:503},{status:503},{status:503});
  assert.equal((await analyzer.fetch('https://source.example/list')).statusCode,503);
  assert.equal(f.calls.length,3);
  const policy=f.HttpRetryPolicy.parse({times:3,base:10,maxDelay:3000});
  const now=Date.parse('2026-10-26T00:00:00Z');
  assert.equal(f.HttpRetryPolicy.delay(policy,0,{'Retry-After':'Mon, 26 Oct 2026 00:00:02 GMT'},now),2000);
  assert.equal(f.HttpRetryPolicy.delay(policy,2,{'Retry-After':'invalid'},now),40);
  assert.throws(()=>f.HttpRetryPolicy.parse({times:1,onStatus:[200]}),/onStatus/);
  assert.throws(()=>f.HttpRetryPolicy.parse({times:1,base:0}),/base/);
}
// Model actual SDK redirect timing: no fictitious NETWORK_CONNECT callback on every hop.
{
  const f=fixture(); const client=new f.HttpClient();
  const req={...request(),headers:{'X-Media-Token':'secret',Authorization:'bearer',Accept:'image/*'},protectedHeaderNames:['X-Media-Token']};
  f.state.cookie='session=test';
  f.replies.push({status:302,headers:{Location:'/same'},emptyResult:true},
    {status:307,headers:{Location:'//other.example/image'},emptyResult:true},{});
  const result=await client.executeBinary(req);
  assert.equal(result.success,true);
  assert.equal(result.finalUrl,'https://other.example/image');
  assert.equal(f.state.stoppedRedirects,2);
  assert.deepEqual(f.calls.map(c=>c.header['X-Media-Token']),['secret','secret',undefined]);
  assert.equal(f.calls[2].header.Authorization,undefined);
  assert.equal(f.calls[2].header.Cookie,undefined,'cross-origin hop must not re-inject source cookies');
  assert.equal(f.calls[2].header.Accept,'image/*');
  assert.equal(req.headers['X-Media-Token'],'secret','caller headers remain reusable');
  const old=fixture(21);
  assert.match((await new old.HttpClient().executeBinary(req)).error,/API 22/);
  assert.equal(old.calls.length,0,'unsupported interception fails before transmitting custom credentials');
  const unavailable=fixture();unavailable.state.attach=false;
  assert.match((await new unavailable.HttpClient().executeBinary(req)).error,/API 22/);
  assert.equal(unavailable.calls.length,0);
}
// Origin comparisons normalize default ports; returning to the original origin never restores removed credentials.
{
  const f=fixture(), req={...request(),headers:{'X-Key':'secret'},protectedHeaderNames:['X-Key']};
  f.replies.push({status:302,headers:{Location:'https://SOURCE.example:443/same'}},
    {status:302,headers:{Location:'http://source.example/other'}},
    {status:302,headers:{Location:'https://source.example/back'}},{});
  assert.equal((await new f.HttpClient().executeBinary(req)).success,true);
  assert.deepEqual(f.calls.map(c=>c.header['X-Key']),['secret','secret',undefined,undefined]);
}
for (const location of ['https://source.example/chapter','file:///tmp/test','https://user:pass@other.example/image']) {
  const f=fixture();f.replies.push({status:302,headers:{Location:location}});
  const result=await new f.HttpClient().executeBinary({...request(),headers:{'X-Key':'secret'},protectedHeaderNames:['X-Key']});
  assert.equal(result.success,false);assert.ok(result.error);assert.equal(f.calls.length,1);
}
{
  const f=fixture();
  for(let i=0;i<9;i++)f.replies.push({status:302,headers:{Location:'/hop'+i}});
  const result=await new f.HttpClient().executeBinary({...request(),headers:{'X-Key':'secret'},protectedHeaderNames:['X-Key']});
  assert.match(result.error,/8 次/);assert.equal(f.calls.length,9);
}
{
  const f=fixture();f.replies.push({status:302,headers:{Location:'/next'},delay:25},{hang:true});
  const result=await new f.HttpClient().executeBinary({...request(),headers:{'X-Key':'secret'},protectedHeaderNames:['X-Key'],deadlineAt:Date.now()+70});
  assert.match(result.error,/超时/);assert.ok(f.calls.length<=2);
}
console.log('network-compatibility-check: transports, final headers, managed retry/backoff/cancellation/deadlines, protected media and legacy policies passed');

{
  const f=fixture(); const client=new f.HttpClient();
  f.state.requestCookie='session=new; cf_clearance=fixture; duplicate=a; duplicate=b';
  f.replies.push({});
  await client.execute({...request(),automaticCookieHeader:true,headers:{Cookie:'session=old; fallback=kept','user-agent':'custom-UA'}});
  assert.equal(f.calls.at(-1).header.Cookie,'session=new; cf_clearance=fixture; duplicate=a; duplicate=b; fallback=kept');
  assert.equal(f.calls.at(-1).header['User-Agent'],'custom-UA');
  assert.equal(f.calls.at(-1).header['user-agent'],undefined);
  f.replies.push({}); await client.execute({...request(),headers:{cookie:'explicit=only'}});
  assert.equal(f.calls.at(-1).header.cookie,'explicit=only'); assert.equal(f.calls.at(-1).header.Cookie,undefined);
  f.replies.push({}); await client.execute({...request(),useCookieJar:false});
  assert.equal(f.calls.at(-1).header.Cookie,undefined);
  const host=new f.NativeHost({bookSourceUrl:'https://source.example'},client,()=>false);
  assert.equal(host.cookieGet(request().url,'cf_clearance'),'fixture');
}
console.log('Partition-aware request cookie / explicit-header / UA casing checks passed.');
