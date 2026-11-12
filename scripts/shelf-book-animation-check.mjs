import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = path => fs.readFileSync(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const coverOpeningSource = read('components/reader/ReaderShelfCoverOpening.ets');
const constants = [
  ...coverOpeningSource.split('\n').filter(line => line.startsWith('export const ')),
  ...[...coverOpeningSource.matchAll(/^export function [\s\S]*?\n}/gm)].map(match => match[0])
].join('\n').replaceAll('export ', '');
let now = 1000, sequence = 0;
const timers = new Map(), storage = new Map();
const context = vm.createContext({
  Date: { now: () => now }, console,
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Curve: { Friction: 'friction', EaseInOut: 'easeInOut' },
  ReaderTtsFloatingSession: { isActive: () => false }, SHELF_UPDATE_BADGE_VARIABLE: 'shelfUpdateBadge',
  setTimeout: (callback, delay) => { timers.set(++sequence, { callback, at: now + delay }); return sequence; },
  clearTimeout: id => timers.delete(id)
});
vm.runInContext(stripTypeScriptTypes(constants), context);
assert.equal(context.shelfCoverCropAspect({ cropImage: true, boundsWidth: 100, boundsHeight: 140 }), 100 / 140,
  'cropped shelf covers keep their aspect while the page shrinks onto them');
assert.equal(context.shelfCoverCropAspect({ cropImage: false, boundsWidth: 100, boundsHeight: 140 }), 0,
  'stretched shelf covers stay stretched');
function hostFor(source, names) {
  return vm.runInContext(stripTypeScriptTypes(`({${names.map(name => method(source, name)).join(',')}})`), context);
}
function advance(ms) {
  now += ms;
  for (const [id, timer] of [...timers]) {
    if (timer.at <= now) { timers.delete(id); timer.callback(); }
  }
}

