import assert from 'node:assert/strict';
import { harness } from './lib/reader-cache-test-harness.mjs';

let passed = 0;
function ok(message) { passed++; console.log(`ok ${passed} - ${message}`); }

{
  const h = harness();
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'original');
  const selected = await h.db.listOnlineCachedContentEntries(true);
  await h.db.pinCachedChapterContent('novel', 0);
  assert.equal((await h.db.deleteCachedContentEntries(selected, false, h.now())).removed, 0);
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'rewritten', false);
  assert.equal(h.sql.prepare('SELECT pinned FROM book_contents').get().pinned, 1);
  assert.equal(await h.db.getOnlineCachedContentBytes(), 0);
  assert.equal(await h.db.getOnlineCachedContentBytes(true), 9);
  ok('late pin survives a stale deletion plan; automatic writes cannot downgrade offline content; budgets exclude offline bytes');
  h.close();
}
{
  const h = harness();
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'old');
  const stale = await h.db.listOnlineCachedContentEntries(true);
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'new');
  assert.equal((await h.db.deleteCachedContentEntries(stale, false, h.now())).removed, 0);
  const fresh = await h.db.listOnlineCachedContentEntries(true);
  const release = h.Coordinator.retainBook('novel');
  assert.equal((await h.db.deleteCachedContentEntries(fresh, false, h.now())).removed, 0);
  release();
  assert.equal((await h.db.deleteCachedContentEntries(fresh, false, h.now())).removed, 1);
  await h.db.saveCachedChapterContent('local://book', h.chapter(0), 'local');
  assert.equal((await h.db.listOnlineCachedContentEntries(false)).length, 0);
  ok('rewritten chapters and active/background readers survive deletion; local imports are excluded');
  h.close();
}
{
  const h = harness(); const path = '/files/reader_images/shared.jpg'; h.put(path);
  await h.db.saveCachedChapterContent('auto', h.chapter(0), h.Marker.create(path));
  await h.db.saveCachedChapterContent('offline', h.chapter(0), h.Marker.create(path), true);
  assert.equal((await h.Budget.clearComic()).removed, 0);
  const result = await h.Budget.clearOffline();
  assert.equal(result.removed, 1); assert.ok(h.files.has(path), 'automatic chapter still references the shared image');
  assert.equal(await h.Budget.comicUsageBytes(), 100);
  ok('shared originals are counted once and retained while any offline/remaining chapter needs them');
  h.close();
}
{
  const h = harness(); const path = '/files/reader_images/held.jpg'; h.put(path);
  const release = h.Coordinator.retainFile(path);
  assert.equal((await h.Budget.clearComic()).removed, 0);
  release(); assert.equal((await h.Budget.clearComic()).removed, 1);
  const mtimePath = '/cache/comic_images/color_test.jpg'; h.put(mtimePath);
  const before = h.files.get(mtimePath).mtime;
  h.Cache.touch(mtimePath);
  assert.equal((await h.Budget.clearComic()).removed, 0);
  assert.equal(h.files.get(mtimePath).mtime, before);
  ok('file leases and real cache hits protect files without altering image mtime');
  h.close();
}
{
  const h = harness(); const old = '/cache/comic_images/old.jpg'; h.put(old);
  h.sql.prepare('INSERT INTO book_contents(bookUrl,chapterIndex,content,pinned) VALUES(?,?,?,?)').run('legacy', 0, h.Marker.create(old), 1);
  await h.db.backfillImageReferences();
  h.failCopy(true);
  await assert.rejects(h.Cache.migrateLegacy());
  assert.ok((await h.db.getCachedChapterContent('legacy', 0)).includes(encodeURIComponent(old)));
  assert.ok(h.files.has(old));
  h.failCopy(false);
  await h.Cache.migrateLegacy();
  const text = await h.db.getCachedChapterContent('legacy', 0);
  assert.ok(text.includes('reader_images')); assert.ok(h.Cache.complete(text, true));
  assert.ok(h.files.has(old), 'live legacy references retain the old file during migration');
  assert.equal(await h.db.backfillImageReferences(), 0);
  ok('upgrade indexes old chapters; failed copy preserves old references; resumed migration commits a complete durable copy');
  h.close();
}
{
  const h = harness(); const path = '/files/reader_images/write.jpg'; h.put(path, 2);
  h.failWrites(true);
  await assert.rejects(h.Cache.commit(path, new Uint8Array([1, 2, 3]), 'source', 'https://image', 0));
  assert.equal(h.files.get(path).size, 2, 'failed temporary write must not truncate the old file');
  h.failWrites(false);
  await h.Cache.commit(path, new Uint8Array([1, 2, 3]), 'source', 'https://image', 0);
  assert.equal(h.files.get(path).size, 3);
  assert.equal((await h.db.imageResource(path)).raw, 'https://image');
  assert.ok(!h.files.has(path + '.part'));
  ok('partial writes never replace a complete original; committed images have recovery metadata');
  h.close();
}
{
  const h = harness(); h.Budget.COMIC_LIMIT_BYTES = 100;
  const path = '/files/reader_images/recent.jpg'; h.put(path, 110, 0);
  h.Budget.noteComicWrite(path);
  await h.advance(15000); assert.ok(h.files.has(path));
  assert.ok(h.timers.size > 0);
  await h.advance(601000); assert.ok(!h.files.has(path));
  ok('over-budget files are retried after protection expires, without another write or restart');
  h.close();
}
{
  const h = harness(); h.Budget.TEXT_LIMIT_BYTES = 100;
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'a'.repeat(110));
  h.Budget.noteTextWrite(); await h.advance(15000);
  assert.equal(await h.db.getOnlineCachedContentBytes(), 110);
  await h.advance(601000); assert.equal(await h.db.getOnlineCachedContentBytes(), 0);
  ok('text over-budget scheduling also retries recent protected chapters');
  h.close();
}
{
  const h = harness(); const path = '/files/reader_images/deleted.jpg';
  const row = new h.Resource(); row.path = path; row.sourceUrl = 'source'; row.raw = 'https://original'; row.state = 'missing';
  await h.db.saveImageResource(row);
  const text = h.Marker.create(path); await h.db.saveCachedChapterContent('comic', h.chapter(0), text, true);
  let downloads = 0;
  h.context.ComicImagePipeline = { async materialize() { downloads++; await Promise.resolve(); h.put(path, 100, 0); return path; } };
  const outputs = await Promise.all([h.Recovery.restore(path), h.Recovery.restore(path)]);
  assert.equal(downloads, 1); assert.deepEqual(outputs, [path, path]);
  h.files.delete(path);
  const engine = h.Engine.createBackgroundWorker(); engine.book = { bookUrl: 'comic', origin: 'source' };
  engine.source = { bookSourceUrl: 'source' }; engine.chapters = [h.chapter(0)];
  const repaired = await engine.fetchContentUncached(0);
  assert.ok(h.Cache.complete(repaired, true)); assert.equal(downloads, 2);
  assert.equal(h.sql.prepare('SELECT pinned FROM book_contents').get().pinned, 1);
  ok('missing originals recover through production chapter reads; concurrent consumers share one download and pinning survives');
  h.close();
}
{
  const h = harness(); const engine = h.Engine.createBackgroundWorker();
  engine.book = { bookUrl: 'novel', origin: 'source' }; engine.chapters = [h.chapter(0)];
  await h.db.saveCachedChapterContent('novel', engine.chapters[0], 'already cached');
  assert.equal(await engine.cacheChapter(0), true);
  assert.equal(h.sql.prepare('SELECT pinned FROM book_contents').get().pinned, 1);
  h.failSql('INSERT INTO book_contents');
  assert.equal(await engine.cacheChapter(0), false);
  ok('manual caching promotes an existing automatic chapter and reports persistence failure as failure');
  h.close();
}
{
  const h = harness();
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'old');
  const selected = await h.db.listOnlineCachedContentEntries(true);
  h.failSql('DELETE FROM reader_pagination_cache');
  await assert.rejects(h.db.deleteCachedContentEntries(selected, false, h.now()));
  assert.equal(await h.db.getCachedChapterContent('novel', 0), 'old');
  ok('a failed deletion batch rolls back content and reference changes together');
  h.close();
}
{
  const h = harness(); const engine = h.Engine.createBackgroundWorker();
  const book = { bookUrl: 'novel', origin: 'source' };
  engine.book = book; engine.source = { bookSourceUrl: 'source' };
  engine.sourceLoadedAt = h.now(); engine.sourceLoadedOrigin = 'source';
  engine.chapters = [h.chapter(0), h.chapter(1)];
  engine.openBook = async () => {}; engine.webBook.getContent = async () => 'downloaded';
  await h.db.saveCachedChapterContent('novel', engine.chapters[0], 'already cached automatically');
  h.Engine.createBackgroundWorker = () => engine;
  h.db.initWithContext = async () => {}; h.db.getBook = async () => book;
  h.context.AppStorage.setOrCreate = () => {};
  h.context.FullTextCacheCancelCoordinator = { register() {} };
  h.context.HdsFeedback = { showToast() {} }; h.context.sleepMs = async () => {};
  h.load('core/reader/ReaderFullTextCacheController.ets');
  const Controller = (await import('node:vm')).default.runInContext('ReaderFullTextCacheController', h.context);
  const controller = new Controller({ bookUrl: () => 'novel', bookName: () => 'fixture', abilityContext: () => ({}), onStateChanged() {}, onChaptersChanged() {} });
  for (const method of ['startBackgroundRunning', 'stopBackgroundRunning', 'requestNotificationEnabled', 'publishNotification', 'syncLiveEngine']) controller[method] = async () => {};
  controller.releaseCancelRegistration = () => {}; controller.taskId = 1;
  await controller.run(1, []);
  assert.equal(controller.done, 2); assert.equal(controller.total, 2);
  assert.equal(h.sql.prepare('SELECT COUNT(*) AS n FROM book_contents WHERE pinned=1').get().n, 2);
  assert.equal(controller.status, '全文缓存完成');
  ok('the real full-text task verifies and pins both previously cached and newly downloaded chapters before reporting completion');
  h.close();
}
{
  const h = harness(); h.Budget.TEXT_LIMIT_BYTES = 100;
  await h.db.saveCachedChapterContent('novel', h.chapter(0), 'a'.repeat(110)); h.age(3600000);
  const hide = h.Coordinator.watchReader(() => 'novel');
  const stopSpeech = h.Coordinator.retainBook('novel');
  h.Budget.noteTextWrite(); await h.advance(15000);
  assert.equal(await h.db.getOnlineCachedContentBytes(), 110);
  hide(); await h.advance(1500);
  assert.equal(await h.db.getOnlineCachedContentBytes(), 110, 'background speech must outlive the page');
  stopSpeech(); await h.advance(1500);
  assert.equal(await h.db.getOnlineCachedContentBytes(), 0);
  ok('leaving a reader preserves background speech, then stopping speech triggers deferred cleanup without new writes');
  h.close();
}
console.log(`\n${passed} cache integration scenarios passed`);
