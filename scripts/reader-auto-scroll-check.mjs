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
  'stopReaderAutoScroll', 'advanceReaderAutoScroll', 'shouldPauseReaderAutoScrollForPanel', 'waitReaderAutoScroll',
  'restoreReaderAutoScrollAnchor', 'scrollReaderContinuousToSourceOffset', 'onReaderAutoScrollBackground',
  'readerComicEffectiveMode', 'isReaderComicPagedMode', 'readerComicAutoScrollImagesReady',
  'isReaderNovelContinuousScrollModeActive', 'readerEffectivePageTurnMode',
  'cancelReaderAutoScrollTap', 'handleReaderAutoScrollTap', 'rememberContinuousReaderPointer',
  'cancelContinuousReaderSelectionTimer', 'shouldShowReaderAutoScrollCapsule',
  'shouldShowReaderSessionQuickActions', 'shouldShowTtsMiniPlayer', 'shouldShowGlobalTtsMiniPlayer',
  'readerAutoScrollCapsuleLeft', 'readerAutoScrollCapsuleTop',
  'clampTtsMiniPlayerPositionX', 'clampTtsMiniPlayerPositionY'];
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
  setTimeout: fn => { timers.set(++id, fn); return id; },
  clearTimeout: value => timers.delete(value),
  TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 },
  ReaderAutoScrollCapsule: { WIDTH: 184, HEIGHT: 46 },
  ReaderTtsCapsule: { WIDTH: 184, HEIGHT: 46 },
  ReaderComicMode: { WEBTOON: 'webtoon', isPaged: mode => ['ltr', 'rtl'].includes(mode) },
  HdsFeedback: { showToast() {} },
  ReaderTtsFloatingSession: { pause: async () => {}, isOwner: () => false },
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
    readerAutoScrollTapTimer: -1, readerAutoScrollTapAt: 0,
    readerContinuousSelectionTimerId: -1, readerContinuousSelectionMoved: false, readerTapSlop: 12,
    readerAutoScrollPositionX: -1, readerAutoScrollPositionY: -1,
    readerHoldingHandSide: 0, readerAutoScrollManuallyPositioned: false,
    pageViewWidth: 360, pageViewHeight: 720, navBarHeight: 24,
    readerPageVisible: true, readerInitialPageReady: true, readerPageTurnMode: 1,
    chapters: [{}, {}, {}], currentChapterIndex: 0, content: 'test novel', contentPages: ['test novel'],
    pendingRestorePageIndex: -1, readerTypographyRestoreOffset: -1, readerContinuousCommitChapter: -1,
    readerContinuousLastListStart: 0, readerContinuousLastListEnd: 0,
    distance: 0, reflows: [], isLoading: false, loadRequests: 0,
    atEnd: false, lastChapter: 0, failed: false, nativeTts: false,
    isReaderComicModeActive: () => false, hasReaderTextSelection: () => false,
    readerComicSettings: { defaultMode: 'webtoon' }, readerComicBookMode: '', readerComicZoomScale: 1,
    readerComicScrollRestoreSerial: 0,
    syncReaderComicPageDataSource() {}, scheduleReaderComicScrollRestore() {},
    getEffectiveReaderLineHeight: () => 30, getReaderStableReflowOffset: () => 480,
    readerContinuousV2FirstVisibleSourceOffset: () => 960,
    reflowReaderAutoScrollMode: value => p.reflows.push(value),
    setReaderTextSelectionActive() {}, clearQueuedReaderPageTurns() {}, stopReaderComicScreenScroll() {},
    cancelReaderComicPan() {}, hideReaderPanels() {}, cancelManualPageTurnTtsResume() {},
    applyReaderScreenTimeout() {}, scheduleReaderComicProgressSave() {}, flushReaderAutoScrollSpeed() {},
    updateTtsFloatingSession() {},
    shouldBlockReaderInteraction: () => false, readerSourceActionAtPoint: () => '',
    shortTaps: 0, selections: 0,
    handleContinuousReaderShortTap: () => { p.shortTaps++; p.showMenu = true; },
    selectReaderTextAtPoint: () => { p.selections++; },
    readerFloatingBarRight: () => 344, readerBottomMenuOverlayHeight: () => 120,
    getReaderTopSafePadding: () => 24,
    ttsReader: { isSpeaking: () => p.nativeTts, isPaused: () => false, pause: async () => {} },
    readerComicScroller: { isAtEnd: () => p.atEnd, scrollBy: (_x, y) => { p.distance += y; },
      currentOffset: () => ({ xOffset: 0, yOffset: p.distance }),
      scrollTo: ({ yOffset }) => { p.distance = yOffset; p.inertiaStops = (p.inertiaStops || 0) + 1; } },
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

