import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { window } from '@kit.ArkUI';
import { Book, BookChapter } from '@legado/sourceengine';
import { appDb } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { LocalChapterContentLoader } from '../core/book/LocalChapterContentLoader';
import { EpubChapterPlanner, EpubChapterSegment } from '../core/book/EpubChapterPlanner';
import { EpubConvertResult, EpubHtmlConverter } from '../core/book/EpubHtmlConverter';
import { EpubNoteLink } from '../core/book/EpubNoteLink';
import { EpubOriginalDocument, EpubOriginalPiece } from '../core/book/EpubOriginalDocument';
import { EpubOriginalPosition, EpubOriginalSpot } from '../core/book/EpubOriginalPosition';
import {
  EpubOriginalLayoutOptions, EpubOriginalMargins, EpubOriginalScript, EpubOriginalTarget
} from '../core/book/EpubOriginalScript';
import { ReaderImageMarker } from '../core/book/ReaderImageMarker';
import { ReaderNoteContent } from '../components/reader/ReaderNoteContent';
import { EpubOriginalControls } from '../components/reader/EpubOriginalControls';
import { ReaderLayoutElementSettingsPanel } from '../components/reader/ReaderLayoutElementSettingsPanel';
import { ReaderQuickJumpModel } from '../core/reader/ReaderQuickJumpModel';
import { ReaderBrightnessSession } from '../utils/ReaderBrightnessSession';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { AppFontSize } from '../theme/AppFontSize';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ReaderProgressCheckpoint } from '../utils/ReaderProgressCheckpoint';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderOpenTrace } from '../utils/ReaderOpenTrace';
import { syncDesktopTitleBar, syncSystemSafeAreas } from '../utils/SystemBars';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { WebDavBookService } from '../webdav/WebDavBookService';
import {
  ReaderShelfCoverOpening, SHELF_COVER_OPEN_ANGLE, SHELF_COVER_OPEN_DURATION, SHELF_COVER_OPEN_START_CAP,
  SHELF_COVER_CLOSE_DURATION, SHELF_COVER_FRAME_RATE, SHELF_BOOK_MOTION_UNTIL_KEY, SHELF_BOOK_MOTION_SETTLE,
  SHELF_OPENING_COVER_KEY, ShelfOpeningCover, ShelfOpeningIdleStarter
} from '../components/reader/ReaderShelfCoverOpening';

/** 本书的文件排版设置与位置（书籍变量）。 */
const SCROLL_KEY = 'epubOriginalScroll';
const ZOOM_KEY = 'epubOriginalZoom';
const POSITION_KEY = 'epubOriginalPosition';
/** 与普通阅读器共用的章内字符偏移（见 ReadBook 的 READER_PROGRESS_OFFSET_KEY）。 */
const NATIVE_OFFSET_KEY = 'readProgressCharOffsetV2';
const NATIVE_OFFSET_CHAPTER_KEY = 'readProgressCharOffsetChapterV2';
const NOTE_POPUP_MAX_CHARS = 320;
/** 章节文档交给网页后这么久还没排好版，就不再一直转圈。 */
const CHAPTER_READY_TIMEOUT_MS = 12000;
const MAX_RESOURCE_BYTES = 64 * 1024 * 1024;

/** 网页回报的阅读位置。 */
class EpubOriginalReport {
  snippet: string = '';
  fraction: number = 0;
  page: number = 0;
  count: number = 1;
  scroll: number = 0;
}

/** 文件排版上次保存的位置；offset 与普通阅读器的偏移相同时说明之后没在普通阅读器里读过，可以直接用 snippet。 */
class EpubOriginalSavedPosition {
  chapter: number = -1;
  offset: number = -1;
  snippet: string = '';
  fraction: number = 0;
}

/** 网页脚本调用的宿主对象；方法名见 EpubOriginalScript.HOST_METHODS。回调都推到下一轮再处理，不在网页的同步调用里跑。 */
class EpubOriginalBridge {
  onReady: (count: number, page: number) => void;
  onPosition: (json: string) => void;
  onTap: (x: number, y: number) => void;
  onLink: (href: string, note: boolean, x: number, y: number) => void;
  onEdge: (direction: number) => void;

  constructor(onReady: (count: number, page: number) => void, onPosition: (json: string) => void,
    onTap: (x: number, y: number) => void, onLink: (href: string, note: boolean, x: number, y: number) => void,
    onEdge: (direction: number) => void) {
    this.onReady = onReady;
    this.onPosition = onPosition;
    this.onTap = onTap;
    this.onLink = onLink;
    this.onEdge = onEdge;
  }

  ready(count: number, page: number): void {
    setTimeout((): void => this.onReady(Number(count) || 1, Number(page) || 0), 0);
  }

  position(json: string): void {
    setTimeout((): void => this.onPosition(`${json}`), 0);
  }

  tap(x: number, y: number): void {
    setTimeout((): void => this.onTap(Number(x), Number(y)), 0);
  }

  link(href: string, note: number, x: number, y: number): void {
    setTimeout((): void => this.onLink(`${href}`, Number(note) === 1, Number(x), Number(y)), 0);
  }

  edge(direction: number): void {
    setTimeout((): void => this.onEdge(Number(direction)), 0);
  }
}

class EpubChapterTitleSource implements IDataSource {
  private titles: string[] = [];
  private listeners: DataChangeListener[] = [];

