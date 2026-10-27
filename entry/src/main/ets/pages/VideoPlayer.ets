import { router, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { Book, BookChapter, BookSource, CookieStore } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { WebBookService } from '../core/book/WebBookService';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { syncSystemBars } from '../utils/SystemBars';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VideoPlaybackSource, VideoPlaybackSupport } from '../core/book/VideoPlaybackSupport';

/** 每次尝试创建独立实例，让旧组件回调携带旧编号。 */
class VideoNativeAttempt {
  id: number;
  url: string;
  controller: VideoController = new VideoController();
  constructor(id: number, url: string) { this.id = id; this.url = url; }
}

class VideoWebAttempt {
  id: number;
  url: string;
  controller: webview.WebviewController = new webview.WebviewController();
  attached: boolean = false;
  constructor(id: number, url: string) { this.id = id; this.url = url; }
}

interface VideoPlayerParams {
  bookUrl?: string;
  chapterIndex?: string;
  shelfBookOpening?: string;
}

/** 选集列表的数据源：集数可能上千，用懒加载避免一次创建全部条目。 */
class EpisodeDataSource implements IDataSource {
  private titles: string[] = [];
  private listeners: DataChangeListener[] = [];

  replace(titles: string[]): void {
    this.titles = titles;
    for (const listener of this.listeners) listener.onDataReloaded();
  }

  totalCount(): number {
    return this.titles.length;
  }

  getData(index: number): string {
    return this.titles[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}

// Video 组件的 currentProgressRate 只接受 0.75、1、1.25、1.75、2 这几档，别的值不生效。
const SPEEDS: number[] = [1, 1.25, 1.75, 2, 0.75];
const CONTROLS_HIDE_DELAY_MS: number = 4000;

// 操作栏按钮的统一外观。用 @Extend 而不是带参数的 @Builder：按值传参的 @Builder 不会随状态刷新，
// 「连播 开/关」「播放/暂停」、倍速这些会变的文字就停在创建时的样子。
@Extend(Text)
function playerRoundButton() {
  .fontSize(AppFontSize.BODY)
  .fontColor('#FFFFFF')
  .height(36)
  .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
  .borderRadius(18)
  .backgroundColor('#33FFFFFF')
  .textAlign(TextAlign.Center)
}

/**
 * 视频类书籍（短剧等）的播放页：全屏播放，页内切换集数。
 * 播放地址由书源的 content.video 给出，每次切集都重新取，避免带时效的地址过期。
 */
@Entry
@Component
struct VideoPlayerPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @State bookName: string = '';
  @State episodeTitle: string = '';
  @State episodeIndex: number = 0;
  @State episodeCount: number = 0;
  @State videoUrl: string = '';
  @State statusText: string = '正在加载...';
  @State isPlaying: boolean = false;
  @State positionSec: number = 0;
  @State durationSec: number = 0;
  @State speed: number = 1;
  @State showControls: boolean = true;
  @State showEpisodes: boolean = false;
  @State autoNext: boolean = true;
  @State landscape: boolean = false;
  @State seeking: boolean = false;
  @State nativeAttempts: VideoNativeAttempt[] = [];
  @State webAttempts: VideoWebAttempt[] = [];
  @State webMode: boolean = false;
  @State webFullscreen: boolean = false;
  @State webStatus: string = '';
  @State videoPageUrl: string = '';
  @State playbackFailed: boolean = false;
  private controller: VideoController = new VideoController();
  private fullScreenHandler: FullScreenExitHandler | null = null;
  private activeAttemptId: number = 0;
  private contentService: WebBookService | null = null;
  private resolveTimerId: number = -1;
  private playbackReady: boolean = false;
  private resumeSeekPending: boolean = false;
  private episodeScroller: Scroller = new Scroller();
  private episodeData: EpisodeDataSource = new EpisodeDataSource();
  private book: Book | null = null;
  private source: BookSource | null = null;
  private chapters: BookChapter[] = [];
  private loadSerial: number = 0;
  private hideTimerId: number = -1;
  private resumeSec: number = 0;
  private retried: boolean = false;
  private lastSavedSec: number = -1;
  private playerPageVisible: boolean = false;
  private orientationSerial: number = 0;
  private manualLandscapeRequested: boolean = false;
  // 从书架带开书动画进来时，书架那层“正在打开书籍”要等这里通知才会收起，否则返回后一直转圈。
  private openedWithShelfAnimation: boolean = false;
  private openedBookUrl: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as VideoPlayerParams;
    const bookUrl = params && params.bookUrl ? params.bookUrl : '';
    const requestedIndex = params && params.chapterIndex !== undefined && params.chapterIndex !== '' ?
      Number(params.chapterIndex) : -1;
    this.openedWithShelfAnimation = !!params && params.shelfBookOpening === 'true';
    this.openedBookUrl = bookUrl;
    this.loadBook(bookUrl, requestedIndex);
  }

