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
  console: { warn() {}, info() {} },
  VideoController: MediaController, webview: { WebviewController: MediaController },
  Scroller: class {}, EpisodeDataSource: class { replace() {} }, SeekMode: { Accurate: 0, ClosestKeyframe: 3 },
  WebBookService: class {
    cancelled = false;
    getVideoContent(...args) { requests.push(args); return resolveContent(...args); }
    cancelPendingRequests() { this.cancelled = true; }
  },
  AppDatabase: { getInstance: () => ({ updateBook: async book => saves.push(structuredClone(book)) }) },
  HdsFeedback: { showToast: text => notices.push(text) }, ReaderTtsFloatingSession: { pause: async () => {}, suspendForOtherAudio: async () => {}, resumeAfterOtherAudio: async () => {} },
  CookieStore: { saveSync() {} },
  setTimeout: (fn, ms) => { const id = ++nextTimer; timers.set(id, { fn, ms }); return id; },
  clearTimeout: id => timers.delete(id), CONTROLS_HIDE_DELAY_MS: 4000, SPEEDS: [1, 1.25, 1.75, 2, 0.75],
  DISPLAY_MODES: ['contain', 'none', 'cover', 'fill'],
  ImageFit: { Contain: 0, None: 1, Cover: 2, Fill: 3 },
  RESUME_WAIT_MS: 15000, STALL_HINT_MS: 8000, STALL_RELOAD_MS: 25000, MAX_STALL_RELOADS: 2,
  PAUSE_REFRESH_MS: 600000, XComponentController: class {},
  VideoAvSession: class {
    calls = [];
    constructor(url, headers, speed, listener) { Object.assign(this, { url, headers, speed, listener }); }
    open() { this.calls.push('open'); }
    start() { this.calls.push('start'); }
    pause() { this.calls.push('pause'); }
    seek(second, accurate) { this.calls.push(['seek', second, accurate]); }
    setSpeed(speed) { this.calls.push(['speed', speed]); }
    release() { this.calls.push('release'); }
  },
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

const seeking = newPage();
await seeking.playEpisode(0, 85);
seeking.seekBy(15);
assert.equal(seeking.positionSec, 85, 'unprepared media cannot seek');
seeking.onVideoUpdated(0);
assert.equal(seeking.positionSec, 85, 'preparation updates must retain the retry/resume target');
seeking.onVideoPrepared(300);
seeking.onVideoUpdated(0);
assert.equal(seeking.book.durChapterPos, 85, 'initial media update cannot erase resume position');
seeking.onVideoSeeked(85);
assert.equal(seeking.resumeNotice, '已恢复到 01:25');
assert.equal(seeking.canSeek(), true);
seeking.isPlaying = false;
const seekCalls = seeking.controller.calls.length;
seeking.seekBy(15);
seeking.seekBy(15);
seeking.seekBy(15);
assert.equal(seeking.positionSec, 130, 'rapid taps accumulate from the requested position');
assert.equal(seeking.book.durChapterPos, 130, 'immediate exit can recover the selected target');
assert.equal(seeking.controller.calls.length, seekCalls + 1, 'only one seek is submitted at a time');
seeking.onVideoUpdated(86);
assert.equal(seeking.positionSec, 130, 'updates before the seek callback cannot move the progress backwards');
seeking.onVideoSeeked(100);
assert.equal(seeking.controller.calls.at(-1)[1], 130, 'intermediate completion submits the latest queued target');
assert.equal(seeking.positionSec, 130);
seeking.onVideoSeeked(130);
assert.equal(seeking.pendingSeekSec, -1);
assert.equal(seeking.resumeNotice, '', 'manual seeking dismisses the resume prompt');
assert.equal(seeking.isPlaying, false, 'seeking preserves pause state');
seeking.seekBy(-1000);
assert.equal(seeking.positionSec, 0);
seeking.onVideoSeeked(0);
seeking.seekBy(1000);
assert.equal(seeking.positionSec, 300);
seeking.onVideoSeeked(300);
seeking.seeking = true;
seeking.positionSec = 40;
seeking.onVideoUpdated(299);
seeking.saveProgress(true);
assert.equal(seeking.book.durChapterPos, 300, 'slider preview must not be saved before release');
seeking.seeking = false;
seeking.seekTo(40);
seeking.onVideoSeeked(40);
seeking.positionSec = 43;
seeking.isPlaying = true;
seeking.togglePlay();
assert.equal(seeking.book.durChapterPos, 43, 'pause immediately saves even within the ten-second interval');
seeking.restartPlayback();
assert.equal(seeking.book.durChapterPos, 0);
assert.equal(seeking.controller.calls.at(-1), 'start');
seeking.onVideoSeeked(0);
seeking.openPlaybackSpeeds();
assert.equal(seeking.playerOptionsMode, 'speed');
const beforeSpeed = seeking.controller.calls.length;
seeking.selectSpeed(1.25);
assert.equal(seeking.speed, 1.25);
assert.equal(seeking.showDisplayModes, false);
assert.equal(seeking.controller.calls.length, beforeSpeed, 'speed selection preserves the player and position');
seeking.selectSpeed(1.5);
assert.equal(seeking.speed, 1.25, 'unsupported video rates are rejected');
seeking.openDisplayModes();
assert.equal(seeking.playerOptionsMode, 'display');
seeking.autoNext = false;
seeking.onVideoFinished();
assert.equal(seeking.book.durChapterPos, 300, 'finishing saves the final position');
seeking.stopPlayback();
assert.equal(seeking.canSeek(), false);
assert.equal(seeking.pendingSeekSec, -1);