  reset(titles: string[]): void {
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

/**
 * EPUB“文件排版”阅读页：解压目录里的原始 XHTML、CSS、字体、图片原样交给网页组件，按书本身的样式渲染。
 * 章节划分、目录、阅读进度与普通阅读器共用；两边切换时用 EpubOriginalPosition 换算章内位置。
 * 翻页模式用 CSS 多栏分页（见 EpubOriginalScript），滚动模式每章一个长网页。
 */
@Entry
@Component
struct EpubOriginalReadBookPage {
  /** 深色跟随应用全局的日夜模式：深色时页面整体反色，图片保持原样。 */
  @StorageLink('appDarkMode') @Watch('onAppDarkChanged') darkMode: boolean = false;
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('launchShortcutNonce') @Watch('onShortcut') shortcutNonce: number = 0;
  @State title: string = '文件排版';
  @State chapterTitle: string = '';
  @State chapterIndex: number = 0;
  @State chapterCount: number = 0;
  @State pageIndex: number = 0;
  @State pageCount: number = 1;
  @State @Watch('applySystemBars') ready: boolean = false;
  @State loading: boolean = true;
  @State statusText: string = '正在打开…';
  @State failed: boolean = false;
  @State @Watch('applySystemBars') menuVisible: boolean = false;
  @State activePanel: string = '';
  @State @Watch('syncLayoutElementDialog') showLayoutElements: boolean = false;
  /** 快速跳转在等确认或正在载入目标章节。 */
  @State jumpBusy: boolean = false;
  @State brightnessValue: number = -1;
  @State lastManualBrightness: number = 50;
  @State brightnessReady: boolean = false;
  @State paged: boolean = true;
  @State zoom: number = 100;
  @State showNotePopup: boolean = false;
  @State showNoteSheet: boolean = false;
  @State noteX: number = 0;
  @State noteY: number = 0;
  @State notePlacement: Placement = Placement.Bottom;
  @State noteLabel: string = '';
  @State noteBlocks: string[] = [];
  @State viewWidth: number = 360;
  @State viewHeight: number = 720;
  @State visible: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: EpubOriginalBridge = new EpubOriginalBridge(
    (count: number, page: number): void => this.onDocumentReady(count, page),
    (json: string): void => this.onPosition(json),
    (x: number, y: number): void => this.onTap(x, y),
    (href: string, note: boolean, x: number, y: number): void => this.onLink(href, note, x, y),
    (direction: number): void => this.onEdge(direction));
  private titleSource: EpubChapterTitleSource = new EpubChapterTitleSource();
  private book: Book | null = null;
  private bookUrl: string = '';
  private extractRoot: string = '';
  private chapters: BookChapter[] = [];
  private documents: Map<string, string> = new Map<string, string>();
  private nativeTexts: Map<number, string> = new Map<number, string>();
  private spot: EpubOriginalSpot = new EpubOriginalSpot();
  private attached: boolean = false;
  /**
   * 声明式 src 的 about:blank 在控制器挂上之后才开始载入，会把在它之前 loadUrl 的章节顶掉。
   * 等它载完再载章节（与 NativeCommentPageView 相同）。
   */
  private blankReady: boolean = false;
  private pendingUrl: string = '';
  private readyTimer: number = -1;
  /** 上次收起或唤出菜单的时间：网页回报的点按晚一拍到达，紧跟在菜单切换之后的那一下不再重复切换。 */
  private menuToggledAt: number = 0;
  /** 开始载入章节的时间；载入卡住时，过一会儿也允许再次翻到下一章。 */
  private loadStartedAt: number = 0;
  private brightnessSession: ReaderBrightnessSession = new ReaderBrightnessSession();
  private layoutElementDialog: SystemDialogSession = new SystemDialogSession();
  /** 阅读设置里的“屏幕常亮”分钟数，与普通阅读页同一个设置；0 跟随系统。 */
  private screenTimeoutMinutes: number = ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
  private screenTimeoutTimer: number = -1;
  private screenTimeoutSerial: number = 0;
  private loadSerial: number = 0;
  private noteSerial: number = 0;
  private alive: boolean = true;
  private saveTimer: number = -1;
  private saveTask: Promise<void> = Promise.resolve();
  private owner: string = `epub-original-${Date.now()}-${Math.random()}`;
  private shortcutReplace: boolean = false;
  private closing: boolean = false;
  private switching: boolean = false;
  // 从书架封面翻开的动画，与 PDF 阅读页相同（见 PdfReadBook）。
  @State shelfSharedCoverId: string = '';
  @State shelfCoverVisible: boolean = false;
  @State shelfCoverAngle: number = SHELF_COVER_OPEN_ANGLE;
  @State shelfCoverShade: number = 0.5;
  @State shelfCoverScaleX: number = 0;
  @State shelfCoverFillImage: boolean = false;
  @State shelfCoverFrameVisible: boolean = true;
  @State shelfOpenScaleX: number = 1;
  @State shelfOpenScaleY: number = 1;
  @State shelfOpenTranslateX: number = 0;
  @State shelfOpenTranslateY: number = 0;
  private openedWithShelfAnimation: boolean = false;
  private shelfOpeningCover: ShelfOpeningCover | null = null;
  private shelfPendingSharedCoverId: string = '';
  private shelfOpenAnimating: boolean = false;
  private shelfOpenStarted: boolean = false;
  private shelfOpenStartTimer: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    const params = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.bookUrl = params?.['bookUrl'] || '';
    this.shortcutReplace = params?.['shortcutEntry'] === 'true' && params?.['shortcutReplace'] === 'true';
    // 这之前不能有 await：第一帧就要缩在书架封面上。
    this.openedWithShelfAnimation = params?.['shelfBookOpening'] === 'true';
    this.shelfSharedCoverId = params?.['shelfSharedCoverId'] || '';
    const openingCover = AppStorage.get<ShelfOpeningCover>(SHELF_OPENING_COVER_KEY);
    this.shelfOpeningCover = this.shelfSharedCoverId && openingCover && openingCover.bookUrl === this.bookUrl ?
      openingCover : null;
    this.prepareShelfOpening();
    if (!this.shelfOpenAnimating) AppStorage.setOrCreate('shelfReaderDirectTransition', false);
    ReaderProgressCheckpoint.attach(this.owner, (): Promise<void> => this.saveProgress(), (): string => this.bookUrl);
    this.open();
  }

  onPageShow(): void {
    this.visible = true;
    this.activateBrightness();
    this.applyScreenTimeout();
    this.applySystemBars();
    if (this.ready) readStatsTracker.setReadingActive(this.bookUrl);
    this.onShortcut();
  }

  onPageHide(): void {
    this.visible = false;
    this.showLayoutElements = false;
    this.brightnessSession.deactivate();
    this.releaseScreenTimeout();
    this.applySystemBars();
    readStatsTracker.setReadingActive('');
    this.flushAndSyncProgress();
  }

  aboutToDisappear(): void {
    this.flushAndSyncProgress();
    this.alive = false;
    this.loadSerial++;
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    this.showLayoutElements = false;
    this.brightnessSession.deactivate();
    this.releaseScreenTimeout();
    this.applySystemBars();
    ReaderProgressCheckpoint.detach(this.owner);
    readStatsTracker.setReadingActive('');
  }

  onBackPress(): boolean {
    if (this.showLayoutElements) {
      this.showLayoutElements = false;
      return true;
    }
    if (this.showNotePopup || this.showNoteSheet) {
      this.showNotePopup = false;
      this.showNoteSheet = false;
      return true;
    }
    if (this.activePanel) {
      this.activePanel = '';
      return true;
    }
    if (this.menuVisible) {
      this.menuVisible = false;
      return true;
    }
    this.close();
    return true;
  }

  private async open(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('无法获取应用上下文');
      await appDb.initWithContext(context);
      let book = await appDb.getBook(this.bookUrl);
      if (!book) throw new Error('未找到这本书，请重新导入');
      if (CloudAutoSync.isPlaceholder(book)) {
        this.statusText = '正在从云端下载书籍…';
        book = await CloudAutoSync.ensureBookDownloaded(context, book);
      }
      if (LocalBookService.isWebDavBook(book)) {
        book = await WebDavBookService.ensureCached(context, book, (message: string): void => {
          if (this.alive) this.statusText = message;
        });
      }
      this.statusText = '正在准备书籍…';
      if (await LocalBookService.ensureLocalParserCurrent(context, book)) {
        book = await appDb.getBook(this.bookUrl) || book;
      }
      if (!this.alive) return;
      if (!LocalBookService.canUseEpubOriginalLayout(book)) throw new Error('这本书不能用文件排版打开');
      if (!LocalBookService.usesEpubOriginalLayout(book)) {
        // 书架上的书籍记录还没刷新（刚在别处关掉了文件排版）：交回普通阅读器。
        await this.getUIContext().getRouter().replaceUrl({
          url: 'pages/ReadBook', params: { bookUrl: this.bookUrl, formatChecked: 'true' }
        });
        return;
      }
      this.extractRoot = EpubHtmlConverter.normalizePath(book.getVariable('localExtractRoot'));
      if (!this.extractRoot || !LocalBookService.exists(this.extractRoot)) throw new Error('书籍文件不存在，请重新导入');
      this.chapters = await appDb.getBookChapters(this.bookUrl);
      if (!this.alive) return;
      if (this.chapters.length === 0) throw new Error('这本书没有可阅读的章节');
      this.book = book;
      this.title = book.name || '文件排版';
      this.chapterCount = this.chapters.length;
      this.titleSource.reset(this.chapters.map((chapter: BookChapter, index: number): string =>
        chapter.title || `第${index + 1}章`));
      await this.loadReaderSettings(context);
      this.paged = book.getVariable(SCROLL_KEY) !== '1';
      const zoom = Number(book.getVariable(ZOOM_KEY));
      this.zoom = Number.isFinite(zoom) && zoom >= 50 && zoom <= 250 ? Math.round(zoom) : 100;
      const index = Math.max(0, Math.min(this.chapters.length - 1, book.durChapterIndex));
      await this.loadChapter(index, await this.initialTarget(book, index));
    } catch (error) {
      if (this.alive) this.fail(error instanceof Error ? error.message : '打开失败');
    }
  }

