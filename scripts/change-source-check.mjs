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
  // 按形态挑书源：formSplit 决定哪些跳过，searchFound 按搜索参数给结果，enabledList 是启用书源。
  let formSplit = null, searchFound = null, enabledList = null, scopeForms = [];
  const searchOptions = [];
  const old = book('A');
  const db = {
    initWithContext: async () => {},
    getBook: async () => old,
    getBookSource: async origin => ({ enabled: origin !== 'disabled', bookSourceUrl: origin }),
    getEnabledBookSourcesForSearch: async () => { if (!enabledList) throw new Error('no db'); return enabledList; },
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
    setCatalogProgress(listener) { this.catalogProgress = listener; }
    async getBookInfo(_source, next) {
      events.push('detail'); if (detailGate) await detailGate.promise;
      return Object.assign(next, { name: '测试书完整版', author: '作者 著', bookUrl: next.bookUrl + '/detail' });
    }
    async getChapterList() {
      events.push('toc'); if (tocGate) await tocGate.promise;
      this.catalogProgress?.(1, 2);
      return [{ title: '第一章', url: '/chapter' }, { title: '第二章', url: '/chapter2' }];
    }
  }
  class SearchCoordinator {
    cancel() { events.push('cancel-search'); searchGate?.resolve([]); }
    async search(_name, callback, options) {
      searchCount++;
      searchOptions.push(options);
      const found = searchFound ? searchFound(options) : [book('B'), book('C')];
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
    SearchExploreSettingsStore: { getSearchConcurrency: () => 6, CHANGE_SOURCE_SCOPE_ALL: 'all', CHANGE_SOURCE_SCOPE_GROUP: 'group',
      CHANGE_SOURCE_FORMS: ['novel', 'comic', 'audio', 'video'],
      loadChangeSourceScope: async () => ({ mode: 'all', groups: [], forms: scopeForms.slice() }),
      saveChangeSourceScope: async scope => { scopeForms = scope.forms.slice(); } },
    ChangeSourceScope: class { constructor() { this.mode = 'all'; this.groups = []; this.forms = []; } },
    BookSourceGroupStore: { loadOrder: async () => {} },
    SourcePickerKit: { groupLabel: group => group || '未分组', sortGroups: groups => groups },
    SourceFormProfile: { load: async () => {}, isAlways: () => false, alwaysCount: () => 0, setAlways() {}, clearAlways() {},
      split: (sources, forms) => formSplit ? formSplit(sources, forms) : { kept: sources, skipped: [] } },
    SourceFormJudge: { label: form => ({ comic: '漫画', audio: '有声书', video: '短剧' })[form] || '小说' },
    SearchBookShelfHelper: { isNavigationResult: () => false },
    BookIdentity: { keyOfUrl: (url, origin) => origin + '|' + url, keyOfSearchBook: b => b.origin + '|' + b.bookUrl },
    SearchChineseScriptRuntime: { forSearch: async () => null, saveHints: async () => {}, ready: () => null, enabled: () => true },
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
  const Matcher = load('core/book/ChapterPositionMatcher.ts', 'ChapterPositionMatcher');
  const Task = load('core/book/BookSourceSwitchTask.ets', 'BookSourceSwitchTask');
  const AuthorMatch = load('core/book/ChangeSourceAuthorMatch.ts', 'ChangeSourceAuthorMatch');
  const Policy = load('core/book/BatchSourceSwitchPolicy.ts', 'BatchSourceSwitchPolicy');
  load('core/book/ChangeSourceCandidates.ets', 'ChangeSourceCandidates');
  const Dialog = load('components/BookChangeSourceDialog.ets', 'BookChangeSourceDialog', true);
  return { Cache, Operation, Matcher, Task, AuthorMatch, Policy, Dialog, events, writes, disk, old, get searchCount() { return searchCount; },
    holdDetail() { return detailGate = deferred(); }, holdToc() { return tocGate = deferred(); },
    holdCommit() { return commitGate = deferred(); }, holdSearch() { return searchGate = deferred(); },
    holdWrite() { return beforeWrite = deferred(); }, holdRead() { return beforeRead = deferred(); },
    failCommit() { failCommit = true; },
    searchOptions, setFormSplit(fn) { formSplit = fn; }, setSearchFound(fn) { searchFound = fn; },
    setEnabled(list) { enabledList = list; }, setScopeForms(forms) { scopeForms = forms; } };
}

// The new catalog's reading position follows the chapter title, not the bare index.
{
  const { Matcher } = harness();
  const titles = list => list.map(title => ({ title }));
  // An extra notice in front shifts every chapter by one.
  assert.equal(Matcher.match(2, '第三章 风起', 10, titles(['公告', '第一章 开端', '第二章 相遇', '第三章 风起', '第四章'])), 3);
  // Same chapter written with different numerals and spacing.
  assert.equal(Matcher.match(4, '第十二章　夜雨', 20, titles(['第8章', '第9章', '第10章', '第11章', '请假条', '第12章 夜雨', '第13章'])), 5);
  // Only the number survives when the other source drops chapter names.
  assert.equal(Matcher.match(1, '第一百零五章 归来', 200, titles(['第104章', '第105章', '第106章'])), 1);
  assert.equal(Matcher.match(0, '第一百零五章 归来', 3, titles(['第103章', '第104章', '第105章'])), 2);
  // Volumes restarting at chapter one: the nearest equal title wins.
  const volumes = titles(['第一卷', '第一章 起', '第二章 承', '第二卷', '第一章 起', '第二章 承']);
  assert.equal(Matcher.match(5, '第二章 承', 6, volumes), 5);
  assert.equal(Matcher.match(2, '第二章 承', 6, volumes), 2);
  // Nothing recognisable: keep the clamped index.
  assert.equal(Matcher.match(3, '番外', 4, titles(['甲', '乙'])), 1);
  assert.equal(Matcher.match(3, '', 4, titles(['第一章', '第二章'])), 1);
  // Far outside the window, a unique full-title match is still taken; duplicates are not.
  const far = titles(Array.from({ length: 80 }, (_, i) => `第${i + 1}章`));
  far[70] = { title: '尾声 再见' };
  assert.equal(Matcher.match(5, '尾声 再见', 80, far), 70);
  far[71] = { title: '尾声 再见' };
  assert.equal(Matcher.match(5, '尾声 再见', 80, far), 5);
  assert.equal(Matcher.parseNumber('二〇二三'), 2023);
  assert.equal(Matcher.parseNumber('一千零二十'), 1020);
  assert.equal(Matcher.parseNumber('十二'), 12);
  assert.equal(Matcher.parseNumber('三万零五'), 30005);
  assert.equal(Matcher.chapterNumber('０３２ 回家'), 32);
}

// The switch reports catalog progress and maps the position by title.
{
  const h = harness();
  h.old.durChapterIndex = 3;
  h.old.durChapterTitle = '第一章';
  const labels = [];
  const task = new h.Task(false);
  const next = await task.run({}, 'key', h.old, book('B'), null, label => labels.push(label), () => {});
  assert(labels.includes('正在加载新源目录：已读 1 页 · 2 章'), labels.join('|'));
  assert.equal(next.durChapterIndex, 0);
  assert.equal(next.durChapterTitle, '第一章');
}

// Batch switching prepares candidates without touching the shelf, then commits the chosen one from a fresh task.
{
  const h = harness();
  const preparing = new h.Task(false, 30000);
  const prepared = await preparing.prepare({}, 'key', h.old, book('B'), null, () => {});
  preparing.release();
  assert.equal(prepared.chapters.length, 2);
  assert.equal(h.Task.revisionOf(h.old), 0, 'preparing alone must not count as a switch');
  let delivered;
  const next = await new h.Task(false).commit({}, prepared, () => {}, (switched, previousUrl) => {
    delivered = [switched.origin, previousUrl];
  }, 0);
  assert.equal(next.origin, 'B');
  assert.deepEqual(delivered, ['B', '/a']);
  assert(h.Task.revisionOf({ origin: 'A', bookUrl: '/a' }) > 0);
  // The book was switched meanwhile (by hand, or by an earlier commit): a stale prepared result is refused.
  prepared.target = { origin: 'A', bookUrl: '/a' };
  await assert.rejects(new h.Task(false).commit({}, prepared, () => {}, () => {}, 0), /已经换过源/);
}

// Batch policy: only confidently identified candidates, and the longest catalog that reaches the reading position.
{
  const { Policy: P } = harness();
  const fold = text => text.replace(/貓/g, '猫').replace(/膩/g, '腻');
  assert.deepEqual(Array.from(P.eligible('猫腻', ['貓膩', '', '别人', '猫腻 著'], fold)), [0, 3]);
  assert.deepEqual(Array.from(P.eligible('猫腻', ['貓膩'])), [], 'without the dictionary a traditional name is not assumed equal');
  // The shelf book has no author: accept only when the candidates cannot be two different books.
  assert.deepEqual(Array.from(P.eligible('', ['', '猫腻', '貓膩'], fold)), [0, 1, 2]);
  assert.deepEqual(Array.from(P.eligible('未知', ['猫腻', '别人'], fold)), []);
  assert.equal(P.pick([120, 800, 800, 30], 100), 1);
  assert.equal(P.pick([50, 100], 100), -1, 'a catalog ending at or before the reading position is not usable');
  assert.equal(P.pick([1], 0), 0);
  assert.equal(P.pick([], 0), -1);
  assert.equal(P.enough(800, 800, 100), true);
  assert.equal(P.enough(799, 800, 100), false);
  assert.equal(P.enough(800, 0, 100), false, 'unknown old length: keep comparing candidates');
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

// The current source is searched too: an aggregated source's other sites stay, only the book being read is hidden,
// including the search address the detail page rewrote during the switch.
{
  const h = harness();
  const panel = new h.Dialog(); panel.targetBook = h.old;
  panel.aboutToAppear(); await drain();
  const kept = panel.filterResults([book('A'), book('A', { bookUrl: '/a-site2' }), book('B')], '/a', 'A');
  assert.deepEqual(Array.from(kept, b => b.bookUrl), ['/a-site2', '/b']);
  panel.currentBookAliases = ['/a-search'];
  assert.deepEqual(Array.from(panel.filterResults([book('A', { bookUrl: '/a-search' })], '/a', 'A')), []);
  panel.requestClose(); await h.Cache.flush({});
  const dialogSource = readEtsModule('components/BookChangeSourceDialog.ets');
  assert(!dialogSource.includes('excludeSourceUrls'), 'change source must search the current source too');
  assert(/maxResultsPerSource: MAX_RESULTS_PER_SOURCE/.test(dialogSource));
}

// Author check: normalized names match, placeholders stay undecided, same-title books by others are told apart.
{
  const { AuthorMatch: M } = harness();
  const fold = text => text.replace(/貓/g, '猫').replace(/膩/g, '腻');
  const cases = [
    ['土豆豌豆', '土豆豌豆', M.SAME],
    ['土豆豌豆', '作者：土豆豌豆 著', M.SAME],
    ['土豆豌豆', '土豆豌豆（完结）', M.SAME],
    ['土豆豌豆', '土豆豌豆/著', M.SAME],
    ['作者 著', '作者', M.SAME],
    ['Ｊ.Ｋ.Rowling', 'jk rowling', M.SAME],
    ['土豆豌豆', '土豆豌豆工作室', M.SAME],
    ['土豆豌豆', '锈迹斑斑的克雷恩', M.DIFFERENT],
    ['唐', '唐家三少', M.DIFFERENT],
    ['土豆豌豆', '', M.UNKNOWN],
    ['土豆豌豆', '未知', M.UNKNOWN],
    ['', '锈迹斑斑的克雷恩', M.UNKNOWN],
  ];
  for (const [a, b, expected] of cases) assert.equal(M.compare(a, b), expected, `${a} vs ${b}`);
  assert.equal(M.compare('貓膩', '猫腻'), M.DIFFERENT, 'without the dictionary scripts differ');
  assert.equal(M.compare('貓膩', '猫腻', fold), M.SAME);
}

// The panel hides other authors behind a status-line link, keeps unknown authors after matching ones,
// and counts other-group results only among those it would show.
{
  const h = harness();
  const target = book('A', { author: '土豆豌豆' });
  const panel = new h.Dialog(); panel.targetBook = target;
  panel.aboutToAppear(); await drain();
  panel.allResults = [
    book('X', { author: '锈迹斑斑的克雷恩' }), book('U', { author: '' }), book('B', { author: '土豆豌豆 著' }),
    book('Y', { author: '锈迹斑斑的克雷恩' }), book('C', { author: '土豆豌豆' }), book('Z', { author: '别人' })
  ];
  panel.applyScope();
  assert.deepEqual(Array.from(panel.results, b => b.origin), ['B', 'C', 'U']);
  assert.equal(panel.authorHiddenCount, 3);
  assert.equal(panel.authorTip(), '；3 个作者不同，');
  assert.equal(panel.authorLink(), '显示');
  panel.sourceGroupOf = new Map([['B', '女频'], ['C', '男频'], ['U', '女频'], ['X', '女频'], ['Y', '男频'], ['Z', '男频']]);
  panel.scopeMode = 'group'; panel.scopeGroups = ['女频'];
  assert(panel.isScoped());
  panel.applyScope();
  assert.deepEqual(Array.from(panel.results, b => b.origin), ['B', 'U']);
  assert.equal(panel.hiddenCount, 1, 'other-group count skips other authors');
  assert.equal(panel.authorHiddenCount, 1);
  panel.revealAuthorMismatch();
  assert.deepEqual(Array.from(panel.results, b => b.origin), ['B', 'U', 'X']);
  assert.equal(panel.hiddenCount, 3);
  assert.equal(panel.authorTip(), '');
  assert(panel.isAuthorMismatch(panel.results[2]));
  panel.revealHiddenResults();
  assert.deepEqual(Array.from(panel.results, b => b.origin), ['B', 'C', 'U', 'X', 'Y', 'Z']);
  panel.requestClose(); await h.Cache.flush({});
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

// Source form judge: learned results beat declarations, declarations beat names, unknown sources are searched.
{
  const Judge = (() => {
    const context = vm.createContext({});
    const source = readEtsModule('core/book/SourceFormJudge.ts').replace(/export /g, '');
    vm.runInContext(stripTypeScriptTypes(source) + '\nglobalThis.J = { SourceFormJudge, SourceFormFacts, SourceFormTally };', context);
    return context.J;
  })();
  const { SourceFormJudge: J, SourceFormFacts: Facts, SourceFormTally: Tally } = Judge;
  const facts = (extra = {}) => Object.assign(new Facts(), extra);
  const tally = (novel, comic, audio, video) => Object.assign(new Tally(), { novel, comic, audio, video });
  assert.equal(J.judge(facts(), ['novel']).search, true, 'nothing known: search it');
  const drama = J.judge(facts({ tally: tally(0, 0, 0, 41) }), ['novel']);
  assert.equal(drama.search, false);
  assert.equal(drama.reason, '近 41 条结果都是短剧');
  assert.equal(J.judge(facts({ tally: tally(0, 0, 0, 41) }), ['novel', 'video']).search, true, 'ticked forms are searched');
  assert.equal(J.judge(facts({ tally: tally(30, 25, 5, 40) }), ['audio']).search, true, 'aggregate sources stay');
  assert.equal(J.judge(facts({ tally: tally(99, 0, 0, 1) }), ['video']).search, false, 'one stray result is noise');
  assert.equal(J.judge(facts({ tally: tally(0, 0, 0, 5) }), ['novel']).search, true, 'too few samples to decide');
  assert.equal(J.judge(facts({ tally: tally(0, 0, 0, 5), declared: 'comic', declaredBy: 'type' }), ['novel']).reason,
    '书源类型标为漫画');
  assert.equal(J.judge(facts({ declared: 'comic', declaredBy: 'rule' }), ['novel']).reason, '正文取的是图片，按漫画书源算');
  assert.equal(J.judge(facts({ declared: 'audio', declaredBy: 'type' }), ['audio']).search, true);
  assert.equal(J.judge(facts({ tally: tally(40, 0, 0, 0), declared: 'comic', declaredBy: 'rule' }), ['novel']).search, true,
    'a misread image rule loses to what the source actually returned');
  assert.equal(J.judge(facts({ name: '某某短剧' }), ['novel']).reason, '名称或分组含“短剧”');
  assert.equal(J.judge(facts({ name: '漫画小说网' }), ['novel']).search, true, 'mixed names decide nothing');
  assert.equal(J.judge(facts({ name: '听书站', group: '漫画' }), ['novel']).search, true);
  assert.equal(J.judge(facts({ name: '某某短剧', always: true }), ['novel']).search, true, 'always-search wins');
}

// The panel searches only the kept sources, lists ticked forms in their own sections and falls back to the
// skipped sources when the kept ones have nothing of the book's own form.
{
  const h = harness();
  const src = url => ({ bookSourceUrl: url, bookSourceName: url, bookSourceGroup: '' });
  h.setEnabled([src('B'), src('C'), src('D'), src('M')]);
  h.setScopeForms(['comic']);
  h.setFormSplit(sources => ({
    kept: sources.filter(s => s.bookSourceUrl !== 'D'),
    skipped: sources.filter(s => s.bookSourceUrl === 'D').map(source => ({ source, reason: '近 41 条结果都是短剧' }))
  }));
  h.setSearchFound(() => [book('B'), book('M', { type: 1 })]);
  const panel = new h.Dialog(); panel.targetBook = h.old;
  panel.aboutToAppear(); await drain();
  assert.deepEqual(Array.from(panel.extraForms), ['comic']);
  const options = h.searchOptions[0];
  assert.deepEqual(Array.from(options.mediaCategories), ['text', 'comic']);
  assert.deepEqual(Array.from(options.targetSources, s => s.bookSourceUrl), ['B', 'C', 'M']);
  assert.equal(options.maxResultsPerCategory, 20);
  assert.deepEqual(Array.from(panel.results, b => b.origin), ['B']);
  assert.deepEqual(Array.from(panel.otherRows, r => r.book ? r.book.origin : 'header:' + r.form), ['header:comic', 'M']);
  assert.equal(panel.skipTip(), '；按形态跳过 1 个书源，');
  // Unticking drops the other-form results right away and remembers the choice.
  panel.toggleForm('comic');
  assert.equal(panel.otherRows.length, 0);
  assert.deepEqual(Array.from(panel.extraForms), []);
  panel.requestClose(); await h.Cache.flush({});

  const f = harness();
  f.setEnabled([src('B'), src('D')]);
  f.setFormSplit(sources => ({
    kept: sources.filter(s => s.bookSourceUrl !== 'D'),
    skipped: sources.filter(s => s.bookSourceUrl === 'D').map(source => ({ source, reason: '书源类型标为有声书' }))
  }));
  f.setSearchFound(options => options.targetSources[0].bookSourceUrl === 'D' ? [book('D')] : []);
  const fallback = new f.Dialog(); fallback.targetBook = f.old;
  fallback.aboutToAppear(); await drain();
  assert.equal(f.searchOptions.length, 2, 'nothing found among kept sources: search the skipped ones');
  assert.deepEqual(Array.from(f.searchOptions[1].targetSources, s => s.bookSourceUrl), ['D']);
  assert.deepEqual(Array.from(fallback.results, b => b.origin), ['D']);
  assert.equal(fallback.skipTip(), '；跳过的 1 个书源也搜过了，');
  assert.equal(fallback.searching, false);
  fallback.requestClose(); await f.Cache.flush({});
}

console.log('Change-source cache, lifecycle, deadlines, commit, pagination and rule cancellation checks passed.');