p = fixture(); p.showMenu = true; frame(p); frame(p);
assert.equal(p.readerAutoScrollPaused, false, 'floating bars and capsule do not pause motion');
assert.equal(p.shouldShowReaderAutoScrollCapsule(), true);
assert.equal(p.distance, 0.16, 'content continues moving under floating controls');
p.showMenu = false; frame(p);
assert.equal(p.distance, 0.32, 'dismissing floating controls keeps scrolling');

for (const interrupt of ['showToc', 'showSettings', 'showLayoutElementSettings', 'showReaderCommentPanel',
  'showReaderAutoScrollSpeed', 'showTapZoneSettings', 'showChangeSourceDialog', 'showTxtCharsetDialog',
  'showReaderCacheDialog', 'showReaderChapterCacheDialog', 'showTtsQuickPlayer', 'showGlobalTtsQuickPlayer',
  'showGlobalTtsCatalog', 'globalTtsActive']) {
  p = fixture(); p[interrupt] = true; frame(p);
  assert.equal(p.readerAutoScrollPaused, true, `${interrupt} pauses motion`);
  assert.equal(p.distance, 0);
  p[interrupt] = false; p.showMenu = true; frame(p);
  assert.equal(p.readerAutoScrollPaused, true, `closing ${interrupt} requires explicit resume`);
  assert.equal(p.distance, 0);
}
for (const settingsTab of [0, 1, 2]) {
  p = fixture(); p.showSettings = true; p.settingsPanelTab = settingsTab; frame(p);
  assert.equal(p.readerAutoScrollPaused, true, 'reading, TTS and typography settings all pause');
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

p = fixture(); p.readerAutoScrollPaused = true; p.showReaderAutoScrollSpeed = true;
await p.startReaderAutoScroll();
assert.equal(p.showReaderAutoScrollSpeed, false, 'resume from speed panel closes the blocking sheet');
frame(p); frame(p);
assert.equal(p.readerAutoScrollPaused, false, 'speed-panel resume is not immediately paused again');
assert.equal(p.distance, 0.16);
p.stopReaderAutoScroll(false);

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

// Use the real touch handler so the first Down cannot silently pause a double tap.
function touch(p, type, x = 180, y = 300) {
  const point = { windowX: x, windowY: y };
  p.rememberContinuousReaderPointer({ type, changedTouches: [point], touches: type === 2 ? [] : [point] });
}
function tap(p, x = 180, y = 300) {
  touch(p, 0, x, y); now += 40; touch(p, 2, x, y);
}
function fireTimer(timerId) {
  const fn = timers.get(timerId);
  assert.ok(fn, 'expected pending timer');
  timers.delete(timerId);
  fn();
}
p = fixture();
tap(p);
assert.equal(p.readerAutoScrollPaused, false, 'first tap must not preemptively pause');
assert.equal(p.shortTaps, 0, 'first tap defers opening the menu');
now += 100; tap(p);
assert.equal(p.readerAutoScrollPaused, true, 'double tap pauses running scroll');
assert.equal(p.shortTaps, 0, 'double tap never opens the menu');
assert.equal(p.readerAutoScrollTapTimer, -1);
tap(p); now += 100; tap(p);
await new Promise(resolve => setImmediate(resolve));
assert.equal(p.readerAutoScrollPaused, false, 'double tap resumes paused scroll');
assert.equal(p.shortTaps, 0);
p.stopReaderAutoScroll(false);

p = fixture(); tap(p); now += 210; touch(p, 0); now += 105; touch(p, 2);
assert.equal(p.readerAutoScrollPaused, true, 'double-tap gap excludes the second press duration');
assert.equal(p.shortTaps, 0, 'second press must cancel the pending menu before its deadline');

p = fixture(); tap(p); now += 301; fireTimer(p.readerAutoScrollTapTimer);
assert.equal(p.shortTaps, 1, 'single tap still opens reader controls');
frame(p); frame(p);
assert.equal(p.readerAutoScrollPaused, false, 'single tap opens controls without pausing');
assert.equal(p.distance, 0.16, 'scrolling continues after the single-tap menu opens');
assert.equal(p.shouldShowReaderAutoScrollCapsule(), true);
for (const panel of ['showToc', 'showSettings', 'showTtsQuickPlayer', 'showGlobalTtsQuickPlayer',
  'showReaderAutoScrollSpeed']) {
  p[panel] = true;
  assert.equal(p.shouldShowReaderAutoScrollCapsule(), false, `${panel} hides the capsule`);
  p[panel] = false;
}
p.showMenu = false;
assert.equal(p.shouldShowReaderAutoScrollCapsule(), false, 'capsule follows bottom menu visibility');
p.showMenu = true; p.readerAutoScrollActive = false;
assert.equal(p.shouldShowReaderAutoScrollCapsule(), false, 'stopped sessions have no capsule');

p = fixture(); tap(p); now += 100; tap(p, 260, 300);
assert.equal(p.readerAutoScrollPaused, false, 'distant taps are not a double tap');
p.onReaderAutoScrollBackground();
assert.equal(p.readerAutoScrollTapTimer, -1, 'background cancels deferred single tap');
assert.equal(p.shortTaps, 0);

p = fixture(); tap(p); touch(p, 0); touch(p, 1, 180, 350); touch(p, 2, 180, 350);
assert.ok(p.inertiaStops > 0, 'touch down stops native inertia before a drag is recognized');
assert.equal(p.readerAutoScrollPaused, true, 'dragging still pauses');
assert.equal(p.readerAutoScrollTapTimer, -1, 'drag cancels pending tap');
assert.equal(p.shortTaps, 0, 'drag cannot open the menu');
p = fixture(); touch(p, 0); now += 420; fireTimer(p.readerContinuousSelectionTimerId); touch(p, 2);
assert.equal(p.readerAutoScrollPaused, true, 'long press pauses before selection');
assert.equal(p.selections, 1);
assert.equal(p.shortTaps, 0);
p = fixture(); tap(p); touch(p, 3);
assert.equal(p.readerAutoScrollTapTimer, -1, 'cancelled touch cannot become a delayed menu action');
p = fixture(); p.readerSourceActionAtPoint = () => 'source-action'; tap(p);
assert.equal(p.shortTaps, 1, 'source links retain immediate single-tap handling');
assert.equal(p.readerAutoScrollTapTimer, -1);

p = fixture();
assert.equal(p.readerAutoScrollCapsuleLeft(), 160);
assert.equal(p.readerAutoScrollCapsuleTop(), 546, 'default capsule clears the whole bottom menu');
p.readerUseTtsQuickAction = true; p.isTtsSpeaking = true; p.isTtsPaused = true;
assert.equal(p.readerAutoScrollCapsuleTop(), 546, 'hidden TTS session does not move the scroll capsule');
p.readerAutoScrollPositionX = 999; p.readerAutoScrollPositionY = 999;
assert.equal(p.readerAutoScrollCapsuleLeft(), 168, 'drag cannot leave right edge');
assert.equal(p.readerAutoScrollCapsuleTop(), 642, 'drag cannot enter system navigation area');
p.readerAutoScrollPositionX = 20; p.readerAutoScrollPositionY = 200;
assert.equal(p.readerAutoScrollCapsuleLeft(), 20);
assert.equal(p.readerAutoScrollCapsuleTop(), 200, 'user placement overrides default stacking');
assert.equal(p.clampTtsMiniPlayerPositionX(-99), 8);
assert.equal(p.clampTtsMiniPlayerPositionY(-99), 32);

// Both quick actions follow the same session rule, including paused local/background TTS.
for (const paused of [false, true]) {
  for (const ttsKind of ['none', 'local', 'native', 'global']) {
    p = fixture(); p.showMenu = true; p.readerAutoScrollPaused = paused;
    p.isTtsSpeaking = ttsKind === 'local'; p.nativeTts = ttsKind === 'native';
    p.globalTtsActive = ttsKind === 'global'; p.isTtsPaused = paused; p.globalTtsPaused = paused;
    assert.equal(p.shouldShowReaderSessionQuickActions(), false, 'scroll session hides both quick actions');
    assert.equal(p.shouldShowReaderAutoScrollCapsule(), true);
    assert.equal(p.shouldShowTtsMiniPlayer(), false, 'scroll capsule excludes local TTS capsule');
    assert.equal(p.shouldShowGlobalTtsMiniPlayer(), false, 'scroll capsule excludes background TTS capsule');
    p.stopReaderAutoScroll();
    assert.equal(p.readerAutoScrollActive, false, 'capsule close ends the session, not just pauses it');
    assert.equal(p.shouldShowReaderAutoScrollCapsule(), false);
    assert.equal(p.shouldShowReaderSessionQuickActions(), ttsKind === 'none',
      'close restores quick actions only when no TTS session remains');
    assert.equal(p.shouldShowTtsMiniPlayer(), ttsKind === 'local' || ttsKind === 'native');
    assert.equal(p.shouldShowGlobalTtsMiniPlayer(), ttsKind === 'global');
  }
}
assert.equal(timers.size, 0, 'gesture scenarios leave no pending timers');

// Comics use the same clock/session, but preserve image pages and the saved reading direction.
function comicFixture(mode = 'webtoon') {
  const p = fixture();
  p.isReaderComicModeActive = () => true;
  p.readerComicBookMode = mode;
  p.readerAutoScrollActive = false;
  p.currentPageIndex = 7;
  p.imageState = 1;
  p.readerComicRetryRegistry = { imageState: () => p.imageState };
  p.isReaderImageOnlyPage = () => true;
  p.readerComicPageDataSource.itemAt = () => ({ key: 'image', text: 'image', isPage: () => true });
  p.restoreRequests = 0;
  p.scheduleReaderComicScrollRestore = () => { p.restoreRequests++; };
  p.getReaderStableReflowOffset = () => { throw new Error('comics must not use novel offsets'); };
  p.readerContinuousV2FirstVisibleSourceOffset = p.getReaderStableReflowOffset;
  return p;
}
for (const mode of ['webtoon', 'ltr', 'rtl']) {
  p = comicFixture(mode);
  assert.equal(p.shouldShowReaderSessionQuickActions(), true);
  await p.startReaderAutoScroll();
  assert.equal(p.readerComicEffectiveMode(), 'webtoon');
  assert.equal(p.restoreRequests, mode === 'webtoon' ? 0 : 1);
  assert.equal(p.currentPageIndex, 7, 'temporary surface keeps the image page');
  frame(p); frame(p);
  assert.equal(p.distance, 0.192, '20 means one viewport per minute, independent of novel typography');
  p.readerComicZoomScale = 2;
  frame(p);
  assert.ok(Math.abs(p.distance - 0.288) < 1e-9, 'zoom keeps screen-space speed stable');
  p.showMenu = true;
  assert.equal(p.shouldShowReaderAutoScrollCapsule(), true);
  p.pauseReaderAutoScroll('已暂停');
  assert.equal(p.readerComicEffectiveMode(), 'webtoon', 'pause does not replace the surface');
  await p.startReaderAutoScroll();
  assert.equal(p.restoreRequests, mode === 'webtoon' ? 0 : 1, 'resume preserves intra-image position');
  p.stopReaderAutoScroll();
  assert.equal(p.readerComicEffectiveMode(), mode, 'close restores saved direction');
  assert.equal(p.currentPageIndex, 7);
  assert.deepEqual(p.reflows, [], 'comics never enter novel reflow');
}
p = comicFixture(); await p.startReaderAutoScroll();
p.imageState = 0;
frame(p); frame(p, 600);
assert.equal(p.distance, 0, 'undecoded visible images hold the viewport');
assert.equal(p.readerAutoScrollStatus, '等待图片');
p.imageState = 1; frame(p);
assert.equal(p.distance, 0.192, 'decoded image resumes without catching up');
p.imageState = -1; frame(p);
assert.equal(p.readerAutoScrollStatus, '图片加载失败，已暂停');
p.stopReaderAutoScroll();
p = comicFixture(); await p.startReaderAutoScroll();
p.atEnd = true; p.lastChapter = 2; p.readerComicPaginationParsing = true;
frame(p);
assert.equal(p.readerAutoScrollPaused, false, 'partial final chapter is not book end');
p.readerComicPaginationParsing = false; frame(p);
assert.equal(p.readerAutoScrollStatus, '已到书末');
p.stopReaderAutoScroll();
p = comicFixture(); await p.startReaderAutoScroll(); p.atEnd = true;
frame(p);
assert.equal(p.loadRequests, 1, 'comic boundaries also request the next chapter');
p.onReaderAutoScrollBackground();
assert.equal(p.readerAutoScrollPaused, true);
p.stopReaderAutoScroll();
assert.equal(timers.size, 0, 'comic sessions release timers');

// Exercise the comic view's actual gesture dispatch and mounted image status registry.
const comicView = readEtsModule('components/reader/ReaderComicView.ets');
const registryStart = comicView.indexOf('export class ReaderComicRetryRegistry');
const registryEnd = comicView.indexOf('\n}', registryStart) + 2;
const comicMethod = name => {
  const start = comicView.search(new RegExp(`^  private ${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return comicView.slice(start, comicView.indexOf('\n  }', start) + 4);
};
vm.runInContext(compile(comicView.slice(registryStart, registryEnd)) + compile(`
class ComicGestures {
${['handleDoubleTap', 'handleLongPress', 'handlePinchStart', 'handlePanStart'].map(comicMethod).join('\n')}
}
globalThis.ComicGestures = ComicGestures;
globalThis.ImageRegistry = ReaderComicRetryRegistry;`), sandbox);
const registry = new sandbox.ImageRegistry();
let decodedState = 0;
const firstState = () => decodedState;
registry.registerState('page', firstState);
assert.equal(registry.imageState('page'), 0);
decodedState = 1;
assert.equal(registry.imageState('page'), 1, 'decode completion is observed without list reload');
registry.registerState('page', () => -1);
registry.unregisterState('page', firstState);
assert.equal(registry.imageState('page'), -1, 'old unmount cannot erase a newly mounted image');
registry.registerState('page', firstState);
registry.unregisterState('page', firstState);
assert.equal(registry.imageState('page'), 0, 'unmounted images cannot count as ready');
const gestures = new sandbox.ComicGestures();
let toggles = 0, pauses = 0, zoomResets = 0;
Object.assign(gestures, {
  autoScrollActive: true, touchDragged: false, pinching: false,
  onAutoScrollToggle: () => toggles++, onManualInteraction: () => pauses++,
  zoomed: () => true, resetZoom: () => zoomResets++, onPanStart() {},
  tapPoint: () => [0, 0], centerX: () => 0, centerY: () => 0,
  zoomScale: 1, zoomX: 0, zoomY: 0, scroller: { getItemIndex: () => -1 },
  dataSource: { itemAt: () => null },
});
gestures.handleDoubleTap({});
assert.equal(toggles, 1);
assert.equal(zoomResets, 0, 'auto-scroll double tap never zooms');
gestures.touchDragged = true; gestures.handleDoubleTap({});
assert.equal(toggles, 1, 'drag cannot trigger resume');
gestures.touchDragged = false; gestures.autoScrollActive = false; gestures.handleDoubleTap({});
assert.equal(zoomResets, 1, 'normal zoom returns when the session ends');
gestures.handleLongPress({}); gestures.handlePanStart();
gestures.handlePinchStart({ pinchCenterX: 0, pinchCenterY: 0 });
assert.equal(pauses, 3, 'long press, zoomed pan and pinch all pause');
assert.match(comicView, /interactionLayer\(this.doubleTapZoom \|\| this.autoScrollActive\)/,
  'auto-scroll double tap remains enabled when zoom preference is off');
console.log('PASS reader auto-scroll: novel/comic sessions, screen speed, image readiness, mode restore, lifecycle, chapter boundaries and gestures');
