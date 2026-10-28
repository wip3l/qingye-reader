// Run: node scripts/reading-progress-check.mjs
// Execute production methods against SQLite; no HarmonyOS device or network required.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { DatabaseSync } from 'node:sqlite';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const dbSource = readEtsModule('model/data/AppDatabase.ts');
const shelfSource = readEtsModule('components/home/BookshelfPage.ets');
const readerSource = readEtsModule('pages/ReadBook.ets');
const compile = source => stripTypeScriptTypes(source.replace(/^export /gm, ''), { mode: 'strip' });
function method(source, name) {
  const start = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
class Predicates {
  constructor(table) { this.table = table; this.conditions = []; this.args = []; this.order = ''; }
  equalTo(key, value) { this.conditions.push(`${key} = ?`); this.args.push(value); return this; }
  lessThanOrEqualTo(key, value) { this.conditions.push(`${key} <= ?`); this.args.push(value); return this; }
  orderByDesc(key) { this.order = ` ORDER BY ${key} DESC`; return this; }
  get where() { return this.conditions.length ? ` WHERE ${this.conditions.join(' AND ')}` : ''; }
}
function resultSet(rows) {
  let index = -1;
  let closed = false;
  const keys = Object.keys(rows[0] || {});
  return {
    rowCount: rows.length,
    goToFirstRow() { assert(!closed); index = 0; return rows.length > 0; },
    goToNextRow() { assert(!closed); return ++index < rows.length; },
    getColumnIndex: name => keys.indexOf(name),
    getString: column => String(rows[index][keys[column]] ?? ''),
    getLong: column => Number(rows[index][keys[column]] ?? 0),
    close() { closed = true; }
  };
}
const context = vm.createContext({
  console, relationalStore: { RdbPredicates: Predicates },
  BookIdentity: { keyOfBook: book => book.bookUrl },
  CloudSyncChangeTracker: { markDataChanged() {} },
  ReaderProgressCheckpoint: { canWrite: () => true },
  AppStorage: { setOrCreate() {} },
  READER_PROGRESS_OFFSET_KEY: 'readProgressCharOffsetV2',
  READER_PROGRESS_OFFSET_CHAPTER_KEY: 'readProgressCharOffsetChapterV2'
});
vm.runInContext(compile(readEtsModule('model/data/Book.ts')) + compile(`
  class ProgressDatabase {
    ${['insertBook', 'getBook', 'getAllBooks', 'restoreMissingChapterCounts', 'resultSetToBook',
      'getStringColumn', 'getLongColumn'].map(name => method(dbSource, name)).join('\n')}
  }
  class ProgressShelf {
    ${['hasKnownReadProgressTotal', 'getReadProgressValue', 'getReadProgressPercentText',
      'getShelfProgressText', 'shelfReadProgressKey', 'shelfBookRenderKey'].map(name => method(shelfSource, name)).join('\n')}
  }
  class ProgressReader {
    ${method(readerSource, 'saveReadingProgress')}
    ${method(readerSource, 'currentChapterProgressPageCount')}
  }
  globalThis.api = { Book, ProgressDatabase, ProgressShelf, ProgressReader };
`), context);
const { Book, ProgressDatabase, ProgressShelf, ProgressReader } = context.api;
const shelf = new ProgressShelf();
shelf.shelfCoverRenderVersions = new Map();
function book(url, total = 0, index = 0, pos = 0, pages = 0, metadataChapter = index) {
  const item = new Book();
  Object.assign(item, { bookUrl: url, totalChapterNum: total, durChapterIndex: index, durChapterPos: pos });
  item.putVariable('readStarted', '1');
  if (pages) {
    item.putVariable('readProgressChapterIndex', String(metadataChapter));
    item.putVariable('readProgressPageCount', String(pages));
  }
  return item;
}
function database() {
  const sql = new DatabaseSync(':memory:');
  for (const table of ['books', 'book_chapters']) {
    const start = dbSource.indexOf(`CREATE TABLE IF NOT EXISTS ${table} (`);
    sql.exec(dbSource.slice(start, dbSource.indexOf('`', start)));
  }
  const db = new ProgressDatabase();
  const calls = { counts: 0, updates: [], beforeUpdate: null };
  db.recordBookMutation = async () => {};
  db.store = {
    async query(predicates) {
      return resultSet(sql.prepare(`SELECT * FROM ${predicates.table}${predicates.where}${predicates.order}`).all(...predicates.args));
    },
    async querySql(statement, args = []) {
      calls.counts++;
      return resultSet(sql.prepare(statement).all(...args));
    },
    async insert(table, bucket) {
      const keys = Object.keys(bucket);
      sql.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
        .run(...Object.values(bucket));
    },
    async update(bucket, predicates) {
      calls.beforeUpdate?.();
      calls.beforeUpdate = null;
      calls.updates.push({ ...bucket });
      return sql.prepare(`UPDATE ${predicates.table} SET ${Object.keys(bucket).map(key => `${key}=?`).join(',')}${predicates.where}`)
        .run(...Object.values(bucket), ...predicates.args).changes;
    }
  };
  function catalog(url, count) {
    const statement = sql.prepare('INSERT INTO book_chapters (bookUrl, chapterIndex, title, url) VALUES (?, ?, ?, ?)');
    for (let i = 0; i < count; i++) statement.run(url, i, `第${i + 1}章`, `${url}/${i}`);
  }
  return { db, sql, calls, catalog };
}

const tests = {
  'catalog before book insertion: chapter 39 gets a real denominator': async () => {
    const h = database();
    try {
      h.catalog('first', 287);
      const item = book('first', 0, 38, 0, 10);
      await h.db.insertBook(item);
      const stored = await h.db.getBook('first');
      assert.equal(stored.totalChapterNum, 287);
      assert.equal(shelf.getReadProgressValue(stored), 13.2);
      assert.equal(h.calls.counts, 1, 'known counts do not query the catalog again');
    } finally { h.sql.close(); }
  },
  'existing shelf repairs only missing counts and preserves progress': async () => {
    const h = database();
    try {
      const item = book('legacy', 0, 38, 4, 10);
      await h.db.insertBook(item);
      await h.db.insertBook(book('known', 500, 2));
      await h.db.insertBook(book('uncached'));
      h.catalog('legacy', 287);
      h.catalog('known', 2); // A smaller cache must not shrink a known total.
      h.calls.counts = 0;
      const books = await h.db.getAllBooks();
      const repaired = books.find(b => b.bookUrl === 'legacy');
      assert.equal(repaired.totalChapterNum, 287);
      assert.equal(repaired.durChapterIndex, 38);
      assert.equal(repaired.durChapterPos, 4);
      assert.equal(repaired.variable, item.variable);
      assert.equal(books.find(b => b.bookUrl === 'known').totalChapterNum, 500);
      assert.equal(books.find(b => b.bookUrl === 'uncached').totalChapterNum, 0);
      assert.equal(h.calls.counts, 1, 'one aggregate query for all missing shelf counts');
      assert.deepEqual(h.calls.updates, [{ totalChapterNum: 287 }]);
      assert.equal(h.sql.prepare('SELECT totalChapterNum FROM books WHERE bookUrl=?').get('legacy').totalChapterNum, 287);
      assert.equal(shelf.getReadProgressPercentText(books.find(b => b.bookUrl === 'uncached')), '进度未知');
    } finally { h.sql.close(); }
  },
  'opening one legacy book repairs it without a shelf visit': async () => {
    const h = database();
    try {
      await h.db.insertBook(book('open', 0, 9));
      h.catalog('open', 20);
      assert.equal((await h.db.getBook('open')).totalChapterNum, 20);
      assert.equal(await h.db.getBook('missing'), null);
    } finally { h.sql.close(); }
  },
  'repair cannot overwrite a concurrent catalog/progress update': async () => {
    const h = database();
    try {
      await h.db.insertBook(book('race'));
      h.catalog('race', 10);
      h.calls.beforeUpdate = () => h.sql.exec("UPDATE books SET totalChapterNum=20, durChapterIndex=12, durChapterPos=7 WHERE bookUrl='race'");
      await h.db.getAllBooks();
      const stored = await h.db.getBook('race');
      assert.equal(stored.totalChapterNum, 20);
      assert.equal(stored.durChapterIndex, 12);
      assert.equal(stored.durChapterPos, 7);
    } finally { h.sql.close(); }
  },
  'large imported shelf uses bounded batches and bound URL parameters': async () => {
    const h = database();
    try {
      for (let i = 0; i < 205; i++) {
        const url = `book'${i}`;
        await h.db.insertBook(book(url));
        h.catalog(url, 2);
      }
      h.calls.counts = 0;
      assert((await h.db.getAllBooks()).every(b => b.totalChapterNum === 2));
      assert.equal(h.calls.counts, 2);
    } finally { h.sql.close(); }
  },
  'percentage and completion boundaries': () => {
    const cases = [
      [book('missing', 0, 38), 0, '进度未知', 'reading'],
      [book('chapter39', 287, 38), 13.2, '已读13.2%', 'reading'],
      [book('single-unknown', 1), 0, '已读0%', 'reading'],
      [book('single-start', 1, 0, 0, 100), 1, '已读1%', 'reading'],
      [book('mismatch', 10, 9, 0, 20, 8), 90, '已读90%', 'reading'],
      [book('last-start', 10, 9, 0, 20), 90.5, '已读90.5%', 'reading'],
      [book('finished', 10, 9, 19, 20), 100, '已读100%', 'readDone'],
      [book('invalid-index', 10, 38), 0, '进度未知', 'reading']
    ];
    for (const [item, percent, label, state] of cases) {
      assert.equal(shelf.getReadProgressValue(item), percent, item.bookUrl);
      assert.equal(shelf.getReadProgressPercentText(item), label, item.bookUrl);
      assert.equal(shelf.shelfReadProgressKey(item), state, item.bookUrl);
    }
    const unread = new Book();
    unread.totalChapterNum = 10;
    assert.equal(shelf.shelfReadProgressKey(unread), 'unread');
    assert.equal(shelf.getShelfProgressText(unread), '未读');
    assert.equal(shelf.getShelfProgressText(book('last', 10, 9)), '阅读中');
    assert.equal(shelf.getShelfProgressText(book('end', 10, 9, 19, 20)), '已读完');
  },
  'denominator repair invalidates retained shelf card keys': () => {
    const item = book('key', 0, 38);
    const before = shelf.shelfBookRenderKey(item, 'list');
    item.totalChapterNum = 287;
    assert.notEqual(shelf.shelfBookRenderKey(item, 'list'), before);
  },
  'exit during unfinished pagination preserves unknown page count': async () => {
    const item = book('exit', 1, 0, 4);
    let saved;
    context.AppDatabase = { getInstance: () => ({
      updateBookReadingProgress: async (...args) => { saved = args; }
    }) };
    const reader = Object.assign(new ProgressReader(), {
      book: item, chapters: [{ title: 'one' }], currentChapterIndex: 0, currentPageIndex: 0,
      contentPages: ['loading'], pagedContentText: 'content', readingProgressSaveQueue: Promise.resolve(),
      readerProgressAnchorChapterIndex: 0, readerProgressAnchorPageIndex: 4,
      readerProgressAnchorOffset: 100, readerProgressAnchorPageCount: 0,
      readerProgressAnchorPageText: 'saved', readerProgressAnchorPageImage: '', lastRecentReadCardChapterIndex: 0,
      readerEngine: () => ({ book: item }), canSaveReadingProgress: () => false,
      clampChapterIndex: index => index, getPageStartOffset: () => 0,
      hasPagedReaderArea: () => true, getCachedReaderPagination: () => ({ complete: false }),
      getShelfLastReadPageText: () => '', getShelfLastReadPageImage: () => ''
    });
    assert.equal(reader.currentChapterProgressPageCount(), 0);
    await reader.saveReadingProgress();
    assert.equal(saved[3], 4, 'visible position survives');
    assert.equal(JSON.parse(saved[5]).readProgressPageCount, '0', 'unknown is not coerced into one page');
    assert.equal(shelf.getReadProgressValue(item), 0, 'no false completion');
  }
};
for (const [name, test] of Object.entries(tests)) {
  await test();
  console.log(`PASS ${name}`);
}
console.log(`Reading progress: ${Object.keys(tests).length} scenarios passed.`);
