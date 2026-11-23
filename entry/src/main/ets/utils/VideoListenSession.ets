import { avSession } from '../platform/MediaSession';
import { common, WantAgent } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { Book, BookChapter, BookSource } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { VideoPlaybackSource } from '../core/book/VideoPlaybackSupport';
import { AudioBookMediaCover } from './AudioBookMediaSession';
import { BackgroundPermit } from './BackgroundPermit';
import { BookCoverResolver } from './BookCoverResolver';
import { MixedVideoProgress } from './MixedVideoProgress';
import { ReaderTtsFloatingSession } from './ReaderTtsFloatingSession';
import { RemoteAudioPlayback, RemoteAudioPlaybackListener } from './RemoteAudioPlayback';
import { createLaunchAgent } from '../platform/LaunchAgent';

/** 播放页把正在看的视频交过来时带的信息。book 与播放页是同一个对象，进度写在它上面。 */
export interface VideoListenRequest {
  context: common.UIAbilityContext;
  book: Book;
  source: BookSource;
  /** 选集列表：普通视频书是全部章节，图文书只列视频章。 */
  chapters: BookChapter[];
  mixed: boolean;
  episodeIndex: number;
  url: string;
  headers: Record<string, string>;
  positionSec: number;
  speed: number;
  autoNext: boolean;
}

/** 回到画面时交还给播放页的位置。episodeIndex 是选集列表里的位置。 */
export interface VideoListenSnapshot {
  bookUrl: string;
  episodeIndex: number;
  positionSec: number;
  speed: number;
  autoNext: boolean;
}

const OWNER_ID: string = 'video_listen';
const PERMIT_OWNER: string = 'video-listen';
const RESOLVE_TIMEOUT_MS: number = 30000;
// 和播放页一致：暂停太久，带时效的播放地址多半已过期，继续时直接重取地址。
const PAUSE_REFRESH_MS: number = 10 * 60 * 1000;
const SAVE_STEP_SEC: number = 10;
const AV_POSITION_STEP_MS: number = 5000;
const KEEP_ALIVE_MS: number = 30000;
const SEEK_STEP_MS: number = 15000;

/**
 * 熄屏听视频：只放视频的声音，锁屏、切后台、离开播放页都继续。
 *
 * 借用听书的进程级播放器 RemoteAudioPlayback（不挂画面时 AVPlayer 只解码音轨），
 * 打断、耳机断开、音量增益、定时都和听书一致；两者本来就不会同时播放。
 * 悬浮伴生条、播放面板走共享会话 ReaderTtsFloatingSession（模式 video），系统媒体控件用自己的 AVSession。
 * 进度与播放页共用：普通视频书记在 book.durChapter*，图文书的视频章记在 MixedVideoProgress。
 *
 * 必须放在 utils 模块里：pages 下的类静态字段每次开页都是新的。
 */
export class VideoListenSession implements RemoteAudioPlaybackListener {
  /** 正在听的书；没在听时为空。播放页据此判断要不要显示听视频画面。 */
  static readonly BOOK_KEY: string = 'videoListenBookUrl';
  /** 正在听的集在选集列表里的位置，自动连播或从面板选集后播放页跟着变。 */
  static readonly EPISODE_KEY: string = 'videoListenEpisodeIndex';
  private static instance: VideoListenSession | null = null;

