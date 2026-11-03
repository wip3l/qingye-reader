import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// Run actual reader callbacks and the continuous data source. Fetching and native rectangles are controlled
// so a scroll can be delivered while chapter promotion is awaiting content, without relying on device timing.
const source = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const sandbox = vm.createContext({ console: { info() {}, warn() {}, error() {} } });
const names = ['readerContinuousFirstVisiblePage', 'onReaderComicScrollIndexChanged',
  'runReaderContinuousChapterCommit', 'restorePendingPageIndex', 'getReaderInfoBarContext',
  'updateReaderContinuousDisplayPosition', 'readerContinuousV2FirstVisibleSourceOffset',
  'readerContinuousV2ChapterEndVisible'];
vm.runInContext(stripTypeScriptTypes(
  ['core/reader/ReaderDataSources.ets', 'core/reader/ReaderPageOffsets.ts', 'core/reader/ReaderInfoBarModel.ts']
    .map(file => readEtsModule(file).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')).join('\n') +
  `\nclass Reader { ${names.map(method).join('\n')} }\n` +
  'globalThis.Reader = Reader; globalThis.DataSource = ReaderContinuousDataSource;' +
  'globalThis.Segment = ReaderScrollSegment; globalThis.Text = ReaderInfoBarText; globalThis.Item = ReaderInfoItem;'), sandbox);
const noop = () => {};
function fixture(current = 0) {
  const r = new sandbox.Reader();
  const data = new sandbox.DataSource();
  const segments = [2, 3, 2].map((count, chapter) => {
    const segment = new sandbox.Segment();
    segment.chapterIndex = chapter;
    segment.pages = Array.from({ length: count }, (_, i) => `${chapter}-${i}`);
    segment.starts = segment.pages.map((_, i) => i * 100);
    segment.ends = segment.pages.map((_, i) => (i + 1) * 100);
    segment.source = 'x'.repeat(count * 100);
    return segment;
  });
  data.setCurrent(segments[0], 1);
  data.append(segments[1], 2);
  data.append(segments[2], -1);
  const calls = [], saves = [];
  Object.assign(r, {
    readerComicPageDataSource: data, chapters: [{}, {}, {}], currentChapterIndex: current,
    currentPageIndex: 0, readerContinuousCommitChapter: -1, readerComicChapterSwitching: false,
    pendingRestorePageIndex: -1, readerComicScrollRestoring: false, readerPageVisible: true,
    quickJumpBusy: false, readerContinuousReachedEnd: false,
    readerContinuousLastListStart: data.offsetOf(current), readerContinuousLastListEnd: data.offsetOf(current),
    contentPages: segments[current].pages, pagedContentText: segments[current].source,
    readerContinuousMetricsChapter: current, readerContinuousMetricsSource: segments[current].source,
    readerContinuousMetricsStarts: segments[current].starts, readerContinuousMetricsEnds: segments[current].ends,
    readerContinuousDisplayPageCount: segments[current].pages.length, viewportListTop: data.offsetOf(current),
    readerContinuousV2Documents: new Map(), readerContinuousV2Sources: new Map(),
    warmReaderContinuousLayouts: noop, scheduleReaderContinuousPositionUpdate: noop,
    pruneContinuousReaderSelectionAreas: noop, ensureReaderContinuousNeighbors: noop,
    preloadReaderContentLater: noop, preloadNextChapterPaginationLater: noop, preloadPreviousChapterPaginationLater: noop,
    isReaderContinuousScrollSurfaceActive: () => true, isReaderNovelContinuousScrollModeActive: () => true,
    usesReaderContinuousV2: () => true, isReaderImageOnlyPage: () => false,
    layoutReady: true, readerContinuousV2Request() { return { state: { ready: this.layoutReady } }; },
    isMirroringActiveTtsForCurrentBook: () => false, ttsReader: { isSpeaking: () => false },
    comicImageActions: () => ({ onChapterBecameCurrent: noop }), pauseReaderAutoScroll: noop,
    normalizeReaderSpreadPageIndex: i => i, clampChapterIndex: i => i, getChapterTitle: i => `chapter-${i}`,
    isReaderComicModeActive: () => false, isLandscapeDoublePageActive: () => false,
    isCurrentReaderPaginationComplete: () => true,
    commitReaderContinuousChapter: (chapter, page) => calls.push([chapter, page]),
    scheduleReaderComicProgressSave() { saves.push([this.currentChapterIndex, this.currentPageIndex]); },
    getPageStartOffset: i => i * 100, readerContinuousV2ViewportPx: () => [0, 100],
    readerContinuousV2ItemId(i) { return `${this.currentChapterIndex}:${i}`; },
    getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: id => {
      const [chapter, page] = id.split(':').map(Number);
      return { windowOffset: { y: (data.offsetOf(chapter) + page - r.viewportListTop) * 100 }, size: { height: 100 } };
    } }) }),
    readerContinuousV2Layout(i) {
      const identity = `${this.currentChapterIndex}:${i}`;
      this.readerContinuousV2Documents.set(identity, { sourceOffsetForDisplay: offset => offset });
      this.readerContinuousV2Sources.set(identity, i * 100);
      return { identity, fragments: [{ displayStart: 0, paragraphY: 0,
        paragraph: { getLineMetrics: () => [{ topHeight: 0, startIndex: 0 }] } }] };
    },
    async loadContent(_silent, chapter) {
      if (this.loadGate) await this.loadGate;
      if (this.loadFails) return false;
      const segment = segments[chapter];
      this.currentChapterIndex = chapter;
      this.contentPages = segment.pages; this.pagedContentText = segment.source;
      this.readerContinuousMetricsChapter = chapter; this.readerContinuousMetricsSource = segment.source;
      this.readerContinuousMetricsStarts = segment.starts; this.readerContinuousMetricsEnds = segment.ends;
      this.readerContinuousDisplayPageCount = segment.pages.length;
      this.restorePendingPageIndex(true);
      return true;
    },
  });
  return { r, data, calls, saves };
}

