import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';

const queueSource = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudDownloadQueue.ets', import.meta.url), 'utf8');
const shelfSource = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const methods = ['cloudBookStatus', 'openCloudPlaceholder'].map(name => {
  const match = shelfSource.match(new RegExp(`^  (?:async )?${name}\\([\\s\\S]*?^  }`, 'm'));
  assert.ok(match, name);
  return match[0];
}).join(',\n');
const book = id => ({ bookUrl: `cloudbook://${id}`, name: id });
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}
function fixture() {
  const state = { user: 'user', route: { index: 1, path: 'pages/Index' }, calls: [], opened: [], notices: [], gates: new Map() };
  const storage = new Map();
  const pages = [];
  const sandbox = vm.createContext({
    Error, getContext: () => ({}),
    AccountSessionStore: { account: () => ({ userId: state.user }) },
    AppStorage: { setOrCreate: (key, value) => {
      storage.set(key, value);
      for (const page of pages) page[key] = value;
    } },
    HdsFeedback: { showToast: text => state.notices.push(text) },
    router: { getState: () => ({ ...state.route }) },
    CloudAutoSync: { ensureBookDownloaded: async (_context, selected, progress, wait) => {
      state.calls.push(selected.bookUrl);
      progress(1, 2);
      state.wait = wait;
      if (state.gates.has(selected.bookUrl)) await state.gates.get(selected.bookUrl).promise;
      return selected;
    } }
  });
  vm.runInContext(stripTypeScriptTypes(queueSource.replace(/^import .*;\r?\n/gm, '').replace('export class', 'class') +
    '\nglobalThis.queue = CloudDownloadQueue;', { mode: 'strip' }), sandbox);
  const createPage = () => {
    const page = vm.runInContext(stripTypeScriptTypes(`({${methods}})`, { mode: 'strip' }), sandbox);
    Object.assign(page, { cloudDownloadQueueRaw: storage.get('cloudDownloadQueueRaw') || '[]',
      cloudDownloadStatus: storage.get('cloudDownloadStatus') || '', cloudBookOpenRequest: 0, shelfComponentActive: true,
      loadBooks: async () => {}, openShelfBook: selected => state.opened.push(selected.bookUrl) });
    pages.push(page);
    return page;
  };
  return { queue: sandbox.queue, page: createPage(), createPage, state, storage };
}

test('shelf downloads FIFO, exposes positions/progress, deduplicates and never opens a batch', async () => {
  const { page, state } = fixture();
  const first = book('a'), second = book('b'), third = book('c');
  const gate = deferred();
  state.gates.set(first.bookUrl, gate);
  const a = page.openCloudPlaceholder(first, 0, 0);
  await flush();
  assert.equal(page.cloudBookStatus(first), '下载 50%');
  state.wait(3);
  assert.equal(page.cloudBookStatus(first), '3秒后继续');
  const b = page.openCloudPlaceholder(second, 0, 0);
  const c = page.openCloudPlaceholder(third, 0, 0);
  await page.openCloudPlaceholder(first, 0, 0);
  await page.openCloudPlaceholder(second, 0, 0);
  assert.equal(page.cloudBookStatus(second), '排队 1');
  assert.equal(page.cloudBookStatus(third), '排队 2');
  assert.deepEqual(state.calls, [first.bookUrl]);
  gate.resolve();
  await Promise.all([a, b, c]);
  assert.deepEqual(state.calls, [first.bookUrl, second.bookUrl, third.bookUrl]);
  assert.deepEqual(state.opened, []);
  assert.equal(page.cloudDownloadQueueRaw, '[]');
});

test('single book opens after download; navigation or a later reading request suppresses opening', async () => {
  for (const change of ['none', 'route', 'removed', 'opened-other']) {
    const { page, state } = fixture();
    const first = book('a'), gate = deferred();
    state.gates.set(first.bookUrl, gate);
    const running = page.openCloudPlaceholder(first, 0, 0);
    await flush();
    if (change === 'route') state.route = { index: 2, path: 'pages/ReadBook' };
    if (change === 'removed') page.shelfComponentActive = false;
    if (change === 'opened-other') page.cloudBookOpenRequest++;
    gate.resolve();
    await running;
    assert.deepEqual(state.opened, change === 'none' ? [first.bookUrl] : []);
  }
});

test('failed book releases queue, later book finishes and failed book can be retried', async () => {
  const { page, state } = fixture();
  const first = book('a'), second = book('b'), gate = deferred();
  state.gates.set(first.bookUrl, gate);
  const a = page.openCloudPlaceholder(first, 0, 0);
  const b = page.openCloudPlaceholder(second, 0, 0);
  await flush();
  gate.reject(new Error('连接失败'));
  await Promise.all([a, b]);
  assert.deepEqual(state.calls, [first.bookUrl, second.bookUrl]);
  assert.ok(state.notices.includes('连接失败'));
  state.gates.delete(first.bookUrl);
  await page.openCloudPlaceholder(first, 0, 0);
  assert.equal(state.calls.length, 3);
});

test('shared queue survives page recreation and serializes fonts behind books', async () => {
  const { page, createPage, queue, state } = fixture();
  const first = book('a'), gate = deferred();
  state.gates.set(first.bookUrl, gate);
  const a = page.openCloudPlaceholder(first, 0, 0);
  await flush();
  page.shelfComponentActive = false;
  const replacement = createPage();
  await replacement.openCloudPlaceholder(first, 0, 0);
  let imported = false;
  const font = queue.enqueue('font:b', async () => { imported = true; return '/font.ttf'; });
  assert.equal(queue.position(replacement.cloudDownloadQueueRaw, 'font:b'), 1);
  assert.equal(imported, false);
  gate.resolve();
  await Promise.all([a, font]);
  assert.equal(imported, true);
  assert.equal(state.calls.length, 1);
  assert.equal(replacement.cloudDownloadQueueRaw, '[]');
});

test('account switch prevents pending items from starting with a different account', async () => {
  const { queue, state, storage } = fixture();
  const gate = deferred();
  const a = queue.enqueue('book:a', async () => gate.promise);
  let started = false;
  const b = queue.enqueue('font:b', async () => { started = true; });
  const rejected = assert.rejects(b, /账号已改变/);
  await flush();
  state.user = 'other';
  gate.resolve();
  await Promise.all([a, rejected]);
  assert.equal(started, false);
  assert.equal(storage.get('cloudDownloadQueueRaw'), '[]');
  await queue.enqueue('font:c', async () => { started = true; });
  assert.equal(started, true);
});
