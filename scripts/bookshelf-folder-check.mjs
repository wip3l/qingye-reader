// Tile groups open as an in-shelf page that grows out of the tapped folder card and shrinks back into it.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const names = ['openTileGroupPage', 'selectShelfGroup', 'onActiveShelfGroupChanged', 'exitTileGroupPage',
  'isTileLayout', 'isTileGroupPage', 'activeShelfGroupName', 'applyShelfScope', 'refreshShelfTypeTabs',
  'activeShelfTypeTab', 'booksForShelfScope', 'isInShelfView', 'matchesShelfGroup', 'shelfBookType',
  'shouldUseTileGroupFolders', 'reloadShelfDataSources', 'tileGroupElementId', 'changeTileGroup',
  'beginTileGroupMotion', 'enterTileGroup', 'animateTileGroupIn', 'leaveTileGroupPage', 'animateTileGroupOut',
  'afterTileGroupFrames', 'placeTileGroupMotion', 'leadTileGroupIn', 'interpolateTileGroupBounds',
  'collapseTileGroupToCard', 'landTileGroupOnCard', 'tileGroupShelfShotKeyNow', 'dropTileGroupShelfShot',
  'resetTileGroupMotionTransform', 'applyTileGroupTarget', 'scheduleTileGroupStart', 'snapshotTileGroupElement',
  'releaseTileGroupShot', 'finishTileGroupMotion', 'clearTileGroupMotionLayers', 'cancelTileGroupMotion',
  'onTileGroupBackRequested', 'getTileGroupBooks', 'getTileGroupPreviewBooks', 'updateContextViewport', 'areaDimension',
  'tileGroupPreviewCoverId', 'tileGroupFlyValue', 'measureTileGroupRect', 'captureTileGroupPreviewSources',
  'measureTileGroupPageCover', 'makeTileGroupFlyer', 'mountTileGroupFlyers', 'openTileGroupFlyers',
  'closeTileGroupFlyers', 'shelfCoverScope', 'shelfCoverElementId'];
