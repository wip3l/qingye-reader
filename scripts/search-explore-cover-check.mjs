// node scripts/search-explore-cover-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const readyTimers = [];
const flushReady = () => readyTimers.splice(0).forEach(fn => fn());
let storedCover = () => ({ fallback: 'text' });
const context = vm.createContext({ console, Book: class { customCoverUrl = ''; }, CoverGallerySnapshot: class {},
  CoverGalleryStore: { fallbackFromStorage: () => storedCover().fallback, snapshotFromStorage: () => storedCover() },
  setTimeout: fn => readyTimers.push(fn), clearTimeout: () => {},
  ThemeRuntime: { bookTokens: dark => ({ coverAssetId: dark ? 'dark' : 'light', shelfFrameAssetId: 'frame' }) },
  ThemeAssetRegistry: { themeBookCovers: id => [{ id: `${id}-1` }, { id: `${id}-2` }], themeShelfFrame: () => ({ id: 'frame' }) }
});
for (const file of ['utils/CoverUrlNormalizer.ts', 'utils/CoverFailures.ts', 'utils/BookDisplayHelper.ets', 'utils/CoverGallerySettings.ets', 'utils/ThemeBookCoverSettings.ets']) {
  const source = read(file).replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
  vm.runInContext(stripTypeScriptTypes(source), context);
}
const source = read('components/book/BookCover.ets');
function method(name) {
  const start = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const cover = vm.runInContext(stripTypeScriptTypes(`({${[
  'coverBook', 'rawCoverList', 'refreshCovers', 'resolveDisplayCovers', 'clearCoverRetries', 'activeCover', 'isActiveCoverReady', 'notifyReadyCover', 'markLoaded', 'loadShelfBook', 'onBookChanged', 'onPreparedSelectionChanged'
].map(method).join(',')}})`), context);
Object.assign(cover, {
  bookUrl: 'book-1', origin: 'source', coverUrl: 'source.jpg', shelfBook: null,
  useBookshelfCover: true, appDarkMode: false, applyScope: 'all', targetBooks: '', themeCoverEnabled: false,
  replaceAlbum: true, albumMix: true, fallback: 'text', coverMode: 'sequence', lightAlbum: 'light', darkAlbum: 'dark',
  albums: JSON.stringify([{ id: 'light', covers: ['light-1.jpg', 'light-2.jpg'] }, { id: 'dark', covers: ['dark.jpg'] }]),
  covers: [], displayCovers: [], coverLoadSerial: 0, retryTimers: new Map(), retryCounts: new Map(), activeIndex: 0, loadedRevision: 0, loadedUrls: new Set(), mounted: true,
  imageCover: raw => raw, readyTimer: -1, readyPending: '', readyNotified: null, onReadyCover() {}
});
// 封面组件的设置来自全局存储，这里让存储读到的就是组件上的值。
storedCover = () => ({ albumsRaw: cover.albums, lightAlbumId: cover.lightAlbum, darkAlbumId: cover.darkAlbum,
  applyScope: cover.applyScope, targetBooksRaw: cover.targetBooks, coverMode: cover.coverMode,
  replaceAlbum: cover.replaceAlbum, albumMix: cover.albumMix, fallback: cover.fallback });
const list = () => Array.from(cover.rawCoverList());
assert.deepEqual(list(), ['source.jpg', 'light-1.jpg', 'light-2.jpg'], 'source and album follow shelf ordering');
const customBook = { bookUrl: 'book-1', coverUrl: 'shelf-source.jpg', customCoverUrl: '["custom-1.jpg","custom-2.jpg"]' };
const plainBook = { bookUrl: 'book-1', coverUrl: 'shelf-source.jpg', customCoverUrl: '' };
const coverlessBook = { bookUrl: 'book-1', coverUrl: '', customCoverUrl: '' };
cover.shelfBook = customBook;
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg'], 'a per-book cover wins over the album');
cover.shelfBook = plainBook;
assert.deepEqual(list(), ['shelf-source.jpg', 'light-1.jpg', 'light-2.jpg'], 'own cover and album rotate together');
cover.albumMix = false;
assert.deepEqual(list(), ['light-1.jpg', 'light-2.jpg'], 'album replaces the own cover');
cover.appDarkMode = true;
assert.deepEqual(list(), ['dark.jpg']);
cover.applyScope = 'books'; cover.targetBooks = '["other-book"]';
assert.deepEqual(list(), ['shelf-source.jpg'], 'books outside the album scope keep their own cover');
cover.targetBooks = '["book-1"]'; cover.albumMix = true;
assert.deepEqual(list(), ['shelf-source.jpg', 'dark.jpg']);
cover.coverMode = 'random';
const random = list();
assert.equal(random.length, 1);
assert.deepEqual(random, list(), 'random selection stable for same book/time');
cover.useBookshelfCover = false;
assert.deepEqual(list(), ['source.jpg'], 'switch off restores result source cover');
cover.useBookshelfCover = true; cover.coverMode = 'sequence'; cover.darkAlbum = '';
assert.deepEqual(list(), ['shelf-source.jpg'], 'missing album falls through to the own cover');
cover.darkAlbum = 'dark'; cover.applyScope = 'all'; cover.replaceAlbum = false;
assert.deepEqual(list(), ['shelf-source.jpg'], 'no unified cover: own cover');
cover.shelfBook = coverlessBook;
assert.deepEqual(list(), [], 'coverless book without a fallback shows the title placeholder');
cover.fallback = 'album';
assert.deepEqual(list(), ['dark.jpg'], 'album only fills in for coverless books');
cover.shelfBook = plainBook;
assert.deepEqual(list(), ['shelf-source.jpg'], 'the fallback leaves books with a cover alone');
// 封面地址在、图取不到：当作没有封面走兜底；记录过期或取到后恢复原封面。
const failures = vm.runInContext('CoverFailures', context);
const day = 24 * 60 * 60 * 1000;
assert.equal(failures.mark('shelf-source.jpg'), true);
assert.equal(failures.mark('shelf-source.jpg'), false, 'marking again is not a change');
assert.deepEqual(list(), ['dark.jpg'], 'a cover that cannot be fetched falls back like a missing one');
cover.shelfBook = customBook;
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg']);
failures.mark('custom-1.jpg');
assert.deepEqual(list(), ['custom-2.jpg'], 'only the unusable per-book cover is dropped');
failures.mark('custom-2.jpg');
assert.deepEqual(list(), ['dark.jpg'], 'no usable per-book or own cover: fallback');
assert.equal(vm.runInContext('BookDisplayHelper', context).hasCustomCover(customBook), false);
assert.equal(vm.runInContext('BookDisplayHelper', context).decodeCoverList(customBook.customCoverUrl).length, 2,
  'the editing list still shows every configured cover');
const saved = failures.serialize();
assert.equal(failures.has('shelf-source.jpg', Date.now() + 3 * day), false, 'records expire so the cover is retried');
const urls = ['shelf-source.jpg', 'custom-1.jpg', 'custom-2.jpg'];
for (const url of urls) assert.equal(failures.clear(url), true);
failures.load(saved, Date.now() + 3 * day);
assert.equal(failures.has('custom-1.jpg'), false, 'expired records are dropped on load');
failures.load(saved);
assert.equal(failures.has('custom-1.jpg'), true, 'records survive a restart');
failures.load('not json');
assert.equal(failures.has('custom-1.jpg'), true, 'a broken file keeps what is already known');
for (const url of urls) assert.equal(failures.clear(url), true);
assert.deepEqual(list(), ['custom-1.jpg', 'custom-2.jpg'], 'a cover that loads again is used again');
cover.shelfBook = plainBook;
assert.deepEqual(list(), ['shelf-source.jpg']);
cover.fallback = 'theme';
cover.refreshCovers();
assert.equal(cover.themeCover, false, 'theme fallback leaves books with a cover alone');
cover.shelfBook = coverlessBook;
cover.refreshCovers();
assert.equal(cover.themeCover, true, 'coverless book falls back to the theme cover');
assert.equal(cover.themeFrame.id, 'frame');
cover.fallback = 'text'; cover.replaceAlbum = true; cover.albumMix = true;
cover.shelfBook = customBook;
const ready = [];
cover.onReadyCover = url => ready.push(url);
cover.refreshCovers();
flushReady();
assert.equal(ready.at(-1), '');
cover.markLoaded('custom-1.jpg');
flushReady();
assert.equal(ready.at(-1), 'custom-1.jpg');
cover.activeIndex = 1; cover.notifyReadyCover();
flushReady();
assert.equal(ready.at(-1), '', 'unloaded next slide does not reuse previous backdrop');
cover.markLoaded('custom-2.jpg');
flushReady();
assert.equal(ready.at(-1), 'custom-2.jpg');
cover.useBookshelfCover = false; cover.refreshCovers();
assert.equal(cover.activeIndex, 0, 'switch resets carousel selection');
cover.themeCoverEnabled = true;
cover.refreshCovers();
assert.deepEqual(Array.from(cover.covers), ['source.jpg'], 'disabled setting does not apply theme covers');
cover.useBookshelfCover = true;
cover.refreshCovers();
assert.deepEqual(Array.from(cover.covers), ['custom-1.jpg', 'custom-2.jpg'], 'a per-book cover wins over the theme cover');
cover.shelfBook = plainBook;
cover.refreshCovers();
assert.equal(cover.covers.length, 2);
assert(cover.covers.every(item => item.id.startsWith('dark-')), 'theme covers override source and gallery like shelf');
assert.equal(cover.themeFrame.id, 'frame');
assert(cover.interval >= 3200 && cover.interval <= 4880);
cover.markLoaded(cover.covers[0]);
flushReady();
assert.equal(ready.at(-1).id, cover.covers[0].id, 'theme Resource covers drive backdrop too');
cover.themeCoverEnabled = false;
cover.refreshCovers();
assert.equal(cover.themeFrame, '');
assert.equal(cover.interval, 3500);

// Late shelf lookups must not apply another book's custom cover to a reused result cell.
let resolveShelf;
Object.assign(context, {
  getContext: () => ({}),
  AppDatabase: { getInstance: () => ({ initWithContext: async () => {} }) },
  BookIdentity: { keyOfUrl: url => url, keyOfBook: book => book.bookUrl, workKeyOf: () => '' },
  SearchBookShelfHelper: { findShelfBookByKey: () => new Promise(resolve => { resolveShelf = resolve; }) }
});
cover.requestSerial = 1;
const lateLoad = cover.loadShelfBook(1);
for (let i = 0; i < 5; i++) await Promise.resolve();
cover.requestSerial = 2;
const currentShelfBook = cover.shelfBook;
resolveShelf({ bookUrl: 'old-book', customCoverUrl: 'old-cover.jpg' });
await lateLoad;
assert.equal(cover.shelfBook, currentShelfBook);

// Visible result covers share one database fetch; a late old snapshot cannot overwrite new shelf settings.
let version = 1;
const pendingReads = [];
context.AppStorage = { get: () => version };
context.AppDatabase = { getInstance: () => ({ getAllBooks: () => new Promise(resolve => pendingReads.push(resolve)) }) };
const helperSource = read('utils/SearchBookShelfHelper.ets').replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
vm.runInContext(stripTypeScriptTypes(helperSource), context);
const helper = vm.runInContext('SearchBookShelfHelper', context);
const first = helper.getShelfLookup();
const shared = helper.getShelfLookup();
assert.equal(pendingReads.length, 1, 'one query for concurrent cover loads');
version = 2;
const latest = helper.getShelfLookup();
assert.equal(pendingReads.length, 2);
pendingReads[1]([{ bookUrl: 'new-book' }]);
await latest;
pendingReads[0]([{ bookUrl: 'old-book' }]);
assert((await first).has('new-book'));
assert((await shared).has('new-book'));
assert(!(await helper.getShelfLookup()).has('old-book'));

// Static surfaces (media/cards/LAN) select from exactly the same gallery/theme rules.
let themeEnabled = false;
const settings = { albumsRaw: cover.albums, lightAlbumId: 'light', darkAlbumId: 'dark',
  applyScope: 'all', targetBooksRaw: '', replaceAlbum: true, albumMix: true, fallback: 'text', coverMode: 'sequence' };
context.AppStorage = { get: key => key === 'appThemeBookCoverEnabled' ? themeEnabled : false };
context.CoverGalleryStore = { snapshotFromStorage: () => settings, fallbackFromStorage: () => settings.fallback };
let writes = 0, closed = 0, exists = false, failWrite = false, storedBytes;
context.fs = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  open: async () => ({ fd: 5 }), access: async () => exists,
  write: async (_fd, buffer) => { writes++; if (failWrite) throw Error('disk'); storedBytes = new Uint8Array(buffer); exists = true; },
  close: async () => { closed++; }
};
context.BookCoverCache = { prepareCoverFile: async (_ctx, url) => 'cached:' + url };
vm.runInContext(stripTypeScriptTypes(read('utils/BookCoverResolver.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ')), context);
const resolver = vm.runInContext('BookCoverResolver', context);
const nativeBook = { bookUrl: 'book-1', name: 'Book', author: 'Author', coverUrl: 'source.jpg', customCoverUrl: 'custom.jpg' };
const nativePlain = { bookUrl: 'book-1', name: 'Book', author: 'Author', coverUrl: 'source.jpg', customCoverUrl: '' };
const nativeCoverless = { bookUrl: 'book-1', name: 'Book', author: 'Author', coverUrl: '', customCoverUrl: '' };
assert.equal(resolver.first(nativeBook, false), 'custom.jpg');
settings.albumMix = false;
assert.equal(resolver.first(nativePlain, true), 'dark.jpg');
settings.applyScope = 'books'; settings.targetBooksRaw = '["other"]';
assert.equal(resolver.first(nativePlain, false), 'source.jpg', 'books outside the album scope keep their own cover');
assert.equal(resolver.first(nativeCoverless, false), '');
settings.fallback = 'theme';
assert(resolver.first(nativeCoverless, true).id.startsWith('dark-'), 'static surfaces use the theme fallback too');
assert.equal(resolver.first(nativePlain, true), 'source.jpg');
settings.fallback = 'text';
themeEnabled = true;
assert.equal(resolver.first(nativeBook, true), 'custom.jpg');
assert(resolver.first(nativePlain, true).id.startsWith('dark-'));
assert.equal(resolver.first(null, true), '');
const fileContext = { cacheDir: '/cache', resourceManager: { getMediaContent: async () => new Uint8Array([9, 1, 2, 3, 9]).subarray(1, 4) } };
assert.equal(await resolver.prepareFile(fileContext, ''), '');
assert.equal(await resolver.prepareFile(fileContext, 'source.jpg'), 'cached:source.jpg');
const files = await Promise.all([resolver.prepareFile(fileContext, { id: 7 }), resolver.prepareFile(fileContext, { id: 7 })]);
assert.equal(files[0], files[1]);
assert.equal(writes, 1, 'concurrent media/card requests write the theme resource once');
assert.deepEqual(Array.from(storedBytes), [1, 2, 3], 'respect byte offset and length');
exists = false;
await resolver.prepareFile(fileContext, { id: 7 });
assert.equal(writes, 2, 'recreate file after cache clearing');
failWrite = true;
await assert.rejects(resolver.prepareFile(fileContext, { id: 8 }));
failWrite = false;
await resolver.prepareFile(fileContext, { id: 8 });
assert.equal(closed, 4, 'close files even on failure; failed writes can retry');

