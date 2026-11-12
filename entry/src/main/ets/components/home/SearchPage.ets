import { BookSourceGroupStore } from '../../utils/BookSourceGroupStore';
import { SharedElementMotion } from '../../utils/SharedElementMotion';
import { router } from '@kit.ArkUI';
import { BookSource, SearchBook, SearchKeyword, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { SearchCoordinator, SearchCallback, SearchProgress } from '../../core/book/SearchCoordinator';
import { CategorySwipePager } from './CategorySwipePager';
import { SearchBookResultList } from '../../components/book/SearchBookResultList';
import { SearchResultLoading } from '../book/SearchResultLoading';
import { ResultArrivalTracker } from '../../utils/ResultArrivalTracker';
import { SearchSourceSheet, SearchSourceSheetSession, confirmDiscardSearchSourceChanges } from './SearchSourceSheet';
import { SourcePickerKit } from './SourcePickerKit';
import { ImmersiveMaterialSurface } from '../../components/ImmersiveMaterialSurface';
import { GlassTagModifier, ImmersiveMaterialRuntime, ImmersiveTagModifier } from '../../utils/ImmersiveMaterialRuntime';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HeaderBackdrop } from '../common/HeaderBackdrop';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ListDissolve } from '../../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../common/DeleteParticles';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { SearchResultAggregationStore } from '../../utils/SearchResultAggregationStore';
import { AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { PopupMenuAction } from '../common/PopupMenuAction';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ExploreRankStyle } from '../../utils/ExploreRankStyle';
import { SearchChineseScriptRuntime } from '../../core/book/SearchChineseScriptRuntime';

const SEARCH_CATEGORY_ALL = 'all';
// 小说、漫画、有声、视频各自的结果上限，互不挤占。
const SEARCH_RESULTS_PER_CATEGORY = 150;

class SearchCategoryChip {
  key: string = '';
  label: string = '';
  count: number = 0;
}

/** 搜索范围：全部书源、单个书源（发现页当前书源或外部指定）、自选书源。 */
const SEARCH_SCOPE_ALL = 0;
const SEARCH_SCOPE_SINGLE = 1;
const SEARCH_SCOPE_CUSTOM = 2;

/**
 * 发现页里的搜索层：点发现页搜索框后盖在发现内容上，取消或返回时收起，结果与关键词保留到下次打开。
 * 包含搜索输入、范围、历史、多源/单源搜索进度与结果。
 */
