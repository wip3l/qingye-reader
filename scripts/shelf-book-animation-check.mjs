import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = path => fs.readFileSync(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const constants = read('components/reader/ReaderShelfCoverOpening.ets')
  .split('\n').filter(line => line.startsWith('export const ')).join('\n').replaceAll('export ', '');
let now = 1000, sequence = 0;
const timers = new Map(), storage = new Map();
const context = vm.createContext({
  Date: { now: () => now }, console,
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Curve: { Friction: 'friction' },
  setTimeout: (callback, delay) => { timers.set(++sequence, { callback, at: now + delay }); return sequence; },
  clearTimeout: id => timers.delete(id)
});
vm.runInContext(stripTypeScriptTypes(constants), context);
function hostFor(source, names) {
  return vm.runInContext(stripTypeScriptTypes(`({${names.map(name => method(source, name)).join(',')}})`), context);
}
function advance(ms) {
  now += ms;
  for (const [id, timer] of [...timers]) {
    if (timer.at <= now) { timers.delete(id); timer.callback(); }
  }
}

for (const page of ['ReadBook', 'PdfReadBook']) {
  const source = read(`pages/${page}.ets`);
  const host = hostFor(source, ['closeShelfCover']);
  let animation;
  Object.assign(host, {
    shelfOpeningCover: {},
    getUIContext: () => ({ animateTo: (options, change) => { animation = options; change(); } })
  });
  let closed = false;
  const pending = host.closeShelfCover().then(() => { closed = true; });
  advance(1000); await Promise.resolve();
  assert.equal(closed, false, `${page}: elapsed time cannot substitute for the actual last frame`);
  assert.equal(animation.expectedFrameRateRange.expected, 120);
  animation.onFinish(); await pending;
  assert.equal(closed, true);
  host.shelfOpeningCover = null;
  await host.closeShelfCover();

  const exit = method(source, page === 'ReadBook' ? 'exitReaderPage' : 'close');
  const wait = exit.indexOf(page === 'ReadBook' ? 'await shelfCoverClosed' : 'await coverClosed');
  assert.ok(wait >= 0 && wait < exit.indexOf("'shelfBookCloseAnimationNonce'"),
    `${page}: shelf return countdown starts after the cover finishes`);
}

const shelf = hostFor(read('components/home/BookshelfPage.ets'),
  ['shelfBookMotionDelay', 'scheduleLoadBooks', 'closeShelfBook', 'cancelShelfBookOpening']);
let refreshes = 0;
Object.assign(shelf, { loadTimer: -1, shelfBookReturnRefreshTimer: -1,
  loadBooks: () => { refreshes++; return Promise.resolve(); } });
storage.set('shelfBookMotionUntil', now + 500);
shelf.scheduleLoadBooks();
advance(80); assert.equal(refreshes, 0, 'saving progress cannot rebuild the shelf during opening');
storage.set('shelfBookMotionUntil', now + 500);
advance(420); assert.equal(refreshes, 0, 'an actual animation start extends the initial estimate');
advance(80); assert.equal(refreshes, 1);

shelf.scheduleLoadBooks(); // Progress notification may arrive just before the return notification.
shelf.closeShelfBook('book');
advance(420); assert.equal(refreshes, 1, 'old refresh deadline was inside the 500 ms return flight');
shelf.scheduleLoadBooks(); // And another save can finish during the return flight.
advance(80); assert.equal(refreshes, 1, 'shared target stays stable through the last animation frame');
advance(60); assert.equal(refreshes, 2, 'coalesce progress notifications into one return refresh');
assert.equal(timers.size, 0);
shelf.closeShelfBook('book'); shelf.cancelShelfBookOpening();
advance(1000); assert.equal(refreshes, 2, 'leaving the shelf cancels the return refresh');

const reader = hostFor(read('pages/ReadBook.ets'),
  ['isReaderPaginationInteractionBusy', 'isReaderPageMotionActive']);
Object.assign(reader, {
  pageTurnQueue: { hasPendingBackward: () => false, hasPendingForward: () => false, hasPending: () => false },
  pageSlideDirection: 0, readerComicBoundaryDirection: 0, pendingRestorePageIndex: -1,
  readerPaginationInteractionIdleUntil: 0, shelfOpenAnimating: true, readerInitialPageReady: false
});
assert.equal(reader.isReaderPaginationInteractionBusy(), false, 'opening must still produce the first readable page');
assert.equal(reader.isReaderPageMotionActive(), true, 'neighbor warmup yields while the book opens');
reader.readerInitialPageReady = true;
assert.equal(reader.isReaderPaginationInteractionBusy(), true, 'remaining pagination yields after the first page is ready');
reader.shelfOpenAnimating = false;
assert.equal(reader.isReaderPaginationInteractionBusy(), false, 'pagination resumes after opening');
reader.readerExiting = true;
assert.equal(reader.isReaderPageMotionActive(), true, 'background warmup also yields while closing');
console.log('PASS shelf animation: real finish callback, high-refresh request, stable return target and deferred/coalesced refresh');
