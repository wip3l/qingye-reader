import { BookSourceGroupStore } from '../../utils/BookSourceGroupStore';
import { SharedElementMotion } from '../../utils/SharedElementMotion';
import { LengthMetrics, router } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { Book, BookSource, SearchBook, BookFieldSanitizer } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import {
  ExploreCoordinator,
  ExploreEntry,
  ExploreFilterGroup,
  ExploreSourceOption
} from '../../core/book/ExploreCoordinator';
import { CategorySwipePager } from './CategorySwipePager';
import { ResultCoverCache, SearchBookResultList } from '../../components/book/SearchBookResultList';
import { ResultArrivalTracker } from '../../utils/ResultArrivalTracker';
import { ImmersiveMaterialSurface } from '../../components/ImmersiveMaterialSurface';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HeaderBackdrop } from '../common/HeaderBackdrop';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';
import { SearchSettingsPanel } from './SearchSettingsPanel';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { ExploreCategoryHistoryStore } from '../../utils/ExploreCategoryHistoryStore';
import { ExploreCategoryItem, ExploreCategorySheet } from './ExploreCategorySheet';
import { ExploreCacheHit, ExploreResultCache } from '../../utils/ExploreResultCache';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { WebBookService } from '../../core/book/WebBookService';
import { SourceActionKind, SourceActionMenu, SourceActionRunner, SourceDeleteConfirm, SourceDeleteDialogParams,
  SourceGroupDialogParams, SourceGroupEditor, SourceGroupTag, SourcePickerKit, SourcePickerSearchField,
  SourceVariableDialogParams, SourceVariableEditor
} from './SourcePickerKit';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { ExploreSourceOptionDataSource, ExploreMetadataTask } from '../../core/book/ShelfDataSources';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ExploreRankStyle } from '../../utils/ExploreRankStyle';
import { BookCover } from '../book/BookCover';

class ExplorePageSnapshot {
  books: SearchBook[] = [];
  shelfKeys: string[] = [];
  pageCount: number = 1;
  hasMore: boolean = true;
  updatedAt: number = 0;
  status: string = '';
  verificationUrl: string = '';
  verificationContextToken: string = '';
  verificationTitle: string = '';
  scrollOffset: number = 0;
  covers: ResultCoverCache = new ResultCoverCache();
}

/** 榜单总览里一张榜单卡的加载状态：idle 未请求，loading 加载中，ready 有结果，failed 没拿到。 */
class ExploreOverviewCard {
  books: SearchBook[] = [];
  state: string = 'idle';
  message: string = '';
}

/** 侧栏布局左侧的一节：书源自带分组，或者“榜单 / 分类”两节；只有一节时不显示节名。 */
class ExploreSidebarSection {
  key: string = '';
  title: string = '';
  indices: number[] = [];
}

