import { pdfViewManager, pdfService } from '@kit.PDFKit';
import { common } from '@kit.AbilityKit';
import { Book } from '@legado/sourceengine';
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
import { syncDesktopTitleBar, syncSystemSafeAreas } from '../utils/SystemBars';
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
  detachedShelfSharedCoverId, shelfCoverCropAspect,
  SHELF_OPENING_BACKDROP_KEY, SHELF_OPENING_COVER_KEY, ShelfOpeningCover, ShelfOpeningFrameStarter,
  SHELF_COVER_MOTION_CURVE, SHELF_OPENING_PAGE_SNAPSHOT_KEY
} from '../components/reader/ReaderShelfCoverOpening';
import { ShelfCoverLocator } from '../utils/ShelfCoverLocator';
import { ReaderOpenSnapshotMeta, ReaderOpenSnapshotStore } from '../core/reader/ReaderOpenSnapshotStore';
import { ReaderRenderFrame } from '../core/reader/ReaderRenderFrame';
import { KnockShare } from '../utils/KnockShare';

@Entry
@Component
struct PdfReadBookPage {
  @StorageProp('appDarkMode') @Watch('applySystemBars') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('accountEntitlementsRevision') @Watch('refreshAiAccess') aiAccountRevision: number = 0;
  @StorageProp('accountMembershipSku') @Watch('refreshAiAccess') membershipSku: string = '';
  @StorageProp('aiTrialOpen') @Watch('refreshAiAccess') aiTrialOpen: boolean = false;
  @StorageLink('launchShortcutNonce') @Watch('onShortcut') shortcutNonce: number = 0;
  @State title: string = 'PDF 阅读';
  @State sourcePath: string = '';
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  @State previewIndex: number = -1;
  @State initialPage: number = 0;
  @State @Watch('applySystemBars') ready: boolean = false;
  @State statusText: string = '正在打开 PDF…';
  @State failed: boolean = false;
  @State @Watch('applySystemBars') menuVisible: boolean = false;
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
  private navigationScroller: Scroller = new Scroller();
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
    this.refreshAiAccess();
    this.open();
  }

  onPageShow(): void {
    this.visible = true;
    KnockShare.attachBook(this.owner, getContext(this), (): Book | null => this.book);
    this.activateBrightness();
    AiAccessPolicy.refresh(); this.refreshAiAccess();
    this.applySystemBars();
    if (this.ready) readStatsTracker.setReadingActive(this.bookUrl);
    this.onShortcut();
  }

  onPageHide(): void {
    KnockShare.detach(this.owner);
    this.visible = false; this.previewIndex = -1;
    this.showLayoutElements = false;
    this.brightnessSession.deactivate();
    this.applySystemBars();
    readStatsTracker.setReadingActive('');
    this.flushAndSyncProgress();
  }

  aboutToDisappear(): void {
    KnockShare.detach(this.owner);
    this.flushAndSyncProgress();
    this.alive = false; this.generation++; this.searchGeneration++;
    this.showLayoutElements = false;
    this.brightnessSession.deactivate();
    this.dropShelfOpeningPageSnapshot();
    const closeBackdrop = this.shelfMotionBackdrop;
    this.shelfMotionBackdrop = null;
    if (closeBackdrop && !this.shelfMotionBackdropHandedOff) closeBackdrop.release().catch((): void => {});
    this.applySystemBars();
    ReaderProgressCheckpoint.detach(this.owner);
    readStatsTracker.setReadingActive('');
  }

  onBackPress(): boolean {
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
      this.sourcePath = book.getVariable('localFilePath');
    } catch (error) {
      if (this.alive && token === this.generation) this.fail(error instanceof Error ? error.message : '打开 PDF 失败');
    }
  }

  /** 直接从书架打开 PDF 时普通阅读页还没读过“使用快速亮度组件”。 */
  private async loadReaderSettings(context: Context): Promise<void> {
    try {
      const settings: ReaderSettings = await ReaderSettingsStore.load(context);
      AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_BRIGHTNESS_QUICK_ACTION, settings.useBrightnessQuickAction);
    } catch (error) {
      console.warn('[PDF] reader settings failed:', error);
    }
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
  applySystemBars(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    window.getLastWindow(context).then((mainWindow: window.Window): void => {
      // Read the state at apply time so rapid menu toggles settle on the latest one.
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
    this.saveProgress().then(async (): Promise<void> => {
      if (context) await CloudSyncCoordinator.syncAutomatically(context, CloudSyncCoordinator.TRIGGER_CHANGE);
    }).catch((error: Error): void => { console.warn('[PDF] progress sync failed:', error); });
  }

  private saveProgress(): Promise<void> {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    if (!this.ready || !this.book || !ReaderProgressCheckpoint.canWrite(this.owner)) return this.saveTask;
    const page = this.pageIndex;
    const settings = new ReaderPdfSettings();
    settings.continuous = this.continuous; settings.doublePage = this.doublePage;
    settings.fitPage = this.fitPage; settings.superResolution = this.superResolution;
    const overrides = settings.bookVariables(Array.from(this.customizedPreferences));
    const timestamp = Date.now();
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
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
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

  private jumpConfirming: boolean = false;

  /** 快速跳转松手后确认，文案与小说阅读页的“确认跳转”一致；确认后提示跳到第几页。 */
  private async confirmQuickJump(index: number, percent: number): Promise<void> {
    if (!this.ready || this.jumpConfirming) return;
    const target = PdfPagePosition.clamp(index, this.pageCount);
    if (target === this.pageIndex) {
      this.previewIndex = -1;
      return;
    }
    const count = this.pageCount;
    const token = this.generation;
    this.jumpConfirming = true;
    let confirmed = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认跳转',
        message: percent >= 0 ? `跳转到全书 ${percent.toFixed(1)}%？
第 ${target + 1} 页 · 共 ${count} 页` :
          `跳转到第 ${target + 1} 页？
共 ${count} 页`,
        buttons: [
          { text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
          { text: '跳转', color: ThemeRuntime.accentColor(this.darkMode) }
        ]
      });
      confirmed = result.index === 1 && this.alive && token === this.generation && count === this.pageCount;
    } catch (error) {
      console.warn('[PDF] quick jump dialog failed:', error);
    } finally {
      this.jumpConfirming = false;
    }
    if (!confirmed) {
      this.previewIndex = -1;
      return;
    }
    this.goTo(target);
    HdsFeedback.showToast(`已跳转至第 ${target + 1} 页`);
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
      this.saveProgress().then((): Promise<boolean> => RecentReadShortcut.openPending(true))
        .catch((error: Error): void => { console.warn('[PDF] shortcut failed:', error); });
    }
  }

  private async close(): Promise<void> {
    if (this.closing) return;
    this.closing = true;
    if (this.shortcutReplace) {
      try { await this.saveProgress(); } catch (error) { console.warn('[PDF] exit save failed:', error); }
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch((): void => { this.getUIContext().getRouter().back(); });
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

  @Builder
  navigationPanel() {
    // Opens at the section containing the current page, which stays highlighted while reading.
    List({ scroller: this.navigationScroller, initialIndex: Math.max(0, this.navigationIndex - 2) }) {
      LazyForEach(this.navigation, (entry: PdfOutlineEntry, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            Text(entry.title).layoutWeight(1).fontSize(AppFontSize.BODY)
              .fontWeight(index === this.navigationIndex ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.navigationIndex ? ThemeRuntime.accentColor(this.darkMode) :
                ThemeRuntime.primaryTextColor(this.darkMode)).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.navigation.hasOutline()) {
              Text(`${entry.pageIndex + 1}`).fontSize(AppFontSize.CAPTION)
                .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            }
          }.width('100%').constraintSize({ minHeight: 48 })
            .padding({ left: 16 + Math.min(entry.depth, 8) * 12, right: 16, top: 10, bottom: 10 })
            .borderRadius(16).backgroundColor(index === this.navigationIndex ?
              ThemeRuntime.accentSurfaceColor(this.darkMode) : Color.Transparent)
            .onClick((): void => { this.setPanel(''); this.goTo(entry.pageIndex); })
        }
      }, (entry: PdfOutlineEntry): string => entry.id)
    }.width('100%').height('100%').cachedCount(4).scrollBar(BarState.Auto)
      .padding({ left: 8, right: 8, bottom: 12 })
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
        PdfReaderView({ controller: this.controller, sourcePath: this.sourcePath, initialPage: this.initialPage,
          superResolution: this.superResolution && this.superResolutionAccess === ReaderComicSuperResolutionAccess.READY,
          showOriginal: this.showOriginal, enhancementSuspended: !this.visible || this.activePanel === 'search',
          layoutRevision: this.layoutRevision,
          onEnhancementStatus: (text: string): void => { this.enhancementStatus = text; this.refreshAiAccess(); },
          onReady: (count: number, page: number): void => { this.documentReady(count, page); },
          onPage: (index: number): void => { this.onPage(index); },
          onFailure: (message: string): void => { this.fail(message); },
          onTap: (): void => { this.toggleMenu(); } })
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
        navigationContent: (): void => { this.navigationPanel(); },
        onClose: (): void => { this.close(); }, onPanelChange: (panel: string): void => { this.setPanel(panel); },
        onPageChange: (index: number): void => { this.goTo(index); },
        onQuickJump: (index: number, percent: number): void => { this.confirmQuickJump(index, percent); },
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
        onLayoutElements: (): void => { this.setPanel(''); this.showLayoutElements = true; } })
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
      .sharedTransition(this.shelfSharedCoverId, {
        duration: SHELF_COVER_OPEN_DURATION, curve: Curve.EaseInOut, type: SharedTransitionEffectType.Exchange
      })
      .onAppear((): void => { this.startShelfOpening(); })
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        const wide = Number(after.width) >= 840;
        if (wide !== this.wideWindow) { this.wideWindow = wide; this.applyViewSettings(); }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.shelfMotionBackdrop ? ThemeRuntime.pageColor(this.darkMode) : Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