  /** 打开时的位置：没在普通阅读器里读过就用上次的文字片段，否则从普通阅读器的章内偏移换算。 */
  private async initialTarget(book: Book, index: number): Promise<EpubOriginalTarget> {
    const target = new EpubOriginalTarget();
    const offset = book.getVariable(NATIVE_OFFSET_CHAPTER_KEY) === `${index}` ?
      Number(book.getVariable(NATIVE_OFFSET_KEY)) : -1;
    const saved = this.savedPosition(book);
    if (saved && saved.chapter === index && (offset < 0 || saved.offset === offset) && saved.snippet) {
      target.kind = 'spot';
      target.snippet = saved.snippet;
      target.fraction = saved.fraction;
      return target;
    }
    if (Number.isFinite(offset) && offset > 0) {
      const spot = EpubOriginalPosition.spotAt(await this.nativeText(index), offset);
      if (spot.snippet) {
        target.kind = 'spot';
        target.snippet = spot.snippet;
        target.fraction = spot.fraction;
      }
    }
    return target;
  }

  private savedPosition(book: Book): EpubOriginalSavedPosition | null {
    const raw = book.getVariable(POSITION_KEY);
    if (!raw) return null;
    try {
      const value = JSON.parse(raw) as EpubOriginalSavedPosition;
      const saved = new EpubOriginalSavedPosition();
      saved.chapter = Number(value.chapter);
      saved.offset = Number(value.offset);
      saved.snippet = `${value.snippet || ''}`;
      saved.fraction = Number(value.fraction) || 0;
      return Number.isFinite(saved.chapter) ? saved : null;
    } catch (_) {
      return null;
    }
  }