  aboutToDisappear(): void {
    this.playerPageVisible = false;
    this.orientationSerial++;
    this.loadSerial++;
    this.cancelResolve();
    this.clearHideTimer();
    this.saveProgress(true);
    this.stopPlayback();
    this.leaveImmersive();
    this.requestShelfCloseAnimation();
  }

  onPageShow(): void {
    this.playerPageVisible = true;
    this.enterImmersive();
    this.applyPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
    for (const attempt of this.webAttempts) {
      if (attempt.attached) {
        try { attempt.controller.onActive(); } catch (_) {}
      }
    }
  }

  onPageHide(): void {
    this.playerPageVisible = false;
    this.orientationSerial++;
    try { this.controller.pause(); } catch (_) {}
    this.pauseWeb();
    this.clearHideTimer();
    this.saveProgress(true);
  }

  onBackPress(): boolean {
    if (this.exitWebFullscreen()) return true;
    if (this.showEpisodes) {
      this.showEpisodes = false;
      return true;
    }
    if (this.webMode) {
      const attempt = this.webAttempts[0];
      try {
        if (attempt && attempt.attached && attempt.controller.accessBackward()) {
          attempt.controller.backward();
          return true;
        }
      } catch (_) {}
    }
    if (this.manualLandscapeRequested) {
      this.setLandscape(false);
      return true;
    }
    this.requestShelfCloseAnimation();
    return false;
  }