// The separator belongs to the following chapter, but has no reading position itself.
{
  const { r, calls } = fixture();
  r.onReaderComicScrollIndexChanged(2, 3);
  assert.deepEqual(calls, [[1, 0]], 'next chapter is promoted while its separator is still visible');
  calls.length = 0;
  r.onReaderComicScrollIndexChanged(2, 2);
  assert.deepEqual(calls, [], 'a separator alone must not invent a chapter position');
  r.onReaderComicScrollIndexChanged(1, 3);
  assert.deepEqual(calls, [], 'the current chapter tail remains authoritative while still visible');
  r.onReaderComicScrollIndexChanged(100, 120);
  assert.deepEqual(calls, [], 'stale indexes outside the data source do not select a chapter');
}
for (const guard of ['quickJumpBusy', 'readerComicScrollRestoring']) {
  const { r, calls } = fixture(); r[guard] = true;
  r.onReaderComicScrollIndexChanged(2, 3); assert.deepEqual(calls, [], guard);
}
{
  const { r, calls } = fixture();
  r.readerPageVisible = false; r.onReaderComicScrollIndexChanged(2, 3);
  assert.deepEqual(calls, [], 'hidden route cannot change position');
  r.readerPageVisible = true; r.layoutReady = false; r.onReaderComicScrollIndexChanged(2, 3);
  assert.deepEqual(calls, [], 'loading placeholder cannot become the current chapter');
  r.layoutReady = true; r.onReaderComicScrollIndexChanged(2, 3);
  assert.deepEqual(calls, [[1, 0]], 'measured visible text can become current');
}

// Forward and backward chapter loads both reconcile a later position inside the same target chapter.
for (const [from, to, initialPage, visiblePage] of [[0, 1, 0, 2], [1, 0, 1, 0]]) {
  const { r, data, saves } = fixture(from);
  let release; r.loadGate = new Promise(resolve => { release = resolve; });
  const task = r.runReaderContinuousChapterCommit(to, initialPage);
  r.viewportListTop = data.offsetOf(to) + visiblePage;
  r.onReaderComicScrollIndexChanged(r.viewportListTop, r.viewportListTop);
  release(); await task;
  assert.equal(r.currentChapterIndex, to);
  assert.equal(r.currentPageIndex, visiblePage, 'load completion reconciles the latest local page');
  assert.equal(r.readerContinuousVisibleStart, visiblePage);
  assert.deepEqual(saves.at(-1), [to, visiblePage], 'save uses reconciled progress');
  r.updateReaderContinuousDisplayPosition();
  assert.equal(sandbox.Text.of(sandbox.Item.PAGE, r.getReaderInfoBarContext()),
    `${visiblePage + 1}/${r.contentPages.length}`, 'footer follows the same visible body');
}
{
  const { r, calls } = fixture();
  let release; r.loadGate = new Promise(resolve => { release = resolve; });
  const task = r.runReaderContinuousChapterCommit(1, 0);
  r.onReaderComicScrollIndexChanged(6, 7); // separator + chapter 2 page 0
  release(); await task;
  assert.deepEqual(calls, [[2, 0]], 'completion follows another chapter even when its separator is first');
}
{
  const { r } = fixture(); r.loadFails = true;
  await r.runReaderContinuousChapterCommit(1, 0);
  assert.equal(r.currentChapterIndex, 0); assert.equal(r.pendingRestorePageIndex, -1);
}

// Incomplete paged layout must never advertise its provisional one-page window as 100%.
{
  const { r } = fixture();
  r.isReaderNovelContinuousScrollModeActive = () => false;
  r.isCurrentReaderPaginationComplete = () => false;
  r.contentPages = ['first'];
  let context = r.getReaderInfoBarContext();
  assert.equal(context.pageCountPending, true);
  for (const item of [sandbox.Item.PAGE, sandbox.Item.PAGES_LEFT, sandbox.Item.CHAPTER_PERCENT, sandbox.Item.BOOK_PERCENT]) {
    assert.equal(sandbox.Text.of(item, context), '…');
  }
  assert.equal(sandbox.Text.chapterPercent(context), 0, 'progress bar cannot fill from a partial denominator');
  assert.equal(sandbox.Text.of(sandbox.Item.CHAPTER_PROGRESS, context), '1/3 章');
  r.contentPages = Array(10).fill('page'); r.isCurrentReaderPaginationComplete = () => true;
  context = r.getReaderInfoBarContext();
  assert.equal(sandbox.Text.of(sandbox.Item.PAGE, context), '1/10');
  assert.equal(sandbox.Text.of(sandbox.Item.CHAPTER_PERCENT, context), '10%');
  r.isReaderComicModeActive = () => true; r.readerComicTotalPageCount = () => 12;
  r.isCurrentReaderPaginationComplete = () => false;
  assert.equal(r.getReaderInfoBarContext().pageCountPending, false, 'comic pages retain their own total');
}
console.log('Reader progress sync: separators, asynchronous cross-chapter races, visible footer positions, guards and incomplete page totals passed.');
