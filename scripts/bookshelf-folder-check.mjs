// Tile groups open like the private shelf: the group page is its own layer on top of the shelf, and the two live
// layers zoom around the tapped folder. The shelf underneath is never torn down: opening only builds the group page,
// and going back only shows the hidden shelf again (no rebuild, no scroll restore) before the group layer is dropped.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const names = ['openTileGroupPage', 'leaveTileGroupPage', 'changeTileGroup', 'zoomTileGroup',
  'beginTileGroupCoverWait', 'afterTileGroupCoversReady', 'noteTileGroupCoverMounted', 'applyTileGroupTarget',
  'mountTileGroupLayer', 'syncTileGroupLayer', 'selectShelfGroup', 'onActiveShelfGroupChanged', 'exitTileGroupPage',
  'isTileLayout', 'isCompanionLayout', 'isTileGroupPage', 'activeShelfGroupName', 'applyShelfScope', 'refreshShelfTypeTabs',
  'activeShelfTypeTab', 'booksForShelfScope', 'isInShelfView', 'matchesShelfGroup', 'shelfBaseGroupId',
  'tileGroupPageKey', 'tileGroupLayerKey', 'tileGroupLayerName', 'isTileGroupPageKey', 'pageGroupId', 'pageTypeKey',
  'shelfBookType', 'shouldUseTileGroupFolders', 'reloadShelfDataSources', 'tileGroupElementId', 'beginTileGroupMotion',
  'afterTileGroupFrames', 'finishTileGroupMotion', 'clearTileGroupMotionLayers', 'cancelTileGroupMotion',
  'onTileGroupBackRequested', 'getTileGroupBooks', 'updateContextViewport', 'areaDimension', 'tileGroupViewportKey',
  'measureTileGroupRect', 'coverSyncLoadable', 'shelfCoverSyncLoad', 'shelfPageOrder', 'shelfPageKey',
  'shelfCategoryPage', 'shelfBooksForPage'];