// Reopen through the actual loadBook path using the last persisted book snapshot.
const stored = structuredClone(saves.findLast(book => book.durChapterPos === 43));
const database = context.AppDatabase;
context.getContext = () => ({});
context.AppDatabase = { getInstance: () => ({
  initWithContext: async () => {}, getBook: async () => stored, getBookSource: async () => ({}),
  updateBook: async book => saves.push(structuredClone(book)),
}) };
stored.bookUrl = 'https://site.example/series';
stored.origin = 'https://site.example';
const reopened = newPage();
const engine = { openBook: async () => {}, book: stored, chapters: reopened.chapters };
context.ReadBookEngine = { get: () => engine };
await reopened.loadBook(stored.bookUrl, -1);
reopened.onVideoPrepared(300);
assert.equal(reopened.controller.calls.find(call => Array.isArray(call) && call[0] === 'seek')[1], 43);
reopened.onVideoSeeked(43);
assert.equal(reopened.resumeNotice, '已恢复到 00:43');
reopened.stopPlayback();
context.AppDatabase = database;

// Controller-driven seeks may only report onUpdate; onSeeked belongs to the native progress bar.
const progressOnly = newPage();
await progressOnly.playEpisode(0, 12);
progressOnly.onVideoPrepared(150);
progressOnly.onVideoUpdated(0);
assert.equal(progressOnly.book.durChapterPos, 12, 'startup zero must not erase the saved position');
progressOnly.onVideoUpdated(12);
assert.equal(progressOnly.resumeSeekPending, false, 'onUpdate must confirm resume without onSeeked');
assert.equal(progressOnly.canSeek(), true, 'resume completion must enable the seek controls');
progressOnly.onVideoUpdated(13);
assert.equal(progressOnly.positionSec, 13, 'the recorded frozen 00:12 must advance');
progressOnly.seekBy(15);
progressOnly.seekBy(15);
progressOnly.onVideoUpdated(28);
assert.equal(progressOnly.controller.calls.at(-1)[1], 43, 'progress confirmation releases the queued seek');
progressOnly.onVideoSeeked(28);
assert.equal(progressOnly.positionSec, 43, 'a delayed old completion cannot confirm the newer target');
progressOnly.onVideoUpdated(43);
progressOnly.onVideoUpdated(44);
assert.equal(progressOnly.positionSec, 44);
assert.equal(progressOnly.pendingSeekSec, -1);
progressOnly.stopPlayback();

