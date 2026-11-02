// Run the production cover loader and audiobook metadata callbacks with delayed platform I/O.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const pending = new Map(), decodePending = new Map(), pixels = [], requests = [];
let now = 100000, closed = 0, sourcesReleased = 0;
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const tick = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const context = vm.createContext({
  console: { warn() {} }, Date: { now: () => now }, getContext: () => ({}),
  BookCoverResolver: {
    first: book => book?.coverUrl || '',
    prepareFile: (_context, raw) => {
      requests.push(raw);
      const task = deferred(); pending.set(raw, task); return task.promise;
    },
  },
  fileIo: { OpenMode: { READ_ONLY: 0 }, open: async path => ({ fd: path }), close: async () => { closed++; } },
  image: { createImageSource: path => ({
    createPixelMap: async () => {
      if (decodePending.has(path)) await decodePending.get(path).promise;
      if (path === 'broken') throw Error('decode failed');
      const pixel = { path, releases: 0, async release() { this.releases++; } };
      pixels.push(pixel); return pixel;
    },
    release: async () => { sourcesReleased++; },
  }) },
});
const source = readEtsModule('utils/AudioBookMediaSession.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
vm.runInContext(stripTypeScriptTypes(source), context);
const Holder = vm.runInContext('AudioBookAvSessionHolder', context);
const Cover = vm.runInContext('AudioBookMediaCover', context);
context.AudioBookAvSessionHolder = Holder;
const pageSource = readEtsModule('pages/AudioBook.ets');
const pageMethods = ['audioAvMetadata', 'claimMediaCommands', 'releaseAudioAvSession'].map(name => {
  const match = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(pageSource);
  assert.ok(match, name);
  return pageSource.slice(match.index, pageSource.indexOf('\n  }', match.index) + 4);
});
const page = vm.runInContext(stripTypeScriptTypes(`({${pageMethods.join(',\n')}})`), context);
Object.assign(page, {
  bookUrl: 'book-a', book: { name: 'Book A', author: 'Author', coverUrl: 'https://covers/a.jpg' },
  chapterIndex: 1, chapters: Array(5), latestDurationMs: 30000, appDarkMode: false,
  currentChapter() { return { title: `Chapter ${this.chapterIndex}` }; },
  handlesPlaybackEvents: () => true, unregisterAudioAvSessionCommands() {},
});
const published = [];
Holder.session = { setAVMetadata: async metadata => { published.push(metadata); } };
page.claimMediaCommands();
let metadata = page.audioAvMetadata();
assert.equal(metadata.title, 'Chapter 1', 'metadata is available synchronously while the cover is pending');
assert.equal(metadata.mediaImage, undefined, 'raw URL is never submitted to system media controls');
page.audioAvMetadata();
assert.equal(requests.length, 1, 'repeated progress updates share the pending cover task');

// Another page takes over and advances chapters before the first page finishes downloading.
const replacement = { ...page, chapterIndex: 3 };
replacement.claimMediaCommands();
pending.get('https://covers/a.jpg').resolve('/cache/a.jpg'); await tick();
assert.equal(published.length, 1, 'successful preparation immediately refreshes the media card');
assert.equal(published[0].title, 'Chapter 3', 'completion uses the current page and chapter');
assert.equal(published[0].mediaImage.path, '/cache/a.jpg');
assert.equal(published[0].mediaImage, published[0].avQueueImage, 'track and queue share decoded pixels');
assert.equal(replacement.audioAvMetadata().mediaImage, published[0].mediaImage, 'reopened page reuses the cover');
assert.equal(requests.length, 1);

// A slow decode from a previous book must be released rather than overwrite the new book.
const previousPixel = published[0].mediaImage;
replacement.bookUrl = 'book-b'; replacement.book = { name: 'B', coverUrl: 'https://covers/b.jpg' };
assert.equal(replacement.audioAvMetadata().mediaImage, undefined);
assert.equal(previousPixel.releases, 1, 'switching books releases the retained bitmap');
decodePending.set('/cache/b.jpg', deferred());
pending.get('https://covers/b.jpg').resolve('/cache/b.jpg'); await tick();
replacement.bookUrl = 'book-c'; replacement.book = { name: 'C', coverUrl: 'https://covers/c.jpg' };
replacement.audioAvMetadata();
pending.get('https://covers/c.jpg').resolve('/cache/c.jpg'); await tick();
decodePending.get('/cache/b.jpg').resolve(); await tick();
assert.equal(published.length, 2, 'stale decode does not publish');
assert.equal(published[1].mediaImage.path, '/cache/c.jpg');
assert.equal(pixels.find(pixel => pixel.path === '/cache/b.jpg').releases, 1);

// Failed downloads and decode failures leave playback free to proceed and are retried later.
const cover = new Cover(); let ready = 0;
cover.getImage({}, 'failure', 'failed', () => { ready++; });
pending.get('failed').reject(Error('network failed')); await tick();
const requestCount = requests.length;
cover.getImage({}, 'failure', 'failed', () => { ready++; });
assert.equal(requests.length, requestCount, 'failures have a retry cooldown');
now += 10001;
cover.getImage({}, 'failure', 'failed', () => { ready++; });
pending.get('failed').resolve('broken'); await tick();
assert.equal(ready, 0);
now += 10001;
cover.getImage({}, 'failure', 'failed', () => { ready++; });
pending.get('failed').resolve('/cache/retry.jpg'); await tick();
assert.equal(ready, 1, 'a later successful retry publishes the cover');
cover.clear();

// Destroying the session invalidates pending downloads and releases its current image.
replacement.book.coverUrl = 'https://covers/stopped.jpg'; replacement.audioAvMetadata();
const beforeStop = published.length;
Holder.session = { setAVPlaybackState: async () => {}, deactivate: async () => {}, destroy: async () => {} };
context.avSession = { PlaybackState: { PLAYBACK_STATE_STOP: 3 } };
await replacement.releaseAudioAvSession();
pending.get('https://covers/stopped.jpg').resolve('/cache/stopped.jpg'); await tick();
assert.equal(published.length, beforeStop, 'a destroyed session cannot be revived by a late cover');
assert.equal(pixels.some(pixel => pixel.path === '/cache/stopped.jpg'), false, 'stale download skips decoding');
assert.equal(Holder.session, null);
assert.equal(closed, sourcesReleased, 'all image sources and file descriptors are released');
assert.ok(pixels.every(pixel => pixel.releases === 1), 'all retained and stale bitmaps are released exactly once');
console.log('PASS audio media covers: nonblocking metadata, local pixels, deduplication, page takeover, chapter changes, stale decode, retry and session cleanup');
