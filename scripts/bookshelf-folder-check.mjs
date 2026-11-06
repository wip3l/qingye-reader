// Tile groups open as an in-shelf page: the folder's books fly to their places on the group page while the shelf
// fades out, and fly back into the folder on return.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const names = ['openTileGroupPage', 'flyIntoTileGroup', 'leaveTileGroupPage', 'flyOutOfTileGroup', 'crossFadeTileGroup',
  'settleTileGroupFlyers', 'returnToTileGroupShelf', 'afterTileGroupShelfRestored', 'selectShelfGroup', 'onActiveShelfGroupChanged', 'exitTileGroupPage',
  'isTileLayout', 'isCompanionLayout', 'isTileGroupPage', 'activeShelfGroupName', 'applyShelfScope', 'refreshShelfTypeTabs',
  'activeShelfTypeTab', 'booksForShelfScope', 'isInShelfView', 'matchesShelfGroup', 'shelfBookType',
  'shouldUseTileGroupFolders', 'reloadShelfDataSources', 'tileGroupElementId', 'changeTileGroup',
  'beginTileGroupMotion', 'afterTileGroupFrames', 'applyTileGroupTarget', 'finishTileGroupMotion',
  'clearTileGroupMotionLayers', 'cancelTileGroupMotion', 'onTileGroupBackRequested', 'getTileGroupBooks',
  'getTileGroupPreviewBooks', 'updateContextViewport', 'areaDimension', 'tileGroupPreviewCoverId', 'tileGroupFlyValue',
  'isTileGroupFlyingBook', 'tileGroupViewportKey', 'measureTileGroupRect', 'captureTileGroupPreviewSources',
  'measureTileGroupPageCover', 'measureTileGroupPagePose', 'estimateTileGroupPagePose', 'tileGroupPagePoseKey',
  'rememberTileGroupPagePoses', 'makeTileGroupBookFlyer', 'retargetTileGroupFlyer', 'mountTileGroupFlyers',
  'openTileGroupFlyers', 'closeTileGroupFlyers', 'shelfCoverScope', 'shelfCoverElementId', 'shelfFolderFanSlots',
  'shelfFolderFanAngle', 'shelfFolderFanShift', 'shelfFolderFanRise', 'shelfHardcoverThickness'];
