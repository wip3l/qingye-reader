import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// Exercise the real chapter engine, marker materialization, result registry and scheduler.
// Only the network/image bytes and database are replaced; no device or remote server is needed.
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
async function until(predicate) {
  for (let i = 0; i < 100; i++) {
    if (predicate()) return;
    await tick();
  }
  assert.ok(predicate(), 'asynchronous work did not settle');
}

function harness() {
  const timers = [];
  const downloads = [];
  const requests = [];
  const disk = new Map();
  let hold = false;
  const releases = [];
  const context = vm.createContext({
    console: { log() {}, info() {}, warn() {}, error() {} },
    setTimeout: callback => { timers.push(callback); return timers.length; },
    setInterval, clearInterval,
    HttpClient: class { static CANCELLED_ERROR = 'cancelled'; },
    ComicImageTiming: class {},
    ComicImagePipeline: { async materialize(_http, _source, raw, force, cancelled) {
      assert.equal(force, true, 'ordinary remote images must also be saved to disk');
      downloads.push(raw);
      if (hold) await new Promise(resolve => releases.push(resolve));
      if (cancelled()) throw new Error('cancelled');
      return `/cache/${raw.split('/').at(-1)}`;
    } },
    appDb: {
      async getCachedChapterContent(_book, idx) { return disk.get(idx) || ''; },
      async saveCachedChapterContent(_book, chapter, text) { disk.set(chapter.index, text); },
      async touchCachedChapterContent() {}
    },
    fs: { statSync: () => ({ isFile: () => true, size: 1 }) },
    AppStorage: { get: () => '/cache' },
    ReaderOpenTrace: { mark() {} },
    ReaderCacheBudget: { noteTextWrite() {} },
    ReaderActionMarker: { hasLegacy() { return false; } }
  });
  for (const file of ['ReaderCacheCoordinator', 'ReaderImageMarker', 'ReaderImageReferences', 'ReaderImageCache', 'ReaderImageScheduler', 'ReaderImageResults', 'WebBookService', 'ReadBookEngine']) {
    vm.runInContext(stripTypeScriptTypes(readEtsModule(`core/book/${file}.ts`)
      .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  }
  const { engine, Marker, Scheduler } = vm.runInContext(
    '({ engine: new ReadBookEngine(), Marker: ReaderImageMarker, Scheduler: ReaderImageScheduler })', context);
  engine.foregroundReader = true;
  engine.setReaderImagesDeferred(true);
  engine.book = { bookUrl: 'test-book', origin: 'test-source' };
  engine.source = { bookSourceUrl: 'test-source' };
  engine.sourceLoadedOrigin = 'test-source';
  engine.sourceLoadedAt = Date.now();
  engine.chapters = Array.from({ length: 15 }, (_, index) => ({ index, cacheDate: 0 }));
  engine.webBook.getContent = async function(source, _book, chapter, _cancel, _debug, request) {
    requests.push(chapter.index);
    const text = Array.from({ length: 8 }, (_, i) =>
      Marker.create(`https://images.test/${chapter.index}-${i}.jpg`)).join('\n\n');
    return this.materializeReaderImageMarkers(source, text, _cancel, request);
  };
  return { engine, Marker, Scheduler, downloads, requests, disk,
    flushTimers() { for (const callback of timers.splice(0)) callback(); },
    hold() { hold = true; },
    release() { hold = false; for (const resolve of releases.splice(0)) resolve(); }
  };
}

// Chapter count controls all images, including more images than the old 3/5/10-page option.
for (const count of [1, 3, 10]) {
  const h = harness();
  h.engine.preloadAround(0, count, 0);
  h.flushTimers();
  await until(() => h.disk.size === count);
  assert.deepEqual(h.requests, Array.from({ length: count }, (_, i) => i + 1));
  assert.equal(h.downloads.length, count * 8);
  for (const text of h.disk.values()) {
    assert.equal(h.Marker.hasPending(text), false);
    assert.equal(text.split('\n\n').length, 8);
    assert.ok(!text.includes('https'));
  }
}

// Disabling before scheduled jobs run prevents even chapter requests.
{
  const h = harness();
  h.engine.preloadAround(0, 3, 0);
  h.engine.setPreloadChapterCounts(0);
  h.flushTimers();
  await tick();
  assert.deepEqual(h.requests, []);
}

// Shrinking while images are queued cancels excess chapters, preserves completed files,
// and lets a later increase restart the cancelled chapters without stale pending markers.
{
  const h = harness();
  h.hold();
  h.engine.preloadAround(0, 3, 0);
  h.flushTimers();
  await until(() => h.engine.deferredChapterTexts.size === 3);
  h.engine.setPreloadChapterCounts(1);
  assert.equal(h.engine.getCachedContent(2), '');
  h.release();
  await until(() => h.Scheduler.active === 0 && h.Scheduler.queue.length === 0);
  await tick();
  assert.deepEqual([...h.disk.keys()], [1]);
  assert.equal(h.downloads.length, 8);
  h.engine.preloadAround(0, 3, 0);
  h.flushTimers();
  await until(() => h.disk.size === 3);
  assert.equal(h.downloads.length, 24);
}

// Turning into a preloaded chapter promotes its work to foreground. Turning off preloading
// keeps that chapter intact and stops the rest; it does not strand the displayed markers.
{
  const h = harness();
  h.hold();
  h.engine.preloadAround(0, 3, 0);
  h.flushTimers();
  await until(() => h.engine.deferredChapterTexts.size === 3);
  const current = await h.engine.loadContent(1);
  assert.equal(h.Marker.hasPending(current), true);
  h.engine.setPreloadChapterCounts(0);
  h.release();
  await until(() => h.Scheduler.active === 0 && h.Scheduler.queue.length === 0);
  await tick();
  assert.deepEqual([...h.disk.keys()], [1]);
  assert.equal(h.downloads.length, 8);
  // Explicitly requested adjacent content remains available even with preloading off.
  await h.engine.peekContent(2);
  await until(() => h.disk.has(2));
}

// Re-enable before cancelled image work finishes: old finalizers must not delete
// the replacement chapter, even when both requests produce identical pending text.
{
  const h = harness();
  h.hold();
  h.engine.preloadAround(0, 2, 0);
  h.flushTimers();
  await until(() => h.engine.deferredChapterTexts.size === 2);
  h.engine.setPreloadChapterCounts(0);
  h.engine.preloadAround(0, 2, 0);
  h.flushTimers();
  await until(() => h.requests.length === 4);
  h.release();
  await until(() => h.disk.size === 2);
  assert.ok(h.engine.getCachedContent(1));
  assert.ok(h.engine.getCachedContent(2));
  assert.equal(h.Scheduler.queue.length, 0);
}

// Adjacent content already attached to the reader must survive turning the switch off.
{
  const h = harness();
  h.hold();
  h.engine.preloadAround(0, 2, 0);
  h.flushTimers();
  await until(() => h.engine.deferredChapterTexts.size === 2);
  await h.engine.peekContent(1);
  h.engine.setPreloadChapterCounts(0);
  h.release();
  await until(() => h.disk.has(1) && h.Scheduler.active === 0);
  assert.equal(h.disk.has(2), false);
}

// Legacy comic preferences must not reintroduce a second network-cache limit.
{
  const context = vm.createContext({});
  for (const file of ['ReaderPageTurnAnimation.ts', 'ReaderComicSettings.ets']) {
    vm.runInContext(stripTypeScriptTypes(readEtsModule(`core/reader/${file}`)
      .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  }
  const settings = vm.runInContext('ReaderComicSettings.parse(\'{"preloadCount":0,"pageGap":16}\')', context);
  assert.equal(settings.pageGap, 16);
  assert.equal('preloadCount' in JSON.parse(settings.copy().toJson()), false);
}

console.log('reader-chapter-preload-check: ok');
