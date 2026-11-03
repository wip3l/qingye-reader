// Execute production capture/save/restore callbacks with native line and List geometry doubles.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const source = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
let timerId = 0, owner = true;
const timers = new Map(), writes = [];
const sandbox = vm.createContext({ console, Date, px2vp: n => n / 2,
  LengthMetrics: { vp: n => n }, ScrollAlign: { START: 0 },
  setTimeout: fn => { timers.set(++timerId, fn); return timerId; }, clearTimeout: id => timers.delete(id),
  ReaderProgressCheckpoint: { canWrite: () => owner },
  Book: { hasStartedReading: book => book.getVariable('readStarted') === '1' },
  AppDatabase: { getInstance: () => ({ updateBookReadingProgress: async (...args) => writes.push(args) }) },
  AppStorage: { setOrCreate() {} },
  READER_PROGRESS_OFFSET_KEY: 'readProgressCharOffsetV2',
  READER_PROGRESS_OFFSET_CHAPTER_KEY: 'readProgressCharOffsetChapterV2',
});
const names = ['captureReaderContinuousAnchor', 'readerContinuousSourceIdentity', 'readerContinuousAnchorLineTop',
  'getReaderStableReflowOffset', 'restoreReaderTypographyOffsetIfAvailable', 'scheduleReaderComicScrollRestore',
  'savedReaderProgressOffset', 'saveReadingProgress', 'scheduleReaderComicProgressSave',
  'clearReaderComicProgressSaveTimer', 'flushReadingProgressCheckpoint'];
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderScrollAnchor.ts').replace(/^export /gm, '') +
  `\nclass Reader { ${names.map(method).join('\n')} }\nglobalThis.Reader = Reader; globalThis.Anchor = ReaderScrollAnchor;`), sandbox);
const { Reader, Anchor } = sandbox;
async function tick() {
  const jobs = [...timers.values()]; timers.clear();
  for (const fn of jobs) fn();
  for (let i = 0; i < 8; i++) await Promise.resolve();
}
async function settle() {
  for (let i = 0; timers.size && i < 400; i++) await tick();
  assert.equal(timers.size, 0, 'restore and save retries are bounded');
}
function fixture() {
  const r = new Reader(), variable = new Map();
  const book = { bookUrl: 'book', getVariable: key => variable.get(key) || '',
    putVariable: (key, val) => variable.set(key, val), get variable() { return JSON.stringify(Object.fromEntries(variable)); } };
  const paragraphs = [{ topHeight: 0, height: 40, startIndex: 0, endIndex: 20 },
    { topHeight: 40, height: 40, startIndex: 20, endIndex: 40 },
    { topHeight: 80, height: 40, startIndex: 40, endIndex: 60 }];
  const layout = { identity: 'native', fragments: [{ displayStart: 0, displayEnd: 60,
    paragraphY: 0, imageSource: '', paragraph: { getLineCount: () => paragraphs.length,
      getLineMetrics: i => { assert.equal(typeof i, 'number'); return paragraphs[i]; } } }] };
  Object.assign(r, {
    book, chapters: [{ title: 'chapter', url: 'chapter-0' }, { title: 'next', url: 'chapter-1' }],
    readerPageVisible: true, readerInitialPageReady: true, readerProgressRestoreConfirmed: true,
    readerComicScrollRestoring: false, pendingRestorePageIndex: -1, readerTypographyRestoreOffset: -1,
    readerContinuousCommitChapter: -1, isLoading: false, quickJumpBusy: false,
    currentChapterIndex: 0, currentPageIndex: 0, contentPages: ['first', 'second'],
    pagedContentText: 'x'.repeat(3600), readerContinuousVisibleStart: 0, readerContinuousVisibleEnd: 0,
    readerProgressAnchorChapterIndex: -1, readerProgressAnchorPageIndex: 0,
    readerProgressAnchorOffset: -1, readerContinuousAnchor: null, readerContinuousRestoreAnchor: null,
    readerComicScrollRestoreSerial: 0, readerComicProgressSaveTimerId: -1,
    readingProgressSaveQueue: Promise.resolve(), lastRecentReadCardChapterIndex: 0,
    layoutReady: true, layoutIdentity: 'font-20', itemTop: -10, lineReads: 0, scrollCalls: [],
    usesReaderContinuousV2: () => true, isReaderComicPagedMode: () => false,
    isReaderContinuousScrollSurfaceActive: () => true,
    readerContinuousV2ViewportPx: () => [0, 600], readerContinuousV2ItemId: i => `row-${i}`,
    getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: () =>
      ({ size: { height: 1800 }, windowOffset: { y: r.itemTop } }) }) }),
    readerContinuousV2Layout: () => r.layoutReady ? layout : null,
    readerContinuousV2Request: () => ({ snapshot: { identity: r.layoutIdentity } }),
    readerContinuousV2State: () => ({ ready: r.layoutReady, failed: r.layoutFailed }),
    readerContinuousV2Documents: new Map([['native', {
      sourceOffsetForDisplay: offset => offset, displayOffsetForSource: offset => offset,
    }]]), readerContinuousV2Sources: new Map([['native', 0]]),
    readerPaginationSourceHash: text => text.charCodeAt(0),
    readerContinuousListIndex: i => i + 4, // preceding chapter insertion is independent of the anchor
    readerComicScroller: { scrollToIndex: (index, smooth, align, options) => {
      r.scrollCalls.push({ index, smooth, extraOffset: options.extraOffset });
      r.itemTop = -options.extraOffset * 2;
      if (r.clampAtEnd) r.itemTop = Math.max(-20, r.itemTop);
      r.readerContinuousVisibleStart = r.currentPageIndex;
    } },
    getPageStartOffset: i => i * 1800, findPageIndexByOffset: n => n >= 1800 ? 1 : 0,
    normalizeReaderSpreadPageIndex: i => i, clampChapterIndex: i => i,
    getCurrentPageStartOffset: () => r.currentPageIndex * 1800,
    getShelfLastReadPageText: i => `preview-${i}`, getShelfLastReadPageImage: () => '',
    currentChapterProgressPageCount: () => 8, isCurrentReaderPaginationComplete: () => true,
    canSaveReadingProgress: () => true, readerEngine: () => ({ book }),
    reloadRecentReadCardLater() {}, finishReaderInitialOpening() {}, setCurrentPageText() {},
    scheduleReaderContinuousPositionUpdate() {}, ensureReaderContinuousNeighbors() {},
    shouldRenderTtsFocus: () => false, settleCommittedLocalPageTurnForCheckpoint() {},
    clearReaderPagedProgressSaveTimer() {}, ttsProgressSaveTimerId: -1,
  });
  r.contentPageEnds = [1800, 3600];
  return { r, book, layout, paragraphs, variable };
}