  private readonly playback: RemoteAudioPlayback = RemoteAudioPlayback.get();
  private context: common.UIAbilityContext | null = null;
  private book: Book | null = null;
  private source: BookSource | null = null;
  private chapters: BookChapter[] = [];
  private mixed: boolean = false;
  private episodeIndex: number = 0;
  private autoNext: boolean = true;
  private speed: number = 1;
  private url: string = '';
  private headers: Record<string, string> = {};
  private active: boolean = false;
  /** 正在取这一集的播放地址；这期间播放器报的状态和进度都不算。 */
  private resolving: boolean = false;
  private resolveSerial: number = 0;
  private service: WebBookService | null = null;
  private resolveTimerId: number = -1;
  private failed: boolean = false;
  private retried: boolean = false;
  private statusText: string = '';
  private positionMs: number = 0;
  private durationMs: number = 0;
  private pausedAt: number = 0;
  private lastSavedSec: number = -1;
  private timerMinutes: number = 0;
  private timerTickId: number = -1;
  private keepAliveId: number = -1;
  private lastAvPositionAt: number = 0;
  private session: avSession.AVSession | null = null;
  private sessionStarting: boolean = false;
  private launchAgent: WantAgent | null = null;
  private backgroundQueue: Promise<void> = Promise.resolve();
  private readonly mediaCover: AudioBookMediaCover = new AudioBookMediaCover();
  /** 播放页停在听视频画面时登记：点“看画面”直接在那一页恢复，不再另开一页。 */
  private hostResume: (() => void) | null = null;

  static get(): VideoListenSession {
    if (!VideoListenSession.instance) VideoListenSession.instance = new VideoListenSession();
    return VideoListenSession.instance;
  }

  isListening(bookUrl: string): boolean {
    return this.active && !!this.book && this.book.bookUrl === bookUrl;
  }

  setHost(resume: (() => void) | null): void {
    this.hostResume = resume;
  }

  async start(request: VideoListenRequest): Promise<void> {
    if (this.active) await this.stop();
    // 换成听视频后，被视频暂停的听书或朗读就不再自动恢复了。
    await ReaderTtsFloatingSession.stopOther(OWNER_ID);
    this.context = request.context;
    this.book = request.book;
    this.source = request.source;
    this.chapters = request.chapters.slice();
    this.mixed = request.mixed;
    this.episodeIndex = Math.max(0, Math.min(request.episodeIndex, this.chapters.length - 1));
    this.autoNext = request.autoNext;
    this.speed = request.speed > 0 ? request.speed : 1;
    this.url = request.url;
    this.headers = request.headers;
    this.positionMs = Math.max(0, Math.floor(request.positionSec * 1000));
    this.durationMs = 0;
    this.lastSavedSec = Math.floor(request.positionSec);
    this.failed = false;
    this.retried = false;
    this.pausedAt = 0;
    this.statusText = '正在缓冲…';
    this.active = true;
    this.playback.claim(this, true);
    AppStorage.setOrCreate(VideoListenSession.BOOK_KEY, request.book.bookUrl);
    AppStorage.setOrCreate(VideoListenSession.EPISODE_KEY, this.episodeIndex);
    this.publishSession();
    this.startKeepAlive();
    this.enqueueBackground((): Promise<void> => this.ensureBackground());
    await this.playUrl(this.positionMs);
  }

  /** 播放页要回到画面：停掉声音，交还当前位置。没在听这本书时返回 null。 */
  async takeOver(bookUrl: string): Promise<VideoListenSnapshot | null> {
    if (!this.isListening(bookUrl)) return null;
    const snapshot: VideoListenSnapshot = {
      bookUrl: bookUrl,
      episodeIndex: this.episodeIndex,
      positionSec: Math.floor(this.positionMs / 1000),
      speed: this.speed,
      autoNext: this.autoNext
    };
    await this.stop();
    return snapshot;
  }

  setAutoNext(enabled: boolean): void {
    this.autoNext = enabled;
  }

  episode(): number {
    return this.episodeIndex;
  }

  async stop(): Promise<void> {
    if (!this.active) return;
    this.saveProgress(true);
    this.active = false;
    this.resolving = false;
    this.resolveSerial++;
    this.cancelResolve();
    this.clearTimerTick();
    this.stopKeepAlive();
    this.timerMinutes = 0;
    this.hostResume = null;
    // 先停播放器再交还回调：停止时的 idle 不能转给听书页。
    await this.playback.stop();
    this.playback.release(this);
    ReaderTtsFloatingSession.clear(OWNER_ID);
    AppStorage.setOrCreate(VideoListenSession.BOOK_KEY, '');
    AppStorage.setOrCreate(VideoListenSession.EPISODE_KEY, -1);
    await this.enqueueBackground((): Promise<void> => this.releaseBackground());
  }

