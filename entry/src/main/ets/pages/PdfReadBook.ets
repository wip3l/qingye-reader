import { pdfViewManager, pdfService } from '@kit.PDFKit';
import { HomeRoute } from '../utils/HomeRoute';
import { common } from '@kit.AbilityKit';
import { Book, BookChapter, Bookmark } from '@legado/sourceengine';
import { appDb } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { PdfBookService } from '../core/book/pdf/PdfBookService';
import { PdfOutlineEntry, PdfPagePosition, PdfSearchHit, PdfSearchRect } from '../core/book/pdf/PdfModels';
import { PdfSearchTask } from '../core/concurrency/PdfSearchTask';
import { PdfNavigationDataSource } from '../core/book/pdf/PdfNavigationDataSource';
import { PdfReaderView } from '../components/reader/PdfReaderView';
import { PdfReaderControls } from '../components/reader/PdfReaderControls';
import { ReaderLayoutElementSettingsPanel } from '../components/reader/ReaderLayoutElementSettingsPanel';
import { ReaderBrightnessSession } from '../utils/ReaderBrightnessSession';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import image from '@ohos.multimedia.image';
import { AppFontSize } from '../theme/AppFontSize';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ReaderProgressCheckpoint } from '../utils/ReaderProgressCheckpoint';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderOpenTrace } from '../utils/ReaderOpenTrace';
import { window } from '@kit.ArkUI';
import { applyReaderSystemBars, syncDesktopTitleBar, syncSystemSafeAreas } from '../utils/SystemBars';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { WebDavBookService } from '../webdav/WebDavBookService';
import { ReaderComicSuperResolution, ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../account/AiAccessPolicy';
import { ReaderPdfSettings } from '../core/book/pdf/ReaderPdfSettings';
import { ReaderPdfSettingsStore } from '../core/book/pdf/ReaderPdfSettingsStore';
import {
  ReaderShelfCoverOpening, SHELF_COVER_OPEN_ANGLE, SHELF_COVER_OPEN_DURATION, SHELF_COVER_OPEN_START_CAP,
  SHELF_COVER_CLOSE_DURATION, SHELF_COVER_FRAME_RATE, SHELF_BOOK_MOTION_UNTIL_KEY, SHELF_BOOK_MOTION_SETTLE,
  detachedShelfSharedCoverId, shelfCoverCropAspect, shelfCoverLean,
  SHELF_OPENING_BACKDROP_KEY, SHELF_OPENING_COVER_KEY, ShelfOpeningCover, ShelfOpeningFrameStarter,
  SHELF_COVER_MOTION_CURVE, SHELF_OPENING_PAGE_SNAPSHOT_KEY
} from '../components/reader/ReaderShelfCoverOpening';
import { ShelfCoverLocator } from '../utils/ShelfCoverLocator';
import { ReaderOpenSnapshotMeta, ReaderOpenSnapshotStore } from '../core/reader/ReaderOpenSnapshotStore';
import { ReaderRenderFrame } from '../core/reader/ReaderRenderFrame';
import { KnockShare } from '../utils/KnockShare';
import { ReaderComicInfoBadge } from '../components/reader/ReaderComicView';
import { ReaderTocPanel, ReaderTocPanelController } from '../components/reader/ReaderTocPanel';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ReaderInfoBarClock } from '../core/reader/ReaderInfoBarClock';
import { ScreenCornerInset } from '../utils/ScreenCornerInset';
import { ReaderPageTurnAnimation } from '../core/reader/ReaderPageTurnAnimation';
import { ReaderKeyboard, ReaderKeyboardSettings } from '../core/reader/ReaderKeyboard';
import { ReaderKeyboardSettingsStore } from '../utils/ReaderKeyboardSettingsStore';
import { SmartControlKey } from '../utils/SmartControlKey';
import { ReaderTurnKeys } from '../utils/ReaderTurnKeys';
import { ReaderScreenTimeout } from '../utils/ReaderScreenTimeout';
import { TapZoneSettingsDialogContent } from '../components/TapZoneSettingsDialog';
import { ReaderHaptics } from '../utils/ReaderHaptics';
import { ReaderInputKind, ReaderInputScopes } from '../utils/ReaderInputScopes';
import {
  ReaderSnapshotPageTurn, ReaderSnapshotTurnController, ReaderSnapshotTurnHost
} from '../components/reader/ReaderSnapshotPageTurn';

const DEFAULT_TAP_ZONES: number[] = [3, 3, 2, 3, 1, 2, 2, 2, 2];
/** 截图翻页层截的是这一层：PDF 页面加角标与书签角。 */
const PDF_PAGE_SURFACE_ID = 'pdf_page_surface';
/** 翻页时跳到目标页后，等页码回报的上限与再给渲染留的时间。 */
const PAGE_SETTLE_TIMEOUT_MS = 600;
const PAGE_RENDER_WAIT_MS = 140;

@Entry
@Component
struct PdfReadBookPage {
  @StorageProp('appDarkMode') @Watch('applySystemBars') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('accountEntitlementsRevision') @Watch('refreshAiAccess') aiAccountRevision: number = 0;
  @StorageProp('accountMembershipSku') @Watch('refreshAiAccess') membershipSku: string = '';
  @StorageProp('aiTrialOpen') @Watch('refreshAiAccess') aiTrialOpen: boolean = false;
  @StorageLink('launchShortcutNonce') @Watch('onShortcut') shortcutNonce: number = 0;
  // 与书籍共用：点击区域、智控键支持；音量键、智控键开关与翻页动画在打开时从阅读设置读。
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,2,3,1,2,2,2,2';
  @StorageProp('readerSmartKeyTurnSupported') @Watch('updateTurnKeys') smartKeySupported: boolean = false;
  // 按键翻页按阅读类型生效，这里只看 PDF 一类。
  @StorageProp('readerVolumeTurnScope') @Watch('updateTurnKeys') volumeTurnScope: number = 0;
  @StorageProp('readerSmartKeyTurnScope') @Watch('updateTurnKeys') smartKeyTurnScope: number = 0;
  @State pageTurnAnimation: number = ReaderPageTurnAnimation.SLIDE;
  /** PDF 自己的全局设置：夜间页面（原样 / 调暗 / 反色）与页码角标。 */
  @State nightMode: string = ReaderPdfSettings.NIGHT_ORIGINAL;
  @State pageBadge: boolean = true;
  @State bookmarks: Bookmark[] = [];
  /** 通用目录书签面板用的条目：PDF 目录（没有目录时是各页），序号即面板里的行号。 */
  @State tocChapters: BookChapter[] = [];
  @State tocReverseOrder: boolean = false;
  @State showBookmarkActions: boolean = false;
  @State bookmarkActionX: number = 0;
  @State bookmarkActionY: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  private tocController: ReaderTocPanelController = new ReaderTocPanelController();
  private pendingBookmark: Bookmark | null = null;
  @State infoTimeText: string = '';
  @State infoBatteryPercent: number = -1;
  @State viewWidth: number = 360;
  @State viewHeight: number = 720;
  @State @Watch('syncTapZoneDialog') showTapZones: boolean = false;
  private pdfDefaults: ReaderPdfSettings = new ReaderPdfSettings();
  private turnKeys: ReaderTurnKeys = new ReaderTurnKeys('PDF');
  private screenTimeout: ReaderScreenTimeout = new ReaderScreenTimeout('PDF');
  private keyboardSettings: ReaderKeyboardSettings = new ReaderKeyboardSettings();
  private keyboard: ReaderKeyboard = new ReaderKeyboard();
  private tapZoneDialog: SystemDialogSession = new SystemDialogSession();
  private infoClock: ReaderInfoBarClock | null = null;
  private turnController: ReaderSnapshotTurnController = new ReaderSnapshotTurnController();
  private turnHost: ReaderSnapshotTurnHost = this.createTurnHost();
  private turnActive: boolean = false;
  private turnUndoPage: number = -1;
  private prewarmTimer: number = -1;
  @State title: string = 'PDF 阅读';
  @State sourcePath: string = '';
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  @State previewIndex: number = -1;
  /** 快速跳转撤销：第一次从进度条跳走前的页，关菜单即作废。 */
  @State quickJumpUndoIndex: number = -1;
  @State initialPage: number = 0;
  @State @Watch('applySystemBars') ready: boolean = false;
  @State statusText: string = '正在打开 PDF…';
  @State failed: boolean = false;
  @State @Watch('onMenuVisibleChange') menuVisible: boolean = false;
  @StorageProp('readerHideNavIndicator') @Watch('applySystemBars') readerHideNavIndicator: boolean = false;
  @State activePanel: string = '';
  @State jumpInput: string = '';
  @State searchInput: string = '';
  @State searchCount: number = 0;
  @State searchIndex: number = -1;
  @State searching: boolean = false;
  @State searchCompleted: boolean = false;
  @State continuous: boolean = true;
  @State doublePage: boolean = false;
  @State fitPage: boolean = false;
  @State wideWindow: boolean = false;
  @State superResolution: boolean = false;
  @State superResolutionAccess: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  @State showOriginal: boolean = false;
  @State enhancementStatus: string = '';
  @State layoutRevision: number = 0;
  @State visible: boolean = true;
  // 亮度条与布局元素设置与其它阅读页共用（ReaderBrightnessSession、“使用快速亮度组件”）。
  @State brightnessValue: number = -1;
  @State lastManualBrightness: number = 50;
  @State brightnessReady: boolean = false;
  @State @Watch('syncLayoutElementDialog') showLayoutElements: boolean = false;
  private brightnessSession: ReaderBrightnessSession = new ReaderBrightnessSession();
  private layoutElementDialog: SystemDialogSession = new SystemDialogSession();
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @State navigationIndex: number = 0;
  @State navigationTitle: string = '目录';
  @State navigationCount: number = 0;
  private navigation: PdfNavigationDataSource = new PdfNavigationDataSource();
  private book: Book | null = null;
  private bookUrl: string = '';
  private alive: boolean = true;
  private generation: number = 0;
  private searchGeneration: number = 0;
  private searchHits: PdfSearchHit[] = [];
  private saveTimer: number = -1;
  private saveTask: Promise<void> = Promise.resolve();
  private owner: string = `pdf-${Date.now()}-${Math.random()}`;
  private shortcutReplace: boolean = false;
  private closing: boolean = false;
  private recentReadCardReloadAt: number = 0;
  // Shelf cover-open animation, the same motion as the text reader (see ReadBook.prepareShelfOpening).
  @State shelfSharedCoverId: string = '';
  /** Home-page snapshot shown behind the page while it grows out of, or shrinks back onto, the shelf cover (see ReadBook). */
  @State shelfMotionBackdrop: image.PixelMap | null = null;
  private shelfMotionBackdropHandedOff: boolean = false;
  @State shelfCoverVisible: boolean = false;
  @State shelfCoverAngle: number = SHELF_COVER_OPEN_ANGLE;
  @State shelfCoverShade: number = 0.5;
  @State shelfCoverScaleX: number = 0;
  @State shelfCoverFillImage: boolean = false;
  @State shelfCoverCropAspect: number = 0;
  @State shelfCoverFrameVisible: boolean = true;
  @State shelfOpenScaleX: number = 1;
  @State shelfOpenScaleY: number = 1;
  @State shelfOpenTranslateX: number = 0;
  @State shelfOpenTranslateY: number = 0;
  /** 书架上的书斜靠时，整页缩到封面处的同时以左上角为轴转到同样的角度（度，顺时针为正）。 */
  @State shelfOpenLean: number = 0;
  private openedWithShelfAnimation: boolean = false;
  private shelfOpeningCover: ShelfOpeningCover | null = null;
  private shelfPendingSharedCoverId: string = '';
  private shelfOpenAnimating: boolean = false;
  private shelfOpenStarted: boolean = false;
  private shelfOpenStartTimer: number = -1;
  /**
   * 上次关书那一页的图（归 ReaderOpenSnapshotStore 所有，这里不释放）：第一帧盖在正文位置、立刻开始翻开，
   * 正文就绪时比对渲染身份，相同就在下一帧撤掉（像素一致，看不出换），不同立即撤掉；最多盖 4 秒。
   */
  @State shelfOpeningPageSnapshot: image.PixelMap | null = null;
  private shelfOpeningPageSnapshotIdentity: string = '';
  private shelfOpeningPageSnapshotTimer: number = -1;
  private customizedPreferences: Set<string> = new Set<string>();