// A clipped first line retains the exact screen displacement, even without crossing a chunk boundary.
{
  const { r, book, paragraphs } = fixture();
  r.captureReaderContinuousAnchor();
  assert.equal(r.readerContinuousAnchor.offset, 0);
  assert.equal(r.readerContinuousAnchor.viewportOffsetVp, -5);
  r.itemTop = -54;
  r.captureReaderContinuousAnchor();
  assert.equal(r.currentPageIndex, 0);
  assert.equal(r.readerContinuousAnchor.offset, 20);
  assert.equal(r.readerContinuousAnchor.viewportOffsetVp, -7);
  assert.equal(r.getReaderStableReflowOffset(), 20);
  await r.saveReadingProgress();
  assert.equal(book.getVariable('readStarted'), '1', 'moving within the first chunk starts a new book');
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '20');
  const anchor = Anchor.decode(book.getVariable(Anchor.VARIABLE_KEY), 0, 20);
  assert(anchor); assert.equal(anchor.viewportOffsetVp, -7);

  r.readerTypographyRestoreOffset = 20; r.readerContinuousRestoreAnchor = anchor;
  r.itemTop = 0;
  assert.equal(r.restoreReaderTypographyOffsetIfAvailable(true), true);
  r.scheduleReaderComicScrollRestore(); await settle();
  assert.equal(r.scrollCalls.at(-1).index, 4, 'position resolves through the current chapter List index');
  assert.equal(r.scrollCalls.at(-1).extraOffset, 27);
  assert.equal(r.itemTop, -54, 'same layout returns to the identical clipped line');
  assert.equal(r.readerContinuousRestoreAnchor, null);
  assert.equal(r.readerComicScrollRestoring, false);

  // Native wrapping changed: locate the saved character in its new line, discard old pixel displacement.
  r.readerContinuousRestoreAnchor = anchor; r.readerTypographyRestoreOffset = 20;
  r.layoutIdentity = 'font-30'; r.itemTop = 0;
  paragraphs[0].endIndex = 30;
  paragraphs[1].startIndex = 30;
  r.restoreReaderTypographyOffsetIfAvailable(true);
  r.scheduleReaderComicScrollRestore(); await settle();
  assert.equal(r.scrollCalls.at(-1).extraOffset, 0, 'the saved character now belongs to the first line');
  assert.equal(r.readerContinuousAnchor.offset, 0);
}

