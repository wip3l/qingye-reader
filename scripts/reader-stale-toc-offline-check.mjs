import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// A cached catalog with legacy unresolved chapter URLs must survive a failed refresh on open, so a fully cached
// book still reads offline. Runs the real ReadBookEngine; only the database and network are replaced.
const BOOK_URL = 'https://book.test/1';
const SOURCE_URL = 'https://source.test';

class FakeBook {
  constructor(fields) { Object.assign(this, { durChapterIndex: 0, durChapterPos: 0, totalChapterNum: 0 }, fields); this.vars = {}; }
  getVariable(key) { return this.vars[key] || ''; }
  putVariable(key, value) { this.vars[key] = value; }
  replaceVariable(value) { this.vars = { ...value }; }
  get variable() { return this.vars; }
}

function harness({ cachedUrls, network }) {
  const db = {
    chapters: cachedUrls.map((url, index) => ({ bookUrl: BOOK_URL, index, url, title: `旧第${index + 1}章`, cacheDate: 0 })),
    contents: new Map(cachedUrls.map((_, index) => [index, `缓存正文 ${index}`])),
    deletes: 0
  };
  const context = vm.createContext({
    console: { log() {}, info() {}, warn() {}, error() {} },
    setTimeout, clearTimeout, setInterval, clearInterval,
    HttpClient: class { static CANCELLED_ERROR = 'cancelled'; },
    ComicImageTiming: class {},
    ComicImagePipeline: {},
    appDb: {
      async getBookSource() { return { bookSourceUrl: SOURCE_URL, bookSourceName: 'test' }; },
      async getBookChapters() { return db.chapters.map(chapter => ({ ...chapter })); },
      async deleteBookChapters() { db.deletes++; db.chapters = []; },
      async insertBookChapters(chapters) { db.chapters = chapters.map(chapter => ({ ...chapter })); },
      async updateBook() {},
      async getBookChapterCacheDateMap() { return new Map([...db.contents.keys()].map(index => [index, 1])); },
      async getCachedChapterContent(_book, index) { return db.contents.get(index) || ''; },
      async saveCachedChapterContent(_book, chapter, text) { db.contents.set(chapter.index, text); },
      async touchCachedChapterContent() {}
    },
    fs: { statSync: () => ({ isFile: () => true, size: 1 }) },
    AppStorage: { get: () => '/cache' },
    ReaderOpenTrace: { mark() {} },
    ReaderCacheBudget: { noteTextWrite() {} },
    ReaderActionMarker: { hasLegacy() { return false; } },
    BookTypeSupport: { isAudio: () => false },
    CoverUrlNormalizer: { prefer: (a, b) => a || b },
    BookUrlResolver: { getVariableJson: () => '' },
    SearchCoordinator: class { async search() { return []; } getLastFailureReason() { return 'offline'; } },
    BookSourceInteractionPostProcessor: { interactionCacheIdentity: () => '' }
  });
  for (const file of ['ReaderCacheCoordinator', 'ReaderImageMarker', 'ReaderImageReferences', 'ReaderImageCache',
    'ReaderImageScheduler', 'ReaderImageResults', 'WebBookService', 'ReadBookEngine']) {
    vm.runInContext(stripTypeScriptTypes(readEtsModule(`core/book/${file}.ts`)
      .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  }
  const engine = vm.runInContext('new ReadBookEngine()', context);
  const offline = () => { throw new Error('network unreachable'); };
  engine.webBook.getBookInfo = async (_source, book) => {
    if (network === 'offline') offline();
    return Object.assign(new FakeBook({ ...book }), { tocUrl: `${BOOK_URL}/toc` });
  };
  engine.webBook.getChapterList = async () => {
    if (network === 'offline') offline();
    if (network === 'empty') return [];
    return [0, 1, 2].map(index => ({ bookUrl: BOOK_URL, index, url: `${BOOK_URL}/c${index}`, title: `新第${index + 1}章`, variable: '' }));
  };
  engine.webBook.getContent = async () => offline();
  const book = new FakeBook({ bookUrl: BOOK_URL, origin: SOURCE_URL, name: '测试书', tocUrl: `${BOOK_URL}/toc` });
  return { engine, db, book };
}

const BROKEN = ['{{baseUrl}}/c0', '{{baseUrl}}/c1'];

// Offline (request throws): opening keeps the stale catalog in memory and on disk, and cached chapters read.
for (const network of ['offline', 'empty']) {
  const h = harness({ cachedUrls: BROKEN, network });
  await h.engine.openBook(h.book);
  assert.equal(h.engine.chapters.length, 2, `${network}: stale catalog must stay in memory`);
  assert.equal(h.db.chapters.length, 2, `${network}: stale catalog must stay in the database`);
  assert.equal(h.db.deletes, 0, `${network}: catalog must not be deleted before a replacement arrives`);
  assert.equal(await h.engine.loadContent(1), '缓存正文 1', `${network}: cached content must read offline`);
}

// Online: the stale catalog is replaced only after the new one arrives.
{
  const h = harness({ cachedUrls: BROKEN, network: 'online' });
  await h.engine.openBook(h.book);
  assert.deepEqual(h.engine.chapters.map(chapter => chapter.title), ['新第1章', '新第2章', '新第3章']);
  assert.deepEqual(h.db.chapters.map(chapter => chapter.url), [0, 1, 2].map(index => `${BOOK_URL}/c${index}`));
  assert.equal(h.db.deletes, 1);
}

// A book without any catalog still surfaces the failure so the reader shows its retry message.
{
  const h = harness({ cachedUrls: [], network: 'offline' });
  await assert.rejects(h.engine.openBook(h.book), /network unreachable/);
}

// A valid cached catalog never touches the network on open.
{
  const h = harness({ cachedUrls: [`${BOOK_URL}/c0`, `${BOOK_URL}/c1`], network: 'offline' });
  await h.engine.openBook(h.book);
  assert.equal(h.engine.chapters.length, 2);
  assert.equal(await h.engine.loadContent(0), '缓存正文 0');
}

console.log('reader stale toc offline check passed');
