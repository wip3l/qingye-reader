// 目录换新后已缓存正文跟着章节走：序号挪动时搬到新序号，对不上的删掉，读缓存时再核对章节地址。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { harness } from './lib/reader-cache-test-harness.mjs';

let passed = 0;
function ok(message) { passed++; console.log(`ok ${passed} - ${message}`); }

const chapter = (index, url, title) => ({ index, url, title, cacheDate: 0 });
const catalog = list => list.map((item, index) => chapter(index, item[0], item[1]));
const rows = h => h.sql.prepare('SELECT chapterIndex AS i, chapterUrl AS u, chapterName AS t, content AS c, pinned AS p ' +
  'FROM book_contents WHERE bookUrl=? ORDER BY chapterIndex').all('novel')
  .map(row => ({ i: Number(row.i), u: row.u, t: row.t, c: row.c, p: Number(row.p) }));

// Pure plan: the common shapes of a changed catalog.
{
  const h = harness();
  const Realign = vm.runInContext('CachedChapterRealign', h.context);
  const plan = (cached, next) => {
    const result = Realign.plan(cached.map(([index, url, title]) => ({ index, url, title })), next);
    // Plain copies: the plan comes from another vm realm.
    return { drops: JSON.parse(JSON.stringify(result.drops)), assignments: JSON.parse(JSON.stringify(result.assignments)),
      isUnchanged: () => result.isUnchanged() };
  };
  const old = [[0, '/notice', '公告'], [1, '/c1', '第1章'], [2, '/c2', '第2章'], [3, '/c3', '第3章']];
  // A notice removed in front: every chapter moves one step forward.
  const shifted = plan(old, catalog([['/c1', '第1章'], ['/c2', '第2章'], ['/c3', '第3章']]));
  assert.deepEqual(shifted.drops, [0]);
  assert.deepEqual(shifted.assignments.map(a => [a.from, a.to]).sort((a, b) => a[0] - b[0]), [[1, 0], [2, 1], [3, 2]]);
  // Unchanged positions need no write at all.
  assert.equal(plan(old, catalog([['/notice', '公告'], ['/c1', '第1章'], ['/c2', '第2章'], ['/c3', '第3章'], ['/c4', '第4章']]))
    .isUnchanged(), true);
  // Site changed its address format: same title at the same index stays and adopts the new address.
  const renamed = plan([[1, '/old/1', '第1章']], catalog([['/new/0', '序'], ['/new/1', '第1章']]));
  assert.deepEqual(renamed.assignments.map(a => [a.from, a.to, a.url, a.relabel]), [[1, 1, '/new/1', true]]);
  // ...and moves by a title that is unique in the new catalog.
  const renamedShift = plan([[1, '/old/1', '第1章 风起']], catalog([['/new/1', '第1章 风起'], ['/new/2', '第2章']]));
  assert.deepEqual(renamedShift.assignments.map(a => [a.from, a.to]), [[1, 0]]);
  // Volumes restarting at chapter one: an ambiguous title is dropped, not guessed.
  const volumes = plan([[4, '/old/v2c1', '第一章']], catalog([['/a', '第一卷'], ['/b', '第一章'], ['/c', '第二卷'], ['/d', '第一章']]));
  assert.deepEqual(volumes.drops, [4]);
  // Duplicate addresses: the equal title wins, then the nearest index.
  const dup = plan([[2, '/same', '番外二']], catalog([['/same', '番外一'], ['/x', '第1章'], ['/y', '第2章'], ['/same', '番外二']]));
  assert.deepEqual(dup.assignments.map(a => [a.from, a.to]), [[2, 3]]);
  // A chapter that disappeared is dropped.
  assert.deepEqual(plan([[3, '/gone', '请假条']], catalog([['/c1', '第1章']])).drops, [3]);
  // Read-time check: another chapter's row is rejected, address-less rows and renamed addresses with equal titles pass.
  assert.equal(Realign.matches('/c1', '第1章', chapter(1, '/c2', '第2章')), false);
  assert.equal(Realign.matches('', '第1章', chapter(1, '/c2', '第2章')), true);
  assert.equal(Realign.matches('/old/1', '第1章', chapter(1, '/new/1', '第1章')), true);
  ok('plan follows chapters by address, then by unique title; ambiguous or vanished rows are dropped');
  h.close();
}