for (const page of ['ReadBook', 'PdfReadBook']) {
  const source = read(`pages/${page}.ets`);
  const host = hostFor(source, ['closeShelfCover']);
  let animation;
  Object.assign(host, {
    shelfOpeningCover: {},
    getUIContext: () => ({ animateTo: (options, change) => { animation = options; change(); } })
  });
  let closed = false;
  const pending = host.closeShelfCover().then(() => { closed = true; });
  advance(1000); await Promise.resolve();
  assert.equal(closed, false, `${page}: elapsed time cannot substitute for the actual last frame`);
  assert.equal(animation.expectedFrameRateRange.expected, 120);
  animation.onFinish(); await pending;
  assert.equal(closed, true);
  host.shelfOpeningCover = null;
  await host.closeShelfCover();

  const exit = method(source, page === 'ReadBook' ? 'exitReaderPage' : 'close');
  const wait = exit.indexOf(page === 'ReadBook' ? 'await shelfCoverClosed' : 'await coverClosed');
  assert.ok(wait >= 0 && wait < exit.indexOf("'shelfBookCloseAnimationNonce'"),
    `${page}: shelf return countdown starts after the cover finishes`);

  // Closing onto the cover's current shelf position: the page shrinks itself while the cover closes, over a snapshot
  // of the home page (a covered router page is not rendered); no shared transition and the frame stays visible.
  // Without a position or a snapshot the old close-then-fly path remains.
  assert.match(exit, /ShelfCoverLocator\.locate\(this\.bookUrl\)/, `${page}: asks the shelf where the cover is now`);
  assert.match(exit, /const backdrop = closeTarget \? await ShelfCoverLocator\.backdrop\(\) : null;/, `${page}: snapshots the shelf only with a target`);
  assert.match(exit, /this\.shelfSharedCoverId = detachedShelfSharedCoverId\(this\.shelfSharedCoverId\);\s*this\.shelfMotionBackdrop = backdrop;/, `${page}: backdrop replaces the shared transition`);
  assert.match(exit, /this\.shelfMotionBackdrop = backdrop;[\s\S]*?await ReaderRenderFrame\.wait\(this\.getUIContext\(\)\);/,
    `${page}: the backdrop gets a frame before the page starts shrinking`);
  assert.match(exit, /if \(selfClose\) \{[\s\S]*?this\.shelfMotionBackdropHandedOff = true;\s*AppStorage\.setOrCreate<image\.PixelMap \| null>\('shelfReturnBackdrop', this\.shelfMotionBackdrop\);[\s\S]*?\} else \{[\s\S]*?this\.shelfCoverFrameVisible = false;/,
    `${page}: the backdrop is handed to the home page on landing, the frame hidden only for the shared transition`);
  const closer = hostFor(source, ['closeIntoShelfCover']);
  let closeAnimation;
  Object.assign(closer, { getUIContext: () => ({ animateTo: (options, change) => { closeAnimation = options; change(); } }) });
  const target = { boundsX: 40, boundsY: 300, boundsWidth: 90, boundsHeight: 120, windowWidth: 360, windowHeight: 800 };
  let landed = false;
  const landing = closer.closeIntoShelfCover(target).then(() => { landed = true; });
  assert.equal(closeAnimation.duration, 500, `${page}: closing takes as long as opening`);
  assert.equal(closer.shelfOpenScaleX, 0.25); assert.equal(closer.shelfOpenScaleY, 0.15);
  assert.equal(closer.shelfOpenTranslateX, 40); assert.equal(closer.shelfOpenTranslateY, 300);
  assert.equal(closer.shelfCoverAngle, 0); assert.equal(closer.shelfCoverScaleX, 1); assert.equal(closer.shelfCoverFillImage, true);
  assert.equal(closer.shelfCoverVisible, true);
  assert.ok(storage.get('shelfBookMotionUntil') >= now + 500, `${page}: shelf refresh waits for the landing`);
  advance(1000); await Promise.resolve();
  assert.equal(landed, false); closeAnimation.onFinish(); await landing; assert.equal(landed, true);
  const build = source.slice(source.indexOf('  build() {'), source.indexOf('  build() {') + 400);
  assert.match(build, /if \(this\.shelfMotionBackdrop\) \{\s*Image\(this\.shelfMotionBackdrop\)/, `${page}: the backdrop sits outside the scaled page root`);
}

// The home page keeps the handed-over backdrop on top until the return refresh has drawn, at most 1.5 s.
const home = hostFor(read('pages/Index.ets'),
  ['onShelfReturnBackdropChanged', 'onShelfReturnRefreshed', 'armShelfReturnBackdropDrop', 'dropShelfReturnBackdropNow']);
let backdropReleases = 0;
const handedBackdrop = { release() { backdropReleases++; return Promise.resolve(); } };
Object.assign(home, { shelfReturnBackdrop: handedBackdrop, shelfReturnBackdropShown: false, shelfReturnBackdropTimer: -1 });
home.onShelfReturnBackdropChanged();
assert.equal(home.shelfReturnBackdropShown, true, 'the backdrop covers the home page as soon as it arrives');
advance(1000); assert.equal(home.shelfReturnBackdropShown, true, 'still covering while the refresh is pending');
home.onShelfReturnRefreshed();
advance(100); assert.equal(home.shelfReturnBackdropShown, true, 'two frames for the refreshed shelf to draw');
advance(50); assert.equal(home.shelfReturnBackdropShown, false, 'uncovered after the refresh has drawn');
assert.equal(home.shelfReturnBackdrop, null); assert.equal(backdropReleases, 0, 'the frame that may still draw it gets to finish first');
advance(200); assert.equal(backdropReleases, 1, 'the backdrop is released once');
Object.assign(home, { shelfReturnBackdrop: handedBackdrop, shelfReturnBackdropShown: false });
home.onShelfReturnBackdropChanged(); advance(1500);
assert.equal(home.shelfReturnBackdropShown, false, 'a refresh that never reports still uncovers after 1.5 s');
// A finger on the home page uncovers it at once, so a category swipe is not performed under a still picture.
Object.assign(home, { shelfReturnBackdrop: handedBackdrop, shelfReturnBackdropShown: false });
home.onShelfReturnBackdropChanged(); home.dropShelfReturnBackdropNow();
assert.equal(home.shelfReturnBackdropShown, false, 'touch-down uncovers the home page immediately');
assert.equal(home.shelfReturnBackdropTimer, -1, 'touch-down cancels the fallback timer');
home.dropShelfReturnBackdropNow();
advance(200); assert.equal(backdropReleases, 3, 'each hand-over releases its backdrop exactly once');
assert.match(read('pages/Index.ets'), /TouchType\.Down && this\.shelfReturnBackdropShown\) this\.dropShelfReturnBackdropNow\(\)/,
  'the home root uncovers on touch-down');
assert.match(read('components/home/BookshelfPage.ets'), /\.finally\(\(\): void => \{\s*\/\/[^\n]*\n\s*AppStorage\.setOrCreate<number>\('shelfReturnRefreshNonce', Date\.now\(\)\);/,
  'the shelf reports the return refresh whether it succeeded or failed');

// The shelf registers a locator while mounted; readers get null when nothing is mounted or the bounds are unusable.
const locatorSource = read('utils/ShelfCoverLocator.ets').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
const Locator = vm.runInContext(stripTypeScriptTypes(locatorSource) + '\nShelfCoverLocator', context);
assert.equal(Locator.locate('u'), null, 'no shelf mounted');
const good = { boundsX: 1, boundsY: 2, boundsWidth: 90, boundsHeight: 120, windowWidth: 360, windowHeight: 800 };
const measure = (url) => url === 'u' ? good : { boundsX: 0, boundsY: 0, boundsWidth: 0, boundsHeight: 0, windowWidth: 360, windowHeight: 800 };
Locator.register(measure);
assert.equal(Locator.locate('u'), good);
assert.equal(Locator.locate('other'), null, 'unmeasured covers are not usable');
Locator.unregister(() => null); assert.equal(Locator.locate('u'), good, 'another function cannot unregister the shelf');
Locator.unregister(measure); assert.equal(Locator.locate('u'), null);
const shelfPicture = {};
Locator.register(measure, async () => shelfPicture);
assert.equal(await Locator.backdrop(), shelfPicture, 'the home-page snapshot comes through the locator');
Locator.register(measure, async () => { throw new Error('offscreen capture refused'); });
assert.equal(await Locator.backdrop(), null, 'a refused snapshot yields null instead of throwing');
Locator.unregister(measure); assert.equal(await Locator.backdrop(), null, 'no snapshot once the shelf is gone');
const shelfPageSource = read('components/home/BookshelfPage.ets');
assert.match(shelfPageSource, /ShelfCoverLocator\.register\(this\.shelfCoverLocate, this\.shelfBackdropSnapshot\)/,
  'the shelf registers its locator and home-page snapshot on appear');
assert.match(shelfPageSource, /ShelfCoverLocator\.unregister\(this\.shelfCoverLocate\)/, 'the shelf unregisters on disappear');

const shelf = hostFor(read('components/home/BookshelfPage.ets'),
  ['shelfBookMotionDelay', 'scheduleLoadBooks', 'closeShelfBook', 'cancelShelfBookOpening']);
let refreshes = 0;
let heldReleases = 0;
context.BookshelfSortHelper = { releaseReadTimes: () => { heldReleases++; } };
context.BookshelfPage = { SHELF_RETURN_QUICK_REFRESH: 120 };
Object.assign(shelf, { loadTimer: -1, shelfBookReturnRefreshTimer: -1,
  loadBooks: () => { refreshes++; return Promise.resolve(); },
  playShelfReorder: () => { refreshes++; return Promise.resolve(); }, clearShelfReorderLayers() {} });
storage.set('shelfBookMotionUntil', now + 500);
shelf.scheduleLoadBooks();
advance(80); assert.equal(refreshes, 0, 'saving progress cannot rebuild the shelf during opening');
storage.set('shelfBookMotionUntil', now + 500);
advance(420); assert.equal(refreshes, 0, 'an actual animation start extends the initial estimate');
advance(80); assert.equal(refreshes, 1);

shelf.scheduleLoadBooks(); // Progress notification may arrive just before the return notification.
shelf.closeShelfBook('book');
advance(420); assert.equal(refreshes, 1, 'old refresh deadline was inside the 500 ms return flight');
shelf.scheduleLoadBooks(); // And another save can finish during the return flight.
advance(80); assert.equal(refreshes, 1, 'shared target stays stable through the last animation frame');
advance(60); assert.equal(refreshes, 2, 'coalesce progress notifications into one return refresh');
assert.equal(timers.size, 0);
shelf.closeShelfBook('book'); shelf.cancelShelfBookOpening();
advance(1000); assert.equal(refreshes, 2, 'leaving the shelf cancels the return refresh');
// A reader that shrank onto the cover itself hands over the shelf picture in the same turn; the return transition
// is instant then, so the refresh (and the move of a book whose place changed) follows soon after landing.
storage.set('shelfReturnBackdrop', {});
shelf.closeShelfBook('book');
advance(100); assert.equal(refreshes, 2, 'the handed-over picture still covers the first frames');
advance(30); assert.equal(refreshes, 3, 'refresh 120 ms after a self-drawn landing');
await Promise.resolve(); await Promise.resolve();
assert.equal(heldReleases > 0, true, 'the held reading time is released after the return refresh');
assert.equal(storage.get('shelfReturnRefreshNonce') > 0, true, 'the return refresh is always reported');
storage.delete('shelfReturnBackdrop');

const reader = hostFor(read('pages/ReadBook.ets'),
  ['isReaderPaginationInteractionBusy', 'isReaderPageMotionActive']);
Object.assign(reader, {
  pageTurnQueue: { hasPendingBackward: () => false, hasPendingForward: () => false, hasPending: () => false },
  pageSlideDirection: 0, readerComicBoundaryDirection: 0, pendingRestorePageIndex: -1,
  readerPaginationInteractionIdleUntil: 0, shelfOpenAnimating: true, readerInitialPageReady: false
});
assert.equal(reader.isReaderPaginationInteractionBusy(), false, 'opening must still produce the first readable page');
assert.equal(reader.isReaderPageMotionActive(), true, 'neighbor warmup yields while the book opens');
reader.readerInitialPageReady = true;
assert.equal(reader.isReaderPaginationInteractionBusy(), true, 'remaining pagination yields after the first page is ready');
reader.shelfOpenAnimating = false;
assert.equal(reader.isReaderPaginationInteractionBusy(), false, 'pagination resumes after opening');
reader.readerExiting = true;
assert.equal(reader.isReaderPageMotionActive(), true, 'background warmup also yields while closing');

// The body column is rasterized as one layer while the page scales from and back to the shelf cover; the rotating
// cover layer lives outside it so the cached layer survives every frame of the motion.
const readerSource = read('pages/ReadBook.ets');
const bodyStart = readerSource.search(/^      Column\(\) \{\r?\n        if \(!this\.shouldRenderPrimaryReaderContent\(\)\) \{/m);
assert.ok(bodyStart >= 0, 'body column');
const bodyColumn = readerSource.slice(bodyStart, readerSource.indexOf('// 页眉放在全屏层', bodyStart));
assert.match(bodyColumn, /\.renderGroup\(this\.shelfMotionRasterized\)/, 'the body column rasterizes during shelf motion');
assert.doesNotMatch(bodyColumn, /ReaderShelfCoverOpening\(/, 'the cover layer stays outside the rasterized body');
const motion = hostFor(readerSource, ['prepareShelfOpening', 'finishShelfOpening', 'dropShelfOpeningBackdrop']);
let openingBackdropReleases = 0;
const openingBackdrop = { release() { openingBackdropReleases++; return Promise.resolve(); } };
Object.assign(motion, {
  shelfOpeningCover: { boundsX: 10, boundsY: 20, boundsWidth: 90, boundsHeight: 120, windowWidth: 400, windowHeight: 800 },
  shelfSharedCoverId: 'cover', shelfMotionRasterized: false, shelfOpenStartTimer: -1, readerInitialOpening: true,
  readerExiting: false, shelfCoverAngle: 0, shelfPendingSharedCoverId: '',
  shelfMotionBackdrop: openingBackdrop, shelfMotionBackdropHandedOff: false
});
motion.prepareShelfOpening();
assert.equal(motion.shelfMotionRasterized, true, 'rasterized from the first scaled frame');
motion.finishShelfOpening();
assert.equal(motion.shelfMotionRasterized, false, 'ordinary reading draws the body directly again');
assert.equal(motion.shelfMotionBackdrop, null, 'the home snapshot behind the opening page goes once the motion ends');
assert.equal(openingBackdropReleases, 0, 'the frame that may still draw it gets to finish first');
advance(120); assert.equal(openingBackdropReleases, 1, 'the opening backdrop is released once');
motion.prepareShelfOpening(); motion.readerExiting = true; motion.finishShelfOpening();
assert.equal(motion.shelfMotionRasterized, true, 'leaving during the opening keeps the layer for the return flight');

// Opening a book with an update badge must not rebuild the shelf inside the tap: the in-memory acknowledgement waits
// for the open motion, and a reload that already cleared the badge makes it a no-op.
const shelfSource = read('components/home/BookshelfPage.ets');
const badge = hostFor(shelfSource, ['acknowledgeShelfBookUpdate', 'applyShelfBookUpdateAcknowledgement',
  'shelfBookMotionDelay', 'hasShelfBookUpdate']);
let shelfRebuilds = 0, persisted = 0;
const makeBook = (flag) => ({ bookUrl: 'u', name: 'n', flag, getVariable: function () { return this.flag; },
  putVariable: function (_k, v) { this.flag = v; } });
const taggedBook = makeBook('1');
Object.assign(badge, {
  shelfUpdateAcknowledgedAt: new Map(), shelfComponentActive: true, allBooks: [taggedBook],
  applyShelfScope() {}, reloadShelfDataSources() { shelfRebuilds++; },
  hasShelfRefreshError: () => false, clearShelfRefreshError() {},
  persistShelfBookUpdateAcknowledgement() { persisted++; return Promise.resolve(); }
});
storage.set('shelfBookMotionUntil', now + 800);
badge.acknowledgeShelfBookUpdate(taggedBook, true);
assert.equal(shelfRebuilds, 0, 'no synchronous shelf rebuild inside the tap');
assert.equal(persisted, 1, 'the badge is cleared in the database at once');
assert.equal(taggedBook.flag, '1', 'the visible badge is untouched until the motion ends');
advance(700); assert.equal(shelfRebuilds, 0);
advance(300); assert.equal(shelfRebuilds, 1, 'one shelf rebuild after the open motion');
assert.equal(taggedBook.flag, '');
const reloadedBook = makeBook('1');
badge.allBooks = [reloadedBook];
badge.acknowledgeShelfBookUpdate(reloadedBook, true);
badge.allBooks = [makeBook('')];
advance(2000); assert.equal(shelfRebuilds, 1, 'a reload that already cleared the badge needs no second rebuild');
badge.acknowledgeShelfBookUpdate(makeBook('1'), false);
assert.equal(shelfRebuilds, 1, 'immediate acknowledgement outside the open path still works through the list lookup');
badge.allBooks = [makeBook('1')]; badge.acknowledgeShelfBookUpdate(badge.allBooks[0]);
assert.equal(shelfRebuilds, 2);

// Hardware-key subscription waits for the open motion instead of running inside the tap.
const keys = hostFor(readerSource, ['updateVolumeKeySubscription', 'delayPastShelfOpening']);
let registered = 0;
Object.assign(keys, {
  readerVolumeKeySubscribeTimerId: -1, readerEntryAlive: true, shelfOpenAnimating: true, shelfOpenEndsAt: now + 500,
  readerPageVisible: true, isTtsSpeaking: false, ttsReader: { isSpeaking: () => false }, readerVolumeTurnActive: () => true,
  readerSmartKeyTurnActive: () => false, readerSmartKeyTurnSupported: false,
  unregisterVolumeKeyTurn() {}, unregisterSmartKeyTurn() {}, registerVolumeKeyTurn() { registered++; },
  registerSmartKeyTurn() {}
});
keys.updateVolumeKeySubscription();
assert.equal(registered, 0, 'no key subscription inside the opening tap');
keys.updateVolumeKeySubscription();
advance(400); assert.equal(registered, 0);
keys.shelfOpenAnimating = false; advance(200);
assert.equal(registered, 1, 'one coalesced subscription right after the motion');
assert.equal(keys.readerVolumeKeySubscribeTimerId, -1);
assert.match(readerSource.slice(readerSource.indexOf('  build() {'), readerSource.indexOf('  build() {') + 400),
  /if \(this\.readerStageRuntimeHostMounted\) \{\s*BookSourceStageRuntimeHost\(\)/,
  'the hidden source runtime host is mounted only once the reader has settled');

// A status-bar avoid-area change during the opening animation repaginates only after the motion has finished.
const safeArea = hostFor(readerSource,
  ['applyReaderStatusBarSafeHeight', 'repaginateForSafeAreaChange', 'delayPastShelfOpening']);
let paginations = 0;
Object.assign(safeArea, {
  statusBarSafeHeight: 0, content: 'body', readerEntryAlive: true, hasPagedReaderArea: () => true,
  readerPaginationCache: { clear() {} }, pageTurnPreviewKey: 'preview', readerSafeAreaRepaginateTimerId: -1,
  shelfOpenAnimating: true, shelfOpenEndsAt: now + 500, paginateContent: () => { paginations++; }
});
safeArea.applyReaderStatusBarSafeHeight(36);
assert.equal(paginations, 0, 'no whole-chapter repagination inside the opening animation');
safeArea.applyReaderStatusBarSafeHeight(40);
advance(400); assert.equal(paginations, 0);
advance(200); assert.equal(paginations, 1, 'one coalesced repagination right after the motion');
assert.equal(safeArea.readerSafeAreaRepaginateTimerId, -1);
safeArea.shelfOpenAnimating = false;
safeArea.applyReaderStatusBarSafeHeight(0);
assert.equal(paginations, 2, 'outside the animation the repagination stays immediate');
safeArea.shelfOpenAnimating = true; safeArea.shelfOpenEndsAt = now + 500;
safeArea.applyReaderStatusBarSafeHeight(36); safeArea.readerEntryAlive = false; advance(600);
assert.equal(paginations, 2, 'a page that is already gone does not repaginate');
console.log('PASS shelf animation: real finish callback, high-refresh request, stable return target and deferred/coalesced refresh');