const methods = names.map(name => {
  const plain = source.indexOf(`  ${name}(`);
  const at = plain >= 0 ? plain : source.indexOf(`  async ${name}(`);
  assert.ok(at >= 0, name);
  return source.slice(at, source.indexOf('\n  }', at) + 4);
}).join('\n');
const saved = [], animations = [], reloads = [], finishes = [], released = [];
const timers = new Map();
let nextTimer = 0;
let snapshotMode = 'ok';
const pending = [];
const context = vm.createContext({
  SHELF_GROUP_MOTION_DURATION: 420, SHELF_GROUP_MOTION_START_CAP: 220, SHELF_GROUP_MOTION_WATCHDOG: 1600,
  SHELF_GROUP_LEAD_DURATION: 220, SHELF_GROUP_LEAD_PROGRESS: 0.3, SHELF_GROUP_EXPAND_DURATION: 300,
  SharedElementBounds: class { constructor(x, y, width, height) { Object.assign(this, { x, y, width, height }); } },
  SHELF_GROUP_CARD_RADIUS: 7, SHELF_GROUP_FRAME_RATE: { min: 60, max: 120, expected: 120 },
  setTimeout(fn, delay) { timers.set(++nextTimer, { fn, delay }); return nextTimer; },
  clearTimeout(id) { timers.delete(id); },
  console, getContext: () => ({}), Curve: { Friction: 'friction', EaseOut: 'ease-out' },
  curves: { cubicBezierCurve: () => 'emphasized' },
  ShelfOpeningIdleStarter: class { constructor(fn) { this.fn = fn; } },
  ShelfGroupNextFrame: class { constructor(next) { this.next = next; } },
  SHELF_GROUP_PREMOUNT_FRAMES: 2,
  BookTypeSupport: { isVideo: b => b.type === 'video', isAudio: b => b.type === 'audio', isImage: b => b.type === 'image' },
  BookshelfStateStore: { saveActiveGroupId: async (_context, groupId) => saved.push(groupId) },
  TileGroupFlyer: class {},
  TileGroupPreviewSource: class { constructor(book, bounds) { this.book = book; this.bounds = bounds; } },
});
// Layout rects (window px == vp here). getRectangleById reports layout positions, not transformed ones.
const rects = {
  bookshelf_motion_root: { x: 0, y: 0, width: 800, height: 1200 },
  [`shelf_group_audio_7_cover_${encodeURIComponent('group-a-audio')}`]: { x: 50, y: 190, width: 40, height: 60 },
  [`shelf_book_cover_audio_${encodeURIComponent('group-a-audio')}`]: { x: 20, y: 110, width: 100, height: 140 }
};
vm.runInContext(stripTypeScriptTypes(`class BookshelfPage {
  static TYPE_TAB_IDS = ['all', 'text', 'image', 'audio', 'video'];
  ${methods}
}
globalThis.Shelf = BookshelfPage;`), context);
const shelf = new context.Shelf();
const dataSource = () => ({ books: [], replace(books, force) { this.books = [...books]; reloads.push(force); } });
const books = [
  { bookUrl: 'group-a-audio', group: 7, type: 'audio' },
  { bookUrl: 'group-a-text', group: 7, type: 'text' },
  { bookUrl: 'group-b-audio', group: 8, type: 'audio' },
  { bookUrl: 'group-a-hidden', group: 7, type: 'audio', isPrivate: true },
  { bookUrl: 'filtered', group: 7, type: 'audio' },
  { bookUrl: 'ungrouped', group: 0, type: 'audio' }
].map(book => ({ isPrivate: false, ...book }));
let shotSerial = 0;
const shot = id => ({ id: `${id}#${++shotSerial}`, release() { released.push(this.id); return Promise.resolve(); } });
Object.assign(shelf, {
  bookshelfLayoutMode: 'tile', bookshelfTypeCategoryEnabled: true, bookshelfShowAllTypeTab: true, shelfScope: 'all', shelfTypeTab: 'audio', shelfTypeTabIds: ['all', 'audio'],
  shelfGroups: [{ groupId: 7, groupName: '分组甲' }, { groupId: 8, groupName: '分组乙' }],
  allBooks: books, books: [], isBookMultiSelect: false, shelfAppliedSearchKeyword: '',
  shelfCategoryRevision: 0, shelfStateRestored: false, shelfScopeSwitchAnimating: false,
  showShelfGroupMenu: true, showShelfMoreMenu: true, showShelfFilterMenu: true,
  shelfListBooksSource: dataSource(), shelfTileBooksSource: dataSource(), shelfTileEntriesSource: dataSource(),
  sortBooks: books => [...books], matchesShelfFilters: book => book.bookUrl !== 'filtered',
  matchesShelfSearch: () => true, getTileBooksWithoutLatest: books => books,
  getSortedTileRootEntries: books => books.map(book => ({ book })),
  shelfComponentActive: true, tileGroupAnimating: false, tileGroupHasOrigin: false,
  tileGroupOriginBounds: { x: 0, y: 0, width: 0, height: 0 }, tileGroupOriginGroupId: 0,
  tileGroupBackdrop: undefined, tileGroupCurtain: undefined, tileGroupCardShot: undefined,
  tileGroupShelfShot: undefined, tileGroupShelfShotKey: '', tileGroupCover: undefined, appDarkMode: false,
  tileGroupFlyers: [], tileGroupFlyProgress: 0, tileGroupHiddenCovers: [], tileGroupPreviewSources: [],
  tileGroupLeadBounds: { x: 0, y: 0, width: 0, height: 0 },
  shouldUseThemeBookCover: () => false, getShelfCoverList: () => ['cover.jpg'], getShelfCover: () => 'cover.jpg',
  imageCover: raw => raw, getBookColor: () => '#000000',
  tileGroupMotionScaleX: 1, tileGroupMotionScaleY: 1, tileGroupMotionTranslateX: 0, tileGroupMotionTranslateY: 0,
  tileGroupMotionRadius: 0, tileGroupCardOpacity: 0, tileGroupScrimOpacity: 0, tileGroupPageOpacity: 1,
  tileGroupPendingBack: false, tileGroupPendingTarget: -1, tileGroupMotionGeneration: 0,
  tileGroupStartTimer: -1, tileGroupMotionWatchdog: -1, tileGroupRootPages: null,
  shelfCategoryPages: new Map([['audio', { tileOffset: 420 }]]), shelfHeaderCollapse: 20,
  contextViewportWidth: 800, contextViewportHeight: 1200,
  captureSharedElementBounds: () => ({ x: 40, y: 180, width: 100, height: 150 }),
  shelfBooksForPage: () => shelf.booksForShelfScope('all'), shelfPageKey: () => 'audio',
  getUIContext: () => ({
    animateTo(options, update) { animations.push(options); update(); if (options.onFinish) finishes.push(options.onFinish); },
    // Frame callbacks fire at once; idle callbacks never do, so motion starts from the cap timer.
    postFrameCallback(callback) { if (callback.next) callback.next(); },
    px2vp: value => value,
    getComponentUtils: () => ({ getRectangleById: id => {
      const rect = rects[id];
      if (!rect) throw new Error(`no component ${id}`);
      return { size: { width: rect.width, height: rect.height }, windowOffset: { x: rect.x, y: rect.y } };
    } }),
    getComponentSnapshot: () => ({ get: id => {
      if (snapshotMode === 'fail') return Promise.reject(new Error('snapshot failed'));
      if (snapshotMode === 'hang') return new Promise(resolve => pending.push(() => resolve(shot(id))));
      return Promise.resolve(shot(id));
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
const settle = () => new Promise(resolve => setImmediate(resolve));
function runTimer(id) { const timer = timers.get(id); assert.ok(timer, `timer ${id}`); timers.delete(id); timer.fn(); }
function start() { runTimer(shelf.tileGroupStartTimer); }
function finish() { assert.ok(finishes.length, 'a finishing animation'); finishes.shift()(); }
// Opens from the card and completes the lead phase; the expansion is left running for the caller to finish.
async function open(id) { shelf.openTileGroupPage(id, 'audio', 90, 220); await settle(); start(); finish(); }
async function back() { shelf.exitTileGroupPage(); await settle(); start(); }
const rootPages = shelf.shelfCategoryPages;
assert.equal(shelf.shouldUseTileGroupFolders(), true);
shelf.onActiveShelfGroupChanged();
assert.deepEqual(saved, [], 'initial state restoration must not overwrite the saved group');
shelf.shelfStateRestored = true;

// Opening: snapshots first; the card snapshot starts growing at once and the page is built beneath it.
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, true);
assert.equal(shelf.activeShelfGroupId, 0, 'the shelf stays put until its snapshot is taken');
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupPendingTarget, 7, 'repeated taps cannot replace a running transition');
await settle();
assert.equal(animations[0].duration, 220, 'the lead motion starts before the page is built');
assert.equal(shelf.isTileGroupPage(), true);
assert.equal(shelf.activeShelfGroupName(), '分组甲');
assert.deepEqual(visible(), ['group-a-audio'], 'group page preserves category, privacy and filters');
assert.equal(shelf.shouldUseTileGroupFolders(), false);
assert.ok(shelf.tileGroupBackdrop && shelf.tileGroupCardShot, 'frozen shelf below, card snapshot on top');
// The page is created at the lead's end pose: 30% of the way from the card to full screen.
assert.equal(shelf.tileGroupMotionScaleX, (100 + 700 * 0.3) / 800);
assert.equal(shelf.tileGroupMotionScaleY, (150 + 1050 * 0.3) / 1200);
assert.equal(shelf.tileGroupMotionTranslateX, 40 * 0.7);
assert.equal(shelf.tileGroupMotionTranslateY, 180 * 0.7);
assert.equal(shelf.tileGroupCardOpacity, 1, 'the card snapshot covers the page while it is built');
assert.notEqual(shelf.shelfCategoryPages, rootPages, 'group and root keep separate scroll controllers');
assert.equal(shelf.shelfHeaderCollapse, 0);
assert.equal(shelf.showShelfGroupMenu || shelf.showShelfMoreMenu || shelf.showShelfFilterMenu, false);
assert.deepEqual(saved, [7]);
assert.ok(reloads.every(Boolean));
assert.deepEqual([...shelf.tileGroupPreviewSources].map(source => source.book.bookUrl), ['group-a-audio'],
  'the 2x2 preview positions are measured at the tap');
start();
assert.equal(animations.length, 1, 'expansion waits for the lead to arrive');
assert.equal(shelf.tileGroupFlyers.length, 0);
finish();
assert.equal(animations[1].duration, 300);
// The preview cover flies from its 2x2 slot (as scaled at the end of the lead) to its spot in the 4-across page.
const [opener] = shelf.tileGroupFlyers;
assert.ok(opener, 'a preview cover flies on its own');
assert.ok(Math.abs(opener.fromX - (28 + 10 * 3.1)) < 1e-9 && Math.abs(opener.fromY - (126 + 10 * 3.1)) < 1e-9);
assert.ok(Math.abs(opener.fromScaleX * opener.width - 40 * 3.1) < 1e-9);
assert.equal(opener.toX, 20);
assert.equal(opener.toY, 110);
assert.ok(Math.abs(opener.toScaleX * opener.width - 100) < 1e-9);
assert.equal(shelf.tileGroupFlyProgress, 1, 'flies with the page expansion');
assert.deepEqual([...shelf.tileGroupHiddenCovers], ['group-a-audio'], 'the page hides its own copy meanwhile');
assert.equal(shelf.tileGroupMotionScaleX, 1);
assert.equal(shelf.tileGroupMotionTranslateY, 0);
assert.equal(shelf.tileGroupCardOpacity, 0, 'the blurry enlarged card fades out early');
finish();
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual([...shelf.tileGroupFlyers], [], 'flying covers hand over to the page when it lands');
assert.deepEqual([...shelf.tileGroupHiddenCovers], []);
assert.equal(shelf.tileGroupBackdrop, undefined, 'the frozen shelf leaves the screen after opening');
assert.ok(shelf.tileGroupShelfShot, '...but is kept for the way back');
assert.ok(shelf.tileGroupCardShot, 'the card snapshot is kept for the way back');

// Return: the live group page shrinks onto the card over the kept shelf snapshot; the shelf is rebuilt after.
const keptShelf = shelf.tileGroupShelfShot;
const animationsBeforeBack = animations.length;
shelf.exitTileGroupPage();
assert.equal(shelf.tileGroupCurtain, undefined, 'no snapshot of the group page is needed');
assert.equal(shelf.tileGroupBackdrop, keptShelf);
assert.equal(animations.length, animationsBeforeBack + 2, 'collapse starts right away');
assert.equal(shelf.activeShelfGroupId, 7, 'the shelf is not rebuilt during the motion');
assert.equal(shelf.tileGroupMotionScaleX, 100 / 800, 'the page lands on the card');
assert.equal(shelf.tileGroupMotionTranslateY, 180);
assert.equal(shelf.tileGroupCardOpacity, 1);
const [closer] = shelf.tileGroupFlyers;
assert.ok(closer, 'the preview cover flies back into its 2x2 slot');
assert.equal(closer.fromX, 20);
assert.equal(closer.toX, 50);
assert.equal(closer.toY, 190);
assert.ok(Math.abs(closer.toScaleX * closer.width - 40) < 1e-9);
assert.equal(animations[animations.length - 1].delay, 210, 'the card snapshot fades in late while covers fly');
finish();
assert.equal(shelf.tileGroupCover, keptShelf, 'the landed frame covers the shelf rebuild');
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.shelfCategoryPages, rootPages);
assert.equal(rootPages.get('audio').tileOffset, 420);
assert.equal(shelf.shelfHeaderCollapse, 20);
assert.deepEqual(visible(), ['group-a-audio', 'group-b-audio', 'ungrouped']);
assert.equal(shelf.tileGroupAnimating, true);
start();
assert.equal(shelf.tileGroupAnimating, false);
assert.equal(shelf.tileGroupCover, undefined);
assert.equal(shelf.tileGroupBackdrop, undefined);
assert.equal(shelf.tileGroupShelfShot, undefined);
for (const [id, timer] of [...timers]) if (timer.delay === 300) runTimer(id);
assert.ok(released.includes(keptShelf.id), 'the kept shelf snapshot is released once');
assert.equal(released.filter(id => id === keptShelf.id).length, 1);
assert.equal(shelf.tileGroupCardShot, undefined);
assert.equal(shelf.tileGroupHasOrigin, false);
assert.equal(shelf.shouldUseTileGroupFolders(), true);
assert.deepEqual(saved, [7, 0]);

shelf.consumeShelfSwipeClick = () => true;
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupAnimating, false, 'a swipe release is not a tap');
shelf.consumeShelfSwipeClick = () => false;

// System Back while opening is queued and runs once the page is open.
await open(8);
assert.deepEqual(visible(), ['group-b-audio']);
shelf.onTileGroupBackRequested();
assert.equal(shelf.tileGroupPendingBack, true, 'system Back during opening is queued');
finish();
assert.equal(shelf.tileGroupAnimating, true, 'the queued Back collapses onto the card');
finish();
assert.equal(shelf.activeShelfGroupId, 0);
start();
assert.equal(shelf.tileGroupAnimating, false);
assert.deepEqual(saved, [7, 0, 8, 0]);

// Disposed callbacks cannot unlock a newer transition.
await open(7);
const staleFinish = finishes.shift();
shelf.cancelTileGroupMotion();
await open(8);
staleFinish();
assert.equal(shelf.tileGroupAnimating, true, 'disposed native callbacks cannot unlock a newer transition');
finish();

// A resized window has no valid card to return to: fade out instead.
shelf.updateContextViewport({ width: 1200, height: 800 });
assert.equal(shelf.tileGroupHasOrigin, false, 'resizing invalidates old screen coordinates');
await back();
assert.equal(shelf.tileGroupPageOpacity, 0, 'resized windows fade instead of collapsing to a stale card');
finish();
shelf.updateContextViewport({ width: 800, height: 1200 });

// Group menu switching has no card: the page fades in.
shelf.selectShelfGroup(8);
assert.equal(shelf.activeShelfGroupId, 8);
assert.equal(shelf.tileGroupPageOpacity, 0);
start(); finish();
assert.equal(shelf.tileGroupPageOpacity, 1);
await back(); finish();

// Snapshots failing still opens the group, just without the card motion.
snapshotMode = 'fail';
shelf.openTileGroupPage(7, 'audio', 90, 220);
await settle();
assert.equal(shelf.activeShelfGroupId, 7);
assert.equal(shelf.tileGroupBackdrop, undefined);
start(); finish();
shelf.exitTileGroupPage();
await settle();
assert.equal(shelf.activeShelfGroupId, 0, 'no curtain snapshot: switch back immediately');
assert.equal(shelf.tileGroupAnimating, false);
snapshotMode = 'ok';

// A snapshot that never resolves cannot lock the shelf: the watchdog switches anyway.
snapshotMode = 'hang';
shelf.openTileGroupPage(7, 'audio', 90, 220);
runTimer(shelf.tileGroupMotionWatchdog);
assert.equal(shelf.activeShelfGroupId, 7);
assert.equal(shelf.tileGroupAnimating, false);
pending.splice(0).forEach(resolve => resolve());
await settle();
assert.equal(shelf.tileGroupBackdrop, undefined, 'late snapshots of an abandoned transition are dropped');
snapshotMode = 'ok';
await back(); finish();

shelf.openTileGroupPage(7, 'audio', 90, 220);
await settle();
shelf.cancelTileGroupMotion();
assert.equal(timers.has(shelf.tileGroupStartTimer), false, 'disposal cancels the first-frame wait');
assert.equal(timers.has(shelf.tileGroupMotionWatchdog), false, 'disposal cancels the watchdog');
assert.equal(shelf.tileGroupAnimating, false);
assert.doesNotMatch(source, /openTileFolder|tileFolderOverlay|bookshelf_folder_open|tileGroupTransitionScale|geometryTransition\(this\.tileGroup/);
const index = fs.readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.ok(index.includes("AppStorage.setOrCreate('bookshelfGroupBackRequest'"));
console.log('PASS tile group motion: grows from and shrinks into the card, isolated scroll state, filters, back during opening, stale callbacks, resize, snapshot failure and disposal');
