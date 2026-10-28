// node scripts/result-cover-ready-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';
const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const context = vm.createContext({ console, clearTimeout() {},
  SearchBook: class {}, Book: class { coverUrl = ''; customCoverUrl = ''; }, CoverGallerySnapshot: class {},
  BookIdentity: { keyOfBook: b => `${b.origin}:${b.bookUrl}` },
  CoverUrlNormalizer: { normalize: url => url || '' },
  CoverGallerySettings: { getDisplayCoverList: (_book, _dark, albums, _light, _night, scope, targets) =>
    scope === 'books' && targets !== 'book' ? [] : (albums ? ['album-a', 'album-b'] : []) },
  ThemeBookCoverSettings: { enabled: (_dark, enabled) => enabled, covers: () => ['theme-a', 'theme-b'],
    frame: () => 'frame', interval: () => 3500 },
  AppDatabase: { getInstance: () => ({ initWithContext: async () => {}, getBookSource: async () => ({ bookInfoRule: { coverUrl: 'img' } }) }) },
  SearchBookShelfHelper: { findShelfBookByKey: async () => null,
    keyOf: b => `${b.origin}:${b.bookUrl}`, isInShelf: () => false },
  fileUri: { getUriFromPath: path => `file://${path}` },
  fs: { access: async () => true },
});
let details = 0, files = [], sourcesReleased = 0, pixelsReleased = 0;
context.WebBookService = class { async getBookInfo(_source, book) { details++; return { ...book, coverUrl: 'detail-cover' }; } };
context.BookCoverResolver = { sourceCovers: b => b.coverUrl ? [b.coverUrl] : [],
  prepareFile: async (_ctx, cover) => { files.push(cover); return cover ? `/cache/${cover}` : ''; } };
context.image = { createImageSource: path => ({
  createPixelMap: async () => { if (path.includes('broken')) throw Error('corrupt image'); return { release: async () => { pixelsReleased++; } }; },
  release: async () => { sourcesReleased++; }
}) };
const utility = read('utils/ResultCoverPreparation.ets').replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
vm.runInContext(stripTypeScriptTypes(utility), context);
const prepare = vm.runInContext('ResultCoverPreparation', context);
const Options = vm.runInContext('ResultCoverOptions', context);
const Ready = vm.runInContext('PreparedResultCover', context);
const book = { origin: 'source', bookUrl: 'book', name: '测试书', author: '作者', coverUrl: '' };
let opts = new Options();
opts.useBookshelf = true; opts.themeEnabled = true;
let ready = await prepare.prepare({}, book, opts);
assert.equal(ready.firstImage, 'file:///cache/theme-a');
assert.equal(ready.frame, 'file:///cache/frame');
assert.equal(details, 0, 'theme cover never waits for source detail lookup');
opts.themeEnabled = false; opts.gallery.albumsRaw = 'album';
ready = await prepare.prepare({}, book, opts);
assert.equal(ready.firstImage, 'file:///cache/album-a');
assert.equal(details, 0, 'applicable custom album skips source fetch even if source covers are allowed');
opts.gallery.applyScope = 'books'; opts.gallery.targetBooksRaw = 'other';
ready = await prepare.prepare({}, book, opts);
assert.equal(ready.firstImage, 'file:///cache/detail-cover');
assert.equal(details, 1, 'out-of-scope album respects the configured book selection');
opts = new Options();
const before = files.length;
ready = await prepare.prepare({}, { ...book, coverUrl: 'broken' }, opts);
assert.equal(ready.firstImage, '', 'a URL alone is insufficient: undecodable image becomes final fallback');
assert.equal(files.length, before + 1);
context.AppDatabase.getInstance = () => ({ getBookSource: async () => ({ bookInfoRule: { coverUrl: '' } }) });
ready = await prepare.prepare({}, book, opts);
assert.equal(ready.covers.length, 0);
assert.equal(details, 1, 'no detail cover rule confirms absence without another network request');
assert.equal(sourcesReleased, pixelsReleased + 1, 'decode failures release the source as well; bitmaps are not retained per result');
const albumOptions = new Options();
albumOptions.useBookshelf = true;
context.CoverGallerySettings.getDisplayCoverList = () => ['broken-album'];
ready = await prepare.prepare({}, { ...book, coverUrl: 'source-fallback' }, albumOptions);
assert.equal(ready.firstImage, 'file:///cache/source-fallback', 'broken album falls back to source when allowed');
albumOptions.gallery.ignoreSourceCover = true;
const previousFiles = files.length;
ready = await prepare.prepare({}, { ...book, coverUrl: 'source-fallback' }, albumOptions);
assert.equal(ready.firstImage, '');
assert.ok(!files.slice(previousFiles).includes('source-fallback'), 'explicit ignore-source preference is respected');
opts.showCover = false;
const filesBeforeDisabled = files.length;
await prepare.prepare({}, book, opts);
assert.equal(files.length, filesBeforeDisabled, 'hidden covers need no preparation');