  private requestShelfCloseAnimation(): void {
    if (!this.openedWithShelfAnimation) {
      return;
    }
    this.openedWithShelfAnimation = false;
    AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.openedBookUrl);
    AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
  }

  private enterImmersive(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window): void => {
      if (!this.playerPageVisible) return;
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable([]);
      mainWindow.setWindowKeepScreenOn(true);
    }).catch((error: Error): void => {
      console.warn('[VideoPlayer] enter immersive failed:', error.message);
    });
  }

  private leaveImmersive(): void {
    const dark = this.appDarkMode;
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window): void => {
      if (this.playerPageVisible) return;
      mainWindow.setWindowKeepScreenOn(false);
      mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED).catch((error: Error): void => {
        console.warn('[VideoPlayer] restore orientation failed:', error.message);
      });
      syncSystemBars(getContext(this), dark, ThemeRuntime.pageColor(dark));
    }).catch((error: Error): void => {
      console.warn('[VideoPlayer] leave immersive failed:', error.message);
    });
  }

  private setLandscape(enabled: boolean): void {
    this.manualLandscapeRequested = enabled;
    // 手动切换立即生效，之后仍可跟随系统旋转，不能把窗口永久限制在横屏或竖屏。
    this.applyPreferredOrientation(enabled ? window.Orientation.USER_ROTATION_LANDSCAPE :
      window.Orientation.USER_ROTATION_PORTRAIT);
    this.scheduleHideControls();
  }

  private applyPreferredOrientation(preferred: window.Orientation): void {
    const serial = ++this.orientationSerial;
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      if (!this.playerPageVisible || serial !== this.orientationSerial) return;
      return mainWindow.setPreferredOrientation(preferred);
    }).catch((error: Error): void => {
      console.warn('[VideoPlayer] rotate failed:', error.message);
    });
  }

  private async loadBook(bookUrl: string, requestedIndex: number): Promise<void> {
    const serial = ++this.loadSerial;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const stored = await db.getBook(bookUrl);
      if (!stored) {
        this.statusText = '没有找到这部剧，请重新从详情页打开';
        return;
      }
      this.bookName = stored.name;
      this.source = stored.origin ? await db.getBookSource(stored.origin) : null;
      if (!this.source) {
        this.statusText = '对应的书源已被删除';
        return;
      }
      // 选集沿用阅读引擎的目录加载与缓存；首次打开时由它去取并保存。
      const engine = ReadBookEngine.get();
      await engine.openBook(stored);
      if (serial !== this.loadSerial) return;
      this.book = engine.book && engine.book.bookUrl === stored.bookUrl ? engine.book : stored;
      this.chapters = engine.chapters.slice();
      this.episodeCount = this.chapters.length;
      this.episodeData.replace(this.chapters.map((chapter: BookChapter): string => chapter.title || ''));
      if (this.chapters.length === 0) {
        this.statusText = AppStorage.get<string>('bookSourceStageLastError') || '没有取到选集';
        return;
      }
      const sameEpisode = requestedIndex < 0 || requestedIndex === this.book.durChapterIndex;
      const index = requestedIndex >= 0 ? requestedIndex : this.book.durChapterIndex;
      // durChapterPos 对视频类书籍记的是播放到的秒数。
      await this.playEpisode(index, sameEpisode ? Math.max(0, this.book.durChapterPos) : 0);
    } catch (e) {
      if (serial !== this.loadSerial) return;
      console.warn('[VideoPlayer] load failed:', (e as Error).message);
      this.statusText = `加载失败：${(e as Error).message || '未知错误'}`;
    }
  }

  private async playEpisode(index: number, resumeSec: number = 0, isRetry: boolean = false): Promise<void> {
    const book = this.book;
    const source = this.source;
    if (!book || !source || this.chapters.length === 0) return;
    const target = Math.max(0, Math.min(index, this.chapters.length - 1));
    const chapter = this.chapters[target];
    const previousPageUrl = isRetry && target === this.episodeIndex ? this.videoPageUrl : '';
    this.saveProgress(true);
    this.cancelResolve();
    this.stopPlayback();
    const serial = ++this.loadSerial;
    this.retried = isRetry;
    this.episodeIndex = target;
    this.episodeTitle = chapter.title;
    this.positionSec = VideoPlaybackSupport.position(resumeSec);
    this.durationSec = 0;
    this.isPlaying = false;
    this.videoUrl = '';
    this.videoPageUrl = previousPageUrl;
    this.playbackFailed = false;
    this.playbackReady = false;
    this.resumeSeekPending = false;
    this.resumeSec = this.positionSec;
    this.showControls = true;
    this.seeking = false;
    book.durChapterIndex = target;
    book.durChapterTitle = chapter.title;
    book.durChapterPos = Math.floor(this.positionSec);
    this.lastSavedSec = -1;
    this.saveProgress(true);
    this.statusText = '正在获取播放地址...';
    const service = new WebBookService();
    this.contentService = service;
    let result = new VideoPlaybackSource();
    try {
      result = await Promise.race([
        service.getVideoContent(source, book, chapter,
          (): boolean => serial !== this.loadSerial || this.contentService !== service),
        new Promise<VideoPlaybackSource>((_resolve, reject): void => {
          this.resolveTimerId = setTimeout((): void => {
            service.cancelPendingRequests();
            reject(new Error('获取播放地址超过 30 秒，请重试'));
          }, 30000);
        })
      ]);
    } catch (e) {
      result.error = (e as Error).message || '获取播放地址失败';
    }
    if (serial !== this.loadSerial) return;
    this.cancelResolve();
    this.videoPageUrl = result.pageUrl || previousPageUrl;
    if (!result.url) {
      this.statusText = result.error || '没有取到播放地址';
      this.playbackFailed = true;
      this.showControls = true;
      return;
    }
    this.statusText = '正在缓冲...';
    this.videoUrl = result.url;
    const attempt = new VideoNativeAttempt(++this.activeAttemptId, result.url);
    this.controller = attempt.controller;
    this.nativeAttempts = [attempt];
    this.scheduleHideControls();
  }

  private cancelResolve(): void {
    if (this.resolveTimerId >= 0) clearTimeout(this.resolveTimerId);
    this.resolveTimerId = -1;
    if (this.contentService) this.contentService.cancelPendingRequests();
    this.contentService = null;
  }

  private isCurrentNative(attempt: VideoNativeAttempt): boolean {
    return !this.webMode && attempt.id === this.activeAttemptId && this.nativeAttempts.length > 0;
  }

  private isCurrentWeb(attempt: VideoWebAttempt): boolean {
    return this.webMode && attempt.id === this.activeAttemptId;
  }

  private exitWebFullscreen(): boolean {
    const wasFullscreen = this.webFullscreen;
    const handler = this.fullScreenHandler;
    this.fullScreenHandler = null;
    this.webFullscreen = false;
    if (handler) { try { handler.exitFullScreen(); } catch (_) {} }
    return wasFullscreen;
  }

  private pauseWeb(): void {
    this.exitWebFullscreen();
    for (const attempt of this.webAttempts) {
      if (!attempt.attached) continue;
      try { attempt.controller.pauseAllMedia(); attempt.controller.onInactive(); } catch (_) {}
    }
    if (this.webAttempts.length > 0) CookieStore.saveSync();
  }

  private stopPlayback(): void {
    this.activeAttemptId++;
    this.clearHideTimer();
    this.exitWebFullscreen();
    try { this.controller.stop(); } catch (_) {}
    for (const attempt of this.webAttempts) {
      if (attempt.attached) {
        try { attempt.controller.stopAllMedia(); attempt.controller.onInactive(); } catch (_) {}
      }
    }
    if (this.webAttempts.length > 0) CookieStore.saveSync();
    this.nativeAttempts = [];
    this.webAttempts = [];
    this.webMode = false;
    this.isPlaying = false;
  }

  private openWebPlayback(automatic: boolean = false): void {
    if (!this.videoPageUrl || this.webMode) return;
    this.saveProgress(true);
    this.stopPlayback();
    this.videoUrl = '';
    this.webMode = true;
    this.webStatus = '网页加载中…';
    this.statusText = '';
    this.showEpisodes = false;
    this.webAttempts = [new VideoWebAttempt(++this.activeAttemptId, this.videoPageUrl)];
    ReaderTtsFloatingSession.pause().catch((): void => {});
    if (automatic) HdsFeedback.showToast('原生播放不可用，已切换网页播放');
  }

  private retryWebPlayback(): void {
    this.stopPlayback();
    this.openWebPlayback();
  }

  private backFromPlayer(): void {
    if (!this.onBackPress()) this.getUIContext().getRouter().back();
  }

  private saveProgress(force: boolean = false): void {
    const book = this.book;
    if (!book) return;
    const second = Math.floor(this.positionSec);
    // 播放中每 10 秒落一次库，切集、离开页面时立即保存。
    if (!force && Math.abs(second - this.lastSavedSec) < 10) return;
    this.lastSavedSec = second;
    if (!this.webMode && this.playbackReady && !this.resumeSeekPending) book.durChapterPos = second;
    book.durChapterTime = Date.now();
    AppDatabase.getInstance().updateBook(book, false).catch((error: Error): void => {
      console.warn('[VideoPlayer] save progress failed:', error.message);
    });
  }

  private onVideoPrepared(duration: number): void {
    this.playbackReady = true;
    this.durationSec = Math.max(0, duration);
    this.statusText = '';
    if (this.resumeSec > 1 && (this.durationSec <= 0 || this.resumeSec < this.durationSec - 3)) {
      this.resumeSeekPending = true;
      this.controller.setCurrentTime(this.resumeSec, SeekMode.Accurate);
    } else {
      this.positionSec = 0;
    }
    this.resumeSec = 0;
    if (this.playerPageVisible) this.controller.start();
  }

  private onVideoFinished(): void {
    this.isPlaying = false;
    if (this.autoNext && this.episodeIndex < this.chapters.length - 1) {
      this.playEpisode(this.episodeIndex + 1);
      return;
    }
    this.showControls = true;
    this.statusText = this.episodeIndex >= this.chapters.length - 1 ? '已播完最后一集' : '';
  }

  private onVideoError(code: number): void {
    this.saveProgress(true);
    this.stopPlayback();
    this.videoUrl = '';
    this.playbackFailed = true;
    this.statusText = VideoPlaybackSupport.failureText(code);
    console.warn(`[VideoPlayer] playback error code=${code}, episode=${this.episodeIndex}`);
    if (VideoPlaybackSupport.unsupported(code) && this.videoPageUrl && this.playerPageVisible) {
      this.openWebPlayback(true);
      return;
    }
    if (!VideoPlaybackSupport.unsupported(code) && code !== 5411005 && !this.retried) {
      this.playEpisode(this.episodeIndex, this.positionSec, true);
      return;
    }
    this.isPlaying = false;
    this.showControls = true;
  }

  private togglePlay(): void {
    if (!this.videoUrl) {
      this.playEpisode(this.episodeIndex, this.positionSec);
      return;
    }
    if (this.isPlaying) this.controller.pause();
    else this.controller.start();
    this.scheduleHideControls();
  }

  private toggleControls(): void {
    this.showControls = !this.showControls;
    if (this.showControls) this.scheduleHideControls();
    else this.clearHideTimer();
  }

  private clearHideTimer(): void {
    if (this.hideTimerId >= 0) {
      clearTimeout(this.hideTimerId);
      this.hideTimerId = -1;
    }
  }

  private scheduleHideControls(): void {
    this.clearHideTimer();
    this.hideTimerId = setTimeout((): void => {
      this.hideTimerId = -1;
      if (this.isPlaying && !this.showEpisodes && !this.seeking) this.showControls = false;
    }, CONTROLS_HIDE_DELAY_MS);
  }

  private nextSpeed(): void {
    const index = SPEEDS.indexOf(this.speed);
    this.speed = SPEEDS[(index + 1) % SPEEDS.length];
    this.scheduleHideControls();
  }

  private openEpisodes(): void {
    this.showEpisodes = true;
    this.clearHideTimer();
    setTimeout((): void => {
      this.episodeScroller.scrollToIndex(Math.max(0, this.episodeIndex - 8));
    }, 60);
  }

  private formatTime(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    const minute = Math.floor(total / 60);
    const second = total % 60;
    return `${minute < 10 ? '0' : ''}${minute}:${second < 10 ? '0' : ''}${second}`;
  }

  @Builder
  topBar() {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .width(40)
        .height(40)
        .onClick(() => this.backFromPlayer())
      Column() {
        Text(this.bookName)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.episodeTitle}${this.episodeCount > 0 ? ` · 共 ${this.episodeCount} 集` : ''}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#CCFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.autoNext ? '连播 开' : '连播 关')
        .playerRoundButton()
        .onClick(() => {
          this.autoNext = !this.autoNext;
          this.scheduleHideControls();
        })
      Text('选集')
        .playerRoundButton()
        .onClick(() => this.openEpisodes())
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: this.statusBarHeight + AppSpacing.MD,
      bottom: AppSpacing.XL })
    .linearGradient({ direction: GradientDirection.Bottom, colors: [['#B3000000', 0], ['#00000000', 1]] })
    .position({ left: 0, top: 0 })
  }

  @Builder
  bottomBar() {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.MD }) {
        Text(this.formatTime(this.positionSec))
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
        Slider({ value: this.positionSec, min: 0, max: Math.max(1, this.durationSec), step: 1 })
          .enabled(this.playbackReady && !this.playbackFailed && this.nativeAttempts.length > 0)
          .layoutWeight(1)
          .trackColor('#55FFFFFF')
          .selectedColor('#FFFFFF')
          .blockColor('#FFFFFF')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              this.seeking = true;
              this.positionSec = value;
              return;
            }
            this.seeking = false;
            this.positionSec = value;
            this.controller.setCurrentTime(value, SeekMode.Accurate);
            this.scheduleHideControls();
          })
        Text(this.formatTime(this.durationSec))
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
        Text('上一集')
          .playerRoundButton()
          .onClick(() => {
            if (this.episodeIndex > 0) this.playEpisode(this.episodeIndex - 1);
            else HdsFeedback.showToast('已经是第一集');
          })
        Text(this.isPlaying ? '暂停' : '播放')
          .playerRoundButton()
          .onClick(() => this.togglePlay())
        Text('下一集')
          .playerRoundButton()
          .onClick(() => {
            if (this.episodeIndex < this.chapters.length - 1) this.playEpisode(this.episodeIndex + 1);
            else HdsFeedback.showToast('已经是最后一集');
          })
        Blank()
        Text(`${this.speed}x`)
          .playerRoundButton()
          .onClick(() => this.nextSpeed())
        Text(this.landscape ? '竖屏' : '横屏')
          .playerRoundButton()
          .onClick(() => this.setLandscape(!this.landscape))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XL,
      bottom: this.navBarHeight + AppSpacing.LG })
    .linearGradient({ direction: GradientDirection.Top, colors: [['#B3000000', 0], ['#00000000', 1]] })
    .position({ left: 0, bottom: 0 })
  }

  @Builder
  episodePanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showEpisodes = false;
          this.scheduleHideControls();
        })
      Column() {
        Text(`选集 · 共 ${this.episodeCount} 集`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.LG })
        List({ space: AppSpacing.MD, scroller: this.episodeScroller }) {
          LazyForEach(this.episodeData, (title: string, index: number) => {
            ListItem() {
              Text(title || `第${index + 1}集`)
                .fontSize(AppFontSize.BODY)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(index === this.episodeIndex ? '#7A5AF8' : '#26FFFFFF')
                .onClick(() => {
                  this.showEpisodes = false;
                  if (index !== this.episodeIndex) this.playEpisode(index);
                  else this.scheduleHideControls();
                })
            }
          }, (title: string, index: number): string => `${index}_${title}_${index === this.episodeIndex ? 'on' : 'off'}`)
        }
        .lanes(this.landscape ? 6 : 4, AppSpacing.MD)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('55%')
      .padding({ bottom: this.navBarHeight + AppSpacing.LG })
      .backgroundColor('#F01C1C1E')
      .borderRadius({ topLeft: 18, topRight: 18 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  webPlayback() {
    Column() {
      if (!this.webFullscreen) {
        Row({ space: AppSpacing.SM }) {
          Button('返回').onClick(() => this.backFromPlayer())
          Text(`${this.bookName} · ${this.episodeTitle}`)
            .fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Button('选集').onClick(() => this.openEpisodes())
        }.padding(AppSpacing.MD).width('100%')
        Text('网页播放 · 进度与连播由网站控制')
          .fontSize(AppFontSize.CAPTION).fontColor(Color.White)
        Row({ space: AppSpacing.SM }) {
          Button('上一集').enabled(this.episodeIndex > 0)
            .layoutWeight(1).fontSize(AppFontSize.CAPTION)
            .onClick(() => this.playEpisode(this.episodeIndex - 1))
          Button('下一集').enabled(this.episodeIndex < this.chapters.length - 1)
            .layoutWeight(1).fontSize(AppFontSize.CAPTION)
            .onClick(() => this.playEpisode(this.episodeIndex + 1))
          Button('重试原生').layoutWeight(1).fontSize(AppFontSize.CAPTION)
            .onClick(() => this.playEpisode(this.episodeIndex, this.positionSec))
          Button('刷新网页').layoutWeight(1).fontSize(AppFontSize.CAPTION)
            .onClick(() => this.retryWebPlayback())
        }.padding(AppSpacing.SM).width('100%').justifyContent(FlexAlign.SpaceAround)
        if (this.webStatus) {
          Text(this.webStatus).fontSize(AppFontSize.CAPTION).fontColor(Color.White).padding(AppSpacing.SM)
        }
      }
      ForEach(this.webAttempts, (attempt: VideoWebAttempt) => {
        Web({ src: attempt.url, controller: attempt.controller })
          .width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(true)
          .fileAccess(false).mediaPlayGestureAccess(true)
          .onControllerAttached(() => {
            attempt.attached = true;
            if (!this.isCurrentWeb(attempt) || !this.playerPageVisible) {
              try { attempt.controller.pauseAllMedia(); attempt.controller.onInactive(); } catch (_) {}
            }
          })
          .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
            if (!this.isCurrentWeb(attempt)) return true;
            const target = event ? event.data.getRequestUrl() : '';
            // 仅允许正常网页跳转；不自动拉起外部客户端，也不转发媒体请求头。
            return !!target && target !== 'about:blank' && !VideoPlaybackSupport.httpUrl(target);
          })
          .onPageBegin(() => {
            if (this.isCurrentWeb(attempt)) this.webStatus = '网页加载中…';
          })
          .onPageEnd(() => {
            if (!this.isCurrentWeb(attempt)) return;
            if (this.webStatus === '网页加载中…') this.webStatus = '';
            if (!this.playerPageVisible) this.pauseWeb();
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (this.isCurrentWeb(attempt) && event.request.isMainFrame()) {
              this.webStatus = '网页加载失败，可刷新网页或重试原生播放';
            }
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
            if (this.isCurrentWeb(attempt) && event.request.isMainFrame()) {
              this.webStatus = '网页访问失败，请检查登录状态或刷新网页';
            }
          })
          .onFullScreenEnter((event: FullScreenEnterEvent) => {
            if (!this.isCurrentWeb(attempt) || !this.playerPageVisible) {
              event.handler.exitFullScreen();
              return;
            }
            this.fullScreenHandler = event.handler;
            this.webFullscreen = true;
          })
          .onFullScreenExit(() => {
            if (!this.isCurrentWeb(attempt)) return;
            this.fullScreenHandler = null;
            this.webFullscreen = false;
          })
      }, (attempt: VideoWebAttempt): string => `${attempt.id}`)
    }
    .width('100%').height('100%')
    .padding({ top: this.webFullscreen ? 0 : this.statusBarHeight,
      bottom: this.webFullscreen ? 0 : this.navBarHeight })
  }

  build() {
    Stack() {
      if (this.webMode) {
        this.webPlayback()
      } else {
        ForEach(this.nativeAttempts, (attempt: VideoNativeAttempt) => {
          Video({ src: attempt.url, controller: attempt.controller, currentProgressRate: this.speed })
            .width('100%')
            .height('100%')
            .controls(false)
            .autoPlay(false)
            .loop(false)
            .objectFit(ImageFit.Contain)
            .backgroundColor(Color.Black)
            .onPrepared((event: PreparedInfo) => {
              if (!this.isCurrentNative(attempt)) return;
              this.onVideoPrepared(event.duration);
            })
            .onStart(() => {
              if (!this.isCurrentNative(attempt) || !this.playerPageVisible) {
                try { attempt.controller.pause(); } catch (_) {}
                return;
              }
              // 同一应用内的音频流系统不会互相打断，朗读/听书要自己停下，免得和视频声音叠在一起。
              ReaderTtsFloatingSession.pause().catch((error: Error) => {
                console.warn('[VideoPlayer] pause tts failed:', error.message);
              });
              this.isPlaying = true;
              this.statusText = '';
              this.scheduleHideControls();
            })
            .onPause(() => {
              if (!this.isCurrentNative(attempt)) return;
              this.isPlaying = false;
              this.showControls = true;
            })
            .onUpdate((event: PlaybackInfo) => {
              if (!this.isCurrentNative(attempt) || this.resumeSeekPending) return;
              if (!this.seeking) this.positionSec = VideoPlaybackSupport.position(event.time);
              this.saveProgress();
            })
            .onSeeked((event: PlaybackInfo) => {
              if (!this.isCurrentNative(attempt)) return;
              this.resumeSeekPending = false;
              this.positionSec = VideoPlaybackSupport.position(event.time);
            })
            .onFinish(() => {
              if (!this.isCurrentNative(attempt) || !this.playerPageVisible) return;
              this.onVideoFinished();
            })
            .onError((error?: BusinessError) => {
              if (this.isCurrentNative(attempt)) this.onVideoError(error ? error.code : 0);
            })
        }, (attempt: VideoNativeAttempt): string => `${attempt.id}`)

        // 点画面显示或隐藏操作栏，双击暂停或继续。
        Column()
          .width('100%')
          .height('100%')
          .gesture(GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 }).onAction(() => this.togglePlay()),
            TapGesture({ count: 1 }).onAction(() => this.toggleControls())))

        if (this.statusText) {
          Column({ space: AppSpacing.MD }) {
            Text(this.statusText)
              .fontSize(AppFontSize.BODY)
              .fontColor('#FFFFFF')
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
              .borderRadius(12)
              .backgroundColor('#80000000')
            if (this.playbackFailed) {
              Row({ space: AppSpacing.MD }) {
                Button('重试').onClick(() => this.playEpisode(this.episodeIndex, this.positionSec))
                if (this.videoPageUrl) {
                  Button('网页播放').onClick(() => this.openWebPlayback())
                }
              }
            }
          }.padding(AppSpacing.LG)
        }

        // 两条操作栏各自贴边放在点按层之上：栏内按钮能收到点击，栏外的画面区域仍由点按层处理。
        // 不能给操作栏设 HitTestMode.Block，它会连栏内的按钮一起挡掉。
        if (this.showControls) {
          this.topBar()
          this.bottomBar()
        }
      }

      if (this.showEpisodes) {
        this.episodePanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width > 0 && height > 0) this.landscape = width > height;
    })
  }
}