  /** 快速跳转、亮度、屏幕常亮这些设置与普通阅读页共用；直接从书架进来时普通阅读页还没读过它们。 */
  private async loadReaderSettings(context: Context): Promise<void> {
    try {
      const settings: ReaderSettings = await ReaderSettingsStore.load(context);
      AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP, settings.useChapterQuickJump);
      AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_BRIGHTNESS_QUICK_ACTION, settings.useBrightnessQuickAction);
      AppStorage.setOrCreate(ReaderSettingsStore.KEY_QUICK_JUMP_MODE,
        ReaderQuickJumpModel.normalizeMode(settings.quickJumpMode));
      this.screenTimeoutMinutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(settings.screenTimeoutMinutes);
      this.applyScreenTimeout();
    } catch (error) {
      console.warn('[EpubOriginal] reader settings failed:', error);
    }
  }

  private activateBrightness(): void {
    this.brightnessReady = false;
    this.brightnessSession.activate(this.getUIContext().getHostContext() as Context, (value: number): void => {
      this.brightnessValue = value;
      if (value >= 0) this.lastManualBrightness = value;
      this.brightnessReady = true;
    }, (): void => HdsFeedback.showToast('阅读亮度设置失败，请稍后重试'));
  }

  private setBrightness(value: number, persist: boolean): void {
    this.brightnessValue = value;
    if (value >= 0) this.lastManualBrightness = value;
    this.brightnessSession.set(value, persist);
  }

  /** 与普通阅读页 applyReaderScreenTimeout 相同：0 跟随系统，正数为无操作后保持常亮的分钟数，其余一直常亮。 */
  private applyScreenTimeout(): void {
    if (this.screenTimeoutTimer >= 0) {
      clearTimeout(this.screenTimeoutTimer);
      this.screenTimeoutTimer = -1;
    }
    const serial = ++this.screenTimeoutSerial;
    const minutes = this.screenTimeoutMinutes;
    if (!this.visible || minutes === ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM) {
      this.setKeepScreenOn(false, serial);
      return;
    }
    this.setKeepScreenOn(true, serial);
    if (minutes > 0) {
      this.screenTimeoutTimer = setTimeout((): void => {
        this.screenTimeoutTimer = -1;
        if (serial === this.screenTimeoutSerial) this.setKeepScreenOn(false, serial);
      }, minutes * 60 * 1000);
    }
  }

  /** 有操作时重新计时。 */
  private refreshScreenTimeout(): void {
    if (this.visible && this.screenTimeoutMinutes > 0) this.applyScreenTimeout();
  }

  private releaseScreenTimeout(): void {
    if (this.screenTimeoutTimer >= 0) {
      clearTimeout(this.screenTimeoutTimer);
      this.screenTimeoutTimer = -1;
    }
    this.setKeepScreenOn(false, ++this.screenTimeoutSerial);
  }

  private setKeepScreenOn(enabled: boolean, serial: number): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    window.getLastWindow(context).then((mainWindow: window.Window): void => {
      if (serial !== this.screenTimeoutSerial) return;
      mainWindow.setWindowKeepScreenOn(enabled).catch((error: Error): void => {
        console.warn('[EpubOriginal] keep screen on failed:', error);
      });
    }).catch((error: Error): void => { console.warn('[EpubOriginal] window failed:', error); });
  }

  @Builder
  layoutElementDialogContent() {
    ReaderLayoutElementSettingsPanel({
      comicMode: false,
      showReadingActions: false,
      dark: this.appDark(),
      textColor: ThemeRuntime.primaryTextColor(this.darkMode),
      subTextColor: ThemeRuntime.subTextColor(this.darkMode),
      accentColor: ThemeRuntime.accentColor(this.darkMode),
      onClose: (): void => {
        this.showLayoutElements = false;
      }
    })
  }

  syncLayoutElementDialog(): void {
    this.layoutElementDialog.sync(this.getUIContext(), this.showLayoutElements, (): void => {
      this.layoutElementDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.darkMode),
      warnTag: '显示布局元素设置失败:',
      onDismiss: (): void => {
        this.showLayoutElements = false;
      }
    });
  }

  private appDark(): boolean {
    return this.darkMode;
  }

  private openLayoutElements(): void {
    this.activePanel = '';
    this.showLayoutElements = true;
  }

  // ---- 快速跳转：与普通阅读页相同，章节与百分比松手后确认，本章页数也要确认；左右箭头直接到上一章、下一章 ----

  private async quickJump(mode: string, value: number): Promise<void> {
    if (this.jumpBusy || !this.ready || this.chapters.length === 0) return;
    const count = this.chapters.length;
    let chapter = this.chapterIndex;
    let ratio = -1;
    let page = -1;
    let message = '';
    if (mode === 'percent') {
      const target = ReaderQuickJumpModel.fromPercent(value, count);
      chapter = target.chapterIndex;
      ratio = target.chapterRatio;
      message = `跳转到全书 ${ReaderQuickJumpModel.clampPercent(value).toFixed(1)}%？\n` +
        `「${this.chapterTitleAt(chapter)}」· 约章内 ${Math.round(ratio * 100)}%`;
    } else if (mode === 'page') {
      page = Math.max(0, Math.min(Math.round(value), this.pageCount - 1));
      if (page === this.pageIndex) return;
      message = `跳转到本章第 ${page + 1} 页？\n「${this.chapterTitle}」· 共 ${this.pageCount} 页`;
    } else {
      chapter = Math.max(0, Math.min(count - 1, Math.round(value)));
      if (chapter === this.chapterIndex && this.pageIndex === 0) return;
      message = `跳转到「${this.chapterTitleAt(chapter)}」？\n从该章开头继续阅读`;
    }
    const serial = this.loadSerial;
    this.jumpBusy = true;
    let confirmed = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认跳转',
        message: message,
        buttons: [
          { text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
          { text: '跳转', color: ThemeRuntime.accentColor(this.darkMode) }
        ]
      });
      confirmed = result.index === 1 && this.alive && serial === this.loadSerial;
    } catch (error) {
      console.warn('[EpubOriginal] quick jump dialog failed:', error);
    } finally {
      this.jumpBusy = false;
    }
    if (!confirmed) return;
    if (mode === 'page') {
      this.run(`__legado.goPage(${page}, false)`);
      HdsFeedback.showToast(`已跳转至第 ${page + 1} 页`);
      return;
    }
    const target = new EpubOriginalTarget();
    if (ratio > 0) {
      target.kind = 'spot';
      target.fraction = ratio;
    }
    if (chapter === this.chapterIndex && ratio >= 0) {
      this.run(`__legado.goSpot('', ${ratio})`);
    } else {
      this.loadChapter(chapter, target);
    }
    HdsFeedback.showToast(mode === 'percent' ? `已跳转至全书 ${ReaderQuickJumpModel.clampPercent(value).toFixed(1)}%` :
      `已跳转至第 ${chapter + 1} 章`);
  }

  private chapterTitleAt(index: number): string {
    const chapter = this.chapters[index];
    return chapter && chapter.title ? chapter.title : `第${index + 1}章`;
  }

  /** 普通阅读器的章节正文，只用来换算位置。 */
  private async nativeText(index: number): Promise<string> {
    const cached = this.nativeTexts.get(index);
    if (cached !== undefined) return cached;
    let text = '';
    try {
      text = await appDb.getCachedChapterContent(this.bookUrl, index);
      if (!text && this.book && this.chapters[index]) {
        text = await LocalChapterContentLoader.load(this.book, this.chapters[index]);
      }
    } catch (error) {
      console.warn('[EpubOriginal] native text failed:', error);
    }
    if (this.nativeTexts.size >= 4) this.nativeTexts.clear();
    this.nativeTexts.set(index, text || '');
    return text || '';
  }

  private async loadChapter(index: number, target: EpubOriginalTarget): Promise<void> {
    const chapter = this.chapters[index];
    if (!chapter) return;
    const serial = ++this.loadSerial;
    this.loading = true;
    this.loadStartedAt = Date.now();
    this.showNotePopup = false;
    let segments = EpubChapterPlanner.decodeSegments(chapter.variable);
    if (segments.length === 0) {
      const whole = new EpubChapterSegment();
      whole.path = EpubHtmlConverter.normalizePath(EpubHtmlConverter.withoutFragment(chapter.resourceUrl || ''));
      segments = [whole];
    }
    const relative: EpubChapterSegment[] = [];
    const pieces: EpubOriginalPiece[] = [];
    const loaded = new Set<string>();
    for (const segment of segments) {
      const absolute = EpubHtmlConverter.normalizePath(segment.path);
      if (!absolute.startsWith(`${this.extractRoot}/`) || !LocalBookService.exists(absolute)) continue;
      const path = absolute.substring(this.extractRoot.length + 1);
      const piece = new EpubChapterSegment();
      piece.path = path;
      piece.startId = segment.startId;
      piece.endId = segment.endId;
      relative.push(piece);
      if (loaded.has(path)) continue;
      loaded.add(path);
      const file = new EpubOriginalPiece();
      file.path = path;
      if (EpubHtmlConverter.isImagePath(path)) {
        // spine 里直接放图片的书：包一层页面，图片按一屏大小居中。
        const name = path.substring(path.lastIndexOf('/') + 1);
        file.html = `<html><body><div style="text-align:center"><img src="${encodeURIComponent(name)}" ` +
          'style="max-width:100%"/></div></body></html>';
      } else {
        try {
          file.html = await LocalChapterContentLoader.readHtmlFile(absolute);
        } catch (error) {
          console.warn('[EpubOriginal] read chapter file failed:', path, error);
          file.html = '';
        }
      }
      pieces.push(file);
    }
    if (serial !== this.loadSerial || !this.alive) return;
    const options = new EpubOriginalLayoutOptions();
    options.paged = this.paged;
    options.forceDark = this.darkMode;
    options.margins = this.margins();
    options.target = target;
    const html = EpubOriginalDocument.build(pieces, relative, EpubOriginalScript.injection(options),
      chapter.title || this.title);
    const url = EpubOriginalDocument.chapterUrl(index, serial);
    this.documents.clear();
    this.documents.set(url, html);
    this.chapterIndex = index;
    this.chapterTitle = chapter.title || `第${index + 1}章`;
    this.pageIndex = 0;
    this.pageCount = 1;
    this.navigate(url);
  }

  private margins(): EpubOriginalMargins {
    const margins = new EpubOriginalMargins();
    margins.left = 22;
    margins.right = 22;
    margins.top = this.statusBarHeight + (this.paged ? 28 : 16);
    margins.bottom = this.navBarHeight + (this.paged ? 28 : 24);
    return margins;
  }

  private navigate(url: string): void {
    this.armReadyTimer();
    if (!this.attached || !this.blankReady) {
      this.pendingUrl = url;
      return;
    }
    try {
      this.controller.loadUrl(url);
    } catch (error) {
      console.warn('[EpubOriginal] load failed:', error);
      this.fail('页面加载失败');
    }
  }

  private flushPendingUrl(): void {
    if (!this.pendingUrl || !this.attached || !this.blankReady) return;
    const url = this.pendingUrl;
    this.pendingUrl = '';
    this.navigate(url);
  }

  private armReadyTimer(): void {
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    const serial = this.loadSerial;
    this.readyTimer = setTimeout((): void => {
      this.readyTimer = -1;
      if (!this.alive || serial !== this.loadSerial || !this.loading) return;
      console.warn('[EpubOriginal] chapter not ready in time:', this.chapterIndex);
      if (!this.ready) {
        this.fail('文件排版没能打开这一章，可以改用应用排版阅读');
      } else {
        this.loading = false;
        HdsFeedback.showToast('这一章排版超时');
      }
    }, CHAPTER_READY_TIMEOUT_MS);
  }

  private reloadAtCurrentSpot(): void {
    const target = new EpubOriginalTarget();
    target.kind = this.spot.snippet ? 'spot' : 'start';
    target.snippet = this.spot.snippet;
    target.fraction = this.spot.fraction;
    this.loadChapter(this.chapterIndex, target);
  }

  // ---- 网页组件：只放行虚拟站点，书里的文件从解压目录读，其它请求一律拒绝 ----

  private intercept(url: string): WebResourceResponse | null {
    if (!url || url.startsWith('about:')) return null;
    if (EpubOriginalDocument.isChapterUrl(url)) {
      const html = this.documents.get(url.replace(/#.*$/, ''));
      return html !== undefined ? this.response(html, 'text/html', 200) : this.response('', 'text/plain', 404);
    }
    const path = EpubOriginalDocument.pathOf(url);
    if (!path || EpubOriginalDocument.isScript(path)) return this.response('', 'text/plain', 403);
    const response = new WebResourceResponse();
    response.setResponseIsReady(false);
    this.fillResource(response, path).catch((error: Error): void => {
      console.warn('[EpubOriginal] resource failed:', path, error);
      response.setResponseData('');
      response.setResponseCode(404);
      response.setReasonMessage('Not Found');
      response.setResponseIsReady(true);
    });
    return response;
  }

  private response(data: string, mime: string, code: number): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseData(data);
    response.setResponseMimeType(mime);
    response.setResponseEncoding('utf-8');
    response.setResponseCode(code);
    response.setReasonMessage(code === 200 ? 'OK' : 'Blocked');
    return response;
  }

  private async fillResource(response: WebResourceResponse, path: string): Promise<void> {
    const absolute = `${this.extractRoot}/${path}`;
    const stat = await fs.stat(absolute);
    if (!stat.isFile() || stat.size > MAX_RESOURCE_BYTES) throw new Error('not a readable file');
    const file = await fs.open(absolute, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(stat.size);
    try {
      if (stat.size > 0) await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
    } finally {
      await fs.close(file);
    }
    const mime = EpubOriginalDocument.mimeType(path);
    response.setResponseData(buffer);
    response.setResponseMimeType(mime);
    if (EpubOriginalDocument.isText(mime)) response.setResponseEncoding('utf-8');
    response.setResponseHeader([{ headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }]);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseIsReady(true);
  }

  // ---- 网页回报 ----

  private onDocumentReady(count: number, page: number): void {
    if (!this.alive) return;
    this.pageCount = Math.max(1, count);
    this.pageIndex = Math.max(0, Math.min(this.pageCount - 1, page));
    this.loading = false;
    if (this.readyTimer >= 0) {
      clearTimeout(this.readyTimer);
      this.readyTimer = -1;
    }
    if (!this.ready) {
      this.ready = true;
      this.statusText = '';
      ReaderOpenTrace.finish(this.bookUrl, 'epub-original-ready');
      if (this.visible) readStatsTracker.setReadingActive(this.bookUrl);
    }
  }

  private onPosition(json: string): void {
    if (!this.alive) return;
    try {
      const report = JSON.parse(json) as EpubOriginalReport;
      const spot = new EpubOriginalSpot();
      spot.snippet = `${report.snippet || ''}`;
      spot.fraction = Number(report.fraction) || 0;
      this.spot = spot;
      this.pageIndex = Math.max(0, Number(report.page) || 0);
      this.pageCount = Math.max(1, Number(report.count) || 1);
      this.scheduleSave();
    } catch (error) {
      console.warn('[EpubOriginal] bad position report:', error);
    }
  }

  private onTap(x: number, y: number): void {
    this.refreshScreenTimeout();
    if (Date.now() - this.menuToggledAt < 400) return;
    if (this.showNotePopup) {
      this.showNotePopup = false;
      return;
    }
    if (this.menuVisible) {
      this.toggleMenu();
      return;
    }
    if (this.paged) {
      if (x < 0.3) this.run('__legado.prev(true)');
      else if (x > 0.7) this.run('__legado.next(true)');
      else this.toggleMenu();
      return;
    }
    if (y < 0.3) this.run('__legado.screen(-1)');
    else if (y > 0.7) this.run('__legado.screen(1)');
    else this.toggleMenu();
  }

  private onEdge(direction: number): void {
    this.refreshScreenTimeout();
    // 正在载入时连续翻页只算一次；载入超过几秒还没好（卡住）就允许重新触发。
    if (this.loading && Date.now() - this.loadStartedAt < 3000) return;
    if (direction > 0) {
      if (this.chapterIndex >= this.chapters.length - 1) {
        HdsFeedback.showToast('已经是最后一章');
        return;
      }
      this.loadChapter(this.chapterIndex + 1, new EpubOriginalTarget());
      return;
    }
    if (this.chapterIndex <= 0) {
      HdsFeedback.showToast('已经是第一章');
      return;
    }
    const target = new EpubOriginalTarget();
    target.kind = 'end';
    this.loadChapter(this.chapterIndex - 1, target);
  }

  private onLink(href: string, note: boolean, x: number, y: number): void {
    const path = EpubOriginalDocument.pathOf(href);
    if (!path) {
      HdsFeedback.showToast('暂不支持打开书外的链接');
      return;
    }
    const fragment = EpubOriginalDocument.fragmentOf(href);
    if (note && fragment) {
      this.openNote(path, fragment, x, y);
      return;
    }
    this.jumpTo(path, fragment);
  }

  private run(script: string): void {
    if (!this.attached) return;
    try {
      this.controller.runJavaScript(`window.__legado && ${script}`).catch((error: Error): void => {
        console.warn('[EpubOriginal] script failed:', error);
      });
    } catch (error) {
      console.warn('[EpubOriginal] script failed:', error);
    }
  }

  // ---- 注释与书内跳转 ----

  private openNote(path: string, fragment: string, x: number, y: number): void {
    const book = this.book;
    if (!book) return;
    const serial = ++this.noteSerial;
    LocalChapterContentLoader.loadNote(book, EpubNoteLink.create(path, fragment))
      .then((note: EpubConvertResult | null): void => {
        if (serial !== this.noteSerial || !this.alive) return;
        const blocks = note ? EpubNoteLink.blocks(note.content) : [];
        if (blocks.length === 0) {
          this.jumpTo(path, fragment);
          return;
        }
        this.noteLabel = '';
        this.noteBlocks = blocks;
        const long = (note?.content.length ?? 0) > NOTE_POPUP_MAX_CHARS ||
          blocks.some((block: string): boolean => ReaderImageMarker.isMarker(block));
        if (long) {
          this.showNoteSheet = true;
          return;
        }
        this.noteX = x;
        this.noteY = y;
        this.notePlacement = y > this.viewHeight / 2 ? Placement.Top : Placement.Bottom;
        this.showNotePopup = true;
      }).catch((error: Error): void => {
        console.warn('[EpubOriginal] note failed:', error);
        if (serial === this.noteSerial) HdsFeedback.showToast('注释读取失败');
      });
  }

  private jumpTo(path: string, fragment: string): void {
    this.chapterForTarget(path, fragment).then((index: number): void => {
      if (!this.alive) return;
      if (index < 0) {
        HdsFeedback.showToast('链接指向的内容不在正文里');
        return;
      }
      if (index === this.chapterIndex && fragment) {
        this.run(`__legado.goAnchor(${JSON.stringify(fragment)})`);
        return;
      }
      const target = new EpubOriginalTarget();
      target.kind = fragment ? 'anchor' : 'start';
      target.anchor = fragment;
      this.loadChapter(index, target);
    });
  }

  /** 链接目标所在的章节：同一个文件切成多章时按锚点所在位置挑。 */
  private async chapterForTarget(path: string, fragment: string): Promise<number> {
    const absolute = `${this.extractRoot}/${path}`;
    const candidates: number[] = [];
    const ranges: EpubChapterSegment[] = [];
    for (let index = 0; index < this.chapters.length; index++) {
      const chapter = this.chapters[index];
      const segments = EpubChapterPlanner.decodeSegments(chapter.variable);
      if (segments.length === 0 &&
        EpubHtmlConverter.normalizePath(EpubHtmlConverter.withoutFragment(chapter.resourceUrl || '')) === absolute) {
        candidates.push(index);
        ranges.push(new EpubChapterSegment());
        continue;
      }
      for (const segment of segments) {
        if (EpubHtmlConverter.normalizePath(segment.path) !== absolute) continue;
        candidates.push(index);
        ranges.push(segment);
        break;
      }
    }
    if (candidates.length <= 1 || !fragment) return candidates.length > 0 ? candidates[0] : -1;
    try {
      const body = EpubHtmlConverter.bodyOf(await LocalChapterContentLoader.readHtmlFile(absolute));
      const offset = EpubHtmlConverter.findAnchorOffset(body, fragment);
      if (offset < 0) return candidates[0];
      for (let index = candidates.length - 1; index >= 0; index--) {
        const startId = ranges[index].startId;
        const start = startId ? EpubHtmlConverter.findAnchorOffset(body, startId) : 0;
        if (start >= 0 && start <= offset) return candidates[index];
      }
    } catch (error) {
      console.warn('[EpubOriginal] locate link target failed:', error);
    }
    return candidates[0];
  }

  // ---- 进度 ----

  private scheduleSave(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      this.saveProgress().catch((error: Error): void => { console.warn('[EpubOriginal] save failed:', error); });
    }, 600);
  }

  private flushAndSyncProgress(): void {
    const context = this.getUIContext().getHostContext();
    this.saveProgress().then(async (): Promise<void> => {
      if (context) await CloudSyncCoordinator.syncAutomatically(context, CloudSyncCoordinator.TRIGGER_CHANGE);
    }).catch((error: Error): void => { console.warn('[EpubOriginal] progress sync failed:', error); });
  }

  /** 保存进度，同时写好普通阅读器的章内偏移：切回普通阅读器或在别的设备上打开都停在同一处。 */
  private saveProgress(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (!this.ready || !this.book || !ReaderProgressCheckpoint.canWrite(this.owner)) return this.saveTask;
    const index = this.chapterIndex;
    const title = this.chapterTitle;
    // 滚动模式的页是一屏，书架进度按同样的页数算。
    const page = this.pageIndex;
    const count = this.pageCount;
    const spot = this.spot;
    const paged = this.paged;
    const zoom = this.zoom;
    const timestamp = Date.now();
    const bookUrl = this.bookUrl;
    const task = this.saveTask.catch((): void => {}).then(async (): Promise<void> => {
      const latest = await appDb.getBook(bookUrl);
      if (!latest || timestamp < latest.durChapterTime && latest.hasStartedReading()) return;
      const offset = spot.snippet ? EpubOriginalPosition.offsetFor(await this.nativeText(index), spot) : 0;
      const saved = new EpubOriginalSavedPosition();
      saved.chapter = index;
      saved.offset = offset;
      saved.snippet = spot.snippet;
      saved.fraction = spot.fraction;
      latest.putVariable('readStarted', '1');
      latest.putVariable('readProgressChapterIndex', `${index}`);
      latest.putVariable('readProgressPageCount', `${count}`);
      latest.putVariable(NATIVE_OFFSET_KEY, `${offset}`);
      latest.putVariable(NATIVE_OFFSET_CHAPTER_KEY, `${index}`);
      latest.putVariable(POSITION_KEY, JSON.stringify(saved));
      latest.putVariable(SCROLL_KEY, paged ? '' : '1');
      latest.putVariable(ZOOM_KEY, zoom === 100 ? '' : `${zoom}`);
      await appDb.updateBookReadingProgress(bookUrl, title, index, page, timestamp, latest.variable);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    });
    this.saveTask = task;
    return task;
  }

  // ---- 设置与切换 ----

  private setPaged(paged: boolean): void {
    if (this.paged === paged) return;
    this.paged = paged;
    this.reloadAtCurrentSpot();
    this.scheduleSave();
  }

  private setZoom(zoom: number): void {
    const value = Math.max(50, Math.min(250, Math.round(zoom / 10) * 10));
    if (value === this.zoom) return;
    this.zoom = value;
    // 字号改变后栏数跟着变，重新载入本章再停回原处，页码才准。
    this.reloadAtCurrentSpot();
    this.scheduleSave();
  }

  /** 应用日夜模式变了：页面跟着换深浅（重新载入本章并停回原处）。 */
  onAppDarkChanged(): void {
    this.applySystemBars();
    if (this.ready && this.alive) this.reloadAtCurrentSpot();
  }

  /** 与普通阅读页 applyReaderThemeMode 相同：改的是应用全局的日间 / 夜间 / 跟随系统。 */
  private applyThemeMode(nextMode: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const systemDark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const nextDark = nextMode === 'dark' || (nextMode === 'system' && systemDark);
    const colorMode = nextMode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (nextMode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    // 先同步模式来源，避免 setColorMode 引起的配置更新读到旧值。
    AppThemeModeStore.applyToStorage(nextMode);
    if (this.darkMode !== nextDark) this.darkMode = nextDark;
    context.getApplicationContext().setColorMode(colorMode);
    AppThemeModeStore.save(context, nextMode).catch((error: Error): void => {
      console.warn('[EpubOriginal] save theme mode failed:', error);
    });
    HdsFeedback.showToast(nextMode === 'light' ? '已切换至日间模式' :
      (nextMode === 'dark' ? '已切换至夜间模式' : '已切换至自动模式'));
  }

  private toggleDayNight(): void {
    const mode = AppThemeModeStore.normalizeMode(this.appThemeMode);
    const dark = mode === 'dark' || (mode === 'system' && this.darkMode);
    this.applyThemeMode(dark ? 'light' : 'dark');
  }

  /** 关掉文件排版，回到普通阅读器，停在同一处。 */
  private async switchToAppLayout(): Promise<void> {
    if (this.switching) return;
    this.switching = true;
    this.activePanel = '';
    try {
      await this.saveProgress();
      const latest = await appDb.getBook(this.bookUrl);
      if (latest) {
        latest.putVariable(LocalBookService.EPUB_ORIGINAL_LAYOUT_KEY, '');
        await appDb.updateBook(latest, false);
        // 书架按书籍记录选阅读页，让它重新读一遍，下次从书架打开才不会又进文件排版。
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
      await this.getUIContext().getRouter().replaceUrl({
        url: 'pages/ReadBook', params: { bookUrl: this.bookUrl, formatChecked: 'true' }
      });
    } catch (error) {
      this.switching = false;
      console.warn('[EpubOriginal] switch to app layout failed:', error);
      HdsFeedback.showToast('切换失败');
    }
  }

  private goChapter(index: number): void {
    if (index < 0 || index >= this.chapters.length) return;
    this.activePanel = '';
    if (index === this.chapterIndex) return;
    this.loadChapter(index, new EpubOriginalTarget());
  }

  private toggleMenu(): void {
    this.menuToggledAt = Date.now();
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.activePanel = '';
      this.menuVisible = !this.menuVisible;
    });
  }

  private setPanel(panel: string): void {
    if (panel === 'close') {
      this.toggleMenu();
      return;
    }
    this.activePanel = panel;
    this.menuVisible = true;
  }

  private fail(message: string): void {
    this.ready = false;
    this.loading = false;
    this.failed = true;
    this.statusText = message;
    readStatsTracker.setReadingActive('');
  }

  /** 与 PDF 阅读页一样：正文时隐藏状态栏，菜单出现时一起出来；布局始终全屏，安全区高度不随显隐变化。 */
  applySystemBars(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    window.getLastWindow(context).then((mainWindow: window.Window): void => {
      const showStatus = !this.alive || !this.visible || this.menuVisible || !this.ready;
      const dark = this.darkMode;
      mainWindow.setWindowBackgroundColor(ThemeRuntime.pageColor(dark));
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(showStatus ? ['navigation', 'status'] : ['navigation']);
      syncDesktopTitleBar(mainWindow, dark);
      syncSystemSafeAreas(mainWindow);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: dark,
        statusBarContentColor: ThemeRuntime.primaryTextColor(dark),
        navigationBarColor: '#00000000',
        isNavigationBarLightIcon: dark,
        navigationBarContentColor: ThemeRuntime.primaryTextColor(dark)
      });
    }).catch((error: Error): void => { console.warn('[EpubOriginal] system bars failed:', error); });
  }

  private onShortcut(): void {
    if (this.alive && this.visible && RecentReadShortcut.isPending()) {
      this.saveProgress().then((): Promise<boolean> => RecentReadShortcut.openPending(true))
        .catch((error: Error): void => { console.warn('[EpubOriginal] shortcut failed:', error); });
    }
  }

  private async close(): Promise<void> {
    if (this.closing) return;
    this.closing = true;
    if (this.shortcutReplace) {
      try { await this.saveProgress(); } catch (error) { console.warn('[EpubOriginal] exit save failed:', error); }
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
        .catch((): void => { this.getUIContext().getRouter().back(); });
      return;
    }
    // 先收尾没播完的翻开动画，返回转场才有共享 id；存进度的同时合上封面。
    this.finishShelfOpening();
    const coverClosed = this.openedWithShelfAnimation ? this.closeShelfCover() : Promise.resolve();
    try { await this.saveProgress(); }
    catch (error) { console.warn('[EpubOriginal] exit save failed:', error); }
    await coverClosed;
    if (this.openedWithShelfAnimation) {
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
      AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.bookUrl);
      AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
    }
    // 封面的 SVG 边框不跟着共享转场缩放，见 ReaderShelfCoverOpening.showFrame。
    this.shelfCoverFrameVisible = false;
    this.getUIContext().getRouter().back();
  }

  pageTransition() {
    if (this.openedWithShelfAnimation || AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionEnter({ type: RouteType.Push, duration: 0 })
      PageTransitionExit({ type: RouteType.Pop, duration: 0 })
    }
  }

  private prepareShelfOpening(): void {
    const cover = this.shelfOpeningCover;
    if (!this.openedWithShelfAnimation || !cover || cover.boundsWidth <= 0 || cover.boundsHeight <= 0 ||
      cover.windowWidth <= cover.boundsWidth || cover.windowHeight <= cover.boundsHeight) {
      return;
    }
    this.shelfPendingSharedCoverId = this.shelfSharedCoverId;
    this.shelfSharedCoverId = '';
    this.shelfOpenScaleX = cover.boundsWidth / cover.windowWidth;
    this.shelfOpenScaleY = cover.boundsHeight / cover.windowHeight;
    this.shelfOpenTranslateX = cover.boundsX;
    this.shelfOpenTranslateY = cover.boundsY;
    this.shelfCoverAngle = 0;
    this.shelfCoverScaleX = 1;
    this.shelfCoverShade = 0;
    this.shelfCoverFillImage = true;
    this.shelfCoverVisible = true;
    this.shelfOpenAnimating = true;
  }

  private startShelfOpening(): void {
    if (!this.shelfOpenAnimating || this.shelfOpenStarted || this.shelfOpenStartTimer >= 0) return;
    const begin = (): void => this.beginShelfOpening();
    this.shelfOpenStartTimer = setTimeout(begin, SHELF_COVER_OPEN_START_CAP);
    try {
      this.getUIContext().postFrameCallback(new ShelfOpeningIdleStarter(begin));
    } catch (error) {
      begin();
    }
  }

  private beginShelfOpening(): void {
    if (this.shelfOpenStartTimer >= 0) { clearTimeout(this.shelfOpenStartTimer); this.shelfOpenStartTimer = -1; }
    if (!this.shelfOpenAnimating || this.shelfOpenStarted) return;
    this.shelfOpenStarted = true;
    AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY,
      Date.now() + SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
    this.getUIContext().animateTo({
      duration: SHELF_COVER_OPEN_DURATION, curve: Curve.EaseInOut,
      expectedFrameRateRange: SHELF_COVER_FRAME_RATE, onFinish: (): void => this.finishShelfOpening()
    }, (): void => {
      this.shelfOpenScaleX = 1;
      this.shelfOpenScaleY = 1;
      this.shelfOpenTranslateX = 0;
      this.shelfOpenTranslateY = 0;
      this.shelfCoverAngle = SHELF_COVER_OPEN_ANGLE;
      this.shelfCoverScaleX = 0;
      this.shelfCoverShade = 0.5;
    });
  }

  private finishShelfOpening(): void {
    if (!this.shelfOpenAnimating) return;
    if (this.shelfOpenStartTimer >= 0) { clearTimeout(this.shelfOpenStartTimer); this.shelfOpenStartTimer = -1; }
    this.shelfOpenAnimating = false;
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
    this.shelfOpenScaleX = 1;
    this.shelfOpenScaleY = 1;
    this.shelfOpenTranslateX = 0;
    this.shelfOpenTranslateY = 0;
    if (this.shelfCoverAngle === SHELF_COVER_OPEN_ANGLE) this.shelfCoverVisible = false;
    this.shelfCoverFillImage = false;
    if (this.shelfPendingSharedCoverId) {
      this.shelfSharedCoverId = this.shelfPendingSharedCoverId;
      this.shelfPendingSharedCoverId = '';
    }
  }

  private closeShelfCover(): Promise<void> {
    if (!this.shelfOpeningCover) return Promise.resolve();
    this.shelfCoverVisible = true;
    AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY,
      Date.now() + SHELF_COVER_CLOSE_DURATION + SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
    return new Promise<void>((resolve: () => void): void => {
      this.getUIContext().animateTo({
        duration: SHELF_COVER_CLOSE_DURATION, curve: Curve.Friction,
        expectedFrameRateRange: SHELF_COVER_FRAME_RATE, onFinish: resolve
      }, (): void => {
        this.shelfCoverAngle = 0;
        this.shelfCoverScaleX = 1;
        this.shelfCoverShade = 0;
      });
    });
  }

  // ---- 界面 ----

  private progressText(): string {
    if (!this.ready) return '';
    // 两种翻页方式都按页显示（滚动模式一屏算一页），与普通阅读页的菜单读数一致。
    return `${this.chapterTitle} · 第 ${this.pageIndex + 1}/${this.pageCount} 页`;
  }

  private sheetOptions(onDisappear: () => void): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      onDisappear: onDisappear
    }, this.darkMode, ThemeRuntime.accentColor(this.darkMode));
  }

  @Builder
  tocPanel() {
    List({ initialIndex: Math.max(0, this.chapterIndex - 2) }) {
      LazyForEach(this.titleSource, (title: string, index: number) => {
        ListItem() {
          Text(title).width('100%').fontSize(AppFontSize.BODY)
            .fontWeight(index === this.chapterIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.chapterIndex ? ThemeRuntime.accentColor(this.darkMode) :
              ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ minHeight: 48 })
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(16)
            .backgroundColor(index === this.chapterIndex ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
              Color.Transparent)
            .onClick((): void => { this.goChapter(index); })
        }
      }, (title: string, index: number): string => `${index}_${title}`)
    }
    .width('100%')
    .height('100%')
    .cachedCount(6)
    .scrollBar(BarState.Auto)
    .padding({ left: 8, right: 8, bottom: 12 })
  }

  @Builder
  notePopupContent() {
    ReaderNoteContent({ label: this.noteLabel, blocks: this.noteBlocks, dark: this.darkMode, sheet: false,
      popupWidth: Math.min(320, Math.max(200, this.viewWidth - 48)) })
  }

  @Builder
  noteSheetContent() {
    ReaderNoteContent({ label: this.noteLabel, blocks: this.noteBlocks, dark: this.darkMode, sheet: true })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
        .width('100%')
        .height('100%')
        .backgroundColor(this.darkMode ? '#141414' : '#FFFFFF')
        // 浅色时书的颜色由它自己的样式决定；应用夜间模式时由注入的反色样式转成深色。
        .darkMode(WebDarkMode.Off)
        .forceDarkAccess(false)
        .javaScriptAccess(true)
        .fileAccess(false)
        .domStorageAccess(false)
        .databaseAccess(false)
        .geolocationAccess(false)
        .multiWindowAccess(false)
        .allowWindowOpenMethod(false)
        .imageAccess(true)
        .textZoomRatio(this.zoom)
        .overScrollMode(OverScrollMode.NEVER)
        .horizontalScrollBarAccess(false)
        .verticalScrollBarAccess(!this.paged)
        .javaScriptProxy({
          object: this.bridge,
          name: EpubOriginalScript.HOST_NAME,
          methodList: EpubOriginalScript.HOST_METHODS,
          controller: this.controller
        })
        .onPermissionRequest((event: OnPermissionRequestEvent): void => event.request.deny())
        .onAlert((event: OnAlertEvent): boolean => { event.result.handleCancel(); return true; })
        .onConfirm((event: OnConfirmEvent): boolean => { event.result.handleCancel(); return true; })
        .onPrompt((event: OnPromptEvent): boolean => { event.result.handleCancel(); return true; })
        .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
          const url = event?.data?.getRequestUrl() || '';
          // 只允许载入拼好的章节文档；书里的链接由脚本拦下交给页面处理。
          return !(url.startsWith('about:') || EpubOriginalDocument.isChapterUrl(url));
        })
        .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null =>
          this.intercept(event?.request?.getRequestUrl() || ''))
        .onControllerAttached((): void => {
          this.attached = true;
          this.flushPendingUrl();
        })
        .onPageEnd((event: OnPageEndEvent): void => {
          if (this.blankReady || !event.url.startsWith('about:')) return;
          this.blankReady = true;
          this.flushPendingUrl();
        })
        .onErrorReceive((event: OnErrorReceiveEvent): void => {
          if (event.request.isMainFrame() && EpubOriginalDocument.isChapterUrl(event.request.getRequestUrl())) {
            this.fail('章节渲染失败');
          }
        })

      if (this.loading && this.ready && !this.failed) {
        LoadingProgress().width(32).height(32).color(ThemeRuntime.accentColor(this.darkMode))
          .position({ x: this.viewWidth / 2 - 16, y: this.viewHeight / 2 - 16 })
          .hitTestBehavior(HitTestMode.None)
      }

      if (!this.ready) {
        Column({ space: 16 }) {
          if (!this.failed) { LoadingProgress().width(36).height(36).color(ThemeRuntime.accentColor(this.darkMode)) }
          Text(this.statusText).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .textAlign(TextAlign.Center)
          if (this.failed) {
            Button('返回书架').backgroundColor(ThemeRuntime.accentColor(this.darkMode))
              .fontColor(ThemeRuntime.onAccentColor()).onClick((): void => { this.close(); })
            if (this.book || this.bookUrl) {
              Button('改用应用排版打开').backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
                .fontColor(ThemeRuntime.accentColor(this.darkMode)).onClick((): void => { this.switchToAppLayout(); })
            }
          }
        }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeRuntime.pageColor(this.darkMode))
      }

      EpubOriginalControls({ darkMode: this.darkMode, bookTitle: this.title, progressLabel: this.progressText(),
        menuVisible: this.menuVisible && this.ready, activePanel: this.activePanel, ready: this.ready,
        busy: this.jumpBusy || this.loading,
        chapterIndex: this.chapterIndex, chapterCount: this.chapterCount,
        pageIndex: this.pageIndex, pageCount: this.pageCount,
        paged: this.paged, zoom: this.zoom,
        brightnessValue: this.brightnessValue, lastManualBrightness: this.lastManualBrightness,
        brightnessReady: this.brightnessReady,
        tocContent: (): void => { this.tocPanel(); },
        titleOf: (index: number): string => this.chapterTitleAt(index),
        onClose: (): void => { this.close(); },
        onPanelChange: (panel: string): void => { this.setPanel(panel); },
        onQuickJump: (mode: string, value: number): void => { this.quickJump(mode, value); },
        onStep: (direction: number): void => { this.goChapter(this.chapterIndex + direction); },
        onPagedChange: (paged: boolean): void => { this.setPaged(paged); },
        onZoomChange: (zoom: number): void => { this.setZoom(zoom); },
        onDayNight: (): void => { this.toggleDayNight(); },
        onAutoMode: (): void => { this.applyThemeMode('system'); },
        onBrightnessChange: (value: number, persist: boolean): void => { this.setBrightness(value, persist); },
        onLayoutElements: (): void => { this.openLayoutElements(); },
        onAppLayout: (): void => { this.switchToAppLayout(); } })

      Column()
        .width(1)
        .height(1)
        .position({ x: this.noteX, y: this.noteY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showNotePopup, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.notePopupContent()
          }, this.notePlacement, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
            this.showNotePopup = false;
          }))

      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showNoteSheet, this.noteSheetContent(),
          this.sheetOptions((): void => { this.showNoteSheet = false; }))

      if (this.shelfOpeningCover) {
        ReaderShelfCoverOpening({ angle: this.shelfCoverAngle, shade: this.shelfCoverShade,
          scaleX: this.shelfCoverScaleX, fillImage: this.shelfCoverFillImage, showFrame: this.shelfCoverFrameVisible,
          cover: this.shelfOpeningCover })
          .width('100%')
          .height('100%')
          .visibility(this.shelfCoverVisible ? Visibility.Visible : Visibility.Hidden)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? '#141414' : '#FFFFFF')
    .id('epub_original_root')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .scale({ x: this.shelfOpenScaleX, y: this.shelfOpenScaleY, centerX: 0, centerY: 0 })
    .translate({ x: this.shelfOpenTranslateX, y: this.shelfOpenTranslateY })
    .sharedTransition(this.shelfSharedCoverId, {
      duration: SHELF_COVER_OPEN_DURATION, curve: Curve.EaseInOut, type: SharedTransitionEffectType.Exchange
    })
    .onAppear((): void => { this.startShelfOpening(); })
    .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
      this.viewWidth = Number(after.width) || this.viewWidth;
      this.viewHeight = Number(after.height) || this.viewHeight;
    })
  }
}