// Repeated movement inside one chunk merges into a single durable position after scrolling stops.
{
  const { r, book } = fixture();
  r.itemTop = -54; r.scheduleReaderComicProgressSave();
  r.itemTop = -94; r.scheduleReaderComicProgressSave();
  assert.equal(timers.size, 1);
  await settle();
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '40');
  assert.equal(r.currentPageIndex, 0);
}

// Reading only part of the very first line still has a position, despite its character offset remaining zero.
{
  const { r, book } = fixture(); r.itemTop = -10;
  await r.saveReadingProgress();
  assert.equal(book.getVariable('readStarted'), '1');
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '0');
  assert.equal(Anchor.decode(book.getVariable(Anchor.VARIABLE_KEY), 0, 0).viewportOffsetVp, -5);
}

// Cold and failed layouts cannot overwrite a durable target, and a hidden timer cannot finish a restore.
{
  const { r, book } = fixture();
  r.itemTop = -54; await r.saveReadingProgress();
  const target = r.readerContinuousAnchor;
  r.readerTypographyRestoreOffset = target.offset; r.readerContinuousRestoreAnchor = target;
  r.restoreReaderTypographyOffsetIfAvailable(true);
  r.layoutReady = false; r.scheduleReaderComicScrollRestore(); await tick();
  assert.equal(r.scrollCalls.length, 0, 'wait for real heights instead of aligning placeholder rows');
  r.readerPageVisible = false; await tick();
  r.itemTop = 0; await r.flushReadingProgressCheckpoint();
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '20');
  assert.equal(JSON.parse(book.getVariable(Anchor.VARIABLE_KEY)).viewportOffsetVp, -7);
  assert.equal(r.readerComicScrollRestoring, true);
  r.readerPageVisible = true; r.layoutReady = true; r.scheduleReaderComicScrollRestore(); await settle();
  assert.equal(r.itemTop, -54, 'foreground retries the same immutable target');

  r.readerContinuousRestoreAnchor = r.readerContinuousAnchor;
  r.layoutReady = false; r.layoutFailed = true;
  r.scheduleReaderComicScrollRestore(); await settle();
  assert.equal(r.readerComicScrollRestoring, false, 'failed native layout has a bounded block fallback');
}

// A source/chapter replacement invalidates the old line data, while legacy checkpoints still restore.
{
  const { r } = fixture();
  r.itemTop = -54; r.captureReaderContinuousAnchor();
  r.readerContinuousRestoreAnchor = r.readerContinuousAnchor;
  r.readerContinuousRestoreAnchor.pageIndex = 1;
  r.pagedContentText = 'y'.repeat(3600); r.readerTypographyRestoreOffset = 20;
  r.restoreReaderTypographyOffsetIfAvailable(true);
  assert.equal(r.currentPageIndex, 1);
  assert.equal(r.readerContinuousRestoreAnchor.offset, 1800, 'changed source falls back to the saved block');
  assert.equal(r.readerContinuousRestoreAnchor.viewportOffsetVp, 0);
  r.currentChapterIndex = 1; r.scheduleReaderComicScrollRestore(); await settle();
  assert.equal(r.readerContinuousRestoreAnchor, null, 'another chapter never receives the old line target');
  r.currentChapterIndex = 0; r.readerContinuousAnchor = null;
  r.readerTypographyRestoreOffset = 40; r.restoreReaderTypographyOffsetIfAvailable(true);
  assert.equal(r.readerContinuousRestoreAnchor.offset, 40, 'legacy character offsets gain line-level restore');
}