const methods = names.map(name => {
  const plain = source.indexOf(`  ${name}(`);
  const at = plain >= 0 ? plain : source.indexOf(`  async ${name}(`);
  assert.ok(at >= 0, name);
  return source.slice(at, source.indexOf('\n  }', at) + 4);
}).join('\n');
const saved = [], animations = [], warmed = [];
/** null: frame callbacks fire at once; an array: they wait until flushFrames(). */
let frameQueue = null;
function flushFrames() { const queued = frameQueue.splice(0); queued.forEach(callback => callback.next()); }
const timers = new Map();
let nextTimer = 0;
/** Every replace() on a category page's data source, by page key: a replaced shelf page means the shelf rebuilt. */
const replaced = [];
const dataSource = key => ({ books: [], replace(books) { this.books = [...books]; replaced.push(key); } });
class ShelfCategoryPage {
  constructor() {
    this.signature = ''; this.books = []; this.tileOffset = 0;
    this.listSource = dataSource('list'); this.tileSource = dataSource('tile'); this.entrySource = dataSource('entry');
  }
}
const context = vm.createContext({
  SHELF_GROUP_ZOOM_IN_DURATION: 420, SHELF_GROUP_ZOOM_OUT_DURATION: 340, SHELF_GROUP_ZOOM_LARGE: 1.06,
  SHELF_GROUP_ZOOM_SMALL: 0.94, SHELF_GROUP_PAGE_PREPARE_OPACITY: 0.01, SHELF_GROUP_MOTION_WATCHDOG: 2400,
  SHELF_GROUP_COVER_WAIT: 150, SHELF_GROUP_FRAME_RATE: { min: 60, max: 120, expected: 120 },
  SharedElementBounds: class { constructor(x, y, width, height) { Object.assign(this, { x, y, width, height }); } },
  ShelfCategoryPage,
  setTimeout(fn, delay) { timers.set(++nextTimer, { fn, delay }); return nextTimer; },
  clearTimeout(id) { timers.delete(id); },
  console, getContext: () => ({}),
  curves: { cubicBezierCurve: (...points) => ({ points }) },
  ShelfGroupNextFrame: class { constructor(next) { this.next = next; } },
  BookTypeSupport: { isVideo: b => b.type === 'video', isAudio: b => b.type === 'audio', isImage: b => b.type === 'image' },
  BookshelfStateStore: { saveActiveGroupId: async (_context, groupId) => saved.push(groupId) },
});
const rects = {
  bookshelf_motion_root: { x: 0, y: 0, width: 800, height: 1200 },
  shelf_group_audio_7: { x: 40, y: 180, width: 100, height: 150 }
};
vm.runInContext(stripTypeScriptTypes(`class BookshelfPage {
  static TYPE_TAB_IDS = ['all', 'text', 'image', 'audio', 'video'];
  ${methods}
}
globalThis.Shelf = BookshelfPage;`), context);
const shelf = new context.Shelf();
const books = [
  { bookUrl: 'group-a-audio', group: 7, type: 'audio', name: '甲' },
  { bookUrl: 'group-a-text', group: 7, type: 'text', name: '乙' },
  { bookUrl: 'group-b-audio', group: 8, type: 'audio', name: '丙' },
  { bookUrl: 'group-a-hidden', group: 7, type: 'audio', isPrivate: true },
  { bookUrl: 'filtered', group: 7, type: 'audio' },
  { bookUrl: 'ungrouped', group: 0, type: 'audio' }
].map(book => ({ isPrivate: false, ...book }));
const legacySource = () => ({ replace() {} });
Object.assign(shelf, {
  bookshelfLayoutMode: 'companion', bookshelfTypeCategoryEnabled: true, bookshelfShowAllTypeTab: true, shelfScope: 'all',
  shelfTypeTab: 'audio', shelfTypeTabIds: ['all', 'audio'],
  shelfGroups: [{ groupId: 7, groupName: '分组甲' }, { groupId: 8, groupName: '分组乙' }],
  allBooks: books, books: [], isBookMultiSelect: false, shelfAppliedSearchKeyword: '', shelfFilterKeys: '',
  sortMode: 'recent', bookshelfLastReadPinMode: 'off', bookshelfLastReadPinCount: 1,
  privateShelfEnabled: false, privateShelfHasPassword: false, privateShelfRevealed: false,
  shelfCategoryRevision: 0, shelfStateRestored: false, shelfScopeSwitchAnimating: false,
  showShelfGroupMenu: true, showShelfMoreMenu: true, showShelfFilterMenu: true,
  shelfListBooksSource: legacySource(), shelfTileBooksSource: legacySource(), shelfTileEntriesSource: legacySource(),
  shelfTileEntriesCacheKey: '', shelfTileEntriesCache: [],
  sortBooks: books => [...books], matchesShelfFilters: book => book.bookUrl !== 'filtered',
  matchesShelfSearch: () => true, getTileBooksWithoutLatest: books => books, getLatestReadTileBooks: () => [],
  getSortedTileRootEntries: books => books.map(book => ({ book })),
  shelfComponentActive: true, tileGroupAnimating: false, tileGroupHasOrigin: false,
  tileGroupOriginGroupId: 0, tileGroupOriginViewportKey: '', tileGroupOriginX: 0, tileGroupOriginY: 0,
  tileGroupLayerGroupId: 0, tileGroupPages: new Map(), tileGroupBaseGroupId: 0, tileGroupBackdropReveal: 0,
  tileGroupShelfScale: 1, tileGroupPageScale: 1, tileGroupZoomX: 0, tileGroupZoomY: 0,
  tileGroupShelfOpacity: 1, tileGroupPageOpacity: 1,
  tileGroupAwaitCovers: false, tileGroupPendingCovers: new Set(),
  tileGroupPendingBack: false, tileGroupPendingTarget: -1, tileGroupMotionGeneration: 0, tileGroupMotionWatchdog: -1,
  shelfCategoryPages: new Map(), shelfListScroller: null, shelfTileScroller: null,
  contextViewportWidth: 800, contextViewportHeight: 1200, shelfTileViewportWidth: 800, statusBarHeight: 30,
  getUIContext: () => ({
    animateTo(options, update) {
      options.from = { shelfScale: shelf.tileGroupShelfScale, shelfOpacity: shelf.tileGroupShelfOpacity,
        pageScale: shelf.tileGroupPageScale, pageOpacity: shelf.tileGroupPageOpacity };
      options.layer = shelf.tileGroupLayerGroupId;
      animations.push(options);
      update();
      options.to = { shelfScale: shelf.tileGroupShelfScale, shelfOpacity: shelf.tileGroupShelfOpacity,
        pageScale: shelf.tileGroupPageScale, pageOpacity: shelf.tileGroupPageOpacity };
    },
    postFrameCallback(callback) {
      if (frameQueue) frameQueue.push(callback);
      else callback.next();
    },
    px2vp: value => value,
    getComponentUtils: () => ({ getRectangleById: id => {
      const rect = rects[id];
      if (!rect) throw new Error(`no component ${id}`);
      return { size: { width: rect.width, height: rect.height }, windowOffset: { x: rect.x, y: rect.y } };
    } })
  }),
  consumeShelfSwipeClick: () => false,
  // The real one reads the disk cache; here it only records the call.
  warmTileGroupCovers(id) { warmed.push(id); }
});
let groupId = 0;
Object.defineProperty(shelf, 'activeShelfGroupId', {
  get: () => groupId,
  set(value) { if (groupId !== value) { groupId = value; shelf.onActiveShelfGroupChanged(); } }
});
const pageBooks = key => Array.from(shelf.shelfBooksForPage(key), book => book.bookUrl);
/** What build() shows: the shelf hides under an open group page once nothing moves; the group layer is tile-only. */
const shelfHidden = () => shelf.isTileGroupPage() && !shelf.tileGroupAnimating;
const groupLayerShown = () => shelf.tileGroupLayerGroupId > 0 && shelf.isTileLayout();
function runTimer(id) { const timer = timers.get(id); assert.ok(timer, `timer ${id}`); timers.delete(id); timer.fn(); }
function complete(duration) {
  for (let i = animations.length - 1; i >= 0; i--) {
    const a = animations[i];
    if (a.duration === duration && a.onFinish && !a.done) { a.done = true; a.onFinish(); return a; }
  }
  assert.fail(`no pending ${duration}ms animation`);
}
const last = () => animations[animations.length - 1];
shelf.onActiveShelfGroupChanged();
assert.deepEqual(saved, [], 'initial state restoration must not overwrite the saved group');
shelf.shelfStateRestored = true;
assert.deepEqual(pageBooks('audio'), ['group-a-audio', 'group-b-audio', 'ungrouped'], 'the shelf shows everything');
const shelfPage = shelf.shelfCategoryPage('audio');
const shelfReplaced = () => replaced.filter(key => key === 'entry').length;
const shelfBuilds = shelfReplaced();

