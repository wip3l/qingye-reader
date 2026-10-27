// Execute the production page's non-rendering methods with controlled media/network adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const file = fs.readFileSync(new URL('../entry/src/main/ets/pages/VideoPlayer.ets', import.meta.url), 'utf8');
const support = fs.readFileSync(new URL('../entry/src/main/ets/core/book/VideoPlaybackSupport.ts', import.meta.url), 'utf8');
const attempts = file.slice(file.indexOf('class VideoNativeAttempt'), file.indexOf('interface VideoPlayerParams'));
const methods = file.slice(file.indexOf('struct VideoPlayerPage {'), file.indexOf('  @Builder'))
  .replace('struct VideoPlayerPage', 'class VideoPlayerPage')
  .replace(/@(State|StorageProp|StorageLink)(\([^\n]*?\))?\s+/g, '');
const saves = [], notices = [], requests = [], timers = new Map();
let nextTimer = 0;
class MediaController {
  calls = [];
  start() { this.calls.push('start'); }
  stop() { this.calls.push('stop'); }
  pause() { this.calls.push('pause'); }
  setCurrentTime(second) { this.calls.push(['seek', second]); }
  stopAllMedia() { this.calls.push('stopAllMedia'); }
  pauseAllMedia() { this.calls.push('pauseAllMedia'); }
  onInactive() { this.calls.push('inactive'); }
  onActive() { this.calls.push('active'); }
  accessBackward() { return false; }
}
let resolveContent = async () => ({ url: 'https://cdn.example/v.mp4', pageUrl: 'https://site.example/watch/1', error: '', headers: {} });
const context = vm.createContext({
  console: { warn() {} },
  VideoController: MediaController, webview: { WebviewController: MediaController },
  Scroller: class {}, EpisodeDataSource: class {}, SeekMode: { Accurate: 0 },
  WebBookService: class {
    cancelled = false;
    getVideoContent(...args) { requests.push(args); return resolveContent(...args); }
    cancelPendingRequests() { this.cancelled = true; }
  },
  AppDatabase: { getInstance: () => ({ updateBook: async book => saves.push(structuredClone(book)) }) },
  HdsFeedback: { showToast: text => notices.push(text) }, ReaderTtsFloatingSession: { pause: async () => {} },
  CookieStore: { saveSync() {} },
  setTimeout: (fn, ms) => { const id = ++nextTimer; timers.set(id, { fn, ms }); return id; },
  clearTimeout: id => timers.delete(id), CONTROLS_HIDE_DELAY_MS: 4000, SPEEDS: [1, 2],
});
vm.runInContext(stripTypeScriptTypes(support.replace(/^export /gm, '') + '\n' + attempts + '\n' + methods + '\n}', { mode: 'strip' }), context);
const Page = vm.runInContext('VideoPlayerPage', context);
const Support = vm.runInContext('VideoPlaybackSupport', context);
const newPage = () => {
  const page = new Page();
  page.book = { durChapterIndex: 0, durChapterPos: 85, durChapterTitle: '第一集' };
  page.source = {};
  page.chapters = [{ url: '/api/1', title: '第一集' }, { url: '/api/2', title: '第二集' }];
  page.playerPageVisible = true;
  return page;
};
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

for (const invalid of ['javascript:alert(1)', 'file:///tmp/a', 'data:text/html,x', 'https://user:pass@a/', 'https://a/\nb', 'https://a\\b']) {
  assert.equal(Support.httpUrl(invalid), '', invalid);
}
assert.equal(Support.httpUrl(' https://a.example/watch?id=1 '), 'https://a.example/watch?id=1');
assert.equal(Support.unsupported(103602), false, 'invalid source is not proof of an unsupported codec');
assert.equal(Support.unsupported(5400106), true);