const methods = names.map(name => {
  const plain = source.indexOf(`  ${name}(`);
  const at = plain >= 0 ? plain : source.indexOf(`  async ${name}(`);
  assert.ok(at >= 0, name);
  return source.slice(at, source.indexOf('\n  }', at) + 4);
}).join('\n');
const topClass = name => {
  const at = source.indexOf(`class ${name} {`);
  assert.ok(at >= 0, name);
  const end = source.slice(at).search(/\n}\r?\n/);
  return source.slice(at, at + end + 2);
};
const saved = [], animations = [], reloads = [];
/** null: frame callbacks fire at once; an array: they wait until flushFrames(). */
let frameQueue = null;
function flushFrames() { const queued = frameQueue.splice(0); queued.forEach(callback => callback.next()); }
const timers = new Map();
let nextTimer = 0;
const context = vm.createContext({
  SHELF_GROUP_FLY_DURATION: 440, SHELF_GROUP_FLY_BACK_DURATION: 400, SHELF_GROUP_FADE_OUT_DURATION: 160,
  SHELF_GROUP_FADE_IN_DURATION: 180, SHELF_GROUP_SETTLE_DURATION: 180, SHELF_GROUP_MOTION_WATCHDOG: 1600,
  SHELF_GROUP_RESTORE_WAIT: 600,
  SHELF_GROUP_FRAME_RATE: { min: 60, max: 120, expected: 120 }, SHELF_GROUP_PREMOUNT_FRAMES: 2,
  SharedElementBounds: class { constructor(x, y, width, height) { Object.assign(this, { x, y, width, height }); } },
  BookTileLayout: { SIDE_PADDING: 20 },
  setTimeout(fn, delay) { timers.set(++nextTimer, { fn, delay }); return nextTimer; },
  clearTimeout(id) { timers.delete(id); },
  console, getContext: () => ({}), Curve: { EaseOut: 'ease-out' },
  curves: { cubicBezierCurve: (...points) => ({ points }) },
  ShelfGroupNextFrame: class { constructor(next) { this.next = next; } },
  BookTypeSupport: { isVideo: b => b.type === 'video', isAudio: b => b.type === 'audio', isImage: b => b.type === 'image' },
  BookshelfStateStore: { saveActiveGroupId: async (_context, groupId) => saved.push(groupId) },
});
// Layout rects (window px == vp here). getRectangleById reports layout positions, not transformed ones.
const rects = {
  bookshelf_motion_root: { x: 0, y: 0, width: 800, height: 1200 },
  shelf_group_audio_7: { x: 40, y: 180, width: 100, height: 150 },
  [`shelf_group_audio_7_cover_${encodeURIComponent('group-a-audio')}`]: { x: 50, y: 190, width: 40, height: 60 },
  [`shelf_book_cover_audio_${encodeURIComponent('group-a-audio')}`]: { x: 20, y: 110, width: 100, height: 140 }
};
vm.runInContext(stripTypeScriptTypes(`${topClass('TileGroupPreviewSource')}
${topClass('TileGroupFlyer')}
class BookshelfPage {
  static TYPE_TAB_IDS = ['all', 'text', 'image', 'audio', 'video'];
  ${methods}
}
globalThis.Shelf = BookshelfPage;
globalThis.TileGroupFlyer = TileGroupFlyer;
globalThis.TileGroupPreviewSource = TileGroupPreviewSource;`), context);
const shelf = new context.Shelf();
const dataSource = () => ({ books: [], replace(books, force) { this.books = [...books]; reloads.push(force); } });
const books = [
  { bookUrl: 'group-a-audio', group: 7, type: 'audio', name: '甲' },
  { bookUrl: 'group-a-text', group: 7, type: 'text', name: '乙' },
  { bookUrl: 'group-b-audio', group: 8, type: 'audio', name: '丙' },
  { bookUrl: 'group-a-hidden', group: 7, type: 'audio', isPrivate: true },
  { bookUrl: 'filtered', group: 7, type: 'audio' },
  { bookUrl: 'ungrouped', group: 0, type: 'audio' }
].map(book => ({ isPrivate: false, ...book }));
Object.assign(shelf, {
  bookshelfLayoutMode: 'tile', bookshelfCompanionStagger: true, bookshelfTypeCategoryEnabled: true, bookshelfShowAllTypeTab: true, shelfScope: 'all', shelfTypeTab: 'audio', shelfTypeTabIds: ['all', 'audio'],
  shelfGroups: [{ groupId: 7, groupName: '分组甲' }, { groupId: 8, groupName: '分组乙' }],
  allBooks: books, books: [], isBookMultiSelect: false, shelfAppliedSearchKeyword: '',
  shelfCategoryRevision: 0, shelfStateRestored: false, shelfScopeSwitchAnimating: false,
  showShelfGroupMenu: true, showShelfMoreMenu: true, showShelfFilterMenu: true,
  shelfListBooksSource: dataSource(), shelfTileBooksSource: dataSource(), shelfTileEntriesSource: dataSource(),
  sortBooks: books => [...books], matchesShelfFilters: book => book.bookUrl !== 'filtered',
  matchesShelfSearch: () => true, getTileBooksWithoutLatest: books => books,
  getSortedTileRootEntries: books => books.map(book => ({ book })),
  shelfComponentActive: true, tileGroupAnimating: false, tileGroupHasOrigin: false,
  tileGroupOriginGroupId: 0, tileGroupOriginPageKey: '', tileGroupOriginViewportKey: '',
  tileGroupFlyers: [], tileGroupFlyProgress: 0, tileGroupFlyingBooks: [], tileGroupHiddenFolder: '',
  tileGroupMotionBackground: false, tileGroupSyncCovers: false, tileGroupSyncAfterRestore: false, tileGroupShelfOpacity: 1, tileGroupPageOpacity: 1,
  tileGroupPreviewSources: [], tileGroupPagePoseCache: new Map(),
  shouldUseThemeBookCover: () => false, getBookColor: () => '#000000',
  tileGroupPendingBack: false, tileGroupPendingTarget: -1, tileGroupMotionGeneration: 0,
  tileGroupMotionWatchdog: -1, tileGroupRootPages: null,
  shelfCategoryPages: new Map([['audio', { tileOffset: 420 }]]), shelfHeaderCollapse: 20,
  contextViewportWidth: 800, contextViewportHeight: 1200, statusBarHeight: 30,
  shelfTileColumnCount: () => 3, shelfTileColumnWidth: () => 100, shelfTileColumnGap: () => 20,
  // Companion-layout metrics: the fanned folder books are smaller than the books on the group page.
  shelfFolderBookWidth: () => 60, shelfFolderBookHeight: () => 82, shelfTileHardcoverHeight: () => 110,
  shelfTileBookCoverWidth: () => 80, shelfTileBookCoverHeight: () => 109, shelfTileBookLean: () => 2,
  shelfBooksForPage: () => shelf.booksForShelfScope('all'), shelfPageKey: () => 'audio',
  getUIContext: () => ({
    animateTo(options, update) { animations.push(options); update(); },
    // Frame callbacks fire at once.
    // Unqueued frames also stand in for the grid's deferred scroll restore, which runs right after the rebuild.
    postFrameCallback(callback) {
      if (frameQueue) frameQueue.push(callback);
      else { shelf.tileGroupSyncAfterRestore = false; callback.next(); }
    },
    px2vp: value => value,
    getComponentUtils: () => ({ getRectangleById: id => {
      const rect = rects[id];
      if (!rect) throw new Error(`no component ${id}`);
      return { size: { width: rect.width, height: rect.height }, windowOffset: { x: rect.x, y: rect.y } };
    } })
  }),
  consumeShelfSwipeClick: () => false
});
let groupId = 0;
Object.defineProperty(shelf, 'activeShelfGroupId', {
  get: () => groupId,
  set(value) { if (groupId !== value) { groupId = value; shelf.onActiveShelfGroupChanged(); } }
});
const visible = () => Array.from(shelf.shelfTileBooksSource.books, book => book.bookUrl);
function runTimer(id) { const timer = timers.get(id); assert.ok(timer, `timer ${id}`); timers.delete(id); timer.fn(); }
/** Ends the most recent animation of the given duration that still has a pending completion. */
function complete(duration) {
  for (let i = animations.length - 1; i >= 0; i--) {
    const a = animations[i];
    if (a.duration === duration && a.onFinish && !a.done) { a.done = true; a.onFinish(); return a; }
  }
  assert.fail(`no pending ${duration}ms animation`);
}
const close = (a, b, message) => assert.ok(Math.abs(a - b) < 1e-9, `${message}: ${a} vs ${b}`);
const rootPages = shelf.shelfCategoryPages;
assert.equal(shelf.shouldUseTileGroupFolders(), true);
shelf.onActiveShelfGroupChanged();
assert.deepEqual(saved, [], 'initial state restoration must not overwrite the saved group');
shelf.shelfStateRestored = true;

