// Execute category selection, data-source updates and animation completion races from production code.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const source = readEtsModule('components/home/BookshelfPage.ets');
const compile = code => stripTypeScriptTypes(code.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''));
const names = ['setShelfPage', 'applyShelfScope', 'refreshShelfTypeTabs', 'booksForShelfScope', 'isInShelfView',
  'matchesShelfGroup', 'shelfBookType', 'activeShelfTypeTab', 'shelfPageKey', 'shelfPageOrder', 'isTileLayout', 'isCompanionLayout',
  'switchShelfScopeBySelection', 'canSelectShelfPage', 'shelfCategoryPage', 'markShelfScopePanGesture', 'clearShelfScopeTransition', 'shelfBookViewPrefix', 'shelfBookRenderKey',
  'shelfScopeTabIndex', 'shelfScopeTabHighlighted', 'onPrivateShelfEnabledChanged', 'showsShelfScopeTabs',
  'toggleShelfPrivateByHeaderDoubleTap', 'shelfBaseGroupId', 'isTileGroupPageKey', 'pageGroupId', 'pageTypeKey',
  'tileGroupPageKey'];
const methods = names.map(name => {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join('\n');
const context = vm.createContext({
  Date, console, ListScroller: class {}, Scroller: class {}, Curve: { EaseOut: 'ease-out' }, curves: { springMotion: () => 'spring' },
  SHELF_COVER_INITIAL_PREFETCH_COUNT: 16, BiometricAuth: { isAvailable: () => false },
  BookTypeSupport: { isVideo: b => b.type === 'video', isAudio: b => b.type === 'audio', isImage: b => b.type === 'image' },
  setTimeout() { assert.fail('category selection must not wait on a JS timer'); }, clearTimeout() {}
});
vm.runInContext(compile(readEtsModule('core/book/ShelfDataSources.ets')) + compile(`
class BookshelfPage {
  static TYPE_TAB_IDS = ['all', 'text', 'image', 'audio', 'video'];
  ${methods}
}
globalThis.api = { BookshelfPage, ShelfBookDataSource, ShelfTileEntryDataSource };`), context);
const { BookshelfPage, ShelfBookDataSource, ShelfTileEntryDataSource } = context.api;
const books = [
  { bookUrl: 'novel', type: 'text', isPrivate: false, group: 0 },
  { bookUrl: 'comic', type: 'image', isPrivate: false, group: 0 },
  { bookUrl: 'audio', type: 'audio', isPrivate: false, group: 0 },
  { bookUrl: 'secret', type: 'text', isPrivate: true, group: 0 }
].map(b => ({ ...b, getVariable: () => '' }));

function makeShelf(layout, folders = false) {
  const shelf = new BookshelfPage();
  const finishes = [], warmed = [], updates = { list: 0, tiles: 0, folders: 0 };
  const list = new ShelfBookDataSource(), tiles = new ShelfBookDataSource(), entries = new ShelfTileEntryDataSource();
  for (const [key, data] of [['list', list], ['tiles', tiles], ['folders', entries]]) {
    data.registerDataChangeListener({ onDataReloaded: () => updates[key]++ });
  }
  Object.assign(shelf, {
    allBooks: books, books, shelfScope: 'all', shelfTypeTab: 'all', activeShelfGroupId: 0,
    bookshelfLayoutMode: layout, shelfTypeTabIds: ['all', 'text', 'image', 'audio'],
    bookshelfTypeCategoryEnabled: true, bookshelfShowAllTypeTab: true, bookshelfCompanionStagger: true,
    shelfCategoryPages: new Map(), shelfCategoryRevision: 0, privateShelfRevealed: false,
    privateShelfUnlockDialogSession: { isOpen: () => false }, shelfScopeSwapTimer: -1, shelfScopeFinishTimer: -1, shelfScopeTransitionGeneration: 0,
    shelfScopeSwitchAnimating: false, privateShelfEnabled: true, privateShelfHasPassword: true,
    shelfCoverRenderVersions: new Map(), shelfListBooksSource: list, shelfTileBooksSource: tiles,
    shelfTileEntriesSource: entries, matchesShelfFilters: () => true, matchesShelfSearch: () => true,
    sortBooks: books => books.slice(), shouldUseTileGroupFolders: () => folders,
    getTileBooksWithoutLatest: books => books.slice(), getLatestReadTileBooks: () => [],
    getSortedTileRootEntries: books => books.map(book => ({ key: book.bookUrl, book })),
    ensureShelfBookCoverCache: book => warmed.push(book.bookUrl),
    refreshShelfCoverCache() { assert.fail('category changes must preserve in-flight cover tasks'); },
    reloadShelfDataSources() { assert.fail('category changes must not rebuild inactive layouts'); },
    isTileGroupPage: () => false, isBookMultiSelect: false, unlockRequests: 0, privateLayerMoves: [],
    privateShelfBiometric: false, privateShelfBiometricPending: false, privateShelfBiometricQueued: false,
    animatePrivateShelfLayer(enter) { this.privateLayerMoves.push(enter); },
    openPrivateShelfUnlockDialog() { this.unlockRequests++; },
    getUIContext: () => ({ animateTo: (options, update) => {
      update();
      if (options.onFinish) finishes.push(options.onFinish);
    } })
  });
  return { shelf, finishes, warmed, updates, list, tiles, entries };
}

for (const [layout, folders, active] of [['compact', false, 'list'], ['loose', false, 'list'],
  ['tile', false, 'tiles'], ['tile', true, 'folders']]) {
  const { shelf, finishes, warmed, updates } = makeShelf(layout, folders);
  shelf.switchShelfScopeBySelection('text');
  assert.equal(shelf.shelfPageKey(), 'text', 'content changes in the selection turn');
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['novel']);
  assert.equal(shelf.shelfScopeTabIndex(), 1, 'indicator and results select the same page');
  const novelPage = shelf.shelfCategoryPage('text');
  const sourceKey = active === 'list' ? 'listSource' : active === 'tiles' ? 'tileSource' : 'entrySource';
  let reloads = 0;
  novelPage[sourceKey].registerDataChangeListener({ onDataReloaded() { reloads++; } });
  novelPage.listOffset = 320;
  shelf.switchShelfScopeBySelection('image');
  shelf.switchShelfScopeBySelection('audio');
  assert.equal(shelf.shelfPageKey(), 'audio', 'rapid taps retain the latest destination');
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['audio']);
  assert.deepEqual(Array.from(novelPage.books, b => b.bookUrl), ['novel'], 'outgoing page keeps independent content');
  assert.notEqual(novelPage.listScroller, shelf.shelfCategoryPage('audio').listScroller);
  shelf.switchShelfScopeBySelection('text');
  assert.equal(shelf.shelfCategoryPage('text'), novelPage);
  assert.equal(novelPage.listOffset, 320);
  assert.equal(reloads, 0, 'warm page selection does not rebuild its data source');
  assert.ok(!shelf.shelfPageOrder().includes('private'), 'the private shelf is never a swipe page');
  shelf.switchShelfScopeBySelection('private');
  assert.equal(shelf.shelfPageKey(), 'text', 'selection cannot reach the private shelf');
  shelf.toggleShelfPrivateByHeaderDoubleTap();
  assert.equal(shelf.unlockRequests, 1);
  assert.equal(shelf.shelfCategoryPage('private').books.length, 0, 'locked private shelf never renders its books');
  assert.equal(shelf.shelfPageKey(), 'text');
  shelf.privateShelfHasPassword = false;
  shelf.toggleShelfPrivateByHeaderDoubleTap();
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['secret']);
  assert.equal(shelf.shelfScopeTabHighlighted(), false);
  shelf.toggleShelfPrivateByHeaderDoubleTap();
  assert.equal(shelf.shelfPageKey(), 'text', 'double tap inside returns to the previous category');
  assert.deepEqual(Array.from(shelf.privateLayerMoves), [true, false], 'entering and leaving animate the private layer');
  shelf.toggleShelfPrivateByHeaderDoubleTap();
  shelf.privateShelfEnabled = false;
  shelf.onPrivateShelfEnabledChanged();
  assert.ok(shelf.books.every(b => !b.isPrivate), 'disabling privacy removes private content immediately');
  shelf.matchesShelfFilters = () => false;
  shelf.switchShelfScopeBySelection('all');
  assert.equal(shelf.books.length, 0, 'empty filtered categories do not retain old data');
}