@Component
export struct SearchPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 搜索框的高度。 */
  static readonly HEADER_CONTROL_SIZE: number = 40;
  /** 结果分类栏的高度、两侧留白与选中指示条宽度。 */
  static readonly CATEGORY_BAR_HEIGHT: number = 44;
  static readonly CATEGORY_BAR_PADDING: number = 6;
  static readonly CATEGORY_INDICATOR_WIDTH: number = 18;
  /** 搜索框上方留白（状态栏以下）。 */
  static readonly FIELD_ROW_TOP_GAP: number = 8;
  /** 搜索框左侧的范围前缀。 */
  static readonly SCOPE_PREFIX_HEIGHT: number = 30;
  /** 有结果时搜索框下的进度行。 */
  static readonly STATUS_ROW_HEIGHT: number = 28;
  static readonly SCOPE_MENU_WIDTH: number = 220;
  static readonly INPUT_ID: string = 'home_search_input';
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State displayedSearchResults: SearchBook[] = [];
  // 与 BookTypeSupport.MEDIA_CATEGORIES 同序：小说、漫画、有声、视频。
  @State searchCategoryCounts: number[] = [0, 0, 0, 0];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  /** 正在消散的搜索记录，见 ListDissolve。 */
  @State dissolvingHistory: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  @State searchHistoryExpanded: boolean = false;
  @State searchHistoryEditing: boolean = false;
  @State showSearchHistoryDropdown: boolean = false;
  @State showResult: boolean = false;
  @State statusMessage: string = '';
  @State verificationUrl: string = '';
  private verificationContextToken: string = '';
  @State verificationTitle: string = '';
  @State showSearchScopeMenu: boolean = false;
  @State showSearchSourcePicker: boolean = false;
  @State searchableSources: BookSource[] = [];
  @StorageLink('bookSourceGroupOrder') @Watch('onSourceGroupOrderChanged') sourceGroupOrderRaw: string = '';
  @State sourceGroups: string[] = [];
  @State searchViewportWidth: number = 360;
  /** 搜索框的实际宽度：沉浸光感底板需要具体数值。 */
  @State searchFieldWidth: number = 0;
  /** 结果分类栏的实际宽度：沉浸材质底板需要具体数值。 */
  @State searchCategoryBarWidth: number = 0;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultCoverBackground') searchExploreShowResultCoverBackground: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExploreAggregateResults') @Watch('onSearchAggregationChanged')
  searchExploreAggregateResults: boolean = true;
  @StorageLink('searchResultCategory') searchResultCategory: string = SEARCH_CATEGORY_ALL;
  /** 结果布局与发现页共用（发现页“更多 › 结果布局”）：'list' 卡片列表，'grid' 封面平铺。 */
  @StorageLink('exploreResultLayout') searchResultLayout: string = 'list';
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') exactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') exactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') showSearchProgress: boolean = true;
  /** 简繁同搜开关：切换时按新规则重新聚合已有结果（不重新搜索）。 */
  @StorageLink('searchExploreSimpTradSearch') @Watch('onSearchAggregationChanged') simpTradSearch: boolean = true;
  /** 这次搜索关键词的另一种写法（简繁同搜），进度行显示；没有差异时为空。 */
  @State scriptVariantText: string = '';
  @StorageLink('searchExploreSearchConcurrency') searchConcurrency: number = 6;
  @StorageLink('searchExploreSelectedSourceGroups') selectedSourceGroupsRaw: string = '';
  @StorageLink('searchExploreSelectedSourceUrls') selectedSourceUrlsRaw: string =
    SearchExploreSettingsStore.LEGACY_SOURCE_SELECTION;
  @StorageLink('searchExploreCustomSourceUrls') customSourceUrlsRaw: string = '';
  /** 记住的范围（all / current / custom），重启后由它恢复“当前书源”。 */
  @StorageLink('searchExploreScopeMode') searchScopeModeRaw: string = '';
  /** 最近一次按发现页当前书源设下的单书源；单书源不是它时说明是外部指定的（书源管理里点“搜索”），不跟着改。 */
  private exploreSyncedSourceUrl: string = '';
  /** 发现页当前书源，范围“当前书源”用它。 */
  @StorageProp('exploreSourceUrl') exploreSourceUrl: string = '';
  @StorageProp('exploreSourceName') exploreSourceName: string = '';
  @StorageLink('singleSourceSearchUrl') singleSourceSearchUrl: string = '';
  @StorageLink('singleSourceSearchName') singleSourceSearchName: string = '';
  @StorageLink('globalSearchPendingNonce') @Watch('onGlobalSearchPendingNonceChanged') globalSearchPendingNonce: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  private coordinator: SearchCoordinator | null = null;
  private hasInitialized: boolean = false;
  private shelfStatusVersion: number = 0;
  private shelfSyncRunning: boolean = false;
  private pendingShelfSyncBooks: SearchBook[] = [];
  private searchResultKeySet: Set<string> = new Set<string>();
  private searchResultScroller: ListScroller = new ListScroller();
  private searchCategoryScrollers: Map<string, ListScroller> = new Map();
  /** 分类栏以上（标题行、搜索框、状态行）的收起量，0 为完整显示；结果分类栏不收起。 */
  @State searchHeaderCollapse: number = 0;
  // 顶栏毛玻璃按列表实际滚动距离显现，见 CollapsingHeader.backdropReveal。
  @State searchHeaderBackdropReveal: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private searchSessionId: number = 0;
  private resultArrivalTracker: ResultArrivalTracker = new ResultArrivalTracker();
  private readonly NO_SOURCE_GROUPS_SELECTED: string = '__NO_SOURCE_GROUPS_SELECTED__';
  private readonly NO_SOURCES_SELECTED: string = '__NO_SOURCES_SELECTED__';
  private searchSourceList: BookSource[] = [];
  private searchSourceUrlList: string[] = [];
  private searchSourceUrlSet: Set<string> = new Set<string>();
  private searchSourceGroupOf: string[] = [];
  private searchSourceGroupOrder: string[] = [];
  private searchSourceSheetInitialUrls: string[] = [];
  private searchSourceSheetSession: SearchSourceSheetSession = new SearchSourceSheetSession();
  private searchSourcePickerOpening: boolean = false;

  aboutToAppear() {
    if (this.isActive) {
      this.initPage();
      // 冷启动直接打开搜索层时（小艺搜索），搜索词已先写好，没有页签切换事件来触发。
      this.consumePendingGlobalSearch();
    }
  }

  onActiveChanged(): void {
    if (this.isActive) {
      const hasPendingKeyword = !!(AppStorage.get<string>('globalSearchPendingKeyword') || '').trim() ||
        !!(AppStorage.get<string>('singleSourceSearchKeyword') || '');
      this.initPage();
      this.refreshSearchShelfStatus();
      this.syncCurrentScopeWithExplore();
      this.consumePendingGlobalSearch();
      // 从发现页搜索框或“搜索该书源”进来就是要输入；带着关键词进来的直接出结果，不弹键盘。
      if (!hasPendingKeyword) this.focusSearchInputSoon();
    } else {
      this.showSearchHistoryDropdown = false;
      this.showSearchScopeMenu = false;
      this.resultArrivalTracker.discardPending();
    }
  }

  focusSearchInputSoon(): void {
    setTimeout(() => {
      if (!this.isActive) return;
      try {
        this.getUIContext().getFocusController().requestFocus(SearchPage.INPUT_ID);
      } catch (e) {
      }
    }, 80);
  }

  /** 返回：收起搜索层回到发现内容；关键词、结果和范围都留着。 */
  exitSearchMode(): void {
    this.hideKeyboard();
    this.showSearchHistoryDropdown = false;
    this.showSearchScopeMenu = false;
    AppStorage.setOrCreate('homeSearchActive', false);
  }

  onGlobalSearchPendingNonceChanged(): void {
    this.consumePendingGlobalSearch();
  }

  // 外部页面（书籍详情等）通过 AppStorage 请求全局搜索：nonce 先到时页面可能尚未切换为
  // 激活态，因此这里与 onActiveChanged 双入口消费，后到的一方负责填词并发起搜索。
  consumePendingGlobalSearch(): void {
    if (!this.isActive) return;
    const keyword = (AppStorage.get<string>('globalSearchPendingKeyword') || '').trim();
    if (!keyword) return;
    AppStorage.setOrCreate('globalSearchPendingKeyword', '');
    if (this.singleSourceSearchUrl) {
      // 全局检索必须退出单书源搜索模式，否则会被限定在旧书源内。
      this.clearSingleSourceSearch();
    }
    this.keyword = keyword;
    this.submitKeywordSearch();
  }

  async initPage() {
    if (this.hasInitialized) {
      return;
    }
    this.hasInitialized = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map(k => k.keyword);
      await this.loadSearchableSources(db);
      this.syncCurrentScopeWithExplore();
      const pendingKeyword = AppStorage.get<string>('singleSourceSearchKeyword') || '';
      if (pendingKeyword && this.singleSourceSearchUrl) {
        AppStorage.setOrCreate('singleSourceSearchKeyword', '');
        this.keyword = pendingKeyword;
        setTimeout((): void => {
          this.doSearch();
        }, 0);
      }
    } catch (e) {
      console.error('初始化搜索页失败:', e);
    }
  }

  onSearchAggregationChanged(): void {
    this.applySearchResultsSnapshot(this.searchResults);
  }

  applySearchResultsSnapshot(books: SearchBook[]): void {
    // Record both identities so toggling aggregation never turns old books into new arrivals.
    const arrivalKeys: string[] = [];
    for (const book of books) {
      arrivalKeys.push(`item:${JSON.stringify([book.origin || '', book.bookUrl || ''])}`);
      arrivalKeys.push(`group:${SearchResultAggregationStore.keyOf(book)}`);
    }
    this.resultArrivalTracker.record(arrivalKeys, this.isActive, Date.now());
    this.searchResults = books;
    const counts = SearchResultAggregationStore.countByCategory(books);
    this.searchCategoryCounts = BookTypeSupport.MEDIA_CATEGORIES.map((category: string): number =>
      counts.get(category) || 0);
    const visible = SearchResultAggregationStore.filterByCategory(books, this.effectiveSearchCategory());
    this.displayedSearchResults = this.searchExploreAggregateResults ?
      SearchResultAggregationStore.aggregate(visible) : visible.slice();
  }

  searchCategoryCount(category: string): number {
    const index = BookTypeSupport.MEDIA_CATEGORIES.indexOf(category);
    return index >= 0 ? (this.searchCategoryCounts[index] || 0) : this.searchResults.length;
  }

  claimSearchResultArrival(book: SearchBook): number {
    if (!this.isActive) return -1;
    const key = book.aggregationKey ? `group:${book.aggregationKey}` :
      `item:${JSON.stringify([book.origin || '', book.bookUrl || ''])}`;
    return this.resultArrivalTracker.claim(key, Date.now());
  }

  onSearchResultReady(book: SearchBook): void {
    const key = book.aggregationKey ? `group:${book.aggregationKey}` :
      `item:${JSON.stringify([book.origin || '', book.bookUrl || ''])}`;
    this.resultArrivalTracker.markReady(key, this.isActive, Date.now());
  }

  // 记住的分段在本次搜索里没有结果时，搜索结束后按"全部"展示，但不改写用户的选择。
  effectiveSearchCategory(): string {
    const selected = this.searchResultCategory;
    if (!BookTypeSupport.MEDIA_CATEGORIES.includes(selected)) return SEARCH_CATEGORY_ALL;
    if (!this.isSearching && this.searchCategoryCount(selected) === 0) return SEARCH_CATEGORY_ALL;
    return selected;
  }

  searchCategoryChips(): SearchCategoryChip[] {
    const labels: string[] = ['小说', '漫画', '有声', '视频'];
    const effective = this.effectiveSearchCategory();
    const chips: SearchCategoryChip[] = [];
    BookTypeSupport.MEDIA_CATEGORIES.forEach((category: string, index: number): void => {
      const count = this.searchCategoryCount(category);
      if (count === 0 && category !== effective) return;
      const chip = new SearchCategoryChip();
      chip.key = category;
      chip.label = labels[index];
      chip.count = count;
      chips.push(chip);
    });
    // 只有一种类型且未筛选时，分段栏没有可切换的内容。
    if (chips.length < 2 && effective === SEARCH_CATEGORY_ALL) return [];
    const all = new SearchCategoryChip();
    all.key = SEARCH_CATEGORY_ALL;
    all.label = '全部';
    all.count = this.searchResults.length;
    chips.unshift(all);
    return chips;
  }

  showSearchCategoryBar(): boolean {
    return this.showResult && this.searchResults.length > 0 && this.searchCategoryChips().length > 0;
  }

  selectSearchCategory(category: string): void {
    if (category === this.effectiveSearchCategory()) return;
    this.searchResultCategory = category;
    this.applySearchResultsSnapshot(this.searchResults);
    // 平铺分类保留各自的位置，进入时由结果列表对齐共享顶栏；列表模式仍从头展示。
    if (this.searchResultLayout !== 'grid') this.searchResultScroller.scrollToIndex(0);
  }

  openSearchBookOrGroup(book: SearchBook): void {
    if (!this.searchExploreAggregateResults || book.aggregationCount <= 1 || !book.aggregationKey) {
      this.openSearchBookDetail(book);
      return;
    }
    const members = SearchResultAggregationStore.members(this.searchResults, book.aggregationKey);
    if (members.length <= 1) {
      this.openSearchBookDetail(members[0] || book);
      return;
    }
    const token = SearchResultAggregationStore.publish(book.name, members);
    router.pushUrl({
      url: 'pages/SearchResultGroup',
      params: { token: token, title: book.name }
    });
  }

  onSourceGroupOrderChanged(): void {
    this.rebuildSearchSourceIndex(this.searchSourceList);
    this.sourceGroups = this.searchSourceGroupOrder.slice();
  }

  async loadSearchableSources(db: AppDatabase = AppDatabase.getInstance()): Promise<void> {
    try {
      await BookSourceGroupStore.loadOrder(getContext(this));
      const sources = await db.getEnabledBookSourcesForSearch();
      const searchable = sources.filter((source: BookSource): boolean =>
        !!(source.bookSourceUrl && source.bookSourceName && source.searchUrl && source.searchRule?.bookList));
      this.rebuildSearchSourceIndex(searchable);
      this.searchableSources = searchable;
      this.sourceGroups = this.searchSourceGroupOrder.slice();
      this.migrateLegacySearchSourceSelection();
      this.pruneSearchSourceSelection();
    } catch (e) {
      console.warn('加载可搜索书源失败:', e);
      this.rebuildSearchSourceIndex([]);
      this.searchableSources = [];
    }
  }

  /** 书源上千时，范围统计和筛选都靠这里预先算好的地址集合与分组，界面刷新里不再反复线性查找。 */
  rebuildSearchSourceIndex(sources: BookSource[]): void {
    const urls: string[] = [];
    const urlSet: Set<string> = new Set<string>();
    const groupOf: string[] = [];
    const groupSet: Set<string> = new Set<string>();
    for (const source of sources) {
      const url = source.bookSourceUrl;
      const group = this.normalizeSourceGroup(source);
      groupOf.push(group);
      groupSet.add(group);
      if (url && !urlSet.has(url)) {
        urlSet.add(url);
        urls.push(url);
      }
    }
    this.searchSourceList = sources;
    this.searchSourceUrlList = urls;
    this.searchSourceUrlSet = urlSet;
    this.searchSourceGroupOf = groupOf;
    this.searchSourceGroupOrder = SourcePickerKit.sortGroups(Array.from(groupSet));
  }

  async openSearchSourcePicker(): Promise<void> {
    if (this.showSearchSourcePicker || this.searchSourcePickerOpening) return;
    this.searchSourcePickerOpening = true;
    this.showSearchHistoryDropdown = false;
    this.showSearchScopeMenu = false;
    try {
      await this.loadSearchableSources();
    } catch (e) {
      console.warn('刷新可搜索书源失败:', e);
    }
    // 修改自选时从记住的自选书源开始勾，没有自选过就从当前生效的范围开始。
    const custom = this.customSourceUrls();
    this.searchSourceSheetInitialUrls = custom.length > 0 ? custom :
      (this.singleSourceSearchUrl ? [this.singleSourceSearchUrl] : this.effectiveSelectedSourceUrls());
    this.searchSourceSheetSession = new SearchSourceSheetSession();
    this.searchSourcePickerOpening = false;
    this.showSearchSourcePicker = true;
  }

  searchSourceSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['75%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 注册了 onWillDismiss 后系统默认先把下滑的面板弹回原高度再关，看着像回弹一下才收起。
      // 接管回弹：只有要弹确认框时才弹回，否则从松手位置直接收起。
      onWillSpringBackWhenDismiss: (action: SpringBackAction): void => {
        if (this.searchSourceSheetSession.dirty) {
          action.springBack();
        }
      },
      // 下滑、点遮罩或返回收起时，有没保存的勾选先确认。
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.searchSourceSheetSession.dirty) {
          action.dismiss();
          return;
        }
        confirmDiscardSearchSourceChanges().then((discard: boolean): void => {
          if (discard) {
            this.searchSourceSheetSession.dirty = false;
            action.dismiss();
          }
        });
      },
      onDisappear: () => {
        this.showSearchSourcePicker = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options, this.appDarkMode, this.accentColor());
  }

  @Builder
  searchSourceSheet() {
    SearchSourceSheet({
      sources: this.searchSourceList,
      sourceGroupOf: this.searchSourceGroupOf,
      groups: this.searchSourceGroupOrder,
      initialSelectedUrls: this.searchSourceSheetInitialUrls,
      session: this.searchSourceSheetSession,
      onDone: (urls: string[]): void => {
        this.applySearchSourceSelection(urls);
      },
      onCancel: (): void => {
        this.showSearchSourcePicker = false;
      },
      onSourcesChanged: (): void => {
        this.loadSearchableSources();
      }
    })
  }

  searchableSourceUrls(): string[] {
    return this.searchSourceUrlList.slice();
  }

  uniqueSourceUrls(urls: string[]): string[] {
    const result: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const rawUrl of urls) {
      const url = (rawUrl || '').trim();
      if (url && !seen.has(url)) {
        seen.add(url);
        result.push(url);
      }
    }
    return result;
  }

  selectedSourceUrls(): string[] {
    const raw = this.selectedSourceUrlsRaw.trim();
    if (!raw || raw === this.NO_SOURCES_SELECTED ||
      raw === SearchExploreSettingsStore.LEGACY_SOURCE_SELECTION) return [];
    return this.uniqueSourceUrls(raw.split('\n'));
  }

  isAllSearchSourcesSelected(): boolean {
    const raw = this.selectedSourceUrlsRaw.trim();
    return raw === '' || raw === SearchExploreSettingsStore.LEGACY_SOURCE_SELECTION;
  }

  isNoSearchSourcesSelected(): boolean {
    return this.selectedSourceUrlsRaw.trim() === this.NO_SOURCES_SELECTED;
  }

  effectiveSelectedSourceUrls(): string[] {
    if (this.isAllSearchSourcesSelected()) return this.searchableSourceUrls();
    if (this.isNoSearchSourcesSelected()) return [];
    return this.selectedSourceUrls().filter((url: string): boolean => this.searchSourceUrlSet.has(url));
  }

  selectedSourceGroupCount(urls: string[]): number {
    const selected: Set<string> = new Set<string>(urls);
    const groups: Set<string> = new Set<string>();
    for (let index = 0; index < this.searchSourceList.length; index++) {
      if (selected.has(this.searchSourceList[index].bookSourceUrl)) groups.add(this.searchSourceGroupOf[index]);
    }
    return groups.size;
  }

  searchScopeSummary(): string {
    if (this.singleSourceSearchUrl) {
      return this.singleSourceSearchName || this.singleSourceSearchUrl;
    }
    // 先读一次书源列表状态，书源重新加载后标签跟着刷新。
    const total = this.searchableSources.length;
    if (this.isAllSearchSourcesSelected()) {
      return total > 0 ? `全部书源 · ${total}` : '全部书源';
    }
    const selected = this.effectiveSelectedSourceUrls();
    if (selected.length === 0) return '未选择书源';
    if (selected.length === 1) {
      const source = this.searchSourceList.find((item: BookSource): boolean => item.bookSourceUrl === selected[0]);
      return source?.bookSourceName || '1 个书源';
    }
    return `${selected.length} 个书源 · ${this.selectedSourceGroupCount(selected)} 个分组`;
  }

  migrateLegacySearchSourceSelection(): void {
    if (this.selectedSourceUrlsRaw.trim() !== SearchExploreSettingsStore.LEGACY_SOURCE_SELECTION) return;
    const legacyRaw = this.selectedSourceGroupsRaw.trim();
    if (!legacyRaw) {
      this.selectedSourceUrlsRaw = '';
    } else if (legacyRaw === this.NO_SOURCE_GROUPS_SELECTED) {
      this.selectedSourceUrlsRaw = this.NO_SOURCES_SELECTED;
    } else {
      const legacyGroups = legacyRaw.split('\n').map((group: string): string => group.trim())
        .filter((group: string): boolean => !!group);
      const urls = this.searchableSources.filter((source: BookSource): boolean =>
        legacyGroups.includes(this.normalizeSourceGroup(source)))
        .map((source: BookSource): string => source.bookSourceUrl);
      this.selectedSourceUrlsRaw = urls.length > 0 ? this.uniqueSourceUrls(urls).join('\n') : this.NO_SOURCES_SELECTED;
    }
    this.saveSearchExploreSettings();
  }

  pruneSearchSourceSelection(): void {
    if (this.isAllSearchSourcesSelected() || this.isNoSearchSourcesSelected()) return;
    const selected = this.selectedSourceUrls().filter((url: string): boolean => this.searchSourceUrlSet.has(url));
    const normalized = selected.length > 0 ? selected.join('\n') : this.NO_SOURCES_SELECTED;
    if (normalized !== this.selectedSourceUrlsRaw) {
      this.selectedSourceUrlsRaw = normalized;
      this.saveSearchExploreSettings();
    }
  }

  applySearchSourceSelection(urls: string[]): void {
    const selected = this.uniqueSourceUrls(urls)
      .filter((url: string): boolean => this.searchSourceUrlSet.has(url));
    this.selectedSourceUrlsRaw = selected.length === this.searchSourceUrlList.length ? '' :
      (selected.length > 0 ? selected.join('\n') : this.NO_SOURCES_SELECTED);
    this.customSourceUrlsRaw = selected.length > 0 && selected.length < this.searchSourceUrlList.length ?
      selected.join('\n') : '';
    this.selectedSourceGroupsRaw = '';
    this.singleSourceSearchUrl = '';
    this.singleSourceSearchName = '';
    this.searchScopeModeRaw = this.isAllSearchSourcesSelected() ? 'all' : 'custom';
    this.saveSearchExploreSettings();
    this.showSearchSourcePicker = false;
    this.afterSearchScopeChanged();
  }

  resetSearchForScopeChange(): void {
    this.searchSessionId++;
    this.coordinator?.cancel();
    this.coordinator = null;
    this.isSearching = false;
    this.searchResults = [];
    this.displayedSearchResults = [];
    this.searchCategoryCounts = [0, 0, 0, 0];
    this.searchResultKeySet.clear();
    this.showResult = false;
    this.statusMessage = '';
    this.verificationUrl = '';
    this.verificationTitle = '';
  }

  build() {
    Stack() {
      HomeThemeBackdrop({ visibleHeight: this.statusBarHeight + 230, strength: 0.6 })
        .position({ x: 0, y: 0 })

      Column() {
        Column() {
          // 状态栏占位固定不动；下面的搜索框和范围行作为一整块随列表上滑收起，只留结果分类栏。
          Column()
            .width('100%')
            .height(this.statusBarHeight)

          // 外层按收起量变矮并裁剪，内容贴底上移；各行在被裁掉前依次淡出。
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              Row() {
                ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
                  buttonSize: 40, containerWidth: 56, containerHeight: SearchPage.HEADER_CONTROL_SIZE,
                  materialScale: 0.83, compactLayout: true, accessibilityLabel: '返回发现',
                  onBack: () => this.exitSearchMode() })
                // 与返回钮、发现页书源标签同一种沉浸光感底板（HDS 悬浮栏材质），宽度按实际布局量出来。
                Row() {
                  if (this.searchFieldWidth > 0) {
                    ImmersiveMaterialSurface({
                      surfaceWidth: this.searchFieldWidth,
                      surfaceHeight: SearchPage.HEADER_CONTROL_SIZE,
                      darkMode: this.appDarkMode,
                      fallbackColor: this.glassCardColor(),
                      glowColor: this.accentGlowColor()
                    }) {
                      Row() {
                        this.searchFieldContent()
                      }
                      .width('100%')
                      .height('100%')
                      .alignItems(VerticalAlign.Center)
                    }
                  }
                }
                .layoutWeight(1)
                .height(SearchPage.HEADER_CONTROL_SIZE)
                .onAreaChange((_oldValue: Area, newValue: Area) => {
                  const width = Math.floor(Number(newValue.width));
                  if (Number.isFinite(width) && width > 0 && width !== this.searchFieldWidth) {
                    this.searchFieldWidth = width;
                  }
                })

                Text(this.isSearching ? '停止' : '搜索')
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.accentColor())
                  .height(SearchPage.HEADER_CONTROL_SIZE)
                  .padding({ left: AppSpacing.LG, right: AppSpacing.XS })
                  .accessibilityText(this.isSearching ? '停止搜索' : '搜索')
                  .onClick(() => this.onSearchButtonTap())
              }
              .width('100%')
              .height(this.searchFieldRowHeight())
              .padding({ right: AppSpacing.XL - AppSpacing.XS, top: SearchPage.FIELD_ROW_TOP_GAP, bottom: AppSpacing.MD })
              .alignItems(VerticalAlign.Center)
              .opacity(this.searchHeaderRowOpacity(0, this.searchFieldRowHeight()))
              .hitTestBehavior(this.searchHeaderRowHitTest(0, this.searchFieldRowHeight()))
              .bindSheet($$this.showSearchSourcePicker, this.searchSourceSheet(), this.searchSourceSheetOptions())
              .bindPopup(this.showSearchHistoryDropdown && this.showResult && this.searchHistory.length > 0,
                ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
                  this.searchHistoryPopupContent()
                }, Placement.Bottom, this.appDarkMode, this.accentColor(), () => {
                  this.showSearchHistoryDropdown = false;
                }, false))

              if (this.showResult) {
                this.searchStatusRow()
              }
            }
            .width('100%')
            .height(this.searchCollapsibleHeight())
          }
          .width('100%')
          .height(this.searchCollapsibleHeight() - this.searchHeaderCollapseValue())
          .clip(true)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.onHeaderCollapseChange(1 - Number(newArea.height) / this.searchCollapsibleHeight());
          })

          if (this.showSearchCategoryBar()) {
            this.searchCategoryBar()
          }
        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(4)

        HeaderBackdrop({ backdropHeight: this.searchHeaderBackdropHeight(),
          statusBarHeight: this.statusBarHeight,
          backdropColor: ThemeRuntime.topBarColor(this.appDarkMode),
          reveal: ThemeRuntime.homeBackdrop(this.appDarkMode) ? this.searchHeaderBackdropReveal : 1 })
          .width('100%')
          .position({ x: 0, y: 0 })
          .zIndex(3)

        if (this.usesSearchCategoryPager()) {
          CategorySwipePager({
            pageKeys: this.searchCategoryPageKeys(),
            selectedIndex: Math.max(0, this.searchCategoryPageKeys().indexOf(this.effectiveSearchCategory())),
            onSelect: (key: string): void => this.selectSearchCategory(key),
            pageContent: (key: string) => {
              this.searchResultContent(key)
            }
          })
          .layoutWeight(1)
        } else {
          this.searchResultContent('')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.surfaceColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])




      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('search_page_root')
    .width('100%')
    .height('100%')
    // 搜索层盖在发现内容上：有主题背景图时内容层是透明的，底色要自己铺，否则会透出下面的发现列表。
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = typeof newValue.width === 'number' ? newValue.width : Number.parseFloat(`${newValue.width}`);
      if (Number.isFinite(width) && width > 0) {
        this.searchViewportWidth = width;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  searchBooksForCategory(category: string): SearchBook[] {
    if (!category || category === this.effectiveSearchCategory()) return this.displayedSearchResults;
    const books = SearchResultAggregationStore.filterByCategory(this.searchResults, category);
    return this.searchExploreAggregateResults ? SearchResultAggregationStore.aggregate(books) : books;
  }

  searchCategoryScroller(category: string): ListScroller {
    let scroller = this.searchCategoryScrollers.get(category);
    if (!scroller) {
      scroller = new ListScroller();
      this.searchCategoryScrollers.set(category, scroller);
    }
    return scroller;
  }

  @Builder
  searchResultContent(category: string) {
    // Builder 只接收稳定的页标识；动态结果在 UI 更新闭包内读取，持续搜索时相邻页也会刷新。
    if (this.showResult && this.searchBooksForCategory(category).length > 0) {
      SearchBookResultList({
        sharedCoverScope: 'search',
        markTraditional: true,
        books: this.searchBooksForCategory(category),
        claimArrival: (book: SearchBook): number => this.claimSearchResultArrival(book),
        onResultReady: (book: SearchBook): void => this.onSearchResultReady(book),
        scroller: category ? this.searchCategoryScroller(category) : this.searchResultScroller,
        // 发现页的排行、总览、侧栏布局对搜索结果没有意义，搜索只分列表和平铺。
        layoutMode: ExploreRankStyle.searchLayout(this.searchResultLayout),
        gridViewportWidth: this.searchViewportWidth,
        shelfBookKeys: this.shelfBookKeys,
        busyBookKeys: this.addingShelfBookKeys,
        showLoadingMore: this.isSearching,
        showResultCover: this.searchExploreShowResultCover,
        showResultCoverBackground: this.searchExploreShowResultCoverBackground,
        useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
        showResultTags: this.searchExploreShowResultTags,
        pageColor: this.surfaceColor(),
        cardColor: this.glassCardColor(),
        itemBorderColor: this.glassBorderColor(),
        itemBorderWidth: 1,
        shadowColor: this.glassShadowColor(),
        primaryTextColor: this.primaryTextColor(),
        secondaryTextColor: this.secondaryTextColor(),
        subTextColor: this.subTextColor(),
        topPadding: this.searchResultTopPadding(),
        userScrollOnly: this.usesSearchCategoryPager(),
        gridPageActive: this.isActive && (!category || category === this.effectiveSearchCategory()),
        gridHeaderCollapse: this.searchHeaderCollapseValue(),
        bottomPadding: this.resultListBottomInset(),
        onOpenBook: (book: SearchBook) => {
          this.openSearchBookOrGroup(book);
        },
        onReadBook: (book: SearchBook) => {
          this.readSearchBook(book);
        },
        onToggleShelf: (book: SearchBook) => {
          this.toggleSearchBookShelf(book);
        },
        onListScroll: (delta: number, offset: number) => {
          if (!category || category === this.effectiveSearchCategory()) this.onSearchListScroll(delta, offset);
        },
        onListScrollStop: (offset: number) => {
          if (!category || category === this.effectiveSearchCategory()) this.onSearchListScrollStop(offset);
        }
      })
    } else if (this.isSearching) {
      SearchResultLoading({
        topPadding: this.searchResultTopPadding()
      })
      .layoutWeight(1)
    } else if (this.showResult && this.searchBooksForCategory(category).length === 0) {
      Column({ space: AppSpacing.LG }) {
        Text(this.searchResults.length > 0 ? '该类型下没有结果' : '未找到相关书籍')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
        if (this.searchResults.length === 0 && this.searchScopeMode() !== SEARCH_SCOPE_ALL && this.keyword.trim()) {
          Text(`在全部书源中搜「${this.keyword.trim()}」`)
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .onClick(() => this.selectSearchScope(SEARCH_SCOPE_ALL))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: this.searchResultTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else {
      this.searchIdleContent()
    }
  }

  onSearchButtonTap(): void {
    if (this.isSearching) {
      this.showSearchHistoryDropdown = false;
      this.searchSessionId++;
      this.coordinator?.cancel();
      this.coordinator = null;
      this.isSearching = false;
      this.applySearchResultsSnapshot(this.searchResults);
      this.statusMessage = '搜索已停止';
    } else {
      this.showSearchHistoryDropdown = false;
      this.hideKeyboard();
      this.doSearch();
    }
  }

  /** 搜索框左侧的范围前缀：全部 / 当前 / 自选，点开菜单换范围（菜单里写明是哪个书源、几个书源）。 */
  @Builder
  searchScopePrefix() {
    Row() {
      // 胶囊本身也是沉浸光感底板（和分段栏选中块一样叠在外层材质上），按下有跟手光晕。
      ImmersiveMaterialSurface({
        surfaceWidth: this.searchScopePrefixWidth(),
        surfaceHeight: SearchPage.SCOPE_PREFIX_HEIGHT,
        darkMode: this.appDarkMode,
        fallbackColor: ThemeRuntime.accentSurfaceColor(this.appDarkMode),
        glowColor: this.accentGlowColor()
      }) {
        Row({ space: 2 }) {
          Text(this.searchScopePrefixLabel())
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .maxLines(1)
          SymbolGlyph(this.showSearchScopeMenu ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(11)
            .fontColor([this.accentColor()])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`搜索范围：${this.searchScopeSummary()}，点开更改`)
        .onClick(() => {
          this.showSearchHistoryDropdown = false;
          this.hideKeyboard();
          this.showSearchScopeMenu = !this.showSearchScopeMenu;
        })
      }
    }
    .margin({ left: AppSpacing.XS + AppSpacing.XXS })
    .flexShrink(0)
    .bindPopup(this.showSearchScopeMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.searchScopeMenu()
    }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
      this.showSearchScopeMenu = false;
    }))
  }

  /** 前缀宽度：两个字加箭头与左右留白；按实际字号量，系统调大字体时不被截断。 */
  searchScopePrefixWidth(): number {
    let textWidth = AppFontSize.CAPTION * 2 * 1.2;
    try {
      const context = this.getUIContext();
      const widthPx = context.getMeasureUtils().measureText({
        textContent: this.searchScopePrefixLabel(),
        fontSize: AppFontSize.CAPTION,
        fontWeight: FontWeight.Medium
      });
      if (widthPx > 0) textWidth = context.px2vp(widthPx);
    } catch (error) {
    }
    // 左右留白 10 + 8、箭头 11、间隔 2，再留 2 防止取整后被省略。
    return Math.ceil(textWidth) + 33;
  }

  searchScopePrefixLabel(): string {
    const mode = this.searchScopeMode();
    return mode === SEARCH_SCOPE_SINGLE ? '当前' : (mode === SEARCH_SCOPE_CUSTOM ? '自选' : '全部');
  }

  /** 有结果时搜索框下的一行：进度与“去验证 / 搜全部书源”；停止在顶栏的搜索按钮上。 */
  @Builder
  searchStatusRow() {
    Row({ space: AppSpacing.SM }) {
      if (this.isSearching) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(this.secondaryTextColor())
      }
      Text(this.searchStatusText())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.simpTradSearch && this.scriptVariantText) {
        Text(`简繁 · ${this.scriptVariantText}`)
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.secondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '40%' })
          .flexShrink(0)
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
          .border({ width: 1, color: this.secondaryTextColor() })
          .borderRadius(ThemeRuntime.mediumRadius())
          .accessibilityText(`简繁同搜，同时搜索${this.scriptVariantText}`)
      }

      if (this.verificationUrl) {
        this.searchStatusLink('去验证', '去网页验证', () => this.openVerification())
      } else if (this.searchScopeMode() !== SEARCH_SCOPE_ALL && this.keyword.trim()) {
        this.searchStatusLink('搜全部书源', '在全部书源中搜索这个关键词', () => this.selectSearchScope(SEARCH_SCOPE_ALL))
      }
    }
    .width('100%')
    .height(this.searchStatusRowHeight())
    .padding({ left: AppSpacing.XL + AppSpacing.XS, right: AppSpacing.XL, bottom: AppSpacing.XS })
    .alignItems(VerticalAlign.Center)
    .opacity(this.searchHeaderRowOpacity(this.searchStatusRowTop(), this.searchStatusRowHeight()))
    .hitTestBehavior(this.searchHeaderRowHitTest(this.searchStatusRowTop(), this.searchStatusRowHeight()))
  }

  @Builder
  searchStatusLink(label: string, accessibility: string, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.accentColor())
      .flexShrink(0)
      .padding({ left: AppSpacing.XS, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .accessibilityText(accessibility)
      .onClick(() => onTap())
  }

  /** 范围前缀弹出的菜单：三种范围，当前项用强调色，右边是书源数；另给自选一个“修改”入口。 */
  @Builder
  searchScopeMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.square_grid_2x2'), '全部书源', this.searchScopeMenuColor(SEARCH_SCOPE_ALL),
        () => this.selectSearchScope(SEARCH_SCOPE_ALL), true,
        this.searchableSources.length > 0 ? `${this.searchableSources.length}` : '', this.secondaryTextColor())
      PopupMenuAction($r('sys.symbol.magnifyingglass'), this.currentScopeMenuLabel(),
        this.searchScopeMenuColor(SEARCH_SCOPE_SINGLE), () => this.selectSearchScope(SEARCH_SCOPE_SINGLE),
        this.searchScopeMode() === SEARCH_SCOPE_SINGLE || this.exploreSourceSearchable())
      PopupMenuAction($r('sys.symbol.list_bullet'), '自选书源', this.searchScopeMenuColor(SEARCH_SCOPE_CUSTOM),
        () => this.selectSearchScope(SEARCH_SCOPE_CUSTOM), true,
        this.customSourceUrls().length > 0 ? `${this.customSourceUrls().length}` : '', this.secondaryTextColor())
      PopupMenuAction($r('sys.symbol.square_and_pencil'), '修改自选书源', this.primaryTextColor(), () => {
        this.showSearchScopeMenu = false;
        this.openSearchSourcePicker();
      })
    }
    .width(SearchPage.SCOPE_MENU_WIDTH)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  searchScopeMenuColor(mode: number): string {
    return this.searchScopeMode() === mode ? this.accentColor() : this.primaryTextColor();
  }

  searchScopeMode(): number {
    if (this.singleSourceSearchUrl) return SEARCH_SCOPE_SINGLE;
    return this.isAllSearchSourcesSelected() ? SEARCH_SCOPE_ALL : SEARCH_SCOPE_CUSTOM;
  }

  /** 发现页当前书源能不能搜：书源列表没加载完时先当能搜，选的时候再核对。 */
  exploreSourceSearchable(): boolean {
    return !!this.exploreSourceUrl &&
      (this.searchSourceUrlSet.size === 0 || this.searchSourceUrlSet.has(this.exploreSourceUrl));
  }

  currentScopeMenuLabel(): string {
    if (this.searchScopeMode() !== SEARCH_SCOPE_SINGLE) {
      if (!this.exploreSourceUrl) return '当前书源（发现页未选书源）';
      if (!this.exploreSourceSearchable()) return '当前书源不支持搜索';
    }
    const name = this.currentScopeSourceName();
    return name ? `仅 ${name}` : '当前书源';
  }

  /** 记住的自选书源；旧版本只存了当前选择，那份也算自选。书源列表加载后去掉已失效的。 */
  customSourceUrls(): string[] {
    const raw = this.customSourceUrlsRaw.trim();
    let urls = raw ? this.uniqueSourceUrls(raw.split('\n')) : [];
    if (urls.length === 0 && !this.isAllSearchSourcesSelected() && !this.isNoSearchSourcesSelected()) {
      urls = this.selectedSourceUrls();
    }
    if (this.searchSourceUrlSet.size === 0) return urls;
    return urls.filter((url: string): boolean => this.searchSourceUrlSet.has(url));
  }

  /** “当前书源”指的书源：单源搜索中就是那个书源，否则是发现页正在看的书源。 */
  currentScopeSourceName(): string {
    if (this.singleSourceSearchUrl) return this.singleSourceSearchName || this.singleSourceSearchUrl;
    return this.exploreSourceUrl ? this.exploreSourceDisplayName() : '';
  }

  searchStatusText(): string {
    if (this.statusMessage) return this.statusMessage;
    return this.searchResults.length > 0 ? `共 ${this.searchResults.length} 条结果` : '';
  }

  selectSearchScope(index: number): void {
    this.showSearchScopeMenu = false;
    const mode = this.searchScopeMode();
    if (index === mode) return;
    if (index === SEARCH_SCOPE_ALL) {
      this.singleSourceSearchUrl = '';
      this.singleSourceSearchName = '';
      this.selectedSourceUrlsRaw = '';
      this.selectedSourceGroupsRaw = '';
      this.searchScopeModeRaw = 'all';
      this.saveSearchExploreSettings();
      this.afterSearchScopeChanged();
      return;
    }
    if (index === SEARCH_SCOPE_SINGLE) {
      const url = this.exploreSourceUrl;
      if (!url) {
        HdsFeedback.showToast('发现页还没有选择书源');
        return;
      }
      if (this.searchSourceUrlSet.size > 0 && !this.searchSourceUrlSet.has(url)) {
        HdsFeedback.showToast('当前书源不支持搜索');
        return;
      }
      this.singleSourceSearchUrl = url;
      this.singleSourceSearchName = this.exploreSourceDisplayName();
      this.exploreSyncedSourceUrl = url;
      this.searchScopeModeRaw = 'current';
      this.saveSearchExploreSettings();
      this.afterSearchScopeChanged();
      return;
    }
    const custom = this.customSourceUrls();
    if (custom.length === 0) {
      // 还没自选过：先打开书源面板，选好后范围自然变成自选。
      this.hideKeyboard();
      this.openSearchSourcePicker();
      return;
    }
    this.singleSourceSearchUrl = '';
    this.singleSourceSearchName = '';
    this.selectedSourceUrlsRaw = custom.join('\n');
    this.selectedSourceGroupsRaw = '';
    this.searchScopeModeRaw = 'custom';
    this.saveSearchExploreSettings();
    this.afterSearchScopeChanged();
  }

  /**
   * 记住的范围是“当前书源”时，单书源跟着发现页当前书源走：重启后（单书源本身不保存）补上，发现页换了书源后跟过去。
   * 外部指定的单书源和正在进行的搜索不动；发现页当前书源不能搜时保持原样。
   */
  syncCurrentScopeWithExplore(): void {
    if (this.searchScopeModeRaw !== 'current' || this.isSearching) return;
    const url = this.exploreSourceUrl;
    if (!url || (this.searchSourceUrlSet.size > 0 && !this.searchSourceUrlSet.has(url))) return;
    if (this.singleSourceSearchUrl && this.singleSourceSearchUrl !== this.exploreSyncedSourceUrl) return;
    this.exploreSyncedSourceUrl = url;
    if (this.singleSourceSearchUrl === url) return;
    this.singleSourceSearchUrl = url;
    this.singleSourceSearchName = this.exploreSourceDisplayName();
  }

  exploreSourceDisplayName(): string {
    if (this.exploreSourceName) return this.exploreSourceName;
    const source = this.searchSourceList.find((item: BookSource): boolean =>
      item.bookSourceUrl === this.exploreSourceUrl);
    return source?.bookSourceName || this.exploreSourceUrl;
  }

  /** 换范围后：已经搜过就用同一个关键词按新范围重搜，否则清掉旧状态。 */
  afterSearchScopeChanged(): void {
    if (this.keyword.trim() && this.showResult) {
      this.doSearch();
    } else {
      this.resetSearchForScopeChange();
    }
  }

  isSearchScopeNarrowed(): boolean {
    return !!this.singleSourceSearchUrl || !this.isAllSearchSourcesSelected();
  }

  /** 没搜索时页面上直接显示的搜索历史；没有历史时给出引导和当前范围。 */
  @Builder
  searchIdleContent() {
    Scroll() {
      Column() {
        if (this.searchHistory.length > 0) {
          Row() {
            Text('搜索历史')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Text('清空')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.secondaryTextColor())
              .padding({ left: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .onClick(() => {
                this.clearSearchHistory();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.searchHistory, (keyword: string) => {
              this.searchHistoryTag(keyword)
            }, (keyword: string) => keyword)
          }
          .width('100%')
          .margin({ top: AppSpacing.MD })

          Text('长按单条可删除')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.secondaryTextColor())
            .opacity(0.8)
            .margin({ top: AppSpacing.XS })
        } else {
          Column({ space: AppSpacing.MD }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(48)
              .fontColor([this.secondaryTextColor()])
              .opacity(0.5)
            Text('输入书名或作者搜索')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.secondaryTextColor())
            Text(`当前范围：${this.searchScopeSummary()}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.secondaryTextColor())
              .opacity(0.8)
          }
          .width('100%')
          .padding({ top: 96 })
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .padding({
        left: AppSpacing.XL,
        right: AppSpacing.XL,
        top: this.searchTopOverlayHeight() + AppSpacing.SM,
        bottom: this.resultListBottomInset()
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  searchHistoryTag(keyword: string) {
    Text(keyword)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.primaryTextColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: '72%' })
      .height(34)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .attributeModifier(new ImmersiveTagModifier(ThemeRuntime.cardColor(this.appDarkMode),
        this.secondaryTextColor(), this.appDarkMode))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .opacity(ListDissolve.opacity(this.isHistoryDissolving(keyword)))
      .scale(ListDissolve.scale(this.isHistoryDissolving(keyword)))
      .blur(ListDissolve.blur(this.isHistoryDissolving(keyword)))
      .hitTestBehavior(this.isHistoryDissolving(keyword) ? HitTestMode.None : HitTestMode.Default)
      .id(this.historyTagElementId(keyword, false))
      .priorityGesture(
        GestureGroup(GestureMode.Exclusive,
          LongPressGesture({ repeat: false })
            .onAction(() => {
              this.deleteSearchHistoryItem(keyword);
            }),
          TapGesture()
            .onAction(() => {
              this.showSearchHistoryDropdown = false;
              this.searchFromHistory(keyword);
            })
        ),
        GestureMask.IgnoreInternal
      )
  }

  @Builder
  searchCategoryBar() {
    Row() {
      if (this.searchCategoryBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.searchCategoryBarWidth,
          surfaceHeight: SearchPage.CATEGORY_BAR_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Row() {
              ForEach(this.searchCategoryChips(), (chip: SearchCategoryChip) => {
                Text() {
                  Span(chip.label)
                    .fontSize(AppFontSize.BODY_LARGE)
                  Span(` ${chip.count}`)
                    .fontSize(AppFontSize.CAPTION)
                }
                .fontWeight(chip.key === this.effectiveSearchCategory() ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(chip.key === this.effectiveSearchCategory() ? this.accentColor() : this.secondaryTextColor())
                .maxLines(1)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height('100%')
                .accessibilityText(`${chip.label} ${chip.count} 条`)
                .accessibilitySelected(chip.key === this.effectiveSearchCategory())
                .onClick(() => this.selectSearchCategory(chip.key))
              }, (chip: SearchCategoryChip) =>
                `${chip.key}:${chip.count}:${chip.key === this.effectiveSearchCategory() ? 1 : 0}`)
            }
            .width('100%')
            .height('100%')
            .padding({ left: SearchPage.CATEGORY_BAR_PADDING, right: SearchPage.CATEGORY_BAR_PADDING })

            Row()
              .width(SearchPage.CATEGORY_INDICATOR_WIDTH)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentColor())
              .translate({ x: this.searchCategoryIndicatorX(), y: -5 })
              .animation({ duration: 280, curve: Curve.Friction })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(SearchPage.CATEGORY_BAR_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.searchCategoryBarWidth) {
        this.searchCategoryBarWidth = width;
      }
    })
  }

  /** 指示条居中在选中分类下方；各分类等宽平分去掉两侧留白后的宽度。 */
  searchCategoryIndicatorX(): number {
    const chips = this.searchCategoryChips();
    const count = Math.max(1, chips.length);
    const index = Math.max(0, chips.findIndex((chip: SearchCategoryChip) => chip.key === this.effectiveSearchCategory()));
    const itemWidth = (this.searchCategoryBarWidth - SearchPage.CATEGORY_BAR_PADDING * 2) / count;
    return SearchPage.CATEGORY_BAR_PADDING + itemWidth * index + (itemWidth - SearchPage.CATEGORY_INDICATOR_WIDTH) / 2;
  }

  @Builder
  searchFieldContent() {
    this.searchScopePrefix()
    Row()
      .width(1)
      .height(18)
      .margin({ left: AppSpacing.MD })
      .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
    TextInput({ placeholder: '搜索书名或作者', text: this.keyword })
      .id(SearchPage.INPUT_ID)
      .layoutWeight(1)
      .height(SearchPage.HEADER_CONTROL_SIZE)
      .enterKeyType(EnterKeyType.Search)
      .backgroundColor(Color.Transparent)
      .fontColor(this.primaryTextColor())
      .placeholderColor(this.subTextColor())
      .padding({ left: AppSpacing.SM, right: AppSpacing.XS })
      .onFocus(() => {
        this.showSearchHistoryDropdown = this.keyword.trim().length === 0 && this.searchHistory.length > 0;
      })
      .onClick(() => {
        this.showSearchHistoryDropdown = this.keyword.trim().length === 0 && this.searchHistory.length > 0;
      })
      .onChange((value: string) => {
        this.keyword = value;
        this.showSearchHistoryDropdown = value.trim().length === 0 && this.searchHistory.length > 0;
      })
      .onSubmit(() => {
        this.submitKeywordSearch();
      })

    if (this.keyword.length > 0) {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(18)
        .fontColor([this.secondaryTextColor()])
        .width(36)
        .height(36)
        .margin({ right: AppSpacing.XS })
        .accessibilityText('清除输入')
        .onClick(() => {
          this.keyword = '';
          this.showSearchHistoryDropdown = this.showResult && this.searchHistory.length > 0;
        })
    }
  }

  searchHistoryPopupPanelWidth(): number {
    return Math.min(420, Math.max(200, this.searchViewportWidth - 32));
  }

  /** 已有结果时聚焦空输入框弹出的搜索历史：沉浸光感弹出层，历史词为玻璃标签，点按搜索、长按删除。 */
  @Builder
  searchHistoryPopupContent() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text('清空')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .padding({ left: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
          .onClick(() => {
            this.showSearchHistoryDropdown = false;
            this.clearSearchHistory();
          })
      }
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (keyword: string) => {
            Text(keyword)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '72%' })
              .height(34)
              .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
              .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
              .attributeModifier(new GlassTagModifier(this.appDarkMode))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
              .opacity(ListDissolve.opacity(this.isHistoryDissolving(keyword)))
              .scale(ListDissolve.scale(this.isHistoryDissolving(keyword)))
              .blur(ListDissolve.blur(this.isHistoryDissolving(keyword)))
              .hitTestBehavior(this.isHistoryDissolving(keyword) ? HitTestMode.None : HitTestMode.Default)
              .id(this.historyTagElementId(keyword, true))
              .priorityGesture(
                GestureGroup(GestureMode.Exclusive,
                  LongPressGesture({ repeat: false })
                    .onAction(() => {
                      this.deleteSearchHistoryItem(keyword);
                    }),
                  TapGesture()
                    .onAction(() => {
                      this.showSearchHistoryDropdown = false;
                      this.searchFromHistory(keyword);
                    })
                ),
                GestureMask.IgnoreInternal
              )
          }, (keyword: string) => keyword)
        }
        .width('100%')
        .padding({ left: AppSpacing.MD, right: AppSpacing.XS, top: AppSpacing.SM })
      }
      .width('100%')
      .constraintSize({ maxHeight: 260 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width(this.searchHistoryPopupPanelWidth())
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.XS })
  }

  searchFromHistory(keyword: string): void {
    this.keyword = keyword;
    this.hideKeyboard();
    this.doSearch();
  }

  submitKeywordSearch(): void {
    this.showSearchHistoryDropdown = false;
    this.hideKeyboard();
    this.doSearch();
  }

  historyTagElementId(keyword: string, dropdown: boolean): string {
    return `search_history_${dropdown ? 'drop' : 'tag'}_${encodeURIComponent(keyword)}`;
  }

  isHistoryDissolving(keyword: string): boolean {
    return this.dissolvingHistory.length > 0 && this.dissolvingHistory.indexOf(keyword) >= 0;
  }

  /** 这些搜索记录消散后在补位动画里执行 remove；下拉框打开时量下拉里那一份。 */
  async dissolveHistory(keywords: string[], remove: () => void): Promise<void> {
    const dropdown = this.showSearchHistoryDropdown;
    await ListDissolve.fadeOut(this.getUIContext(), keywords, (keyword: string) => {
      this.dissolvingHistory = [...this.dissolvingHistory, keyword];
    }, ListDissolve.particles('search_page_root', [this.accentColor(), this.primaryTextColor(), this.subTextColor()],
      (keyword: string): string => this.historyTagElementId(keyword, dropdown),
      (): DeleteParticleBurst[] => this.deleteParticleBursts,
      (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }));
    ListDissolve.commit(this.getUIContext(), remove, () => {
      this.dissolvingHistory = ListDissolve.without(this.dissolvingHistory, keywords);
    });
  }

  async deleteSearchHistoryItem(keyword: string): Promise<void> {
    if (this.isHistoryDissolving(keyword)) return;
    try {
      await AppDatabase.getInstance().deleteSearchKeyword(keyword);
      await this.dissolveHistory([keyword], () => {
        this.searchHistory = this.searchHistory.filter((item: string) => item !== keyword);
      });
      HdsFeedback.showToast('已删除该条搜索记录');
      if (this.searchHistory.length === 0) {
        this.searchHistoryEditing = false;
        this.searchHistoryExpanded = false;
        this.showSearchHistoryDropdown = false;
      }
    } catch (e) {
      console.error('删除搜索历史失败:', e);
      HdsFeedback.showToast('删除失败');
    }
  }

  async clearSearchHistory(): Promise<void> {
    try {
      await AppDatabase.getInstance().clearSearchKeywords();
      await this.dissolveHistory([...this.searchHistory], () => {
        this.searchHistory = [];
      });
      this.searchHistoryEditing = false;
      this.searchHistoryExpanded = false;
      this.showSearchHistoryDropdown = false;
    } catch (e) {
      console.error('清空搜索历史失败:', e);
      HdsFeedback.showToast('清空失败');
    }
  }

  clearSingleSourceSearch(): void {
    this.searchSessionId++;
    this.coordinator?.cancel();
    this.coordinator = null;
    this.isSearching = false;
    this.singleSourceSearchUrl = '';
    this.singleSourceSearchName = '';
    this.searchResults = [];
    this.displayedSearchResults = [];
    this.searchCategoryCounts = [0, 0, 0, 0];
    this.searchResultKeySet.clear();
    this.showResult = false;
    this.statusMessage = '';
    this.verificationUrl = '';
    this.verificationTitle = '';
  }

  async doSearch() {
    const keyword = this.keyword.trim();
    if (!keyword) {
      HdsFeedback.showToast('请输入搜索关键词');
      return;
    }

    let sessionId = 0;
    let activeCoordinator: SearchCoordinator | null = null;
    // 先切到“搜索中”并让这一帧画出来，点击立刻有反馈；读书源、建协调器等准备工作随后进行。
    const previousShowResult = this.showResult;
    this.coordinator?.cancel();
    this.coordinator = null;
    sessionId = ++this.searchSessionId;
    this.resultArrivalTracker.reset();
    this.isSearching = true;
    this.showResult = true;
    this.searchResults = [];
    this.displayedSearchResults = [];
    this.searchCategoryCounts = [0, 0, 0, 0];
    // 新一轮搜索从完整顶栏开始，不沿用上一轮结果滚动留下的收起量。
    this.searchHeaderCollapse = 0;
    this.searchHeaderBackdropReveal = 0;
    this.statusMessage = '正在准备搜索...';
    this.verificationUrl = '';
    this.verificationTitle = '';
    await SearchPage.nextFrame();
    if (sessionId !== this.searchSessionId) return;
    const restoreIdleState = (): void => {
      if (sessionId !== this.searchSessionId) return;
      this.isSearching = false;
      this.showResult = previousShowResult;
      this.statusMessage = '';
    };
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const targetSources: BookSource[] = [];
      if (this.singleSourceSearchUrl) {
        const targetSource = await db.getBookSource(this.singleSourceSearchUrl);
        if (!targetSource) {
          HdsFeedback.showToast('指定书源不存在或已被删除');
          restoreIdleState();
          this.clearSingleSourceSearch();
          return;
        }
        targetSources.push(targetSource);
      } else {
        // 搜索页激活时已加载过书源，这里直接复用，不再每次搜索都从数据库读出全部书源规则。
        if (this.searchableSources.length === 0) {
          await this.loadSearchableSources(db);
        }
        if (sessionId !== this.searchSessionId) return;
        if (this.isNoSearchSourcesSelected() || this.effectiveSelectedSourceUrls().length === 0) {
          HdsFeedback.showToast('请先在搜索范围中选择书源');
          restoreIdleState();
          return;
        }
        if (!this.isAllSearchSourcesSelected()) {
          const selectedUrls: Set<string> = new Set<string>(this.effectiveSelectedSourceUrls());
          targetSources.push(...this.searchSourceList.filter((source: BookSource): boolean =>
            selectedUrls.has(source.bookSourceUrl)));
        }
      }

      this.searchResultKeySet.clear();
      this.statusMessage = targetSources.length === 1 ?
        `正在通过 ${this.singleSourceSearchName || targetSources[0].bookSourceName} 搜索...` :
        (targetSources.length > 1 ? `正在通过 ${targetSources.length} 个书源搜索...` : '正在搜索...');
      const chineseScript = await SearchChineseScriptRuntime.forSearch(getContext(this));
      if (sessionId !== this.searchSessionId) return;
      this.scriptVariantText = chineseScript ? chineseScript.variants(keyword).other() : '';
      const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
      activeCoordinator = coordinator;
      this.coordinator = coordinator;
      this.saveSearchHistoryLater(db, keyword);

      const callback: SearchCallback = (p: SearchProgress) => {
        if (sessionId !== this.searchSessionId || this.coordinator !== coordinator) {
          return;
        }
        if (p.sortedResults && (p.finished || (p.deltaResults && p.deltaResults.length > 0))) {
          // 搜索过程中直接采用协调器提供的完整稳定排序快照，避免按网络返回先后追加。
          this.applySearchResultsSnapshot(p.sortedResults);
          this.rebuildSearchResultKeys(p.sortedResults);
        } else if (p.finished) {
          this.applySearchResultsSnapshot(p.results);
          this.rebuildSearchResultKeys(p.results);
        } else if (p.deltaResults && p.deltaResults.length > 0) {
          this.applySearchResultsSnapshot(this.appendSearchResults(this.searchResults, p.deltaResults));
        }
        if (this.showSearchProgress) {
          this.statusMessage = p.status;
        }
        this.verificationContextToken = p.verificationContextToken || '';
        this.verificationUrl = p.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
        this.verificationTitle = p.verificationTitle || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
        if (p.finished) {
          this.requestSearchShelfStatusSync(this.searchResults);
        }
        if (p.finished) {
          this.isSearching = false;
          // 结束后分段的回退规则生效，按最终状态重排一次。
          this.applySearchResultsSnapshot(this.searchResults);
        }
      };

      const allBooks = await coordinator.search(keyword, callback, {
        exactMatch: this.exactSearch,
        exactMatchAuthor: this.exactSearchMatchAuthor,
        targetSources: targetSources,
        maxResultsPerCategory: SEARCH_RESULTS_PER_CATEGORY,
        chineseScript: chineseScript || undefined
      });
      SearchChineseScriptRuntime.saveHints(getContext(this));
      if (sessionId !== this.searchSessionId || this.coordinator !== coordinator) {
        return;
      }
      const verifyUrl = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
      if (!this.showSearchProgress || !this.isSearching) {
        const failureReason = coordinator.getLastFailureReason();
        const groupCount = this.searchExploreAggregateResults ?
          SearchResultAggregationStore.aggregate(allBooks).length : allBooks.length;
        const resultText = allBooks.length > 0 ?
          (groupCount < allBooks.length ?
            `搜索完成，共找到 ${allBooks.length} 个结果，聚合为 ${groupCount} 组` :
            `搜索完成，共找到 ${allBooks.length} 本书`) :
          (failureReason ? `搜索完成：${failureReason}` : '搜索完成，未找到相关书籍');
        this.statusMessage = verifyUrl ? `${resultText}；有书源需要网页验证` : resultText;
      }
    } catch (e) {
      if (sessionId !== this.searchSessionId || this.coordinator !== activeCoordinator) {
        return;
      }
      console.error('搜索失败:', e);
      this.isSearching = false;
      this.statusMessage = '搜索失败';
    } finally {
      if (sessionId === this.searchSessionId && this.coordinator === activeCoordinator && !this.isSearching) {
        this.coordinator = null;
      }
    }
  }

  /** 让出一帧，让刚改的界面状态先画出来，再继续后面的同步重活。 */
  private static nextFrame(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 32);
    });
  }

  async saveSearchHistoryLater(db: AppDatabase, keyword: string): Promise<void> {
    try {
      await db.saveSearchKeyword(keyword);
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map((item: SearchKeyword): string => item.keyword);
    } catch (error) {
      console.warn('保存搜索历史失败:', error);
    }
  }

  hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
  }

  onShelfChanged(): void {
    this.refreshSearchShelfStatus();
  }

  refreshSearchShelfStatus(): void {
    if (this.searchResults.length > 0) {
      this.requestSearchShelfStatusSync(this.searchResults);
    }
  }

  requestSearchShelfStatusSync(books: SearchBook[]): void {
    this.pendingShelfSyncBooks = books;
    if (!this.shelfSyncRunning) {
      this.drainSearchShelfStatusSync();
    }
  }

  appendSearchResults(existing: SearchBook[], incoming: SearchBook[]): SearchBook[] {
    const merged = existing.slice();
    for (const book of incoming) {
      const key = `${book.origin || ''}::${book.bookUrl || ''}`;
      if (!book.name || !book.bookUrl) continue;
      if (this.searchResultKeySet.has(key)) continue;
      this.searchResultKeySet.add(key);
      merged.push(book);
    }
    return merged;
  }

  rebuildSearchResultKeys(books: SearchBook[]): void {
    this.searchResultKeySet.clear();
    for (const book of books) {
      if (!book.name || !book.bookUrl) continue;
      this.searchResultKeySet.add(`${book.origin || ''}::${book.bookUrl || ''}`);
    }
  }

  async drainSearchShelfStatusSync(): Promise<void> {
    this.shelfSyncRunning = true;
    while (this.pendingShelfSyncBooks.length > 0) {
      const books = this.pendingShelfSyncBooks;
      this.pendingShelfSyncBooks = [];
      await this.syncSearchShelfStatus(books);
    }
    this.shelfSyncRunning = false;
  }

  async syncSearchShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const keys = await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
      if (version === this.shelfStatusVersion) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步搜索书架状态失败:', e);
    }
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

  openSearchBookDetail(book: SearchBook, autoStartRead: boolean = false) {
    router.pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        sharedCoverId: autoStartRead ? '' : SharedElementMotion.coverId('search', book.origin, book.bookUrl),
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

  normalizeSourceGroup(source: BookSource): string {
    return SourcePickerKit.groupLabel(source.bookSourceGroup);
  }

  saveSearchExploreSettings(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.showResultCoverBackground = this.searchExploreShowResultCoverBackground;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.aggregateSearchResults = this.searchExploreAggregateResults;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.exactSearch;
      settings.exactSearchMatchAuthor = this.exactSearchMatchAuthor;
      settings.showSearchProgress = this.showSearchProgress;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchConcurrency);
      settings.selectedSourceGroupsRaw = this.selectedSourceGroupsRaw;
      settings.selectedSourceUrlsRaw = this.selectedSourceUrlsRaw;
      settings.customSourceUrlsRaw = this.customSourceUrlsRaw;
      settings.scopeMode = this.searchScopeModeRaw;
      settings.sourceSortRaw = AppStorage.get<string>('searchExploreSourceSort') || '';
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索设置失败:', e);
    });
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

  glassCardColor(): string {
    return this.cardColor();
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

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  buttonBackgroundColor(): string {
    const normalized = AppThemeSettingsStore.normalizeColor(this.buttonColor(), AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    return `#${this.appDarkMode ? '33' : '1A'}${normalized.substring(1)}`;
  }

  usesSearchCategoryPager(): boolean {
    // 从等待结果起就保留同一个“全部”页；分类增加只追加页，不重建已显示的封面。
    return this.searchResultLayout === 'grid';
  }

  searchCategoryPageKeys(): string[] {
    const keys = this.searchCategoryChips().map((chip: SearchCategoryChip): string => chip.key);
    return keys.length > 0 ? keys : [SEARCH_CATEGORY_ALL];
  }

  searchResultTopPadding(): number {
    // 固定滚动内容尺寸，避免收起量改变留白后触发新的滚动回调，导致顶栏来回抖动。
    return this.searchTopOverlayHeight();
  }

  /**
   * 平铺分类共享收起状态。当前页没有结果列表时（搜索中、无结果、空分类）一律完整显示：
   * 占位内容不能滚动，收起后就再也拉不出搜索框。
   */
  searchHeaderCollapseValue(): number {
    return this.showResult && this.displayedSearchResults.length > 0 ?
      Math.min(this.searchHeaderCollapse, this.searchCollapsibleHeight()) : 0;
  }

  searchFieldRowHeight(): number {
    return SearchPage.FIELD_ROW_TOP_GAP + SearchPage.HEADER_CONTROL_SIZE + AppSpacing.MD;
  }

  /** 进度行：只在有结果时出现。 */
  searchStatusRowHeight(): number {
    return this.showResult ? SearchPage.STATUS_ROW_HEIGHT + AppSpacing.XS : 0;
  }

  searchHeaderBackdropHeight(): number {
    // 有结果时衬底覆盖进度行；未搜索时停在搜索框底边。
    const contentBottom = this.showResult ? this.searchCollapsibleHeight() :
      this.searchStatusRowTop() - AppSpacing.MD;
    return this.statusBarHeight + Math.max(0,
      contentBottom - this.searchHeaderCollapseValue());
  }

  searchStatusRowTop(): number {
    return this.searchFieldRowHeight();
  }

  /** 可收起的总高度：搜索框行 + 进度行（有结果时）。 */
  searchCollapsibleHeight(): number {
    return this.searchStatusRowTop() + this.searchStatusRowHeight();
  }

  searchHeaderRowOpacity(top: number, height: number): number {
    return CollapsingHeader.rowOpacity(this.searchHeaderCollapseValue(), top, height);
  }

  searchHeaderRowHitTest(top: number, height: number): HitTestMode {
    return this.searchHeaderRowOpacity(top, height) > 0.5 ? HitTestMode.Default : HitTestMode.None;
  }

  onSearchListScroll(delta: number, offset: number): void {
    const reveal = CollapsingHeader.backdropReveal(offset);
    if (reveal !== this.searchHeaderBackdropReveal) this.searchHeaderBackdropReveal = reveal;
    // 分类共享顶栏收起量，不受各自纵向位置限制；布局变化由结果列表过滤，不驱动顶栏。
    if (this.usesSearchCategoryPager() && offset <= 0 && delta >= 0) return;
    const next = CollapsingHeader.next(this.searchHeaderCollapseValue(), delta,
      this.usesSearchCategoryPager() ? this.searchCollapsibleHeight() : offset,
      this.searchCollapsibleHeight());
    if (next !== this.searchHeaderCollapse) {
      this.searchHeaderCollapse = next;
    }
  }

  onSearchListScrollStop(offset: number): void {
    const target = CollapsingHeader.settle(this.searchHeaderCollapseValue(),
      this.usesSearchCategoryPager() ? this.searchCollapsibleHeight() : offset,
      this.searchCollapsibleHeight());
    if (target !== this.searchHeaderCollapse) {
      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.searchHeaderCollapse = target;
      });
    }
  }

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。 */
  searchTopOverlayHeight(): number {
    let height = this.statusBarHeight + this.searchCollapsibleHeight();
    if (this.showSearchCategoryBar()) {
      height += SearchPage.CATEGORY_BAR_HEIGHT + AppSpacing.MD;
    }
    return height;
  }

  /** 搜索层是整页，底栏收起，只给系统导航条留位置。 */
  resultListBottomInset(): number {
    return this.navBarHeight + 20;
  }
}