// Gap, illustration, repeated chunks and chapter-end offsets preserve the production source mapping.
{
  const { r, layout } = fixture();
  layout.fragments[0].paragraphY = 50; r.itemTop = 0;
  r.captureReaderContinuousAnchor();
  assert.equal(r.readerContinuousAnchor.viewportOffsetVp, 25, 'paragraph/title gap is part of viewport position');
  layout.fragments.unshift({ displayStart: 0, displayEnd: 1, imageSource: 'image', imageRect: { top: 0, bottom: 50 } });
  r.itemTop = -10; r.captureReaderContinuousAnchor();
  assert.equal(r.readerContinuousAnchor.viewportOffsetVp, -5, 'a clipped illustration retains its own origin');
  layout.fragments.shift();
  r.readerContinuousV2Sources.set('native', 1800); r.currentPageIndex = 1;
  r.readerContinuousVisibleStart = 1; r.readerContinuousVisibleEnd = 1; r.itemTop = -104;
  r.captureReaderContinuousAnchor();
  assert.equal(r.readerContinuousAnchor.offset, 1820, 'identical-looking chunks retain distinct offsets');
  assert.equal(r.readerContinuousAnchor.pageIndex, 1);
  assert.equal(r.readerContinuousAnchorLineTop(1, 3600), 130, 'end maps to the last real line');
  r.readerContinuousRestoreAnchor = r.readerContinuousAnchor; r.clampAtEnd = true;
  r.scheduleReaderComicScrollRestore(); await settle();
  assert(r.scrollCalls.length <= 6, 'chapter-tail clamping cannot retry forever');
}

// Capturing and resolving a long paragraph read logarithmically many native metrics.
{
  const { r, layout } = fixture(); let reads = 0;
  layout.fragments[0].displayEnd = 4096 * 30;
  layout.fragments[0].paragraph = { getLineCount: () => 4096, getLineMetrics: i => {
    assert.equal(typeof i, 'number'); reads++;
    return { topHeight: i * 20, height: 20, startIndex: i * 30, endIndex: (i + 1) * 30 };
  } };
  r.itemTop = -40001;
  r.getUIContext = () => ({ getComponentUtils: () => ({ getRectangleById: () =>
    ({ size: { height: 100000 }, windowOffset: { y: r.itemTop } }) }) });
  r.captureReaderContinuousAnchor();
  assert.equal(r.readerContinuousAnchor.offset, 60000);
  assert(reads <= 14);
  reads = 0;
  assert.equal(r.readerContinuousAnchorLineTop(0, 60000), 40000);
  assert(reads <= 14);
}

// Late/unmounted geometry, a pending target and a superseded page can never replace the captured checkpoint.
{
  const { r, book } = fixture(); r.itemTop = -54; await r.saveReadingProgress();
  r.readerPageVisible = false; r.itemTop = 0; await r.saveReadingProgress();
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '20');
  const before = writes.length; owner = false; await r.saveReadingProgress(); owner = true;
  assert.equal(writes.length, before);
  r.usesReaderContinuousV2 = () => false;
  await r.saveReadingProgress();
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '20', 'leaving temporary auto-scroll retains its captured text');
  r.readerPageVisible = true; r.usesReaderContinuousV2 = () => false;
  await r.saveReadingProgress();
  assert.equal(book.getVariable(Anchor.VARIABLE_KEY), '', 'paged saves invalidate stale scrolling geometry');
  assert.equal(book.getVariable('readProgressCharOffsetV2'), '0');
}

for (const raw of ['', 'null', '[]', '{bad', JSON.stringify({ version: 2 }),
  JSON.stringify({ version: 1, chapterIndex: 0, offset: 20, pageIndex: -1 })]) {
  assert.equal(Anchor.decode(raw, 0, 20), null);
}
{
  const { r } = fixture(); r.captureReaderContinuousAnchor();
  assert.equal(Anchor.decode(JSON.stringify(r.readerContinuousAnchor), 1, 0), null);
  assert.equal(Anchor.decode(JSON.stringify(r.readerContinuousAnchor), 0, 20), null);
}
assert.match(source, /\.onDidScroll\(\(\) => \{[^]*?scheduleReaderComicProgressSave\(\)/);
for (const name of ['onPageHide', 'aboutToDisappear', 'exitReaderPage']) {
  const body = method(name);
  assert(body.indexOf('captureReaderContinuousAnchor()') < body.indexOf('this.readerPageVisible = false'),
    `${name} captures before the route geometry can shrink`);
}
console.log('PASS: clipped-line persistence, pixel/character restore, typography, async layout, lifecycle, source/chapter guards, legacy fallback, illustrations, long paragraphs and bounded chapter tails');
