import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';

const read = file => fs.readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8');
function method(file, name) {
  const source = read(file);
  const at = source.search(new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`, 'm'));
  assert(at >= 0, name);
  return source.slice(at, source.indexOf('\n  }', at) + 4);
}
function compile(code, globals = {}) {
  return vm.runInNewContext(stripTypeScriptTypes(code), globals);
}
const clean = file => read(file).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
const Helper = compile(clean('utils/BookshelfSortHelper.ets') + '\nBookshelfSortHelper');
const State = compile(clean('utils/BookshelfStateStore.ets') + '\nBookshelfStateStore');
const shelfFile = 'components/home/BookshelfPage.ets';
const Shelf = compile(`class Shelf { ${['sortBooks', 'compareTileRootEntry'].map(n => method(shelfFile, n)).join('\n')} }; Shelf`,
  { BookshelfSortHelper: Helper });
const shelf = new Shelf();
shelf.compareBookName = (a, b) => a.name.localeCompare(b.name);
const books = [
  { name: 'old', confirmedChapterUpdateTime: 10, latestChapterTime: 999, lastCheckTime: 999, isPinned: false },
  { name: 'new', confirmedChapterUpdateTime: 100, latestChapterTime: 100, isPinned: false },
  { name: 'pinned', confirmedChapterUpdateTime: 1, isPinned: true },
  { name: 'imported', latestChapterTime: 9999, lastCheckTime: 9999, isPinned: false },
];
assert.equal(State.normalizeSortMode('recentUpdate'), 'recentUpdate');
assert.equal(State.normalizeSortMode('bad'), 'recentRead');
assert.deepEqual(Array.from(shelf.sortBooks(books, 'recentUpdate'), b => b.name), ['pinned', 'new', 'old', 'imported']);
assert.equal(books[0].name, 'old', 'sorting does not mutate the source snapshot');
assert(shelf.compareTileRootEntry({ updateTime: 100, pinned: false }, { updateTime: 10, pinned: false }, 'recentUpdate') < 0);
assert(shelf.compareTileRootEntry({ updateTime: 1, pinned: true }, { updateTime: 100, pinned: false }, 'recentUpdate') < 0);
assert.equal(Helper.getBookUpdateTime({ confirmedChapterUpdateTime: Infinity, latestChapterTime: 999 }), 0);
const sameBatch = [{ name: 'B', confirmedChapterUpdateTime: 500 }, { name: 'A', confirmedChapterUpdateTime: 500 }];
assert.deepEqual(Array.from(shelf.sortBooks(sameBatch, 'recentUpdate'), b => b.name), ['A', 'B']);
assert.deepEqual(Array.from(shelf.sortBooks([...sameBatch].reverse(), 'recentUpdate'), b => b.name), ['A', 'B']);

const Updates = compile(clean('core/book/BookChapterUpdate.ts') + '\nBookChapterUpdate');
const chapter = (n, title = `chapter ${n}`) => ({ url: `chapter/${n}`, title, variable: '' });
const before = [chapter(1), chapter(2)];
assert.equal(Updates.hasNewChapters([], before), false, 'initial catalog is not a new chapter');
assert.equal(Updates.hasNewChapters(before, []), false);
assert.equal(Updates.hasNewChapters(before, [chapter(2)]), false, 'shrunk catalog');
assert.equal(Updates.hasNewChapters(before, [chapter(1), chapter(2, 'corrected title')]), false);
assert.equal(Updates.hasNewChapters(before, [chapter(1), chapter(2), chapter(3)]), true);
assert.equal(Updates.hasNewChapters(before, [chapter(2), chapter(3)]), true, 'rolling catalog');
assert.equal(Updates.hasNewChapters(before, [chapter(11), chapter(12)]), false, 'unrelated replacement catalog');

let confirmedTime = 0, nextChapters = [chapter(1), chapter(2), chapter(3)];
const engineDb = {
  recordBookChapterUpdate: async (url, time) => { confirmedTime = Math.max(confirmedTime, time); },
  updateBook: async () => {}, deleteBookChapters: async () => {}, insertBookChapters: async () => {},
};
const Engine = compile(clean('core/book/ReadBookEngine.ts') + '\nReadBookEngine', {
  WebBookService: class {}, BookChapterUpdate: Updates, appDb: engineDb,
  BookUrlResolver: { getVariableJson: value => value }, console: { log() {}, warn() {} },
});
const engine = Engine.createBackgroundWorker();
engine.source = {};
engine.book = { bookUrl: 'book', tocUrl: 'toc', latestChapterTitle: 'chapter 2',
  lastCheckTime: Date.now(), confirmedChapterUpdateTime: 0 };
engine.chapters = before;
engine.chapterUpdateBatchTime = 500;
engine.webBook = { getChapterList: async () => nextChapters };
engine.syncChapterCacheDates = async () => {};
await engine.refreshToc();
assert.equal(confirmedTime, 500, 'batch start, not network completion time');
engine.chapterUpdateBatchTime = 600;
await engine.refreshToc();
assert.equal(confirmedTime, 500, 'unchanged refresh preserves timestamp');
nextChapters = [...nextChapters, chapter(4)];
await engine.refreshToc();
assert.equal(confirmedTime, 600);
engine.chapters = [];
nextChapters = [...nextChapters, chapter(5)];
engine.chapterUpdateBatchTime = 700;
await engine.refreshToc();
assert.equal(confirmedTime, 600, 'missing initial cache is not a confirmed update');
nextChapters = [...nextChapters, chapter(6)];
await engine.refreshToc(0, true);
assert.equal(confirmedTime, 600, 'repairing a broken catalog is not update evidence');
nextChapters = [...nextChapters, { ...chapter(7), variable: 'true' }];
await engine.refreshToc();
assert.equal(confirmedTime, 600, 'temporary fallback catalog is not update evidence');
assert(!method('model/data/AppDatabase.ts', 'updateBook').includes('confirmedChapterUpdateTime'),
  'ordinary stale progress snapshots must not overwrite confirmed update time');
const Db = compile(`class Db { ${method('model/data/AppDatabase.ts', 'recordBookChapterUpdate')} }; Db`);
const dbTime = new Db();
const sqlite = new DatabaseSync(':memory:');
sqlite.exec("CREATE TABLE books (bookUrl TEXT PRIMARY KEY, latestChapterTime INTEGER); INSERT INTO books VALUES ('book', 9999)");
const column = read('model/data/AppDatabase.ts').match(/column: 'confirmedChapterUpdateTime', definition: '([^']+)'/)[1];
assert(Number(read('model/data/AppDatabase.ts').match(/SCHEMA_VERSION = (\d+)/)[1]) > 25,
  'installed databases must run the new column migration');
sqlite.exec(`ALTER TABLE books ADD COLUMN ${column}`);
const storedTime = () => sqlite.prepare("SELECT confirmedChapterUpdateTime AS time FROM books WHERE bookUrl = 'book'").get().time;
assert.equal(storedTime(), 0, 'migration must not mistake legacy import time for an update');
dbTime.store = { executeSql: async (sql, args) => { sqlite.prepare(sql).run(...args); } };
await dbTime.recordBookChapterUpdate('book', 800);
await dbTime.recordBookChapterUpdate('book', 600);
assert.equal(storedTime(), 800);
await dbTime.recordBookChapterUpdate('book', 900);
assert.equal(storedTime(), 900);
await dbTime.recordBookChapterUpdate('book', Infinity);
assert.equal(storedTime(), 900);
sqlite.close();

const Backup = compile(`class AppDataBackupService { ${method('utils/AppDataBackupService.ets', 'hydrateBook')} }; AppDataBackupService`,
  { Book: class { replaceVariable(value) { this.variable = value; } } });
Backup.replaceRoot = value => value;
assert.equal(Backup.hydrateBook({ confirmedChapterUpdateTime: 123 }, '', '').confirmedChapterUpdateTime, 123);
assert.equal(Backup.hydrateBook({ latestChapterTime: 999 }, '', '').confirmedChapterUpdateTime, 0);
const Sync = compile(`class CloudSyncCoordinator { ${method('account/CloudSyncCoordinator.ets', 'restoreBook')} }; CloudSyncCoordinator`,
  { Book: class {}, BookIdentity: { keyOfBook: () => 'book' } });
let restored = { confirmedChapterUpdateTime: 500, bookUrl: 'book' };
const syncDb = { getBook: async () => restored, restoreBook: async book => { restored = book; } };
await Sync.restoreBook(syncDb, { bookUrl: 'book', origin: 'source' });
assert.equal(restored.confirmedChapterUpdateTime, 500, 'old clients cannot clear new update evidence');
await Sync.restoreBook(syncDb, { bookUrl: 'book', origin: 'source', confirmedChapterUpdateTime: 700 });
assert.equal(restored.confirmedChapterUpdateTime, 700);
await Sync.restoreBook(syncDb, { bookUrl: 'book', origin: 'source', confirmedChapterUpdateTime: 600 });
assert.equal(restored.confirmedChapterUpdateTime, 700, 'late sync cannot roll back update time');

const Explore = compile(`class Explore { ${method('components/home/ExplorePage.ets', 'openExploreSourcePicker')} }; Explore`);
const explore = new Explore();
Object.assign(explore, { sourceOptions: [{ sourceUrl: 'a', sourceGroup: '漫画' }, { sourceUrl: 'b', sourceGroup: '' }],
  exploreSourceGroupLabel: group => group.trim() || '未分组', refreshExploreSourceDataSource() {} });
for (const [url, group] of [['a', '漫画'], ['b', '未分组'], ['removed', '__all__']]) {
  explore.selectedSourceUrl = url; explore.activeExploreSourceGroup = '旧分组';
  explore.exploreSourceFilterInput = '旧搜索'; explore.openExploreSourcePicker();
  assert.equal(explore.activeExploreSourceGroup, group); assert.equal(explore.exploreSourceFilterInput, '');
  assert.equal(explore.showExploreSourcePicker, true);
}

let playingBook = 'trial', stopped = 0, deleted = 0;
let releaseStop;
// The production static method refers to its class by name.
const context = vm.createContext({ AppStorage: { get: () => playingBook } });
vm.runInContext(stripTypeScriptTypes(`class ReaderTtsFloatingSession { ${method('utils/ReaderTtsFloatingSession.ets', 'stopForBook')} };
  globalThis.Floating = ReaderTtsFloatingSession;`), context);
const floating = context.Floating;
floating.stopAction = () => { stopped++; return new Promise(resolve => { releaseStop = resolve; }); };
floating.clear = () => { stopped++; };
await floating.stopForBook('another'); assert.equal(stopped, 0, 'declining another book must not stop current playback');
const db = { initWithContext: async () => {}, getBook: async () => ({ pendingAddToShelf: true }),
  deleteBook: async () => { deleted++; } };
const Detail = compile(`class Detail { ${method('pages/SearchBookDetail.ets', 'removePendingReadBook')} }; Detail`, {
  AppDatabase: { getInstance: () => db }, getContext: () => ({}), console,
  AppStorage: { setOrCreate() {} }, ReaderTtsFloatingSession: floating,
  SearchExplorePendingBook: { isPendingAddToShelf: b => b?.pendingAddToShelf },
});
const detail = new Detail(); detail.pendingAddToShelfBookUrl = 'trial';
const removing = detail.removePendingReadBook();
for (let i = 0; i < 8; i++) await Promise.resolve();
assert.equal(stopped, 1); assert.equal(deleted, 0, 'deletion waits for playback, media session and progress cleanup');
releaseStop(); await removing; assert.equal(deleted, 1); assert.equal(detail.pendingAddToShelfBookUrl, '');
db.getBook = async () => ({ pendingAddToShelf: false });
detail.pendingAddToShelfBookUrl = 'trial'; await detail.removePendingReadBook();
assert.equal(stopped, 1); assert.equal(deleted, 1, 'a concurrently added shelf book is retained');
console.log('PASS: recent-update ordering and persistence, current discovery group, scoped and awaited trial playback cleanup');
