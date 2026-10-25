// Exercise the actual ArkTS clock, persistence and reader session methods with platform doubles.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''));
const reader = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = reader.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  const end = reader.indexOf('\n  }', start);
  return reader.slice(start, end + 4);
}
const names = ['startReaderAutoScroll', 'toggleReaderAutoScroll', 'pauseReaderAutoScroll',
  'stopReaderAutoScroll', 'advanceReaderAutoScroll', 'waitReaderAutoScroll',
  'restoreReaderAutoScrollAnchor', 'onReaderAutoScrollBackground',
  'isReaderNovelContinuousScrollModeActive', 'readerEffectivePageTurnMode'];
let now = 1000;
let id = 0;
const timers = new Map();
const persisted = [];
let storedSpeed = 20;
const sandbox = vm.createContext({
  console, Date: { now: () => now },
  getContext: () => ({}), px2vp: n => n / 2,
  LengthMetrics: { vp: n => n }, ScrollAlign: { START: 0 },
  setInterval: fn => { timers.set(++id, fn); return id; },
  clearInterval: value => timers.delete(value),
  HdsFeedback: { showToast() {} },
  ReaderTtsFloatingSession: { pause: async () => {} },
  preferences: { getPreferences: async () => ({
    get: async () => storedSpeed,
    put: async (_key, value) => { await Promise.resolve(); storedSpeed = value; persisted.push(value); },
    flush: async () => {},
  }) },
});
vm.runInContext(compile(readEtsModule('core/reader/ReaderAutoScrollClock.ets')) +
  '\nglobalThis.Clock = ReaderAutoScrollClock;', sandbox);
vm.runInContext(compile(readEtsModule('utils/ReaderAutoScrollSettingsStore.ets')) +
  '\nglobalThis.Store = ReaderAutoScrollSettingsStore;', sandbox);
vm.runInContext(compile(`class ReaderSession {\n${names.map(method).join('\n')}\n}
  globalThis.ReaderSession = ReaderSession;`), sandbox);

const { Clock, Store, ReaderSession } = sandbox;
const clock = new Clock();
let moved = clock.advance(0, 20, 30, true);
for (let t = 16; t <= 60000; t += 16) moved += clock.advance(t, 20, 30, true);
assert.ok(Math.abs(moved - 600) < 0.001, '20 lines/min × 30 vp = 600 vp over one minute');
assert.equal(clock.advance(120000, 20, 30, true), 0.64, 'no catch-up jump after a suspended frame');
assert.equal(clock.advance(120016, 20, 30, false), 0, 'loading never scrolls');
assert.equal(clock.advance(120032, 40, 60, true), 0.64, 'new speed and font size apply on next frame');
clock.reset();
assert.equal(clock.advance(130000, 60, 30, true), 0, 'resume starts a fresh clock');
assert.equal(clock.advance(129000, 60, 30, true), 0, 'clock moving backwards cannot reverse text');
assert.deepEqual([NaN, 0, 7, 100].map(Clock.normalizeSpeed), [20, 6, 8, 60]);
await Promise.all([Store.save({}, 12), Store.save({}, 32), Store.save({}, 60)]);
assert.deepEqual(persisted, [12, 32, 60], 'concurrent saves stay ordered');
assert.equal(await Store.load({}), 60, 'reopen gets latest saved speed');
storedSpeed = NaN;
assert.equal(await Store.load({}), 20, 'invalid stored speed falls back');
storedSpeed = 20;

function fixture() {
  const p = new ReaderSession();
  Object.assign(p, {
    readerAutoScrollActive: true, readerAutoScrollPaused: false, readerAutoScrollSpeed: 20,
    readerAutoScrollStatus: '', readerAutoScrollRequest: 0, readerAutoScrollStarting: false,
    readerAutoScrollSettingsLoaded: true, readerAutoScrollAnchor: -1,
    readerAutoScrollWaitingSince: 0, readerAutoScrollTimer: -1, readerAutoScrollClock: new Clock(),
    readerPageVisible: true, readerInitialPageReady: true, readerPageTurnMode: 1,
    chapters: [{}, {}, {}], currentChapterIndex: 0, content: 'test novel', contentPages: ['test novel'],
    pendingRestorePageIndex: -1, readerTypographyRestoreOffset: -1, readerContinuousCommitChapter: -1,
    readerContinuousLastListStart: 0, readerContinuousLastListEnd: 0,
    distance: 0, reflows: [], isLoading: false, loadRequests: 0,
    atEnd: false, lastChapter: 0, failed: false, nativeTts: false,
    isReaderComicModeActive: () => false, hasReaderTextSelection: () => false,
    getEffectiveReaderLineHeight: () => 30, getReaderStableReflowOffset: () => 480,
    readerContinuousV2FirstVisibleSourceOffset: () => 960,
    reflowReaderAutoScrollMode: value => p.reflows.push(value),
    setReaderTextSelectionActive() {}, clearQueuedReaderPageTurns() {}, stopReaderComicScreenScroll() {},
    cancelReaderComicPan() {}, hideReaderPanels() {}, cancelManualPageTurnTtsResume() {},
    applyReaderScreenTimeout() {}, scheduleReaderComicProgressSave() {}, flushReaderAutoScrollSpeed() {},
    updateTtsFloatingSession() {},
    ttsReader: { isSpeaking: () => p.nativeTts, isPaused: () => false, pause: async () => {} },
    readerComicScroller: { isAtEnd: () => p.atEnd, scrollBy: (_x, y) => { p.distance += y; } },
    readerComicPageDataSource: { lastChapter: () => p.lastChapter, totalCount: () => 2,
      itemAt: () => ({ failed: p.failed }) },
    ensureReaderContinuousNeighbors: () => { p.loadRequests++; },
  });
  return p;
}
function frame(p, ms = 16) { now += ms; p.advanceReaderAutoScroll(); }