  // ---- RemoteAudioPlaybackListener ----

  onStateChanged(state: string): void {
    if (!this.active || this.resolving) return;
    if (state === 'playing') {
      this.pausedAt = 0;
      this.failed = false;
      this.statusText = '';
      this.enqueueBackground((): Promise<void> => this.ensureBackground());
    } else if (state === 'paused' || state === 'stopped') {
      if (this.pausedAt <= 0) this.pausedAt = Date.now();
      this.saveProgress(true);
    }
    this.publishDetails();
    this.updateAvState();
  }

  onPositionChanged(positionMs: number, durationMs: number): void {
    if (!this.active || this.resolving) return;
    this.positionMs = Math.max(0, positionMs);
    this.durationMs = Math.max(0, durationMs);
    ReaderTtsFloatingSession.updateAudioProgress(OWNER_ID, this.positionMs, this.durationMs);
    this.saveProgress(false);
    const now = Date.now();
    if (now - this.lastAvPositionAt >= AV_POSITION_STEP_MS) {
      this.lastAvPositionAt = now;
      this.updateAvState();
    }
  }

  onPlaybackCompleted(): void {
    if (!this.active || this.resolving) return;
    if (this.durationMs > 0) this.positionMs = this.durationMs;
    this.saveProgress(true);
    if (this.autoNext && this.episodeIndex < this.chapters.length - 1) {
      this.playEpisode(this.episodeIndex + 1, 0);
      return;
    }
    this.statusText = this.episodeIndex >= this.chapters.length - 1 ? '已播完最后一集' : '';
    this.publishDetails();
    this.updateAvState();
  }

  onPlaybackError(message: string): void {
    if (!this.active || this.resolving) return;
    console.warn(`[VideoListen] playback error episode=${this.episodeIndex}: ${message}`);
    // 带时效的地址过期也会报错：重取一次地址从原位置接着放。
    if (!this.retried) {
      this.retried = true;
      this.playEpisode(this.episodeIndex, Math.floor(this.positionMs / 1000), true);
      return;
    }
    this.markFailed('这一集播放失败，可以点“看画面”重试');
  }

  // ---- 控制 ----

  isPlaying(): boolean {
    if (this.resolving) return true;
    const state = this.playback.state;
    return state === 'playing' || state === 'loading' || state === 'initialized' || state === 'prepared';
  }

  isBusy(): boolean {
    if (this.resolving) return true;
    const state = this.playback.state;
    return state === 'loading' || state === 'initialized' || state === 'prepared';
  }

  async toggle(): Promise<void> {
    if (!this.active || this.resolving) return;
    if (this.playback.state === 'playing') {
      await this.playback.pause();
      return;
    }
    if (this.failed || !this.url || (this.pausedAt > 0 && Date.now() - this.pausedAt > PAUSE_REFRESH_MS)) {
      await this.playEpisode(this.episodeIndex, Math.floor(this.positionMs / 1000), this.failed);
      return;
    }
    if (this.playback.state === 'completed' && this.durationMs > 0 && this.positionMs >= this.durationMs - 1000) {
      this.positionMs = 0;
    }
    await this.playback.resume();
  }