// Opening: the folder's book takes off at once; the shelf fades out and is only then replaced by the group page.
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, true);
assert.equal(shelf.tileGroupMotionBackground, true, 'the page background stays put under the fading shelf');
const [opener] = shelf.tileGroupFlyers;
assert.equal(shelf.tileGroupFlyers.length, 1, 'one preview cover is visible in the folder');
assert.equal(opener.kind, 'flat');
assert.equal(opener.fromX, 50);
assert.equal(opener.fromY, 190);
assert.equal(opener.toX, 20, 'first column of the group page');
assert.equal(opener.toY, 30 + 56 + 12, 'first row sits 12vp under the title bar');
close(opener.fromScaleX * opener.width, 40, 'starts at the 2x2 cell size');
assert.equal(shelf.tileGroupHiddenFolder, 'shelf_group_audio_7', 'the folder copy hides once the flyer is drawn');
assert.equal(animations[0].duration, 440, 'the book flies right away');
assert.equal(shelf.tileGroupFlyProgress, 1);
assert.equal(animations[1].duration, 160);
assert.equal(shelf.tileGroupShelfOpacity, 0, 'the live shelf fades out');
assert.equal(shelf.activeShelfGroupId, 0, 'the shelf is not torn down while it fades');
assert.equal(shelf.tileGroupSyncCovers, false, 'the live shelf keeps loading covers asynchronously');
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupPendingTarget, 7, 'repeated taps cannot replace a running transition');
complete(160);
assert.equal(shelf.isTileGroupPage(), true, 'the group page is built once the shelf is invisible');
assert.equal(shelf.tileGroupSyncCovers, true, 'covers built mid-transition decode synchronously: no empty hardcovers');
assert.equal(shelf.activeShelfGroupName(), '分组甲');
assert.deepEqual(visible(), ['group-a-audio'], 'group page preserves category, privacy and filters');
assert.equal(shelf.shouldUseTileGroupFolders(), false);
assert.notEqual(shelf.shelfCategoryPages, rootPages, 'group and root keep separate scroll controllers');
assert.equal(shelf.shelfHeaderCollapse, 0);
assert.equal(shelf.showShelfGroupMenu || shelf.showShelfMoreMenu || shelf.showShelfFilterMenu, false);
assert.deepEqual(saved, [7]);
assert.ok(reloads.every(Boolean));
assert.equal(animations[2].duration, 180);
assert.equal(shelf.tileGroupPageOpacity, 1, 'the built page fades in');
assert.equal(shelf.isTileGroupFlyingBook({ bookUrl: 'group-a-audio' }), true,
  'the page copy stays hidden while the flyer is still landing');