// Opening: the group page is built on top of the shelf (all but transparent, small), then both layers zoom.
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, true);
assert.equal(shelf.showShelfGroupMenu || shelf.showShelfMoreMenu || shelf.showShelfFilterMenu, false);
assert.deepEqual([shelf.tileGroupZoomX, shelf.tileGroupZoomY], [90, 255], 'zooms around the tapped folder');
assert.deepEqual(warmed, [7], 'cached covers are swapped in before the group page is built');
assert.equal(shelf.tileGroupLayerGroupId, 7, 'the group layer is mounted');
assert.equal(groupLayerShown(), true);
assert.equal(shelf.shelfPageKey(), 'g7:audio');
assert.deepEqual(pageBooks('g7:audio'), ['group-a-audio'], 'group page preserves category, privacy and filters');
assert.equal(shelf.shelfBaseGroupId(), 0, 'the shelf underneath stays on the whole shelf');
assert.deepEqual(pageBooks('audio'), ['group-a-audio', 'group-b-audio', 'ungrouped'], '...with its own books');
assert.equal(shelf.shelfCategoryPage('audio'), shelfPage, 'same category page object: same scroll position');
assert.equal(shelfReplaced(), shelfBuilds, 'the shelf is not rebuilt');
assert.deepEqual(saved, [7]);
const opening = last();
assert.equal(animations.length, 1, 'one motion only');
assert.equal(opening.duration, 420);
assert.deepEqual(opening.from, { shelfScale: 1, shelfOpacity: 1, pageScale: 0.94, pageOpacity: 0.01 },
  'the group page waits small and all but transparent (still drawn, so its first moving frame is cheap)');
assert.deepEqual(opening.to, { shelfScale: 1.06, shelfOpacity: 0, pageScale: 1, pageOpacity: 1 },
  'the shelf grows and fades while the group page rises');