  aboutToAppear(): void {
    this.alive = true;
    const params = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.bookUrl = params?.['bookUrl'] || '';
    this.shortcutReplace = params?.['shortcutEntry'] === 'true' && params?.['shortcutReplace'] === 'true';
    // No await before this point: the first frame must already be scaled down onto the shelf cover.
    this.openedWithShelfAnimation = params?.['shelfBookOpening'] === 'true';
    this.shelfSharedCoverId = params?.['shelfSharedCoverId'] || '';
    const openingCover = AppStorage.get<ShelfOpeningCover>(SHELF_OPENING_COVER_KEY);
    this.shelfOpeningCover = this.shelfSharedCoverId && openingCover && openingCover.bookUrl === this.bookUrl ?
      openingCover : null;
    this.prepareShelfOpening();
    this.takeShelfOpeningBackdrop();
    this.takeShelfOpeningPageSnapshot();
    if (!this.shelfOpenAnimating) AppStorage.setOrCreate('shelfReaderDirectTransition', false);
    ReaderProgressCheckpoint.attach(this.owner, (): Promise<void> => this.saveProgress(), (): string => this.bookUrl);
    // 按键翻页、翻页震感按阅读类型存；直接从书架打开时普通阅读页还没读过。
    ReaderInputScopes.load(this.getUIContext().getHostContext() as Context);
    this.refreshAiAccess();
    this.open();
  }

  onPageShow(): void {
    this.visible = true;
    KnockShare.attachBook(this.owner, getContext(this), (): Book | null => this.book);
    this.activateBrightness();
    AiAccessPolicy.refresh(); this.refreshAiAccess();
    this.applySystemBars();
    this.updateTurnKeys();
    this.syncInfoClock();
    this.screenTimeout.apply(this.getUIContext().getHostContext(), true);
    if (this.ready) readStatsTracker.setReadingActive(this.bookUrl);
    this.onShortcut();
  }

  onPageHide(): void {
    KnockShare.detach(this.owner);
    this.visible = false; this.previewIndex = -1;
    this.showLayoutElements = false;
    this.showTapZones = false;
    this.brightnessSession.deactivate();
    this.turnKeys.release();
    this.keyboard.reset();
    this.syncInfoClock();
    this.screenTimeout.release(this.getUIContext().getHostContext());
    this.applySystemBars();
    readStatsTracker.setReadingActive('');
    this.flushAndSyncProgress();
  }

  aboutToDisappear(): void {
    KnockShare.detach(this.owner);
    this.flushAndSyncProgress();
    this.alive = false; this.generation++; this.searchGeneration++;
    this.showLayoutElements = false;
    this.showTapZones = false;
    this.brightnessSession.deactivate();
    this.turnKeys.release();
    this.infoClock?.stop();
    if (this.prewarmTimer >= 0) clearTimeout(this.prewarmTimer);
    this.screenTimeout.release(this.getUIContext().getHostContext());
    this.dropShelfOpeningPageSnapshot();
    const closeBackdrop = this.shelfMotionBackdrop;
    this.shelfMotionBackdrop = null;
    if (closeBackdrop && !this.shelfMotionBackdropHandedOff) closeBackdrop.release().catch((): void => {});
    this.applySystemBars();
    ReaderProgressCheckpoint.detach(this.owner);
    readStatsTracker.setReadingActive('');
  }

  onBackPress(): boolean {
    if (this.showBookmarkActions) { this.closeBookmarkActions(); return true; }
    if (this.showTapZones) { this.showTapZones = false; return true; }
    if (this.showLayoutElements) { this.showLayoutElements = false; return true; }
    if (this.activePanel) { this.setPanel(''); return true; }
    if (this.menuVisible) { this.menuVisible = false; return true; }
    this.close(); return true;
  }