let p = fixture();
frame(p); frame(p);
assert.equal(p.distance, 0.16, 'continuous native scrolling moves forward');
p.isLoading = true; frame(p, 5000);
assert.equal(p.distance, 0.16, 'chapter commit/loading holds position');
p.isLoading = false; frame(p);
assert.equal(p.distance, 0.32, 'load completion continues without catch-up');
p.onReaderAutoScrollBackground(); frame(p, 5000);
assert.equal(p.distance, 0.32);
assert.equal(p.readerAutoScrollPaused, true, 'background must require explicit resume');

for (const interrupt of ['showMenu', 'showToc', 'showSettings', 'showReaderCommentPanel', 'globalTtsActive']) {
  p = fixture(); p[interrupt] = true; frame(p);
  assert.equal(p.readerAutoScrollPaused, true, `${interrupt} pauses motion`);
  assert.equal(p.distance, 0);
}
p = fixture(); p.atEnd = true; frame(p);
assert.equal(p.loadRequests, 1, 'chapter boundary uses existing neighbor loader');
assert.equal(p.readerAutoScrollPaused, false, 'loading next chapter is not end of book');
frame(p, 30001);
assert.equal(p.readerAutoScrollPaused, true, 'stalled source pauses after bounded wait');
p = fixture(); p.atEnd = true; p.failed = true; frame(p);
assert.equal(p.readerAutoScrollPaused, true);
assert.equal(p.loadRequests, 0, 'failed source is not hammered by frame timer');
p = fixture(); p.atEnd = true; p.lastChapter = 2; frame(p);
assert.equal(p.readerAutoScrollStatus, '已到书末');

p = fixture(); p.readerAutoScrollActive = false;
await p.startReaderAutoScroll();
assert.deepEqual(p.reflows, [480], 'start preserves current source offset');
assert.equal(p.readerPageTurnMode, 1, 'temporary scroll mode never rewrites preference');
assert.equal(p.readerEffectivePageTurnMode(), 3);
assert.equal(p.isReaderNovelContinuousScrollModeActive(), true);
assert.ok(timers.has(p.readerAutoScrollTimer));
p.pauseReaderAutoScroll('已暂停');
assert.equal(timers.size, 0, 'pause releases frame timer');
p.readerAutoScrollAnchor = -1;
p.stopReaderAutoScroll();
assert.deepEqual(p.reflows, [480, 960], 'exit restores original mode at newly reached position');
assert.equal(p.readerEffectivePageTurnMode(), 1);
assert.equal(p.isReaderNovelContinuousScrollModeActive(), false);

p = fixture(); p.readerAutoScrollActive = false;
const pendingStart = p.startReaderAutoScroll();
p.onReaderAutoScrollBackground();
await pendingStart;
assert.equal(p.readerAutoScrollActive, false, 'late async start cannot restart background session');
assert.equal(timers.size, 0);
p = fixture(); p.readerAutoScrollActive = false; p.nativeTts = true;
await p.startReaderAutoScroll();
assert.equal(p.readerAutoScrollActive, false, 'failed TTS pause cannot run both readers');
p = fixture(); p.readerPageTurnMode = 3; p.stopReaderAutoScroll();
assert.deepEqual(p.reflows, [], 'native continuous mode exits without changing scroll position');
p = fixture(); p.stopReaderAutoScroll(false);
assert.deepEqual(p.reflows, [], 'destroyed page does not rebuild native renderer');

p = fixture(); p.readerAutoScrollAnchor = 480;
p.findPageIndexByOffset = () => 2;
p.readerContinuousV2Layout = () => ({ identity: 'layout', fragments: [{ displayStart: 0,
  paragraphY: 20, paragraph: { getLineMetrics: () => [
    { startIndex: 0, topHeight: 0 }, { startIndex: 80, topHeight: 60 },
    { startIndex: 160, topHeight: 120 }] } }] });
p.readerContinuousV2Documents = new Map([['layout', { displayOffsetForSource: n => n }]]);
p.readerContinuousV2Sources = new Map([['layout', 400]]);
p.readerContinuousListIndex = index => index + 1;
let anchor;
p.readerComicScroller.scrollToIndex = (...args) => { anchor = args; };
assert.equal(p.restoreReaderAutoScrollAnchor(), true);
assert.equal(anchor[0], 3);
assert.equal(anchor[3].extraOffset, 40, 'source offset restores the exact line within a multi-screen chunk');
assert.equal(p.readerAutoScrollAnchor, -1);
console.log('PASS reader auto-scroll: clock, ordered persistence, lifecycle, TTS exclusion, chapter boundaries and position restore');