assert.equal(shelfHidden(), false, 'the shelf stays visible while it zooms out');
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.activeShelfGroupId, 7, 'repeated taps cannot replace a running transition');
complete(420);
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(shelfHidden(), true, 'once still, the shelf is hidden under the group page (kept, not destroyed)');
assert.deepEqual([shelf.tileGroupShelfScale, shelf.tileGroupShelfOpacity], [1, 1], 'reset for the way back');

// Return: the hidden shelf reappears (only laid out) slightly large, then both layers zoom; the group layer goes last.
frameQueue = [];
shelf.exitTileGroupPage();
assert.equal(shelf.activeShelfGroupId, 0, 'the shelf is current again at once');
assert.equal(shelfHidden(), false, 'the shelf is shown again for the way back');
assert.equal(shelf.tileGroupLayerGroupId, 7, 'the group layer stays while it zooms out');
assert.equal(shelf.shelfPageKey(), 'audio');
assert.equal(shelfReplaced(), shelfBuilds, 'nothing to rebuild or scroll back');
assert.equal(animations.length, 1, 'waits for the shelf to be laid out and drawn');
flushFrames();
assert.equal(animations.length, 1);
flushFrames();
frameQueue = null;
const closing = last();
assert.equal(closing.duration, 340);
assert.deepEqual([shelf.tileGroupZoomX, shelf.tileGroupZoomY], [90, 255], 'shrinks back into the folder it came from');
assert.deepEqual(closing.from, { shelfScale: 1.06, shelfOpacity: 0.01, pageScale: 1, pageOpacity: 1 });
assert.deepEqual(closing.to, { shelfScale: 1, shelfOpacity: 1, pageScale: 0.94, pageOpacity: 0 });
complete(340);
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(shelf.tileGroupLayerGroupId, 0, 'the group layer is dropped once everything is still');
assert.equal(shelf.tileGroupPages.size, 0);
assert.equal(shelf.tileGroupHasOrigin, false);
assert.equal(shelf.shelfCategoryPage('audio'), shelfPage);
assert.equal(shelfReplaced(), shelfBuilds, 'the shelf survived the whole round trip untouched');
assert.deepEqual(saved, [7, 0]);

// The group page starts moving only once the covers it mounted have decoded; uncached network covers are not awaited.
frameQueue = [];
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.tileGroupAwaitCovers, true);
shelf.noteTileGroupCoverMounted({ bookUrl: 'group-a-audio' }, 'file://a.jpg', false);
shelf.noteTileGroupCoverMounted({ bookUrl: 'group-a-net' }, 'https://cdn/a.jpg', false);
shelf.noteTileGroupCoverMounted({ bookUrl: 'group-a-sync' }, 'file://b.jpg', true);
assert.deepEqual(Array.from(shelf.tileGroupPendingCovers), ['group-a-audio']);
const before = animations.length;
flushFrames(); flushFrames(); flushFrames(); flushFrames();
assert.equal(animations.length, before, 'still decoding: nothing moves');
shelf.tileGroupPendingCovers.delete('group-a-audio'); // Image.onComplete
flushFrames();
assert.equal(animations.length, before, 'decoded covers get one frame to be drawn');
flushFrames(); flushFrames();
assert.equal(last().duration, 420, 'covers ready: the zoom starts');
assert.equal(shelf.tileGroupAwaitCovers, false);
frameQueue = null;
complete(420);
shelf.exitTileGroupPage(); complete(340);

shelf.consumeShelfSwipeClick = () => true;
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, false, 'a swipe release is not a tap');
shelf.consumeShelfSwipeClick = () => false;

// A folder that cannot be measured zooms around the screen centre; system Back while opening is queued.
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.deepEqual([shelf.tileGroupZoomX, shelf.tileGroupZoomY], [400, 600]);
assert.deepEqual(pageBooks('g8:audio'), ['group-b-audio']);
shelf.onTileGroupBackRequested();
assert.equal(shelf.tileGroupPendingBack, true, 'system Back during opening is queued');
complete(420);
assert.equal(shelf.tileGroupAnimating, true, 'the queued Back runs at once');
complete(340);
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual(saved, [7, 0, 7, 0, 8, 0]);