{
  // 书架设置：关闭“显示全部分类”时分类栏去掉“全部”，选中的“全部”落到第一个有书的类型。
  const { shelf } = makeShelf('tile');
  shelf.bookshelfShowAllTypeTab = false;
  shelf.applyShelfScope(false);
  assert.deepEqual(Array.from(shelf.shelfTypeTabIds), ['text', 'image', 'audio'], 'hiding "all" keeps only present types');
  assert.equal(shelf.shelfPageKey(), 'text', 'the "all" selection falls back to the first type');
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['novel']);
  shelf.allBooks = [];
  shelf.applyShelfScope(false);
  assert.deepEqual(Array.from(shelf.shelfTypeTabIds), ['all'], 'an empty shelf still has one page');
  // 关闭“书籍分类”：只有“全部”一页、没有分类栏，所有类型平铺。
  shelf.allBooks = books;
  shelf.bookshelfShowAllTypeTab = true;
  shelf.shelfTypeTab = 'audio';
  shelf.bookshelfTypeCategoryEnabled = false;
  shelf.applyShelfScope(false);
  assert.deepEqual(Array.from(shelf.shelfTypeTabIds), ['all']);
  assert.deepEqual(Array.from(shelf.shelfPageOrder()), ['all'], 'the private shelf is entered by double tap only');
  assert.equal(shelf.shelfPageKey(), 'all');
  assert.equal(shelf.showsShelfScopeTabs(), false, 'no category bar without categories');
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['novel', 'comic', 'audio']);
  shelf.bookshelfTypeCategoryEnabled = true;
  shelf.applyShelfScope(false);
  assert.equal(shelf.shelfPageKey(), 'audio', 'turning categories back on restores the chosen type');
}

const { shelf } = makeShelf('tile');
const key = book => shelf.shelfBookRenderKey(book, shelf.shelfBookViewPrefix('tile'));
const before = key(books[0]);
shelf.shelfTypeTab = 'text';
shelf.shelfFilterKeys = 'local';
assert.equal(key(books[0]), before, 'common books keep node identity across category/filter changes');
books[0].durChapterIndex = 8;
assert.notEqual(key(books[0]), before, 'reading progress still refreshes a retained book');
const publicKey = key(books[0]);
shelf.shelfScope = 'private';
assert.notEqual(key(books[0]), publicKey, 'private and public nodes remain isolated');
// The page body is a Column: an in-flow private layer would be laid out under the category pager, off screen.
const privateLayer = source.slice(source.indexOf('if (this.privateShelfLayerMounted) {'));
assert.match(privateLayer.slice(0, privateLayer.indexOf('.hitTestBehavior(')), /\.position\(\{ x: 0, y: 0 \}\)/,
  'the private shelf layer overlays the category pager');
console.log('PASS shelf native pages: immediate and rapid selections, native completion races, active-layout updates, cover reuse, empty results and privacy gates');