const missingConfirmation = newPage();
await missingConfirmation.playEpisode(0, 12);
missingConfirmation.onVideoPrepared(150);
missingConfirmation.onVideoUpdated(4);
let seekWatchdog = timers.get(missingConfirmation.seekTimerId);
assert.ok(seekWatchdog, 'seek confirmation must have a bounded wait');
timers.delete(missingConfirmation.seekTimerId);
seekWatchdog.fn();
assert.equal(missingConfirmation.resumeSeekPending, true, 'first timeout retries the resume on a keyframe');
assert.equal(missingConfirmation.seekAccurate, false);
assert.equal(missingConfirmation.controller.calls.at(-1)[1], 12);
missingConfirmation.onVideoUpdated(4);
seekWatchdog = timers.get(missingConfirmation.seekTimerId);
timers.delete(missingConfirmation.seekTimerId);
seekWatchdog.fn();
assert.equal(missingConfirmation.resumeSeekPending, false);
assert.equal(missingConfirmation.canSeek(), true);
assert.equal(missingConfirmation.resumeFailedSec, 12);
assert.equal(missingConfirmation.resumeNotice, '没能跳到上次的 00:12', 'an unconfirmed resume must not announce success');
missingConfirmation.onVideoUpdated(5);
assert.equal(missingConfirmation.positionSec, 5, 'timeout returns to actual media updates');
missingConfirmation.saveProgress(true);
assert.equal(missingConfirmation.book.durChapterPos, 12, 'a failed resume keeps the saved position until playback reaches it');
missingConfirmation.isPlaying = false;
missingConfirmation.seekBy(15);
missingConfirmation.seekBy(15);
seekWatchdog = timers.get(missingConfirmation.seekTimerId);
timers.delete(missingConfirmation.seekTimerId);
seekWatchdog.fn();
assert.equal(missingConfirmation.controller.calls.at(-1)[1], 35, 'timeout still submits the latest queued target');
const staleWatchdog = timers.get(missingConfirmation.seekTimerId);
missingConfirmation.stopPlayback();
staleWatchdog.fn();
assert.equal(missingConfirmation.pendingSeekSec, -1, 'a retired attempt cannot be changed by an old timer');

const pausedSeek = newPage();
await pausedSeek.playEpisode(0);
pausedSeek.onVideoPrepared(150);
pausedSeek.isPlaying = false;
pausedSeek.seekTo(30);
const pausedWatchdog = timers.get(pausedSeek.seekTimerId);
timers.delete(pausedSeek.seekTimerId);
pausedWatchdog.fn();
assert.equal(pausedSeek.pendingSeekSec, -1, 'a paused player with no updates cannot permanently lock seeking');
assert.equal(pausedSeek.canSeek(), true);
pausedSeek.onVideoUpdated(31);
assert.equal(pausedSeek.positionSec, 31);
assert.equal(pausedSeek.isPlaying, false, 'recovery never starts a paused player');
pausedSeek.stopPlayback();

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

resolveContent = async () => ({ url: 'https://cdn.example/v.mp4', pageUrl: 'https://site.example/watch/1', error: '' });
const display = newPage();
await display.playEpisode(0, 85);
display.onVideoPrepared(300);
display.resumeSeekPending = false;
display.positionSec = 97;
display.isPlaying = true;
const displayAttempt = display.nativeAttempts[0];
const controllerCalls = structuredClone(display.controller.calls);
const requestCount = requests.length;
display.openDisplayModes();
assert.equal(display.hideTimerId, -1, 'the mode menu cancels auto-hide');
display.scheduleHideControls();
const displayTimerId = display.hideTimerId;
timers.get(displayTimerId).fn();
timers.delete(displayTimerId);
assert.equal(display.showControls, true, 'playback callbacks cannot hide controls while selecting a mode');
for (const mode of ['none', 'cover', 'fill', 'contain']) {
  display.openDisplayModes();
  display.selectDisplayMode(mode);
  assert.equal(display.displayMode, mode);
  assert.equal(display.showDisplayModes, false);
  assert.equal(display.nativeAttempts[0], displayAttempt, 'display changes preserve the native player instance');
  assert.deepEqual(display.controller.calls, controllerCalls, 'display changes must not pause, seek or restart playback');
  assert.equal(display.positionSec, 97);
  assert.equal(display.isPlaying, true);
}
assert.equal(requests.length, requestCount, 'display changes must not resolve the source again');
display.selectDisplayMode('invalid');
assert.equal(display.displayMode, 'contain');
display.selectDisplayMode('cover');
display.openDisplayModes();
display.manualLandscapeRequested = true;
assert.equal(display.onBackPress(), true);
assert.equal(display.showDisplayModes, false);
assert.equal(display.manualLandscapeRequested, true, 'Back closes the menu before leaving landscape');
await display.playEpisode(1);
assert.equal(display.displayMode, 'cover', 'switching episodes retains the selected display mode');
display.openDisplayModes();
display.openWebPlayback();
assert.equal(display.showDisplayModes, false, 'web fallback cannot retain a native-only menu');
display.openDisplayModes();
assert.equal(display.showDisplayModes, false);
await display.playEpisode(1);
assert.equal(display.displayMode, 'cover', 'returning from web playback retains the selected mode');
display.openDisplayModes();
display.onPageHide();
assert.equal(display.showDisplayModes, false);
display.stopPlayback();