const page = newPage();
await page.playEpisode(0, 85);
assert.equal(page.book.durChapterPos, 85, 'loading cannot erase resume position');
page.onVideoPrepared(300);
assert.equal(page.resumeSeekPending, true);
page.saveProgress(true);
assert.equal(page.book.durChapterPos, 85, 'pending seek cannot erase resume position');
page.resumeSeekPending = false;
page.positionSec = 97;
const old = page.nativeAttempts[0];
page.onVideoError(5400106);
assert.equal(page.webMode, true);
assert.equal(page.book.durChapterPos, 97);
assert.equal(page.nativeAttempts.length, 0);
assert.equal(page.isCurrentNative(old), false, 'stale native callbacks cannot affect the web session');
assert.equal(notices.length, 1);
page.openWebPlayback(true);
assert.equal(notices.length, 1, 'a session cannot enter web fallback twice');
const web = page.webAttempts[0];
web.attached = true;
page.webFullscreen = true;
let exited = 0;
page.fullScreenHandler = { exitFullScreen() { exited++; } };
assert.equal(page.onBackPress(), true);
assert.equal(exited, 1, 'back exits full screen first');
page.landscape = true;
assert.equal(page.onBackPress(), false, 'a naturally wide desktop window must not trap Back');
page.applyPreferredOrientation = () => {};
context.window = { Orientation: { USER_ROTATION_LANDSCAPE: 1, USER_ROTATION_PORTRAIT: 2 } };
page.manualLandscapeRequested = true;
assert.equal(page.onBackPress(), true, 'manual rotation is exited once');
assert.equal(page.manualLandscapeRequested, false);
page.onPageHide();
assert.ok(web.controller.calls.includes('pauseAllMedia'));
assert.ok(web.controller.calls.includes('inactive'));
page.positionSec = 0;
page.saveProgress(true);
assert.equal(page.book.durChapterPos, 97, 'web mode does not write fake progress');
page.positionSec = 97;
await page.playEpisode(1);
assert.ok(web.controller.calls.includes('stopAllMedia'));
assert.equal(page.isCurrentWeb(web), false);
assert.equal(page.book.durChapterIndex, 1);
assert.equal(page.book.durChapterPos, 0, 'new episode starts at zero');
page.onVideoPrepared(300);
assert.ok(!page.controller.calls.includes('start'), 'background preparation must not start playback');
page.stopPlayback();

const retry = newPage();
await retry.playEpisode(0, 85);
const beforeRetry = requests.length;
retry.onVideoError(5411002);
await flush();
assert.equal(requests.length, beforeRetry + 1);
retry.onVideoError(5411002);
await flush();
assert.equal(requests.length, beforeRetry + 1, 'only one automatic URL refresh');
assert.equal(retry.webMode, false, 'network failures require explicit web selection');
assert.equal(retry.playbackFailed, true);
assert.equal(retry.book.durChapterPos, 85);
retry.openWebPlayback();
assert.equal(retry.webMode, true);
retry.stopPlayback();

const expired = newPage();
await expired.playEpisode(0, 85);
resolveContent = async () => ({ url: '', pageUrl: '', error: '网络失败', headers: {} });
expired.onVideoError(5411002);
await flush();
assert.equal(expired.videoPageUrl, 'https://site.example/watch/1', 'failed URL refresh keeps the known episode web page');
assert.equal(expired.statusText, '网络失败');
await expired.playEpisode(1);
assert.equal(expired.videoPageUrl, '', 'old episode web page must not leak into a new episode');
expired.stopPlayback();

resolveContent = async () => ({ url: '', pageUrl: 'https://site.example/login', error: '请先登录', headers: {} });
const login = newPage();
await login.playEpisode(0, 85);
assert.equal(login.statusText, '请先登录');
assert.equal(login.webMode, false);
assert.equal(login.videoPageUrl, 'https://site.example/login');
login.openWebPlayback();
assert.equal(login.webMode, true);
login.stopPlayback();

const pending = [];
resolveContent = (...args) => new Promise(resolve => pending.push({ resolve, cancelled: args[3] }));
const racing = newPage();
const firstLoad = racing.playEpisode(0, 85);
const secondLoad = racing.playEpisode(1);
assert.equal(pending[0].cancelled(), true);
pending[1].resolve({ url: 'https://cdn.example/second.mp4', pageUrl: '', error: '' });
await secondLoad;
pending[0].resolve({ url: 'https://cdn.example/first.mp4', pageUrl: 'https://site.example/old', error: '' });
await firstLoad;
assert.equal(racing.videoUrl, 'https://cdn.example/second.mp4');
assert.equal(racing.videoPageUrl, '');
racing.onVideoError(5400106);
assert.equal(racing.webMode, false, 'never guess a web page from chapter API');
assert.equal(racing.playbackFailed, true);
racing.stopPlayback();

const timeout = newPage();
const timedLoad = timeout.playEpisode(0, 85);
const timeoutCallback = [...timers.values()].find(timer => timer.ms === 30000);
assert.ok(timeoutCallback);
timeoutCallback.fn();
await timedLoad;
assert.match(timeout.statusText, /30 秒/);
assert.equal(timeout.book.durChapterPos, 85);
assert.equal(timeout.playbackFailed, true);
assert.equal(pending[pending.length - 1].cancelled(), true, 'timed-out resolver remains cancelled after returning');
assert.equal(timers.size, 0, 'all lifecycle timers cleaned up');
console.log('video-playback-fallback-check: URL validation, resume, error classification, retry bound, stale callbacks, fullscreen, background, cancellation and timeout passed');
