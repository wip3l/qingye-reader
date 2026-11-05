import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const names = ['openShelfBook', 'closeShelfBook', 'cancelShelfBookOpening'];
const methods = names.map(name => {
  const start = source.indexOf(`  ${name}(`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join(',');
const timers = new Map(), routes = [], storage = new Map(), snapshotRequests = [];
let sequence = 0, resolveRoute, rejectRoute, refreshes = 0, pageSnapshot = null;
const pixel = name => ({ name, released: false, release() { this.released = true; return Promise.resolve(); } });
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const context = vm.createContext({
  console: { error() {}, warn() {} },
  CloudAutoSync: { isPlaceholder: () => false },
  BookshelfSortHelper: { holdReadTime() {}, releaseReadTimes() {} },
  LocalBookService: {
    isPdfBook: book => book.format === 'pdf',
    usesEpubOriginalLayout: book => book.originalLayout === true
  },
  ReaderOpenTrace: { begin() {}, mark() {}, cancel() {} },
  ReaderOpenSnapshotStore: {
    open: (_context, bookUrl, chapterIndex, widthPx, heightPx, dark, themeRevision, waitMs) => {
      snapshotRequests.push({ bookUrl, chapterIndex, widthPx, heightPx, dark, themeRevision, waitMs });
      return Promise.resolve(pageSnapshot);
    }
  },
  BookshelfPage: { SHELF_OPENING_BACKDROP_WAIT: 100 },
  getContext: () => ({}),
  SHELF_OPENING_COVER_KEY: 'shelfOpeningCover',
  SHELF_OPENING_BACKDROP_KEY: 'shelfOpeningBackdrop',
  SHELF_OPENING_PAGE_SNAPSHOT_KEY: 'shelfOpeningPageSnapshot',
  SHELF_BOOK_MOTION_UNTIL_KEY: 'shelfBookMotionUntil',
  SHELF_COVER_OPEN_DURATION: 500, SHELF_COVER_OPEN_START_CAP: 250, SHELF_BOOK_MOTION_SETTLE: 60,
  AppStorage: { setOrCreate: (key, value) => storage.set(key, value), get: key => storage.get(key) },
  router: { pushUrl: route => { routes.push(route); return new Promise((resolve, reject) => { resolveRoute = resolve; rejectRoute = reject; }); } },
  setTimeout: callback => { timers.set(++sequence, callback); return sequence; },
  clearTimeout: id => timers.delete(id)
});
// The shared-element id helper and the cover validity rule run as the real modules, imports dropped.
for (const file of ['SharedElementMotion.ts', 'ShelfCoverLocator.ets']) {
  const text = fs.readFileSync(new URL(`../entry/src/main/ets/utils/${file}`, import.meta.url), 'utf8')
    .replace(/^import .*$/gm, '').replace('export class', 'class');
  vm.runInContext(stripTypeScriptTypes(text), context);
}
const host = vm.runInContext(stripTypeScriptTypes(`({ ${methods} })`), context);
let backdropShot = null, backdropTaken = 0, backdropDiscarded = 0;
Object.assign(host, {
  shelfBookRoutePending: false, bookshelfBookOpenAnimation: true,
  cloudBookOpenRequest: 0, acknowledgeShelfBookUpdate() {},
  // Bounds left at zero: the cover could not be measured, so no backdrop is wanted.
  shelfOpeningCover: target => ({ bookUrl: target.bookUrl, cover: 'cover.jpg', frame: '', color: '#007DFF', initial: 'b',
    boundsX: 0, boundsY: 0, boundsWidth: 0, boundsHeight: 0, windowWidth: 400, windowHeight: 800, cropImage: true }),
  getUIContext: () => ({ vp2px: value => value * 3 }),
  appDarkMode: false, themeRevision: 7,
  takeShelfOpeningBackdrop: () => { backdropTaken++; return Promise.resolve(backdropShot); },
  discardShelfOpeningBackdrop: () => { backdropDiscarded++; },
  playShelfReorder: async () => { refreshes++; }, shelfBookReturnRefreshTimer: -1
});
const book = { bookUrl: 'book:1', origin: 'source', name: 'book' };
host.openShelfBook(book, 50, 100);
host.openShelfBook(book, 50, 100);
assert.equal(routes.length, 1, 'repeated tap during route creation must not push twice');
assert.equal(routes[0].url, 'pages/ReadBook', 'text books open the text reader directly');
assert.equal(timers.size, 0, 'native page transition starts immediately, without an intermediate timer/overlay');
assert.equal(routes[0].params.shelfSharedCoverId, 'cover:shelf:source:book%3A1');
assert.equal(storage.get('shelfOpeningCover').bookUrl, book.bookUrl, 'the reader receives the cover it opens before the route starts');
assert.equal(backdropDiscarded, 1, 'an unmeasured cover drops the pre-taken home snapshot instead of waiting for it');
assert.equal(backdropTaken, 0);
assert.equal(storage.get('shelfOpeningBackdrop'), null);
assert.equal(storage.get('shelfOpeningPageSnapshot'), null);
resolveRoute(); await Promise.resolve();
assert.equal(host.shelfBookRoutePending, false);
host.closeShelfBook(book.bookUrl);
assert.equal(refreshes, 0, 'return must keep the shared source stable during native motion');
for (const [id, callback] of timers) { timers.delete(id); callback(); }
assert.equal(refreshes, 1);
host.closeShelfBook(book.bookUrl); host.cancelShelfBookOpening();
assert.equal(timers.size, 0, 'leaving the shelf cancels pending refresh');
host.bookshelfBookOpenAnimation = false;
storage.delete('shelfOpeningCover');
host.openShelfBook(book, 50, 100);
assert.equal(routes[1].params.shelfSharedCoverId, '', 'animation preference disables the shared transition');
assert.equal(storage.has('shelfOpeningCover'), false, 'animation preference also skips the cover opening');
rejectRoute(new Error('test route failure')); await Promise.resolve(); await Promise.resolve();
assert.equal(host.shelfBookRoutePending, false, 'a failed route unlocks the shelf');
assert.equal(storage.get('shelfReaderDirectTransition'), false);
host.bookshelfBookOpenAnimation = true;
const pdfBook = { bookUrl: 'local:pdf:1', origin: 'local', name: 'PDF book', format: 'pdf' };
host.openShelfBook(pdfBook, 50, 100);
assert.equal(routes[2].url, 'pages/PdfReadBook', 'PDF books open their dedicated reader directly');
assert.equal(routes[2].params.shelfBookOpening, 'true', 'PDF books retain the cover opening animation');
assert.equal(routes[2].params.shelfSharedCoverId, 'cover:shelf:local:local%3Apdf%3A1');
assert.equal(storage.get('shelfOpeningCover').bookUrl, pdfBook.bookUrl);
resolveRoute(); await Promise.resolve();
assert.equal(host.shelfBookRoutePending, false, 'a PDF route unlocks the shelf after creation');
for (const originalLayout of [false, true]) {
  const epubBook = { bookUrl: `local:epub:${originalLayout}`, origin: 'local', name: 'EPUB book', format: 'epub', originalLayout };
  host.openShelfBook(epubBook, 50, 100);
  const route = routes.at(-1);
  assert.equal(route.url, originalLayout ? 'pages/EpubOriginalReadBook' : 'pages/ReadBook',
    'EPUB routing follows the saved original-layout preference');
  assert.equal(route.params.bookUrl, epubBook.bookUrl);
  assert.equal(route.params.shelfBookOpening, 'true', 'EPUB books retain the cover opening animation');
  assert.equal(route.params.shelfSharedCoverId, `cover:shelf:local:${encodeURIComponent(epubBook.bookUrl)}`);
  assert.equal(storage.get('shelfOpeningCover').bookUrl, epubBook.bookUrl);
  resolveRoute(); await Promise.resolve();
  assert.equal(host.shelfBookRoutePending, false, 'an EPUB route unlocks the shelf after creation');
}

// A measured cover: the route waits for the home snapshot and the last-closed page picture, then hands both over.
host.shelfOpeningCover = (target, x, y) => ({ bookUrl: target.bookUrl, cover: 'cover.jpg', frame: '', color: '#007DFF', initial: 'b',
  boundsX: x, boundsY: y, boundsWidth: 90, boundsHeight: 120, windowWidth: 400, windowHeight: 800, cropImage: true });
backdropShot = pixel('backdrop');
pageSnapshot = { pixelMap: pixel('page'), meta: { bookUrl: 'book:2', identity: 'chapter-3' } };
const measuredBook = { bookUrl: 'book:2', origin: 'source', name: 'measured', durChapterIndex: 3 };
let routesBefore = routes.length, discardedBefore = backdropDiscarded;
host.openShelfBook(measuredBook, 50, 100);
assert.equal(routes.length, routesBefore, 'with a measured cover the route waits for the backdrop and the page snapshot');
assert.equal(host.shelfBookRoutePending, true, 'the shelf stays locked while the pictures are fetched');
assert.equal(backdropDiscarded, discardedBefore, 'the pre-taken home snapshot is consumed, not discarded');
assert.equal(backdropTaken, 1);
assert.deepEqual(snapshotRequests.at(-1),
  { bookUrl: 'book:2', chapterIndex: 3, widthPx: 1200, heightPx: 2400, dark: false, themeRevision: 7, waitMs: 100 },
  'the page snapshot is looked up by chapter, window pixels, dark mode and theme revision');
await flush();
assert.equal(routes.length, routesBefore + 1, 'the route is pushed once both pictures are in');
assert.equal(routes.at(-1).params.shelfSharedCoverId, 'cover:shelf:source:book%3A2');
assert.equal(storage.get('shelfOpeningBackdrop'), backdropShot, 'the home snapshot goes behind the opening reader');
assert.equal(storage.get('shelfOpeningPageSnapshot'), pageSnapshot.pixelMap, 'the last-closed page picture covers the text area');
assert.equal(storage.get('shelfOpeningPageSnapshotMeta'), 'book:2\nchapter-3', 'the reader can verify the picture against its own identity');
rejectRoute(new Error('test route failure')); await flush();
assert.equal(host.shelfBookRoutePending, false, 'a failed route unlocks the shelf');
assert.equal(backdropShot.released, true, 'a failed route releases the home snapshot it had handed over');
assert.equal(storage.get('shelfOpeningBackdrop'), null);
assert.equal(storage.get('shelfOpeningPageSnapshot'), null);

// No usable page picture: the backdrop alone is handed over and the meta is cleared.
backdropShot = pixel('backdrop-2'); pageSnapshot = null;
routesBefore = routes.length;
host.openShelfBook(measuredBook, 50, 100);
await flush();
assert.equal(routes.length, routesBefore + 1);
assert.equal(storage.get('shelfOpeningBackdrop'), backdropShot);
assert.equal(storage.get('shelfOpeningPageSnapshot'), null);
assert.equal(storage.get('shelfOpeningPageSnapshotMeta'), '');
resolveRoute(); await flush();
assert.equal(host.shelfBookRoutePending, false);

assert.doesNotMatch(source, /openingBookCoverAngle|openingBookTurnTimer|shelfBookOpeningOverlay/);
console.log('PASS native book route: text/PDF/EPUB routing, shared page transition, cover handoff, home/page snapshot handoff, duplicate taps, return refresh, preferences and failure cleanup');
