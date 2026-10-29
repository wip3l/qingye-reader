// Execute reader display metrics with deterministic native pagination and viewport doubles.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const reader = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = reader.search(new RegExp(`^  ${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return reader.slice(start, reader.indexOf('\n  }', start) + 4);
}
let now = 1000, timerId = 0, measurements = 0;
const timers = new Map();
const sandbox = vm.createContext({
  console, Date: { now: () => now },
  setTimeout: fn => { timers.set(++timerId, fn); return timerId; },
  clearTimeout: id => timers.delete(id),
  READER_DOUBLE_PAGE_DIVIDER_WIDTH: 1,
  ReaderV2DocumentParser: { parse: source => ({ source }) },
  ReaderV2Paginator: {
    start: (document, snapshot) => ({ document, snapshot, pageSet: { pages: [], complete: false } }),
    appendPages: (session, count) => {
      measurements++;
      assert.equal(count, 1, 'counting yields after one screen');
      const pages = session.pageSet.pages;
      pages.push({ sourceStart: pages.length * session.snapshot.capacity });
      session.pageSet.complete = pages.length * session.snapshot.capacity >= session.document.source.length;
    },
  },
});
const names = ['cancelReaderContinuousMetricsTimers', 'refreshReaderContinuousPageMetrics',
  'scheduleReaderContinuousMetricsBatch', 'runReaderContinuousMetricsBatch',
  'scheduleReaderContinuousPositionUpdate', 'updateReaderContinuousDisplayPosition',
  'readerContinuousV2ChapterEndVisible', 'readerContinuousV2FirstVisibleSourceOffset',
  'getReaderInfoBarContext', 'getProgressText', 'ttsQuickProgress',
  'getReaderPageColumnWidth'];
vm.runInContext(stripTypeScriptTypes(
  readEtsModule('core/reader/ReaderPageOffsets.ts').replace(/^export /gm, '') + '\n' +
  readEtsModule('core/reader/ReaderInfoBarModel.ts').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '') +
  `\nclass Reader { ${names.map(method).join('\n')} }\n` +
  'globalThis.Reader = Reader; globalThis.Text = ReaderInfoBarText; globalThis.Item = ReaderInfoItem;'), sandbox);
function tick() {
  const jobs = [...timers.values()];
  timers.clear();
  now += 80;
  for (const job of jobs) job();
}
function settle() {
  for (let i = 0; timers.size && i < 50; i++) tick();
  assert.equal(timers.size, 0, 'work terminates');
}
const p = new sandbox.Reader();
Object.assign(p, {
  readerContinuousMetricsTimer: -1, readerContinuousPositionTimer: -1,
  readerContinuousMetricsSource: '', readerContinuousMetricsChapter: -1,
  readerContinuousMetricsSnapshot: null, readerContinuousMetricsSession: null,
  readerContinuousMetricsStarts: [], readerContinuousMetricsEnds: [],
  readerContinuousDisplayPageCount: 0, readerContinuousDisplayPageIndex: 0,
  readerContinuousDisplayProgress: 0, readerContinuousPointerDown: false,
  readerContinuousLastScrollAt: 0, readerAutoScrollActive: false,
  readerPageVisible: true, currentChapterIndex: 0, pendingRestorePageIndex: -1,
  readerComicScrollRestoring: false, pagedContentText: '字'.repeat(7200),
  contentPages: ['chunk-1', 'chunk-2', 'chunk-3', 'chunk-4'], currentPageIndex: 0,
  chapters: [{}, {}], readerContinuousVisibleEnd: 0,
  isReaderNovelContinuousScrollModeActive: () => true, isReaderComicModeActive: () => false,
  hasPagedReaderArea: () => true, buildReaderV2Snapshot: (continuous, metrics) => {
    assert.equal(continuous, false); assert.equal(metrics, true);
    return { identity: 'font-20', capacity: 900 };
  },
  buildReaderV2RegexStyles: () => [], readerV2HeadingHints: () => [],
  getChapterTitle: () => '测试章', clampChapterIndex: index => index,
  isLandscapeDoublePageActive: () => false,
  getPageStartOffset: index => index * 1800,
  readerContinuousV2FirstVisibleSourceOffset: () => 0,
  readerContinuousV2ViewportPx: () => [0, 600],
  readerContinuousV2ItemId: index => `chunk-${index}`,
  getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: () =>
    ({ windowOffset: { y: -200 }, size: { height: 1600 } }) }) }),
});

p.refreshReaderContinuousPageMetrics();
assert.equal(measurements, 0, 'no native layout in publication/gesture callback');
assert.equal(sandbox.Text.of(sandbox.Item.PAGE, p.getReaderInfoBarContext()), '…');
assert.equal(sandbox.Text.of(sandbox.Item.PAGES_LEFT, p.getReaderInfoBarContext()), '…');
tick();
assert.equal(p.readerContinuousDisplayPageCount, 0, 'partial counts are not published as a total');
settle();
assert.equal(p.readerContinuousDisplayPageCount, 8, 'four chunks represent eight screen pages');
assert.equal(p.getProgressText(), '1/2 · 1/8');
assert.equal(p.contentPages.length, 4, 'counting never replaces the scroll chunks');
assert.equal(p.readerContinuousMetricsSession, null, 'native page layouts released after completion');

