import { router, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { WebRuntimeAvailability } from '../utils/WebRuntimeAvailability';
import { HdsAnimationMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { Book, BookChapter, BookSourceStageWebRuntime } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { BookSourceAudioWebRuntimeHost } from '../components/BookSourceAudioWebRuntimeHost';
import { syncSystemSafeAreas, syncDesktopTitleBar } from '../utils/SystemBars';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderOpenTrace } from '../utils/ReaderOpenTrace';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { CloudSyncCoordinator } from '../account/CloudSyncCoordinator';
import { AudioOfflineCatalogInfo, ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { ReaderTtsPlayerPanel } from '../components/ReaderTtsPlayerPanel';
import { ReaderTtsCapsule } from '../components/reader/ReaderTtsControls';
import { TtsCatalogSheet, CatalogTitleDataSource } from '../components/TtsCatalogSheet';
import { BlankTabPage } from '../components/home/HomeTabShells';
import { BookshelfPage } from '../components/home/BookshelfPage';
import { ExplorePage } from '../components/home/ExplorePage';
import { SearchPage } from '../components/home/SearchPage';
import { SettingsPage } from '../components/home/SettingsTabPage';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

@Entry
@Component
struct Index {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 方案 B：由原生页签容器统一执行连续横移，不再叠加页面入场动画。 */
  static readonly TAB_SWITCH_DURATION: number = 320;
  private stageRuntimeController: webview.WebviewController = new webview.WebviewController();
  @State stageRuntimeMounted: boolean = true;
  private stageRuntimeResetScheduled: boolean = false;
  private stageRuntimeDisappearing: boolean = false;
  private stageRuntimeAttachRetryId: number = -1;
  private shortcutRoutingActive: boolean = false;
  private cloudSyncDebounceTimer: number = -1;
  @State @Watch('onCurrentIndexChanged') currentIndex: number = 0;
  /** 发现页第一次打开后常驻，切走只停用不销毁，回来时直接显示已加载的分类和列表。 */
  @State exploreTabMounted: boolean = false;
  /** 原生切换完成前保留出入两页，避免离场内容提前变成空白。 */
  @State homeTransitionFrom: number = -1;
  @State homeTransitionTo: number = -1;
  private homeTransitionTimer: number = -1;
  private homeTransitionStartedAt: number = 0;
  @State hdsMaterialRenderBranch: boolean = false;
  @State bookshelfMultiSelectActive: boolean = false;
  @State bookshelfActiveGroupId: number = 0;
  private immersiveTabsController: HdsTabsController = new HdsTabsController();
  private compatTabsController: TabsController = new TabsController();
  private immersiveTabBarHidden: boolean = false;
  // 每页单独保存进度，常驻的搜索/发现页不能改变当前页的底栏。
  private tabHeaderCollapseProgress: number[] = [0, 0, 0, 0];
  @State bottomBarCollapseProgress: number = 0;
  @StorageLink('themeRevision') @Watch('onThemeRevisionChanged') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('appDarkMode') @Watch('onAppDarkModeChanged') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @StorageLink('singleSourceSearchNonce') @Watch('onSingleSourceSearchRequested') singleSourceSearchNonce: number = 0;
  @StorageLink('globalSearchPendingNonce') @Watch('onGlobalSearchRequested') globalSearchPendingNonce: number = 0;
  @StorageLink('bookSourceExploreRefreshNonce') @Watch('onBookSourceExploreRefreshRequested')
  bookSourceExploreRefreshNonce: number = 0;
  @StorageLink('cloudSyncDataChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncDataRevision: number = 0;
  @StorageLink('cloudSyncPreferenceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncPreferenceRevision: number = 0;
  @StorageLink('cloudSyncApplicationPreferenceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncApplicationPreferenceRevision: number = 0;
  @StorageLink('cloudSyncBookSourceChangeRevision') @Watch('onCloudSyncDataChanged')
  cloudSyncBookSourceRevision: number = 0;
  @StorageLink('globalTtsActive') @Watch('onGlobalTtsActiveChanged') globalTtsActive: boolean = false;
  @StorageLink('globalTtsPaused') globalTtsPaused: boolean = false;
  @StorageLink('globalTtsBookName') globalTtsBookName: string = '';
  @StorageProp('globalTtsBookUrl') globalTtsBookUrl: string = '';
  @StorageLink('globalTtsCover') globalTtsCover: ResourceStr = '';
  @StorageLink('globalTtsChapterTitle') globalTtsChapterTitle: string = '';
  @StorageLink('globalTtsMode') globalTtsMode: string = '';
  @StorageLink('globalTtsPanelRequest') @Watch('onGlobalTtsPanelRequest') globalTtsPanelRequest: number = 0;
  @StorageLink('globalTtsCatalogRevision') @Watch('onGlobalTtsCatalogRevisionChanged') globalTtsCatalogRevision: number = 0;
  @StorageLink('globalTtsChapterProgress') globalTtsChapterProgress: string = '';
  @StorageLink('globalTtsBusy') globalTtsBusy: boolean = false;
  @State showGlobalTtsPanel: boolean = false;
  @State showGlobalTtsCatalog: boolean = false;
  @StorageLink('globalTtsAudioCatalogReverseOrder') @Watch('onGlobalTtsCatalogOrderChanged')
  globalTtsCatalogReverseOrder: boolean = false;
  @State globalTtsViewportWidth: number = 360;
  @State globalTtsViewportHeight: number = 720;
  @StorageLink('globalTtsCapsulePositionX') globalTtsCapsulePositionX: number = 16;
  @StorageLink('globalTtsCapsulePositionY') globalTtsCapsulePositionY: number = -1;
  private globalTtsDragOriginX: number = 0;
  private globalTtsDragOriginY: number = 0;
  private globalTtsCatalogScroller: ListScroller = new ListScroller();
  private globalTtsCatalogSource: CatalogTitleDataSource = new CatalogTitleDataSource();

  aboutToAppear() {
    this.shortcutRoutingActive = true;
    this.stageRuntimeDisappearing = false;
    this.scheduleStageRuntimeAttachFallback(0);
    BookSourceStageWebRuntime.get().setResetHandler((): void => this.resetStageRuntimeHost(),
      this.stageRuntimeController);
    hilog.info(0x0000, 'testTag', 'StartupTrace Index aboutToAppear %{public}d', Date.now());
    this.syncHomeSystemBars();
    this.openPendingShortcut();
  }

  onPageShow(): void {
    this.shortcutRoutingActive = true;
    // 从后台被桌面卡片/快捷方式唤起时，onNewWant 先于 onPageShow 写入 launchShortcutNonce，
    // 那时页面仍处于隐藏状态，@Watch 会把请求忽略掉，所以页面重新可见时要再检查一次。
    this.openPendingShortcut();
    hilog.info(0x0000, 'testTag', 'StartupTrace Index onPageShow %{public}d', Date.now());
    this.syncHomeSystemBars();
    // ReadBook is pushed over the retained Index route. Its final progress notification can arrive while the
    // bookshelf component is covered, so the storage watcher may already have been consumed before the route is
    // visible again. Publish a strictly monotonic refresh revision on page-show to force the retained shelf to
    // reload the committed Book snapshot without requiring a tab switch.
    if (this.currentIndex === 0) {
      const previousShelfUpdate = AppStorage.get<number>('shelfUpdateTime') || 0;
      AppStorage.setOrCreate('shelfUpdateTime', Math.max(Date.now(), previousShelfUpdate + 1));
    }
  }

  onAppDarkModeChanged(): void {
    this.clearHomeTabSwitch();
    this.hdsMaterialRenderBranch = !this.hdsMaterialRenderBranch;
    this.syncHomeSystemBars();
  }

  onLaunchShortcutChanged(): void {
    if (!this.shortcutRoutingActive) {
      return;
    }
    this.openPendingShortcut();
  }

  onPageHide(): void {
    this.shortcutRoutingActive = false;
  }

  aboutToDisappear(): void {
    this.clearHomeTabSwitch();
    this.stageRuntimeDisappearing = true;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    BookSourceStageWebRuntime.get().clearResetHandler(this.stageRuntimeController);
    BookSourceStageWebRuntime.get().detach(this.stageRuntimeController);
  }

  private adoptStageRuntimeController(): void {
    if (this.stageRuntimeDisappearing) return;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    BookSourceStageWebRuntime.get().attach(this.stageRuntimeController);
    BookSourceStageWebRuntime.get().setResetHandler((): void => this.resetStageRuntimeHost(),
      this.stageRuntimeController);
  }

  private scheduleStageRuntimeAttachFallback(attempt: number): void {
    if (this.stageRuntimeDisappearing) return;
    this.stageRuntimeAttachRetryId = setTimeout((): void => {
      if (this.stageRuntimeDisappearing) return;
      try {
        // A successful getWebId proves the controller is associated with a Web component. On
        // some routed/hidden Web nodes ArkWeb omits onControllerAttached — including nodes
        // rebuilt by resetStageRuntimeHost() — so treat this poll as the authoritative attach path.
        this.stageRuntimeController.getWebId();
        this.adoptStageRuntimeController();
        return;
      } catch (_) {}
      if (attempt < 100) this.scheduleStageRuntimeAttachFallback(attempt + 1);
    }, attempt === 0 ? 0 : 100);
  }

  resetStageRuntimeHost(): void {
    if (this.stageRuntimeResetScheduled) return;
    this.stageRuntimeResetScheduled = true;
    if (this.stageRuntimeAttachRetryId >= 0) clearTimeout(this.stageRuntimeAttachRetryId);
    this.stageRuntimeAttachRetryId = -1;
    const previous = this.stageRuntimeController;
    BookSourceStageWebRuntime.get().detach(previous);
    this.stageRuntimeMounted = false;
    // Let ArkUI commit the unmounted branch before constructing the replacement controller.
    setTimeout(() => {
      this.stageRuntimeController = new webview.WebviewController();
      this.stageRuntimeMounted = true;
      this.stageRuntimeResetScheduled = false;
      this.scheduleStageRuntimeAttachFallback(0);
    }, 50);
  }

  onSingleSourceSearchRequested(): void {
    const sourceUrl = AppStorage.get<string>('singleSourceSearchUrl') || '';
    if (!sourceUrl) {
      return;
    }
    this.bookshelfMultiSelectActive = false;
    this.selectHomeTab(2);
    this.syncHomeSystemBars();
  }

  onGlobalSearchRequested(): void {
    const keyword = AppStorage.get<string>('globalSearchPendingKeyword') || '';
    if (!keyword.trim()) {
      return;
    }
    this.bookshelfMultiSelectActive = false;
    this.selectHomeTab(2);
    this.syncHomeSystemBars();
  }

  onCurrentIndexChanged(): void {
    if (this.currentIndex === 1) {
      this.exploreTabMounted = true;
    }
    // 书架保留列表与滚动位置，底栏沿用该页的收起进度；只有重建的“我的”重置。
    if (this.currentIndex === 3) {
      this.tabHeaderCollapseProgress[this.currentIndex] = 0;
    }
    this.syncBottomBarCollapse(true);
  }

  onTabHeaderCollapseChange(index: number, progress: number): void {
    if (!Number.isFinite(progress)) return;
    this.tabHeaderCollapseProgress[index] = Math.max(0, Math.min(1, progress));
    if (index === this.currentIndex) {
      this.syncBottomBarCollapse();
    }
  }

  syncBottomBarCollapse(resetImmersiveState: boolean = false): void {
    this.bottomBarCollapseProgress = this.tabHeaderCollapseProgress[this.currentIndex] || 0;
    if (this.supportsImmersiveTabs()) {
      // 原生滚动动效统一控制位移、透明度和材质，不能再叠加逐帧下移/淡出。
      // 收起、展开使用不同阈值，避免在临界位置反复启动系统动画。
      const threshold = !resetImmersiveState && this.immersiveTabBarHidden ? 0.25 : 0.5;
      const hidden = this.bottomBarCollapseProgress >= threshold;
      if (!resetImmersiveState && hidden === this.immersiveTabBarHidden) return;
      this.immersiveTabBarHidden = hidden;
      if (hidden) {
        this.immersiveTabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      } else {
        this.immersiveTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      }
    } else {
      // 旧系统只移动导航栏，不改变内容区高度，避免列表跳动。
      this.compatTabsController.setTabBarTranslate({
        y: (56 + this.compatTabSafeHeight()) * this.bottomBarCollapseProgress
      });
      this.compatTabsController.setTabBarOpacity(1 - this.bottomBarCollapseProgress);
    }
  }

  onBookSourceExploreRefreshRequested(): void {
    if (this.bookSourceExploreRefreshNonce <= 0) return;
    this.bookshelfMultiSelectActive = false;
    this.selectHomeTab(1);
    this.syncHomeSystemBars();
  }

  onThemeRevisionChanged(): void {
    this.clearHomeTabSwitch();
    this.hdsMaterialRenderBranch = !this.hdsMaterialRenderBranch;
    this.syncHomeSystemBars();
  }

  onCloudSyncDataChanged(): void {
    if (this.cloudSyncDebounceTimer >= 0) {
      clearTimeout(this.cloudSyncDebounceTimer);
    }
    this.cloudSyncDebounceTimer = setTimeout(() => {
      this.cloudSyncDebounceTimer = -1;
      CloudSyncCoordinator.syncAutomatically(
        getContext(this), CloudSyncCoordinator.TRIGGER_CHANGE).catch((error: Error) => {
        console.warn('数据变更后自动同步失败:', error);
      });
    }, 15 * 1000);
  }

  onGlobalTtsActiveChanged(): void {
    if (!this.globalTtsActive) {
      this.showGlobalTtsPanel = false;
    }
  }

  onBackPress(): boolean {
    if (this.showGlobalTtsCatalog) {
      this.closeGlobalTtsCatalog();
      return true;
    }
    if (this.showGlobalTtsPanel) {
      this.closeGlobalTtsPanel();
      return true;
    }
    // 书架搜索栏开着时，返回键先清空关键词并收起它。
    if (this.currentIndex === 0 && AppStorage.get<boolean>('bookshelfSearchActive')) {
      AppStorage.setOrCreate('bookshelfSearchKeyword', '');
      AppStorage.setOrCreate('bookshelfSearchActive', false);
      return true;
    }
    if (this.currentIndex !== 0) {
      this.bookshelfMultiSelectActive = false;
      this.selectHomeTab(0);
      this.syncHomeSystemBars();
      return true;
    }
    if (this.currentIndex === 0 && this.bookshelfActiveGroupId > 0) {
      this.bookshelfActiveGroupId = 0;
      return true;
    }
    return false;
  }

  openGlobalTtsPanel(): void {
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showGlobalTtsPanel = true;
    });
  }

  /** 通知栏媒体控件点进来、首页在最上层时，直接打开这里的听书面板，不再另开一个听书页叠在上面。 */
  onGlobalTtsPanelRequest(): void {
    if (this.globalTtsPanelRequest <= 0 || !this.globalTtsActive) return;
    this.showGlobalTtsCatalog = false;
    if (!this.showGlobalTtsPanel) this.openGlobalTtsPanel();
  }

  closeGlobalTtsPanel(): void {
    this.showGlobalTtsCatalog = false;
    animateTo({ duration: 190, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsPanel = false;
    });
  }

  /**
   * 后台朗读的阅读页已离开路由栈，这里按书架直接打开的方式重新进入正文；
   * 新阅读页会作为镜像接上正在进行的朗读。
   */
  openGlobalTtsReader(): void {
    const bookUrl = AppStorage.get<string>('globalTtsBookUrl') || '';
    if (!bookUrl) {
      HdsFeedback.showToast('暂未获取到朗读中的书籍');
      return;
    }
    this.closeGlobalTtsPanel();
    ReaderOpenTrace.begin(bookUrl);
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
    ReaderOpenTrace.mark(bookUrl, 'direct-open');
    ReaderOpenTrace.mark(bookUrl, 'route-requested');
    router.pushUrl({
      url: 'pages/ReadBook',
      params: {
        bookUrl: bookUrl,
        shelfBookOpening: 'false'
      }
    }).catch((error: Error) => {
      AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
      console.error('从朗读面板回到正文失败:', error);
      ReaderOpenTrace.cancel(bookUrl, 'route-failed');
    });
  }

  openGlobalTtsCatalog(): void {
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) {
      HdsFeedback.showToast('暂未获取到听书目录');
      return;
    }
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    this.openGlobalTtsCatalogWithFreshCacheFlags();
  }

  /**
   * The shelf holds no chapter list of its own, so the cache snapshot is rebuilt
   * from the database before the sheet appears — otherwise the chips would show
   * whatever the publishing page last reported.
   */
  private openGlobalTtsCatalogWithFreshCacheFlags(): void {
    const ownerId = ReaderTtsFloatingSession.currentOwnerId();
    const bookUrl = AppStorage.get<string>('globalTtsBookUrl') || '';
    if (!ownerId || !bookUrl) {
      this.presentGlobalTtsCatalog();
      return;
    }
    // 有声书的"已下载"只看离线音频，正文缓存里的地址文本不算；由听书页重新读一次。
    const audioOffline = this.globalAudioOffline();
    if (audioOffline) {
      audioOffline.refresh().catch((error: Error) => console.warn('刷新听书目录下载标记失败:', error))
        .finally(() => this.presentGlobalTtsCatalog());
      return;
    }
    AppDatabase.getInstance().getBookChapters(bookUrl)
      .then((chapters: BookChapter[]): void => {
        ReaderTtsFloatingSession.updateCatalogCachedFlags(ownerId, this.chapterCachedFlagsOf(chapters));
        this.presentGlobalTtsCatalog();
      })
      .catch((error: Error) => {
        console.warn('刷新听书目录缓存标记失败:', error);
        this.presentGlobalTtsCatalog();
      });
  }

  private presentGlobalTtsCatalog(): void {
    animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.showGlobalTtsCatalog = true;
    });
    setTimeout(() => {
      if (!this.showGlobalTtsCatalog) return;
      try {
        this.globalTtsCatalogScroller.scrollToIndex(
          this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  /**
   * Positional, to line up with how every publisher builds the titles array
   * (`chapters.map(title)`) — the rest of the reader treats array position as the
   * canonical chapter index too.
   */
  private chapterCachedFlagsOf(chapters: BookChapter[]): boolean[] {
    const flags: boolean[] = [];
    for (let index = 0; index < chapters.length; index++) {
      flags.push(chapters[index].cacheDate > 0);
    }
    return flags;
  }

  /** 听书会话发布的离线信息；朗读会话或没有发布时为 null。读修订号是为了让界面随它刷新。 */
  globalAudioOffline(): AudioOfflineCatalogInfo | null {
    return this.globalTtsCatalogRevision >= 0 && this.globalTtsMode === 'audio' ?
      ReaderTtsFloatingSession.audioOfflineInfo() : null;
  }

  onGlobalTtsCatalogRevisionChanged(): void {
    if (!this.showGlobalTtsCatalog) return;
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) return;
    // 重载后键里带的标记变了的行才会重建，下载完成的章节马上显示"已下载"。
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
  }

  closeGlobalTtsCatalog(): void {
    animateTo({ duration: 210, curve: Curve.EaseIn }, () => {
      this.showGlobalTtsCatalog = false;
    });
  }

  onGlobalTtsCatalogOrderChanged(): void {
    const titles = ReaderTtsFloatingSession.catalogTitles();
    if (titles.length === 0) return;
    this.globalTtsCatalogSource.replace(this.globalTtsCatalogReverseOrder ? titles.slice().reverse() : titles);
    this.scrollGlobalTtsCatalogToCurrent();
  }

  selectGlobalTtsCatalog(index: number): void {
    this.closeGlobalTtsCatalog();
    ReaderTtsFloatingSession.selectCatalogIndex(this.globalTtsCatalogCanonicalIndex(index));
  }

  globalTtsCatalogCanonicalIndex(displayIndex: number): number {
    const count = ReaderTtsFloatingSession.catalogCount();
    return this.globalTtsCatalogReverseOrder ? count - 1 - displayIndex : displayIndex;
  }

  globalTtsCatalogDisplayIndex(canonicalIndex: number): number {
    const count = ReaderTtsFloatingSession.catalogCount();
    return this.globalTtsCatalogReverseOrder ? count - 1 - canonicalIndex : canonicalIndex;
  }

  toggleGlobalTtsCatalogOrder(): void {
    this.globalTtsCatalogReverseOrder = !this.globalTtsCatalogReverseOrder;
  }

  scrollGlobalTtsCatalogToCurrent(): void {
    setTimeout(() => {
      if (!this.showGlobalTtsCatalog) return;
      try {
        this.globalTtsCatalogScroller.scrollToIndex(
          this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()), false, ScrollAlign.CENTER);
      } catch (_) {}
    }, 0);
  }

  globalTtsCapsuleTransition(): TransitionEffect {
    const appear = TransitionEffect.scale({ x: 0.84, y: 0.84, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.Friction });
    const disappear = TransitionEffect.scale({ x: 0.9, y: 0.9, centerX: '50%', centerY: '50%' })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 170, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  globalTtsPanelTransition(): TransitionEffect {
    const appear = TransitionEffect.translate({ y: 52 })
      .combine(TransitionEffect.scale({ x: 0.985, y: 0.985, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 300, curve: Curve.Friction });
    const disappear = TransitionEffect.translate({ y: 28 })
      .combine(TransitionEffect.scale({ x: 0.99, y: 0.99, centerX: '50%', centerY: '100%' }))
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 190, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    try {
      await RecentReadShortcut.openPending();
    } catch (e) {
      console.error('打开最近阅读快捷项失败:', e);
    }
  }

  pageTransition() {
    if (AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionExit({ type: RouteType.Push, duration: 0 })
      PageTransitionEnter({ type: RouteType.Pop, duration: 0 })
    }
  }

  build() {
    Stack() {
      if (this.supportsImmersiveTabs()) {
        if (this.hdsMaterialRenderBranch) {
          this.immersiveTabs()
        } else {
          this.immersiveTabs()
        }
      } else {
        this.compatTabs()
      }
      if (this.globalTtsActive && !this.showGlobalTtsPanel) {
        this.globalTtsMiniPlayer()
      }
      if (this.globalTtsActive && this.showGlobalTtsPanel) {
        ReaderTtsPlayerPanel({
          sharedMotionId: 'home_tts_player',
          darkMode: this.appDarkMode,
          accentColor: this.tabBarActiveColor(),
          playButtonColor: ThemeRuntime.buttonColor(this.appDarkMode),
          primaryTextColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
          subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
          panelColor: ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'),
          backgroundThemeId: ThemeRuntime.ttsPanelThemeId(this.appDarkMode),
          topInset: this.statusBarHeight,
          bottomInset: this.navBarHeight,
          viewportHeight: this.globalTtsViewportHeight,
          onClose: () => this.closeGlobalTtsPanel(),
          onOpenCatalog: () => this.openGlobalTtsCatalog(),
          hostDownloadAvailable: this.globalAudioOffline() !== null,
          onOpenDownload: () => this.globalAudioOffline()?.openDownload(this.getUIContext()),
          showOpenReader: this.globalTtsMode !== 'audio',
          onOpenReader: () => this.openGlobalTtsReader()
        })
      }
      // 朗读目录：系统半模态，挂在 1×1 节点上。
      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet(this.globalTtsActive && this.showGlobalTtsPanel && this.showGlobalTtsCatalog,
          this.globalTtsCatalogOverlay(), this.ttsCatalogSheetOptions())
      if (this.stageRuntimeMounted && WebRuntimeAvailability.isAvailable()) {
        Web({ src: 'about:blank', controller: this.stageRuntimeController })
          .width(1)
          .height(1)
          .opacity(0.01)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            this.adoptStageRuntimeController();
          })
          .onPageBegin(() => {
            BookSourceStageWebRuntime.get().setReady(false, this.stageRuntimeController);
          })
          .onPageEnd(() => {
            BookSourceStageWebRuntime.get().setReady(true, this.stageRuntimeController);
          })
      }
      WebBookFetchRuntimeHost()
      // 书架后台下载有声书时，网页规则的音频地址要靠它解析；听书页打开时用听书页自己的。
      BookSourceAudioWebRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(width) && width > 0) this.globalTtsViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.globalTtsViewportHeight = height;
    })
  }

  @Builder
  globalTtsMiniPlayer() {
    ReaderTtsCapsule({
      sharedMotionId: 'home_tts_player',
      title: this.globalTtsBusy ? '加载中' :
        (this.globalTtsPaused ? '已暂停' : (this.globalTtsMode === 'audio' ? '听书中' : '朗读中')),
      subtitle: this.globalTtsChapterProgress || (this.globalTtsMode === 'audio' ? '后台听书' : '后台朗读'),
      paused: this.globalTtsPaused,
      playbackKey: `global_tts_capsule_playback_${this.globalTtsPaused}`,
      panelColor: ThemeRuntime.cardColor(this.appDarkMode),
      dark: this.appDarkMode,
      textColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
      subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
      accentColor: this.tabBarActiveColor(),
      onCapsuleDragStart: (): void => {
        this.globalTtsDragOriginX = this.globalTtsCapsuleLeft();
        this.globalTtsDragOriginY = this.globalTtsCapsuleTop();
      },
      onCapsuleDragMove: (offsetX: number, offsetY: number): void => {
        this.globalTtsCapsulePositionX = this.clampGlobalTtsPositionX(this.globalTtsDragOriginX + offsetX);
        this.globalTtsCapsulePositionY = this.clampGlobalTtsPositionY(this.globalTtsDragOriginY + offsetY);
      },
      onOpen: (): void => this.openGlobalTtsPanel(),
      onToggle: (): void => {
        ReaderTtsFloatingSession.toggle();
      },
      onClose: (): void => {
        this.closeGlobalTtsPanel();
        ReaderTtsFloatingSession.stop();
      }
    })
      .position({ x: 0, y: 0 })
      .translate({
        x: this.globalTtsCapsuleLeft(),
        y: this.globalTtsCapsuleTop()
      })

  }

  globalTtsCapsuleLeft(): number {
    return this.clampGlobalTtsPositionX(this.globalTtsCapsulePositionX);
  }

  globalTtsCapsuleTop(): number {
    const defaultTop = this.globalTtsViewportHeight - this.navBarHeight - 118;
    return this.clampGlobalTtsPositionY(this.globalTtsCapsulePositionY < 0 ?
      defaultTop : this.globalTtsCapsulePositionY);
  }

  clampGlobalTtsPositionX(position: number): number {
    const minLeft = 8;
    const maxLeft = Math.max(minLeft, this.globalTtsViewportWidth - ReaderTtsCapsule.WIDTH - 8);
    return Math.max(minLeft, Math.min(position, maxLeft));
  }

  clampGlobalTtsPositionY(position: number): number {
    const minTop = this.statusBarHeight + 8;
    const maxTop = Math.max(minTop, this.globalTtsViewportHeight - this.navBarHeight - 110);
    return Math.max(minTop, Math.min(position, maxTop));
  }

  @Builder
  globalTtsCatalogOverlay() {
    TtsCatalogSheet({
      bookUrl: this.globalTtsBookUrl,
      darkMode: this.appDarkMode,
      accentColor: this.tabBarActiveColor(),
      primaryTextColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
      subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
      controlIconColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
      bookName: this.globalTtsBookName,
      bookInitial: this.globalTtsCatalogInitial(),
      cover: this.globalTtsCover,
      // 听书页发布了作者就显示作者，与听书页的目录一致；朗读会话只有书名和封面，退回正在读的章节。
      bookSubtitle: this.globalAudioOffline()?.author || this.globalTtsChapterTitle,
      cachedLabel: this.globalAudioOffline()?.cachedLabel || '已缓存',
      noteText: this.globalAudioOffline()?.summary || '',
      actionLabel: this.globalAudioOffline() !== null ? '下载' : '',
      onAction: () => this.globalAudioOffline()?.openDownload(this.getUIContext()),
      onLongPress: this.globalAudioOffline() !== null ? (displayIndex: number): void => {
        this.globalAudioOffline()?.chapterAction(this.getUIContext(), this.globalTtsCatalogCanonicalIndex(displayIndex));
      } : null,
      count: ReaderTtsFloatingSession.catalogCount(),
      currentDisplayIndex: this.globalTtsCatalogDisplayIndex(ReaderTtsFloatingSession.catalogIndex()),
      reverseOrder: this.globalTtsCatalogReverseOrder,
      bottomInset: this.navBarHeight,
      viewportHeight: this.globalTtsViewportHeight,
      scroller: this.globalTtsCatalogScroller,
      source: this.globalTtsCatalogSource,
      isCached: (displayIndex: number): boolean => this.isGlobalTtsCatalogChapterCached(displayIndex),
      onToggleOrder: () => this.toggleGlobalTtsCatalogOrder(),
      onSelect: (displayIndex: number) => this.selectGlobalTtsCatalog(displayIndex),
      onClose: () => this.closeGlobalTtsCatalog()
    })
  }

  ttsCatalogSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: TtsCatalogSheet.sheetHeight(this.globalTtsViewportHeight),
      dragBar: false,
      showClose: false,
      onWillDismiss: (): void => {
        this.closeGlobalTtsCatalog();
      },
      onWillSpringBackWhenDismiss: (): void => {}
    }, this.appDarkMode, this.tabBarActiveColor());
  }

  globalTtsCatalogInitial(): string {
    const name = (this.globalTtsBookName || '书').trim();
    return name.length > 0 ? name.substring(0, 1) : '书';
  }

  isGlobalTtsCatalogChapterCached(displayIndex: number): boolean {
    return ReaderTtsFloatingSession.catalogCachedFlag(this.globalTtsCatalogCanonicalIndex(displayIndex));
  }

  prepareHomeTabSwitch(from: number, to: number): boolean {
    if (from === to || to < 0 || to > 3) return true;
    if (this.homeTransitionTo !== to || this.homeTransitionFrom !== from) {
      if (this.homeTransitionTimer >= 0) clearTimeout(this.homeTransitionTimer);
      this.homeTransitionTimer = -1;
      this.homeTransitionFrom = from;
      this.homeTransitionTo = to;
      this.homeTransitionStartedAt = Date.now();
    }
    if (to === 1) this.exploreTabMounted = true;
    return true;
  }

  homeTabIsMounted(index: number): boolean {
    // 书架从首页启动起常驻。销毁后在转场开始时重建，会先滑入空数据/加载占位，
    // 再跳成书籍列表；只延长离场保留时间无法避免返回时的这一闪烁。
    // 书籍与显示设置仍由 BookshelfPage 的 StorageLink/Watch 接收更新。
    return index === 0 || index === this.currentIndex || index === this.homeTransitionFrom ||
      index === this.homeTransitionTo;
  }

  homeTabIsActive(index: number): boolean {
    return index === (this.homeTransitionTo >= 0 ? this.homeTransitionTo : this.currentIndex);
  }

  finishHomeTabSwitch(index: number): void {
    // 快速连点时，前一次原生动画的结束通知不能覆盖最后一次选择。
    if (this.homeTransitionTo >= 0 && index !== this.homeTransitionTo) return;
    this.currentIndex = index;
    this.syncHomeSystemBars();
    if (this.homeTransitionTimer >= 0) clearTimeout(this.homeTransitionTimer);
    const remaining = Math.max(0, Index.TAB_SWITCH_DURATION - (Date.now() - this.homeTransitionStartedAt));
    this.homeTransitionTimer = setTimeout((): void => {
      this.homeTransitionTimer = -1;
      this.homeTransitionFrom = -1;
      this.homeTransitionTo = -1;
    }, remaining);
  }

  selectHomeTab(index: number): void {
    const from = this.homeTransitionTo >= 0 ? this.homeTransitionTo : this.currentIndex;
    if (index === from) return;
    this.prepareHomeTabSwitch(from, index);
    // 使用控制器保留原生切换动画；直接改 index 会跳过内容滑移。
    if (this.supportsImmersiveTabs()) this.immersiveTabsController.changeIndex(index);
    else this.compatTabsController.changeIndex(index);
  }

  clearHomeTabSwitch(): void {
    if (this.homeTransitionTimer >= 0) clearTimeout(this.homeTransitionTimer);
    this.homeTransitionTimer = -1;
    this.homeTransitionFrom = -1;
    this.homeTransitionTo = -1;
  }

  supportsImmersiveTabs(): boolean {
    return ImmersiveMaterialRuntime.supportsHdsTabs();
  }

  immersiveTabsBarBackgroundColor(): ResourceColor {
    return this.supportsImmersiveTabs() ? Color.Transparent :
      ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel');
  }

  @Builder
  immersiveTabs() {
    HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.immersiveTabsController }) {
      TabContent() {
        if (this.homeTabIsMounted(0)) {
          BookshelfPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isBookMultiSelect: $bookshelfMultiSelectActive,
            activeShelfGroupId: $bookshelfActiveGroupId,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(0, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('bookshelf'), '书架'))

      TabContent() {
        if (this.exploreTabMounted) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: this.homeTabIsActive(1),
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(1, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('explore'), '发现'))

      TabContent() {
        SearchPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.homeTabIsActive(2),
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('search'), '搜索'))

      TabContent() {
        if (this.homeTabIsMounted(3)) {
          SettingsPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(3, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .align(Alignment.TopStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.bottomTabBar(this.navigationIcon('mine'), '我的'))
    }
    .key(`home_immersive_tabs_${this.themeRevision}_${this.appDarkMode ? 'dark' : 'light'}`)
    .barBackgroundColor(this.immersiveTabsBarBackgroundColor())
    .barMode(BarMode.Fixed)
    .barHeight(this.bookshelfMultiSelectActive ? 0 : 56)
    .barOverlap(true)
    // Desktop already clips the entire window to its native outline. A second 30vp
    // content radius cuts away the header backdrop inside the smaller window corners.
    .borderRadius(deviceInfo.deviceType === '2in1' ? 0 : 30)
    .clip(true)
    .barFloatingStyle({
      systemMaterialEffect: {
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel(this.immersiveLightLevel)
      },
      barBottomMargin: this.floatingBarBottomMargin(),
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: 96
      },
      adaptToHandedness: true,
      thermoCtrl: true,
      barOpacity: this.bookshelfMultiSelectActive ? 0 : 1
    })
    .scrollable(false)
    // 主题/深浅色切换会重建 HdsTabs，新实例需要重新应用显隐状态。
    .onAppear(() => this.syncBottomBarCollapse(true))
    .animationDuration(Index.TAB_SWITCH_DURATION)
    .onContentWillChange((from: number, to: number): boolean => this.prepareHomeTabSwitch(from, to))
    .onAnimationStart((from: number, to: number): void => {
      this.prepareHomeTabSwitch(from, to);
    })
    .onChange((index: number): void => this.finishHomeTabSwitch(index))
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  compatTabs() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.compatTabsController }) {
      TabContent() {
        if (this.homeTabIsMounted(0)) {
          BookshelfPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isBookMultiSelect: $bookshelfMultiSelectActive,
            activeShelfGroupId: $bookshelfActiveGroupId,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(0, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('bookshelf'), '书架', 0))

      TabContent() {
        if (this.exploreTabMounted) {
          ExplorePage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            isActive: this.homeTabIsActive(1),
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(1, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('explore'), '发现', 1))

      TabContent() {
        SearchPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.homeTabIsActive(2),
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
      }
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('search'), '搜索', 2))

      TabContent() {
        if (this.homeTabIsMounted(3)) {
          SettingsPage({
            statusBarHeight: this.statusBarHeight,
            navBarHeight: this.navBarHeight,
            onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(3, progress)
          })
        } else {
          BlankTabPage()
        }
      }
      .height('100%')
      .align(Alignment.TopStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.compatTabBar(this.navigationIcon('mine'), '我的', 3))
    }
    .barMode(BarMode.Fixed)
    .barHeight(this.bookshelfMultiSelectActive ? 0 : 56 + this.compatTabSafeHeight())
    .barBackgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    .scrollable(false)
    .onAppear(() => this.syncBottomBarCollapse())
    .animationDuration(Index.TAB_SWITCH_DURATION)
    .onContentWillChange((from: number, to: number): boolean => this.prepareHomeTabSwitch(from, to))
    .onAnimationStart((from: number, to: number): void => {
      this.prepareHomeTabSwitch(from, to);
    })
    .onChange((index: number): void => this.finishHomeTabSwitch(index))
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  bottomTabBar(icon: Resource, title: string): BottomTabBarStyle {
    return BottomTabBarStyle.of(icon, title)
      .labelStyle({
        font: { size: 11 },
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .iconStyle({
        selectedColor: this.tabBarActiveColor(),
        unselectedColor: this.tabBarTextColor()
      })
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: 0, bottom: 0 })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center);
  }

  @Builder
  compatTabBar(icon: Resource, title: string, index: number) {
    Column() {
      Column({ space: AppSpacing.XXS }) {
        Column() {
          Image(icon)
            .width(22)
            .height(22)
            .fillColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(title)
          .fontSize(AppFontSize.MICRO)
          .lineHeight(14)
          .height(14)
          .fontColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(56 + this.compatTabSafeHeight())
    .padding({ bottom: this.compatTabSafeHeight() })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  syncHomeSystemBars(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = ThemeRuntime.pageColor(this.appDarkMode);
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
      syncDesktopTitleBar(mainWindow, this.appDarkMode);
      syncSystemSafeAreas(mainWindow);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: this.appDarkMode,
        statusBarContentColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
        navigationBarColor: '#00000000',
        isNavigationBarLightIcon: this.appDarkMode,
        navigationBarContentColor: ThemeRuntime.primaryTextColor(this.appDarkMode)
      });
    }).catch((err: Error) => {
      console.error('同步首页系统栏颜色失败:', err);
    });
  }

  tabBarActiveColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  tabBarTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  navigationIcon(tabId: string): Resource {
    return ThemeAssetRegistry.navigationIcon(ThemeRuntime.iconPackId(), tabId);
  }

  floatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  compatTabSafeHeight(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 24;
  }

}