  async playEpisode(index: number, startSec: number, isRetry: boolean = false): Promise<void> {
    const book = this.book;
    const source = this.source;
    if (!this.active || !book || !source || index < 0 || index >= this.chapters.length) return;
    const target = index;
    if (target !== this.episodeIndex) this.saveProgress(true);
    const chapter = this.chapters[target];
    const serial = ++this.resolveSerial;
    this.cancelResolve();
    this.resolving = true;
    this.failed = false;
    if (!isRetry) this.retried = false;
    this.episodeIndex = target;
    this.positionMs = Math.max(0, Math.floor(startSec * 1000));
    this.durationMs = 0;
    this.pausedAt = 0;
    this.lastSavedSec = -1;
    this.statusText = '正在获取播放地址…';
    AppStorage.setOrCreate(VideoListenSession.EPISODE_KEY, target);
    this.saveProgress(true);
    ReaderTtsFloatingSession.updateCatalogIndex(OWNER_ID, target);
    this.publishDetails();
    this.updateAvState();
    // 上一集别在新地址就绪前接着响。
    await this.playback.abortPendingLoad();
    if (this.playback.state === 'playing') await this.playback.pause();
    const service = new WebBookService();
    this.service = service;
    let result = new VideoPlaybackSource();
    try {
      result = await Promise.race([
        service.getVideoContent(source, book, chapter,
          (): boolean => serial !== this.resolveSerial || this.service !== service),
        new Promise<VideoPlaybackSource>((_resolve, reject): void => {
          this.resolveTimerId = setTimeout((): void => {
            service.cancelPendingRequests();
            reject(new Error('获取播放地址超过 30 秒，请重试'));
          }, RESOLVE_TIMEOUT_MS);
        })
      ]);
    } catch (e) {
      result.error = (e as Error).message || '获取播放地址失败';
    }
    if (serial !== this.resolveSerial || !this.active) return;
    this.cancelResolve();
    this.resolving = false;
    if (!result.url) {
      this.markFailed(result.pageUrl ? '这一集只能在网页里播放，请点“看画面”' :
        (result.error || '没有取到播放地址'));
      return;
    }
    this.url = result.url;
    this.headers = result.headers || {};
    this.statusText = '正在缓冲…';
    this.publishDetails();
    await this.playUrl(this.positionMs);
  }

  seekTo(positionMs: number): void {
    // 还没拿到时长就是还在加载：这时的定位会顶掉续播目标，让声音从头放。
    if (!this.active || this.resolving || this.durationMs <= 0) return;
    const target = Math.max(0, Math.min(positionMs, this.durationMs));
    this.positionMs = target;
    this.playback.seek(target);
    this.saveProgress(true);
    this.updateAvState();
  }

  seekBy(deltaMs: number): void {
    this.seekTo(this.playback.positionMs + deltaMs);
  }

  setSpeed(value: number): void {
    if (!this.active || value <= 0) return;
    this.speed = value;
    this.playback.setSpeed(value);
    this.publishDetails();
    this.updateAvState();
  }

  setTimer(minutes: number): void {
    if (!this.active) return;
    this.timerMinutes = Math.max(0, Math.round(minutes));
    this.playback.setSleepTimer(this.timerMinutes);
    this.syncTimer();
  }

  extendTimer(minutes: number): void {
    if (!this.active || minutes <= 0) return;
    this.timerMinutes += minutes;
    this.playback.extendSleepTimer(minutes);
    this.syncTimer();
  }

  /** 回到画面：播放页正停在听视频画面就在那里恢复，否则打开播放页，由它接过当前位置。 */
  watch(): void {
    const book = this.book;
    if (!this.active || !book) return;
    const host = this.hostResume;
    if (host) {
      host();
      return;
    }
    const chapter = this.chapters[this.episodeIndex];
    // 图文书的播放页按章节序号找视频章；普通视频书直接是选集位置。
    const chapterIndex = this.mixed && chapter ? chapter.index : this.episodeIndex;
    router.pushUrl({
      url: 'pages/VideoPlayer',
      params: { bookUrl: book.bookUrl, chapterIndex: `${chapterIndex}` }
    }).catch((error: Error) => console.warn('[VideoListen] open player failed:', error.message));
  }

  // ---- 内部 ----

  private async playUrl(startMs: number): Promise<void> {
    const book = this.book;
    if (!book || !this.url) return;
    const serial = this.resolveSerial;
    try {
      await this.playback.play(book.bookUrl, this.episodeIndex, this.url, this.headers, startMs, this.speed);
    } catch (error) {
      if (serial !== this.resolveSerial || !this.active) return;
      this.onPlaybackError((error as Error).message || String(error));
    }
  }

  private markFailed(text: string): void {
    this.failed = true;
    this.resolving = false;
    this.statusText = text;
    this.publishDetails();
    this.updateAvState();
  }