// The same player preparing again (e.g. reclaimed in the background) must return to the last position, not zero.
const reprepare = newPage();
await reprepare.playEpisode(0);
reprepare.onVideoPrepared(300);
reprepare.handleNativeStart(reprepare.nativeAttempts[0]);
reprepare.onVideoUpdated(1);
reprepare.onVideoUpdated(50);
assert.equal(reprepare.book.durChapterPos, 50);
reprepare.onVideoPrepared(300);
assert.deepEqual(reprepare.controller.calls.findLast(call => Array.isArray(call)), ['seek', 50]);
assert.equal(reprepare.controller.calls.at(-1), 'start', 'a playing player resumes after re-preparing');
reprepare.onVideoUpdated(0);
reprepare.saveProgress(true);
assert.equal(reprepare.book.durChapterPos, 50, 're-preparation cannot erase the position');
reprepare.onVideoUpdated(50);
assert.equal(reprepare.resumeSeekPending, false);
reprepare.handleNativePause(reprepare.nativeAttempts[0]);
const pausedCalls = reprepare.controller.calls.length;
reprepare.onVideoPrepared(300);
assert.equal(reprepare.controller.calls.length, pausedCalls, 'a paused player is not seeked or started yet');
assert.equal(reprepare.deferredResumeSec, 50);
reprepare.onVideoUpdated(0);
reprepare.saveProgress(true);
assert.equal(reprepare.book.durChapterPos, 50, 'deferred resume keeps the saved position');
reprepare.togglePlay();
assert.deepEqual(reprepare.controller.calls.slice(pausedCalls), [['seek', 50], 'start'], 'play seeks back first');
reprepare.stopPlayback();

// A paused URL may have expired: resuming after a long pause resolves the address again at the same position.
const longPause = newPage();
await longPause.playEpisode(0);
longPause.onVideoPrepared(300);
longPause.handleNativeStart(longPause.nativeAttempts[0]);
longPause.onVideoUpdated(1);
longPause.onVideoUpdated(70);
longPause.handleNativePause(longPause.nativeAttempts[0]);
longPause.pausedAt = Date.now() - 11 * 60 * 1000;
const beforeRefresh = requests.length;
longPause.togglePlay();
assert.equal(requests.length, beforeRefresh + 1, 'long pause refreshes the playback address');
await flush();
assert.equal(longPause.book.durChapterPos, 70);
assert.equal(longPause.resumeSec, 70);
assert.equal(longPause.retried, false, 'refreshing keeps the automatic error retry');
longPause.stopPlayback();

// Expired addresses answer 403; that is retried once with a fresh address too.
const forbidden = newPage();
await forbidden.playEpisode(0, 30);
const beforeForbidden = requests.length;
forbidden.onVideoError(5411005);
await flush();
assert.equal(requests.length, beforeForbidden + 1);
assert.equal(forbidden.resumeSec, 30);
forbidden.onVideoError(5411005);
assert.equal(forbidden.playbackFailed, true);
forbidden.stopPlayback();