complete(440);
assert.equal(shelf.tileGroupAnimating, true, 'waits for the page too');
complete(180);
// The estimate was 12vp off; the landed book slides onto the measured spot before handing over.
const settle = animations[animations.length - 1];
assert.equal(settle.duration, 180);
assert.equal(shelf.tileGroupFlyers[0].toY, 110);
close(shelf.tileGroupFlyers[0].toScaleY * shelf.tileGroupFlyers[0].height, 140, 'settles to the measured size');
assert.equal(shelf.tileGroupAnimating, true);
settle.onFinish();
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual([...shelf.tileGroupFlyers], [], 'the flying book hands over to the page');
assert.equal(shelf.isTileGroupFlyingBook({ bookUrl: 'group-a-audio' }), false, 'in the same frame the page copy shows');
assert.equal(shelf.tileGroupHiddenFolder, '');
assert.equal(shelf.tileGroupMotionBackground, false);
assert.equal(shelf.tileGroupSyncCovers, false, 'covers scrolled in later load asynchronously again');
assert.equal(shelf.tileGroupShelfOpacity, 1);
assert.ok(shelf.tileGroupPagePoseCache.size === 1, 'the measured landing spot is remembered');

// Return: the page's book flies back into the folder; the shelf is rebuilt only after the page has faded out.
shelf.exitTileGroupPage();
const [closer] = shelf.tileGroupFlyers;
assert.ok(closer, 'the preview book flies back');
assert.equal(closer.fromX, 20);
assert.equal(closer.fromY, 110);
assert.equal(closer.toX, 50);
assert.equal(closer.toY, 190);
assert.deepEqual([...shelf.tileGroupFlyingBooks], ['group-a-audio'], 'the page copy hides once the flyer is drawn');
assert.equal(shelf.tileGroupPageOpacity, 0);
assert.equal(shelf.activeShelfGroupId, 7, 'the shelf is not rebuilt during the fade');
complete(160);
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.shelfCategoryPages, rootPages);
assert.equal(rootPages.get('audio').tileOffset, 420);
assert.equal(shelf.shelfHeaderCollapse, 20);
assert.deepEqual(visible(), ['group-a-audio', 'group-b-audio', 'ungrouped']);
assert.equal(shelf.tileGroupHiddenFolder, 'shelf_group_audio_7', 'the folder stays empty until the book lands');
assert.equal(shelf.tileGroupSyncAfterRestore, false, 'the restore has run (simulated by the next frame)');
assert.equal(shelf.tileGroupShelfOpacity, 1, 'the rebuilt shelf fades in');
complete(400);
complete(180);
assert.equal(shelf.tileGroupAnimating, false, 'lands exactly on the folder: no settling needed');
assert.equal(shelf.tileGroupHiddenFolder, '');
assert.equal(shelf.tileGroupHasOrigin, false);
assert.equal(shelf.shouldUseTileGroupFolders(), true);
assert.deepEqual(saved, [7, 0]);

