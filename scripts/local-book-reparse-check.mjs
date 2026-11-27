// 本地书重新解析：目录替换要么整本成功、要么旧目录原样保留；解析版本只在目录写好后记下；
// 库里目录空了会按原文件重建；同一本书同时只重建一次。
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
const compile = (code, globals = {}) => vm.runInNewContext(stripTypeScriptTypes(code), { Promise, Map, Error, ...globals });

// ---- AppDatabase.replaceBookChaptersWithContents：删旧与写新同一事务 ----
const dbFile = 'model/data/AppDatabase.ts';
const Db = compile(`class ChapterContentBuckets { chapters = []; contents = []; }
class AppDatabase { static BATCH_INSERT_CHUNK_SIZE = 2;
${['replaceBookChaptersWithContents', 'batchInsertChapterBuckets', 'chapterContentBuckets'].map(n => method(dbFile, n)).join('\n')}
}; AppDatabase`, {
  ReaderCacheCoordinator: { run: task => task() },
  ChapterWordCounts: { count: text => text.length },
});

function sqliteStore(failInsertAt = -1) {
  const sql = new DatabaseSync(':memory:');
  sql.exec(`CREATE TABLE book_chapters (url TEXT PRIMARY KEY, title TEXT, bookUrl TEXT, chapterIndex INTEGER,
    isVip INTEGER, isPay INTEGER, resourceUrl TEXT, tag TEXT, startOffset INTEGER, endOffset INTEGER, variable TEXT);
    CREATE TABLE book_contents (bookUrl TEXT, chapterIndex INTEGER, chapterUrl TEXT, chapterName TEXT, content TEXT,
    cacheDate INTEGER, contentChars INTEGER, PRIMARY KEY (bookUrl, chapterIndex));
    CREATE TABLE reader_image_refs (bookUrl TEXT, chapterIndex INTEGER);
    CREATE TABLE reader_pagination_cache (bookUrl TEXT, chapterIndex INTEGER);`);
  let inserts = 0;
  return {
    sql,
    createTransaction: async () => {
      sql.exec('BEGIN');
      return {
        execute: async (statement, args) => { sql.prepare(statement).run(...args); },
        batchInsert: async (table, rows) => {
          if (inserts++ === failInsertAt) throw new Error('模拟写入失败');
          for (const row of rows) {
            const keys = Object.keys(row);
            sql.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
              .run(...keys.map(key => row[key] ?? null));
          }
        },
        commit: async () => sql.exec('COMMIT'),
        rollback: async () => sql.exec('ROLLBACK'),
      };
    },
  };
}
const chapterRows = (bookUrl, titles) => titles.map((title, index) => ({
  url: `${bookUrl}#chapter=${index}`, title, bookUrl, index, isVip: false, isPay: false, resourceUrl: '', tag: '',
  start: 0, end: 0, variable: '',
}));
const titlesOf = store => store.sql.prepare('SELECT title FROM book_chapters ORDER BY chapterIndex').all()
  .map(row => row.title);

{
  const store = sqliteStore();
  const db = new Db();
  db.store = store;
  await db.replaceBookChaptersWithContents('local://a', chapterRows('local://a', ['旧一', '旧二', '旧三']), ['1', '2', '3']);
  store.sql.prepare('INSERT INTO reader_pagination_cache VALUES (?, ?)').run('local://a', 0);
  await db.replaceBookChaptersWithContents('local://a', chapterRows('local://a', ['新一', '新二']), ['x', 'y']);
  assert.deepEqual(titlesOf(store), ['新一', '新二']);
  assert.equal(store.sql.prepare('SELECT COUNT(*) AS n FROM book_contents').get().n, 2);
  assert.equal(store.sql.prepare('SELECT COUNT(*) AS n FROM reader_pagination_cache').get().n, 0);
}
{
  // 第一次替换 3 章分两批共 4 次 batchInsert（序号 0～3），第二次替换在序号 5 时失败（新章节已写进一部分）：整本回滚，旧目录和正文都在。
  const store = sqliteStore(5);
  const db = new Db();
  db.store = store;
  await db.replaceBookChaptersWithContents('local://b', chapterRows('local://b', ['旧一', '旧二', '旧三']), ['1', '2', '3']);
  await assert.rejects(db.replaceBookChaptersWithContents('local://b',
    chapterRows('local://b', ['新一', '新二', '新三', '新四', '新五']), ['a', 'b', 'c', 'd', 'e']), /模拟写入失败/);
  assert.deepEqual(titlesOf(store), ['旧一', '旧二', '旧三']);
  assert.equal(store.sql.prepare('SELECT COUNT(*) AS n FROM book_contents').get().n, 3);
}

