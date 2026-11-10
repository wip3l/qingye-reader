import { router, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { WebRuntimeAvailability } from '../utils/WebRuntimeAvailability';
import { HdsAnimationMode, HdsBarWidthRangeOptions, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import lazy { motion } from '@kit.MultimodalAwarenessKit';
import { Book, BookChapter, BookSourceStageWebRuntime } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import image from '@ohos.multimedia.image';
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
import { HomeTtsAccessory } from '../components/home/HomeTtsAccessory';
import { ReaderMaterialPanel } from '../components/reader/ReaderFloatingMaterialBar';
import { TtsCatalogSheet, CatalogTitleDataSource } from '../components/TtsCatalogSheet';
import { BlankTabPage } from '../components/home/HomeTabShells';
import { BookshelfPage } from '../components/home/BookshelfPage';
import { ExplorePage } from '../components/home/ExplorePage';
import { SearchPage } from '../components/home/SearchPage';
import { SettingsPage } from '../components/home/SettingsTabPage';
import { ListenTabPage } from '../components/home/ListenTabPage';
import { FootprintTabPage } from '../components/home/FootprintTabPage';
import { HomeTabBarSettingsStore } from '../utils/HomeTabBarSettingsStore';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

@Entry
@Component
struct Index {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('smartGripEnabled') smartGripEnabled: boolean = true;
  /** 底栏样式：floating 悬浮（系统支持 HDS 页签时）/ flat 平铺。 */
  @StorageProp('homeTabBarStyle') @Watch('onHomeTabBarStyleChanged') homeTabBarStyle: string = 'floating';
  /** 第四个页签：none / listen / footprint，放在发现和我的之间。 */
  @StorageProp('homeExtraTab') @Watch('onHomeExtraTabChanged') homeExtraTab: string = 'none';
  /** 方案 B：由原生页签容器统一执行连续横移，不再叠加页面入场动画。 */
  static readonly TAB_SWITCH_DURATION: number = 320;
  static readonly COMPAT_ACCESSORY_HEIGHT: number = 56;
  static readonly COMPAT_ACCESSORY_MARGIN: number = 12;
  /** 悬浮底栏（barHeight）高度；并成一行时伴生条和页签圆钮都用这个高度。 */
  static readonly FLOATING_TAB_BAR_HEIGHT: number = 56;
  /** 平铺底栏图标加文字那一行的高度，下面再接导航条留白。 */
  static readonly FLAT_TAB_BAR_HEIGHT: number = 50;
  static readonly ACCESSORY_HEIGHT: number = 48;
  static readonly ACCESSORY_GAP: number = 8;
  static readonly ACCESSORY_SIDE_MARGIN: number = 16;
  static readonly ACCESSORY_MAX_WIDTH: number = 480;
  static readonly TTS_SHARED_MOTION_ID: string = 'home_tts_player';
  static readonly SEARCH_LAYER_FADE_DURATION: number = 200;
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
  /** 发现页里的搜索层：点发现页搜索框或外部要求搜索时打开，取消/返回收起。 */
  @StorageLink('homeSearchActive') @Watch('onHomeSearchActiveChanged') homeSearchActive: boolean = false;
  /** 搜索层第一次打开后常驻，收起只隐藏，关键词与结果保留。 */
  @State searchLayerMounted: boolean = false;
  /** 搜索层淡出期间仍可见，淡完再隐藏，不再参与绘制。 */
  @State searchLayerFading: boolean = false;
  private searchLayerFadeTimer: number = -1;
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
  // 每页单独保存进度，常驻的发现页不能改变当前页的底栏；发现页里的搜索层另记一份。
  private tabHeaderCollapseProgress: number[] = [0, 0, 0, 0];
  private searchHeaderCollapseProgress: number = 0;
  @State bottomBarCollapseProgress: number = 0;
  @StorageLink('themeRevision') @Watch('onThemeRevisionChanged') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('appDarkMode') @Watch('onAppDarkModeChanged') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
  @StorageLink('singleSourceSearchNonce') @Watch('onSingleSourceSearchRequested') singleSourceSearchNonce: number = 0;
  @StorageLink('globalSearchPendingNonce') @Watch('onGlobalSearchRequested') globalSearchPendingNonce: number = 0;
  @StorageLink('homeTabRequestNonce') @Watch('onHomeTabRequested') homeTabRequestNonce: number = 0;
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
  /** 列表下滑后底栏藏起，伴生条落到底栏那一行、旁边留当前页签的圆钮；回到上方再分成两行。 */
  @State globalTtsBarMerged: boolean = false;
  /** 握持手：-1 左手，1 右手，0 未知（按左手）。并成一行时页签圆钮放在握持手一侧。 */
  @State globalTtsHandSide: number = 0;
  private homeHoldingHandSubscribed: boolean = false;
  private homeHoldingHandCallback: (status: motion.HoldingHandStatus) => void =
    (status: motion.HoldingHandStatus): void => this.onHomeHoldingHandChanged(status);
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
    // 冷启动时小艺等入口先写好搜索词。Tabs 还没建，控制器切页签会被忽略，直接以发现页签为初始页并打开搜索层，
    // 搜索层首次挂载时自己取走搜索词。
    if ((AppStorage.get<string>('globalSearchPendingKeyword') || '').trim()) {
      this.currentIndex = 1;
      this.exploreTabMounted = true;
      this.openHomeSearchLayer();
    }
  }

  onPageShow(): void {
    this.shortcutRoutingActive = true;
    // 从后台被桌面卡片/快捷方式唤起时，onNewWant 先于 onPageShow 写入 launchShortcutNonce，
    // 那时页面仍处于隐藏状态，@Watch 会把请求忽略掉，所以页面重新可见时要再检查一次。
    this.openPendingShortcut();
    hilog.info(0x0000, 'testTag', 'StartupTrace Index onPageShow %{public}d', Date.now());
    this.syncHomeSystemBars();
    this.syncHomeHoldingHandTracking();
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
    this.syncHomeHoldingHandTracking();
  }

  aboutToDisappear(): void {
    this.clearHomeTabSwitch();
    this.shortcutRoutingActive = false;
    this.syncHomeHoldingHandTracking();
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
    this.selectHomeTab(1);
    this.openHomeSearchLayer();
    this.syncHomeSystemBars();
  }

  onGlobalSearchRequested(): void {
    const keyword = AppStorage.get<string>('globalSearchPendingKeyword') || '';
    if (!keyword.trim()) {
      return;
    }
    this.bookshelfMultiSelectActive = false;
    this.selectHomeTab(1);
    this.openHomeSearchLayer();
    this.syncHomeSystemBars();
  }

  openHomeSearchLayer(): void {
    this.exploreTabMounted = true;
    this.searchLayerMounted = true;
    if (!this.homeSearchActive) this.homeSearchActive = true;
  }

  onHomeSearchActiveChanged(): void {
    if (this.searchLayerFadeTimer >= 0) clearTimeout(this.searchLayerFadeTimer);
    this.searchLayerFadeTimer = -1;
    if (this.homeSearchActive) {
      this.exploreTabMounted = true;
      this.searchLayerMounted = true;
      this.searchLayerFading = false;
    } else {
      this.searchLayerFading = true;
      this.searchLayerFadeTimer = setTimeout((): void => {
        this.searchLayerFadeTimer = -1;
        this.searchLayerFading = false;
      }, Index.SEARCH_LAYER_FADE_DURATION);
    }
    try {
      // 冷启动时 aboutToAppear 里就会打开搜索层，那时底栏还没建好；建好后 onAppear 会再同步一次。
      this.syncBottomBarCollapse(true);
    } catch (e) {
    }
  }

  homeSearchLayerActive(): boolean {
    return this.homeSearchActive && this.homeTabIsActive(1);
  }

  /** 书架多选和发现页的搜索层都是整页，底栏收起。 */
  homeTabBarHidden(): boolean {
    return this.bookshelfMultiSelectActive || this.homeSearchLayerActive();
  }

  onSearchHeaderCollapseChange(progress: number): void {
    if (!Number.isFinite(progress)) return;
    this.searchHeaderCollapseProgress = Math.max(0, Math.min(1, progress));
    if (this.currentIndex === 1 && this.homeSearchActive) {
      this.syncBottomBarCollapse();
    }
  }

  /** 其他页面（如使用说明里的“去搜索”）退回首页时要求切到指定页签。 */
  onHomeTabRequested(): void {
    const requested = AppStorage.get<number>('homeTabRequestIndex') ?? -1;
    if (requested < 0 || requested > 2) {
      return;
    }
    // 请求方按书架/发现/我的三个页签编号，“我的”在有第四个页签时顺延。
    const index = requested === 2 ? this.mineTabIndex() : requested;
    this.bookshelfMultiSelectActive = false;
    this.selectHomeTab(index);
    this.syncHomeSystemBars();
  }

  onCurrentIndexChanged(): void {
    if (this.currentIndex === 1) {
      this.exploreTabMounted = true;
    }
    // 书架保留列表与滚动位置，底栏沿用该页的收起进度；重建的第四个页签和“我的”重置。
    if (this.currentIndex >= 2) {
      this.tabHeaderCollapseProgress[this.currentIndex] = 0;
    }
    this.syncBottomBarCollapse(true);
  }

  onTabHeaderCollapseChange(index: number, progress: number): void {
    if (!Number.isFinite(progress)) return;
    this.tabHeaderCollapseProgress[index] = Math.max(0, Math.min(1, progress));
    if (index === this.currentIndex && !(index === 1 && this.homeSearchActive)) {
      this.syncBottomBarCollapse();
    }
  }

  syncBottomBarCollapse(resetImmersiveState: boolean = false): void {
    this.bottomBarCollapseProgress = this.currentIndex === 1 && this.homeSearchActive ?
      this.searchHeaderCollapseProgress : (this.tabHeaderCollapseProgress[this.currentIndex] || 0);
    if (this.useFloatingTabs()) {
      // 原生滚动动效统一控制位移、透明度和材质，不能再叠加逐帧下移/淡出。
      // 收起、展开使用不同阈值，避免在临界位置反复启动系统动画。
      const threshold = !resetImmersiveState && this.immersiveTabBarHidden ? 0.25 : 0.5;
      const hidden = this.bottomBarCollapseProgress >= threshold;
      if (!resetImmersiveState && hidden === this.immersiveTabBarHidden) return;
      this.immersiveTabBarHidden = hidden;
      // 有伴生条时底栏照样藏起，伴生条落到底栏那一行，旁边留一个当前页签的圆钮。
      this.setGlobalTtsBarMerged(hidden && this.globalTtsActive);
      if (hidden) {
        this.immersiveTabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      } else {
        this.immersiveTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      }
    } else {
      // 平铺底栏固定显示，列表滚动时不收起。
      this.bottomBarCollapseProgress = 0;
      this.compatTabsController.setTabBarTranslate({ y: 0 });
      this.compatTabsController.setTabBarOpacity(1);
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
    // 伴生条出现或消失时重新套用底栏宽度和收起状态。
    this.syncBottomBarCollapse(true);
    this.syncHomeHoldingHandTracking();
  }

  private syncHomeHoldingHandTracking(): void {
    const wanted = this.smartGripEnabled && this.shortcutRoutingActive && this.globalTtsActive &&
      this.useFloatingTabs() && canIUse('SystemCapability.MultimodalAwareness.Motion');
    if (wanted === this.homeHoldingHandSubscribed) return;
    try {
      if (wanted) {
        this.homeHoldingHandSubscribed = true;
        motion.on('holdingHandChanged', this.homeHoldingHandCallback);
      } else {
        this.homeHoldingHandSubscribed = false;
        // 只取消首页的回调，阅读页自己的订阅不受影响。
        motion.off('holdingHandChanged', this.homeHoldingHandCallback);
      }
    } catch (error) {
      this.homeHoldingHandSubscribed = false;
      console.warn('首页握姿感知不可用，页签圆钮保持在左侧:', error);
    }
  }

  private onHomeHoldingHandChanged(status: motion.HoldingHandStatus): void {
    if (!this.homeHoldingHandSubscribed) return;
    // 双手、未握持和未知都保留上次位置，放下手机时不来回跳。
    if (status !== motion.HoldingHandStatus.LEFT_HAND_HELD &&
      status !== motion.HoldingHandStatus.RIGHT_HAND_HELD) return;
    const side = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? -1 : 1;
    if (side === this.globalTtsHandSide) return;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
      this.globalTtsHandSide = side;
    });
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
    // 发现页的搜索层开着时，返回键先收起它回到发现内容。
    if (this.currentIndex === 1 && this.homeSearchActive) {
      this.homeSearchActive = false;
      return true;
    }
    // 发现页“榜单总览”点进了某个榜单时，返回键先回到总览。
    if (this.currentIndex === 1 && AppStorage.get<boolean>('exploreOverviewDrillActive') &&
      AppStorage.get<string>('exploreResultLayout') === 'overview') {
      AppStorage.setOrCreate('exploreOverviewDrillActive', false);
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
    if (this.currentIndex === 0 &&
      (this.bookshelfActiveGroupId > 0 || AppStorage.get<boolean>('bookshelfGroupTransitionActive'))) {
      AppStorage.setOrCreate('bookshelfGroupBackRequest',
        (AppStorage.get<number>('bookshelfGroupBackRequest') || 0) + 1);
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

  // 阅读页关闭动画结束时交来的书架截图：重新显示的首页头几帧封面图还没加载，随后进度刷新又会重建卡片，
  // 这段时间把截图盖在最上层，刷新画出来后揭开；兜底最多盖 1.5 秒。
  @StorageLink('shelfReturnBackdrop') @Watch('onShelfReturnBackdropChanged') shelfReturnBackdrop: image.PixelMap | null = null;
  @StorageLink('shelfReturnRefreshNonce') @Watch('onShelfReturnRefreshed') shelfReturnRefreshNonce: number = 0;
  @State shelfReturnBackdropShown: boolean = false;
  private shelfReturnBackdropTimer: number = -1;

  onShelfReturnBackdropChanged(): void {
    if (!this.shelfReturnBackdrop) {
      this.shelfReturnBackdropShown = false;
      return;
    }
    this.shelfReturnBackdropShown = true;
    this.armShelfReturnBackdropDrop(1500);
  }

  onShelfReturnRefreshed(): void {
    // 刷新后的书架再给两帧把封面画出来。
    if (this.shelfReturnBackdropShown) this.armShelfReturnBackdropDrop(120);
  }

  private armShelfReturnBackdropDrop(delayMs: number): void {
    if (this.shelfReturnBackdropTimer >= 0) clearTimeout(this.shelfReturnBackdropTimer);
    this.shelfReturnBackdropTimer = setTimeout((): void => {
      this.shelfReturnBackdropTimer = -1;
      this.dropShelfReturnBackdropNow();
    }, delayMs);
  }

  /**
   * 手指一按下就揭开：截图不拦触摸，底下的分类 Swiper 会照常响应滑动，但画面还是静止的截图，
   * 揭开时已经切完，用户看到的就是"切换动画丢了"。按下即揭开，宁可偶尔看到一两帧封面重载。
   */
  private dropShelfReturnBackdropNow(): void {
    if (this.shelfReturnBackdropTimer >= 0) {
      clearTimeout(this.shelfReturnBackdropTimer);
      this.shelfReturnBackdropTimer = -1;
    }
    const backdrop = this.shelfReturnBackdrop;
    if (!this.shelfReturnBackdropShown && !backdrop) return;
    this.shelfReturnBackdropShown = false;
    this.shelfReturnBackdrop = null;
    // 这一帧可能还在画它，晚一点再释放。
    if (backdrop) setTimeout((): void => { backdrop.release().catch((): void => {}); }, 200);
  }

  pageTransition() {
    if (AppStorage.get<boolean>('shelfReaderDirectTransition') === true) {
      PageTransitionExit({ type: RouteType.Push, duration: 0 })
      PageTransitionEnter({ type: RouteType.Pop, duration: 0 })
    }
  }

  build() {
    Stack() {
      if (this.useFloatingTabs()) {
        if (this.hdsMaterialRenderBranch) {
          this.immersiveTabs()
        } else {
          this.immersiveTabs()
        }
      } else {
        this.compatTabs()
      }
      if (this.globalTtsActive && !this.homeTabBarHidden()) {
        if (this.useFloatingTabs()) {
          this.globalTtsFloatingAccessory()
        } else {
          this.globalTtsCompatAccessory()
        }
      }
      if (this.globalTtsActive && this.showGlobalTtsPanel) {
        ReaderTtsPlayerPanel({
          sharedMotionId: Index.TTS_SHARED_MOTION_ID,
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
      if (this.shelfReturnBackdropShown && this.shelfReturnBackdrop) {
        Image(this.shelfReturnBackdrop)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .hitTestBehavior(HitTestMode.None)
      }
    }
    // 阅读页关闭动画会对首页整张离屏截图垫在自己后面（见 ShelfCoverLocator）。
    .id('home_root')
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.shelfReturnBackdropShown) this.dropShelfReturnBackdropNow();
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(width) && width > 0) this.globalTtsViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.globalTtsViewportHeight = height;
    })
  }

  /**
   * 伴生条本体。面板打开时移除，和面板的 geometryTransition 成对完成一镜到底；悬浮底栏与旧底栏共用。
   * 位置和宽高必须在这里直接读状态：@Builder 按值传入的数字在状态变化后不会刷新。
   */
  @Builder
  globalTtsAccessory() {
    if (!this.showGlobalTtsPanel) {
      Column() {
        ReaderMaterialPanel({
          panelWidth: this.globalTtsAccessoryWidth(),
          panelHeight: this.globalTtsAccessoryHeight(),
          cornerRadius: this.globalTtsAccessoryHeight() / 2,
          darkMode: this.appDarkMode,
          fallbackColor: ThemeRuntime.cardColor(this.appDarkMode)
        }) {
          HomeTtsAccessory({
            accentColor: this.tabBarActiveColor(),
            textColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
            subTextColor: ThemeRuntime.subTextColor(this.appDarkMode),
            trackColor: ThemeRuntime.hairlineColor(this.appDarkMode),
            onOpen: (): void => this.openGlobalTtsPanel()
          })
        }
      }
      .width(this.globalTtsAccessoryWidth())
      .height(this.globalTtsAccessoryHeight())
      .borderRadius(this.globalTtsAccessoryHeight() / 2)
      .position({ x: this.globalTtsAccessoryLeft(), y: this.globalTtsAccessoryTop() })
      .geometryTransition(Index.TTS_SHARED_MOTION_ID)
      .transition(TransitionEffect.opacity(0.99))
    }
  }

  /** 悬浮底栏：平时贴在底栏正上方、与底栏同宽；并成一行时落到底栏那一行，旁边是当前页签圆钮。 */
  @Builder
  globalTtsFloatingAccessory() {
    if (this.globalTtsBarMerged) {
      Column() {
        ReaderMaterialPanel({
          panelWidth: Index.FLOATING_TAB_BAR_HEIGHT,
          panelHeight: Index.FLOATING_TAB_BAR_HEIGHT,
          cornerRadius: Index.FLOATING_TAB_BAR_HEIGHT / 2,
          darkMode: this.appDarkMode,
          fallbackColor: ThemeRuntime.cardColor(this.appDarkMode)
        }) {
          Stack({ alignContent: Alignment.Center }) {
            Image(this.navigationIcon(this.currentHomeTabId(), this.currentIndex))
              .width(this.navigationHidesLabels() ? 30 : 26)
              .height(this.navigationHidesLabels() ? 30 : 26)
              .fillColor(this.tabBarActiveColor())
              .draggable(false)
          }
          .width(Index.FLOATING_TAB_BAR_HEIGHT)
          .height(Index.FLOATING_TAB_BAR_HEIGHT)
          // 点击要挂在材质里面：材质底板是一个单页签 Tabs，挂在外层会被它的页签栏接走。
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
          .accessibilityText('展开底栏')
          .onClick(() => this.expandHomeTabBarFromMerged())
        }
      }
      .width(Index.FLOATING_TAB_BAR_HEIGHT)
      .height(Index.FLOATING_TAB_BAR_HEIGHT)
      .borderRadius(Index.FLOATING_TAB_BAR_HEIGHT / 2)
      .position({ x: this.globalTtsTabButtonLeft(), y: this.globalTtsTabBarTop() })
      .transition(TransitionEffect.scale({ x: 0.6, y: 0.6 }).combine(TransitionEffect.opacity(0)))
    }
    this.globalTtsAccessory()
  }

  /** 平铺底栏：贴在底栏正上方、左右与底栏对齐；底栏不收起，伴生条也不动。 */
  @Builder
  globalTtsCompatAccessory() {
    Stack() {
      this.globalTtsAccessory()
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  compatTabBarHeight(): number {
    return Index.FLAT_TAB_BAR_HEIGHT + this.compatTabSafeHeight();
  }

  currentHomeTabId(): string {
    return this.homeTabIdAt(this.currentIndex);
  }

  homeTabIdAt(index: number): string {
    if (index === 1) return 'explore';
    if (index === this.mineTabIndex()) return 'mine';
    if (index === 2) return this.extraTabId();
    return 'bookshelf';
  }

  /** 有伴生条时底栏和伴生条用同一个宽度，左右对齐。 */
  globalTtsRowWidth(): number {
    return Math.max(0, Math.min(Index.ACCESSORY_MAX_WIDTH,
      this.globalTtsViewportWidth - Index.ACCESSORY_SIDE_MARGIN * 2));
  }

  globalTtsRowLeft(): number {
    return (this.globalTtsViewportWidth - this.globalTtsRowWidth()) / 2;
  }

  globalTtsTabBarWidth(): HdsBarWidthRangeOptions | undefined {
    if (!this.globalTtsActive || this.homeTabBarHidden()) return undefined;
    const width = this.globalTtsRowWidth();
    const options: HdsBarWidthRangeOptions = { smallWidth: width, mediumWidth: width, largeWidth: width };
    return options;
  }

  globalTtsTabBarTop(): number {
    return this.globalTtsViewportHeight - this.floatingBarBottomMargin() - Index.FLOATING_TAB_BAR_HEIGHT;
  }

  globalTtsAccessoryWidth(): number {
    if (!this.useFloatingTabs()) {
      return Math.max(0, this.globalTtsViewportWidth - Index.COMPAT_ACCESSORY_MARGIN * 2);
    }
    return this.globalTtsBarMerged ?
      Math.max(0, this.globalTtsRowWidth() - Index.FLOATING_TAB_BAR_HEIGHT - Index.ACCESSORY_GAP) :
      this.globalTtsRowWidth();
  }

  globalTtsAccessoryHeight(): number {
    if (!this.useFloatingTabs()) return Index.COMPAT_ACCESSORY_HEIGHT;
    return this.globalTtsBarMerged ? Index.FLOATING_TAB_BAR_HEIGHT : Index.ACCESSORY_HEIGHT;
  }

  globalTtsAccessoryLeft(): number {
    if (!this.useFloatingTabs()) return Index.COMPAT_ACCESSORY_MARGIN;
    if (this.globalTtsBarMerged && this.globalTtsHandSide <= 0) {
      return this.globalTtsRowLeft() + Index.FLOATING_TAB_BAR_HEIGHT + Index.ACCESSORY_GAP;
    }
    return this.globalTtsRowLeft();
  }

  globalTtsAccessoryTop(): number {
    if (!this.useFloatingTabs()) {
      return this.globalTtsViewportHeight - this.compatTabBarHeight() - Index.COMPAT_ACCESSORY_HEIGHT -
        Index.COMPAT_ACCESSORY_MARGIN;
    }
    return this.globalTtsBarMerged ? this.globalTtsTabBarTop() :
      this.globalTtsTabBarTop() - Index.ACCESSORY_GAP - Index.ACCESSORY_HEIGHT;
  }

  globalTtsTabButtonLeft(): number {
    return this.globalTtsHandSide > 0 ?
      this.globalTtsRowLeft() + this.globalTtsRowWidth() - Index.FLOATING_TAB_BAR_HEIGHT : this.globalTtsRowLeft();
  }

  setGlobalTtsBarMerged(merged: boolean): void {
    if (merged === this.globalTtsBarMerged) return;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
      this.globalTtsBarMerged = merged;
    });
  }

  /** 点并成一行时的页签圆钮：放出底栏、伴生条回到上方，下次滚过阈值再收。 */
  expandHomeTabBarFromMerged(): void {
    this.immersiveTabBarHidden = false;
    this.immersiveTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    this.setGlobalTtsBarMerged(false);
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
    if (from === to || to < 0 || to > this.mineTabIndex()) return true;
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
    if (this.useFloatingTabs()) this.immersiveTabsController.changeIndex(index);
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

  /** 悬浮底栏要系统支持；用户选了平铺或系统不支持时走平铺底栏。 */
  useFloatingTabs(): boolean {
    return this.supportsImmersiveTabs() && this.homeTabBarStyle !== HomeTabBarSettingsStore.STYLE_FLAT;
  }

  extraTabId(): string {
    return HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab) === HomeTabBarSettingsStore.EXTRA_NONE ? '' :
      this.homeExtraTab;
  }

  /** 有第四个页签时它占 2，“我的”顺延到 3。 */
  mineTabIndex(): number {
    return this.extraTabId() ? 3 : 2;
  }

  onHomeTabBarStyleChanged(): void {
    this.clearHomeTabSwitch();
    this.immersiveTabBarHidden = false;
    this.globalTtsBarMerged = false;
    this.syncHomeHoldingHandTracking();
  }

  /** 一般是在“我的 › 其他设置”里改的，回到首页时仍停在“我的”。 */
  onHomeExtraTabChanged(): void {
    this.clearHomeTabSwitch();
    if (this.currentIndex >= 2) {
      this.currentIndex = this.mineTabIndex();
    }
    this.tabHeaderCollapseProgress = [this.tabHeaderCollapseProgress[0], this.tabHeaderCollapseProgress[1], 0, 0];
  }

  immersiveTabsBarBackgroundColor(): ResourceColor {
    return this.useFloatingTabs() ? Color.Transparent :
      ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel');
  }

  /** 发现页签：发现内容常驻，搜索层盖在上面，收起时只隐藏。 */
  @Builder
  exploreTabContent() {
    Stack() {
      if (this.exploreTabMounted) {
        ExplorePage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.homeTabIsActive(1) && !this.homeSearchActive,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(1, progress)
        })
      } else {
        BlankTabPage()
      }
      if (this.searchLayerMounted) {
        SearchPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          isActive: this.homeSearchLayerActive(),
          onHeaderCollapseChange: (progress: number) => this.onSearchHeaderCollapseChange(progress)
        })
          .opacity(this.homeSearchActive ? 1 : 0)
          .animation({ duration: Index.SEARCH_LAYER_FADE_DURATION, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(this.homeSearchActive ? HitTestMode.Default : HitTestMode.None)
          .visibility(this.homeSearchActive || this.searchLayerFading ? Visibility.Visible : Visibility.Hidden)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 第四个页签（听/足迹）：和“我的”一样只在显示时挂载。 */
  @Builder
  extraTabContent() {
    if (this.homeTabIsMounted(2)) {
      if (this.extraTabId() === HomeTabBarSettingsStore.EXTRA_LISTEN) {
        ListenTabPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
      } else {
        FootprintTabPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(2, progress)
        })
      }
    } else {
      BlankTabPage()
    }
  }

  extraTabTitle(): string {
    return this.extraTabId() === HomeTabBarSettingsStore.EXTRA_LISTEN ? '听' : '足迹';
  }

  /** 底栏页签顺序：书架、发现、[听/足迹]、我的。 */
  homeTabIds(): string[] {
    const extra = this.extraTabId();
    return extra ? ['bookshelf', 'explore', extra, 'mine'] : ['bookshelf', 'explore', 'mine'];
  }

  homeTabTitle(tabId: string): string {
    if (tabId === 'bookshelf') return '书架';
    if (tabId === 'explore') return '发现';
    if (tabId === 'mine') return '我的';
    return this.extraTabTitle();
  }

  @Builder
  homeTabBody(tabId: string) {
    if (tabId === 'bookshelf') {
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
    } else if (tabId === 'explore') {
      this.exploreTabContent()
    } else if (tabId === 'mine') {
      if (this.homeTabIsMounted(this.mineTabIndex())) {
        SettingsPage({
          statusBarHeight: this.statusBarHeight,
          navBarHeight: this.navBarHeight,
          onHeaderCollapseChange: (progress: number) => this.onTabHeaderCollapseChange(this.mineTabIndex(), progress)
        })
      } else {
        BlankTabPage()
      }
    } else {
      this.extraTabContent()
    }
  }

  @Builder
  immersiveTabs() {
    HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.immersiveTabsController }) {
      // 页签用 ForEach 按列表生成：三页签时若在“我的”前面留一个空的 if 分支，
      // 系统更新页签栏项时会错位一格，选中态图标和文字颜色对不上。
      ForEach(this.homeTabIds(), (tabId: string, index: number) => {
        TabContent() {
          this.homeTabBody(tabId)
        }
        .height('100%')
        .align(index < 2 ? Alignment.Center : Alignment.TopStart)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .tabBar(this.bottomTabBar(tabId, this.homeTabTitle(tabId), index))
      }, (tabId: string) => tabId)
    }
    .key(`home_immersive_tabs_${this.themeRevision}_${this.appDarkMode ? 'dark' : 'light'}_${this.extraTabId()}`)
    .barBackgroundColor(this.immersiveTabsBarBackgroundColor())
    .barMode(BarMode.Fixed)
    .barHeight(this.homeTabBarHidden() ? 0 : 56)
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
      barWidth: this.globalTtsTabBarWidth(),
      adaptToHandedness: this.smartGripEnabled,
      thermoCtrl: true,
      barOpacity: this.homeTabBarHidden() ? 0 : 1
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
      ForEach(this.homeTabIds(), (tabId: string, index: number) => {
        TabContent() {
          this.homeTabBody(tabId)
        }
        .height('100%')
        .align(index < 2 ? Alignment.Center : Alignment.TopStart)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .tabBar(this.compatTabBar(tabId, this.homeTabTitle(tabId), index))
      }, (tabId: string) => tabId)
    }
    .barMode(BarMode.Fixed)
    // 第四个页签增减时整个重建，页签数和选中项才不会错位。
    .key(`home_compat_tabs_${this.extraTabId()}`)
    .barHeight(this.homeTabBarHidden() ? 0 : this.compatTabBarHeight())
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

  // SVG 图标按 iconStyle 染色，位图保持原色（系统只给 SVG 填色）。
  bottomTabBar(tabId: string, title: string, index: number): BottomTabBarStyle {
    return BottomTabBarStyle.of(this.navigationIcon(tabId, index), this.navigationHidesLabels() ? '' : title)
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
  compatTabBar(tabId: string, title: string, index: number) {
    Column() {
      Column({ space: AppSpacing.XXS }) {
        Column() {
          Image(this.navigationIcon(tabId, index))
            .width(this.navigationHidesLabels() ? 28 : 22)
            .height(this.navigationHidesLabels() ? 28 : 22)
            .fillColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
        }
        .width(this.navigationHidesLabels() ? 30 : 24)
        .height(this.navigationHidesLabels() ? 30 : 24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        if (!this.navigationHidesLabels()) {
          Text(title)
            .fontSize(AppFontSize.MICRO)
            .lineHeight(14)
            .height(14)
            .fontColor(this.currentIndex === index ? this.tabBarActiveColor() : this.tabBarTextColor())
        }
      }
      .width('100%')
      .height(Index.FLAT_TAB_BAR_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(this.compatTabBarHeight())
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

  // 选中态跟内容切换同时换图（homeTabIsActive 在转场开始时就指向目标页签）。没有选中态图标的主题
  // 不读页签状态，切换页签时底栏样式不会被重设。
  navigationIcon(tabId: string, index: number): ResourceStr {
    // 第四个页签（听 / 足迹）也由图标包提供：内置主题各有一套，主题包没给时用基底主题的。
    const iconPackId = ThemeRuntime.iconPackId();
    const selected = ThemeAssetRegistry.navigationHasSelectedIcons(iconPackId) && this.homeTabIsActive(index);
    return ThemeAssetRegistry.navigationIcon(iconPackId, tabId, selected);
  }

  navigationHidesLabels(): boolean {
    return ThemeAssetRegistry.navigationHidesLabels(ThemeRuntime.iconPackId());
  }

  floatingBarBottomMargin(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  /** 有底部导航条时只让出导航条，没有时（三键导航或取不到）沿用整块底部避让区。 */
  compatTabSafeHeight(): number {
    if (this.navIndicatorHeight > 0) return this.navIndicatorHeight;
    return this.navBarHeight > 0 ? this.navBarHeight : 24;
  }

}