// Second opening uses the remembered landing spot: no settling step.
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.tileGroupFlyers[0].toY, 110);
complete(160);
complete(440);
const before = animations.length;
complete(180);
assert.equal(animations.length, before, 'nothing left to settle');
assert.equal(shelf.tileGroupAnimating, false);
// The rebuilt shelf scrolls back a frame later; it fades in only once it is back where it was, not at the top first.
frameQueue = [];
shelf.exitTileGroupPage();
flushFrames(); flushFrames();
complete(160);
// The rebuilt scroller still reports the old offset, so the wait keys off the restore itself.
assert.equal(shelf.tileGroupSyncAfterRestore, true, 'the restored screen will decode synchronously...');
assert.equal(shelf.tileGroupSyncCovers, false, '...while the top of the shelf, about to scroll away, decodes lazily');
const fadesBefore = animations.length;
flushFrames(); flushFrames(); flushFrames();
assert.equal(animations.length, fadesBefore, 'not scrolled back yet: no fade-in');
shelf.tileGroupSyncAfterRestore = false; // restoreShelfPageScroll ran
flushFrames();
assert.equal(animations.length, fadesBefore, 'the restored screen still needs laying out and drawing');
flushFrames(); flushFrames();
assert.equal(animations[animations.length - 1].duration, 180, 'back in place: fades in');
frameQueue = null;
complete(400); complete(180);
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.tileGroupAnimating, false);

shelf.consumeShelfSwipeClick = () => true;
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, false, 'a swipe release is not a tap');
shelf.consumeShelfSwipeClick = () => false;

// A folder with nothing measurable to fly cross-fades; system Back while opening is queued.
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupFlyers.length, 0);
assert.equal(shelf.tileGroupShelfOpacity, 0);
complete(160);
assert.deepEqual(visible(), ['group-b-audio']);
shelf.onTileGroupBackRequested();
assert.equal(shelf.tileGroupPendingBack, true, 'system Back during opening is queued');
complete(180);
assert.equal(shelf.tileGroupAnimating, true, 'the queued Back runs at once');
assert.equal(shelf.tileGroupPageOpacity, 0, 'no origin to fly back to: fade out');
complete(160);
complete(180);
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual(saved, [7, 0, 7, 0, 8, 0]);

// Disposed callbacks cannot unlock a newer transition.
shelf.openTileGroupPage(7, 'audio', 90, 220);
const staleFade = animations[animations.length - 1];
shelf.cancelTileGroupMotion();
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(timers.has(shelf.tileGroupMotionWatchdog), false, 'disposal cancels the watchdog');
shelf.openTileGroupPage(7, 'audio', 90, 220);
staleFade.onFinish();
assert.equal(shelf.activeShelfGroupId, 0, 'a disposed fade cannot switch the page');
complete(160); complete(440); complete(180);
assert.equal(shelf.tileGroupAnimating, false);

