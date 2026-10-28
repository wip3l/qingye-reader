// Run: node scripts/bookshelf-recent-carousel-check.mjs
// Execute production selection, storage, exclusion and gesture math without a device.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
const preferencesData = new Map();
const storage = new Map();
const ctx = vm.createContext({
  preferences: { getPreferences: async () => ({
    get: async (key, fallback) => preferencesData.get(key) ?? fallback,
    put: async (key, value) => preferencesData.set(key, value), flush: async () => {}
  }) },
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  CloudSyncChangeTracker: { markApplicationPreferenceChanged() {} },
  BookDisplayHelper: { pickCover: covers => covers[1] ?? covers[0] }
});
function method(source, name) {
  const start = new RegExp(`^  (?:private )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const shelfSource = readEtsModule('components/home/BookshelfPage.ets');
vm.runInContext([
  'model/data/Book.ts', 'utils/BookshelfCoverBadgeSettings.ts', 'utils/BookshelfDisplaySettingsStore.ets',
  'utils/BookshelfSortHelper.ets', 'utils/RecentReadCarouselGeometry.ts', 'core/book/ShelfDataSources.ets'
].map(file => compile(readEtsModule(file))).join('\n') + compile(`
class RecentShelfHarness {
${['isTileLayout', 'isLatestTileCardLarge', 'shouldShowLatestExpandedTileBook', 'getLatestReadTileBook',
  'getLatestReadTileBooks', 'getTileBooksWithoutLatest', 'getSortedTileRootEntries', 'getTileFolderGroups',
  'latestTileGroupReadTime', 'latestTileGroupAddTime', 'compareTileRootEntry', 'getBookReadTime', 'getBookAddTime',
  'normalizeBookName', 'compareBookName', 'getShelfCover'].map(name => method(shelfSource, name)).join('\n')}
  shelfViewKey(): string { return 'normal'; }
}
globalThis.api = { Book, Store: BookshelfDisplaySettingsStore, Settings: BookshelfDisplaySettings,
  Sort: BookshelfSortHelper, Geometry: RecentReadCarouselGeometry, Shelf: RecentShelfHarness };`), ctx);
const { Book, Store, Settings, Sort, Geometry, Shelf } = ctx.api;
const urls = books => Array.from(books, b => b.bookUrl);
const reset = () => { preferencesData.clear(); storage.clear(); Store.cachedSettings = null; };

reset();
assert.deepEqual([new Settings().layoutMode, new Settings().lastReadPinMode, new Settings().lastReadPinCount], ['tile', 'large', 3]);
const defaults = await Store.load({});
assert.deepEqual([defaults.layoutMode, defaults.lastReadPinMode, defaults.lastReadPinCount], ['tile', 'large', 3]);
assert.equal(Store.fromStorage().lastReadPinCount, 3);
for (const layout of ['compact', 'loose', 'tile']) for (const pin of ['off', 'medium', 'large']) {
  reset(); preferencesData.set('bookshelfLayoutMode', layout); preferencesData.set('bookshelfLastReadPinMode', pin);
  const saved = await Store.load({});
  assert.deepEqual([saved.layoutMode, saved.lastReadPinMode, saved.lastReadPinCount], [layout, pin, 3]);
  for (let n = 1; n <= 5; n++) {
    saved.lastReadPinCount = n;
    await Store.save({}, saved); Store.applyToStorage(saved); Store.cachedSettings = null;
    assert.equal((await Store.load({})).lastReadPinCount, n);
    assert.equal(Store.fromStorage().lastReadPinCount, n);
    // The same JSON shape is used by cloud sync and backups.
    const backup = JSON.parse(JSON.stringify(saved));
    await Store.save({}, backup); Store.applyToStorage(backup);
    assert.equal(Store.fromStorage().lastReadPinCount, n);
  }
}
for (const invalid of [undefined, null, NaN, Infinity, 0, -1, 6, 2.5, '4']) {
  const oldBackup = new Settings(); oldBackup.layoutMode = 'compact'; oldBackup.lastReadPinMode = 'medium';
  oldBackup.lastReadPinCount = invalid;
  await Store.save({}, oldBackup); Store.applyToStorage(oldBackup);
  assert.equal(Store.fromStorage().lastReadPinCount, 3);
  assert.equal(Store.fromStorage().layoutMode, 'compact');
}

function book(url, time = 0, group = 0) {
  const b = new Book(); b.bookUrl = url; b.name = url; b.group = group;
  if (time > 0) b.putVariable('lastReadTime', String(time));
  return b;
}
const a = book('a', 500), b = book('b', 400), c = book('c', 300, 8), d = book('d', 200), e = book('e', 100), unread = book('unread');
unread.isPinned = true;
const books = [unread, e, c, a, d, b, book('a', 450)];
for (let n = 1; n <= 5; n++) assert.deepEqual(urls(Sort.getPinnedRecentReadBooks(books, n)), ['a', 'b', 'c', 'd', 'e'].slice(0, n));
assert.deepEqual(urls(Sort.getPinnedRecentReadBooks([unread], 3)), []);
assert.deepEqual(urls(Sort.getPinnedRecentReadBooks([a, unread], 3)), ['a']);
assert.deepEqual(urls(Sort.getPinnedRecentReadBooks([], 3)), []);
const tieA = book('tie-a', 800), tieB = book('tie-b', 800);
tieA.shelfModifiedTime = tieB.shelfModifiedTime = 10;
assert.deepEqual(urls(Sort.getPinnedRecentReadBooks([tieB, tieA], 3)), ['tie-a', 'tie-b']);

const shelf = new Shelf();
shelf.getShelfCoverList = () => ['first.jpg', 'second.jpg'];
assert.equal(shelf.getShelfCover(a, false), 'first.jpg'); // static cards bypass the time-based picker
assert.equal(shelf.getShelfCover(a), 'second.jpg'); // other shelf cover behavior is preserved
shelf.getShelfCoverList = () => [];
assert.equal(shelf.getShelfCover(a, false), '');
Object.assign(shelf, { books, bookshelfLayoutMode: 'tile', bookshelfLastReadPinMode: 'large', bookshelfLastReadPinCount: 3,
  activeShelfGroupId: 0, isBookMultiSelect: false, shelfAppliedSearchKeyword: '', sortMode: 'recentRead',
  shelfGroups: [{ groupId: 8, groupName: '分组' }], shelfTileEntriesCacheKey: '', shelfTileEntriesCache: [] });
assert.deepEqual(urls(shelf.getTileBooksWithoutLatest(books)).sort(), ['d', 'e', 'unread']);
let entries = shelf.getSortedTileRootEntries(books);
assert.deepEqual(urls(entries.filter(x => x.book).map(x => x.book)).sort(), ['d', 'e', 'unread']);
assert(entries.some(x => x.kind === 'group' && x.group.groupId === 8));
// All N candidates, not just the active slide, affect exclusion and the root-entry cache.
shelf.bookshelfLastReadPinCount = 1;
entries = shelf.getSortedTileRootEntries(books);
assert.deepEqual(urls(entries.filter(x => x.book).map(x => x.book)).sort(), ['b', 'd', 'e', 'unread']);
shelf.bookshelfLastReadPinCount = 5;
assert.deepEqual(urls(shelf.getTileBooksWithoutLatest(books)), ['unread']);
shelf.bookshelfLastReadPinMode = 'medium';
assert.deepEqual(urls(shelf.getLatestReadTileBooks(books)), ['a']);
for (const change of [{ bookshelfLastReadPinMode: 'off' }, { isBookMultiSelect: true },
  { activeShelfGroupId: 8 }, { shelfAppliedSearchKeyword: 'a' }, { bookshelfLayoutMode: 'compact' }]) {
  const baseline = { bookshelfLastReadPinMode: 'large', isBookMultiSelect: false, activeShelfGroupId: 0,
    shelfAppliedSearchKeyword: '', bookshelfLayoutMode: 'tile' };
  Object.assign(shelf, baseline, change);
  assert.equal(shelf.getTileBooksWithoutLatest(books).length, 6);
  Object.assign(shelf, baseline);
}
// Reading return promotes the new snapshot; deletion and filtered subsets never keep stale cards.
const recentE = book('e', 900);
assert.equal(shelf.getLatestReadTileBooks([a, b, recentE])[0].bookUrl, 'e');
assert.deepEqual(urls(shelf.getLatestReadTileBooks([b])), ['b']);
assert.deepEqual(urls(shelf.getLatestReadTileBooks([])), []);
assert.deepEqual(urls(shelf.getLatestReadTileBooks([c, d])), ['c', 'd']);

const carouselSource = readEtsModule('components/home/RecentReadCarousel.ets');
ctx.Curve = { EaseOut: 'ease-out' };
ctx.AppSpacing = { XL: 16 };
vm.runInContext(compile(`class CarouselMotionHarness {
${['resetMotion', 'itemWidth', 'itemStride', 'itemTranslation', 'startDrag', 'updateDrag', 'finishDrag'].map(name => method(carouselSource, name)).join('\n')}
}
globalThis.Motion = CarouselMotionHarness;`), ctx);
const layout = new ctx.Motion();
Object.assign(layout, { books: [a,b,c], viewportWidth: 400, positionValue: 0 });
const isVisible = (slot, position) => {
  layout.positionValue = position;
  return Math.abs(layout.itemTranslation(slot)) < (layout.viewportWidth + layout.itemWidth()) / 2 - 0.00001;
};

for (const n of [3, 4, 5]) for (let current = 0; current < n; current++) {
  const visible = Array.from(Geometry.slots(current, n))
    .filter(slot => isVisible(slot, current)).map(slot => slot - current).sort();
  assert.deepEqual(visible, [-1, 0, 1]);
  assert.equal(Geometry.wrap(Geometry.target(current, -90, 0, n), n), (current + 1) % n);
  assert.equal(Geometry.wrap(Geometry.target(current, 90, 0, n), n), (current + n - 1) % n);
  assert.equal(Geometry.target(current, 10, 0, n), current);
}
assert.deepEqual(Array.from(Geometry.slots(0, 2)), [0, 1]);
assert.deepEqual(Array.from(Geometry.slots(1, 1)), [0]);
assert.deepEqual(Array.from(Geometry.slots(0, 0)), []);
assert.equal(Geometry.target(0, 100, 0, 2), 0);
assert.equal(Geometry.target(1, -100, 0, 2), 1);
assert.equal(Geometry.target(0, -10, -700, 3), 1);
assert.equal(Geometry.target(0, -100, -700, 1), 0);

// Sample entire gestures (including the circular seam), not just the settled endpoints.
for (const viewport of [280, 360, 540, 900, 1600]) {
layout.viewportWidth = viewport;
for (const count of [3, 4, 5]) for (const anchor of [-1, 0, count - 1, count, count * 2]) {
  for (const direction of [-1, 1]) {
    const slots = Array.from(Geometry.slots(anchor, count));
    let previous = new Map();
    for (let frame = 0; frame <= 100; frame++) {
      const position = anchor + direction * frame / 100;
      const visibleBooks = [];
      for (const slot of slots) {
        const distance = slot - position;
        if (previous.has(slot)) assert(Math.abs(distance - previous.get(slot)) < 0.011, 'card must never jump across the center');
        previous.set(slot, distance);
        if (isVisible(slot, position)) visibleBooks.push(Geometry.wrap(slot, count));
        assert.equal(layout.itemStride() - layout.itemWidth(), 16, 'cards keep a fixed gap and never overlap');
      }
      assert.equal(new Set(visibleBooks).size, visibleBooks.length, 'no visible duplicate book at the loop seam');
    }
    const target = anchor + direction;
    const visible = list => list.filter(slot => isVisible(slot, target));
    assert.deepEqual(visible(slots), visible(Array.from(Geometry.slots(target, count))), 'reanchoring only replaces hidden slots');
  }
}
}
const motion = new ctx.Motion();
Object.assign(motion, { books: [a,b,c], currentIndex: 0, settledPosition: 0, positionValue: 0,
  viewportWidth: 400, animationGeneration: 0, dragging: false, settling: false });
const completions = [];
motion.getUIContext = () => ({ animateTo(options, update) { update(); completions.push(options.onFinish); } });
for (let step = 1; step <= 7; step++) {
  motion.startDrag();
  const initialX = motion.itemTranslation(step - 1);
  const initialWidth = motion.itemWidth();
  motion.updateDrag({ offsetX: -90 });
  assert(Math.abs(motion.itemTranslation(step - 1) - initialX + 90) < 0.00001, 'whole card must follow the finger 1:1');
  assert.equal(motion.itemWidth(), initialWidth, 'card size stays fixed during drag');
  motion.finishDrag({ offsetX: -90, velocityX: 0 });
  assert.equal(motion.positionValue, step);
  assert.equal(motion.currentIndex, step % 3);
  completions.shift()();
  assert.equal(motion.settledPosition, step);
  assert.equal(motion.positionValue, step, 'animation completion must not wrap the rendered position');
}
motion.startDrag(); motion.updateDrag({ offsetX: 12 }); motion.finishDrag(); completions.shift()();
assert.equal(motion.positionValue, 7, 'cancel returns to the current virtual anchor');
motion.startDrag(); motion.finishDrag({ offsetX: -90, velocityX: 0 });
motion.currentIndex = 0; motion.resetMotion(); completions.shift()();
assert.equal(motion.settledPosition, 0, 'stale animation callback must not change reset data');
Object.assign(motion, { books: [a,b], currentIndex: 0 }); motion.resetMotion();
motion.startDrag(); motion.updateDrag({ offsetX: 90 });
assert.equal(motion.positionValue, 0, 'two-book rail stops at first book');
motion.finishDrag(); completions.shift()();
Object.assign(motion, { currentIndex: 1 }); motion.resetMotion();
motion.startDrag(); motion.updateDrag({ offsetX: -90 });
assert.equal(motion.positionValue, 1, 'two-book rail stops at last book');
motion.finishDrag(); completions.shift()();
console.log('PASS: defaults/migration, 1–5 persistence and backup, candidate selection, root dedup/cache, scope boundaries, manual carousel geometry');