  private async open(): Promise<void> {
    const token = ++this.generation;
    this.failed = false;
    try {
      if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) throw new Error('此设备暂不支持 PDF 阅读');
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('无法获取应用上下文');
      await appDb.initWithContext(context);
      let book = await appDb.getBook(this.bookUrl);
      if (!book || !LocalBookService.isPdfBook(book)) throw new Error('未找到 PDF 书籍，请重新导入');
      if (CloudAutoSync.isPlaceholder(book)) {
        this.statusText = '正在从云端下载 PDF…';
        book = await CloudAutoSync.ensureBookDownloaded(context, book);
      }
      if (LocalBookService.isWebDavBook(book)) {
        book = await WebDavBookService.ensureCached(context, book, (message: string): void => {
          if (this.alive && token === this.generation) this.statusText = message;
        });
      }
      const path = book.getVariable('localFilePath');
      if (!path || !LocalBookService.exists(path)) throw new Error('PDF 文件不存在，请重新导入或从书库重新下载');
      await LocalBookService.ensureLocalParserCurrent(context, book);
      book = await appDb.getBook(this.bookUrl);
      if (!book || !this.alive || token !== this.generation) return;
      const defaults = await ReaderPdfSettingsStore.load(context);
      this.pdfDefaults = defaults;
      this.nightMode = defaults.nightMode;
      this.pageBadge = defaults.pageBadge;
      this.syncInfoClock();
      await this.loadReaderSettings(context);
      if (!this.alive || token !== this.generation) return;
      const settings = defaults.withOverrides({
        'pdfContinuous': book.getVariable(ReaderPdfSettings.CONTINUOUS),
        'pdfDoublePage': book.getVariable(ReaderPdfSettings.DOUBLE_PAGE),
        'pdfFitPage': book.getVariable(ReaderPdfSettings.FIT_PAGE),
        'pdfSuperResolution': book.getVariable(ReaderPdfSettings.SUPER_RESOLUTION)
      });
      this.book = book; this.title = book.name || 'PDF 阅读';
      this.pageCount = book.totalChapterNum;
      this.initialPage = PdfPagePosition.clamp(book.durChapterIndex, this.pageCount);
      this.pageIndex = this.initialPage; this.jumpInput = `${this.initialPage + 1}`;
      this.continuous = settings.continuous;
      this.doublePage = settings.doublePage;
      this.fitPage = settings.fitPage;
      this.superResolution = settings.superResolution;
      const outline = await PdfBookService.outline(book);
      if (!this.alive || token !== this.generation) return;
      this.navigation.reset(outline, this.pageCount);
      this.navigationTitle = this.navigation.hasOutline() ? '目录' : '页面';
      this.navigationCount = this.navigation.totalCount();
      this.navigationIndex = this.navigation.indexForPage(this.pageIndex);
      this.tocChapters = this.buildTocChapters(book.bookUrl);
      this.sourcePath = book.getVariable('localFilePath');
      this.loadBookmarks();
    } catch (error) {
      if (this.alive && token === this.generation) this.fail(error instanceof Error ? error.message : '打开 PDF 失败');
    }
  }

  /** 直接从书架打开 PDF 时普通阅读页还没读过“使用快速亮度组件”。 */
  private async loadReaderSettings(context: Context): Promise<void> {
    try {
      const settings: ReaderSettings = await ReaderSettingsStore.load(context);
      AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_BRIGHTNESS_QUICK_ACTION, settings.useBrightnessQuickAction);
      this.applyReaderSettings(settings);
      this.keyboardSettings = await ReaderKeyboardSettingsStore.load(context);
    } catch (error) {
      console.warn('[PDF] reader settings failed:', error);
    }
    SmartControlKey.detect().catch((): void => {});
    this.updateTurnKeys();
  }

  private activateBrightness(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.brightnessReady = false;
    this.brightnessSession.activate(context, (value: number): void => {
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

  private appDark(): boolean {
    return this.darkMode;
  }

  @Builder
  layoutElementDialogContent() {
    ReaderLayoutElementSettingsPanel({
      comicMode: false,
      showReadingActions: false,
      showQuickJump: false,
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

  private documentReady(count: number, index: number): void {
    if (!this.alive || count <= 0) return;
    this.pageCount = count;
    this.pageIndex = PdfPagePosition.clamp(index, count);
    this.jumpInput = `${this.pageIndex + 1}`;
    this.navigationIndex = this.navigation.indexForPage(this.pageIndex);
    this.ready = true; this.statusText = '';
    this.settleShelfOpeningPageSnapshot();
    ReaderOpenTrace.finish(this.bookUrl, 'pdf-document-ready');
    this.applyViewSettings();
    if (this.visible) readStatsTracker.setReadingActive(this.bookUrl);
    this.scheduleSave();
  }

  /**
   * Like the comic reader, the document runs under a hidden status bar and the bar returns with the menu.
   * Layout stays full screen either way, and the safe-area heights ignore visibility, so nothing shifts.
   */
  onMenuVisibleChange(): void {
    if (!this.menuVisible) this.quickJumpUndoIndex = -1;
    this.applySystemBars();
  }

  applySystemBars(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    window.getLastWindow(context).then((mainWindow: window.Window): void => {
      // Read the state at apply time so rapid menu toggles settle on the latest one.
      const showStatus = !this.alive || !this.visible || this.menuVisible || !this.ready;
      const dark = this.darkMode;
      mainWindow.setWindowBackgroundColor(ThemeRuntime.pageColor(dark));
      mainWindow.setWindowLayoutFullScreen(true);
      applyReaderSystemBars(mainWindow, showStatus, this.alive && this.visible && this.ready && !this.menuVisible);
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
    }).catch((error: Error): void => { console.warn('[PDF] system bars failed:', error); });
  }

  private fail(message: string): void {
    this.ready = false; this.failed = true; this.statusText = message;
    readStatsTracker.setReadingActive('');
  }

  private onPage(index: number): void {
    if (!this.ready || !this.alive || !this.visible) return;
    this.pageIndex = PdfPagePosition.clamp(index, this.pageCount);
    this.jumpInput = `${this.pageIndex + 1}`;
    this.navigationIndex = this.navigation.indexForPage(this.pageIndex);
    this.scheduleSave();
    this.schedulePrewarm();
  }

  private scheduleSave(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout((): void => { this.saveTimer = -1; this.flushProgress(); }, 500);
  }

  private flushProgress(): void {
    this.saveProgress().catch((error: Error): void => { console.warn('[PDF] progress save failed:', error); });
  }

  private flushAndSyncProgress(): void {
    const context = this.getUIContext().getHostContext();
    this.saveProgress(true).then(async (): Promise<void> => {
      if (context) await CloudSyncCoordinator.syncAutomatically(context, CloudSyncCoordinator.TRIGGER_CHANGE);
    }).catch((error: Error): void => { console.warn('[PDF] progress sync failed:', error); });
  }

  // 翻页后的保存很频繁，书架页还挂在阅读页下面：每次都发 shelfUpdateTime 会让它整页重读数据库、重建卡片，
  // 正好落在下一次翻页动画里（真机上一次 20–30ms 的主线程卡顿）。和普通阅读页一样，进度照常写库，
  // 只有离开这本书时（关书、切排版、进详情、退到后台）才通知书架。
  private saveProgress(notifyShelf: boolean = false): Promise<void> {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    if (!this.ready || !this.book || !ReaderProgressCheckpoint.canWrite(this.owner)) return this.saveTask;
    const page = this.pageIndex;
    const settings = new ReaderPdfSettings();
    settings.continuous = this.continuous; settings.doublePage = this.doublePage;
    settings.fitPage = this.fitPage; settings.superResolution = this.superResolution;
    const overrides = settings.bookVariables(Array.from(this.customizedPreferences));
    const timestamp = Date.now();
    const notify = notifyShelf || this.closing;
    const bookUrl = this.bookUrl;
    const task = this.saveTask.catch((): void => {}).then(async (): Promise<void> => {
      const latest = await appDb.getBook(bookUrl);
      if (!latest || timestamp < latest.durChapterTime && latest.hasStartedReading()) return;
      // 书架“最近阅读”排序和置顶优先按 lastReadTime，和普通阅读页一样只在页码变了时刷新，
      // 打开看一眼就关的书不挪位，关书缩回时封面还在原处。
      const pageChanged = !latest.hasStartedReading() || latest.durChapterIndex !== page;
      const readTime = pageChanged || !latest.durChapterTime ? timestamp : latest.durChapterTime;
      latest.putVariable('readStarted', '1');
      if (pageChanged) latest.putVariable('lastReadTime', `${readTime}`);
      for (const key of Object.keys(overrides)) latest.putVariable(key, overrides[key]);
      latest.putVariable('readProgressChapterIndex', `${page}`);
      latest.putVariable('readProgressPageCount', '1');
      await appDb.updateBookReadingProgress(bookUrl, PdfPagePosition.title(page), page, 0, readTime, latest.variable,
        pageChanged);
      if (notify) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.reloadRecentReadCard(this.closing);
    });
    this.saveTask = task;
    return task;
  }


  /** 桌面“最近阅读”卡片跟着进度走；翻页保存很频繁，不在退出时每 30 秒最多刷一次。 */
  private reloadRecentReadCard(force: boolean): void {
    const now = Date.now();
    if (!force && now - this.recentReadCardReloadAt < 30000) return;
    this.recentReadCardReloadAt = now;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) return;
    RecentReadCardUpdater.reload(context)
      .catch((error: Error): void => { console.warn('[PDF] recent card reload failed:', error); });
  }

  /** 快速跳转松手直接跳；第一次跳走前记下原页，胶囊上的撤销键可回去。 */
  private quickJump(index: number): void {
    if (!this.ready) return;
    const target = PdfPagePosition.clamp(index, this.pageCount);
    if (target === this.pageIndex) {
      this.previewIndex = -1;
      return;
    }
    if (this.quickJumpUndoIndex < 0) this.quickJumpUndoIndex = this.pageIndex;
    this.goTo(target);
  }

  private undoQuickJump(): void {
    const target = this.quickJumpUndoIndex;
    this.quickJumpUndoIndex = -1;
    if (target >= 0 && target < this.pageCount) this.goTo(target);
  }

  private goTo(index: number): void {
    if (!this.ready) return;
    const target = PdfPagePosition.clamp(index, this.pageCount);
    this.previewIndex = -1;
    try { this.controller.goToPage(target); }
    catch (error) { console.warn('[PDF] navigation failed:', error); HdsFeedback.showToast('页码跳转失败'); }
  }

  private jump(): void {
    const page = Number(this.jumpInput);
    if (!Number.isInteger(page) || page < 1 || page > this.pageCount) {
      HdsFeedback.showToast(`请输入 1–${this.pageCount} 的页码`); return;
    }
    this.goTo(page - 1);
    this.setPanel('');
  }

  private applyViewSettings(): void {
    if (!this.ready) return;
    try {
      const page = this.pageIndex;
      this.controller.setPageContinuous(this.continuous);
      this.controller.setPageLayout(this.doublePage && this.wideWindow ?
        pdfService.PageLayout.LAYOUT_DOUBLE : pdfService.PageLayout.LAYOUT_SINGLE);
      this.controller.setPageFit(this.fitPage ? pdfService.PageFit.FIT_PAGE : pdfService.PageFit.FIT_WIDTH);
      this.controller.goToPage(page);
      this.layoutRevision++;
      this.scheduleSave();
    } catch (error) { console.warn('[PDF] view settings failed:', error); HdsFeedback.showToast('阅读布局调整失败'); }
  }

  private async search(): Promise<void> {
    if (!this.ready || this.searching || !this.searchInput.trim()) return;
    const token = ++this.searchGeneration;
    this.searching = true; this.searchCount = 0; this.searchIndex = -1; this.searchCompleted = false;
    try {
      const result = await PdfSearchTask.search(this.sourcePath, this.searchInput.trim());
      if (!this.alive || token !== this.searchGeneration) return;
      this.searchHits = result.hits; this.searchCount = result.hits.length; this.searchCompleted = true;
      if (this.searchCount > 0) { this.searchIndex = 0; this.showSearchHit(); }
      if (result.truncated) HdsFeedback.showToast('匹配结果较多，仅显示前 5000 项');
    } catch (error) { if (this.alive && token === this.searchGeneration) HdsFeedback.showToast('PDF 搜索失败'); }
    finally { if (this.alive) this.searching = false; }
  }

  refreshAiAccess(): void {
    this.superResolutionAccess = ReaderComicSuperResolution.access();
  }

  private setSuperResolution(checked: boolean): void {
    this.refreshAiAccess();
    if (checked && this.superResolutionAccess !== ReaderComicSuperResolutionAccess.READY) return;
    if (this.superResolution === checked) return;
    this.customizedPreferences.add(ReaderPdfSettings.SUPER_RESOLUTION);
    this.superResolution = checked; this.showOriginal = false; this.enhancementStatus = '';
    this.scheduleSave();
  }

  private setViewPreference(key: string, checked: boolean): void {
    if (key === ReaderPdfSettings.CONTINUOUS && this.continuous !== checked) this.continuous = checked;
    else if (key === ReaderPdfSettings.DOUBLE_PAGE && this.doublePage !== checked) this.doublePage = checked;
    else if (key === ReaderPdfSettings.FIT_PAGE && this.fitPage !== checked) this.fitPage = checked;
    else return;
    this.customizedPreferences.add(key);
    this.applyViewSettings();
  }

  private openAiAccount(): void {
    this.setPanel('');
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AccountCenter' })
      .catch((error: Error): void => { console.warn('[PDF] account page failed:', error); });
  }

  private searchNext(direction: number): void {
    if (this.searchCount <= 0 || this.searching) return;
    this.searchIndex = (this.searchIndex + direction + this.searchCount) % this.searchCount;
    this.showSearchHit();
  }

  private showSearchHit(): void {
    const hit = this.searchHits[this.searchIndex];
    if (!hit || !this.ready) return;
    try {
      const boxes: pdfService.PdfRect[] = hit.rects.map((rect: PdfSearchRect): pdfService.PdfRect => {
        const box = new pdfService.PdfRect();
        box.left = rect.left; box.top = rect.top; box.right = rect.right; box.bottom = rect.bottom;
        return box;
      });
      const rgb = Number.parseInt(ThemeRuntime.accentColor(this.darkMode).slice(-6), 16);
      this.controller.setHighlightRects([new pdfViewManager.PageRects(hit.pageIndex, boxes)], 0x55000000 + rgb);
      this.goTo(hit.pageIndex);
    } catch (error) { console.warn('[PDF] search highlight failed:', error); }
  }

  private setPanel(panel: string): void {
    if (this.activePanel === 'search' && panel !== 'search') this.invalidateSearch();
    this.previewIndex = -1;
    this.activePanel = panel;
    this.menuVisible = true;
  }

  private toggleMenu(): void {
    if (this.activePanel) { this.setPanel(''); return; }
    this.previewIndex = -1;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.menuVisible = !this.menuVisible;
    });
  }

  private invalidateSearch(): void {
    this.searchGeneration++; this.searchCount = 0; this.searchIndex = -1; this.searchCompleted = false;
    this.searchHits = [];
    try { if (this.ready) this.controller.setHighlightRects([]); } catch (_) {}
  }

  private onShortcut(): void {
    if (this.alive && this.visible && RecentReadShortcut.isPending()) {
      this.saveProgress(true).then((): Promise<boolean> => RecentReadShortcut.openPending(true))
        .catch((error: Error): void => { console.warn('[PDF] shortcut failed:', error); });
    }
  }

  private async close(): Promise<void> {
    if (this.closing) return;
    this.closing = true;
    if (this.shortcutReplace) {
      try { await this.saveProgress(); } catch (error) { console.warn('[PDF] exit save failed:', error); }
      HomeRoute.replaceWithHome(this.getUIContext().getRouter()).catch((): void => { this.getUIContext().getRouter().back(); });
      return;
    }
    // Finish an unfinished opening first so the return transition has its shared id; close the cover while saving.
    this.finishShelfOpening();
    // With the cover's current shelf position and a home-page snapshot to show behind the page (a covered router
    // page is not rendered), shrink onto the cover in one motion, the mirror of opening; otherwise close first and
    // let the shared transition shrink the page.
    const openSnapshot = this.captureReaderOpenSnapshot();
    const openSnapshotIdentity = this.readerOpenSnapshotIdentity();
    const closeTarget = this.openedWithShelfAnimation && this.shelfOpeningCover ?
      ShelfCoverLocator.locate(this.bookUrl) : null;
    const backdrop = closeTarget ? await ShelfCoverLocator.backdrop() : null;
    const selfClose = !!closeTarget && !!backdrop;
    if (selfClose) {
      this.shelfSharedCoverId = detachedShelfSharedCoverId(this.shelfSharedCoverId);
      this.shelfMotionBackdrop = backdrop;
      await ReaderRenderFrame.wait(this.getUIContext());
    }
    const coverClosed = selfClose && closeTarget ? this.closeIntoShelfCover(closeTarget) :
      this.openedWithShelfAnimation ? this.closeShelfCover() : Promise.resolve();
    try { await this.saveProgress(); }
    catch (error) { console.warn('[PDF] exit save failed:', error); }
    this.storeReaderOpenSnapshot(openSnapshot, 0, openSnapshotIdentity);
    await coverClosed;
    if (this.openedWithShelfAnimation) {
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
      AppStorage.setOrCreate('shelfBookCloseAnimationUrl', this.bookUrl);
      AppStorage.setOrCreate('shelfBookCloseAnimationNonce', Date.now());
    }
    if (selfClose) {
      // The home page shows this same snapshot on top until its own covers and progress refresh have drawn.
      this.shelfMotionBackdropHandedOff = true;
      AppStorage.setOrCreate<image.PixelMap | null>('shelfReturnBackdrop', this.shelfMotionBackdrop);
    } else {
      // The SVG frame does not scale with the shared transition; see ReaderShelfCoverOpening.showFrame.
      this.shelfCoverFrameVisible = false;
    }
    this.getUIContext().getRouter().back();
  }

  pageTransition() {
    if (this.openedWithShelfAnimation || AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionEnter({ type: RouteType.Push, duration: 0 })
      PageTransitionExit({ type: RouteType.Pop, duration: 0 })
    }
  }

  /** First frame: the whole page scaled onto the shelf cover, the cover drawn on top, no shared id yet. */
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
    this.shelfOpenLean = shelfCoverLean(cover);
    this.shelfCoverAngle = 0;
    this.shelfCoverScaleX = 1;
    this.shelfCoverShade = 0;
    this.shelfCoverFillImage = true;
    this.shelfCoverCropAspect = shelfCoverCropAspect(cover);
    this.shelfCoverVisible = true;
    this.shelfOpenAnimating = true;
  }

  /** Starts on the first vsync after the first frame is drawn (at most SHELF_COVER_OPEN_START_CAP later). */
  private startShelfOpening(): void {
    if (!this.shelfOpenAnimating || this.shelfOpenStarted || this.shelfOpenStartTimer >= 0) return;
    const begin = (): void => this.beginShelfOpening();
    this.shelfOpenStartTimer = setTimeout(begin, SHELF_COVER_OPEN_START_CAP);
    try {
      this.getUIContext().postFrameCallback(new ShelfOpeningFrameStarter(begin));
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
      duration: SHELF_COVER_OPEN_DURATION, curve: SHELF_COVER_MOTION_CURVE,
      expectedFrameRateRange: SHELF_COVER_FRAME_RATE, onFinish: (): void => this.finishShelfOpening()
    }, (): void => {
      this.shelfOpenScaleX = 1;
      this.shelfOpenScaleY = 1;
      this.shelfOpenTranslateX = 0;
      this.shelfOpenTranslateY = 0;
      this.shelfOpenLean = 0;
      this.shelfCoverAngle = SHELF_COVER_OPEN_ANGLE;
      this.shelfCoverScaleX = 0;
      this.shelfCoverShade = 0.5;
    });
  }

  private finishShelfOpening(): void {
    if (!this.shelfOpenAnimating) return;
    if (this.shelfOpenStartTimer >= 0) { clearTimeout(this.shelfOpenStartTimer); this.shelfOpenStartTimer = -1; }
    this.shelfOpenAnimating = false;
    this.dropShelfOpeningBackdrop();
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
    this.shelfOpenScaleX = 1;
    this.shelfOpenScaleY = 1;
    this.shelfOpenTranslateX = 0;
    this.shelfOpenTranslateY = 0;
    this.shelfOpenLean = 0;
    if (this.shelfCoverAngle === SHELF_COVER_OPEN_ANGLE) this.shelfCoverVisible = false;
    this.shelfCoverFillImage = false;
    if (this.shelfPendingSharedCoverId) {
      this.shelfSharedCoverId = this.shelfPendingSharedCoverId;
      this.shelfPendingSharedCoverId = '';
    }
  }

  /**
   * 取走书架点开时截的首页图，放大期间垫在整页后面（关书缩回时也用同一个位置）；
   * 没在放大（量不到封面位置、动画关闭）就直接释放。
   */
  private takeShelfOpeningBackdrop(): void {
    const backdrop = AppStorage.get<image.PixelMap | null>(SHELF_OPENING_BACKDROP_KEY) || null;
    if (!backdrop) return;
    AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_BACKDROP_KEY, null);
    if (this.shelfOpenAnimating && !this.shelfMotionBackdrop) {
      this.shelfMotionBackdrop = backdrop;
    } else {
      backdrop.release().catch((): void => {});
    }
  }

  /** 放大结束后整页已盖满窗口，撤下书架图；隔一会儿再释放，免得当前帧还在画它。 */
  private dropShelfOpeningBackdrop(): void {
    const backdrop = this.shelfMotionBackdrop;
    if (!backdrop || this.shelfMotionBackdropHandedOff) return;
    this.shelfMotionBackdrop = null;
    setTimeout((): void => { backdrop.release().catch((): void => {}); }, 120);
  }

  /** 取书架交来的上一页的图：是这本书、且确实在做翻开动画才用。 */
  private takeShelfOpeningPageSnapshot(): void {
    const pixelMap = AppStorage.get<image.PixelMap | null>(SHELF_OPENING_PAGE_SNAPSHOT_KEY) || null;
    const meta = AppStorage.get<string>(`${SHELF_OPENING_PAGE_SNAPSHOT_KEY}Meta`) || '';
    AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_PAGE_SNAPSHOT_KEY, null);
    AppStorage.setOrCreate<string>(`${SHELF_OPENING_PAGE_SNAPSHOT_KEY}Meta`, '');
    if (!pixelMap || !this.shelfOpenAnimating) return;
    const separator = meta.indexOf('\n');
    if (separator < 0 || meta.substring(0, separator) !== this.bookUrl) return;
    this.shelfOpeningPageSnapshotIdentity = meta.substring(separator + 1);
    this.shelfOpeningPageSnapshot = pixelMap;
    this.shelfOpeningPageSnapshotTimer = setTimeout((): void => {
      this.shelfOpeningPageSnapshotTimer = -1;
      this.dropShelfOpeningPageSnapshot();
    }, 4000);
  }

  /** 正文就绪：图与现在要画的一致就等这一帧画出来再撤，不一致立即撤。 */
  private settleShelfOpeningPageSnapshot(): void {
    if (!this.shelfOpeningPageSnapshot) return;
    const same = this.readerOpenSnapshotIdentity() === this.shelfOpeningPageSnapshotIdentity;
    ReaderOpenTrace.mark(this.bookUrl, 'page-snapshot-settled', same ? 'same' : 'different');
    if (!same) {
      this.dropShelfOpeningPageSnapshot();
      return;
    }
    try {
      this.getUIContext().postFrameCallback(new ShelfOpeningFrameStarter((): void => this.dropShelfOpeningPageSnapshot()));
    } catch (_) {
      this.dropShelfOpeningPageSnapshot();
    }
  }

  private dropShelfOpeningPageSnapshot(): void {
    if (this.shelfOpeningPageSnapshotTimer >= 0) {
      clearTimeout(this.shelfOpeningPageSnapshotTimer);
      this.shelfOpeningPageSnapshotTimer = -1;
    }
    this.shelfOpeningPageSnapshot = null;
    this.shelfOpeningPageSnapshotIdentity = '';
  }

  /** 这一页此刻的渲染身份：关书时随图存下，下次打开正文就绪时比对。 */
  private readerOpenSnapshotIdentity(): string {
    return `${this.pageIndex}|${this.continuous}|${this.doublePage}|${this.fitPage}|${this.wideWindow}|${this.darkMode}`;
  }

  /** 关书时把当前页整张离屏截下来（与首页截图并行），下次从书架打开先盖它。 */
  private captureReaderOpenSnapshot(): Promise<image.PixelMap | null> {
    if (!this.ready || this.failed || this.shelfOpenAnimating) return Promise.resolve(null);
    return this.getUIContext().getComponentSnapshot().get('pdf_reader_root', { scale: 1, waitUntilRenderFinished: true })
      .catch((error: Error): image.PixelMap | null => {
        console.warn('[OpenSnapshot] capture failed:', error);
        return null;
      });
  }

  /** 进度已保存后登记这张图；chapterIndex 要与保存的进度一致，书架按它判断图是否还成立。 */
  private storeReaderOpenSnapshot(capture: Promise<image.PixelMap | null>, chapterIndex: number, identity: string): void {
    const meta = new ReaderOpenSnapshotMeta();
    meta.bookUrl = this.bookUrl;
    meta.chapterIndex = chapterIndex;
    meta.identity = identity;
    meta.dark = this.darkMode;
    meta.themeRevision = AppStorage.get<number>('themeRevision') || 0;
    const context = getContext(this);
    capture.then((pixelMap: image.PixelMap | null): void => {
      if (pixelMap) ReaderOpenSnapshotStore.save(context, meta, pixelMap);
    });
  }

  /** Shrink the page onto the cover's current shelf position while the cover closes: one 500 ms motion. */
  private closeIntoShelfCover(target: ShelfOpeningCover): Promise<void> {
    this.shelfCoverVisible = true;
    this.shelfCoverFillImage = true;
    this.shelfCoverCropAspect = shelfCoverCropAspect(target);
    AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY,
      Date.now() + SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
    return new Promise<void>((resolve: () => void): void => {
      this.getUIContext().animateTo({
        duration: SHELF_COVER_OPEN_DURATION, curve: SHELF_COVER_MOTION_CURVE,
        expectedFrameRateRange: SHELF_COVER_FRAME_RATE, onFinish: resolve
      }, (): void => {
        this.shelfOpenScaleX = target.boundsWidth / target.windowWidth;
        this.shelfOpenScaleY = target.boundsHeight / target.windowHeight;
        this.shelfOpenTranslateX = target.boundsX;
        this.shelfOpenTranslateY = target.boundsY;
        this.shelfOpenLean = shelfCoverLean(target);
        this.shelfCoverAngle = 0;
        this.shelfCoverScaleX = 1;
        this.shelfCoverShade = 0;
      });
    });
  }

  /** Close the cover, then let the return transition shrink the page back onto the shelf. */
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

  // ---- 与普通阅读页拉齐的交互：点击区域、按键翻页、亮屏时间（不加界面元素） ----

  /** 普通阅读页的翻页、按键、亮屏时间设置；直接从书架打开 PDF 时普通阅读页还没读过。 */
  private applyReaderSettings(settings: ReaderSettings): void {
    this.pageTurnAnimation = ReaderPageTurnAnimation.normalize(settings.pageTurnAnimationType);
    if (settings.tapZoneActions) this.readerTapZoneActions = settings.tapZoneActions;
    this.screenTimeout.setMinutes(settings.screenTimeoutMinutes);
    this.screenTimeout.apply(this.getUIContext().getHostContext(), this.visible);
  }

  updateTurnKeys(): void {
    this.turnKeys.update(this.alive && this.visible, this.volumeTurnOn(), this.smartKeyTurnOn(),
      this.smartKeySupported, (direction: number): void => {
        if (this.canTurnByKey()) this.turn(direction);
      });
  }

  /** 菜单、面板、弹窗开着时按键不翻页，与普通阅读页一致。 */
  private canTurnByKey(): boolean {
    return this.ready && this.visible && !this.menuVisible && !this.activePanel && !this.showLayoutElements &&
      !this.showTapZones;
  }

  /** 键盘翻页：按键映射与开关在普通阅读页的阅读设置里配置。 */
  private handleKeyboardEvent(event: KeyEvent): boolean {
    const settings = this.keyboardSettings;
    const direction = event.keyCode === settings.previous ? -1 : (event.keyCode === settings.next ? 1 : 0);
    if (event.type === KeyType.Up) return this.keyboard.release(event.keyCode, event.deviceId);
    if (event.type !== KeyType.Down) return false;
    const first = this.keyboard.press(event.keyCode, event.deviceId);
    if (!settings.enabled || direction === 0 || ReaderKeyboard.hasModifiers(event)) return false;
    this.keyboard.consume(event.keyCode, event.deviceId);
    if (first && this.canTurnByKey()) this.turn(direction);
    return true;
  }

  private volumeTurnOn(): boolean {
    return ReaderInputScopes.includes(this.volumeTurnScope, ReaderInputKind.PDF);
  }

  private smartKeyTurnOn(): boolean {
    return ReaderInputScopes.includes(this.smartKeyTurnScope, ReaderInputKind.PDF);
  }

  /** 面板里的开关只改 PDF 一类；订阅由 scope 的 @Watch 重新决定。 */
  private setVolumeTurnPage(enabled: boolean): void {
    ReaderInputScopes.toggle(this.getUIContext().getHostContext() as Context, ReaderInputScopes.KEY_VOLUME_TURN,
      ReaderInputKind.PDF, enabled).catch((error: Error): void => console.error('[PDF] save volume turn failed:', error));
  }

  private setSmartKeyTurnPage(enabled: boolean): void {
    ReaderInputScopes.toggle(this.getUIContext().getHostContext() as Context, ReaderInputScopes.KEY_SMART_KEY_TURN,
      ReaderInputKind.PDF, enabled)
      .catch((error: Error): void => console.error('[PDF] save smart key turn failed:', error));
  }

  private setPageTurnAnimation(type: number): void {
    const value = ReaderPageTurnAnimation.normalize(type);
    if (value === this.pageTurnAnimation) return;
    this.pageTurnAnimation = value;
    this.turnController.invalidate();
    ReaderSettingsStore.savePageTurnAnimationType(getContext(this), value).catch((error: Error): void => {
      console.warn('[PDF] save page turn animation failed:', error);
    });
  }

  // ---- 夜间页面与页码角标：PDF 自己的全局设置（ReaderPdfSettings） ----

  private savePdfDefaults(mutate: (settings: ReaderPdfSettings) => void): void {
    const next = this.pdfDefaults.copy();
    mutate(next);
    this.pdfDefaults = next;
    ReaderPdfSettingsStore.save(getContext(this), next).catch((error: Error): void => {
      console.warn('[PDF] save defaults failed:', error);
    });
  }

  private setNightMode(mode: string): void {
    const value = ReaderPdfSettings.normalizeNightMode(mode);
    if (value === this.nightMode) return;
    this.nightMode = value;
    this.turnController.invalidate();
    this.savePdfDefaults((settings: ReaderPdfSettings): void => { settings.nightMode = value; });
  }

  private setPageBadge(enabled: boolean): void {
    if (enabled === this.pageBadge) return;
    this.pageBadge = enabled;
    this.turnController.invalidate();
    this.savePdfDefaults((settings: ReaderPdfSettings): void => { settings.pageBadge = enabled; });
    this.syncInfoClock();
  }

  /** 页码角标贴右下角，按屏幕圆角往里让，免得大圆角手机上被切掉。 */
  private pageBadgePosition(): Edges {
    const offset = ScreenCornerInset.place(this.viewWidth, 10, 10, 10);
    const edges: Edges = { right: offset.right, bottom: offset.bottom };
    return edges;
  }

  /** 应用夜间模式时交给视图的显示方式；白天一律原样。 */
  private viewNightMode(): string {
    return this.darkMode ? this.nightMode : ReaderPdfSettings.NIGHT_ORIGINAL;
  }

  /** 角标里的时间与电量每分钟刷新，只在页面可见、角标打开时走。 */
  private syncInfoClock(): void {
    if (!(this.alive && this.visible && this.pageBadge)) {
      this.infoClock?.stop();
      return;
    }
    if (!this.infoClock) {
      this.infoClock = new ReaderInfoBarClock((): void => {
        this.infoTimeText = ReaderInfoBarClock.timeText();
        this.infoBatteryPercent = ReaderInfoBarClock.batteryPercent();
      });
    }
    this.infoClock.start();
  }

  /** 角标里的目录标题：目录中当前页所在的条目，没有目录就不显示。 */
  private sectionTitle(): string {
    if (!this.navigation.hasOutline() || this.navigationCount <= 0) return '';
    return this.navigation.getData(Math.max(0, Math.min(this.navigationCount - 1, this.navigationIndex))).title;
  }

  // ---- 点击区域与翻页 ----

  private tapZoneActions(): number[] {
    const parts = (this.readerTapZoneActions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const value = Number(parts[i]);
      result.push(Number.isFinite(value) && value >= 0 && value <= 3 ? Math.round(value) : DEFAULT_TAP_ZONES[i]);
    }
    return result;
  }

  private tapZoneSummary(): string {
    const actions = this.tapZoneActions();
    const count = (action: number): number => actions.filter((value: number): boolean => value === action).length;
    return `上一页 ${count(3)} · 菜单 ${count(1)} · 下一页 ${count(2)}，与书籍共用`;
  }

  /** 点按页面：菜单开着就收起；否则按点击区域翻页或呼出菜单（九格里没有“菜单”时中间格保留菜单）。 */
  private onTapAt(x: number, y: number): void {
    this.screenTimeout.refresh(this.getUIContext().getHostContext(), this.visible);
    if (this.menuVisible || this.activePanel) {
      this.toggleMenu();
      return;
    }
    const column = Math.max(0, Math.min(2, Math.floor(Math.max(0, x) * 3)));
    const row = Math.max(0, Math.min(2, Math.floor(Math.max(0, y) * 3)));
    const zone = row * 3 + column;
    const actions = this.tapZoneActions();
    const action = zone === 4 && !actions.includes(1) ? 1 : actions[zone];
    if (action === 1) this.toggleMenu();
    else if (action === 2) this.turn(1);
    else if (action === 3) this.turn(-1);
  }

  /** 一次翻页的步长：双页并排时一次翻两页。 */
  private pageStep(): number {
    return this.doublePage && this.wideWindow ? 2 : 1;
  }

  /** 点按、按键翻页：逐页翻阅时播放与书籍相同的翻页动画；连续滚动时直接跳到相邻页。 */
  private turn(direction: number): void {
    if (!this.ready) return;
    this.screenTimeout.refresh(this.getUIContext().getHostContext(), this.visible);
    if (!this.continuous) {
      this.turnController.turn(direction > 0 ? 1 : -1);
      return;
    }
    const target = this.pageIndex + (direction > 0 ? 1 : -1) * this.pageStep();
    if (target < 0 || target >= this.pageCount) {
      HdsFeedback.showToast(direction > 0 ? '已经是最后一页' : '已经是第一页');
      return;
    }
    ReaderHaptics.pageTurned(ReaderInputKind.PDF, false);
    this.goTo(target);
  }

  private openTapZones(): void {
    this.setPanel('');
    this.menuVisible = false;
    this.showTapZones = true;
  }

  @Builder
  tapZoneDialogContent() {
    TapZoneSettingsDialogContent({
      onDone: (): void => {
        this.showTapZones = false;
      }
    })
  }

  syncTapZoneDialog(): void {
    this.tapZoneDialog.sync(this.getUIContext(), this.showTapZones, (): void => {
      this.tapZoneDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.darkMode),
      warnTag: '显示点击区域设置失败:',
      onDismiss: (): void => {
        this.showTapZones = false;
      }
    });
  }

  // ---- 翻页动画：截图翻页层（与文件排版相同的 ReaderSnapshotPageTurn） ----

  private createTurnHost(): ReaderSnapshotTurnHost {
    const host = new ReaderSnapshotTurnHost();
    host.capture = (scale: number): Promise<image.PixelMap | null> => this.capturePage(scale);
    host.textureKey = (): string => this.pageTextureKey();
    host.advance = (direction: number): Promise<boolean> => this.advanceForTurn(direction);
    host.revert = (_direction: number): Promise<void> => this.revertTurn();
    host.committed = (_direction: number): void => { this.turnUndoPage = -1; this.scheduleSave(); };
    host.activeChanged = (active: boolean): void => {
      this.turnActive = active;
      if (!active) this.schedulePrewarm();
    };
    return host;
  }

  private capturePage(scale: number): Promise<image.PixelMap | null> {
    if (!this.alive || !this.ready || this.closing) return Promise.resolve(null);
    return this.getUIContext().getComponentSnapshot()
      .get(PDF_PAGE_SURFACE_ID, { scale: scale, waitUntilRenderFinished: true })
      .catch((error: Error): image.PixelMap | null => {
        console.warn('[PDF] page snapshot failed:', error);
        return null;
      });
  }

  private pageTextureKey(): string {
    if (!this.ready) return '';
    return `${this.pageIndex}/${this.pageCount}|${this.continuous}|${this.doublePage}|${this.fitPage}|${this.wideWindow}|` +
      `${this.darkMode}|${this.viewNightMode()}|${this.superResolution}|${this.showOriginal}|${this.layoutRevision}|` +
      `${this.pageBadge}|${this.isPageBookmarked()}|${this.infoTimeText}|${this.infoBatteryPercent}`;
  }

  /** 跳到某页并等它显示出来：等页码回报，再留一点时间让新页面渲染完。 */
  private async showPageForTurn(target: number): Promise<void> {
    try {
      this.controller.goToPage(target);
    } catch (error) {
      console.warn('[PDF] turn navigation failed:', error);
      return;
    }
    const started = Date.now();
    while (this.alive && this.pageIndex !== target && Date.now() - started < PAGE_SETTLE_TIMEOUT_MS) {
      await new Promise<void>((resolve) => setTimeout(resolve, 16));
    }
    if (!this.alive) return;
    if (this.pageIndex !== target) this.onPage(target);
    await new Promise<void>((resolve) => setTimeout(resolve, PAGE_RENDER_WAIT_MS));
  }

  private async advanceForTurn(direction: number): Promise<boolean> {
    if (!this.alive || !this.ready || this.continuous) return false;
    const target = this.pageIndex + direction * this.pageStep();
    if (target < 0 || target >= this.pageCount) {
      HdsFeedback.showToast(direction > 0 ? '已经是最后一页' : '已经是第一页');
      return false;
    }
    this.turnUndoPage = this.pageIndex;
    await this.showPageForTurn(target);
    return this.alive;
  }

  private async revertTurn(): Promise<void> {
    const page = this.turnUndoPage;
    this.turnUndoPage = -1;
    if (page >= 0 && this.alive) await this.showPageForTurn(page);
  }

  private schedulePrewarm(): void {
    if (this.prewarmTimer >= 0) clearTimeout(this.prewarmTimer);
    this.prewarmTimer = setTimeout((): void => {
      this.prewarmTimer = -1;
      if (!this.alive || !this.visible || !this.ready || this.continuous || this.turnActive || this.closing) return;
      this.turnController.prewarm();
    }, 600);
  }

  // ---- 书签：与书籍同一张表，章节序号记 PDF 页码 ----

  private isPageBookmarked(): boolean {
    return this.bookmarks.some((item: Bookmark): boolean => item.chapterIndex === this.pageIndex);
  }

  private async loadBookmarks(): Promise<void> {
    try {
      const list = await appDb.getBookmarks(this.bookUrl);
      this.bookmarks = list.sort((a: Bookmark, b: Bookmark): number => a.chapterIndex - b.chapterIndex);
    } catch (error) {
      console.warn('[PDF] load bookmarks failed:', error);
    }
  }

  /** ⋯ 菜单里的“添加书签 / 移除本页书签”。 */
  private async toggleBookmark(): Promise<void> {
    if (!this.book || !this.ready) {
      HdsFeedback.showToast('当前没有可添加的阅读位置');
      return;
    }
    const page = this.pageIndex;
    const existing = this.bookmarks.filter((item: Bookmark): boolean => item.chapterIndex === page);
    try {
      if (existing.length > 0) {
        await appDb.deleteBookmarks(existing.map((item: Bookmark): number => item.id));
        await this.loadBookmarks();
        HdsFeedback.showToast('已移除本页书签');
        return;
      }
      const bookmark = new Bookmark();
      bookmark.bookUrl = this.book.bookUrl;
      bookmark.bookName = this.book.name;
      bookmark.bookAuthor = this.book.author;
      bookmark.chapterIndex = page;
      bookmark.chapterName = this.sectionTitle() || PdfPagePosition.title(page);
      bookmark.pageIndex = 0;
      bookmark.startPos = 0;
      bookmark.endPos = 0;
      bookmark.content = '';
      bookmark.createTime = Date.now();
      bookmark.id = await appDb.insertBookmark(bookmark);
      await this.loadBookmarks();
      HdsFeedback.showToast('书签已添加');
    } catch (error) {
      console.error('[PDF] toggle bookmark failed:', error);
      HdsFeedback.showToast('书签操作失败');
    }
  }

  // ---- 目录与书签：阅读页通用的目录书签面板（ReaderTocPanel），与文件排版页相同 ----

  /** 把 PDF 目录（没有目录时是每一页）转成面板的条目；下级条目用缩进表示层级。 */
  private buildTocChapters(bookUrl: string): BookChapter[] {
    const result: BookChapter[] = [];
    const count = this.navigation.totalCount();
    for (let i = 0; i < count; i++) {
      const entry = this.navigation.getData(i);
      const chapter = new BookChapter();
      chapter.bookUrl = bookUrl;
      chapter.index = i;
      chapter.url = `pdf-page:${entry.pageIndex}`;
      chapter.title = `${'　'.repeat(Math.min(entry.depth, 4))}${entry.title}`;
      result.push(chapter);
    }
    return result;
  }

  private openBookmarkActions(bookmark: Bookmark, globalX: number, globalY: number): void {
    this.bookmarkActionX = globalX;
    this.bookmarkActionY = globalY;
    this.pendingBookmark = bookmark;
    this.showBookmarkActions = true;
  }

  private closeBookmarkActions(): void {
    this.showBookmarkActions = false;
    this.pendingBookmark = null;
  }

  @Builder
  bookmarkActionMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.checkmark_circle'), '多选', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        const bookmark = this.pendingBookmark;
        this.closeBookmarkActions();
        if (bookmark) this.tocController.enterBookmarkMultiSelect(bookmark.id);
      })
      PopupMenuAction($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.darkMode), () => {
        const bookmark = this.pendingBookmark;
        this.closeBookmarkActions();
        if (bookmark) this.tocController.deleteBookmark(bookmark);
      })
    }
    .width(220)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 与普通阅读页相同的参数，从目录面板顶部的书名进入书籍详情。 */
  private async openBookDetail(): Promise<void> {
    const book = this.book;
    if (!book) return;
    try {
      await this.saveProgress(true);
      this.setPanel('');
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SearchBookDetail',
        params: {
          bookUrl: book.bookUrl, tocUrl: book.tocUrl, origin: book.origin, originName: book.originName,
          name: book.name, author: book.author, kind: book.kind, status: book.status,
          coverUrl: book.customCoverUrl || book.coverUrl, intro: book.customIntro || book.intro,
          latestChapterTitle: book.latestChapterTitle, updateTime: book.updateTime, wordCount: book.wordCount,
          type: `${book.type}`, variable: book.variable, readerBookUrl: book.bookUrl, promptAddToShelfOnBack: 'false'
        }
      });
    } catch (error) {
      console.error('[PDF] open book detail failed:', error);
      HdsFeedback.showToast('打开书籍详情失败');
    }
  }

  @Builder
  tocPanel() {
    ReaderTocPanel({
      chapters: $tocChapters,
      bookmarks: $bookmarks,
      reverseOrder: $tocReverseOrder,
      currentChapterIndex: this.navigationIndex,
      dark: this.darkMode,
      textColor: ThemeRuntime.primaryTextColor(this.darkMode),
      subTextColor: ThemeRuntime.subTextColor(this.darkMode),
      accentColor: ThemeRuntime.accentColor(this.darkMode),
      swipeButtonColor: ThemeRuntime.buttonColor(this.darkMode),
      panelColor: this.darkMode ? '#191B1F' : '#FFFFFF',
      solidPanelColor: this.darkMode ? '#191B1F' : '#FFFFFF',
      panelBorderColor: this.darkMode ? '#26FFFFFF' : '#14000000',
      panelShadowColor: this.darkMode ? '#66000000' : '#1F000000',
      selectedColor: ThemeRuntime.accentSurfaceColor(this.darkMode),
      panelWidth: PdfReaderControls.tocPanelWidth(this.viewWidth),
      panelHeight: PdfReaderControls.tocPanelHeight(this.viewHeight, this.navBarHeight > 0 ? this.navBarHeight : 8),
      book: this.book,
      controller: this.tocController,
      useDatabaseCount: false,
      chapterTitle: (index: number): string => this.tocChapters[index]?.title.trim() || PdfPagePosition.title(index),
      onClose: (): void => { this.setPanel(''); },
      onOpenBookDetail: (): void => { this.openBookDetail(); },
      onJumpToChapter: (index: number): void => {
        this.activePanel = '';
        this.menuVisible = false;
        if (this.navigationCount > 0) this.goTo(this.navigation.getData(Math.max(0, Math.min(index, this.navigationCount - 1))).pageIndex);
      },
      onJumpToBookmark: (bookmark: Bookmark): void => {
        this.activePanel = '';
        this.menuVisible = false;
        this.goTo(bookmark.chapterIndex);
      },
      onRefreshToc: (): Promise<void> => Promise.resolve(),
      onLoadBookmarks: (): void => { this.loadBookmarks(); },
      onShowBookmarkActions: (bookmark: Bookmark, globalX: number, globalY: number): void =>
        this.openBookmarkActions(bookmark, globalX, globalY)
    })
  }

  /** 已加书签的页右上角的小书签角。 */
  @Builder
  bookmarkRibbon() {
    SymbolGlyph($r('sys.symbol.bookmark_fill'))
      .fontSize(24)
      .fontColor([ThemeRuntime.accentColor(this.darkMode)])
      .position({ x: this.viewWidth - 42, y: -2 })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityText('本页已加书签')
  }

  build() {
    Stack() {
      if (this.shelfMotionBackdrop) {
        Image(this.shelfMotionBackdrop)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
      }
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.sourcePath && !this.failed) {
        // 页面层：PDF 整屏铺满，右下角页码角标、已加书签页的书签角都在这一层，截图翻页截的就是它。
        Stack({ alignContent: Alignment.TopStart }) {
          PdfReaderView({ controller: this.controller, sourcePath: this.sourcePath, initialPage: this.initialPage,
            superResolution: this.superResolution && this.superResolutionAccess === ReaderComicSuperResolutionAccess.READY,
            showOriginal: this.showOriginal, enhancementSuspended: !this.visible || this.activePanel === 'search',
            layoutRevision: this.layoutRevision, nightMode: this.viewNightMode(),
            spreadSpine: this.doublePage && this.wideWindow,
            onEnhancementStatus: (text: string): void => { this.enhancementStatus = text; this.refreshAiAccess(); },
            onReady: (count: number, page: number): void => { this.documentReady(count, page); },
            onPage: (index: number): void => { this.onPage(index); },
            onFailure: (message: string): void => { this.fail(message); },
            onTap: (): void => { this.toggleMenu(); },
            onTapAt: (x: number, y: number): void => { this.onTapAt(x, y); },
            // 逐页翻阅时横向滑动跟手翻页（PDF 自己的单页模式不响应横向滑动）；连续滚动时滑动交给 PDF 滚动。
            onTouchObserved: (event: TouchEvent): void => {
              if (!this.continuous && this.ready && !this.menuVisible && !this.activePanel) this.turnController.touch(event);
            } })
          if (this.ready && this.isPageBookmarked()) {
            this.bookmarkRibbon()
          }
          if (this.ready && this.pageBadge) {
            ReaderComicInfoBadge({
              chapterText: this.sectionTitle(),
              pageText: `${this.pageIndex + 1} / ${this.pageCount}`,
              timeText: this.infoTimeText,
              battery: this.infoBatteryPercent
            })
              .position(this.pageBadgePosition())
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeRuntime.pageColor(this.darkMode))
        .id(PDF_PAGE_SURFACE_ID)

        ReaderSnapshotPageTurn({
          host: this.turnHost,
          controller: this.turnController,
          hapticsKind: ReaderInputKind.PDF,
          animationType: this.pageTurnAnimation,
          viewWidth: this.viewWidth,
          viewHeight: this.viewHeight,
          darkMode: this.darkMode,
          paperColor: ThemeRuntime.pageColor(this.darkMode)
        })
      }
      if (!this.ready) {
        Column({ space: 16 }) {
          if (!this.failed) { LoadingProgress().width(36).height(36).color(ThemeRuntime.accentColor(this.darkMode)) }
          Text(this.statusText).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .textAlign(TextAlign.Center)
          if (this.failed) {
            Button('返回书架').backgroundColor(ThemeRuntime.accentColor(this.darkMode))
              .fontColor(ThemeRuntime.onAccentColor()).onClick((): void => { this.close(); })
          }
        }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeRuntime.pageColor(this.darkMode))
      }
      PdfReaderControls({ darkMode: this.darkMode, bookTitle: this.title,
        menuVisible: this.menuVisible || !this.ready, activePanel: this.activePanel,
        ready: this.ready, pageCount: this.pageCount, pageIndex: this.pageIndex, previewIndex: this.previewIndex,
        continuous: this.continuous, doublePage: this.doublePage, fitPage: this.fitPage, wideWindow: this.wideWindow,
        superResolution: this.superResolution, superResolutionAccess: this.superResolutionAccess,
        showOriginal: this.showOriginal, enhancementStatus: this.enhancementStatus,
        onSuperResolutionChange: (checked: boolean): void => { this.setSuperResolution(checked); },
        onOriginalChange: (): void => { this.showOriginal = !this.showOriginal; },
        onOpenMembership: (): void => { this.openAiAccount(); },
        searchInput: this.searchInput, searching: this.searching, searchCompleted: this.searchCompleted,
        searchCount: this.searchCount, searchIndex: this.searchIndex, navigationTitle: this.navigationTitle,
        navigationCount: this.navigationCount,
        navigationContent: (): void => { this.tocPanel(); },
        onClose: (): void => { this.close(); }, onPanelChange: (panel: string): void => { this.setPanel(panel); },
        onPageChange: (index: number): void => { this.goTo(index); },
        quickJumpUndoIndex: this.quickJumpUndoIndex,
        onQuickJump: (index: number): void => { this.quickJump(index); },
        onQuickJumpUndo: (): void => { this.undoQuickJump(); },
        onPreview: (index: number): void => { this.previewIndex = index; },
        onJump: (text: string): void => { this.jumpInput = text; this.jump(); },
        onContinuousChange: (checked: boolean): void => { this.setViewPreference(ReaderPdfSettings.CONTINUOUS, checked); },
        onDoublePageChange: (checked: boolean): void => { this.setViewPreference(ReaderPdfSettings.DOUBLE_PAGE, checked); },
        onFitPageChange: (checked: boolean): void => { this.setViewPreference(ReaderPdfSettings.FIT_PAGE, checked); },
        onSearchInput: (text: string): void => { this.searchInput = text; this.invalidateSearch(); },
        onSearch: (): void => { this.search(); },
        onSearchStep: (direction: number): void => { this.searchNext(direction); },
        brightnessValue: this.brightnessValue, lastManualBrightness: this.lastManualBrightness,
        brightnessReady: this.brightnessReady,
        onBrightnessChange: (value: number, persist: boolean): void => { this.setBrightness(value, persist); },
        onLayoutElements: (): void => { this.setPanel(''); this.showLayoutElements = true; },
        alignedLayout: true, pageTurnAnimation: this.pageTurnAnimation,
        tapZoneActions: this.tapZoneActions().join(','), tapZoneSummary: this.tapZoneSummary(),
        volumeTurnPage: this.volumeTurnOn(), smartKeyTurnPage: this.smartKeyTurnOn(),
        smartKeySupported: this.smartKeySupported, pdfNightMode: this.nightMode, pageBadge: this.pageBadge,
        bookmarkedPage: this.isPageBookmarked(),
        onPageTurnAnimationChange: (type: number): void => { this.setPageTurnAnimation(type); },
        onTapZones: (): void => { this.openTapZones(); },
        onVolumeTurnChange: (enabled: boolean): void => { this.setVolumeTurnPage(enabled); },
        onSmartKeyTurnChange: (enabled: boolean): void => { this.setSmartKeyTurnPage(enabled); },
        onNightModeChange: (mode: string): void => { this.setNightMode(mode); },
        onPageBadgeChange: (enabled: boolean): void => { this.setPageBadge(enabled); },
        onToggleBookmark: (): void => { this.toggleBookmark(); } })
      Column()
        .width(1)
        .height(1)
        .position({ x: this.bookmarkActionX, y: this.bookmarkActionY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showBookmarkActions, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.bookmarkActionMenu()
          }, Placement.BottomLeft, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
            if (this.showBookmarkActions) this.closeBookmarkActions();
          }))
      if (this.shelfOpeningPageSnapshot) {
        Image(this.shelfOpeningPageSnapshot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.shelfOpeningCover) {
        // Hidden rather than removed after opening: closing animates back from the open angle.
        ReaderShelfCoverOpening({ angle: this.shelfCoverAngle, shade: this.shelfCoverShade,
          scaleX: this.shelfCoverScaleX, fillImage: this.shelfCoverFillImage,
          cropAspect: this.shelfCoverCropAspect, showFrame: this.shelfCoverFrameVisible,
          cover: this.shelfOpeningCover })
          .width('100%')
          .height('100%')
          .visibility(this.shelfCoverVisible ? Visibility.Visible : Visibility.Hidden)
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').backgroundColor(ThemeRuntime.pageColor(this.darkMode))
      .id('pdf_reader_root')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scale({ x: this.shelfOpenScaleX, y: this.shelfOpenScaleY, centerX: 0, centerY: 0 })
      .translate({ x: this.shelfOpenTranslateX, y: this.shelfOpenTranslateY })
      .rotate({ angle: this.shelfOpenLean, centerX: 0, centerY: 0 })
      .sharedTransition(this.shelfSharedCoverId, {
        duration: SHELF_COVER_OPEN_DURATION, curve: Curve.EaseInOut, type: SharedTransitionEffectType.Exchange
      })
      .onAppear((): void => { this.startShelfOpening(); })
      .onKeyEvent((event: KeyEvent): boolean => this.handleKeyboardEvent(event))
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        if (!this.closing) {
          this.viewWidth = Number(after.width) || this.viewWidth;
          this.viewHeight = Number(after.height) || this.viewHeight;
        }
        // Same spread rule as the text reader (wider than tall, or near-square and ≥600vp such as an
        // unfolded foldable); very wide portrait windows keep the original 840vp allowance.
        const width = Number(after.width) || 0;
        const height = Number(after.height) || 0;
        const wide = width >= 840 || (width > 0 && height > 0 &&
          (width > height || (width >= 600 && width / height >= 0.8)));
        if (wide !== this.wideWindow) { this.wideWindow = wide; this.applyViewSettings(); }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.shelfMotionBackdrop ? ThemeRuntime.pageColor(this.darkMode) : Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