// Disposed callbacks cannot unlock a newer transition.
shelf.openTileGroupPage(7, 'audio', 90, 220);
const stale = last();
shelf.cancelTileGroupMotion();
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(timers.has(shelf.tileGroupMotionWatchdog), false, 'disposal cancels the watchdog');
assert.equal(shelf.tileGroupLayerGroupId, 7, 'the group page it switched to stays');
shelf.exitTileGroupPage();
stale.onFinish();
assert.equal(shelf.tileGroupAnimating, true, 'a disposed motion cannot finish the newer one');
complete(340);
assert.equal(shelf.activeShelfGroupId, 0);

// A resized window has no valid folder to return to: zoom around the screen centre instead.
shelf.openTileGroupPage(7, 'audio', 90, 220); complete(420);
shelf.updateContextViewport({ width: 1200, height: 800 });
assert.equal(shelf.tileGroupHasOrigin, false, 'resizing invalidates old screen coordinates');
shelf.exitTileGroupPage();
assert.deepEqual([shelf.tileGroupZoomX, shelf.tileGroupZoomY], [600, 400]);
complete(340);
shelf.updateContextViewport({ width: 800, height: 1200 });

// Group menu: opening a group zooms around the screen centre; switching the shelf to "ungrouped" needs no motion,
// and a group opened from there returns to it.
shelf.selectShelfGroup(8);
assert.equal(shelf.tileGroupZoomX, 400);
assert.equal(shelf.activeShelfGroupId, 8);
complete(420);
shelf.exitTileGroupPage(); complete(340);
const motions = animations.length;
shelf.selectShelfGroup(-1);
assert.equal(animations.length, motions, 'the shelf just filters in place');
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(shelf.activeShelfGroupId, -1);
assert.deepEqual(pageBooks('audio'), ['ungrouped']);
shelf.openTileGroupPage(7, 'audio', 90, 220); complete(420);
assert.equal(shelf.shelfBaseGroupId(), -1);
shelf.exitTileGroupPage(); complete(340);
assert.equal(shelf.activeShelfGroupId, -1, 'back where the group was opened from');
shelf.selectShelfGroup(0);
assert.equal(shelf.activeShelfGroupId, 0);

// A lost animation callback cannot lock the shelf: the watchdog finishes anyway.
frameQueue = [];
shelf.openTileGroupPage(7, 'audio', 90, 220);
runTimer(shelf.tileGroupMotionWatchdog);
frameQueue = null;
assert.equal(shelf.activeShelfGroupId, 7);
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(shelf.tileGroupPageOpacity, 1, 'the group page is fully shown');
shelf.exitTileGroupPage(); complete(340);

// Restoring straight into a group page (no motion) mounts its layer over the whole shelf; switching to a list layout
// turns the group back into a shelf filter and the layer stops showing.
shelf.activeShelfGroupId = 7;
assert.equal(shelf.tileGroupLayerGroupId, 7);
assert.equal(shelfHidden(), true);
assert.equal(shelf.shelfBaseGroupId(), 0);
shelf.bookshelfLayoutMode = 'list';
assert.equal(groupLayerShown(), false);
assert.equal(shelf.isTileGroupPage(), false);
shelf.bookshelfLayoutMode = 'companion';
shelf.activeShelfGroupId = 0;
assert.equal(shelf.tileGroupLayerGroupId, 0);

// Covers never load synchronously from the network: that would download on the UI thread.
assert.equal(shelf.shelfCoverSyncLoad('file://cover.jpg', true), true);
assert.equal(shelf.shelfCoverSyncLoad('https://cdn/cover.jpg', true), false);

// The backdrop is mounted once under both layers; remounting it around the motion made it flash.
assert.doesNotMatch(source, /tileGroupBareBody|tileGroupMotionBackground|tileGroupBackgroundLayer/);
assert.equal((source.match(/HomeThemeBackdrop\(/g) || []).length, 1, 'one shelf backdrop only');
assert.doesNotMatch(source, /tileGroupCurtain|swapTileGroupPage|returnToTileGroupShelf|tileGroupRootPages|flyIntoTileGroup|TileGroupPreviewSource/);
const index = fs.readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.ok(index.includes("AppStorage.setOrCreate('bookshelfGroupBackRequest'"));
console.log('PASS tile group motion: group page layered over a kept shelf, zoom around the folder, no shelf rebuild, covers ready first, back during opening, stale callbacks, resize, menu switching, restore, layout switch and watchdog');
