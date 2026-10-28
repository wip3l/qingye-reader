// Execute category selection, data-source updates and animation completion races from production code.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const source = readEtsModule('components/home/BookshelfPage.ets');
const compile = code => stripTypeScriptTypes(code.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''));
const names = ['setShelfPage', 'applyShelfScope', 'refreshShelfTypeTabs', 'booksForShelfScope', 'isInShelfView',
  'matchesShelfGroup', 'shelfBookType', 'shelfPageKey', 'shelfPageOrder', 'isTileLayout',
  'switchShelfScopeBySelection', 'canSelectShelfPage', 'shelfCategoryPage', 'markShelfScopePanGesture', 'clearShelfScopeTransition', 'shelfBookViewPrefix', 'shelfBookRenderKey',
  'shelfScopeTabIndex', 'shelfScopeTabHighlighted', 'onPrivateShelfEnabledChanged'];
const methods = names.map(name => {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join('\n');
const context = vm.createContext({
  Date, console, ListScroller: class {}, Scroller: class {}, Curve: { EaseOut: 'ease-out' }, curves: { springMotion: () => 'spring' },
  SHELF_COVER_INITIAL_PREFETCH_COUNT: 16,
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
    shelfCategoryPages: new Map(), shelfCategoryRevision: 0, privateShelfRevealed: false,
    privateShelfUnlockDialogSession: { isOpen: () => false }, shelfScopeSwapTimer: -1, shelfScopeFinishTimer: -1, shelfScopeTransitionGeneration: 0,
    shelfScopeSwitchAnimating: false, privateShelfEnabled: true, privateShelfHasPassword: true,
    shelfCoverRenderVersions: new Map(), shelfListBooksSource: list, shelfTileBooksSource: tiles,
    shelfTileEntriesSource: entries, matchesShelfFilters: () => true, matchesShelfSearch: () => true,
    sortBooks: books => books.slice(), shouldUseTileGroupFolders: () => folders,
    getTileBooksWithoutLatest: books => books.slice(),
    getSortedTileRootEntries: books => books.map(book => ({ key: book.bookUrl, book })),
    ensureShelfBookCoverCache: book => warmed.push(book.bookUrl),
    refreshShelfCoverCache() { assert.fail('category changes must preserve in-flight cover tasks'); },
    reloadShelfDataSources() { assert.fail('category changes must not rebuild inactive layouts'); },
    isTileGroupPage: () => false, isBookMultiSelect: false, unlockRequests: 0,
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
  shelf.switchShelfScopeBySelection('private');
  assert.equal(shelf.unlockRequests, 1);
  assert.equal(shelf.shelfCategoryPage('private').books.length, 0, 'locked neighbor never renders private books');
  assert.equal(shelf.shelfPageKey(), 'text');
  shelf.privateShelfHasPassword = false;
  shelf.switchShelfScopeBySelection('private');
  assert.deepEqual(Array.from(shelf.books, b => b.bookUrl), ['secret']);
  assert.equal(shelf.shelfScopeTabHighlighted(), false);
  shelf.privateShelfEnabled = false;
  shelf.onPrivateShelfEnabledChanged();
  assert.ok(shelf.books.every(b => !b.isPrivate), 'disabling privacy removes private content immediately');
  shelf.matchesShelfFilters = () => false;
  shelf.switchShelfScopeBySelection('all');
  assert.equal(shelf.books.length, 0, 'empty filtered categories do not retain old data');
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
console.log('PASS shelf native pages: immediate and rapid selections, native completion races, active-layout updates, cover reuse, empty results and privacy gates');
