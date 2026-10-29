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
  ReaderOpenTrace: { begin() {}, mark() {}, cancel() {} },
  AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
  router: { pushUrl: route => { routes.push(route); return new Promise((resolve, reject) => { resolveRoute = resolve; rejectRoute = reject; }); } },
  setTimeout: callback => { timers.set(++sequence, callback); return sequence; },
  clearTimeout: id => timers.delete(id)
});
vm.runInContext(stripTypeScriptTypes(fs.readFileSync(new URL('../entry/src/main/ets/utils/SharedElementMotion.ts', import.meta.url), 'utf8').replace('export class', 'class')), context);
const host = vm.runInContext(stripTypeScriptTypes(`({ ${methods} })`), context);
Object.assign(host, {
  showTileFolder: false, shelfBookRoutePending: false, bookshelfBookOpenAnimation: true,
  cloudBookOpenRequest: 0, acknowledgeShelfBookUpdate() {},
  loadBooks: () => { refreshes++; return Promise.resolve(); }, shelfBookReturnRefreshTimer: -1
});
const book = { bookUrl: 'book:1', origin: 'source', name: 'book' };
host.openShelfBook(book, 50, 100);
host.openShelfBook(book, 50, 100);
assert.equal(routes.length, 1, 'repeated tap during route creation must not push twice');
assert.equal(timers.size, 0, 'native page transition starts immediately, without an intermediate timer/overlay');
assert.equal(routes[0].params.shelfSharedCoverId, 'cover:shelf:source:book%3A1');
resolveRoute(); await Promise.resolve();
assert.equal(host.shelfBookRoutePending, false);
host.closeShelfBook(book.bookUrl);
assert.equal(refreshes, 0, 'return must keep the shared source stable during native motion');
for (const [id, callback] of timers) { timers.delete(id); callback(); }
assert.equal(refreshes, 1);
host.closeShelfBook(book.bookUrl); host.cancelShelfBookOpening();
assert.equal(timers.size, 0, 'leaving the shelf cancels pending refresh');
host.bookshelfBookOpenAnimation = false;
host.openShelfBook(book, 50, 100);
assert.equal(routes[1].params.shelfSharedCoverId, '', 'animation preference disables the shared transition');
rejectRoute(new Error('test route failure')); await Promise.resolve(); await Promise.resolve();
assert.equal(host.shelfBookRoutePending, false, 'a failed route unlocks the shelf');
assert.equal(storage.get('shelfReaderDirectTransition'), false);
assert.doesNotMatch(source, /openingBookCoverAngle|openingBookTurnTimer|shelfBookOpeningOverlay/);
console.log('PASS native book route: immediate shared page transition, duplicate taps, return refresh, preferences and failure cleanup');