// Exercise the actual component queue with slow, out-of-order and stale completions.
const listSource = read('components/book/SearchBookResultList.ets');
function methods(names) {
  return vm.runInContext(stripTypeScriptTypes(`({${names.map(name => {
    const start = listSource.indexOf(`  ${name}(`); assert.ok(start >= 0, name);
    return listSource.slice(start, listSource.indexOf('\n  }', start) + 4);
  }).join(',')}})`), context);
}
prepare.options = () => ({ showCover: true });
prepare.signature = b => `${b.bookUrl}:${b.coverUrl}`;
const list = methods(['onBooksChanged', 'resultBook', 'itemKey', 'listItemKey', 'safeText', 'requestResultCovers',
  'publishReadyResults', 'drainCoverQueue', 'aboutToDisappear']);
let visible = [], tasks = new Map(), admitted = [];
Object.assign(list, { books: [], resultBooks: new Map(), readyCoverUrls: new Map(), tagCache: new Map(),
  preparedCovers: new Map(), preparedSignatures: new Map(), pendingCovers: new Map(), runningCovers: new Set(),
  activeCoverTasks: 0, coverGeneration: 0, coverMounted: true, gridPageActive: true, layoutMode: 'grid',
  shelfBookKeys: [], gridAlignTimer: -1,
  dataSource: { replace: keys => { visible = Array.from(keys); } },
  onResultReady: b => admitted.push(b.bookUrl),
  prepareResultCover: b => new Promise((resolve, reject) => tasks.set(b.bookUrl, { resolve, reject })) });
const results = Array.from({ length: 8 }, (_, i) => ({ ...book, bookUrl: String(i), coverUrl: `url-${i}` }));
list.books = results; list.onBooksChanged();
assert.equal(tasks.size, 6, 'cover work is concurrency bounded');
assert.deepEqual(visible, [], 'no per-book placeholders while image preparation is pending');
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
const complete = (id, uri) => { const c = new Ready(); c.firstImage = uri; c.covers = [uri]; tasks.get(id).resolve(c); };
complete('2', 'decoded-2'); await flush();
assert.deepEqual(visible, ['source:2'], 'one slow cover cannot block another completed book');
assert.equal(tasks.has('6'), true, 'completion drains the next queued book');
list.books = results.filter(b => b.bookUrl !== '0'); list.onBooksChanged();
complete('0', 'old'); await flush();
assert.ok(!visible.includes('source:0'), 'removed result never returns after its download completes');
tasks.get('1').reject(Error('failed')); await flush();
assert.equal(list.preparedCovers.get('source:1').firstImage, '', 'terminal failure admits a final fallback');
list.books = list.books.map(b => b.bookUrl === '2' ? { ...b, coverUrl: 'updated' } : b);
list.onBooksChanged();
assert.equal(list.preparedCovers.get('source:2').firstImage, 'decoded-2', 'visible cover stays while replacement prepares');
complete('2', 'decoded-updated'); await flush();
assert.equal(list.preparedCovers.get('source:2').firstImage, 'decoded-updated');
assert.equal(admitted.filter(id => id === '2').length, 1, 'metadata/cover updates do not replay admission');
list.aboutToDisappear();
const snapshot = visible.slice();
complete('3', 'late'); await flush();
assert.deepEqual(visible, snapshot, 'unmounted page ignores late cover completion');
assert.equal(list.pendingCovers.size, 0, 'unmount discards queued work');
console.log('PASS ready covers: theme/album priority, scope, detail fallback, decode validation/release, bounded concurrency, independent admission, failures, replacements and stale completions');