// The same resolver powers both result layouts and the detail page; saved preference key is preserved.
const results = read('components/book/SearchBookResultList.ets');
assert(results.includes('BookCover({'));
assert(results.includes('this.resultCover(key, 8, 360, 480)'));
assert(results.includes('this.resultCover(key, 6, 180, 240)'));
assert(read('pages/SearchBookDetail.ets').includes('BookCover({'));
assert(read('pages/SearchExploreSettings.ets').includes("title: '使用书架封面'"));
assert(read('pages/SearchExploreSettings.ets').includes("@StorageLink('searchExploreUseBookshelfCoverGallery')"));
assert(read('pages/CoverSettings.ets').includes("@StorageLink('searchExploreUseBookshelfCoverGallery')"));
for (const path of ['components/reader/ReaderTocPanel.ets', 'components/TtsCatalogSheet.ets',
  'components/ReaderTtsPlayerPanel.ets', 'pages/ReadingStats.ets', 'pages/AudioBook.ets', 'pages/OpdsBrowse.ets']) {
  assert(read(path).includes('BookCover({'), `${path} uses the shared cover component`);
}
cover.preparedSelection = { firstImage: 'file:///prepared', covers: ['file:///prepared', 'album-next.jpg'], frame: 'file:///frame', interval: 4000 };
cover.loadShelfBook = () => { throw Error('prepared results must not restart shelf lookup'); };
cover.onBookChanged();
assert.equal(cover.activeCover(), 'file:///prepared');
assert.equal(cover.isActiveCoverReady(), true, 'prepared first image is ready before the result is painted');
assert.equal(cover.themeFrame, 'file:///frame');
assert.equal(cover.interval, 4000);
cover.preparedSelection = { firstImage: '', covers: [], frame: '', interval: 3500 };
cover.onPreparedSelectionChanged();
assert.equal(cover.covers.length, 0, 'confirmed missing cover stays a final fallback instead of restarting network loading');
console.log('PASS shared covers: source/custom/theme/albums, prepared first paint, scope, modes, backdrop, stale loads, shared lookup, static surfaces, resource file caching/retry');
