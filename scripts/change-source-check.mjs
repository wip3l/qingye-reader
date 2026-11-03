import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
async function drain() { for (let n = 0; n < 60; n++) await Promise.resolve(); }
class Book {
  constructor() { Object.assign(this, { name: '测试书', author: '作者', origin: 'A', bookUrl: '/a',
    type: 0, variable: '', durChapterIndex: 3, durChapterPos: 2, readConfig: null }); }
  putVariable() {}
}
class SearchBook {}
function book(origin, extra = {}) { return Object.assign(new Book(), { origin, bookUrl: '/' + origin.toLowerCase() }, extra); }
function harness(disk = new Map()) {
  const events = [], writes = [];
  let detailGate, tocGate, commitGate, searchGate, beforeWrite, beforeRead;
  let failCommit = false, searchCount = 0;
  const old = book('A');
  const db = {
    initWithContext: async () => {},
    getBook: async () => old,
    getBookSource: async origin => ({ enabled: origin !== 'disabled', bookSourceUrl: origin }),
    commitBookSourceSwitch: async (_url, next) => {
      events.push('commit-start');
      if (commitGate) await commitGate.promise;
      if (failCommit) throw new Error('commit failed');
      events.push('commit-done'); Object.assign(old, next);
    }
  };
  class WebBookService {
    constructor(cancelled) { this.cancelled = cancelled; }
    cancelPendingRequests() { events.push('cancel-work'); }
    async getBookInfo(_source, next) {
      events.push('detail'); if (detailGate) await detailGate.promise;
      return Object.assign(next, { name: '测试书完整版', author: '作者 著', bookUrl: next.bookUrl + '/detail' });
    }
    async getChapterList() {
      events.push('toc'); if (tocGate) await tocGate.promise;
      return [{ title: '第一章', url: '/chapter' }, { title: '第二章', url: '/chapter2' }];
    }
  }
  class SearchCoordinator {
    cancel() { events.push('cancel-search'); searchGate?.resolve([]); }
    async search(_name, callback) {
      searchCount++;
      const found = [book('B'), book('C')];
      callback({ deltaResults: found, finished: false, status: '搜索中' });
      if (searchGate) await searchGate.promise;
      callback({ results: found, finished: true, status: '完成' });
      return found;
    }
  }
  const context = vm.createContext({
    console: { info() {}, warn() {}, error() {} }, setTimeout, clearTimeout, Book, SearchBook,
    BookTypeSupport: { mediaCategoryOf: b => b?.type === 1 ? 'comic' : 'text' },
    preferences: { getPreferences: async () => ({
      get: async (key, fallback) => { if (beforeRead) await beforeRead.promise; return disk.get(key) ?? fallback; },
      put: async (key, value) => { if (beforeWrite) await beforeWrite.promise; disk.set(key, value); writes.push(value); },
      flush: async () => {}
    }) },
    AppDatabase: { getInstance: () => db }, WebBookService, SearchCoordinator,
    SourceEngineHost: { getError: () => '' },
    BookFieldSanitizer: { prefer: (a, b) => a || b }, CoverUrlNormalizer: { prefer: (a, b) => a || b },
    AppStorage: { setOrCreate() {} }, getContext: () => ({}),
    SearchExploreSettingsStore: { getSearchConcurrency: () => 6 },
    SearchBookShelfHelper: { isNavigationResult: () => false },
    HdsFeedback: { showToast: text => events.push(text) }
  });
  function load(path, name, component = false) {
    let source = readEtsModule(path).replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
    if (component) source = source.slice(0, source.indexOf('  build() {')) + '}';
    source = source.replace(/@Component\s*/g, '').replace(/@StorageLink\('[^']+'\)\s*/g, '')
      .replace(/@State\s*/g, '').replace('struct BookChangeSourceDialog', 'class BookChangeSourceDialog');
    vm.runInContext(stripTypeScriptTypes(source) + '\nglobalThis.' + name + ' = ' + name + ';', context);
    return context[name];
  }
  const Cache = load('utils/ChangeSourceResultCache.ets', 'ChangeSourceResultCache');
  const Operation = load('core/book/SourceSwitchOperation.ts', 'SourceSwitchOperation');
  const Task = load('core/book/BookSourceSwitchTask.ets', 'BookSourceSwitchTask');
  const Dialog = load('components/BookChangeSourceDialog.ets', 'BookChangeSourceDialog', true);
  return { Cache, Operation, Task, Dialog, events, writes, disk, old, get searchCount() { return searchCount; },
    holdDetail() { return detailGate = deferred(); }, holdToc() { return tocGate = deferred(); },
    holdCommit() { return commitGate = deferred(); }, holdSearch() { return searchGate = deferred(); },
    holdWrite() { return beforeWrite = deferred(); }, holdRead() { return beforeRead = deferred(); },
    failCommit() { failCommit = true; } };
}

// Partial results survive immediate A -> B selection, changed metadata/URL, disposal and restart.
{
  const h = harness(); h.holdSearch();
  const panel = new h.Dialog(); panel.targetBook = h.old;
  let switched;
  panel.onSwitched = next => { switched = next; };
  panel.onClosed = () => panel.aboutToDisappear();
  panel.aboutToAppear(); await drain();
  assert.equal(panel.results.length, 2);
  assert.equal(h.searchCount, 1);
  await panel.switchSource(panel.results[0]);
  assert(switched); assert.equal(switched.author, '作者 著');
  await h.Cache.flush({});
  const restarted = harness(h.disk);
  const next = new restarted.Dialog(); next.targetBook = switched;
  next.aboutToAppear(); await drain();
  assert.equal(restarted.searchCount, 0, 'reopening B must reuse history');
  assert.deepEqual(Array.from(next.results, b => b.origin).sort(), ['A', 'C']);
  next.requestClose(); await restarted.Cache.flush({});
}

// Different authors/media stay separate; empty/partial refresh retains old candidates, expired entries remain usable.
{
  const h = harness();
  const original = await h.Cache.load({}, book('A'));
  h.Cache.merge({}, original.key, [book('B')]);
  h.Cache.merge({}, original.key, []);
  const another = await h.Cache.load({}, book('X', { author: '另一个作者' }));
  const comic = await h.Cache.load({}, book('Y', { type: 1 }));
  assert.notEqual(original.key, another.key); assert.notEqual(original.key, comic.key);
  assert.equal(another.results.length, 1);
  await h.Cache.flush({});
  const saved = JSON.parse(h.disk.get('history_v3'));
  saved.forEach(e => e.updatedAt = 1); h.disk.set('history_v3', JSON.stringify(saved));
  const restart = harness(h.disk);
  const stale = await restart.Cache.load({}, book('A'));
  assert.equal(stale.results.length, 2); assert.equal(stale.updatedAt, 1);
  await restart.Cache.flush({});
}

// Serialized writes cannot overwrite a newer alias/result with a slow earlier snapshot.
{
  const h = harness(); const entry = await h.Cache.load({}, book('A'));
  const gate = h.holdWrite(); const first = h.Cache.flush({});
  h.Cache.merge({}, entry.key, [book('B')]);
  h.Cache.rememberSwitch({}, entry.key, book('B', { author: '作者 著' }));
  const second = h.Cache.flush({}); gate.resolve(); await Promise.all([first, second]);
  const restart = harness(h.disk);
  assert.equal((await restart.Cache.load({}, book('B', { author: '作者 著' }))).key, entry.key);
  await restart.Cache.flush({});
}

// Closing during hydration cannot flush an empty history over existing disk data.
{
  const h = harness(); const entry = await h.Cache.load({}, book('A'));
  h.Cache.merge({}, entry.key, [book('B')]); await h.Cache.flush({});
  const restart = harness(h.disk); const gate = restart.holdRead();
  const reading = restart.Cache.load({}, book('A')); await drain();
  await restart.Cache.flush({});
  assert.equal(restart.writes.length, 0, 'closing during hydration cannot erase disk history');
  gate.resolve(); assert.equal((await reading).results.length, 2);
  await restart.Cache.flush({});
}

// Save-progress rejection releases controls and permits closing; no network/commit begins.
{
  const h = harness(); const panel = new h.Dialog(); panel.targetBook = h.old;
  const entry = await h.Cache.load({}, h.old); panel.cacheKey = entry.key;
  panel.onBeforeSwitch = async () => { throw new Error('保存进度失败'); };
  let closed = false; panel.onClosed = () => { closed = true; };
  await panel.switchSource(book('B'));
  assert.equal(panel.switching, false); assert.match(panel.status, /保存进度失败/);
  panel.requestClose(); assert(closed); assert(!h.events.includes('detail'));
  await h.Cache.flush({});
}

// Closing by button OR system disposal cancels a blocked detail/TOC; late responses cannot commit.
for (const stage of ['holdDetail', 'holdToc']) for (const close of ['requestClose', 'aboutToDisappear']) {
  const h = harness(); const gate = h[stage]();
  const panel = new h.Dialog(); panel.targetBook = h.old;
  panel.cacheKey = (await h.Cache.load({}, h.old)).key;
  let delivered = false; panel.onSwitched = () => { delivered = true; };
  const running = panel.switchSource(book('B')); await drain();
  panel[close](); await running;
  gate.resolve(); await drain();
  assert(!delivered); assert(!h.events.includes('commit-start'));
  await h.Cache.flush({});
}

// During atomic commit the dialog can disappear; completion is still delivered exactly once.
{
  const h = harness(); const gate = h.holdCommit();
  const panel = new h.Dialog(); panel.targetBook = h.old;
  const original = book('A');
  panel.cacheKey = (await h.Cache.load({}, h.old)).key;
  let delivered = 0; panel.onSwitched = () => delivered++;
  const running = panel.switchSource(book('B')); await drain();
  assert(h.events.includes('commit-start'));
  panel.requestClose();
  const concurrent = new h.Task(false);
  await assert.rejects(concurrent.run({}, panel.cacheKey, h.old, book('C'), null, () => {}, () => {}), /仍在保存/);
  gate.resolve(); await running;
  assert.equal(delivered, 1); assert(h.events.includes('commit-done'));
  await assert.rejects(new h.Task(false).run({}, panel.cacheKey, original, book('C'), null,
    () => {}, () => {}, 0), /书籍已切换/, 'a panel opened during commit cannot later switch a stale target');
  await h.Cache.flush({});
}

// An aborted database transaction does not publish a new book, even when the panel was closed.
{
  const h = harness(); const gate = h.holdCommit(); h.failCommit();
  const panel = new h.Dialog(); panel.targetBook = h.old;
  panel.cacheKey = (await h.Cache.load({}, h.old)).key;
  panel.onSwitched = () => assert.fail('failed commit published');
  const running = panel.switchSource(book('B')); await drain(); panel.requestClose(); gate.resolve(); await running;
  assert.equal(h.old.origin, 'A'); assert(h.events.some(e => e.includes('保存失败')));
  await h.Cache.flush({});
}

// A timeout rejects promptly, cancels the actual work and blocks any late commit.
{
  const h = harness(); let cancelled = 0;
  const op = new h.Operation(() => cancelled++, 100);
  const gate = deferred();
  await assert.rejects(op.stage('目录', 5, () => gate.promise), /目录超时/);
  assert.equal(cancelled, 1); gate.resolve(); await drain();
  assert.throws(() => op.beginCommit(), /已取消/);
  const committed = new h.Operation(() => assert.fail('cancelled atomic commit'));
  committed.beginCommit(); committed.cancel(); assert.equal(committed.isCancelled(), false);
}

// Exercise the real WebBookService pagination and rule ownership, with transport/parser fixtures.
function webHarness(strict = true) {
  const requests = [], cancelledOwners = [];
  let stopped = false, parseGate = null, failSecond = false, batchGate = null;
  class RuleContext {
    put() {} get() { return ''; } has() { return false; }
    loadFromJson() {} toPersistentJson() { return '{}'; } toPersistentRecord() { return {}; }
  }
  const rules = { executeBatch: async () => batchGate ? await batchGate.promise : { values: [], errors: [], contextValues: [] },
    cancelOwner: id => cancelledOwners.push(id), clearOwner() {} };
  const context = vm.createContext({ console: { info() {}, warn() {}, log() {} },
    HttpClient: class { cancelAll() {} }, RuleContext,
    AnalyzeUrl: class {
      setCancelCheck(check) { this.check = check; return this; }
      async fetch(url) {
        assert(!this.check(), 'cancelled work issued another HTTP request'); requests.push(url);
        return { success: !(failSecond && url === '/next'), body: url === '/next' ? 'last' : 'first', url, statusCode: 200 };
      }
    },
    SourceEngineHost: { setError() {}, getError: () => '' }, NativeSourceService: { isNative: () => false },
    BookSourceMetadataSupport: { applyBook() {} }, BookSourceDataUrlSupport: { isEncodedSource: () => false },
    EncodedSourceUrl: { canHandle: () => false, decode: () => null, scalarVariables: () => ({}) },
    SourceRuntimeStage: { TOC: 'toc' }, BookUrlResolver: { effectiveBase: response => response.url },
    RuleExecutionService: { get: () => rules }, RuleBatchExecutionRequest: class {}, RuleFieldRequest: class {},
    RuleValue: { fromExternal: value => value },
  });
  vm.runInContext(stripTypeScriptTypes(readEtsModule('core/book/WebBookService.ts')
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')) + '\nglobalThis.Service = WebBookService;', context);
  const service = new context.Service(() => stopped, strict);
  service.resolveTocUrl = () => '/toc'; service.requestVerificationIfNeeded = () => false;
  service.parseChapterPage = async (_source, _book, body) => {
    if (parseGate) await parseGate.promise;
    return [{ title: body, url: '/' + body }];
  };
  service.evaluateNextTocUrls = async (_source, _book, body) => body === 'first' ? ['/next'] : [];
  const source = { bookSourceUrl: 'source', tocRule: { chapterList: '$.chapters', nextTocUrl: '$.next' } };
  return { service, source, requests, cancelledOwners, context: new RuleContext(),
    stop() { stopped = true; service.cancelPendingRequests(); },
    failPage() { failSecond = true; }, holdParse() { return parseGate = deferred(); },
    holdBatch() { return batchGate = deferred(); } };
}
{
  const h = webHarness(); h.failPage();
  await assert.rejects(h.service.getChapterList(h.source, book('A'), 0, false), /目录分页加载失败/);
  assert.deepEqual(h.requests, ['/toc', '/next']);
  const legacy = webHarness(false); legacy.failPage();
  assert.equal((await legacy.service.getChapterList(legacy.source, book('A'), 0, false)).length, 1,
    'strict completeness is scoped to source switching');
}
{
  const h = webHarness(); const gate = h.holdParse();
  const work = h.service.getChapterList(h.source, book('A'), 0, false); await drain();
  h.stop(); gate.resolve(); await assert.rejects(work, /已取消/);
  assert.deepEqual(h.requests, ['/toc'], 'no next page after cancelled parsing');
}
{
  const h = webHarness(); const gate = h.holdBatch();
  const work = h.service.executeSingleRuleField(h.source, book('A'), null, '$.value', '{}', '/', 'toc', h.context);
  await drain(); h.stop();
  assert.equal(h.cancelledOwners.length, 1, 'TOC rule owner is cancellable');
  gate.resolve({ values: [{ value: '/next' }], errors: [], contextValues: [] });
  await assert.rejects(work, /已取消/);
  assert.equal(h.service.activeRuleOwners.size, 0);
}

console.log('Change-source cache, lifecycle, deadlines, commit, pagination and rule cancellation checks passed.');