p.readerContinuousV2FirstVisibleSourceOffset = () => 1000;
p.scheduleReaderContinuousPositionUpdate(); settle();
assert.equal(p.currentPageIndex, 0, 'still in the same first chunk');
assert.equal(p.readerContinuousDisplayPageIndex, 1, 'display page advances inside a chunk');
assert.equal(p.getProgressText(), '1/2 · 2/8');
assert.ok(Math.abs(p.ttsQuickProgress() - 1000 / 7200 * 50) < 1e-8);
assert.equal(sandbox.Text.of(sandbox.Item.PAGES_LEFT, p.getReaderInfoBarContext()), '剩余 6 页');
p.readerContinuousV2FirstVisibleSourceOffset = () => 0;
p.scheduleReaderContinuousPositionUpdate(); settle();
assert.equal(p.readerContinuousDisplayPageIndex, 0, 'reverse scrolling restores earlier display pages');

// Last chunk starts before the last screen. Restoring it must not immediately report 100%.
p.currentPageIndex = 3; p.readerContinuousVisibleEnd = 3; p.readerContinuousReachedEnd = true;
p.readerContinuousV2FirstVisibleSourceOffset = () => 5400;
p.updateReaderContinuousDisplayPosition();
assert.equal(p.readerContinuousDisplayPageIndex, 6);
assert.equal(p.readerContinuousDisplayProgress, 0.75);
p.getUIContext = () => ({ getComponentUtils: () => ({ getRectangleById: () =>
  ({ windowOffset: { y: -1000 }, size: { height: 1600 } }) }) });
p.updateReaderContinuousDisplayPosition();
assert.equal(p.readerContinuousDisplayPageIndex, 7);
assert.equal(p.readerContinuousDisplayProgress, 1);

// Typography invalidates counting. While held/scrolling, no native measurement competes for a frame.
p.buildReaderV2Snapshot = () => ({ identity: 'font-30', capacity: 600 });
p.readerContinuousPointerDown = true;
p.refreshReaderContinuousPageMetrics();
const before = measurements;
tick(); tick();
assert.equal(measurements, before);
p.readerContinuousPointerDown = false;
p.readerContinuousLastScrollAt = now;
tick(); assert.equal(measurements, before, 'inertia gets priority too');
settle();
assert.equal(p.readerContinuousDisplayPageCount, 12);

// A newly promoted chapter discards pending work from the old one; a hidden page does no layout.
p.currentChapterIndex = 1; p.pagedContentText = '新'.repeat(1200);
p.refreshReaderContinuousPageMetrics(); tick();
assert.equal(p.readerContinuousDisplayPageCount, 0);
p.readerPageVisible = false; p.cancelReaderContinuousMetricsTimers();
const hiddenMeasurements = measurements; tick();
assert.equal(measurements, hiddenMeasurements);
p.readerPageVisible = true; p.refreshReaderContinuousPageMetrics(); settle();
assert.equal(p.readerContinuousDisplayPageCount, 2);
p.currentChapterIndex = 0; p.pagedContentText = '换'.repeat(6000);
p.refreshReaderContinuousPageMetrics(); tick();
p.currentChapterIndex = 1; p.pagedContentText = '另'.repeat(600);
p.refreshReaderContinuousPageMetrics(); settle();
assert.equal(p.readerContinuousDisplayPageCount, 1, 'no stale chapter count can publish');

p.readerLandscapeDoublePage = true; p.pageViewWidth = 1200; p.pageViewHeight = 800;
assert.equal(p.getReaderPageColumnWidth(), 1200, 'scroll surface remains a full-width column');
assert.equal(p.getReaderPageColumnWidth(true), 599.5, 'statistics use paged landscape leaf geometry');
p.isReaderNovelContinuousScrollModeActive = () => false;
p.refreshReaderContinuousPageMetrics();
assert.equal(timers.size, 0);
assert.equal(p.readerContinuousMetricsStarts.length, 0);
assert.equal(p.getReaderInfoBarContext().pageCount, 4, 'paged/comic path retains its own page source');
assert.equal(p.getReaderInfoBarContext().pageCountPending, false);

// Native fragments always have an imageRect, including text: only real image fragments may use it.
const locator = new sandbox.Reader();
let viewportTop = -10;
Object.assign(locator, {
  contentPages: ['text-and-image'], readerContinuousVisibleStart: 0, readerContinuousVisibleEnd: 0,
  readerContinuousV2ViewportPx: () => [viewportTop, 600], readerContinuousV2ItemId: () => 'item',
  getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: () =>
    ({ size: { height: 1000 }, windowOffset: { y: 0 } }) }) }),
  readerContinuousV2Layout: () => ({ identity: 'layout', fragments: [
    { imageSource: '', imageRect: { bottom: 0 }, paragraphY: 0, displayStart: 0,
      paragraph: { getLineMetrics: () => [{ topHeight: 0, startIndex: 5 }, { topHeight: 20, startIndex: 20 }] } },
    { imageSource: 'image.jpg', imageRect: { bottom: 300 }, displayStart: 40, paragraph: null },
  ] }),
  readerContinuousV2Documents: new Map([['layout', { sourceOffsetForDisplay: offset => offset }]]),
  readerContinuousV2Sources: new Map([['layout', 100]]),
});
assert.equal(locator.readerContinuousV2FirstVisibleSourceOffset(), 105);
viewportTop = 10;
assert.equal(locator.readerContinuousV2FirstVisibleSourceOffset(), 120, 'text advances by visible line');
viewportTop = 100;
assert.equal(locator.readerContinuousV2FirstVisibleSourceOffset(), 140, 'visible illustration maps to its source');

assert.match(reader, /\.onDidScroll\(\(\) => \{[\s\S]*?scheduleReaderContinuousPositionUpdate\(\)/);
console.log('Reader continuous page metrics: independent counts, visible offsets, end geometry, pending state, font/chapter changes, lifecycle and gesture priority passed.');