/** 首页"发现"页签：发现源、筛选条件与结果列表；标题行的搜索按钮打开整页的搜索层（SearchPage）。 */
@Component
export struct ExplorePage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 顶部书源标签、筛选与刷新按钮的高度。 */
  static readonly HEADER_CONTROL_SIZE: number = 40;
  /** 标题下方频道栏的高度。 */
  static readonly CHANNEL_BAR_HEIGHT: number = 44;
  /** 频道栏被裁端的淡出长度（vp）。两侧已有分割线标出边界，淡出只做短过渡，不再叠模糊，免得分割线内侧空出一段。 */
  static readonly CHANNEL_FADE_LENGTH: number = 20;
  static readonly MENU_ITEM_HEIGHT: number = 44;
  static readonly MORE_MENU_WIDTH: number = 224;
  static readonly SEARCH_SETTINGS_MENU_WIDTH: number = 272;
  /** 分类达到这个数量才在频道栏右端显示“全部分类”按钮，少量分类横滑就能看完。 */
  static readonly CATEGORY_SHEET_MIN_COUNT: number = 6;
  /** 侧栏布局左侧频道列的宽度。 */
  static readonly SIDEBAR_RAIL_WIDTH: number = 96;
  /** 榜单总览最多做几张卡片（其余进宫格）；书源没有榜单类频道时取前几个频道做预览。 */
  static readonly OVERVIEW_MAX_BOARDS: number = 8;
  static readonly OVERVIEW_PREVIEW_FALLBACK: number = 4;
  /** 榜单卡片：最宽 320、占屏宽八成；高度放得下第一名（封面 80）加四行。 */
  static readonly OVERVIEW_CARD_MAX_WIDTH: number = 320;
  static readonly OVERVIEW_CARD_HEIGHT: number = 304;
  static readonly OVERVIEW_ROW_HEIGHT: number = 34;
  /** 本地分组键与书源平台参数分开；空分组也有非空、稳定的身份。 */
  static readonly ENTRY_GROUP_PREFIX: string = 'explore-group:';
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @State entries: ExploreEntry[] = [];
  @State sourceOptions: ExploreSourceOption[] = [];
  private exploreSourceDataSource: ExploreSourceOptionDataSource = new ExploreSourceOptionDataSource();
  @StorageLink('bookSourceGroupOrder') @Watch('onSourceGroupOrderChanged') sourceGroupOrderRaw: string = '';
  @State exploreSourceGroups: string[] = [];
  @State activeExploreSourceGroup: string = '__all__';
  @State platformNames: string[] = [];
  @State entryGroupMode: boolean = false;
  @State exploreFilters: ExploreFilterGroup[] = [];
  @State exploreFilterDrafts: ExploreFilterGroup[] = [];
  @State showExploreFilterPanel: boolean = false;
  @State sourceNames: string[] = [];
  /** 搜索层的范围“当前书源”要显示名字，放进 AppStorage。 */
  @StorageLink('exploreSourceName') selectedSourceName: string = '';
  @State selectedIndex: number = 0;
  @State showExploreSourcePicker: boolean = false;
  @State showExploreMoreMenu: boolean = false;
  /** “更多”菜单当前页：'' 一级，'layout' 结果布局，'search' 搜索设置。 */
  @State exploreMoreMenuPage: string = '';
  /** 频道栏左侧“模式”的下拉。 */
  @State showExplorePlatformMenu: boolean = false;
  @State showExploreCategorySheet: boolean = false;
  /** 频道栏的实际宽度：沉浸材质底板需要具体数值。 */
  @State exploreChannelBarWidth: number = 0;
  @State showExploreSourceActionMenu: boolean = false;
  @State actionExploreSourceUrl: string = '';
  @State actionExploreSourceNative: boolean = false;
  /** 书源地址到显示名（同名书源补地址）的对照，书源列表加载时重算。 */
  private exploreSourceDisplayNames: Map<string, string> = new Map<string, string>();
  @State exploreContextMenuX: number = 16;
  @State exploreContextMenuY: number = 96;
  @State exploreSourceFilterInput: string = '';
  @State exploreSourceFilterKeyword: string = '';
  @State exploreViewportWidth: number = 360;
  @State exploreViewportHeight: number = 720;
  @State books: SearchBook[] = [];
  /** 分类会话同时保留结果、分页、封面和滚动位置；切回不重走加载流程。 */
  @State explorePages: Map<string, ExplorePageSnapshot> = new Map();
  private exploreBooksPageKey: string = '';
  private resultArrivalTracker: ResultArrivalTracker = new ResultArrivalTracker();
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isLoading: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMoreExploreBooks: boolean = true;
  @State status: string = '';
  @State verificationUrl: string = '';
  private verificationContextToken: string = '';
  @State verificationTitle: string = '';
  @StorageLink('explorePlatform') selectedPlatform: string = '';
  /**
   * 结果布局，持久保存：'list' 卡片列表，'grid' 封面平铺，'rank' 排行，'overview' 榜单总览，
   * 'sidebar' 侧栏。约定见 ExploreRankStyle。
   */
  @StorageLink('exploreResultLayout') exploreResultLayout: string = 'list';
  /** 榜单总览里点进了某个榜或分类（看的是 selectedIndex 那一项）；返回键据此先回总览。 */
  @StorageLink('exploreOverviewDrillActive') @Watch('onOverviewDrillActiveChanged') overviewDrilled: boolean = false;
  /** 榜单总览各卡片的结果，键与 explorePageKeys() 一致；整表替换才会刷新界面。 */
  @State overviewCards: Map<string, ExploreOverviewCard> = new Map();
  /** 总览卡片用自己的解析器，和当前频道的加载互不取消；两路并发，一路一个。 */
  private overviewWorkers: ExploreCoordinator[] = [new ExploreCoordinator(), new ExploreCoordinator()];
  private overviewWorkerBusy: boolean[] = [false, false];
  private overviewQueue: number[] = [];
  private overviewGeneration: number = 0;
  /** 总览横滑到的最后一张卡；只加载已经看到的和下一张。 */
  private overviewVisibleEnd: number = 1;
  /** 并发写发现缓存会互相覆盖（整份读改写），总览的写入排队进行。 */
  private overviewCacheChain: Promise<void> = Promise.resolve();
  private exploreOverviewScroller: Scroller = new Scroller();
  private exploreRailScroller: ListScroller = new ListScroller();
  @StorageLink('exploreSourceUrl') selectedSourceUrl: string = '';
  @StorageLink('bookSourceExploreRefreshNonce') @Watch('onExploreRefreshRequested')
  bookSourceExploreRefreshNonce: number = 0;
  @StorageProp('exploreSourceCacheRevision') @Watch('onExploreSourceCacheInvalidated')
  exploreSourceCacheRevision: number = 0;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookSourceOrderRevision') @Watch('onBookSourceOrderChanged') bookSourceOrderRevision: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultCoverBackground') searchExploreShowResultCoverBackground: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: ExploreCoordinator = new ExploreCoordinator();
  private exploreSourceScroller: Scroller = new Scroller();
  private exploreChannelScroller: Scroller = new Scroller();
  /** 标题行收起量，0 为完整显示，exploreCollapsibleHeight() 为完全收起。 */
  @State exploreHeaderCollapse: number = 0;
  // 顶栏毛玻璃按列表实际滚动距离显现，见 CollapsingHeader.backdropReveal。
  @State exploreHeaderBackdropReveal: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private hasLoaded: boolean = false;
  private hasRestoredExploreSelection: boolean = false;
  private shelfStatusVersion: number = 0;
  private exploreLoadVersion: number = 0;
  private exploreContentLoadedAt: number = 0;
  private explorePage: number = 1;
  private exploreMetadataQueue: ExploreMetadataTask[] = [];
  private exploreMetadataQueued: Set<string> = new Set<string>();
  private exploreMetadataInFlight: Set<string> = new Set<string>();
  private exploreMetadataUnavailable: Set<string> = new Set<string>();
  private exploreMetadataActive: number = 0;

  aboutToAppear() {
    if (this.isActive) {
      this.ensureLoaded();
    }
  }

  onActiveChanged(): void {
    if (this.isActive) {
      this.ensureLoaded();
      if (this.showsOverviewHome()) this.requestOverviewCards(this.overviewVisibleEnd);
    } else {
      this.cancelExploreLoad();
      this.cancelExploreOverview();
      this.resultArrivalTracker.discardPending();
      this.closeExploreFilterPanel();
      this.showExplorePlatformMenu = false;
      this.showExploreMoreMenu = false;
      if (this.showExploreSourcePicker) {
        this.showExploreSourcePicker = false;
        this.clearExploreSourceFilter();
      }
      this.closeExploreSourceActions();
      SourceActionRunner.closeVariableEditor(this.getUIContext());
    }
  }

  ensureLoaded(): void {
    if ((!this.hasLoaded || !ExploreResultCache.isFresh(this.exploreContentLoadedAt)) && !this.isLoading) {
      this.loadEntries();
    }
  }

  aboutToDisappear(): void {
    this.cancelExploreLoad();
    this.cancelExploreOverview();
  }

  cancelExploreLoad(): void {
    if (this.isLoading || this.isLoadingMore) this.exploreContentLoadedAt = 0;
    this.coordinator.cancelPending();
    this.exploreLoadVersion++;
    this.exploreMetadataQueue = [];
    this.exploreMetadataQueued.clear();
    this.isLoading = false;
    this.isLoadingMore = false;
  }

  onShelfChanged(): void {
    this.syncExploreShelfStatus(this.books);
  }

  onBookSourceOrderChanged(): void {
    if (this.isActive && this.hasLoaded && !this.isLoading) {
      this.loadEntries();
    } else if (this.hasLoaded) {
      // 页面常驻但不在前台：标记过期，下次切回发现页时按新顺序重新加载书源列表。
      this.exploreContentLoadedAt = 0;
    }
  }

  onSourceGroupOrderChanged(): void {
    this.exploreSourceGroups = this.buildExploreSourceGroups();
    this.syncExploreSourceGroupsFromDb();
  }

  onExploreRefreshRequested(): void {
    if (this.bookSourceExploreRefreshNonce <= 0) return;
    const sourceUrl = AppStorage.get<string>('bookSourceExploreRefreshSourceUrl') || '';
    if (sourceUrl) this.selectedSourceUrl = sourceUrl;
    this.exploreContentLoadedAt = 0;
    this.coordinator.clearExploreMenuCache();
    if (this.isActive && !this.isLoading) {
      this.loadEntries('', true);
    }
  }

  onExploreSourceCacheInvalidated(): void {
    // 书源在书源管理中被删除、导入或编辑：已加载的分类和列表不再可信，下次进入发现页时重新加载。
    this.exploreContentLoadedAt = 0;
    this.coordinator.clearExploreMenuCache();
    if (this.isActive && this.hasLoaded) {
      this.loadEntries();
    }
  }

  async loadEntries(platformOverride: string = '', forceRefresh: boolean = false, retainPages: boolean = false) {
    if (!retainPages) {
      this.resultArrivalTracker.reset();
      this.explorePages.clear();
    }
    const loadVersion = this.beginExploreLoad();
    const previousActiveEntries = this.getActiveEntries();
    const previousEntry = previousActiveEntries.length > 0 ?
      previousActiveEntries[Math.min(this.selectedIndex, previousActiveEntries.length - 1)] : null;
    const previousEntryKey = previousEntry ? `${previousEntry.title}\n${previousEntry.url}` : '';
    this.hasLoaded = true;
    this.exploreContentLoadedAt = 0;
    this.status = '正在加载发现分类...';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      if (!this.hasRestoredExploreSelection) {
        this.hasRestoredExploreSelection = true;
        await this.restoreExploreSelectionFromSettings();
        if (!this.isCurrentExploreLoad(loadVersion)) return;
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const previousSourceName = this.selectedSourceName;
      const previousSourceUrl = this.selectedSourceUrl;
      const sourceOptions = await this.coordinator.getExploreSources();
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      // 数据库查询已经按书源管理中的 customOrder 排序，同时只会返回已启用的书源。
      this.sourceOptions = sourceOptions;
      await BookSourceGroupStore.loadOrder(getContext(this));
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.rebuildExploreSourceDisplayNames(sourceOptions);
      this.exploreSourceGroups = this.buildExploreSourceGroups();
      if (this.activeExploreSourceGroup !== '__all__' &&
        !this.exploreSourceGroups.includes(this.activeExploreSourceGroup)) {
        this.activeExploreSourceGroup = '__all__';
      }
      this.sourceNames = this.sourceOptions.map((option: ExploreSourceOption) => option.sourceName);
      this.refreshExploreSourceDataSource();
      const restoredOption = this.sourceOptions.find((option: ExploreSourceOption) =>
        option.sourceUrl === previousSourceUrl) ||
        this.sourceOptions.find((option: ExploreSourceOption) => option.sourceName === previousSourceName) ||
        (this.sourceOptions.length > 0 ? this.sourceOptions[0] : null);
      this.selectedSourceName = restoredOption ? restoredOption.sourceName : '';
      this.selectedSourceUrl = restoredOption ? restoredOption.sourceUrl : '';
      this.entryGroupMode = false;
      this.platformNames = this.getSelectedSourcePlatforms();
      if (platformOverride && this.platformNames.includes(platformOverride)) {
        this.selectedPlatform = platformOverride;
      }
      this.normalizeSelectedPlatform();
      const entries = await this.coordinator.getEntries(
        this.platformNames.length > 0 ? this.selectedPlatform : '', this.getSelectedSourceUrl());
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.entries = entries;
      const dynamicPlatforms = this.coordinator.getDiscoveredPlatforms(this.selectedSourceUrl);
      const inferredGroups = this.getEntryGroupNames(entries);
      const activeOption = this.getSelectedSourceOption();
      this.exploreFilters = this.coordinator.getDiscoveredFilters(this.selectedSourceUrl);
      if (activeOption && dynamicPlatforms.length > 0) {
        // 兼容书源脚本给出的“平台/来源”选择器本身就是一种筛选，有筛选按钮时不再重复显示。
        activeOption.platforms = this.exploreFilters.length > 0 ? [] : dynamicPlatforms;
      } else if (activeOption && activeOption.platforms.length === 0 && inferredGroups.length > 1) {
        // 菜单自带的分组与筛选互不相干：原生书源的分组来自 menus 里无 url 的条目，筛选来自 vars，
        // 两者并存；以前有筛选就清掉分组，各组分类会被合并平铺成一行。
        activeOption.platforms = inferredGroups;
        this.entryGroupMode = true;
      }
      this.platformNames = this.getSelectedSourcePlatforms();
      // 本地分组要等菜单解析后才存在，不能只在请求前处理显式切换。
      if (platformOverride && this.platformNames.includes(platformOverride)) {
        this.selectedPlatform = platformOverride;
      }
      this.normalizeSelectedPlatform();
      if (this.entries.length > 0) {
        // Keep the group that was visible before refresh. Resetting to index 0 made a refresh
        // from (for example) “玄幻” reload the first group and leave the visible group stale.
        let restoredIndex = previousEntryKey ? this.restoreExploreCategory(previousEntryKey) : -1;
        if (restoredIndex < 0 && !previousEntryKey && !platformOverride) {
          // 首次进入或刚切换到这个书源：回到上次在该书源停留的分类。
          await ExploreCategoryHistoryStore.load(getContext(this));
          if (!this.isCurrentExploreLoad(loadVersion)) return;
          const lastKey = ExploreCategoryHistoryStore.last(this.selectedSourceUrl);
          restoredIndex = lastKey ? this.restoreExploreCategory(lastKey) : -1;
        }
        this.selectedIndex = restoredIndex >= 0 ? restoredIndex : 0;
        if (this.selectedIndex > 0) {
          this.scrollExploreChannelToSelected();
        }
        if (this.showsOverviewHome()) {
          // 总览首屏不加载单个频道，各榜单卡片自己按需加载。
          if (forceRefresh) {
            try {
              await ExploreResultCache.clearSource(getContext(this), this.selectedSourceUrl);
            } catch (cacheError) {
              console.warn('清除发现内容缓存失败:', cacheError);
            }
            if (!this.isCurrentExploreLoad(loadVersion)) return;
          }
          this.status = '';
          this.exploreContentLoadedAt = Date.now();
          this.startExploreOverview();
        } else if (forceRefresh || !this.restoreExplorePage(this.explorePageKeys()[this.selectedIndex] || '')) {
          await this.loadBooks(loadVersion, forceRefresh);
        }
      } else {
        this.books = [];
        this.status = this.coordinator.getNoticeMessage() ||
          `${this.getSelectedSiteLabel()} 暂无可用发现分类`;
      }
    } catch (e) {
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      console.error('加载发现失败:', e);
      this.status = '发现加载失败';
    } finally {
      this.finishExploreLoad(loadVersion);
    }
  }

  async loadBooks(loadVersion?: number, forceRefresh: boolean = false) {
    const currentLoadVersion = loadVersion ?? this.beginExploreLoad();
    // 离开的页面已保存为翻页预览；新分类请求失败时不能把旧分类的书当成新结果。
    this.books = [];
    this.exploreContentLoadedAt = 0;
    this.explorePage = 1;
    this.hasMoreExploreBooks = true;
    this.isLoadingMore = false;
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) {
      this.finishExploreLoad(currentLoadVersion);
      return;
    }
    this.status = '';
    this.verificationUrl = '';
    this.verificationTitle = '';
    try {
      const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
      if (forceRefresh) {
        // A manual refresh must not leave a failed request able to resurrect stale discovery
        // results on the next normal load. Clear the source cache before requesting new data.
        this.coordinator.clearExploreMenuCache();
        await ExploreResultCache.clearSource(getContext(this), entry.sourceUrl);
      }
      if (!forceRefresh) {
        try {
          const cached: ExploreCacheHit | null = await ExploreResultCache.load(
            getContext(this), entry.sourceUrl, this.selectedPlatform, entry.title, entry.url);
          if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
          if (cached) {
            this.exploreContentLoadedAt = cached.updatedAt;
            this.explorePage = cached.pageCount;
            this.hasMoreExploreBooks = cached.hasMore;
            await this.applyExploreBooks(cached.books, entry, currentLoadVersion, true);
            return;
          }
        } catch (cacheError) {
          console.warn('读取发现内容缓存失败，改用网络加载:', cacheError);
        }
      }
      const books = await this.coordinator.explore(entry, 1);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      this.hasMoreExploreBooks = books.length > 0;
      await this.applyExploreBooks(books, entry, currentLoadVersion, false);
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      if (books.length > 0) {
        this.exploreContentLoadedAt = Date.now();
        try {
          await ExploreResultCache.save(getContext(this), entry.sourceUrl, this.selectedPlatform,
            entry.title, entry.url, books, this.explorePage, this.hasMoreExploreBooks);
        } catch (cacheError) {
          console.warn('保存发现内容缓存失败:', cacheError);
        }
      }
    } catch (e) {
      if (!this.isCurrentExploreLoad(currentLoadVersion)) return;
      console.error('获取发现内容失败:', e);
      this.status = '发现内容获取失败';
    } finally {
      this.finishExploreLoad(currentLoadVersion);
    }
  }

  async loadMoreExploreBooks(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMoreExploreBooks || this.books.length === 0) return;
    const activeEntries = this.getActiveEntries();
    if (activeEntries.length === 0) return;
    const entry = activeEntries[Math.min(this.selectedIndex, activeEntries.length - 1)];
    const loadVersion = this.exploreLoadVersion;
    const nextPage = this.explorePage + 1;
    this.isLoadingMore = true;
    try {
      const nextBooks = await this.coordinator.explore(entry, nextPage);
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      const merged = this.mergeExploreBooks(this.books, nextBooks);
      const addedCount = merged.length - this.books.length;
      if (nextBooks.length === 0 || addedCount === 0) {
        const notice = this.coordinator.getNoticeMessage();
        // Network/verification failures should remain retryable; a genuinely empty or duplicate
        // next page means the source has reached its end (or does not implement pagination).
        this.hasMoreExploreBooks = nextBooks.length === 0 && this.isRetryableExploreNotice(notice);
        this.status = notice || `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · 已加载全部`;
      } else {
        this.books = merged;
        this.explorePage = nextPage;
        this.status = `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · ${this.books.length} 本`;
        await this.syncExploreShelfStatus(this.books);
      }
      if (!this.isCurrentExploreLoad(loadVersion)) return;
      this.exploreContentLoadedAt = Date.now();
      await ExploreResultCache.save(getContext(this), entry.sourceUrl, this.selectedPlatform,
        entry.title, entry.url, this.books, this.explorePage, this.hasMoreExploreBooks);
    } catch (e) {
      if (this.isCurrentExploreLoad(loadVersion)) {
        console.error('加载更多发现内容失败:', e);
        this.status = '加载更多发现内容失败，可继续上滑重试';
      }
    } finally {
      if (this.isCurrentExploreLoad(loadVersion)) {
        this.isLoadingMore = false;
        this.retainCurrentExplorePage();
      }
    }
  }

  mergeExploreBooks(current: SearchBook[], incoming: SearchBook[]): SearchBook[] {
    const merged = current.slice();
    for (const book of incoming) {
      if (!merged.some((item: SearchBook): boolean =>
        item.origin === book.origin && item.bookUrl === book.bookUrl)) {
        merged.push(book);
      }
    }
    return merged;
  }

  isRetryableExploreNotice(notice: string): boolean {
    return /请求失败|网络|超时|timeout|HTTP|网页验证|需要验证|接口返回空响应/i.test(notice || '');
  }

  shouldOfferExploreSourceLogin(): boolean {
    return !!this.selectedSourceUrl &&
      /请先登[录陆]|需要登[录陆]|未登[录陆]|令牌|token|无权限|登录设备数已达上限|设备管理/i.test(this.status || '');
  }

  exploreSourceLoginButtonLabel(): string {
    return /登录设备数已达上限|设备管理/i.test(this.status || '') ? '管理登录设备' : '登录书源';
  }

  openExploreSourceLogin(): void {
    if (!this.selectedSourceUrl) return;
    router.pushUrl({
      url: 'pages/BookSource',
      params: {
        openLoginSourceUrl: this.selectedSourceUrl
      }
    });
  }

  async applyExploreBooks(books: SearchBook[], entry: ExploreEntry, loadVersion: number,
    fromCache: boolean): Promise<void> {
    this.exploreBooksPageKey = this.explorePageKeys()[this.selectedIndex] || '';
    this.books = books;
    const shelfStatusVersion = this.shelfStatusVersion;
    const shelfKeys = await this.loadExploreShelfKeys(books);
    if (!this.isCurrentExploreLoad(loadVersion)) return;
    if (shelfStatusVersion === this.shelfStatusVersion) {
      this.shelfBookKeys = shelfKeys;
    }
    if (fromCache) {
      this.verificationUrl = '';
      this.verificationTitle = '';
    } else {
      this.verificationContextToken = AppStorage.get<string>('pendingVerificationContextToken') || '';
      this.verificationUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
      this.verificationTitle = AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
    }
    this.status = this.books.length > 0 ?
      `${this.getSelectedSiteLabel()} · ${entry.sourceName} · ${entry.title} · ${this.books.length} 本${fromCache ? ' · 缓存' : ''}` :
      (this.verificationUrl ? `${entry.sourceName} 可能需要网页验证` :
        (this.coordinator.getNoticeMessage() || `${this.getSelectedSiteLabel()} 当前分类暂无结果`));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HomeThemeBackdrop({ visibleHeight: this.statusBarHeight + 250, strength: 0.7 })

      Column() {
        Column() {
          // 列表上滑时标题行收起：外层按收起量变矮并裁剪，标题行贴底上移并淡出。
          Stack({ alignContent: Alignment.Bottom }) {
            Row() {
              Text('发现')
                .fontSize(AppFontSize.DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .flexShrink(0)

              Blank()

              this.exploreSourceLabel()

              if (this.exploreFilters.length > 0) {
                this.exploreFilterButton()
              }

              Row() {
                this.exploreHeaderCircleButton($r('sys.symbol.magnifyingglass'), false, '搜索书名或作者', () => {
                  this.openHomeSearch();
                })
              }
              .margin({ right: 10 })

              this.exploreMoreButton()
            }
            .width('100%')
            .height(56 + this.statusBarHeight)
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.statusBarHeight })
            .alignItems(VerticalAlign.Center)
            .opacity(CollapsingHeader.contentOpacity(this.exploreHeaderCollapseValue()))
            .hitTestBehavior(CollapsingHeader.acceptsTouch(this.exploreHeaderCollapseValue()) ? HitTestMode.Default : HitTestMode.None)
          }
          .width('100%')
          .height(this.statusBarHeight + this.exploreCollapsibleHeight() - this.exploreHeaderCollapseValue())
          .clip(true)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.onHeaderCollapseChange((this.statusBarHeight + this.exploreCollapsibleHeight() -
              Number(newArea.height)) / this.exploreCollapsibleHeight());
          })

          if (this.isOverviewLayout() && this.overviewDrilled) {
            this.exploreOverviewDrillBar()
          } else if (this.isOverviewLayout() || this.isSidebarLayout()) {
            if (this.showsExplorePlatformSelector()) {
              this.explorePlatformBar()
            }
          } else if (this.showsExploreChannelBar()) {
            this.exploreChannelBar()
          }

          if (this.shouldShowExploreStatus()) {
            Row() {
              Text(this.status)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.secondaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
                .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
                .borderRadius(12)

              if (this.verificationUrl) {
                Button('去验证')
                  .height(28)
                  .fontSize(AppFontSize.CAPTION)
                  .borderRadius(14)
                  .backgroundColor(this.buttonColor())
                  .fontColor(ThemeRuntime.onAccentColor())
                  .margin({ left: AppSpacing.LG })
                  .onClick(() => {
                    this.openVerification();
                  })
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(4)

      HeaderBackdrop({ backdropHeight: this.statusBarHeight + this.exploreCollapsibleHeight() -
        this.exploreHeaderCollapseValue(),
        statusBarHeight: this.statusBarHeight,
        backdropColor: ThemeRuntime.topBarColor(this.appDarkMode),
        reveal: ThemeRuntime.homeBackdrop(this.appDarkMode) ? this.exploreHeaderBackdropReveal : 1 })
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(3)

      if (this.showsOverviewHome() && this.getActiveEntries().length > 0) {
        this.exploreOverviewHome()
      } else if (this.isSidebarLayout() && this.getActiveEntries().length > 0) {
        Row() {
          this.exploreSidebarRail()
          this.exploreCurrentResultContent()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      } else if (this.isOverviewLayout() && this.getActiveEntries().length > 0) {
        this.exploreCurrentResultContent()
      } else if (this.usesExploreCategoryPager()) {
        CategorySwipePager({
          pageKeys: this.explorePageKeys(),
          selectedIndex: this.selectedIndex,
          onSelect: (key: string): void => {
            const index = this.explorePageKeys().indexOf(key);
            if (index >= 0 && index !== this.selectedIndex) this.selectExploreEntry(index);
          },
          pageContent: (key: string) => {
            this.exploreResultContent(key)
          }
        })
        .layoutWeight(1)
      } else {
        // 没有分类时，空 key 持续跟随当前内容。
        this.exploreResultContent('')
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.surfaceColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      // 长按书源菜单的锚点：放在手指位置的 1×1 节点，弹出层贴着它弹出。
      Column()
        .width(1)
        .height(1)
        .position({ x: this.exploreContextMenuX, y: this.exploreContextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showExploreSourceActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.exploreSourceActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showExploreSourceActionMenu = false;
        }))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      if (Number.isFinite(width) && width > 0) {
        this.exploreViewportWidth = width;
      }
      const height = typeof newValue.height === 'number' ? newValue.height : Number.parseFloat(`${newValue.height}`);
      if (Number.isFinite(height) && height > 0) {
        this.exploreViewportHeight = height;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showExploreCategorySheet, this.exploreCategorySheet(), this.exploreCategorySheetOptions())
  }

  /** 全部分类面板：与详情页目录同一种半模态，停 60% 与全屏两档。 */
  exploreCategorySheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['60%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onDisappear: () => {
        this.showExploreCategorySheet = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options, this.appDarkMode, this.accentColor());
  }

  @Builder
  exploreCategorySheet() {
    ExploreCategorySheet({
      items: this.exploreCategoryItems(),
      recentKeys: ExploreCategoryHistoryStore.recent(this.selectedSourceUrl),
      selectedKey: this.currentExploreEntryKey(),
      onSelect: (key: string): void => {
        this.selectExploreCategory(key);
      },
      onClose: (): void => {
        this.showExploreCategorySheet = false;
      }
    })
  }

  openSearchBookDetail(book: SearchBook, autoStartRead: boolean = false) {
    router.pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        sharedCoverId: autoStartRead ? '' : SharedElementMotion.coverId('explore', book.origin, book.bookUrl),
        bookUrl: book.bookUrl,
        tocUrl: book.tocUrl,
        origin: book.origin,
        originName: book.originName,
        name: book.name,
        author: book.author,
        kind: book.kind,
        status: book.status,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        updateTime: book.updateTime,
        wordCount: book.wordCount,
        type: String(book.type || 0),
        variable: book.variable || '',
        promptAddToShelfOnBack: !autoStartRead && this.searchExplorePromptAddToShelfOnBack ? 'true' : 'false',
        autoStartRead: autoStartRead ? 'true' : 'false'
      }
    });
  }

  /** 书源选择弹出层：顶部搜索框，下面是分组小标签和书源列表；长按书源打开操作菜单。 */
  @Builder
  exploreSourcePickerContent() {
    Column({ space: AppSpacing.XS }) {
      SourcePickerSearchField({
        text: this.exploreSourceFilterInput,
        onTextChange: (value: string): void => {
          this.exploreSourceFilterInput = value;
          this.applyExploreSourceFilter();
        }
      })

      if (this.exploreSourceGroups.length > 1) {
        this.exploreSourceGroupTabs()
      }

      if (this.getFilteredExploreSourceOptions().length === 0) {
        Text(this.activeExploreSourceGroup === '__all__' ? '没有匹配的书源' : '当前分组没有匹配的书源')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(52)
          .textAlign(TextAlign.Center)
      } else {
        List({ scroller: this.exploreSourceScroller, space: 0 }) {
          LazyForEach(this.exploreSourceDataSource, (option: ExploreSourceOption) => {
            ListItem() {
              Row() {
                Text(this.exploreSourceDisplayName(option))
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontColor(option.sourceUrl === this.selectedSourceUrl ? this.accentColor() : this.primaryTextColor())
                  .fontWeight(option.sourceUrl === this.selectedSourceUrl ? FontWeight.Medium : FontWeight.Regular)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                if (this.activeExploreSourceGroup === '__all__') {
                  SourceGroupTag({ label: this.exploreSourceGroupLabel(option.sourceGroup) })
                    .margin({ left: AppSpacing.MD })
                }

                if (option.sourceUrl === this.selectedSourceUrl) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor([this.accentColor()])
                    .margin({ left: AppSpacing.MD })
                }
              }
              .width('100%')
              .height(ExplorePage.MENU_ITEM_HEIGHT)
              .padding({ left: 12, right: 12 })
              .borderRadius(this.exploreMenuItemRadius())
              .backgroundColor(option.sourceUrl === this.selectedSourceUrl ? this.exploreSelectedBackgroundColor() : '#00000000')
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                if (this.showExploreSourceActionMenu) return;
                this.showExploreSourcePicker = false;
                this.clearExploreSourceFilter();
                this.switchExploreSource(option);
              })
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction((event: GestureEvent) => {
                    this.openExploreSourceActions(option, event);
                  })
              )
            }
          }, (option: ExploreSourceOption): string => option.sourceUrl || option.sourceName)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .constraintSize({ maxHeight: 320 })
        .scrollBar(BarState.Auto)
        .cachedCount(8)
        .onAppear(() => { setTimeout(() => this.scrollExploreSourceToCurrent(), 0); })
      }
    }
    .width(this.exploreSourceDropdownWidth())
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.switchExploreSourceGroupBySwipe(event.offsetX);
        })
    )
  }

  @Builder
  exploreSourceActionMenu() {
    SourceActionMenu(this.actionExploreSourceNative, this.appDarkMode, (kind: string): void => {
      this.runExploreSourceAction(kind);
    })
  }

  @Builder
  exploreSourceGroupTabs() {
    Scroll() {
      Row() {
        this.exploreSourceGroupTab('全部', '__all__')
        ForEach(this.exploreSourceGroups, (group: string) => {
          this.exploreSourceGroupTab(group, group)
        }, (group: string) => group)
      }
      .constraintSize({ minWidth: '100%' })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height(ExplorePage.MENU_ITEM_HEIGHT)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  /** 字号与下面的书源列表、书架分类栏一致，选中项强调色加下划线。 */
  @Builder
  exploreSourceGroupTab(label: string, groupKey: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.activeExploreSourceGroup === groupKey ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.activeExploreSourceGroup === groupKey ? this.accentColor() : this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 128 })
      Row()
        .width(16)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.accentColor())
        .opacity(this.activeExploreSourceGroup === groupKey ? 1 : 0)
    }
    .height('100%')
    .padding({ left: 12, right: 12, top: 6 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.selectExploreSourceGroup(groupKey))
  }

  /** 标题右侧的书源名标签：按名称估宽，最多占屏宽 45%，点开书源选择弹出层。 */
  @Builder
  exploreSourceLabel() {
    Row() {
      ImmersiveMaterialSurface({
        surfaceWidth: this.exploreSourceLabelWidth(),
        surfaceHeight: ExplorePage.HEADER_CONTROL_SIZE,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: this.accentGlowColor()
      }) {
        Row({ space: AppSpacing.XS }) {
          Text(this.selectedSourceName || '选择书源')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          SymbolGlyph(this.showExploreSourcePicker ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.secondaryTextColor()])
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 10 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`当前书源${this.selectedSourceName}，切换书源`)
        .onClick(() => {
          this.showExploreFilterPanel = false;
          this.showExplorePlatformMenu = false;
          this.toggleExploreSourcePicker();
        })
      }
    }
    .margin({ left: AppSpacing.MD, right: 10 })
    .bindPopup(this.showExploreSourcePicker, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.exploreSourcePickerContent()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.showExploreSourcePicker = false;
      this.clearExploreSourceFilter();
    }))
  }

  exploreSourceLabelWidth(): number {
    const name = this.selectedSourceName || '选择书源';
    // 左右留白 24、箭头 14、间隔 4，再留 2 防止取整后差一点被省略。
    const desired = Math.ceil(this.measureExploreSourceLabelText(name)) + 44;
    // 右侧还有搜索、更多（以及可选的筛选）按钮，各 40 加 10 间隔；标题约 56，页边距 32。
    const buttonsWidth = (this.exploreFilters.length > 0 ? 3 : 2) * (ExplorePage.HEADER_CONTROL_SIZE + 10);
    const available = this.exploreViewportWidth - 32 - 56 - AppSpacing.MD - buttonsWidth;
    return Math.max(72, Math.min(desired, Math.floor(Math.min(this.exploreViewportWidth * 0.45, available))));
  }

  /** 按实际字号量书源名宽度：字号是 fp，系统调大字体后按每字 14 估会偏窄，短名字只剩首字。 */
  measureExploreSourceLabelText(name: string): number {
    try {
      const context = this.getUIContext();
      const widthPx = context.getMeasureUtils().measureText({
        textContent: name,
        fontSize: AppFontSize.BODY,
        fontWeight: FontWeight.Medium
      });
      if (widthPx > 0) return context.px2vp(widthPx);
    } catch (error) {
    }
    let textWidth = 0;
    for (let index = 0; index < name.length; index++) {
      textWidth += name.charCodeAt(index) > 0x2E80 ? AppFontSize.BODY : AppFontSize.BODY * 0.6;
    }
    return textWidth * 1.2;
  }

  @Builder
  exploreHeaderCircleButton(icon: Resource, active: boolean, label: string, onTap: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: ExplorePage.HEADER_CONTROL_SIZE,
      surfaceHeight: ExplorePage.HEADER_CONTROL_SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentGlowColor()
    }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([active ? this.accentColor() : this.primaryTextColor()])
      }
      .width('100%')
      .height('100%')
      .accessibilityText(label)
      .onClick(() => onTap())
    }
  }

  /** 随列表收起的高度：标题行；频道栏常驻。 */
  exploreCollapsibleHeight(): number {
    return CollapsingHeader.DISTANCE;
  }

  openHomeSearch(): void {
    this.showExploreSourcePicker = false;
    this.showExploreFilterPanel = false;
    this.showExplorePlatformMenu = false;
    this.showExploreMoreMenu = false;
    AppStorage.setOrCreate('homeSearchActive', true);
  }

  @Builder
  exploreMoreButton() {
    Row() {
      this.exploreHeaderCircleButton($r('sys.symbol.more'), this.showExploreMoreMenu, '更多操作', () => {
        this.exploreMoreMenuPage = '';
        this.showExploreSourcePicker = false;
        this.showExploreFilterPanel = false;
        this.showExplorePlatformMenu = false;
        this.showExploreMoreMenu = !this.showExploreMoreMenu;
      })
    }
    .bindPopup(this.showExploreMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.exploreMoreDropdown()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.showExploreMoreMenu = false;
    }))
  }

  /** 与书架“更多”同样的两级菜单：一级是刷新与布局、搜索设置，后两项点进去换成二级内容，顶部一行返回。 */
  @Builder
  exploreMoreDropdown() {
    Column({ space: AppSpacing.XXS }) {
      if (this.exploreMoreMenuPage !== '') {
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(14)
            .fontColor([this.primaryTextColor()])
          Text(this.exploreMoreMenuPage === 'layout' ? '结果布局' : '搜索设置')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
        }
        .width('100%')
        .height(ExplorePage.MENU_ITEM_HEIGHT)
        .padding({ left: 12, right: 12 })
        .accessibilityText('返回更多操作')
        .onClick(() => { this.exploreMoreMenuPage = ''; })
        Divider().color(ThemeRuntime.hairlineColor(this.appDarkMode))
      }
      if (this.exploreMoreMenuPage === 'layout') {
        this.exploreLayoutItem('列表', ExploreRankStyle.LAYOUT_LIST, $r('sys.symbol.list_bullet'))
        this.exploreLayoutItem('平铺', ExploreRankStyle.LAYOUT_GRID, $r('sys.symbol.square_grid_2x2'))
        this.exploreLayoutItem('排行', ExploreRankStyle.LAYOUT_RANK, $r('sys.symbol.ranking'))
        this.exploreLayoutItem('榜单总览', ExploreRankStyle.LAYOUT_OVERVIEW, $r('sys.symbol.rectangle_on_rectangle'))
        this.exploreLayoutItem('侧栏', ExploreRankStyle.LAYOUT_SIDEBAR, $r('sys.symbol.open_sidebar'))
      } else if (this.exploreMoreMenuPage === 'search') {
        SearchSettingsPanel({ panelWidth: ExplorePage.SEARCH_SETTINGS_MENU_WIDTH -
          ImmersiveMaterialRuntime.POPUP_MENU_PADDING * 2, inMenu: true })
      } else {
        this.exploreMoreActionItem('刷新发现内容', $r('sys.symbol.arrow_clockwise'), () => {
          this.showExploreMoreMenu = false;
          this.loadEntries('', true);
        })
        this.exploreMoreMenuItem('结果布局', this.exploreLayoutLabel(),
          $r('sys.symbol.square_grid_2x2'), 'layout')
        this.exploreMoreMenuItem('搜索设置', '', $r('sys.symbol.gearshape'), 'search')
      }
    }
    .width(this.exploreMoreMenuPage === 'search' ? ExplorePage.SEARCH_SETTINGS_MENU_WIDTH : ExplorePage.MORE_MENU_WIDTH)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  exploreMoreMenuItem(label: string, value: string, icon: Resource, page: string) {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.primaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (value) {
        Text(value)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(ExplorePage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.exploreMenuItemRadius())
    .accessibilityText(value ? `${label}：${value}` : label)
    .onClick(() => { this.exploreMoreMenuPage = page; })
  }

  /** 一级菜单里直接执行的操作（没有二级页）。 */
  @Builder
  exploreMoreActionItem(label: string, icon: Resource, action: () => void) {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.primaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(ExplorePage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.exploreMenuItemRadius())
    .accessibilityText(label)
    .onClick(() => action())
  }

  @Builder
  exploreLayoutItem(label: string, layout: string, icon: Resource) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([this.exploreResultLayout === layout ? this.accentColor() : this.secondaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.exploreResultLayout === layout ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.exploreResultLayout === layout ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.exploreResultLayout === layout) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(ExplorePage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.exploreMenuItemRadius())
    .backgroundColor(this.exploreResultLayout === layout ? this.exploreSelectedBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.applyResultLayout(layout))
  }

  @Builder
  exploreFilterButton() {
    Row() {
      this.exploreHeaderCircleButton($r('sys.symbol.funnel'), this.showExploreFilterPanel,
        `筛选条件：${this.exploreFilterSummary()}`, () => {
          this.showExploreSourcePicker = false;
          this.showExplorePlatformMenu = false;
          this.toggleExploreFilterPanel();
        })
    }
    .margin({ right: 10 })
    .bindPopup(this.showExploreFilterPanel, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.exploreFilterPopupContent()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.closeExploreFilterPanel();
    }))
  }

  exploreFilterSummary(): string {
    return this.exploreFilters.map((filter: ExploreFilterGroup) => `${filter.title}${filter.selected || '未选'}`)
      .join('，');
  }

  /** 书源提供的筛选条件（分类、状态、排序等）：分组排列，选好后点“完成”一次生效。 */
  @Builder
  exploreFilterPopupContent() {
    Column() {
      Row() {
        Text('筛选条件')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text('完成')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
          .padding({ left: AppSpacing.LG, right: AppSpacing.XS, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .onClick(() => {
            this.applyExploreFilterDrafts();
          })
      }
      .width('100%')
      .height(ExplorePage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 8 })

      Scroll() {
        Column({ space: AppSpacing.LG }) {
          ForEach(this.exploreFilterDrafts, (filter: ExploreFilterGroup) => {
            Column({ space: AppSpacing.SM }) {
              Text(filter.title)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.secondaryTextColor())
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(filter.options, (name: string) => {
                  this.exploreFilterDraftOptionChip(filter, name)
                }, (name: string): string => `${filter.title}:${name}`)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (filter: ExploreFilterGroup): string =>
            `${filter.title}:${filter.selected}:${filter.options.join('|')}`)
        }
        .width('100%')
        .padding({ left: 12, right: 4, top: AppSpacing.XS, bottom: AppSpacing.LG })
      }
      .width('100%')
      .constraintSize({ maxHeight: Math.min(420, Math.floor(this.exploreViewportHeight * 0.6)) })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width(Math.min(340, Math.max(1, this.exploreViewportWidth - 32)))
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  showsExploreChannelBar(): boolean {
    return this.getActiveEntries().length > 0 || this.showsExplorePlatformSelector();
  }

  /** 书源有多个模式（站点）或菜单分组时，频道栏左侧固定显示当前模式；筛选按钮在标题栏，两者可以并存。 */
  showsExplorePlatformSelector(): boolean {
    return this.platformNames.length > 1;
  }

  /** 标题下方唯一的一行：左侧可选的模式，右侧横滑频道，选中项强调色加下划线。 */
  @Builder
  exploreChannelBar() {
    Row() {
      if (this.exploreChannelBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.exploreChannelBarWidth,
          surfaceHeight: ExplorePage.CHANNEL_BAR_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Row() {
            if (this.showsExplorePlatformSelector()) {
              Row({ space: AppSpacing.XXS }) {
                Text(this.explorePlatformLabel(this.selectedPlatform || this.platformNames[0]))
                  .fontSize(AppFontSize.BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 96 })
                SymbolGlyph(this.showExplorePlatformMenu ? $r('sys.symbol.chevron_up') :
                  $r('sys.symbol.chevron_down'))
                  .fontSize(12)
                  .fontColor([this.secondaryTextColor()])
              }
              .height('100%')
              .padding({ left: 16, right: 8 })
              .alignItems(VerticalAlign.Center)
              .accessibilityText(`当前模式${this.explorePlatformLabel(this.selectedPlatform)}，切换模式`)
              .bindPopup(this.showExplorePlatformMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
                this.explorePlatformMenuContent()
              }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
                this.showExplorePlatformMenu = false;
              }))
              .onClick(() => {
                this.showExploreSourcePicker = false;
                this.showExploreFilterPanel = false;
                this.showExplorePlatformMenu = !this.showExplorePlatformMenu;
              })

              Divider()
                .vertical(true)
                .height(18)
                .strokeWidth(1)
                .color(ThemeRuntime.hairlineColor(this.appDarkMode))
            }

            List({ scroller: this.exploreChannelScroller }) {
              ForEach(this.getActiveEntries(), (entry: ExploreEntry, index: number) => {
                ListItem() {
                  Column({ space: 3 }) {
                    Text(entry.title)
                      .fontSize(AppFontSize.BODY_LARGE)
                      .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.selectedIndex === index ? this.accentColor() : this.secondaryTextColor())
                      .maxLines(1)
                    Stack() {
                      if (this.selectedIndex === index) {
                        Row()
                          .width(16)
                          .height(3)
                          .borderRadius(1.5)
                          .backgroundColor(this.accentColor())
                          .geometryTransition('home_explore_channel_indicator')
                      }
                    }
                    .width(16)
                    .height(3)
                  }
                  .height('100%')
                  .padding({ left: 10, right: 10, top: 6 })
                  .justifyContent(FlexAlign.Center)
                  .accessibilityText(entry.title)
                  .accessibilitySelected(this.selectedIndex === index)
                  .onClick(() => this.selectExploreEntry(index))
                }
              }, (entry: ExploreEntry, index: number): string => `${index}_${entry.title}`)
            }
            .listDirection(Axis.Horizontal)
            .layoutWeight(1)
            .height('100%')
            .padding({ left: this.showsExplorePlatformSelector() ? 0 : 6, right: this.showsExploreCategoryButton() ? 0 : 6 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            // 被裁掉的一端短淡出，滑到头的一端由系统自动关掉淡出；挨着分割线一侧不留内边距，避免淡出区再往里推。
            .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(ExplorePage.CHANNEL_FADE_LENGTH) })

            // 固定在右端、不随频道横滑：打开全部分类面板。图标与标题行的布局切换按钮区分开。
            if (this.showsExploreCategoryButton()) {
              Divider()
                .vertical(true)
                .height(18)
                .strokeWidth(1)
                .color(ThemeRuntime.hairlineColor(this.appDarkMode))

              Row() {
                SymbolGlyph($r('sys.symbol.chevron_down_circle'))
                  .fontSize(20)
                  .fontColor([this.showExploreCategorySheet ? this.accentColor() : this.primaryTextColor()])
              }
              .width(40)
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .accessibilityText('全部分类')
              .onClick(() => this.openExploreCategorySheet())
            }
          }
          .width('100%')
          .height('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(ExplorePage.CHANNEL_BAR_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.exploreChannelBarWidth) {
        this.exploreChannelBarWidth = width;
      }
    })
  }

  explorePageKeys(): string[] {
    return this.getActiveEntries().map((entry: ExploreEntry, index: number): string =>
      JSON.stringify([entry.sourceUrl, this.selectedPlatform, entry.title, entry.url, index]));
  }

  isCurrentExplorePage(key: string): boolean {
    // 空 key 是列表模式的动态当前页，只有翻页容器使用固定分类 key。
    return key === '' || key === (this.explorePageKeys()[this.selectedIndex] || '');
  }

  explorePageLoading(key: string): boolean {
    return !this.explorePages.has(key) && (!this.isCurrentExplorePage(key) || this.isLoading);
  }

  explorePageBooks(key: string): SearchBook[] {
    // 返回最近访问的分类时，保留滑入的预览，直到缓存或网络结果准备好。
    return this.isCurrentExplorePage(key) && !this.isLoading ? this.books :
      (this.explorePages.get(key)?.books || []);
  }

  explorePageSnapshot(key: string): ExplorePageSnapshot {
    const pageKey = key || this.exploreBooksPageKey;
    let snapshot = this.explorePages.get(pageKey);
    if (!snapshot) {
      snapshot = new ExplorePageSnapshot();
      this.explorePages.set(pageKey, snapshot);
    }
    return snapshot;
  }

  retainCurrentExplorePage(): void {
    const key = this.explorePageKeys()[this.selectedIndex] || '';
    if (this.isLoading || !key || key !== this.exploreBooksPageKey) return;
    const snapshot = this.explorePageSnapshot(key);
    snapshot.books = this.books;
    snapshot.shelfKeys = this.shelfBookKeys;
    snapshot.pageCount = this.explorePage;
    snapshot.hasMore = this.hasMoreExploreBooks;
    snapshot.updatedAt = this.exploreContentLoadedAt || Date.now();
    snapshot.status = this.status;
    snapshot.verificationUrl = this.verificationUrl;
    snapshot.verificationContextToken = this.verificationContextToken;
    snapshot.verificationTitle = this.verificationTitle;
    this.explorePages.delete(key);
    this.explorePages.set(key, snapshot);
    // 与持久缓存同样保留最多 80 个分类；每页仅保存结果对象和封面 URI。
    while (this.explorePages.size > 80) this.explorePages.delete(Array.from(this.explorePages.keys())[0]);
  }

  restoreExplorePage(key: string): boolean {
    const snapshot = this.explorePages.get(key);
    if (!snapshot || !ExploreResultCache.isFresh(snapshot.updatedAt)) return false;
    this.beginExploreLoad(); // 使刚离开分类尚未完成的网络/分页回调失效。
    this.exploreBooksPageKey = key;
    this.books = snapshot.books;
    this.shelfBookKeys = snapshot.shelfKeys;
    this.explorePage = snapshot.pageCount;
    this.hasMoreExploreBooks = snapshot.hasMore;
    this.exploreContentLoadedAt = snapshot.updatedAt;
    this.status = snapshot.status;
    this.verificationUrl = snapshot.verificationUrl;
    this.verificationContextToken = snapshot.verificationContextToken;
    this.verificationTitle = snapshot.verificationTitle;
    this.isLoadingMore = false;
    this.isLoading = false;
    this.syncExploreShelfStatus(this.books);
    return true;
  }

  exploreResultArrivalKey(pageKey: string, book: SearchBook): string {
    const category = pageKey || this.exploreBooksPageKey;
    return JSON.stringify([category, book.origin || '', book.bookUrl || '']);
  }

  claimExploreResultArrival(pageKey: string, book: SearchBook): number {
    if (!this.isActive || !this.isCurrentExplorePage(pageKey)) return -1;
    return this.resultArrivalTracker.claim(this.exploreResultArrivalKey(pageKey, book), Date.now());
  }

  onExploreResultReady(pageKey: string, book: SearchBook): void {
    this.resultArrivalTracker.markReady(this.exploreResultArrivalKey(pageKey, book),
      this.isActive && this.isCurrentExplorePage(pageKey), Date.now());
  }

  @Builder
  exploreResultContent(key: string) {
    if (this.explorePageLoading(key)) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
        Text('加载中...')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.MD })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: this.exploreResultTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else if (this.explorePageBooks(key).length > 0) {
      SearchBookResultList({
        sharedCoverScope: 'explore',
        books: this.explorePageBooks(key),
        coverCache: this.explorePageSnapshot(key).covers,
        initialScrollOffset: this.explorePageSnapshot(key).scrollOffset,
        claimArrival: (book: SearchBook): number => this.claimExploreResultArrival(key, book),
        onResultReady: (book: SearchBook): void => this.onExploreResultReady(key, book),
        orderedReveal: true,
        layoutMode: this.exploreListLayoutMode(key),
        showRankNumbers: this.exploreShowsRankNumbers(key),
        gridViewportWidth: this.exploreViewportWidth,
        shelfBookKeys: this.shelfBookKeys,
        busyBookKeys: this.addingShelfBookKeys,
        showLoadingMore: this.isCurrentExplorePage(key) && this.isLoadingMore,
        keepLoadingFooter: true,
        hasMoreResults: this.isCurrentExplorePage(key) ? this.hasMoreExploreBooks :
          this.explorePageSnapshot(key).hasMore,
        showKind: true,
        showResultCover: this.searchExploreShowResultCover,
        showResultCoverBackground: this.searchExploreShowResultCoverBackground,
        useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
        showResultTags: this.searchExploreShowResultTags,
        showSourceLine: false,
        pageColor: this.surfaceColor(),
        cardColor: this.glassCardColor(),
        itemBorderColor: this.glassBorderColor(),
        itemBorderWidth: 1,
        shadowColor: this.glassShadowColor(),
        primaryTextColor: this.primaryTextColor(),
        secondaryTextColor: this.secondaryTextColor(),
        subTextColor: this.subTextColor(),
        topPadding: this.exploreResultTopPadding(),
        userScrollOnly: this.usesExploreCategoryPager(),
        gridPageActive: this.isActive && this.isCurrentExplorePage(key),
        gridHeaderCollapse: this.exploreHeaderCollapseValue(),
        bottomPadding: this.resultListBottomInset(),
        onOpenBook: (book: SearchBook) => {
          this.openSearchBookDetail(book);
        },
        onReadBook: (book: SearchBook) => {
          this.readSearchBook(book);
        },
        onToggleShelf: (book: SearchBook) => {
          this.toggleSearchBookShelf(book);
        },
        onNeedMetadata: (book: SearchBook) => {
          if (this.isCurrentExplorePage(key) && !this.isLoading) this.requestExploreMetadata(book);
        },
        onReachEnd: () => {
          if (this.isCurrentExplorePage(key)) this.loadMoreExploreBooks();
        },
        onListScroll: (delta: number, offset: number) => {
          if (this.isCurrentExplorePage(key)) {
            this.explorePageSnapshot(key).scrollOffset = offset;
            this.onExploreListScroll(delta, offset);
          }
        },
        onListScrollStop: (offset: number) => {
          if (this.isCurrentExplorePage(key)) {
            this.explorePageSnapshot(key).scrollOffset = offset;
            this.onExploreListScrollStop(offset);
          }
        }
      })
    } else {
      Column() {
        Text('没有发现内容')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
        Text(this.isCurrentExplorePage(key) && this.verificationUrl ?
          '当前书源可能需要网页验证' : '请切换书源或网站，或检查已启用书源的发现地址')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.MD })
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
        if (this.isCurrentExplorePage(key) && this.verificationUrl) {
          Button('去验证')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .borderRadius(18)
            .margin({ top: AppSpacing.LG })
            .backgroundColor(this.buttonColor())
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => {
              this.openVerification();
            })
        }
        if (this.isCurrentExplorePage(key) && this.shouldOfferExploreSourceLogin()) {
          Button(this.exploreSourceLoginButtonLabel())
            .height(36)
            .fontSize(AppFontSize.BODY)
            .borderRadius(18)
            .margin({ top: AppSpacing.LG })
            .backgroundColor(this.buttonColor())
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => {
              this.openExploreSourceLogin();
            })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: this.exploreResultTopPadding() })
      .justifyContent(FlexAlign.Center)
    }
  }

  selectExploreEntry(index: number): void {
    // 跨男频/女频分组时索引可能相同，但内容身份已经变化，仍需加载。
    if (index < 0 || index >= this.getActiveEntries().length) return;
    const targetKey = this.explorePageKeys()[index];
    if (index === this.selectedIndex && targetKey === this.exploreBooksPageKey && !this.isLoading) return;
    this.resultArrivalTracker.discardPending();
    this.retainCurrentExplorePage();
    this.selectedIndex = index;
    const entry = this.getActiveEntries()[index];
    if (entry) {
      ExploreCategoryHistoryStore.record(getContext(this), this.selectedSourceUrl,
        ExploreCategoryHistoryStore.entryKey(entry.title, entry.url));
    }
    if (!this.restoreExplorePage(targetKey)) this.loadBooks();
    try {
      this.exploreChannelScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    } catch (error) {
      console.warn('定位当前发现频道失败:', error);
    }
  }

  @Builder
  explorePlatformMenuContent() {
    Scroll() {
      Column({ space: AppSpacing.XXS }) {
        ForEach(this.platformNames, (name: string) => {
          Row() {
            Text(this.explorePlatformLabel(name))
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(this.selectedPlatform === name ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.selectedPlatform === name ? this.accentColor() : this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.selectedPlatform === name) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([this.accentColor()])
            }
          }
          .width('100%')
          .height(ExplorePage.MENU_ITEM_HEIGHT)
          .padding({ left: 12, right: 12 })
          .borderRadius(this.exploreMenuItemRadius())
          .backgroundColor(this.selectedPlatform === name ? this.exploreSelectedBackgroundColor() : '#00000000')
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.showExplorePlatformMenu = false;
            this.switchExplorePlatform(name);
          })
        }, (name: string) => name)
      }
      .width('100%')
    }
    .width(180)
    // 长分类菜单限制可视高度，超出的选项由 Scroll 承接纵向滑动。
    .constraintSize({ maxHeight: Math.min(420, Math.floor(this.exploreViewportHeight * 0.6)) })
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  exploreMenuItemRadius(): number {
    return ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING;
  }

  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  exploreSourceDropdownWidth(): number {
    // 常规设备保持稳定的 320vp；窄屏只按安全边距收窄，不再随书源或分组内容变化。
    return Math.min(320, Math.max(1, this.exploreViewportWidth - 32));
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    this.markSearchBookJoining(searchKey);
    try {
      const change = await SearchBookShelfHelper.addToShelf(getContext(this), searchBook, this.getUIContext());
      if (change.replacedKey && change.replacedKey !== change.shelfKey) {
        this.shelfStatusVersion++;
        this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.replacedKey);
      }
      this.markSearchBookInShelf(change.shelfKey);
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
    } finally {
      this.unmarkSearchBookJoining(searchKey);
    }
  }

  async readSearchBook(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) return;
    if (!this.isSearchBookInShelf(searchBook)) {
      // Use the transient reader flow; reading a search result must not add it to the shelf.
      this.openSearchBookDetail(searchBook, true);
      return;
    }
    const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(
      SearchBookShelfHelper.keyOf(searchBook), true);
    if (!shelfBook?.bookUrl) {
      HdsFeedback.showToast('书籍准备失败，请稍后重试');
      return;
    }
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: shelfBook.bookUrl } });
  }

  openExploreSourcePicker(): void {
    if (this.sourceOptions.length === 0) {
      return;
    }
    this.exploreSourceFilterInput = '';
    this.exploreSourceFilterKeyword = '';
    const selectedSource = this.sourceOptions.find((option: ExploreSourceOption): boolean =>
      option.sourceUrl === this.selectedSourceUrl);
    this.activeExploreSourceGroup = selectedSource ?
      this.exploreSourceGroupLabel(selectedSource.sourceGroup) : '__all__';
    this.refreshExploreSourceDataSource();
    this.showExploreSourcePicker = true;
    this.syncExploreSourceGroupsFromDb();
  }

  /**
   * 书源管理是另一个页面，在那里分组、改名或删组不会重载发现页，sourceOptions 里的分组会一直是旧的。
   * 打开书源下拉和分组顺序变化时从库里重读一遍分组（只查本地库、不碰网络），就地改写。
   */
  async syncExploreSourceGroupsFromDb(): Promise<void> {
    if (this.sourceOptions.length === 0) return;
    let sources: BookSource[] = [];
    try {
      sources = await AppDatabase.getInstance().getEnabledBookSourcesForExplore();
    } catch (error) {
      console.warn('同步发现书源分组失败:', error);
      return;
    }
    const groups: Map<string, string> = new Map<string, string>();
    sources.forEach((source: BookSource): void => {
      groups.set(source.bookSourceUrl, (source.bookSourceGroup || '').trim());
    });
    const selectedBefore = this.sourceOptions.find((option: ExploreSourceOption): boolean =>
      option.sourceUrl === this.selectedSourceUrl);
    const selectedLabelBefore = selectedBefore ? this.exploreSourceGroupLabel(selectedBefore.sourceGroup) : '';
    let changed = false;
    this.sourceOptions.forEach((option: ExploreSourceOption): void => {
      const group = groups.get(option.sourceUrl);
      if (group !== undefined && group !== option.sourceGroup) {
        option.sourceGroup = group;
        changed = true;
      }
    });
    if (!changed) return;
    this.exploreSourceGroups = this.buildExploreSourceGroups();
    // 下拉刚按旧分组定位到当前书源所在组；当前书源换了组就跟过去。
    if (selectedBefore && this.activeExploreSourceGroup === selectedLabelBefore) {
      this.activeExploreSourceGroup = this.exploreSourceGroupLabel(selectedBefore.sourceGroup);
    }
    if (this.activeExploreSourceGroup !== '__all__' &&
      !this.exploreSourceGroups.includes(this.activeExploreSourceGroup)) {
      this.activeExploreSourceGroup = '__all__';
    }
    this.refreshExploreSourceDataSource();
  }

  scrollExploreSourceToCurrent(): void {
    if (!this.showExploreSourcePicker || !this.selectedSourceUrl) return;
    const options = this.getFilteredExploreSourceOptions();
    const selectedIndex = options.findIndex((option: ExploreSourceOption) =>
      option.sourceUrl === this.selectedSourceUrl);
    if (selectedIndex < 0) return;
    const rowHeight = 44;
    const visibleHeight = 320;
    const targetOffset = Math.max(0, selectedIndex * rowHeight - (visibleHeight - rowHeight) / 2);
    try {
      this.exploreSourceScroller.scrollTo({ xOffset: 0, yOffset: targetOffset, animation: false });
    } catch (error) {
      console.warn('定位当前发现书源失败:', error);
    }
  }

  toggleExploreSourcePicker(): void {
    if (this.showExploreSourcePicker) {
      this.showExploreSourcePicker = false;
      this.clearExploreSourceFilter();
      return;
    }
    this.openExploreSourcePicker();
  }

  applyExploreSourceFilter(): void {
    this.exploreSourceFilterKeyword = this.exploreSourceFilterInput.trim().toLowerCase();
    this.refreshExploreSourceDataSource();
    if (this.sourceOptions.length > 0) {
      this.showExploreSourcePicker = true;
    }
  }

  clearExploreSourceFilter(): void {
    this.exploreSourceFilterInput = '';
    this.exploreSourceFilterKeyword = '';
    this.refreshExploreSourceDataSource();
  }

  openExploreSourceActions(option: ExploreSourceOption, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.exploreContextMenuX = finger.globalX;
      this.exploreContextMenuY = finger.globalY;
    }
    this.actionExploreSourceUrl = option.sourceUrl;
    this.actionExploreSourceNative = option.isNative === true;
    // 先收起书源弹出层，长按菜单再从页面上弹出。
    this.showExploreSourcePicker = false;
    this.showExploreSourceActionMenu = true;
  }

  closeExploreSourceActions(): void {
    this.showExploreSourceActionMenu = false;
    this.actionExploreSourceUrl = '';
    this.actionExploreSourceNative = false;
  }

  /** 长按菜单的源变量与删除确认框内容；在本组件里创建，系统对话框才有父节点。 */
  @Builder
  sourceVariableDialog(params: SourceVariableDialogParams) {
    SourceVariableEditor({ params: params })
  }

  @Builder
  sourceDeleteDialog(params: SourceDeleteDialogParams) {
    SourceDeleteConfirm({ params: params })
  }

  @Builder
  sourceGroupDialog(params: SourceGroupDialogParams) {
    SourceGroupEditor({ params: params })
  }

  /** 改了分组只动书源下拉：就地改这个书源的分组，重算分组小标签，不重新加载发现内容。 */
  applyExploreSourceGroupChange(sourceUrl: string, group: string): void {
    const option = this.sourceOptions.find((item: ExploreSourceOption): boolean => item.sourceUrl === sourceUrl);
    if (!option) return;
    option.sourceGroup = group;
    this.exploreSourceGroups = this.buildExploreSourceGroups();
    if (this.activeExploreSourceGroup !== '__all__' &&
      !this.exploreSourceGroups.includes(this.activeExploreSourceGroup)) {
      this.activeExploreSourceGroup = '__all__';
    }
    this.refreshExploreSourceDataSource();
  }

  /** 长按菜单的执行与搜索范围面板共用；这里只管发现页自己的刷新。 */
  runExploreSourceAction(kind: string): void {
    const sourceUrl = this.actionExploreSourceUrl;
    const isNative = this.actionExploreSourceNative;
    this.closeExploreSourceActions();
    if (!sourceUrl) return;
    if (SourceActionRunner.isNavigation(kind)) {
      SourceActionRunner.navigate(kind, sourceUrl, isNative);
    } else if (kind === SourceActionKind.VARIABLE) {
      SourceActionRunner.openVariableEditor(this.getUIContext(), sourceUrl,
        (dialogParams: SourceVariableDialogParams): CustomBuilder => (): void => {
          this.sourceVariableDialog(dialogParams);
        }, (): void => {
        if (this.isActive && !this.isLoading && this.selectedSourceUrl === sourceUrl) {
          this.loadEntries('', true);
        }
      });
    } else if (kind === SourceActionKind.GROUP) {
      SourceActionRunner.openGroupEditor(this.getUIContext(), sourceUrl,
        (dialogParams: SourceGroupDialogParams): CustomBuilder => (): void => {
          this.sourceGroupDialog(dialogParams);
        }, (group: string): void => {
        this.applyExploreSourceGroupChange(sourceUrl, group);
      });
    } else if (kind === SourceActionKind.DELETE) {
      SourceActionRunner.confirmDelete(this.getUIContext(), sourceUrl,
        (dialogParams: SourceDeleteDialogParams): CustomBuilder => (): void => {
          this.sourceDeleteDialog(dialogParams);
        }, (): void => {
        // 删除后重载发现页：若删的是当前源，loadEntries 会自动回退到首个可用源。
        if (this.isActive) {
          this.loadEntries('', true);
        }
      });
    }
  }

  getFilteredExploreSourceOptions(): ExploreSourceOption[] {
    let options = this.sourceOptions;
    if (this.activeExploreSourceGroup !== '__all__') {
      options = options.filter((option: ExploreSourceOption) =>
        this.exploreSourceGroupLabel(option.sourceGroup) === this.activeExploreSourceGroup);
    }
    const keyword = this.exploreSourceFilterKeyword;
    if (!keyword) {
      return options;
    }
    return options.filter((option: ExploreSourceOption) => {
      const searchable = `${option.sourceName || ''}\n${option.sourceUrl || ''}\n${option.sourceGroup || ''}\n${(option.platforms || []).join(' ')}`
        .toLowerCase();
      return searchable.includes(keyword);
    });
  }

  refreshExploreSourceDataSource(): void {
    this.exploreSourceDataSource.replace(this.getFilteredExploreSourceOptions());
  }

  rebuildExploreSourceDisplayNames(options: ExploreSourceOption[]): void {
    const names = SourcePickerKit.displayNames(
      options.map((option: ExploreSourceOption): string => option.sourceName),
      options.map((option: ExploreSourceOption): string => option.sourceUrl));
    const result: Map<string, string> = new Map<string, string>();
    options.forEach((option: ExploreSourceOption, index: number): void => {
      result.set(option.sourceUrl || option.sourceName, names[index]);
    });
    this.exploreSourceDisplayNames = result;
  }

  exploreSourceDisplayName(option: ExploreSourceOption): string {
    return this.exploreSourceDisplayNames.get(option.sourceUrl || option.sourceName) ||
      option.sourceName || '未命名书源';
  }

  buildExploreSourceGroups(): string[] {
    const groups: Set<string> = new Set<string>();
    for (const option of this.sourceOptions) {
      groups.add(this.exploreSourceGroupLabel(option.sourceGroup));
    }
    return SourcePickerKit.sortGroups(Array.from(groups));
  }

  exploreSourceGroupLabel(group: string): string {
    return SourcePickerKit.groupLabel(group);
  }

  selectExploreSourceGroup(groupKey: string): void {
    if (groupKey === '__all__' || this.exploreSourceGroups.includes(groupKey)) {
      this.activeExploreSourceGroup = groupKey;
      this.refreshExploreSourceDataSource();
    }
  }

  switchExploreSourceGroupBySwipe(offsetX: number): void {
    if (Math.abs(offsetX) < 36) return;
    const groups = ['__all__'].concat(this.exploreSourceGroups);
    const currentIndex = Math.max(0, groups.indexOf(this.activeExploreSourceGroup));
    const direction = offsetX < 0 ? 1 : -1;
    const targetIndex = Math.max(0, Math.min(groups.length - 1, currentIndex + direction));
    if (targetIndex !== currentIndex) {
      this.activeExploreSourceGroup = groups[targetIndex];
      this.refreshExploreSourceDataSource();
    }
  }

  switchExplorePlatform(platform: string): void {
    if (this.selectedPlatform === platform) {
      return;
    }
    this.resultArrivalTracker.discardPending();
    this.retainCurrentExplorePage();
    this.selectedPlatform = platform;
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${this.explorePlatformLabel(platform)}...`;
    AppStorage.setOrCreate('explorePlatform', platform);
    this.saveExploreSelection();
    if (this.entryGroupMode) {
      if (this.showsOverviewHome()) {
        this.status = '';
        this.startExploreOverview();
      } else if (!this.restoreExplorePage(this.explorePageKeys()[0] || '')) {
        this.loadBooks();
      }
      this.scrollExploreChannelToSelected();
    } else {
      this.loadEntries(platform, false, true);
    }
  }

  switchExploreSource(option: ExploreSourceOption): void {
    if (this.selectedSourceUrl === option.sourceUrl) {
      return;
    }
    this.selectedSourceName = option.sourceName;
    this.closeExploreFilterPanel();
    this.overviewDrilled = false;
    this.selectedSourceUrl = option.sourceUrl;
    this.entryGroupMode = false;
    this.platformNames = this.getSelectedSourcePlatforms();
    this.normalizeSelectedPlatform();
    this.selectedIndex = 0;
    this.books = [];
    this.status = `正在切换到 ${option.sourceName}...`;
    AppStorage.setOrCreate('exploreSourceUrl', option.sourceUrl);
    this.saveExploreSelection();
    this.loadEntries();
  }

  beginExploreLoad(): number {
    this.coordinator.cancelPending();
    this.exploreLoadVersion++;
    this.exploreMetadataQueue = [];
    this.exploreMetadataQueued.clear();
    this.exploreMetadataUnavailable.clear();
    this.isLoading = true;
    return this.exploreLoadVersion;
  }

  requestExploreMetadata(book: SearchBook): void {
    if (!book || (!book.bookUrl || !book.origin) || (book.author && book.coverUrl)) return;
    const key = this.exploreMetadataKey(book);
    if (!key || this.exploreMetadataQueued.has(key) || this.exploreMetadataInFlight.has(key) ||
      this.exploreMetadataUnavailable.has(key)) return;
    const task = new ExploreMetadataTask();
    task.book = book;
    task.loadVersion = this.exploreLoadVersion;
    this.exploreMetadataQueue.push(task);
    this.exploreMetadataQueued.add(key);
    this.drainExploreMetadataQueue();
  }

  private drainExploreMetadataQueue(): void {
    while (this.exploreMetadataActive < 3 && this.exploreMetadataQueue.length > 0) {
      const task = this.exploreMetadataQueue.shift();
      if (!task) return;
      const key = this.exploreMetadataKey(task.book);
      this.exploreMetadataQueued.delete(key);
      if (!key || task.loadVersion !== this.exploreLoadVersion || this.exploreMetadataInFlight.has(key)) continue;
      this.exploreMetadataInFlight.add(key);
      this.exploreMetadataActive++;
      this.enrichExploreMetadata(task).catch((error: Object): void => {
        console.warn('[ExploreMetadata] detail enrichment failed:', task.book.originName || task.book.origin,
          error instanceof Error ? error.message : String(error || 'unknown error'));
      }).finally((): void => {
        this.exploreMetadataInFlight.delete(key);
        this.exploreMetadataActive = Math.max(0, this.exploreMetadataActive - 1);
        this.drainExploreMetadataQueue();
      });
    }
  }

  private async enrichExploreMetadata(task: ExploreMetadataTask): Promise<void> {
    if (task.loadVersion !== this.exploreLoadVersion) return;
    const source = await AppDatabase.getInstance().getBookSource(task.book.origin);
    if (!source || task.loadVersion !== this.exploreLoadVersion) return;
    const needsAuthor = !task.book.author && !!(source.bookInfoRule.author || '').trim();
    const needsCover = !task.book.coverUrl && !!(source.bookInfoRule.coverUrl || '').trim();
    const key = this.exploreMetadataKey(task.book);
    if (!needsAuthor && !needsCover) {
      this.exploreMetadataUnavailable.add(key);
      return;
    }

    const detail = new Book();
    detail.bookUrl = task.book.bookUrl;
    detail.tocUrl = task.book.tocUrl;
    detail.origin = task.book.origin;
    detail.originName = task.book.originName;
    detail.name = task.book.name;
    detail.author = task.book.author;
    detail.kind = task.book.kind;
    detail.status = task.book.status;
    detail.coverUrl = task.book.coverUrl;
    detail.intro = task.book.intro;
    detail.latestChapterTitle = task.book.latestChapterTitle;
    detail.updateTime = task.book.updateTime;
    detail.wordCount = task.book.wordCount;
    detail.type = task.book.type;
    detail.variable = task.book.variable;
    const enriched = await new WebBookService().getBookInfo(source, detail);
    if (task.loadVersion !== this.exploreLoadVersion) return;
    const index = this.books.findIndex((item: SearchBook): boolean =>
      item.origin === task.book.origin && item.bookUrl === task.book.bookUrl);
    if (index < 0) return;
    const current = this.books[index];
    let changed = false;
    if (!current.author && enriched.author) {
      current.author = BookFieldSanitizer.clean(enriched.author);
      changed = !!current.author || changed;
    }
    if (!current.coverUrl && enriched.coverUrl) {
      current.coverUrl = CoverUrlNormalizer.normalize(enriched.coverUrl);
      changed = !!current.coverUrl || changed;
    }
    if (!current.status && enriched.status) {
      current.status = BookFieldSanitizer.clean(enriched.status);
      changed = !!current.status || changed;
    }
    if (!current.updateTime && enriched.updateTime) {
      current.updateTime = BookFieldSanitizer.clean(enriched.updateTime);
      changed = !!current.updateTime || changed;
    }
    if (changed) this.books = this.books.slice();
    if ((!needsAuthor || !!current.author) && (!needsCover || !!current.coverUrl)) {
      this.exploreMetadataUnavailable.add(key);
    }
  }

  private exploreMetadataKey(book: SearchBook): string {
    return `${book.origin || ''}|${book.bookUrl || ''}`;
  }

  isCurrentExploreLoad(loadVersion: number): boolean {
    return loadVersion === this.exploreLoadVersion;
  }

  finishExploreLoad(loadVersion: number): void {
    if (this.isCurrentExploreLoad(loadVersion)) {
      this.isLoading = false;
      this.retainCurrentExplorePage();
    }
  }

  normalizeSelectedPlatform(): void {
    if (this.platformNames.length === 0) {
      return;
    }
    if (!this.platformNames.includes(this.selectedPlatform)) {
      // 兼容旧版保存的“男频/女频”等原始分组名称。
      const legacyGroup = this.entryGroupKey(this.selectedPlatform);
      this.selectedPlatform = this.entryGroupMode && this.platformNames.includes(legacyGroup) ?
        legacyGroup : this.platformNames[0];
      AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
      this.saveExploreSelection();
    }
  }

  async restoreExploreSelectionFromSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      const storedSourceUrl = settings.exploreSourceUrl || AppStorage.get<string>('exploreSourceUrl') || '';
      const storedPlatform = settings.explorePlatform || AppStorage.get<string>('explorePlatform') || '';
      if (storedSourceUrl) {
        this.selectedSourceUrl = storedSourceUrl;
        settings.exploreSourceUrl = storedSourceUrl;
      }
      if (storedPlatform) {
        this.selectedPlatform = storedPlatform;
        settings.explorePlatform = storedPlatform;
      }
      SearchExploreSettingsStore.applyToStorage(settings);
    } catch (e) {
      console.warn('恢复发现页选择失败:', e);
    }
  }

  /** 发现内容和搜索层的结果共用这一个布局设置（搜索层直接读 exploreResultLayout）。 */
  applyResultLayout(layout: string): void {
    const previous = this.exploreResultLayout;
    this.exploreResultLayout = layout;
    SearchExploreSettingsStore.saveResultLayout(
      getContext(this), SearchExploreSettingsStore.KEY_EXPLORE_RESULT_LAYOUT, layout
    ).catch((e: Error) => {
      console.warn('保存结果布局失败:', e);
    });
    if (previous === layout) return;
    this.exploreHeaderCollapse = 0;
    this.exploreHeaderBackdropReveal = 0;
    if (layout === ExploreRankStyle.LAYOUT_OVERVIEW) {
      this.overviewDrilled = false;
      this.startExploreOverview();
      return;
    }
    if (previous === ExploreRankStyle.LAYOUT_OVERVIEW) {
      this.cancelExploreOverview();
      this.overviewDrilled = false;
      this.ensureCurrentExploreEntryLoaded();
    }
    if (layout === ExploreRankStyle.LAYOUT_SIDEBAR) {
      this.scrollExploreRailToSelected();
    } else {
      this.scrollExploreChannelToSelected();
    }
  }

  saveExploreSelection(): void {
    AppStorage.setOrCreate('exploreSourceUrl', this.selectedSourceUrl);
    AppStorage.setOrCreate('explorePlatform', this.selectedPlatform);
    SearchExploreSettingsStore.saveExploreSelection(
      getContext(this),
      this.selectedSourceUrl,
      this.selectedPlatform
    ).catch((e: Error) => {
      console.warn('保存发现页选择失败:', e);
    });
  }

  async syncExploreShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const loadVersion = this.exploreLoadVersion;
      const keys = await this.loadExploreShelfKeys(books);
      if (version === this.shelfStatusVersion && this.isCurrentExploreLoad(loadVersion)) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步发现书架状态失败:', e);
    }
  }

  async loadExploreShelfKeys(books: SearchBook[]): Promise<string[]> {
    return await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys);
  }

  isSearchBookJoiningShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isBusy(book, this.addingShelfBookKeys);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) {
      return;
    }

    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    try {
      const change = await SearchBookShelfHelper.removeFromShelf(getContext(this), searchBook);
      this.shelfStatusVersion++;
      this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
    } catch (e) {
      console.error('移出书架失败:', e);
      HdsFeedback.showToast('移出书架失败');
    }
  }

  markSearchBookInShelf(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.shelfBookKeys, bookKey);
    if (next !== this.shelfBookKeys) {
      this.shelfStatusVersion++;
      this.shelfBookKeys = next;
    }
  }

  markSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  unmarkSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withoutKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  shouldShowExploreStatus(): boolean {
    if (!this.status) {
      return false;
    }
    // 总览首屏的加载和失败都显示在各自的卡片里。
    if (this.showsOverviewHome() && this.getActiveEntries().length > 0) {
      return false;
    }
    if (this.verificationUrl) {
      return true;
    }
    return this.books.length === 0;
  }

  getSelectedSourcePlatforms(): string[] {
    const option = this.getSelectedSourceOption();
    return option ? option.platforms : [];
  }

  getSelectedSourceUrl(): string {
    const option = this.getSelectedSourceOption();
    return option ? option.sourceUrl : '';
  }

  getSelectedSourceOption(): ExploreSourceOption | null {
    for (const option of this.sourceOptions) {
      if (option.sourceUrl === this.selectedSourceUrl) return option;
    }
    return null;
  }

  getSelectedSiteLabel(): string {
    return this.platformNames.length > 0 ? this.explorePlatformLabel(this.selectedPlatform) : this.selectedSourceName;
  }

  openVerification(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) {
      HdsFeedback.showToast('暂无需要验证的网页');
      return;
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证',
        verificationContextToken: this.verificationContextToken
      }
    });
  }

  getActiveEntries(): ExploreEntry[] {
    const sourceEntries = !this.selectedSourceUrl ? this.entries :
      this.entries.filter(entry => entry.sourceUrl === this.selectedSourceUrl);
    if (!this.selectedPlatform) return sourceEntries;
    if (this.entryGroupMode) {
      return sourceEntries.filter((entry: ExploreEntry): boolean =>
        this.entryGroupKey(entry.groupTitle || '') === this.selectedPlatform);
    }
    const hasSelectedGroup = sourceEntries.some((entry: ExploreEntry): boolean =>
      (entry.groupTitle || '') === this.selectedPlatform);
    return hasSelectedGroup ? sourceEntries.filter((entry: ExploreEntry): boolean =>
      (entry.groupTitle || '') === this.selectedPlatform) : sourceEntries;
  }

  /** 当前书源已加载的全部分类（不按模式过滤），供全部分类面板分组展示。 */
  exploreCategoryEntries(): ExploreEntry[] {
    return !this.selectedSourceUrl ? this.entries :
      this.entries.filter((entry: ExploreEntry): boolean => entry.sourceUrl === this.selectedSourceUrl);
  }

  showsExploreCategoryButton(): boolean {
    return this.exploreCategoryEntries().length >= ExplorePage.CATEGORY_SHEET_MIN_COUNT;
  }

  exploreCategoryItems(): ExploreCategoryItem[] {
    const items: ExploreCategoryItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const entry of this.exploreCategoryEntries()) {
      const key = ExploreCategoryHistoryStore.entryKey(entry.title, entry.url);
      if (seen.has(key)) continue;
      seen.add(key);
      items.push({ key: key, title: entry.title, groupTitle: entry.groupTitle || '' });
    }
    return items;
  }

  currentExploreEntryKey(): string {
    const entries = this.getActiveEntries();
    if (entries.length === 0) return '';
    const entry = entries[Math.min(Math.max(0, this.selectedIndex), entries.length - 1)];
    return ExploreCategoryHistoryStore.entryKey(entry.title, entry.url);
  }

  async openExploreCategorySheet(): Promise<void> {
    this.showExploreSourcePicker = false;
    this.showExploreFilterPanel = false;
    this.showExplorePlatformMenu = false;
    // “最近”要在面板创建时就有数据，先确保本机记录已读入。
    await ExploreCategoryHistoryStore.load(getContext(this));
    this.showExploreCategorySheet = true;
  }

  /**
   * 面板里点选分类。分类属于另一个已加载的分组（左侧模式）时先切到该分组，分组内容已在内存里，不必重新加载。
   */
  selectExploreCategory(key: string): void {
    const matches = (entry: ExploreEntry): boolean =>
      ExploreCategoryHistoryStore.entryKey(entry.title, entry.url) === key;
    const entry = this.exploreCategoryEntries().find(matches);
    if (entry) this.retainCurrentExplorePage();
    const previousPlatform = this.selectedPlatform;
    const index = entry ? this.restoreExploreCategory(key) : -1;
    if (index < 0) {
      HdsFeedback.showToast('分类已更新，请刷新后重试');
      return;
    }
    const platformChanged = previousPlatform !== this.selectedPlatform;
    this.showExploreCategorySheet = false;
    if (!platformChanged && index === this.selectedIndex) {
      ExploreCategoryHistoryStore.record(getContext(this), this.selectedSourceUrl, key);
      return;
    }
    this.selectExploreEntry(index);
    // 切换分组后频道栏会重建，等它布局完再滚到选中项。
    this.scrollExploreChannelToSelected();
  }

  scrollExploreChannelToSelected(): void {
    if (this.isSidebarLayout()) {
      this.scrollExploreRailToSelected();
      return;
    }
    setTimeout(() => {
      try {
        this.exploreChannelScroller.scrollToIndex(this.selectedIndex, true, ScrollAlign.CENTER);
      } catch (error) {
        console.warn('定位当前发现频道失败:', error);
      }
    }, 0);
  }

  getEntryGroupNames(entries: ExploreEntry[]): string[] {
    const names: string[] = [];
    for (const entry of entries) {
      const name = this.entryGroupKey(entry.groupTitle || '');
      if (!names.includes(name)) names.push(name);
    }
    return names;
  }

  entryGroupKey(title: string): string {
    return ExplorePage.ENTRY_GROUP_PREFIX + title.trim();
  }

  explorePlatformLabel(platform: string): string {
    if (!this.entryGroupMode) return platform;
    const title = platform.substring(ExplorePage.ENTRY_GROUP_PREFIX.length);
    if (title) return title;
    return this.platformNames.includes(this.entryGroupKey('其他')) ? '其他（未分组）' : '其他';
  }

  /** 从全量菜单恢复分组，再在该分组中定位；点击和重新加载共用此路径。 */
  restoreExploreCategory(key: string): number {
    const matches = (entry: ExploreEntry): boolean =>
      ExploreCategoryHistoryStore.entryKey(entry.title, entry.url) === key;
    const entry = this.exploreCategoryEntries().find(matches);
    if (!entry) return -1;
    const group = this.entryGroupMode ? this.entryGroupKey(entry.groupTitle || '') :
      (entry.groupTitle || '').trim();
    if (group && group !== this.selectedPlatform && this.platformNames.includes(group)) {
      this.selectedPlatform = group;
      this.saveExploreSelection();
    }
    return this.getActiveEntries().findIndex(matches);
  }

  /** 左右滑动切频道只在横向频道栏的布局里有；侧栏和总览没有频道栏，也就不翻页。 */
  usesExploreCategoryPager(): boolean {
    return this.getActiveEntries().length > 0 && !this.isOverviewLayout() && !this.isSidebarLayout();
  }

  exploreResultTopPadding(): number {
    // 固定滚动内容尺寸，避免收起量改变留白后触发新的滚动回调，导致顶栏来回抖动。
    return this.exploreTopOverlayHeight();
  }

  /** 平铺分类共享顶栏状态，分类加载中或为空时保持原来的收起量。 */
  exploreHeaderCollapseValue(): number {
    return this.usesExploreCategoryPager() || this.showsOverviewHome() || (!this.isLoading && this.books.length > 0) ?
      Math.min(this.exploreHeaderCollapse, this.exploreCollapsibleHeight()) : 0;
  }

  onExploreListScroll(delta: number, offset: number): void {
    const reveal = CollapsingHeader.backdropReveal(offset);
    if (reveal !== this.exploreHeaderBackdropReveal) this.exploreHeaderBackdropReveal = reveal;
    if (this.usesExploreCategoryPager() && offset <= 0 && delta >= 0) return;
    const next = CollapsingHeader.next(this.exploreHeaderCollapse, delta,
      this.usesExploreCategoryPager() ? this.exploreCollapsibleHeight() : offset, this.exploreCollapsibleHeight());
    if (next !== this.exploreHeaderCollapse) {
      this.exploreHeaderCollapse = next;
    }
  }

  onExploreListScrollStop(offset: number): void {
    const target = CollapsingHeader.settle(this.exploreHeaderCollapse,
      this.usesExploreCategoryPager() ? this.exploreCollapsibleHeight() : offset, this.exploreCollapsibleHeight());
    if (target !== this.exploreHeaderCollapse) {
      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.exploreHeaderCollapse = target;
      });
    }
  }

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。 */
  exploreTopOverlayHeight(): number {
    let height = this.statusBarHeight + this.exploreCollapsibleHeight();
    if (this.showsExploreSecondaryBar()) {
      height += ExplorePage.CHANNEL_BAR_HEIGHT + AppSpacing.MD;
    }
    if (this.shouldShowExploreStatus()) {
      height += 40;
    }
    return height;
  }

  copyExploreFilterGroups(filters: ExploreFilterGroup[]): ExploreFilterGroup[] {
    const copies: ExploreFilterGroup[] = [];
    for (const filter of filters) {
      copies.push({
        title: filter.title,
        options: filter.options.slice(),
        selected: filter.selected
      });
    }
    return copies;
  }

  openExploreFilterPanel(): void {
    this.exploreFilterDrafts = this.copyExploreFilterGroups(this.exploreFilters);
    this.showExploreFilterPanel = true;
  }

  closeExploreFilterPanel(): void {
    this.showExploreFilterPanel = false;
    this.exploreFilterDrafts = [];
  }

  toggleExploreFilterPanel(): void {
    if (this.showExploreFilterPanel) {
      this.closeExploreFilterPanel();
    } else {
      this.openExploreFilterPanel();
    }
  }

  selectExploreFilterDraft(title: string, selection: string): void {
    const next: ExploreFilterGroup[] = [];
    for (const filter of this.exploreFilterDrafts) {
      next.push({
        title: filter.title,
        options: filter.options.slice(),
        selected: filter.title === title ? selection : filter.selected
      });
    }
    this.exploreFilterDrafts = next;
  }

  async applyExploreFilterDrafts(): Promise<void> {
    const drafts = this.copyExploreFilterGroups(this.exploreFilterDrafts);
    const changed: ExploreFilterGroup[] = [];
    for (const draft of drafts) {
      const applied = this.exploreFilters.find((filter: ExploreFilterGroup): boolean =>
        filter.title === draft.title);
      if (applied && applied.selected !== draft.selected) changed.push(draft);
    }
    this.closeExploreFilterPanel();
    if (changed.length === 0 || this.isLoading || !this.selectedSourceUrl) return;

    this.status = '正在应用筛选条件...';
    this.books = [];
    this.isLoading = true;
    const failedTitles: string[] = [];
    for (const filter of changed) {
      const applied = await this.coordinator.applyExploreFilter(
        this.selectedSourceUrl, filter.title, filter.selected);
      if (!applied) failedTitles.push(filter.title);
    }
    this.isLoading = false;
    this.selectedPlatform = '';
    await this.loadEntries('', true);
    if (failedTitles.length > 0) {
      this.status = `${failedTitles.join('、')}筛选条件应用失败`;
    }
  }

  @Builder
  exploreFilterDraftOptionChip(filter: ExploreFilterGroup, name: string) {
    Text(name)
      .fontSize(AppFontSize.BODY)
      .fontWeight(filter.selected === name ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(filter.selected === name ? this.accentColor() : this.primaryTextColor())
      .height(32)
      .maxLines(1)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .backgroundColor(filter.selected === name ? this.exploreSelectedBackgroundColor() :
        ThemeRuntime.softFillColor(this.appDarkMode))
      .borderRadius(16)
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .onClick(() => {
        if (filter.selected !== name) this.selectExploreFilterDraft(filter.title, name);
      })
  }

  // ---------- 结果布局：排行、榜单总览、侧栏 ----------

  isOverviewLayout(): boolean {
    return this.exploreResultLayout === ExploreRankStyle.LAYOUT_OVERVIEW;
  }

  isSidebarLayout(): boolean {
    return this.exploreResultLayout === ExploreRankStyle.LAYOUT_SIDEBAR;
  }

  /** 总览布局且没有点进某个榜单：显示榜单卡片和分类宫格。 */
  showsOverviewHome(): boolean {
    return this.isOverviewLayout() && !this.overviewDrilled;
  }

  /** 标题下面那一行：频道栏；侧栏和总览只在书源有多个模式时显示模式栏；总览点进去后是返回栏。 */
  showsExploreSecondaryBar(): boolean {
    if (this.isOverviewLayout() && this.overviewDrilled) return true;
    if (this.isOverviewLayout() || this.isSidebarLayout()) return this.showsExplorePlatformSelector();
    return this.showsExploreChannelBar();
  }

  exploreLayoutLabel(): string {
    switch (this.exploreResultLayout) {
      case ExploreRankStyle.LAYOUT_GRID:
        return '平铺';
      case ExploreRankStyle.LAYOUT_RANK:
        return '排行';
      case ExploreRankStyle.LAYOUT_OVERVIEW:
        return '榜单总览';
      case ExploreRankStyle.LAYOUT_SIDEBAR:
        return '侧栏';
      default:
        return '列表';
    }
  }

  /** 空 key 表示当前频道。 */
  exploreEntryTitleForKey(key: string): string {
    const entries = this.getActiveEntries();
    const index = key ? this.explorePageKeys().indexOf(key) : this.selectedIndex;
    return index >= 0 && index < entries.length ? entries[index].title : '';
  }

  /**
   * 排行和侧栏是用户自己选的按名次看，所有频道都编号（排行另有领奖台），名次就是书源返回顺序；
   * 频道名猜不全榜单（“热门”“月票”“完本”等不带“榜”字），不再拿它决定编不编号。
   * 总览点进去时才按频道名分：榜单用排行，分类用列表。
   */
  exploreShowsRankNumbers(key: string): boolean {
    if (this.isOverviewLayout()) return ExploreRankStyle.isBoardTitle(this.exploreEntryTitleForKey(key));
    return true;
  }

  /** 结果列表组件的样式：总览点进榜单用排行，点进分类用列表。 */
  exploreListLayoutMode(key: string): string {
    switch (this.exploreResultLayout) {
      case ExploreRankStyle.LAYOUT_GRID:
        return ExploreRankStyle.LAYOUT_GRID;
      case ExploreRankStyle.LAYOUT_RANK:
        return ExploreRankStyle.LAYOUT_RANK;
      case ExploreRankStyle.LAYOUT_SIDEBAR:
        return ExploreRankStyle.LIST_MODE_RANK_COMPACT;
      case ExploreRankStyle.LAYOUT_OVERVIEW:
        return ExploreRankStyle.isBoardTitle(this.exploreEntryTitleForKey(key)) ?
          ExploreRankStyle.LAYOUT_RANK : ExploreRankStyle.LAYOUT_LIST;
      default:
        return ExploreRankStyle.LAYOUT_LIST;
    }
  }

  /** 从总览切到别的布局时，当前频道可能还没加载过。 */
  ensureCurrentExploreEntryLoaded(): void {
    const key = this.explorePageKeys()[this.selectedIndex] || '';
    if (!key || this.isLoading || key === this.exploreBooksPageKey) return;
    if (!this.restoreExplorePage(key)) this.loadBooks();
  }

  /**
   * 侧栏和总览点进去后只显示当前频道。外面套一层按页键的 ForEach：换频道时重建结果列表，
   * 滚动位置和封面缓存跟着各自频道走，不会停在上一个频道滚到的位置。
   */
  @Builder
  exploreCurrentResultContent() {
    Column() {
      ForEach([this.explorePageKeys()[this.selectedIndex] || ''], (pageKey: string) => {
        this.exploreResultContent(pageKey)
      }, (pageKey: string): string => pageKey || 'current')
    }
    .layoutWeight(1)
    .height('100%')
  }

  // ---------- 侧栏 ----------

  exploreSidebarSections(): ExploreSidebarSection[] {
    const entries = this.getActiveEntries();
    const groupTitles: string[] = [];
    for (const entry of entries) {
      const title = (entry.groupTitle || '').trim();
      if (!groupTitles.includes(title)) groupTitles.push(title);
    }
    const sections: ExploreSidebarSection[] = [];
    if (groupTitles.length > 1) {
      for (const title of groupTitles) {
        const section = new ExploreSidebarSection();
        section.key = `group:${title}`;
        section.title = title || '其他';
        entries.forEach((entry: ExploreEntry, index: number): void => {
          if ((entry.groupTitle || '').trim() === title) section.indices.push(index);
        });
        sections.push(section);
      }
      return sections;
    }
    const boards = new ExploreSidebarSection();
    boards.key = 'boards';
    boards.title = '榜单';
    const categories = new ExploreSidebarSection();
    categories.key = 'categories';
    categories.title = '分类';
    entries.forEach((entry: ExploreEntry, index: number): void => {
      if (ExploreRankStyle.isBoardTitle(entry.title)) {
        boards.indices.push(index);
      } else {
        categories.indices.push(index);
      }
    });
    if (boards.indices.length > 0 && categories.indices.length > 0) return [boards, categories];
    const all = new ExploreSidebarSection();
    all.key = 'all';
    all.indices = entries.map((_entry: ExploreEntry, index: number): number => index);
    return [all];
  }

  scrollExploreRailToSelected(): void {
    if (!this.isSidebarLayout()) return;
    setTimeout(() => {
      const sections = this.exploreSidebarSections();
      for (let group = 0; group < sections.length; group++) {
        const item = sections[group].indices.indexOf(this.selectedIndex);
        if (item < 0) continue;
        try {
          // 第 0 项是顶部留白，分组从 1 起。
          this.exploreRailScroller.scrollToItemInGroup(group + 1, item, true, ScrollAlign.CENTER);
        } catch (error) {
          console.warn('定位当前发现频道失败:', error);
        }
        return;
      }
    }, 0);
  }

  /** 左侧竖排频道：顶部留白跟着标题行收起，频道多时自己上下滑。 */
  @Builder
  exploreSidebarRail() {
    List({ scroller: this.exploreRailScroller, space: 2 }) {
      ListItem() {
        Row()
          .width('100%')
          .height(Math.max(0, this.exploreTopOverlayHeight() - this.exploreHeaderCollapseValue()))
      }

      ForEach(this.exploreSidebarSections(), (section: ExploreSidebarSection) => {
        ListItemGroup({ header: this.exploreRailHeader(section.title) }) {
          ForEach(section.indices, (index: number) => {
            ListItem() {
              this.exploreRailItem(index)
            }
          }, (index: number): string => `${index}_${this.exploreEntryTitleAt(index)}`)
        }
      }, (section: ExploreSidebarSection): string => `${section.key}:${section.indices.join(',')}`)

      ListItem() {
        Row()
          .width('100%')
          .height(this.resultListBottomInset())
      }
    }
    .width(ExplorePage.SIDEBAR_RAIL_WIDTH)
    .height('100%')
    .padding({ left: AppSpacing.MD, right: AppSpacing.XS })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  exploreRailHeader(title: string) {
    if (title) {
      Text(title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 10, right: 4, top: AppSpacing.MD, bottom: AppSpacing.XS })
    }
  }

  @Builder
  exploreRailItem(index: number) {
    Text(this.exploreEntryTitleAt(index))
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selectedIndex === index ? this.accentColor() : this.secondaryTextColor())
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 10, right: 6, top: 9, bottom: 9 })
      .borderRadius(12)
      .backgroundColor(this.selectedIndex === index ? this.glassCardColor() : '#00000000')
      .accessibilityText(this.exploreEntryTitleAt(index))
      .accessibilitySelected(this.selectedIndex === index)
      .onClick(() => this.selectExploreEntry(index))
  }

  exploreEntryTitleAt(index: number): string {
    const entries = this.getActiveEntries();
    return index >= 0 && index < entries.length ? entries[index].title : '';
  }

  /** 侧栏和总览没有频道栏，书源有多个模式（站点、男女频等）时用这一行切换。 */
  @Builder
  explorePlatformBar() {
    Row() {
      if (this.exploreChannelBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.exploreChannelBarWidth,
          surfaceHeight: ExplorePage.CHANNEL_BAR_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          List() {
            ForEach(this.platformNames, (name: string) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(this.explorePlatformLabel(name))
                    .fontSize(AppFontSize.BODY_LARGE)
                    .fontWeight(this.selectedPlatform === name ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.selectedPlatform === name ? this.accentColor() : this.secondaryTextColor())
                    .maxLines(1)
                  Row()
                    .width(16)
                    .height(3)
                    .borderRadius(1.5)
                    .backgroundColor(this.accentColor())
                    .opacity(this.selectedPlatform === name ? 1 : 0)
                }
                .height('100%')
                .padding({ left: 10, right: 10, top: 6 })
                .justifyContent(FlexAlign.Center)
                .accessibilityText(this.explorePlatformLabel(name))
                .accessibilitySelected(this.selectedPlatform === name)
                .onClick(() => this.switchExplorePlatform(name))
              }
            }, (name: string): string => name)
          }
          .listDirection(Axis.Horizontal)
          .width('100%')
          .height('100%')
          .padding({ left: 6, right: 6 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(ExplorePage.CHANNEL_BAR_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.exploreChannelBarWidth) {
        this.exploreChannelBarWidth = width;
      }
    })
  }

  // ---------- 榜单总览 ----------

  /** 点进总览里的某个榜单或分类：沿用普通的频道加载，总览卡片已拿到的结果会直接复用。 */
  openOverviewEntry(index: number): void {
    this.exploreHeaderCollapse = 0;
    this.exploreHeaderBackdropReveal = 0;
    this.overviewDrilled = true;
    this.selectExploreEntry(index);
  }

  onOverviewDrillActiveChanged(): void {
    if (this.overviewDrilled) return;
    this.exploreHeaderCollapse = 0;
    this.exploreHeaderBackdropReveal = 0;
    if (this.showsOverviewHome()) this.requestOverviewCards(this.overviewVisibleEnd);
  }

  /** 点进总览后标题下面的返回栏：整行点了都回总览。 */
  @Builder
  exploreOverviewDrillBar() {
    Row() {
      if (this.exploreChannelBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.exploreChannelBarWidth,
          surfaceHeight: ExplorePage.CHANNEL_BAR_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Row({ space: AppSpacing.SM }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontColor([this.primaryTextColor()])
            Text(this.exploreEntryTitleAt(this.selectedIndex))
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
            Blank()
            Text('返回总览')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .flexShrink(0)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 16 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText(`${this.exploreEntryTitleAt(this.selectedIndex)}，返回榜单总览`)
          .onClick(() => {
            this.overviewDrilled = false;
          })
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(ExplorePage.CHANNEL_BAR_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.exploreChannelBarWidth) {
        this.exploreChannelBarWidth = width;
      }
    })
  }

  /** 总览里做成卡片的频道：名字带“榜”的；一个都没有时取前几个频道做预览。 */
  overviewBoardIndices(): number[] {
    const entries = this.getActiveEntries();
    const boards: number[] = [];
    entries.forEach((entry: ExploreEntry, index: number): void => {
      if (ExploreRankStyle.isBoardTitle(entry.title)) boards.push(index);
    });
    if (boards.length > 0) return boards.slice(0, ExplorePage.OVERVIEW_MAX_BOARDS);
    const count = Math.min(ExplorePage.OVERVIEW_PREVIEW_FALLBACK, entries.length);
    const preview: number[] = [];
    for (let index = 0; index < count; index++) preview.push(index);
    return preview;
  }

  overviewHasBoards(): boolean {
    return this.getActiveEntries().some((entry: ExploreEntry): boolean => ExploreRankStyle.isBoardTitle(entry.title));
  }

  /** 其余频道（含超出卡片数量的榜单）放进下面的宫格。 */
  overviewCategoryIndices(): number[] {
    const boards = this.overviewBoardIndices();
    const result: number[] = [];
    this.getActiveEntries().forEach((_entry: ExploreEntry, index: number): void => {
      if (!boards.includes(index)) result.push(index);
    });
    return result;
  }

  startExploreOverview(): void {
    this.cancelExploreOverview();
    this.overviewCards = new Map();
    this.overviewVisibleEnd = 1;
    this.requestOverviewCards(1);
  }

  /** 停掉在途的卡片加载；加载到一半的卡片退回未请求，回来时再要。 */
  cancelExploreOverview(): void {
    this.overviewGeneration++;
    this.overviewQueue = [];
    for (const worker of this.overviewWorkers) worker.cancelPending();
    let changed = false;
    const next = new Map<string, ExploreOverviewCard>();
    this.overviewCards.forEach((card: ExploreOverviewCard, key: string): void => {
      if (card.state === 'loading') {
        changed = true;
        return;
      }
      next.set(key, card);
    });
    if (changed) this.overviewCards = next;
  }

  /** 加载已经滑到的卡片和下一张；visibleEnd 是卡片序号（不是频道序号）。 */
  requestOverviewCards(visibleEnd: number): void {
    if (!this.showsOverviewHome() || !this.isActive) return;
    this.overviewVisibleEnd = Math.max(this.overviewVisibleEnd, visibleEnd);
    const indices = this.overviewBoardIndices();
    const keys = this.explorePageKeys();
    for (let position = 0; position < indices.length && position <= this.overviewVisibleEnd; position++) {
      const index = indices[position];
      const card = this.overviewCards.get(keys[index] || '');
      if ((!card || card.state === 'idle') && !this.overviewQueue.includes(index)) this.overviewQueue.push(index);
    }
    this.drainOverviewQueue();
  }

  private drainOverviewQueue(): void {
    for (let worker = 0; worker < this.overviewWorkers.length; worker++) {
      if (this.overviewWorkerBusy[worker] || this.overviewQueue.length === 0) continue;
      const index = this.overviewQueue.shift();
      if (index === undefined) return;
      this.overviewWorkerBusy[worker] = true;
      this.loadOverviewCard(worker, index, this.overviewGeneration).catch((error: Object): void => {
        console.warn('加载榜单总览失败:', error instanceof Error ? error.message : String(error));
      }).finally((): void => {
        this.overviewWorkerBusy[worker] = false;
        this.drainOverviewQueue();
      });
    }
  }

  setOverviewCard(key: string, state: string, books: SearchBook[], message: string): void {
    const card = new ExploreOverviewCard();
    card.state = state;
    card.books = books;
    card.message = message;
    const next = new Map<string, ExploreOverviewCard>(this.overviewCards);
    next.set(key, card);
    this.overviewCards = next;
  }

  /** 先用内存里的分类结果和发现缓存，没有再请求第一页；拿到的结果写进缓存，点进去时不用再等。 */
  private async loadOverviewCard(worker: number, index: number, generation: number): Promise<void> {
    const entries = this.getActiveEntries();
    const entry = index < entries.length ? entries[index] : undefined;
    const key = this.explorePageKeys()[index] || '';
    if (!entry || !key || generation !== this.overviewGeneration) return;
    const existing = this.overviewCards.get(key);
    if (existing && existing.state !== 'idle') return;
    this.setOverviewCard(key, 'loading', [], '');
    const platform = this.selectedPlatform;
    let books: SearchBook[] = [];
    const snapshot = this.explorePages.get(key);
    if (snapshot && snapshot.books.length > 0 && ExploreResultCache.isFresh(snapshot.updatedAt)) {
      books = snapshot.books;
    } else {
      try {
        const cached = await ExploreResultCache.load(getContext(this), entry.sourceUrl, platform, entry.title, entry.url);
        if (cached) books = cached.books;
      } catch (cacheError) {
        console.warn('读取发现内容缓存失败，改用网络加载:', cacheError);
      }
    }
    if (generation !== this.overviewGeneration) return;
    if (books.length === 0) {
      const coordinator = this.overviewWorkers[worker];
      try {
        books = await coordinator.explore(entry, 1);
      } catch (error) {
        if (generation === this.overviewGeneration) this.setOverviewCard(key, 'failed', [], '加载失败，点开重试');
        return;
      }
      if (generation !== this.overviewGeneration) return;
      if (books.length === 0) {
        const needsVerify = !!(AppStorage.get<string>('pendingVerificationUrl') || '');
        const message = needsVerify ? '需要网页验证，点开处理' : (coordinator.getNoticeMessage() || '暂无内容');
        this.setOverviewCard(key, 'failed', [], message);
        return;
      }
      this.rememberOverviewBooks(key, entry, platform, books);
    }
    this.setOverviewCard(key, 'ready', books, '');
  }

  private rememberOverviewBooks(key: string, entry: ExploreEntry, platform: string, books: SearchBook[]): void {
    if (!this.explorePages.has(key)) {
      const snapshot = new ExplorePageSnapshot();
      snapshot.books = books;
      snapshot.pageCount = 1;
      snapshot.hasMore = true;
      snapshot.updatedAt = Date.now();
      this.explorePages.set(key, snapshot);
    }
    const context = getContext(this);
    this.overviewCacheChain = this.overviewCacheChain.then((): Promise<void> =>
      ExploreResultCache.save(context, entry.sourceUrl, platform, entry.title, entry.url, books, 1, true)
    ).catch((cacheError: Object): void => {
      console.warn('保存发现内容缓存失败:', cacheError);
    });
  }

  overviewCardWidth(): number {
    return Math.min(ExplorePage.OVERVIEW_CARD_MAX_WIDTH, Math.floor(this.exploreViewportWidth * 0.8));
  }

  overviewChipWidth(): number {
    const gap = AppSpacing.SM;
    return Math.max(80, Math.floor((this.exploreViewportWidth - AppSpacing.XL * 2 - gap * 2) / 3));
  }

  /** 总览首屏：横滑的榜单卡片，下面是其余频道的宫格。 */
  @Builder
  exploreOverviewHome() {
    Scroll(this.exploreOverviewScroller) {
      Column() {
        Row()
          .width('100%')
          .height(this.exploreTopOverlayHeight())

        this.overviewSectionHeader(this.overviewHasBoards() ? '榜单' : '频道速览',
          this.overviewBoardIndices().length > 1 ? '左右滑动' : '')

        List({ space: AppSpacing.MD }) {
          ForEach(this.overviewBoardIndices(), (index: number, position: number) => {
            ListItem() {
              this.overviewBoardCard(index, position)
            }
          }, (index: number): string => this.explorePageKeys()[index] || `${index}`)
        }
        .listDirection(Axis.Horizontal)
        .scrollSnapAlign(ScrollSnapAlign.START)
        .contentStartOffset(AppSpacing.XL)
        .contentEndOffset(AppSpacing.XL)
        .width('100%')
        .height(ExplorePage.OVERVIEW_CARD_HEIGHT + 8)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((_start: number, end: number) => {
          this.requestOverviewCards(end + 1);
        })

        if (this.overviewCategoryIndices().length > 0) {
          this.overviewSectionHeader(this.overviewHasBoards() ? '分类' : '更多频道', '')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.overviewCategoryIndices(), (index: number) => {
              this.overviewCategoryChip(index)
            }, (index: number): string => this.explorePageKeys()[index] || `${index}`)
          }
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL - AppSpacing.SM })
        }

        Row()
          .width('100%')
          .height(this.resultListBottomInset())
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll((_xOffset: number, yOffset: number) => {
      this.onExploreListScroll(yOffset, this.exploreOverviewScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      this.onExploreListScrollStop(this.exploreOverviewScroller.currentOffset().yOffset);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  overviewSectionHeader(title: string, hint: string) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Blank()
      if (hint) {
        Text(hint)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XL + 2, right: AppSpacing.XL + 2, top: AppSpacing.SM, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Bottom)
  }

  /** 一张榜单卡：第一名带封面和简介，二到五名各一行；整张点开是完整榜单，点某本书直接看详情。 */
  @Builder
  overviewBoardCard(index: number, position: number) {
    Column() {
      Row({ space: AppSpacing.XS }) {
        Text(this.exploreEntryTitleAt(index))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('完整榜单')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.accentColor()])
      }
      .width('100%')
      .height(28)

      if (this.overviewCardState(index) === 'ready' && this.overviewCardBooks(index).length > 0) {
        this.overviewTopBook(this.overviewCardBooks(index)[0])

        Divider()
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ top: AppSpacing.MD, bottom: AppSpacing.XS })

        ForEach(this.overviewCardBooks(index).slice(1, 5), (book: SearchBook, offset: number) => {
          this.overviewBookRow(book, offset + 2)
        }, (book: SearchBook, offset: number): string => `${offset}_${book.origin}_${book.bookUrl}`)
      } else if (this.overviewCardState(index) === 'failed') {
        Column({ space: AppSpacing.SM }) {
          Text(this.overviewCardMessage(index))
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
          Text('点开查看')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.accentColor())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width(this.overviewCardWidth())
    .height(ExplorePage.OVERVIEW_CARD_HEIGHT)
    .padding(14)
    .backgroundColor(this.glassCardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: 1, color: this.glassBorderColor() })
    .accessibilityText(`${this.exploreEntryTitleAt(index)}，第 ${position + 1} 个，打开完整榜单`)
    .onClick(() => this.openOverviewEntry(index))
  }

  @Builder
  overviewTopBook(book: SearchBook) {
    Row({ space: AppSpacing.MD }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack() {
          Text((book.name || '书').substring(0, 1))
            .fontSize(AppFontSize.HEADLINE)
            .fontColor(this.searchExploreShowResultCover ? this.secondaryTextColor() : '#FFFFFF')
          if (this.searchExploreShowResultCover) {
            BookCover({
              bookUrl: book.bookUrl,
              origin: book.origin,
              coverUrl: book.coverUrl,
              name: book.name,
              author: book.author,
              useBookshelfCover: this.searchExploreUseBookshelfCoverGallery,
              placeholderColor: this.cardColor(),
              cornerRadius: 6,
              decodeWidth: 180,
              decodeHeight: 240
            })
          }
        }
        .width(60)
        .height(80)
        .borderRadius(6)
        .clip(true)
        .backgroundColor(this.searchExploreShowResultCover ? this.cardColor() : this.accentColor())

        Text('1')
          .width(20)
          .height(20)
          .borderRadius(10)
          .textAlign(TextAlign.Center)
          .fontSize(AppFontSize.MICRO)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(ExploreRankStyle.medalColor(1, this.appDarkMode))
          .markAnchor({ x: 5, y: 5 })
      }

      Column({ space: 2 }) {
        Text(book.name || '未知书名')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.overviewByline(book))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.secondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((book.intro || book.latestChapterTitle || '').replace(/\s+/g, ' ').trim())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .margin({ top: AppSpacing.MD })
    .alignItems(VerticalAlign.Top)
    .onClick(() => this.openSearchBookDetail(book))
  }

  @Builder
  overviewBookRow(book: SearchBook, rank: number) {
    Row({ space: AppSpacing.SM }) {
      Text(`${rank}`)
        .width(20)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ExploreRankStyle.medalColor(rank, this.appDarkMode) || this.subTextColor())
        .textAlign(TextAlign.Center)
      Text(book.name || '未知书名')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.overviewFirstTag(book))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .constraintSize({ maxWidth: 72 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(ExplorePage.OVERVIEW_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openSearchBookDetail(book))
  }

  @Builder
  overviewCategoryChip(index: number) {
    Column({ space: 2 }) {
      Text(this.exploreEntryTitleAt(index))
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isLastVisitedExploreEntry(index)) {
        Text('上次看过')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.accentColor())
      }
    }
    .width(this.overviewChipWidth())
    .height(52)
    .padding({ left: 12, right: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.glassCardColor())
    .borderRadius(14)
    .border({ width: 1, color: this.glassBorderColor() })
    .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
    .accessibilityText(this.exploreEntryTitleAt(index))
    .onClick(() => this.openOverviewEntry(index))
  }

  isLastVisitedExploreEntry(index: number): boolean {
    const entries = this.getActiveEntries();
    if (index < 0 || index >= entries.length) return false;
    return ExploreCategoryHistoryStore.last(this.selectedSourceUrl) ===
      ExploreCategoryHistoryStore.entryKey(entries[index].title, entries[index].url);
  }

  overviewCardState(index: number): string {
    return this.overviewCards.get(this.explorePageKeys()[index] || '')?.state || 'idle';
  }

  overviewCardBooks(index: number): SearchBook[] {
    return this.overviewCards.get(this.explorePageKeys()[index] || '')?.books || [];
  }

  overviewCardMessage(index: number): string {
    return this.overviewCards.get(this.explorePageKeys()[index] || '')?.message || '暂无内容';
  }

  overviewFirstTag(book: SearchBook): string {
    const kind = (book.kind || '').trim();
    if (!kind) return '';
    return kind.split(/[,，、|/\s]+/).filter((tag: string): boolean => tag.length > 0)[0] || '';
  }

  overviewByline(book: SearchBook): string {
    const parts: string[] = [(book.author || '').trim() || '作者未知'];
    const tag = this.overviewFirstTag(book);
    if (tag) parts.push(tag);
    return parts.join(' · ');
  }

  resultListBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  // 有主题背景图时铺满整页的层透明，背景由根部的 HomeThemeBackdrop 铺。
  surfaceColor(): string {
    return ThemeRuntime.homeSurfaceColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  exploreSelectedBackgroundColor(): string {
    const color = this.accentColor();
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#11${color.substring(1)}`;
    }
    return this.appDarkMode ? '#112A6FCC' : '#11007DFF';
  }
}