  private cancelResolve(): void {
    if (this.resolveTimerId >= 0) clearTimeout(this.resolveTimerId);
    this.resolveTimerId = -1;
    if (this.service) this.service.cancelPendingRequests();
    this.service = null;
  }

  private currentTitle(): string {
    const chapter = this.chapters[this.episodeIndex];
    return chapter ? (chapter.title || `第${this.episodeIndex + 1}集`) : '';
  }

  private saveProgress(force: boolean): void {
    const book = this.book;
    const context = this.context;
    if (!book || !context) return;
    const second = Math.floor(this.positionMs / 1000);
    if (!force && Math.abs(second - this.lastSavedSec) < SAVE_STEP_SEC) return;
    this.lastSavedSec = second;
    const chapter = this.chapters[this.episodeIndex];
    if (this.mixed) {
      if (!chapter) return;
      MixedVideoProgress.put(context, book.bookUrl, chapter.url, second).catch((error: Error): void => {
        console.warn('[VideoListen] save mixed progress failed:', error.message);
      });
      return;
    }
    book.durChapterIndex = this.episodeIndex;
    if (chapter) book.durChapterTitle = chapter.title;
    book.durChapterPos = second;
    book.durChapterTime = Date.now();
    AppDatabase.getInstance().updateBook(book, false).catch((error: Error): void => {
      console.warn('[VideoListen] save progress failed:', error.message);
    });
  }

  private publishSession(): void {
    const book = this.book;
    if (!book) return;
    ReaderTtsFloatingSession.attach(
      OWNER_ID,
      book.bookUrl,
      book.name || '听视频',
      this.currentTitle(),
      !this.isPlaying(),
      (): Promise<void> => this.toggle(),
      (): boolean => !this.isPlaying(),
      (): Promise<void> => this.stop()
    );
    ReaderTtsFloatingSession.configureControls(
      OWNER_ID,
      (): void => { this.playEpisode(this.episodeIndex - 1, 0); },
      (): void => { this.playEpisode(this.episodeIndex + 1, 0); },
      (value: number): void => this.setSpeed(value),
      (minutes: number): void => this.setTimer(minutes)
    );
    ReaderTtsFloatingSession.configureTimerExtend(OWNER_ID, (minutes: number): void => this.extendTimer(minutes));
    ReaderTtsFloatingSession.configureVideoControls(
      OWNER_ID,
      (positionMs: number): void => this.seekTo(positionMs),
      (deltaMs: number): void => this.seekBy(deltaMs),
      (): void => this.watch()
    );
    ReaderTtsFloatingSession.configureCatalog(
      OWNER_ID,
      this.chapters.map((chapter: BookChapter, index: number): string => chapter.title || `第${index + 1}集`),
      this.episodeIndex,
      (index: number): void => { this.playEpisode(index, 0); }
    );
    this.publishDetails();
  }

  private publishDetails(): void {
    const book = this.book;
    if (!this.active || !book) return;
    const count = this.chapters.length;
    ReaderTtsFloatingSession.update(OWNER_ID, book.name || '听视频', this.currentTitle(), !this.isPlaying());
    ReaderTtsFloatingSession.updateDetails(
      OWNER_ID,
      book.intro || '',
      '', '', '',
      BookCoverResolver.first(book),
      '',
      `${this.episodeIndex + 1}/${Math.max(1, count)}集`,
      this.speed,
      this.timerMinutes,
      this.playback.sleepRemainingSeconds(),
      this.episodeIndex > 0,
      this.episodeIndex < count - 1
    );
    ReaderTtsFloatingSession.updateAudioProgress(OWNER_ID, this.positionMs, this.durationMs);
    const busy = this.isBusy();
    ReaderTtsFloatingSession.updateStatus(OWNER_ID, busy || this.failed ? this.statusText : '', busy);
  }

