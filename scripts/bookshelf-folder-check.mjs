// Tile groups open as an in-shelf page; exercise filtering, persistence and returning to the shelf.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const names = ['openTileGroupPage', 'selectShelfGroup', 'onActiveShelfGroupChanged', 'exitTileGroupPage',
  'isTileLayout', 'isTileGroupPage', 'activeShelfGroupName', 'applyShelfScope', 'refreshShelfTypeTabs',
  'activeShelfTypeTab', 'booksForShelfScope', 'isInShelfView', 'matchesShelfGroup', 'shelfBookType',
  'shouldUseTileGroupFolders', 'reloadShelfDataSources', 'tileGroupElementId', 'beginTileGroupOpen',
  'animateTileGroupChange', 'armTileGroupWatchdog', 'finishTileGroupMotion', 'cancelTileGroupMotion',
  'onTileGroupBackRequested', 'getTileGroupBooks', 'getTileGroupPreviewBooks', 'updateContextViewport', 'areaDimension'];
const methods = names.map(name => {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join('\n');
const saved = [], animations = [], reloads = [], finishes = [];
const timers = new Map();
let nextTimer = 0;
const context = vm.createContext({
  SHELF_GROUP_MOTION_DURATION: 380,
  setTimeout(fn, delay) { timers.set(++nextTimer, { fn, delay }); return nextTimer; },
  clearTimeout(id) { timers.delete(id); },
  console, getContext: () => ({}), Curve: { Friction: 'friction' },
  BookTypeSupport: { isVideo: b => b.type === 'video', isAudio: b => b.type === 'audio', isImage: b => b.type === 'image' },
  BookshelfStateStore: { saveActiveGroupId: async (_context, groupId) => saved.push(groupId) },

});
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
Object.assign(shelf, {
  bookshelfLayoutMode: 'tile', shelfScope: 'all', shelfTypeTab: 'audio', shelfTypeTabIds: ['all', 'audio'],
  shelfGroups: [{ groupId: 7, groupName: '分组甲' }, { groupId: 8, groupName: '分组乙' }],
  allBooks: books, books: [], isBookMultiSelect: false, shelfAppliedSearchKeyword: '',
  shelfCategoryRevision: 0, activeShelfGroupRestored: true, shelfScopeSwitchAnimating: false,
  showShelfGroupMenu: true, showShelfMoreMenu: true, showShelfFilterMenu: true,
  shelfListBooksSource: dataSource(), shelfTileBooksSource: dataSource(), shelfTileEntriesSource: dataSource(),
  sortBooks: books => [...books], matchesShelfFilters: book => book.bookUrl !== 'filtered',
  matchesShelfSearch: () => true, getTileBooksWithoutLatest: books => books,
  getSortedTileRootEntries: books => books.map(book => ({ book })),
  shelfComponentActive: true, tileGroupAnimating: false, tileGroupOriginVisible: false, tileGroupHasOrigin: false,
  tileGroupPendingOpen: 0, tileGroupPendingBack: false, tileGroupMotionGeneration: 0,
  tileGroupOpenTimer: -1, tileGroupMotionWatchdog: -1, tileGroupRootPages: null,
  shelfCategoryPages: new Map([['audio', { tileOffset: 420 }]]), shelfHeaderCollapse: 20,
  contextViewportWidth: 800, contextViewportHeight: 1200,
  captureSharedElementBounds: () => ({ x: 40, y: 180, width: 100, height: 136 }),
  shelfBooksForPage: () => shelf.booksForShelfScope('all'),
  getUIContext: () => ({ animateTo(options, update) { animations.push(options); update(); finishes.push(options.onFinish); } }),
  consumeShelfSwipeClick: () => false
});
let groupId = 0;
Object.defineProperty(shelf, 'activeShelfGroupId', {
  get: () => groupId,
  set(value) { if (groupId !== value) { groupId = value; shelf.onActiveShelfGroupChanged(); } }
});
const visible = () => Array.from(shelf.shelfTileBooksSource.books, book => book.bookUrl);
function runTimer(id) { const timer = timers.get(id); assert.ok(timer); timers.delete(id); timer.fn(); }
function open(id) { shelf.openTileGroupPage(id, 'audio', 90, 220); shelf.beginTileGroupOpen(); runTimer(shelf.tileGroupOpenTimer); }
function finish() { assert.ok(finishes.length); finishes.shift()(); }
const rootPages = shelf.shelfCategoryPages;
assert.equal(shelf.shouldUseTileGroupFolders(), true);
shelf.openTileGroupPage(7, 'audio', 90, 220);
assert.equal(shelf.activeShelfGroupId, 0, 'mount the origin before changing the page');
assert.equal(shelf.tileGroupOriginVisible, true);
assert.deepEqual(Array.from(shelf.tileGroupOriginBooks, b => b.bookUrl), ['group-a-audio']);
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupPendingOpen, 7, 'repeated taps cannot replace an armed transition');
shelf.beginTileGroupOpen();
runTimer(shelf.tileGroupOpenTimer);
assert.equal(shelf.isTileGroupPage(), true);
assert.equal(shelf.activeShelfGroupName(), '分组甲');
assert.deepEqual(visible(), ['group-a-audio'], 'group page preserves category, privacy and filters');
assert.equal(shelf.shouldUseTileGroupFolders(), false);
assert.equal(shelf.tileGroupOriginVisible, false);
assert.notEqual(shelf.shelfCategoryPages, rootPages, 'group and root keep separate scroll controllers');
assert.equal(shelf.shelfHeaderCollapse, 0);
assert.equal(shelf.shelfTypeTab, 'audio');
assert.equal(shelf.showShelfGroupMenu || shelf.showShelfMoreMenu || shelf.showShelfFilterMenu, false);
assert.deepEqual(saved, [7]);
assert.ok(reloads.every(Boolean));
assert.equal(animations[0].duration, 380);
finish();
assert.equal(shelf.tileGroupAnimating, false);
shelf.exitTileGroupPage();
assert.equal(shelf.tileGroupOriginVisible, true, 'reverse transition has a native destination at the original card');
assert.equal(shelf.shelfCategoryPages, rootPages);
assert.equal(rootPages.get('audio').tileOffset, 420);
assert.equal(shelf.shelfHeaderCollapse, 20);
assert.deepEqual(visible(), ['group-a-audio', 'group-b-audio', 'ungrouped']);
finish();
assert.equal(shelf.tileGroupOriginVisible, false);
assert.equal(shelf.shouldUseTileGroupFolders(), true);
assert.deepEqual(saved, [7, 0]);
shelf.consumeShelfSwipeClick = () => true;
shelf.openTileGroupPage(8, 'audio', 90, 220);
assert.equal(shelf.tileGroupPendingOpen, 0);
shelf.consumeShelfSwipeClick = () => false;
open(8);
assert.deepEqual(visible(), ['group-b-audio']);
shelf.onTileGroupBackRequested();
assert.equal(shelf.tileGroupPendingBack, true, 'system Back during opening is queued');
finish();
assert.equal(shelf.activeShelfGroupId, 0);
assert.equal(shelf.tileGroupAnimating, true);
finish();
assert.deepEqual(saved, [7, 0, 8, 0]);
open(7);
const staleFinish = finishes.shift();
shelf.cancelTileGroupMotion();
open(8);
staleFinish();
assert.equal(shelf.tileGroupAnimating, true, 'disposed native callbacks cannot unlock a newer transition');
finish();
shelf.updateContextViewport({ width: 1200, height: 800 });
assert.equal(shelf.tileGroupHasOrigin, false, 'resizing invalidates old screen coordinates');
shelf.exitTileGroupPage();
assert.equal(shelf.tileGroupOriginVisible, false, 'resized windows do not collapse to a stale card');
finish();
// The first-frame callback may never arrive during backgrounding or a layout interruption.
shelf.openTileGroupPage(7, 'audio', 90, 220);
runTimer(shelf.tileGroupMotionWatchdog);
assert.equal(shelf.activeShelfGroupId, 7);
assert.equal(shelf.tileGroupHasOrigin, false);
const completedLate = finishes.shift();
runTimer(shelf.tileGroupMotionWatchdog);
assert.equal(shelf.tileGroupAnimating, false);
completedLate();
shelf.exitTileGroupPage(); finish();
shelf.openTileGroupPage(7, 'audio', 90, 220);
shelf.beginTileGroupOpen();
shelf.cancelTileGroupMotion();
assert.equal(timers.size, 0, 'disposal cancels the first frame and watchdog');
assert.equal(shelf.activeShelfGroupId, 0);
assert.doesNotMatch(source, /openTileFolder|tileFolderOverlay|bookshelf_folder_open|tileGroupTransitionScale/);
const index = fs.readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.ok(index.includes("AppStorage.setOrCreate('bookshelfGroupBackRequest'"));
console.log('PASS tile group shared transitions: paired open/return, isolated scroll state, filters, back during opening, stale callbacks, resize and disposal');