// ---- LocalBookService：版本最后记、空目录自愈、同书去重 ----
const serviceFile = 'core/book/LocalBookService.ets';
const Service = compile(`class LocalChapterData { title = ''; content = ''; sourcePath = ''; variable = ''; }
class BookChapter {}
class LocalBookService { static TYPE_TXT = 0; static TYPE_EPUB = 1; static parserRebuilds = new Map();
${['ensureLocalParserCurrent', 'lostChapters', 'ensureLocalParserCurrentOnce', 'rebuildEpubIndex', 'persistEpubChapters']
    .map(n => method(serviceFile, n)).join('\n')}
}; LocalBookService`, {
  appDb: globalThis.__appDb = {},
  fileUri: { getUriFromPath: path => `file://${path}` },
  ReadBookEngine: { discardSession: () => {} },
  PdfBookService: {},
});

function makeEnv({ chapterCount = 3, replaceFails = false, parseDelay = 0 } = {}) {
  const log = [];
  const stored = { version: '', chapters: chapterCount };
  Object.assign(globalThis.__appDb, {
    initWithContext: async () => {},
    getBookChapterCount: async () => stored.chapters,
    getBookChapters: async () => [],
    getCachedChapterContent: async () => '',
    updateBook: async book => { stored.version = book.getVariable('localParserVersion'); log.push(`update:${stored.version}`); },
    replaceBookChaptersWithContents: async (bookUrl, chapters) => {
      log.push('replace');
      if (replaceFails) throw new Error('写目录失败');
      stored.chapters = chapters.length;
    },
  });
  Object.assign(Service, {
    isLocalBook: () => true,
    isPdfBook: () => false,
    exists: () => true,
    formatOf: () => 'epub',
    parserVersionFor: () => '13',
    hashText: text => text,
    currentEpubChapterPath: async () => '',
    currentEpubChapterContent: async () => '',
    migrateEpubProgress: () => {},
    deleteLocalPath: (_, path) => { log.push(`delete:${path}`); },
    parsePackage: async () => {
      log.push('parse');
      if (parseDelay) await new Promise(resolve => setTimeout(resolve, parseDelay));
      return { title: '', author: '', coverPath: '', extractRoot: '/new', isComic: false,
        chapters: [{ title: '一', content: 'a' }, { title: '二', content: 'b' }] };
    },
  });
  return { log, stored };
}
function makeBook(version, totalChapterNum = 2) {
  const vars = { localParserVersion: version, localFilePath: '/books/a.epub', localExtractRoot: '/old' };
  return {
    bookUrl: 'local://a', type: 1, totalChapterNum, name: '书', author: '',
    getVariable: key => vars[key] ?? '', putVariable: (key, value) => { vars[key] = value; },
  };
}

{
  // 版本已是最新、目录在：不重建。
  const { log } = makeEnv({ chapterCount: 2 });
  assert.equal(await Service.ensureLocalParserCurrent({}, makeBook('13')), false);
  assert.deepEqual(log, []);
}
{
  // 版本已是最新、库里目录却是空的（旧版重建中断留下的）：按原文件重建。
  const { log, stored } = makeEnv({ chapterCount: 0 });
  assert.equal(await Service.ensureLocalParserCurrent({}, makeBook('13', 548)), true);
  assert.equal(stored.chapters, 2);
  assert.deepEqual(log, ['update:importing', 'parse', 'replace', 'update:13', 'delete:/old']);
}
{
  // 写目录失败：库里版本停在 importing（下次打开重来），旧解压目录不删。
  const { log, stored } = makeEnv({ replaceFails: true });
  await assert.rejects(Service.ensureLocalParserCurrent({}, makeBook('12')), /写目录失败/);
  assert.equal(stored.version, 'importing');
  assert.ok(!log.some(entry => entry.startsWith('delete:')));
}
{
  // 重建还没完又打开：两次调用共用一次重建。
  const { log } = makeEnv({ parseDelay: 20 });
  const book = makeBook('12');
  const [first, second] = await Promise.all([
    Service.ensureLocalParserCurrent({}, book), Service.ensureLocalParserCurrent({}, book)]);
  assert.equal(first, true);
  assert.equal(second, true);
  assert.equal(log.filter(entry => entry === 'parse').length, 1);
  assert.equal(Service.parserRebuilds.size, 0);
}

// 导入覆盖已有的书时同样先写目录、后记版本。
const importSource = read(serviceFile);
const importTail = importSource.slice(importSource.indexOf('let chapters: LocalChapterData[] = [];'));
const persistAt = importTail.indexOf('await LocalBookService.persistEpubChapters(bookUrl, chapters);');
assert(persistAt > 0);
assert(importTail.slice(0, persistAt).includes("book.putVariable('localParserVersion', 'importing');"));
assert(!importTail.slice(0, persistAt).includes('deleteLocalPath(context, oldExtractRoot)'));
assert(importTail.slice(persistAt, persistAt + 400)
  .includes("book.putVariable('localParserVersion', LocalBookService.parserVersionFor(extension));"));

console.log('PASS: local book reparse replaces chapters atomically, records the parser version last, rebuilds lost tables and runs once per book');