// Production SQL: rows and image references move together, pins survive, keys never collide mid-way.
{
  const h = harness();
  const before = catalog([['/notice', '公告'], ['/c1', '第1章'], ['/c2', '第2章'], ['/c3', '第3章']]);
  await h.db.saveCachedChapterContent('novel', before[0], '公告正文');
  await h.db.saveCachedChapterContent('novel', before[1], '第一章正文 ![](/files/reader_images/a.jpg)', true);
  await h.db.saveCachedChapterContent('novel', before[2], '第二章正文');
  await h.db.saveCachedChapterContent('novel', before[3], '第三章正文');
  h.sql.prepare('INSERT INTO reader_image_refs VALUES (?,?,?)').run('novel', 1, '/files/reader_images/a.jpg');
  const revision = Number(h.sql.prepare('SELECT cacheRevision AS r FROM book_contents WHERE chapterIndex=2').get().r);
  // The notice disappears and a new chapter is appended: indices 1..3 become 0..2.
  const after = catalog([['/c1', '第1章'], ['/c2', '第2章'], ['/c3', '第3章'], ['/c4', '第4章']]);
  await h.db.realignCachedChapterContents('novel', after);
  assert.deepEqual(rows(h).map(r => [r.i, r.u, r.c.slice(0, 5), r.p]),
    [[0, '/c1', '第一章正文', 1], [1, '/c2', '第二章正文', 0], [2, '/c3', '第三章正文', 0]]);
  assert.deepEqual(h.sql.prepare('SELECT chapterIndex AS i FROM reader_image_refs').all().map(r => Number(r.i)), [0]);
  assert.equal(Number(h.sql.prepare('SELECT cacheRevision AS r FROM book_contents WHERE chapterIndex=1').get().r), revision + 1);
  assert.equal(await h.db.getCachedChapterContent('novel', 1, after[1]), '第二章正文');
  // Running again on the same catalog is a no-op.
  const snapshot = JSON.stringify(rows(h));
  await h.db.realignCachedChapterContents('novel', after);
  assert.equal(JSON.stringify(rows(h)), snapshot);
  ok('changed catalog moves cached text, pins and image refs to the new indices; a second pass changes nothing');
  h.close();
}

// Read-time guard: a row left at a stale index is not served for another chapter.
{
  const h = harness();
  await h.db.saveCachedChapterContent('novel', chapter(5, '/c98', '第98章'), '第九十八章正文');
  assert.equal(await h.db.getCachedChapterContent('novel', 5, chapter(5, '/c104', '第104章')), '');
  assert.equal(await h.db.getCachedChapterContent('novel', 5, chapter(5, '/c98', '第98章')), '第九十八章正文');
  assert.equal(await h.db.getCachedChapterContent('novel', 5), '第九十八章正文');
  ok('reader ignores cached text whose recorded chapter differs from the catalog entry');
  h.close();
}

// The engine wires both: refreshToc realigns after rewriting the catalog, and reading passes the chapter.
{
  const { readFileSync } = await import('node:fs');
  const engine = readFileSync(new URL('../entry/src/main/ets/core/book/ReadBookEngine.ts', import.meta.url), 'utf8');
  const refresh = engine.slice(engine.indexOf('private async runRefreshToc'), engine.indexOf('private isCurrentBookSession'));
  assert.ok(refresh.indexOf('realignCachedChapterContents') > refresh.indexOf('insertBookChapters(chapters)'));
  assert.ok(refresh.indexOf('realignCachedChapterContents') < refresh.lastIndexOf('syncChapterCacheDates'));
  assert.match(engine, /getCachedChapterContent\(sessionBookUrl, idx, chapter\)/);
  assert.ok(refresh.indexOf('realignChapterMarks(targetBook.bookUrl, previousChapters, chapters)') >
    refresh.indexOf('insertBookChapters(chapters)'));
  const reader = readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
  const retry = reader.slice(reader.indexOf('async retryFetchChapters()'), reader.indexOf('initialReaderViewportSize()'));
  assert.match(retry, /chapterMarksRevision !== marksRevision[\s\S]*loadBookmarks\(\)[\s\S]*loadReaderAnnotations\(\)/);
  ok('engine realigns contents and marks after a catalog rewrite; the reader reloads marks when they moved');
}