  private syncTimer(): void {
    this.clearTimerTick();
    const remaining = this.playback.sleepRemainingSeconds();
    if (this.timerMinutes <= 0 || remaining <= 0) {
      this.timerMinutes = 0;
      ReaderTtsFloatingSession.updateTimer(OWNER_ID, 0, 0);
      return;
    }
    ReaderTtsFloatingSession.updateTimer(OWNER_ID, this.timerMinutes, remaining);
    this.timerTickId = setInterval((): void => {
      const left = this.playback.sleepRemainingSeconds();
      if (!this.active || left <= 0) {
        this.clearTimerTick();
        this.timerMinutes = 0;
        ReaderTtsFloatingSession.updateTimer(OWNER_ID, 0, 0);
        return;
      }
      ReaderTtsFloatingSession.updateTimer(OWNER_ID, this.timerMinutes, left);
    }, 1000);
  }

  private clearTimerTick(): void {
    if (this.timerTickId >= 0) clearInterval(this.timerTickId);
    this.timerTickId = -1;
  }

  // ---- 后台许可与系统媒体控件 ----

  private startKeepAlive(): void {
    if (this.keepAliveId >= 0) return;
    // 许可可能被系统收回或第一次没申请到：播放中定期对齐一次。
    this.keepAliveId = setInterval((): void => {
      if (!this.active || this.playback.state !== 'playing') return;
      this.enqueueBackground((): Promise<void> => this.ensureBackground());
    }, KEEP_ALIVE_MS);
  }

  private stopKeepAlive(): void {
    if (this.keepAliveId >= 0) clearInterval(this.keepAliveId);
    this.keepAliveId = -1;
  }

  private enqueueBackground(task: () => Promise<void>): Promise<void> {
    const next = this.backgroundQueue.then(task);
    this.backgroundQueue = next.catch((error: Error): void => {
      console.warn('[VideoListen] background task failed:', error.message);
    });
    return this.backgroundQueue;
  }

  private async ensureBackground(): Promise<void> {
    const context = this.context;
    if (!this.active || !context) return;
    const agent = await this.wantAgent(context);
    if (!this.active) return;
    if (!this.session) await this.startAvSession(context, agent);
    if (!this.active) return;
    if (!BackgroundPermit.satisfies(PERMIT_OWNER)) {
      const running = await BackgroundPermit.acquire(context, PERMIT_OWNER, 'audioPlayback', agent);
      if (!running) console.warn(`[VideoListen] background permit pending: ${BackgroundPermit.debugState()}`);
    }
  }

  private async releaseBackground(): Promise<void> {
    if (this.active) return;
    const session = this.session;
    this.session = null;
    this.mediaCover.clear();
    if (session) {
      try { session.off('play'); } catch (_) {}
      try { session.off('pause'); } catch (_) {}
      try { session.off('stop'); } catch (_) {}
      try { session.off('playNext'); } catch (_) {}
      try { session.off('playPrevious'); } catch (_) {}
      try { session.off('seek'); } catch (_) {}
      try { session.off('fastForward'); } catch (_) {}
      try { session.off('rewind'); } catch (_) {}
      try { session.off('setSpeed'); } catch (_) {}
      try { await session.setAVPlaybackState({ state: avSession.PlaybackState.PLAYBACK_STATE_STOP }); } catch (_) {}
      try { await session.deactivate(); } catch (_) {}
      try { await session.destroy(); } catch (error) {
        console.warn('[VideoListen] destroy media session failed:', (error as Error).message);
      }
    }
    await BackgroundPermit.release(PERMIT_OWNER);
  }