// A resized window has no valid folder to return to: cross-fade instead.
shelf.updateContextViewport({ width: 1200, height: 800 });
assert.equal(shelf.tileGroupHasOrigin, false, 'resizing invalidates old screen coordinates');
shelf.exitTileGroupPage();
assert.equal(shelf.tileGroupFlyers.length, 0);
assert.equal(shelf.tileGroupPageOpacity, 0, 'resized windows fade instead of flying to a stale folder');
complete(160); complete(180);
shelf.updateContextViewport({ width: 800, height: 1200 });

// Group menu switching has no folder: the page cross-fades.
shelf.selectShelfGroup(8);
complete(160);
assert.equal(shelf.activeShelfGroupId, 8);
complete(180);
assert.equal(shelf.tileGroupPageOpacity, 1);
shelf.exitTileGroupPage(); complete(160); complete(180);

// A lost animation callback cannot lock the shelf: the watchdog switches anyway.
shelf.openTileGroupPage(7, 'audio', 90, 220);
runTimer(shelf.tileGroupMotionWatchdog);
assert.equal(shelf.activeShelfGroupId, 7);
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual([...shelf.tileGroupFlyers], []);
complete(160);
assert.equal(shelf.tileGroupPageOpacity, 1, 'late callbacks of an abandoned transition change nothing');
shelf.exitTileGroupPage(); complete(160); complete(400); complete(180);
assert.equal(shelf.activeShelfGroupId, 0);

// Companion layout: the fanned hardcovers take off from their slots (tilted, the back ones darker) and land
// at the full book size with their shelf lean, scaled uniformly.
shelf.bookshelfLayoutMode = 'companion';
shelf.tileGroupPagePoseCache = new Map();
shelf.shelfBooksForPage = () => books.filter(book => !book.isPrivate && book.bookUrl !== 'filtered');
shelf.openTileGroupPage(7, 'audio', 90, 220);
const [back, front] = shelf.tileGroupFlyers;
assert.equal(shelf.tileGroupFlyers.length, 2, 'the two visible fanned books fly, back one first');
assert.equal(back.key, 'group-a-text');
assert.equal(back.kind, 'hardcover');
assert.equal(back.fromX, 40 + Math.round((100 - 60 - 6 - 3) / 2) - 5);
assert.equal(back.fromY, 180 + 110 - 82);
assert.equal(back.fromAngle, -7);
assert.equal(back.fromShade, 0.12);
assert.equal(front.fromAngle, 0);
assert.equal(front.fromShade, 0);
assert.equal(front.width, 80, 'laid out at the group page size');
close(front.fromScaleX, 60 / 80, 'starts at the folder size');
assert.equal(front.fromScaleY, front.fromScaleX, 'hardcovers scale uniformly');
assert.equal(front.toX, 20 + Math.round((100 - 80 - 8 - 3) / 2));
assert.equal(front.toY, 98 + 110 - 109, 'book bottoms line up as on the shelf');
assert.equal(front.toAngle, 2, 'lands with its shelf lean');
assert.equal(back.toX, 20 + 120 + Math.round((100 - 80 - 8 - 3) / 2), 'second book, second column');
shelf.cancelTileGroupMotion();

assert.doesNotMatch(source, /openTileFolder|tileFolderOverlay|bookshelf_folder_open|tileGroupTransitionScale|geometryTransition\(this\.tileGroup|tileGroupBackdrop|tileGroupCardShot/);
const index = fs.readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.ok(index.includes("AppStorage.setOrCreate('bookshelfGroupBackRequest'"));
console.log('PASS tile group motion: books fly out of and back into the folder, isolated scroll state, filters, back during opening, stale callbacks, resize, cross-fade, watchdog and companion hardcovers');
