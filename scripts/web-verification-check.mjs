import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';
import { createRequire } from 'node:module';
import { loadNativeSourceModules } from '../harmony-book-source-engine/scripts/lib/load-native-source-modules.mjs';

function load(file, name, bindings = {}) {
  const context = vm.createContext({ console, setTimeout, clearTimeout, setInterval, clearInterval, ...bindings });
  vm.runInContext(stripTypeScriptTypes(readEtsModule(file).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  return vm.runInContext(name, context);
}
const Runtime = load('core/book/WebBookFetchRuntime.ts', 'WebBookFetchRuntime', {
  util: { TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } } }, CookieStore: { forSource: () => ({ setCookies() {} }) }
});
const request = (url, other = {}) => ({ url: 'https://fixture.invalid/' + url, method: 'GET', headers: {}, deadlineAt: Date.now() + 3000, ...other });
function controller() {
  return { loads: [], posts: [], stops: 0, loadUrl(url) { this.loads.push(url); }, postUrl(url) { this.posts.push(url); }, stop() { this.stops++; } };
}
{
  const runtime = new Runtime(), a = controller(), b = controller();
  runtime.attach(a); runtime.attach(b); runtime.detach(b);
  const p = runtime.fetch(request('restored'));
  assert.ok(a.loads.includes('https://fixture.invalid/restored'));
  runtime.finishActive({ url: 'https://fixture.invalid/restored', statusCode: 200, success: true, body: 'ok', headers: {} });
  await p; runtime.detach(a); assert.equal(runtime.isAttached(), false);
}
{
  const runtime = new Runtime(), a = controller(), b = controller(); runtime.attach(a);
  const p = runtime.fetch(request('post', { method: 'POST', body: 'side-effect' }));
  runtime.attach(b);
  assert.equal((await p).errorCode, 'WEB_HOST_CHANGED');
  assert.equal(a.posts.length, 1); assert.equal(b.posts.length, 0);
  runtime.detach(b); runtime.detach(a);
}
{
  const runtime = new Runtime(), a = controller(); runtime.attach(a);
  const active = runtime.fetch(request('active'));
  let cancelled = false;
  const queued = runtime.fetch(request('queued', { cancelCheck: () => cancelled }));
  cancelled = true;
  assert.equal((await queued).errorCode, 'CANCELLED');
  assert.ok(!a.loads.some(u => u.endsWith('/queued')));
  runtime.detach(a); await active;
}
{
  const runtime = new Runtime(), a = controller(); runtime.attach(a);
  let cancelled = false;
  const active = runtime.fetch(request('cancel', { cancelCheck: () => cancelled })); cancelled = true;
  assert.equal((await active).errorStage, 'cancel'); assert.ok(a.stops > 0); runtime.detach(a);
}
{
  const runtime = new Runtime(), a = controller(); runtime.attach(a);
  const p = runtime.fetch(request('deadline', { deadlineAt: Date.now() + 40 }));
  assert.equal((await p).errorCode, 'REQUEST_DEADLINE'); runtime.detach(a);
}

// Exercise actual CookieStore dispatch and copying without pretending the mock models ArkWeb.
const state = { sdkApiVersion: 26, reads: [], writes: [], ordinary: 'session=plain', partitioned: 'clearance=partition; duplicate=a; duplicate=b' };
const cookies = load('core/http/CookieStore.ts', 'CookieStore', {
  deviceInfo: state, SourceEngineHost: { cookies: () => null }, LogText: { url: x => x },
  SetCookieParser: { split: x => [x] }, util: {},
  webview: { WebCookieManager: {
    fetchCookieSync(...args) { state.reads.push(args); return args[2] ? state.ordinary + '; ' + state.partitioned : state.ordinary; },
    configCookieSync(url, value) { state.writes.push({ url, value }); }, saveCookieAsync() {}, saveCookieSync() {}
  } }
});
assert.equal(cookies.getRequestCookie('https://fixture.invalid/'), 'session=plain; clearance=partition; duplicate=a; duplicate=b');
state.reads.length = 0;
cookies.copyCookies('https://fixture.invalid/', 'https://mirror.invalid/');
assert.ok(state.reads.every(args => args.length === 1), 'copying must never read partitioned cookies');
assert.ok(state.writes.every(write => !write.value.includes('partition')));
state.sdkApiVersion = 20; state.reads.length = 0;
assert.equal(cookies.getRequestCookie('https://fixture.invalid/'), 'session=plain');
assert.ok(state.reads.every(args => args.length === 1), 'old API must not receive API 26 signature');

const storage = new Map();
const verification = load('core/http/VerificationSupport.ts', 'VerificationSupport', {
  AppStorage: { setOrCreate: (k,v) => storage.set(k,v), get: k => storage.get(k) }
});
const a = verification.createContext('https://fixture.invalid/a', 'source-a', 'UA-A');
const b = verification.createContext('https://fixture.invalid/a', 'source-b', 'UA-B');
assert.equal(verification.contextUserAgent(a, 'https://fixture.invalid/a'), 'UA-A');
assert.equal(verification.contextUserAgent(b, 'https://fixture.invalid/a'), 'UA-B');
assert.equal(verification.contextUserAgent(a, 'https://other.invalid/'), '');
assert.equal(verification.contextSource(a, 'https://fixture.invalid/a'), 'source-a');
const require = createRequire(import.meta.url);
const { source } = require('./web-verification-device-fixture.cjs');
const mods = await loadNativeSourceModules();
assert.equal(mods.NativeSourceSpec.fromObject(source).name, source.name);
console.log('web-verification-check: host restoration, non-replayed POST, cancellation, deadlines, cookie API dispatch/copy boundary, UA context and fixture schema passed');
