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
const timers = new Map(), routes = [], storage = new Map();
let sequence = 0, resolveRoute, rejectRoute, refreshes = 0;
const context = vm.createContext({
  console: { error() {}, warn() {} },
  CloudAutoSync: { isPlaceholder: () => false },
  LocalBookService: { isPdfBook: book => book.format === 'pdf' },
  ReaderOpenTrace: { begin() {}, mark() {}, cancel() {} },
  SHELF_OPENING_COVER_KEY: 'shelfOpeningCover',
  AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
  router: { pushUrl: route => { routes.push(route); return new Promise((resolve, reject) => { resolveRoute = resolve; rejectRoute = reject; }); } },
  setTimeout: callback => { timers.set(++sequence, callback); return sequence; },
  clearTimeout: id => timers.delete(id)
});
vm.runInContext(stripTypeScriptTypes(fs.readFileSync(new URL('../entry/src/main/ets/utils/SharedElementMotion.ts', import.meta.url), 'utf8').replace('export class', 'class')), context);
const host = vm.runInContext(stripTypeScriptTypes(`({ ${methods} })`), context);
Object.assign(host, {
  shelfBookRoutePending: false, bookshelfBookOpenAnimation: true,
  cloudBookOpenRequest: 0, acknowledgeShelfBookUpdate() {},
  shelfOpeningCover: target => ({ bookUrl: target.bookUrl, cover: 'cover.jpg', frame: '', color: '#007DFF', initial: 'b' }),
  loadBooks: () => { refreshes++; return Promise.resolve(); }, shelfBookReturnRefreshTimer: -1
});
const book = { bookUrl: 'book:1', origin: 'source', name: 'book' };
host.openShelfBook(book, 50, 100);
host.openShelfBook(book, 50, 100);
assert.equal(routes.length, 1, 'repeated tap during route creation must not push twice');
assert.equal(routes[0].url, 'pages/ReadBook', 'text books open the text reader directly');
assert.equal(timers.size, 0, 'native page transition starts immediately, without an intermediate timer/overlay');
assert.equal(routes[0].params.shelfSharedCoverId, 'cover:shelf:source:book%3A1');
assert.equal(storage.get('shelfOpeningCover').bookUrl, book.bookUrl, 'the reader receives the cover it opens before the route starts');
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
assert.doesNotMatch(source, /openingBookCoverAngle|openingBookTurnTimer|shelfBookOpeningOverlay/);
console.log('PASS native book route: text/PDF routing, shared page transition, cover handoff, duplicate taps, return refresh, preferences and failure cleanup');