// Video has no buffering events: lack of progress first shows a hint, then reloads twice, then fails visibly.
const stall = newPage();
await stall.playEpisode(0);
assert.ok(timers.get(stall.stallTimerId), 'the stall watch runs while native playback is active');
stall.onVideoPrepared(300);
stall.handleNativeStart(stall.nativeAttempts[0]);
stall.onVideoUpdated(1);
stall.onVideoUpdated(40);
stall.lastProgressAt = Date.now() - 9000;
stall.checkStall();
assert.equal(stall.statusText, '网络较慢，正在缓冲...');
stall.onVideoUpdated(41);
assert.equal(stall.statusText, '', 'progress clears the buffering hint');
stall.handleNativePause(stall.nativeAttempts[0]);
stall.lastProgressAt = Date.now() - 60000;
stall.checkStall();
assert.equal(stall.statusText, '', 'a user pause is never treated as a stall');
stall.togglePlay();
stall.lastProgressAt = Date.now() - 26000;
const beforeStall = requests.length;
stall.checkStall();
assert.equal(requests.length, beforeStall + 1, 'a long stall resolves the address again');
await flush();
assert.equal(stall.resumeSec, 41);
stall.lastProgressAt = Date.now() - 26000;
stall.checkStall();
await flush();
assert.equal(requests.length, beforeStall + 2);
stall.lastProgressAt = Date.now() - 26000;
stall.checkStall();
assert.equal(requests.length, beforeStall + 2, 'automatic reloads are bounded');
assert.equal(stall.playbackFailed, true);
assert.equal(stall.book.durChapterPos, 41);
assert.equal(stall.stallTimerId, -1);
stall.stopPlayback();

// Automatic recovery budgets refill once playback has run steadily past the recovery point.
const refill = newPage();
await refill.playEpisode(0, 100);
refill.onVideoError(5411002);
await flush();
assert.equal(refill.retried, true);
refill.onVideoPrepared(600);
refill.onVideoUpdated(100);
refill.onVideoUpdated(120);
assert.equal(refill.retried, true, 'twenty seconds is not yet steady playback');
refill.onVideoUpdated(131);
assert.equal(refill.retried, false, 'steady playback restores the automatic retry');
const beforeRefill = requests.length;
refill.onVideoError(5411002);
await flush();
assert.equal(requests.length, beforeRefill + 1);
refill.handleNativeStart(refill.nativeAttempts[0]);
refill.pausedAt = 0;
refill.onPageHide();
assert.ok(refill.pausedAt > 0, 'hiding the page records the pause time even without onPause');
refill.stopPlayback();

// Sources with media headers play through AVPlayer; Video cannot send request headers.
resolveContent = async () => ({ url: 'https://cdn.example/h.m3u8', pageUrl: '', error: '',
  headers: { Referer: 'https://site.example/' } });
const headed = newPage();
await headed.playEpisode(0, 20);
const session = headed.nativeAttempts[0].session;
assert.ok(session, 'media headers select the AVPlayer session');
assert.deepEqual(session.headers, { Referer: 'https://site.example/' });
assert.deepEqual(session.calls, ['open']);
headed.onVideoPrepared(300);
assert.deepEqual(session.calls.slice(1), [['seek', 20, true], 'start']);
assert.equal(headed.controller.calls.length, 0, 'the unused Video controller receives nothing');
headed.selectSpeed(1.25);
assert.deepEqual(session.calls.at(-1), ['speed', 1.25]);
headed.stopPlayback();
assert.equal(session.calls.at(-1), 'release');
resolveContent = async () => ({ url: 'https://cdn.example/u.mp4', pageUrl: '', error: '',
  headers: { 'User-Agent': 'Mozilla/5.0' } });
const agentOnly = newPage();
await agentOnly.playEpisode(0);
assert.equal(agentOnly.nativeAttempts[0].session, null, 'a User-Agent alone keeps the Video component');
agentOnly.stopPlayback();
resolveContent = async () => ({ url: 'https://cdn.example/v.mp4', pageUrl: 'https://site.example/watch/1', error: '' });

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
console.log('video-playback-fallback-check: fallback, persisted resume, missing seek callbacks, bounded seek recovery, re-preparation, stalls, expired addresses, header playback, queued 15-second seeking, pause/restart, menus and lifecycle passed');