  private async wantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    if (this.launchAgent) return this.launchAgent;
    // 点通知栏媒体卡片只回到应用，停在当时的页面。
    this.launchAgent = await createLaunchAgent(context, 1102);
    return this.launchAgent;
  }

  private async startAvSession(context: common.UIAbilityContext, agent: WantAgent): Promise<void> {
    if (this.sessionStarting) return;
    this.sessionStarting = true;
    try {
      const session = await this.createAvSession(context);
      if (!this.active) {
        try { await session.destroy(); } catch (_) {}
        return;
      }
      this.session = session;
      session.on('play', (): void => {
        if (!this.isPlaying()) this.toggle().catch((): void => {});
      });
      session.on('pause', (): void => {
        if (this.playback.state === 'playing') this.playback.pause().catch((): void => {});
      });
      session.on('stop', (): void => { this.stop().catch((): void => {}); });
      session.on('playNext', (): void => { this.playEpisode(this.episodeIndex + 1, 0); });
      session.on('playPrevious', (): void => { this.playEpisode(this.episodeIndex - 1, 0); });
      session.on('seek', (time: number): void => this.seekTo(time));
      // 回调参数按文档是秒；没给就按 15 秒。
      session.on('fastForward', (time?: number): void => this.seekBy(time && time > 0 ? time * 1000 : SEEK_STEP_MS));
      session.on('rewind', (time?: number): void => this.seekBy(-(time && time > 0 ? time * 1000 : SEEK_STEP_MS)));
      session.on('setSpeed', (speed: number): void => this.setSpeed(speed));
      await session.setLaunchAbility(agent);
      await session.setAVMetadata(this.avMetadata());
      await this.writeAvState(session);
      await session.activate();
    } catch (error) {
      console.warn('[VideoListen] start media session failed:', (error as Error).message);
    } finally {
      this.sessionStarting = false;
    }
  }

  /** 一个 Ability 只能有一个媒体会话；听书或朗读的会话刚停时可能还没销毁完，稍等再试。 */
  private async createAvSession(context: common.UIAbilityContext): Promise<avSession.AVSession> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await avSession.createAVSession(context, 'LegadoVideoListen', 'audio');
      } catch (error) {
        const message = (error as Error).message || '';
        if (attempt >= 3 || !message.includes('existed')) throw error as Error;
        await new Promise<void>((resolve: () => void): number => setTimeout(resolve, 300 * (attempt + 1)));
      }
    }
  }

  private updateAvState(): void {
    const session = this.session;
    if (!session || !this.active) return;
    session.setAVMetadata(this.avMetadata())
      .then((): Promise<void> => this.writeAvState(session))
      .catch((error: Error): void => console.warn('[VideoListen] update media session failed:', error.message));
  }

  private async writeAvState(session: avSession.AVSession): Promise<void> {
    let state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    if (this.isBusy()) state = avSession.PlaybackState.PLAYBACK_STATE_BUFFERING;
    else if (this.playback.state === 'playing') state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    await session.setAVPlaybackState({
      state: state,
      speed: this.speed,
      position: { elapsedTime: this.positionMs, updateTime: Date.now() },
      bufferedTime: this.durationMs,
      loopMode: avSession.LoopMode.LOOP_MODE_SEQUENCE,
      activeItemId: this.episodeIndex
    });
    if (state !== avSession.PlaybackState.PLAYBACK_STATE_PAUSE) await session.activate();
  }

  private avMetadata(): avSession.AVMetadata {
    const book = this.book;
    const bookUrl = book ? book.bookUrl : '';
    const name = book ? (book.name || '听视频') : '听视频';
    const metadata: avSession.AVMetadata = {
      assetId: `${bookUrl}_${this.episodeIndex}`,
      title: this.currentTitle() || name,
      subtitle: name,
      artist: name,
      album: name,
      duration: this.durationMs,
      previousAssetId: this.episodeIndex > 0 ? `${bookUrl}_${this.episodeIndex - 1}` : '',
      nextAssetId: this.episodeIndex < this.chapters.length - 1 ? `${bookUrl}_${this.episodeIndex + 1}` : '',
      avQueueName: name,
      avQueueId: bookUrl || 'video_listen'
    };
    const context = this.context;
    if (context && book) {
      const session = this.session;
      const image = this.mediaCover.getImage(context, bookUrl, BookCoverResolver.first(book), (): void => {
        if (session && session === this.session) this.updateAvState();
      });
      if (image) {
        metadata.mediaImage = image;
        metadata.avQueueImage = image;
      }
    }
    return metadata;
  }
}
