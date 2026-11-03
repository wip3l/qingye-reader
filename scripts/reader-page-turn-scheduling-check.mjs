import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function method(name) {
  const match = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const timers = [];
const context = vm.createContext({ console, Date, setTimeout: fn => { timers.push(fn); return timers.length; },
  READER_INTERACTIVE_PAGINATION_BATCH_DELAY_MS: 56, READER_PAGINATION_BATCH_DELAY_MS: 64,
  READER_PAGINATION_BUSY_RETRY_DELAY_MS: 48, ReaderActionMarker: { has: () => false },
  CooperativeScheduler: { SLOW_OPERATION_MS: 16 } });
const names = ['scheduleReaderPaginationCompletion', 'getLocalPageTurnTargetPageIndex',
  'canTurnPage', 'isForwardChapterTurnWaitingForPagination', 'runTapPageTurn', 'runSlidePageTurn',
  'runNoAnimationPageTurn', 'cancelManualReaderTurn', 'publishCurrentReaderPagination',
  'currentReaderV2ChapterSurfaceKeys'];
const Reader = vm.runInContext(stripTypeScriptTypes(`class Reader { ${names.map(method).join('\n')} }; Reader`,
  { mode: 'strip' }), context);
function harness() {
  const result = { source: '正文', pages: ['first'], ends: [1], complete: false, v2Session: {} };
  const reader = new Reader();
  Object.assign(reader, { currentChapterIndex: 0, currentPageIndex: 0, chapters: [{}],
    contentPages: ['first'], readerPageVisible: true, readerInitialPageReady: true,
    readerPaginationWorkSerial: 0, readerPaginationScheduledResult: null, readerPaginationScheduledSerial: -1,
    readerPaginationRequiredPageCount: 4, readerPaginationCache: new Map([['key', result]]),
    pendingRestorePageIndex: -1, readerTypographyRestoreOffset: -1,
    isPageTurning: false, readerPanActive: false, readerTouchActive: false, pageSlideDirection: 0,
    pageTurnAnimating: false, readerRelayoutRepaintPending: false,
    pageTurnQueue: { hasPendingForward: () => true },
    batches: 0, published: 0, resumed: 0, persisted: 0,
    isReaderImageOnlySource: () => false, isReaderPaginationInteractionBusy: () => true,
    getReaderPageTurnStep: () => 1, armReaderRestoreWatchdog() {},
    updateReaderComicPaginationProgress() {}, isCurrentReaderPaginationComplete: () => result.complete,
    appendReaderPaginationBatch: async () => { reader.batches++; result.pages.push('second'); result.ends.push(2); },
    publishCurrentReaderPagination: () => { reader.published++; reader.contentPages = result.pages.slice(); },
    persistReaderPagination: () => { reader.persisted++; }, runQueuedPageTurnLater: () => { reader.resumed++; } });
  return { reader, result };
}

const first = harness();
first.reader.scheduleReaderPaginationCompletion(0, 'key', first.result);
first.reader.scheduleReaderPaginationCompletion(0, 'key', first.result);
assert.equal(timers.length, 1, 'repeated readiness checks do not restart the same worker');
await timers.shift()();
assert.equal(first.reader.batches, 1, 'native async preparation is not starved by interaction-idle delay');
assert.equal(first.reader.published, 1); assert.equal(first.reader.resumed, 1);
timers.length = 0;

const stale = harness();
let release;
stale.reader.appendReaderPaginationBatch = () => new Promise(resolve => { release = resolve; });
stale.reader.scheduleReaderPaginationCompletion(0, 'key', stale.result);
const work = timers.shift()();
stale.reader.readerPaginationWorkSerial++;
release(); await work;
assert.equal(stale.reader.published, 0, 'stale async completion cannot publish a new page');
assert.equal(timers.length, 0, 'stale work cannot reschedule itself');

const moving = harness();
moving.reader.isPageTurning = true;
moving.reader.appendReaderPaginationBatch = async () => { moving.result.complete = true; moving.result.pages.push('second'); };
moving.reader.scheduleReaderPaginationCompletion(0, 'key', moving.result);
await timers.shift()();
assert.equal(moving.reader.published, 0, 'background completion cannot replace a moving surface');
moving.reader.isPageTurning = false;
await timers.shift()();
assert.equal(moving.reader.published, 1); assert.equal(moving.reader.persisted, 1);
timers.length = 0;

const query = harness();
query.reader.ensureCurrentReaderPaginationAhead = () => { throw new Error('readiness query performed work'); };
assert.equal(query.reader.getLocalPageTurnTargetPageIndex(1), -1);
assert.equal(query.reader.canTurnPage(1), false);
assert.equal(query.reader.isForwardChapterTurnWaitingForPagination(), true,
  'missing pages in the final chapter are queued too');

const hidden = harness();
hidden.reader.readerPageVisible = false;
hidden.reader.scheduleReaderPaginationCompletion(0, 'key', hidden.result);
await timers.shift()();
assert.equal(hidden.reader.readerPaginationScheduledResult, null, 'an inactive owner is released');
hidden.reader.readerPageVisible = true;
hidden.reader.scheduleReaderPaginationCompletion(0, 'key', hidden.result);
assert.equal(timers.length, 1, 'foreground can restart an aborted initial worker');
timers.length = 0;

for (const operation of ['runTapPageTurn', 'runSlidePageTurn']) {
  const reader = new Reader();
  let finishMotion, valid = true, commits = 0;
  Object.assign(reader, { getPageTurnDistance: () => 100, getPageSlideAxisOffset: () => 0,
    prepareSlidePageTurn() {}, capturePageTurnCommitTarget: () => ({ pageIndex: 1 }),
    usesReaderPageCurlCanvas: () => true,
    completeSimulationPageTurnMotion: () => new Promise(resolve => { finishMotion = resolve; }),
    applyPageTurn: async () => { commits++; }, finishAnimatedPageTurn: async () => { commits++; } });
  const pending = operation === 'runTapPageTurn' ? reader.runTapPageTurn(1, () => valid) :
    reader.runSlidePageTurn(1, false, 0, () => valid);
  valid = false; finishMotion(); await pending;
  assert.equal(commits, 0, `${operation}: hide/reflow cannot commit a stale animation`);
}
const handoff = new Reader();
Object.assign(handoff, { currentChapterIndex: 1, currentPageIndex: 0, pagedContentText: '正文',
  contentPages: ['measured'], contentPageStarts: [0], contentPageEnds: [2],
  readerInitialPageReady: true, displayPageChapterIndex: 1, pendingRestorePageIndex: -1,
  readerTypographyRestoreOffset: -1, readerRelayoutRepaintPending: false,
  currentPageText: '正在加载章节内容...', displayPageText: '正在加载章节内容...',
  isLandscapeDoublePageActive: () => false, restorePendingPageIndex() {},
  setCurrentPageText(text) { this.currentPageText = text; this.displayPageText = text; },
  restoreReaderTypographyOffsetIfAvailable: () => false, finishReaderInitialOpening() {},
  isReaderContinuousScrollSurfaceActive: () => false, scheduleTtsFocusSyncAfterPagination() {} });
handoff.publishCurrentReaderPagination({ source: '正文', pages: ['measured'], starts: [0], ends: [2], complete: true });
assert.equal(handoff.currentPageText, 'measured', 'a ready cross-chapter counter must not retain the loading leaf');
assert.equal(handoff.displayPageText, 'measured');
let nativePage = null;
Object.assign(handoff, { readerV2SurfaceGeneration: 0, readerV2Page: () => nativePage });
const pendingHost = handoff.currentReaderV2ChapterSurfaceKeys(1)[0];
nativePage = {};
const nativeHost = handoff.currentReaderV2ChapterSurfaceKeys(2)[0];
assert.notEqual(nativeHost, pendingHost, 'the native page must replace the retained loading branch');
assert.equal(handoff.currentReaderV2ChapterSurfaceKeys(3)[0], nativeHost,
  'later render publications preserve the measured native host');
console.log('PASS: single async pagination owner, starvation avoidance, stale-work rejection, atomic publication, chapter text handoff and pure page queries');