// Bookmarks and annotations follow their chapters; unmatched ones stay where they were.
{
  const h = harness();
  const { readFileSync } = await import('node:fs');
  const dbSource = readFileSync(new URL('../entry/src/main/ets/model/data/AppDatabase.ts', import.meta.url), 'utf8');
  for (const table of ['bookmarks', 'book_annotations']) {
    h.sql.exec(dbSource.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${table} \\([\\s\\S]*?\\n      \\)`))[0]);
  }
  let syncMarks = 0;
  h.context.CloudSyncChangeTracker = { markDataChanged() { syncMarks++; } };
  const addBookmark = (index, name, page) => h.sql.prepare('INSERT INTO bookmarks (bookUrl,chapterIndex,chapterName,pageIndex,createTime) ' +
    'VALUES (?,?,?,?,?)').run('novel', index, name, page, index * 10 + page);
  const addAnnotation = (index, name, quote) => h.sql.prepare('INSERT INTO book_annotations (bookUrl,chapterIndex,chapterName,quote) ' +
    'VALUES (?,?,?,?)').run('novel', index, name, quote);
  const before = catalog([['/notice', '公告'], ['/c1', '第1章'], ['/c2', '第2章 旧名'], ['/c3', '第3章'], ['/c4', '番外']]);
  addBookmark(1, '第1章', 0);
  addBookmark(2, '第2章 旧名', 3);
  addBookmark(3, '第3章', 0);
  addBookmark(4, '番外', 0);
  addBookmark(7, '已删掉的请假条', 0); // a chapter that is gone: stays untouched
  addAnnotation(1, '第1章', '甲');
  addAnnotation(2, '第2章 旧名', '乙');
  addAnnotation(2, '第2章 旧名', '丙');
  // Notice removed, chapter 2 renamed (same address), 番外 has a new address but a unique title.
  const after = catalog([['/c1', '第1章'], ['/c2', '第2章 新名'], ['/c3', '第3章'], ['/c4-new', '番外']]);
  assert.equal(await h.db.realignChapterMarks('novel', before, after), true);
  const marks = h.sql.prepare('SELECT chapterIndex AS i, chapterName AS t, pageIndex AS p FROM bookmarks ORDER BY createTime').all()
    .map(r => [Number(r.i), r.t, Number(r.p)]);
  assert.deepEqual(marks, [[0, '第1章', 0], [1, '第2章 新名', 3], [2, '第3章', 0], [3, '番外', 0], [7, '已删掉的请假条', 0]]);
  const notes = h.sql.prepare('SELECT chapterIndex AS i, chapterName AS t, quote AS q FROM book_annotations ORDER BY quote').all()
    .map(r => [Number(r.i), r.t, r.q]);
  assert.deepEqual(notes, [[1, '第2章 新名', '丙'], [1, '第2章 新名', '乙'], [0, '第1章', '甲']]);
  assert.equal(syncMarks, 1);
  // Same catalog again: nothing to do, nothing to sync.
  assert.equal(await h.db.realignChapterMarks('novel', after, after), false);
  assert.equal(syncMarks, 1);
  ok('bookmarks and annotations move with their chapters, adopt renamed titles, and vanished chapters keep their marks');
  h.close();
}

// Bookmark unique key: a move onto an occupied (chapter, page) is skipped, and so is anything chained behind it.
{
  const h = harness();
  const Realign = vm.runInContext('CachedChapterRealign', h.context);
  const moves = slots => Object.fromEntries([...Realign.bookmarkMoves(slots, new Map([[1, 0], [2, 1]]))]);
  // Index 0 keeps a stale bookmark on page 0 that matched nothing.
  assert.deepEqual(moves([{ id: 9, index: 0, page: 0 }, { id: 1, index: 1, page: 0 }, { id: 2, index: 2, page: 0 },
    { id: 3, index: 2, page: 5 }]), { 3: 1 });
  // No collision: everything moves.
  assert.deepEqual(moves([{ id: 1, index: 1, page: 0 }, { id: 2, index: 2, page: 0 }]), { 1: 0, 2: 1 });
  // Address borrowed from the old catalog only when its title agrees with the stored name.
  const rows = Realign.markRows(new Map([[1, '第1章'], [2, '记错的名字']]), catalog([['/x', '序'], ['/c1', '第1章'], ['/c2', '第2章']]));
  assert.deepEqual(JSON.parse(JSON.stringify(rows)), [{ index: 1, url: '/c1', title: '第1章' }, { index: 2, url: '', title: '记错的名字' }]);
  ok('bookmark moves never break the (chapter, page) key; old-catalog addresses are borrowed only when titles agree');
  h.close();
}

console.log(`1..${passed}`);
