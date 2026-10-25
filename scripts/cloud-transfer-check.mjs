import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudFileClient.ets', import.meta.url), 'utf8');
const compiled = stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
function fixture() {
  const calls = [], waits = [];
  const state = { user: 'user', clock: 0, request: async () => '{}', duringWait() {} };
  class ApiError extends Error {
    constructor(statusCode, retryAfterSeconds = 0) { super('request failed'); this.statusCode = statusCode; this.retryAfterSeconds = retryAfterSeconds; }
  }
  const context = vm.createContext({
    AccountApiError: ApiError,
    AccountSessionStore: { account: () => ({ userId: state.user }), isLoggedIn: () => !!state.user, token: () => 'token' },
    AccountCommerceApi: { cloudRequest: async (...args) => { calls.push(args); return state.request(...args); } },
    setTimeout: (fn, delay) => { waits.push(delay); state.clock += delay; state.duringWait(); fn(); }
  });
  vm.runInContext(compiled, context);
  return { client: vm.runInContext('CloudFileClient', context), context, calls, waits, state, ApiError };
}

test('downloads wait for an occupied transfer slot and serialize even after failures', async () => {
  const f = fixture();
  f.client.beginTransfer(); // An existing upload owns the slot.
  const first = assert.rejects(f.client.download({}, { id: 'a' }, () => {}), /云文件清单无效/);
  const second = assert.rejects(f.client.download({}, { id: 'b' }, () => {}), /云文件清单无效/);
  await Promise.resolve();
  assert.equal(f.calls.length, 0);
  f.client.endTransfer();
  await Promise.all([first, second]);
  assert.deepEqual(f.calls.map(call => call[0]), ['/a', '/b']);
  assert.equal(f.client.isTransferring(), false);
});

test('account switch while waiting for a transfer slot sends no request', async () => {
  const f = fixture();
  f.client.beginTransfer();
  const pending = assert.rejects(f.client.download({}, { id: 'a' }, () => {}), /账号已改变/);
  f.state.user = 'other';
  f.client.endTransfer();
  await pending;
  assert.equal(f.calls.length, 0);
  assert.equal(f.client.isTransferring(), false);
});

test('65 MiB upload crosses a 120-request window and resumes every chunk automatically', async () => {
  const f = fixture();
  let window = 0, count = 0;
  const committed = new Set();
  f.state.request = async path => {
    const nextWindow = Math.floor(f.state.clock / 60000);
    if (nextWindow !== window) { window = nextWindow; count = 0; }
    if (++count > 120) throw new f.ApiError(429, Math.ceil((60000 - f.state.clock % 60000) / 1000));
    if (path.endsWith('/confirm')) committed.add(path);
    return '{}';
  };
  const notices = [];
  for (let index = 0; index < 65; index++) {
    await f.client.transferRequest('/file/upload-ticket', 'POST', JSON.stringify({ index }), 'token', 'user', n => notices.push(n));
    await f.client.transferRequest(`/file/chunks/${index}/confirm`, 'POST', '{}', 'token', 'user', n => notices.push(n));
  }
  await f.client.transferRequest('/file/complete', 'POST', '{}', 'token', 'user');
  assert.equal(committed.size, 65);
  assert.equal(f.state.clock, 60000);
  assert.equal(notices[0], 60);
  assert.equal(notices.at(-1), 1);
  assert.equal(f.calls.length, 132); // 131 successful requests plus the one rate-limited attempt.
});

test('ambiguous download ticket retries preserve the charge identifier and wait before retrying', async () => {
  const f = fixture();
  const tickets = new Set();
  f.state.request = async (_path, _method, body) => {
    const requestId = JSON.parse(body).requestId;
    tickets.add(requestId);
    if (f.calls.length === 1) throw new f.ApiError(500);
    return '{"ok":true}';
  };
  await f.client.transferRequest('/file/chunks/0/download-ticket', 'POST', '{"requestId":"same-ticket"}', 'token', 'user');
  assert.equal(tickets.size, 1);
  assert.deepEqual(f.calls[0], f.calls[1]);
  assert.equal(f.state.clock, 1000);
});

test('pause and account switch interrupt rate-limit waiting before another request', async () => {
  for (const mode of ['pause', 'switch']) {
    const f = fixture();
    f.state.request = async () => { throw new f.ApiError(429, 60); };
    f.state.duringWait = () => { if (mode === 'pause') f.client.pause(); else f.state.user = 'other'; };
    await assert.rejects(f.client.transferRequest('/file/complete', 'POST', '{}', 'token', 'user'), /已暂停|账号已改变/);
    assert.equal(f.calls.length, 1);
    assert.equal(f.state.clock, 250);
  }
});

test('terminal errors do not retry; repeated transient errors have a bounded retry count', async () => {
  for (const status of [401, 403, 409, 500, 429]) {
    const f = fixture();
    f.state.request = async () => { throw new f.ApiError(status, 1); };
    await assert.rejects(f.client.transferRequest('/file/complete', 'POST', '{}', 'token', 'user'));
    assert.equal(f.calls.length, status >= 500 || status === 429 ? 4 : 1);
  }
  const f = fixture();
  await assert.rejects(f.client.stage({}, 'file.json', 'file.json', 'SOURCE'), /数据同步/);
  assert.equal(f.calls.length, 0);
});

test('completed upload retains staged bytes until shelf import succeeds; retry needs no retransmission', async () => {
  const f = fixture();
  const task = { fileId: '', requestId: 'stable', path: '/staged.epub', name: 'book.epub',
    kind: 'BOOK', bytes: 10, manifestHash: 'manifest', meta: null };
  let saved = JSON.stringify(task), hasFile = true, imports = 0;
  f.context.preferences = { getPreferences: async () => ({
    put: async (_key, value) => { saved = value; }, flush: async () => {}, delete: async () => { saved = ''; }
  }) };
  f.context.fs = { OpenMode: { READ_ONLY: 1 }, open: async () => ({ fd: 1 }), close: async () => {},
    unlink: async () => { hasFile = false; } };
  f.client.pending = async () => saved ? JSON.parse(saved) : null;
  f.client.read = async () => new Uint8Array(10);
  f.client.sha256 = () => 'chunk';
  f.state.request = async path => {
    if (path === '/prepare') return '{"id":"cloud-id","state":"READY"}';
    if (path === '/cloud-id') return '{"chunkBytes":1048576,"chunks":[{"index":0,"sha256":"chunk"}]}';
    assert.equal(path, '/cloud-id/complete');
    return '{}';
  };
  const register = async uploaded => {
    assert.equal(uploaded.fileId, 'cloud-id');
    assert.equal(uploaded.path, '/staged.epub');
    assert.equal(hasFile, true);
    assert.ok(saved);
    if (++imports === 1) throw new Error('import failed');
  };
  await assert.rejects(f.client.upload({}, () => {}, undefined, register), /import failed/);
  assert.equal(hasFile, true);
  assert.ok(saved);
  assert.equal(f.client.isTransferring(), false);
  assert.equal(await f.client.upload({}, () => {}, undefined, register), 'cloud-id');
  assert.equal(imports, 2);
  assert.equal(hasFile, false);
  assert.equal(saved, '');
  assert.deepEqual(f.calls.map(c => c[0]), ['/prepare', '/cloud-id', '/cloud-id/complete',
    '/prepare', '/cloud-id', '/cloud-id/complete']);
});
