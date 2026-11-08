import { SharedElementMotion } from '../../utils/SharedElementMotion';
import { SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { BookTileLayout } from '../../utils/BookTileLayout';
import { BookCover } from './BookCover';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CoverBackdropCard } from './CoverBackdropCard';
import { SearchResultArrival } from './SearchResultArrival';
import { PreparedResultCover, ResultCoverOptions, ResultCoverPreparation } from '../../utils/ResultCoverPreparation';
import { ExploreRankStyle } from '../../utils/ExploreRankStyle';
import { SearchChineseScriptRuntime } from '../../core/book/SearchChineseScriptRuntime';
import { SearchResultAggregationStore } from '../../utils/SearchResultAggregationStore';

export type SearchBookAction = (book: SearchBook) => void;

/** 按序显示时，前一项封面最多等这么久，超时就先用 BookCover 自己加载的封面显示出来。 */
const ORDERED_REVEAL_WAIT_MS: number = 800;
/** 列表模式离末尾还剩这么多项时就请求下一页，滑到底之前内容已经接上。 */
const PREFETCH_LIST_ITEMS: number = 8;
/** 平铺模式按行预取，离末尾还剩这么多行就请求。 */
const PREFETCH_GRID_ROWS: number = 3;

/** 页面会话保留已准备好的封面 URI，不持有解码位图。 */
export class ResultCoverCache {
  covers: Map<string, PreparedResultCover> = new Map();
  signatures: Map<string, string> = new Map();
}

class SearchBookResultDataSource implements IDataSource {
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.keys.length; }

  getData(index: number): string { return this.keys[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(keys: string[], force: boolean = false): void {
    const previous = this.keys;
    const extendsPrevious = keys.length >= previous.length &&
      previous.every((key: string, index: number): boolean => key === keys[index]);
    if (!force && extendsPrevious && keys.length === previous.length) return;
    this.keys = keys.slice();
    if (!force && extendsPrevious && previous.length > 0) {
      // 加载更多、按序显示只在末尾追加：按追加通知，已显示的项原地不动，不整表重载重新布局。
      const operation: DataAddOperation = { type: DataOperationType.ADD, index: previous.length,
        count: keys.length - previous.length };
      for (const listener of this.listeners) listener.onDatasetChange([operation]);
      return;
    }
    // 同一个数据源只能用 onDatasetChange 一套接口：上面追加已经用了它，整表重载也必须走 RELOAD，
    // 再调 onDataReloaded 会在下一次通知时抛 401（书架状态变化等强制重载时崩溃）。
    for (const listener of this.listeners) listener.onDatasetChange([{ type: DataOperationType.RELOAD }]);
  }
}

@Component
export struct SearchBookResultList {
  /** 父页面在结果到达前已测得宽度，避免先按 360vp 绘制再重新分列。 */
  @Prop gridViewportWidth: number = 360;
  /** 节点只绑定稳定身份，内容更新由状态表驱动，不销毁已解码的封面。 */
  @State resultBooks: Map<string, SearchBook> = new Map<string, SearchBook>();
  @StorageProp('appDarkMode') @Watch('onCoverSettingsChanged') appDarkMode: boolean = false;
  @StorageProp('themeRevision') @Watch('onCoverSettingsChanged') themeRevision: number = 0;
  @StorageProp('appThemeBookCoverEnabled') @Watch('onCoverSettingsChanged') themeCoverEnabled: boolean = false;
  @StorageProp('bookshelfCoverAlbums') @Watch('onCoverSettingsChanged') coverAlbums: string = '';
  @StorageProp('bookshelfLightCoverAlbumId') @Watch('onCoverSettingsChanged') lightCoverAlbum: string = '';
  @StorageProp('bookshelfDarkCoverAlbumId') @Watch('onCoverSettingsChanged') darkCoverAlbum: string = '';
  @StorageProp('bookshelfCoverApplyScope') @Watch('onCoverSettingsChanged') coverScope: string = '';
  @StorageProp('bookshelfCoverTargetBooks') @Watch('onCoverSettingsChanged') coverTargets: string = '';
  @StorageProp('bookshelfIgnoreSourceCover') @Watch('onCoverSettingsChanged') ignoreSourceCover: boolean = false;
  @StorageProp('bookshelfIgnoreEmptyCoverOnly') @Watch('onCoverSettingsChanged') ignoreEmptyCoverOnly: boolean = false;
  @StorageProp('bookshelfCoverMode') @Watch('onCoverSettingsChanged') coverMode: string = '';
  @StorageProp('shelfUpdateTime') @Watch('onCoverSettingsChanged') shelfRevision: number = 0;
  @State preparedCovers: Map<string, PreparedResultCover> = new Map<string, PreparedResultCover>();
  @State visibleResultCount: number = 0;
  @State preparingCoverCount: number = 0;
  private preparedSignatures: Map<string, string> = new Map<string, string>();
  private pendingCovers: Map<string, string> = new Map<string, string>();
  private runningCovers: Set<string> = new Set<string>();
  private activeCoverTasks: number = 0;
  private coverGeneration: number = 0;
  private coverMounted: boolean = false;
  coverCache: ResultCoverCache | null = null;
  @Prop initialScrollOffset: number = 0;
  private restoredScroll: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @Prop @Watch('onBooksChanged') books: SearchBook[] = [];
  @Prop @Watch('onShelfBookKeysChanged') shelfBookKeys: string[] = [];
  @Prop busyBookKeys: string[] = [];
  @Prop @Watch('onLoadingMoreChanged') showLoadingMore: boolean = false;
  /**
   * 分页列表（发现页）一直保留同样高度的底部提示行，只换文字：提示行随加载出现又消失时，
   * 停在底部的列表会被撑高再缩回，看起来底部在来回跳。
   */
  @Prop keepLoadingFooter: boolean = false;
  /** 搜索结果里给繁体书名加“繁”角标（简繁同搜开着时）；发现页不用。 */
  @Prop markTraditional: boolean = false;
  /** 配合 keepLoadingFooter：还有下一页时提示“继续加载中”，到底了提示“没有更多了”。 */
  @Prop hasMoreResults: boolean = false;
  @Prop showKind: boolean = false;
  @Prop @Watch('onCoverSettingsChanged') showResultCover: boolean = true;
  @Prop showResultCoverBackground: boolean = true;
  @Prop @Watch('onCoverSettingsChanged') useBookshelfCoverGallery: boolean = false;
  @Prop showResultTags: boolean = true;
  @Prop showSourceLine: boolean = true;
  @Prop pageColor: string = '#F5F5F5';
  @Prop cardColor: string = '#FFFFFF';
  @Prop itemBorderColor: string = '#00000000';
  @Prop itemBorderWidth: number = 0;
  @Prop shadowColor: string = '#00000000';
  @Prop primaryTextColor: string = '#1F1F1F';
  @Prop secondaryTextColor: string = '#666666';
  @Prop subTextColor: string = '#999999';
  @Prop topPadding: number = 0;
  @Prop bottomPadding: number = 12;
  /**
   * 'list' 为卡片列表，'grid' 为封面平铺（列数随宽度自适应）；
   * 'rank' 为排行行（榜单时前三名上领奖台），'rankCompact' 为侧栏右侧的窄版排行行。
   */
  @Prop @Watch('onRankLayoutChanged') layoutMode: string = 'list';
  /** 排行样式下是否显示名次（'rank' 时连带领奖台）；不显示时只是紧凑行。 */
  @Prop @Watch('onRankLayoutChanged') showRankNumbers: boolean = false;
  /** 领奖台上的前三名；不足三本或不显示名次时为空，三本都在下面的行里。 */
  @State podiumKeys: string[] = [];
  /** 结果身份到名次（书源返回顺序，从 1 起）。 */
  private rankIndex: Map<string, number> = new Map<string, number>();
  /** 分类翻页的顶栏只响应真实纵向滚动，忽略新页布局、回顶等产生的空闲滚动回调。 */
  @Prop userScrollOnly: boolean = false;
  @Prop @Watch('onGridPageActiveChanged') gridPageActive: boolean = true;
  /** 只在分类进入时对齐滚动位置，不参与列表尺寸计算或逐帧布局。 */
  @Prop gridHeaderCollapse: number = 0;
  private gridAlignTimer: number = -1;
  private gridUserScrolled: boolean = false;
  scroller: ListScroller = new ListScroller();
  private dataSource: SearchBookResultDataSource = new SearchBookResultDataSource();
  private tagCache: Map<string, string[]> = new Map<string, string[]>();
  /** 只对当前已加载的封面显示氛围背景，轮播切图时同步更新。 */
  @State readyCoverUrls: Map<string, ResourceStr> = new Map();
  @Prop sharedCoverScope: string = '';
  /**
   * 结果顺序固定（发现页）时按原顺序逐项显示：前面的封面还没准备好，后面准备好的也先不显示，
   * 否则先到的排在前面、慢的随后插到它们中间，列表看起来在不停插队。
   */
  @Prop orderedReveal: boolean = false;
  private resultSeenAt: Map<string, number> = new Map<string, number>();
  private revealedKeys: Set<string> = new Set<string>();
  private revealTimer: number = -1;
  /** 最近一次可见的最后一个结果序号，加载结束后据此判断是否还要接着预取。 */
  private lastVisibleResultIndex: number = -1;
  onOpenBook: SearchBookAction = (_book: SearchBook) => {};
  onReadBook: SearchBookAction = (_book: SearchBook) => {};
  onToggleShelf: SearchBookAction = (_book: SearchBook) => {};
  onNeedMetadata: SearchBookAction = (_book: SearchBook) => {};
  claimArrival: (book: SearchBook) => number = (_book: SearchBook): number => -1;
  onResultReady: SearchBookAction = (_book: SearchBook): void => {};
  onReachEnd: () => void = () => {};
  /** 列表滚动：本次位移和当前滚动距离，首页据此收起或展开标题行。 */
  onListScroll: (delta: number, offset: number) => void = (_delta: number, _offset: number) => {};
  onListScrollStop: (offset: number) => void = (_offset: number) => {};

  aboutToAppear(): void {
    this.coverMounted = true;
    if (this.coverCache) {
      this.preparedCovers = new Map(this.coverCache.covers);
      this.preparedSignatures = new Map(this.coverCache.signatures);
      // 回到保留的分类时这些项早已显示过，不再当新到结果播入场。
      this.preparedCovers.forEach((_cover: PreparedResultCover, key: string): void => {
        this.revealedKeys.add(key);
      });
    }
    this.onBooksChanged();
  }

  aboutToDisappear(): void {
    this.coverMounted = false;
    this.coverGeneration++;
    this.pendingCovers.clear();
    if (this.gridAlignTimer >= 0) clearTimeout(this.gridAlignTimer);
    if (this.revealTimer >= 0) clearTimeout(this.revealTimer);
    this.revealTimer = -1;
  }

  onGridPageActiveChanged(): void {
    if (this.gridPageActive) this.drainCoverQueue();
    if (this.gridAlignTimer >= 0) clearTimeout(this.gridAlignTimer);
    this.gridAlignTimer = -1;
    if (!this.gridPageActive) return;
    // 首次挂载需等 List 绑定 Scroller；重新进入已有分类时保留更深的阅读位置。
    this.gridAlignTimer = setTimeout(() => {
      this.gridAlignTimer = -1;
      this.alignGridToHeader();
    }, 0);
  }

  alignGridToHeader(): void {
    if (!this.gridPageActive) return;
    const offset = this.scroller.currentOffset().yOffset;
    const target = Math.max(this.userScrollOnly ? this.gridHeaderCollapse : 0,
      this.restoredScroll ? 0 : this.initialScrollOffset);
    this.restoredScroll = true;
    if (offset < target) {
      this.gridUserScrolled = false;
      this.scroller.scrollTo({ xOffset: 0, yOffset: target, animation: false });
    }
  }

  onBooksChanged(): void {
    const snapshot = new Map<string, SearchBook>();
    const ranks = new Map<string, number>();
    let actionsChanged = false;
    const now = Date.now();
    for (const book of this.books) {
      const key = this.itemKey(book);
      if (!ranks.has(key)) ranks.set(key, ranks.size + 1);
      if (!this.resultSeenAt.has(key)) this.resultSeenAt.set(key, now);
      const previous = this.resultBooks.get(key);
      if (this.layoutMode !== 'grid' && previous && this.listItemKey(previous) !== this.listItemKey(book)) {
        actionsChanged = true;
      }
      snapshot.set(key, book);
    }
    this.rankIndex = ranks;
    this.resultBooks = snapshot;
    this.preparedCovers.forEach((_cover: PreparedResultCover, key: string): void => {
      if (!snapshot.has(key)) {
        this.preparedCovers.delete(key);
        this.preparedSignatures.delete(key);
      }
    });
    this.pendingCovers.forEach((_signature: string, key: string): void => {
      if (!snapshot.has(key)) this.pendingCovers.delete(key);
    });
    this.resultSeenAt.forEach((_time: number, key: string): void => {
      if (!snapshot.has(key)) this.resultSeenAt.delete(key);
    });
    this.revealedKeys.forEach((key: string): void => {
      if (!snapshot.has(key)) this.revealedKeys.delete(key);
    });
    this.requestResultCovers();
    this.publishReadyResults(actionsChanged);
    this.tagCache.clear();
    const keys = new Set(this.books.map((book: SearchBook): string => this.itemKey(book)));
    this.readyCoverUrls.forEach((_url: ResourceStr, key: string): void => {
      if (!keys.has(key)) this.readyCoverUrls.delete(key);
    });
  }

  onShelfBookKeysChanged(): void {
    // HdsListItem caches its swipe action options when the item is created.
    // Rebuild the data source when shelf membership changes so the action icon
    // and accessibility label are regenerated from the current state.
    this.publishReadyResults(true);
  }

  onCoverSettingsChanged(): void {
    if (this.coverMounted) this.requestResultCovers();
  }

  onRankLayoutChanged(): void {
    // 领奖台出现或撤下时，前三名要在领奖台和行之间搬家，整表重载。
    if (this.coverMounted) this.publishReadyResults(true);
  }

  isRankLayout(): boolean {
    return this.layoutMode === ExploreRankStyle.LAYOUT_RANK ||
      this.layoutMode === ExploreRankStyle.LIST_MODE_RANK_COMPACT;
  }

  isCompactRank(): boolean {
    return this.layoutMode === ExploreRankStyle.LIST_MODE_RANK_COMPACT;
  }

  usesPodium(): boolean {
    return this.layoutMode === ExploreRankStyle.LAYOUT_RANK && this.showRankNumbers;
  }

  requestResultCovers(): void {
    const options = ResultCoverPreparation.options(this.showResultCover, this.useBookshelfCoverGallery, this.appDarkMode);
    this.resultBooks.forEach((book: SearchBook, key: string): void => {
      const signature = ResultCoverPreparation.signature(book, options);
      if (this.preparedSignatures.get(key) === signature) return;
      if (!options.showCover) {
        const firstAdmission = !this.preparedCovers.has(key);
        this.preparedCovers.set(key, new PreparedResultCover());
        this.preparedSignatures.set(key, signature);
        this.pendingCovers.delete(key);
        if (firstAdmission && !this.orderedReveal) this.onResultReady(book);
      } else {
        this.pendingCovers.set(key, signature);
      }
    });
    this.publishReadyResults();
    this.drainCoverQueue();
  }

  publishReadyResults(force: boolean = false): void {
    if (this.coverCache) {
      this.coverCache.covers = new Map(this.preparedCovers);
      this.coverCache.signatures = new Map(this.preparedSignatures);
    }
    const readyKeys = this.orderedReveal ? this.orderedReadyKeys() :
      Array.from(this.resultBooks.keys()).filter((key: string): boolean => this.preparedCovers.has(key));
    this.visibleResultCount = readyKeys.length;
    this.preparingCoverCount = this.pendingCovers.size;
    // 按序显示时前三本陆续到齐，凑满三本才上领奖台，之前先作为普通行显示。
    const podium = this.usesPodium() && readyKeys.length >= 3 ? readyKeys.slice(0, 3) : [];
    if (podium.join('\n') !== this.podiumKeys.join('\n')) this.podiumKeys = podium;
    this.dataSource.replace(podium.length > 0 ? readyKeys.slice(3) : readyKeys, force);
  }

  /** 从头取连续可显示的项，遇到还在准备且没等够的封面就停下，等它好了或超时再继续。 */
  orderedReadyKeys(): string[] {
    const now = Date.now();
    const keys: string[] = [];
    let waitMs = -1;
    for (const key of this.resultBooks.keys()) {
      if (!this.preparedCovers.has(key) && !this.revealedKeys.has(key)) {
        const waited = now - (this.resultSeenAt.get(key) ?? now);
        if (waited < ORDERED_REVEAL_WAIT_MS) {
          waitMs = ORDERED_REVEAL_WAIT_MS - waited;
          break;
        }
      }
      if (!this.revealedKeys.has(key)) {
        this.revealedKeys.add(key);
        this.onResultReady(this.resultBook(key));
      }
      keys.push(key);
    }
    if (this.revealTimer >= 0) clearTimeout(this.revealTimer);
    this.revealTimer = -1;
    if (waitMs >= 0 && this.coverMounted) {
      this.revealTimer = setTimeout((): void => {
        this.revealTimer = -1;
        if (this.coverMounted) this.publishReadyResults();
      }, waitMs + 16);
    }
    return keys;
  }

  drainCoverQueue(): void {
    if (!this.coverMounted || !this.gridPageActive) return;
    for (const key of this.pendingCovers.keys()) {
      if (this.activeCoverTasks >= 6) break;
      if (this.runningCovers.has(key)) continue;
      const book = this.resultBooks.get(key);
      const signature = this.pendingCovers.get(key);
      if (!book || signature === undefined) continue;
      const options = ResultCoverPreparation.options(this.showResultCover, this.useBookshelfCoverGallery, this.appDarkMode);
      const generation = this.coverGeneration;
      this.runningCovers.add(key);
      this.activeCoverTasks++;
      this.prepareResultCover(book, options).catch((): PreparedResultCover => new PreparedResultCover())
        .then((cover: PreparedResultCover): void => {
          if (!this.coverMounted || generation !== this.coverGeneration ||
            this.pendingCovers.get(key) !== signature || !this.resultBooks.has(key)) return;
          const firstAdmission = !this.preparedCovers.has(key);
          this.preparedCovers.set(key, cover);
          this.preparedSignatures.set(key, signature);
          this.pendingCovers.delete(key);
          if (firstAdmission && !this.orderedReveal) this.onResultReady(this.resultBook(key));
          this.publishReadyResults();
        }).finally((): void => {
          this.runningCovers.delete(key);
          this.activeCoverTasks--;
          this.drainCoverQueue();
        });
    }
  }

  prepareResultCover(book: SearchBook, options: ResultCoverOptions): Promise<PreparedResultCover> {
    return ResultCoverPreparation.prepare(getContext(this), book, options);
  }

  resultBook(key: string): SearchBook {
    return this.resultBooks.get(key) || new SearchBook();
  }

  onLoadingMoreChanged(): void {
    // 新一页很短时停在原处也看得到末尾，滚动回调不会再来，加载结束后补一次判断。
    if (!this.showLoadingMore) this.prefetchNearEnd(this.lastVisibleResultIndex);
  }

  /** 末尾按已拿到的全部结果算（含还在等封面的），等封面的项够多时不会提前再要一页。 */
  prefetchNearEnd(lastVisibleIndex: number): void {
    if (lastVisibleIndex < 0) return;
    this.lastVisibleResultIndex = lastVisibleIndex;
    if (!this.gridPageActive || this.showLoadingMore) return;
    const threshold = this.layoutMode === 'grid' ?
      BookTileLayout.columnCount(this.gridViewportWidth) * PREFETCH_GRID_ROWS : PREFETCH_LIST_ITEMS;
    if (this.resultBooks.size - 1 - lastVisibleIndex <= threshold) this.onReachEnd();
  }

  /** 弹性回弹（越过末尾后弹回）也会报滚动位移，不能拿来展开或收起顶栏。 */
  isEndOverscrollRebound(delta: number): boolean {
    return delta < 0 && this.scroller.isAtEnd();
  }

  showsLoadingFooter(): boolean {
    if (this.visibleResultCount === 0) return false;
    return this.keepLoadingFooter || this.showLoadingMore || this.preparingCoverCount > 0;
  }

  @Builder
  loadingFooter() {
    Row() {
      if (this.showLoadingMore || this.preparingCoverCount > 0 || (this.keepLoadingFooter && this.hasMoreResults)) {
        LoadingProgress()
          .width(20)
          .height(20)
        Text('继续加载中...')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
          .margin({ left: AppSpacing.MD })
      } else {
        Text('没有更多了')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
      }
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      if (this.layoutMode === 'grid') {
        this.resultGrid()
      } else {
        this.resultList()
      }
      if (this.visibleResultCount === 0 && this.preparingCoverCount > 0) {
        Column({ space: AppSpacing.MD }) {
          LoadingProgress().width(28).height(28)
          Text('正在准备封面').fontSize(AppFontSize.BODY).fontColor(this.subTextColor)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topPadding })
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  /** 封面平铺：多列 List 保留懒加载，列数随宽度自适应；顶部留白与底部加载提示放在分组页眉页脚里，不占格子。 */
  @Builder
  resultGrid() {
    List({ scroller: this.scroller }) {
      ListItemGroup({ header: this.gridHeader(), footer: this.gridFooter(), space: AppSpacing.LG }) {
        LazyForEach(this.dataSource, (key: string) => {
          ListItem() {
            SearchResultArrival({
              claimArrival: (): number => this.gridPageActive ? this.claimArrival(this.resultBook(key)) : -1
            }) {
              this.searchResultGridItem(key)
            }
          }
        }, (key: string) => `grid_${key}`)
      }
    }
    .lanes(BookTileLayout.columnCount(this.gridViewportWidth), BookTileLayout.columnGap(this.gridViewportWidth))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: BookTileLayout.SIDE_PADDING, right: BookTileLayout.SIDE_PADDING })
    .height('100%')
    .backgroundColor(this.pageColor)
    .scrollBar(BarState.Auto)
    .onAppear(() => this.onGridPageActiveChanged())
    .onReachEnd(() => {
      if (this.preparingCoverCount === 0) this.onReachEnd();
    })
    .onScrollVisibleContentChange((_start: VisibleListContentInfo, end: VisibleListContentInfo) => {
      const index = end.itemIndexInGroup ??
        (end.itemGroupArea === ListItemGroupArea.IN_FOOTER_AREA ? this.visibleResultCount - 1 : -1);
      this.prefetchNearEnd(index);
    })
    .onDidScroll((delta: number, state: ScrollState) => {
      if (this.userScrollOnly && (state === ScrollState.Idle || delta === 0)) return;
      if (this.isEndOverscrollRebound(delta)) return;
      this.gridUserScrolled = true;
      this.onListScroll(delta, this.scroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      if (this.userScrollOnly && !this.gridUserScrolled) return;
      this.gridUserScrolled = false;
      this.onListScrollStop(this.scroller.currentOffset().yOffset);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  gridHeader() {
    Row()
      .width('100%')
      .height(this.topPadding + AppSpacing.XS)
  }

  @Builder
  gridFooter() {
    Column() {
      if (this.showsLoadingFooter()) {
        this.loadingFooter()
      }
      Column()
        .height(this.bottomPadding)
    }
    .width('100%')
  }

  @Builder
  searchResultGridItem(key: string) {
    // Builder 只捕获稳定 key，UI 闭包从状态表读最新书籍；更新数量不重建 BookCover。
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack() {
          Column() {
            Text(this.safeText(this.resultBook(key).name, '书').substring(0, 1))
              .fontSize(AppFontSize.HEADLINE)
              .fontColor(this.showResultCover ? this.secondaryTextColor : '#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          // 有封面时使用中性底色，避免圆角抗锯齿边缘透出主题色。
          .backgroundColor(this.showResultCover ? this.cardColor : this.accentColor())

          if (this.showResultCover) {
            this.resultCover(key, 8, 360, 480)
          }
        }
        .width('100%')
        .aspectRatio(0.75)
        .borderRadius(8)
        .clip(true)

        if (this.resultBook(key).aggregationCount > 1) {
          Text(`${this.resultBook(key).aggregationCount} 个结果`)
            .fontSize(AppFontSize.MICRO)
            .fontColor('#FFFFFF')
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
            .backgroundColor('#99000000')
            .borderRadius(8)
            .margin({ top: AppSpacing.XS, right: AppSpacing.XS })
        } else if (this.mediaBadge(this.resultBook(key))) {
          Text(this.mediaBadge(this.resultBook(key)))
            .fontSize(AppFontSize.MICRO)
            .fontColor('#FFFFFF')
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
            .backgroundColor(this.accentColor())
            .borderRadius(8)
            .margin({ top: AppSpacing.XS, right: AppSpacing.XS })
        }
      }
      .width('100%')
      // 共享转场挂在带底色和阴影的外层：返回时目标元素在转场结束前是隐藏的，只挂内层会先露出空白卡片和阴影。
      .sharedTransition(this.resultSharedCoverId(key), { duration: 360, curve: Curve.Friction, type: SharedTransitionEffectType.Exchange })
      // 阴影与内层裁切使用相同圆角；外层不裁切，以保留圆角外的柔和阴影。
      .borderRadius(8)
      .backgroundColor(this.cardColor)
      .shadow({ radius: 8, color: this.isDarkMode() ? '#55000000' : '#22000000', offsetX: 0, offsetY: 3 })

      Text(this.safeText(this.resultBook(key).name, '未知书名'))
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: AppSpacing.XS })
      Text(this.safeText(this.resultBook(key).author, '作者未知'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenBook(this.resultBook(key));
    })
    .onAppear(() => {
      if (this.resultBook(key).aggregationCount <= 1 &&
        !this.safeText(this.resultBook(key).author, '')) {
        this.onNeedMetadata(this.resultBook(key));
      }
    })
  }

  @Builder
  resultList() {
    List({ scroller: this.scroller, space: this.isRankLayout() ? AppSpacing.SM : AppSpacing.MD }) {
      if (this.topPadding > 0) {
        ListItem() {
          Row()
            .height(this.topPadding)
        }
      }

      if (this.podiumKeys.length === 3) {
        ListItem() {
          this.rankPodium()
        }
        .margin({ bottom: AppSpacing.XS })
      }

      LazyForEach(this.dataSource, (key: string) => {
        this.searchResultItem(key)
      }, (key: string) => this.listItemKey(this.resultBook(key)))

      if (this.showsLoadingFooter()) {
        ListItem() {
          this.loadingFooter()
        }
      }

      ListItem() {
        Column()
          .height(this.bottomPadding)
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    // 侧栏右侧左边紧挨着频道栏，只留一点缝。
    .padding({ left: this.isCompactRank() ? AppSpacing.XS : AppSpacing.XL, right: AppSpacing.XL })
    .height('100%')
    .backgroundColor(this.pageColor)
    .scrollBar(BarState.Auto)
    .onReachEnd(() => {
      if (this.preparingCoverCount === 0) this.onReachEnd();
    })
    .onScrollIndex((_start: number, end: number) => {
      // 顶部留白、领奖台各占一项（领奖台里有三本），末尾的提示行和底部留白按最后一个结果算。
      const podium = this.podiumKeys.length === 3;
      const index = end - (this.topPadding > 0 ? 1 : 0) + (podium ? 2 : 0);
      this.prefetchNearEnd(Math.min(index, this.visibleResultCount - 1));
    })
    .onAppear(() => this.onGridPageActiveChanged())
    .onDidScroll((delta: number, state: ScrollState) => {
      if (this.userScrollOnly && (state === ScrollState.Idle || delta === 0)) return;
      if (this.isEndOverscrollRebound(delta)) return;
      this.gridUserScrolled = true;
      this.onListScroll(delta, this.scroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      if (this.userScrollOnly && !this.gridUserScrolled) return;
      this.gridUserScrolled = false;
      this.onListScrollStop(this.scroller.currentOffset().yOffset);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private supportsHdsListItem(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  @Builder
  searchResultItem(key: string) {
    if (this.supportsHdsListItem()) {
      HdsListItem({
        customItemBuilder: () => {
          this.animatedSearchResultCard(key)
        },
        // 聚合项只是进入同名结果页，不能直接执行某个来源书籍的操作。
        swipeActionOptions: this.resultBook(key).aggregationCount > 1 ? undefined : this.searchResultSwipeActions(this.resultBook(key))
      })
    } else {
      // API 25 及以下保留原生 ListItem，避免加载 HDS 滑动容器。
      ListItem() {
        this.animatedSearchResultCard(key)
      }
      .swipeAction(this.resultBook(key).aggregationCount > 1 ? {} : {
        end: {
          builder: () => {
            this.searchResultFallbackSwipeActions(key)
          },
          actionAreaDistance: 128,
          onAction: () => this.onReadBook(this.resultBook(key))
        },
        edgeEffect: SwipeEdgeEffect.Spring
      })
    }
  }

  @Builder
  animatedSearchResultCard(key: string) {
    SearchResultArrival({
      claimArrival: (): number => this.gridPageActive ? this.claimArrival(this.resultBook(key)) : -1
    }) {
      if (this.isRankLayout()) {
        this.rankRow(key)
      } else {
        this.searchResultCard(key)
      }
    }
  }

  /** 排行行：名次、小封面、书名和两行信息；窄版去掉简介，只留字数或状态。 */
  @Builder
  rankRow(key: string) {
    Row({ space: this.isCompactRank() ? AppSpacing.SM : 10 }) {
      if (this.showRankNumbers) {
        Text(`${this.rankOf(key)}`)
          .width(this.isCompactRank() ? 22 : 28)
          .fontSize(this.rankOf(key) > 99 ? AppFontSize.BODY : (this.isCompactRank() ? 18 : 20))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.rankColor(this.rankOf(key)))
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }

      if (this.showResultCover) {
        Stack() {
          this.resultCover(key, 5, 150, 200)
        }
        .sharedTransition(this.resultSharedCoverId(key), { duration: 360, curve: Curve.Friction, type: SharedTransitionEffectType.Exchange })
        .width(this.isCompactRank() ? 44 : 46)
        .height(this.isCompactRank() ? 59 : 62)
        .borderRadius(5)
        .clip(true)
      }

      Column({ space: 2 }) {
        Row({ space: AppSpacing.XS }) {
          Text(this.safeText(this.resultBook(key).name, '未知书名'))
            .fontSize(this.isCompactRank() ? AppFontSize.BODY : AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.mediaBadge(this.resultBook(key))) {
            Text(this.mediaBadge(this.resultBook(key)))
              .fontSize(AppFontSize.MICRO)
              .fontColor(this.accentColor())
              .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
              .border({ width: 1, color: this.accentColor() })
              .borderRadius(4)
          }
        }
        .width('100%')

        Text(this.rankByline(this.resultBook(key)))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.rankDetailLine(this.resultBook(key))) {
          Text(this.rankDetailLine(this.resultBook(key)))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: this.showRankNumbers ? 6 : AppSpacing.MD, right: AppSpacing.MD, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.cardColor)
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: this.itemBorderWidth, color: this.itemBorderColor })
    .shadow({ radius: 10, color: this.shadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.onOpenBook(this.resultBook(key));
    })
    .onAppear(() => {
      if (this.resultBook(key).aggregationCount <= 1 &&
        !this.safeText(this.resultBook(key).author, '')) {
        this.onNeedMetadata(this.resultBook(key));
      }
    })
  }

  /** 前三名领奖台：第一名居中稍大，二、三名在两侧；名次徽章压在封面左上角。 */
  @Builder
  rankPodium() {
    Row({ space: AppSpacing.SM }) {
      this.podiumColumn(this.podiumKeys[1], 2)
      this.podiumColumn(this.podiumKeys[0], 1)
      this.podiumColumn(this.podiumKeys[2], 3)
    }
    .width('100%')
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 18, bottom: 14 })
    .alignItems(VerticalAlign.Bottom)
    .backgroundColor(this.cardColor)
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: this.itemBorderWidth, color: this.itemBorderColor })
    .shadow({ radius: 10, color: this.shadowColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  podiumColumn(key: string, rank: number) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack() {
          Column() {
            Text(this.safeText(this.resultBook(key).name, '书').substring(0, 1))
              .fontSize(AppFontSize.HEADLINE)
              .fontColor(this.showResultCover ? this.secondaryTextColor : '#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.showResultCover ? this.cardColor : this.accentColor())

          if (this.showResultCover) {
            this.resultCover(key, 6, 240, 320)
          }
        }
        .width(rank === 1 ? 86 : 70)
        .height(rank === 1 ? 115 : 93)
        .borderRadius(6)
        .clip(true)
        .sharedTransition(this.resultSharedCoverId(key), { duration: 360, curve: Curve.Friction, type: SharedTransitionEffectType.Exchange })

        Text(`${rank}`)
          .width(22)
          .height(22)
          .borderRadius(11)
          .textAlign(TextAlign.Center)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(ExploreRankStyle.medalColor(rank, this.isDarkMode()))
          .shadow({ radius: 4, color: '#33000000', offsetX: 0, offsetY: 1 })
          .markAnchor({ x: 6, y: 6 })
      }

      Text(this.safeText(this.resultBook(key).name, '未知书名'))
        .fontSize(rank === 1 ? AppFontSize.BODY : AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: AppSpacing.XS })
      Text(this.safeText(this.resultBook(key).author, '作者未知'))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(rank === 1 ? 1.2 : 1)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(`第 ${rank} 名，${this.safeText(this.resultBook(key).name, '未知书名')}`)
    .onClick(() => {
      this.onOpenBook(this.resultBook(key));
    })
    .onAppear(() => {
      if (!this.safeText(this.resultBook(key).author, '')) this.onNeedMetadata(this.resultBook(key));
    })
  }

  rankOf(key: string): number {
    return this.rankIndex.get(key) ?? 0;
  }

  rankColor(rank: number): string {
    return ExploreRankStyle.medalColor(rank, this.isDarkMode()) || this.subTextColor;
  }

  /** 第二行：作者和第一个分类标签。 */
  rankByline(book: SearchBook): string {
    const parts: string[] = [this.safeText(book.author, '作者未知')];
    const tags = BookDisplayHelper.splitTags(this.safeText(book.kind, ''), '');
    if (tags.length > 0) parts.push(tags[0]);
    return parts.join(' · ');
  }

  /** 第三行：宽版放简介（没有就放最新章节），窄版放字数和状态。 */
  rankDetailLine(book: SearchBook): string {
    if (this.isCompactRank()) {
      const parts: string[] = [];
      if (this.safeText(book.wordCount, '')) parts.push(this.safeText(book.wordCount, ''));
      if (this.safeText(book.status, '')) parts.push(this.safeText(book.status, ''));
      if (parts.length === 0 && this.safeText(book.latestChapterTitle, '')) {
        parts.push(this.safeText(book.latestChapterTitle, ''));
      }
      return parts.join(' · ');
    }
    const intro = this.safeText(book.intro, '').replace(/\s+/g, ' ');
    if (intro) return intro;
    return this.safeText(book.latestChapterTitle, '') ? `最新：${this.safeText(book.latestChapterTitle, '')}` : '';
  }

  @Builder
  searchResultCard(key: string) {
    // 尾随闭包形式的自定义组件后面不能再接属性，圆角、边框、点击等挂在外层 Column 上。
    Column() {
      CoverBackdropCard({
        cover: this.showResultCover && this.showResultCoverBackground ? this.backdropCover(this.resultBook(key)) : '',
        showBackdrop: this.showResultCoverBackground,
        accentColor: this.accentColor(),
        cardColor: this.cardColor,
        darkMode: this.isDarkMode()
      }) {
        Row() {
          if (this.showResultCover) {
            this.coverView(key)
          }

          Column() {
            Row({ space: AppSpacing.SM }) {
              Text(this.safeText(this.resultBook(key).name, '未知书名'))
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)

              if (this.isTraditionalTitle(this.resultBook(key))) {
                Text('繁')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.subTextColor)
                  .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: 1, bottom: 1 })
                  .border({ width: 1, color: this.subTextColor })
                  .borderRadius(ThemeRuntime.mediumRadius())
              }

              if (this.mediaBadge(this.resultBook(key))) {
                Text(this.mediaBadge(this.resultBook(key)))
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.accentColor())
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
                  .border({ width: 1, color: this.accentColor() })
                  .borderRadius(ThemeRuntime.mediumRadius())
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Text(this.safeText(this.resultBook(key).author, '作者未知'))
              .fontSize(AppFontSize.BODY)
              .fontColor(this.secondaryTextColor)
              .margin({ top: AppSpacing.XS })

            if (this.showResultTags && this.getTags(this.resultBook(key)).length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.getTags(this.resultBook(key)), (tag: string, index: number) => {
                  this.tagChip(tag, index)
                })
              }
              .width('100%')
              .margin({ top: AppSpacing.SM })
            }

            if (this.metadataLine(this.resultBook(key))) {
              Text(this.metadataLine(this.resultBook(key)))
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor)
                .margin({ top: AppSpacing.XXS })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            if (this.showSourceLine) {
              Text(this.sourceLine(this.resultBook(key)))
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor)
                .margin({ top: this.showResultTags && this.getTags(this.resultBook(key)).length > 0 ? 6 : 4 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .margin({ left: this.showResultCover ? 12 : 0 })
          .alignItems(HorizontalAlign.Start)

          if (this.resultBook(key).aggregationCount > 1) {
            this.aggregationIndicator(key)
          }
        }
        .width('100%')
        .padding(AppSpacing.LG)
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .border({ width: this.itemBorderWidth, color: this.itemBorderColor })
    .shadow({ radius: 10, color: this.shadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.onOpenBook(this.resultBook(key));
    })
    .onAppear(() => {
      if (this.resultBook(key).aggregationCount <= 1 &&
        !this.safeText(this.resultBook(key).author, '')) {
        this.onNeedMetadata(this.resultBook(key));
      }
    })
  }

  private toggleShelfFromSwipe(book: SearchBook): void {
    if (SearchBookShelfHelper.isBusy(book, this.busyBookKeys)) return;
    // 先收起横滑菜单，避免菜单一直停留到入架完成。
    this.scroller.closeAllSwipeActions();
    this.onToggleShelf(book);
  }

  private searchResultSwipeActions(book: SearchBook): HdsSwipeActionOptions {
    const options: HdsSwipeActionOptions = {
      icons: [
        {
          icon: new SymbolGlyphModifier(this.searchResultShelfActionIcon(book)),
          // 使用主题按钮色，随当前主题保持一致并确保图标有足够对比度。
          backgroundColor: ThemeRuntime.buttonColor(this.isDarkMode()),
          iconOptions: {
            accessibilityText: SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? '移出书架' : '加入书架'
          },
          onAction: () => {
            this.toggleShelfFromSwipe(book);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.book')),
          backgroundColor: ThemeRuntime.accentColor(this.isDarkMode()),
          iconOptions: {
            accessibilityText: '阅读'
          },
          onAction: () => {
            this.onReadBook(book);
          }
        }
      ]
    };
    return options;
  }

  searchResultShelfActionIcon(book: SearchBook): Resource {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ?
      $r('sys.symbol.bookshelf_badge_checkmark') : $r('sys.symbol.bookshelf_badge_plus');
  }

  @Builder
  searchResultFallbackSwipeActions(key: string) {
    Row() {
      Column({ space: AppSpacing.XS }) {
        SymbolGlyph(this.searchResultShelfActionIcon(this.resultBook(key)))
          .fontSize(22)
          .fontColor(['#FFFFFF'])
        Text(SearchBookShelfHelper.isInShelf(this.resultBook(key), this.shelfBookKeys) ? '移出书架' : '加入书架')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(82)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeRuntime.buttonColor(this.isDarkMode()))
      .onClick(() => this.toggleShelfFromSwipe(this.resultBook(key)))

      Column({ space: AppSpacing.XS }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(22)
          .fontColor(['#FFFFFF'])
        Text('阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(64)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeRuntime.accentColor(this.isDarkMode()))
      .onClick(() => this.onReadBook(this.resultBook(key)))
    }
    .height('100%')
  }

  @Builder
  aggregationIndicator(key: string) {
    Column({ space: AppSpacing.XXS }) {
      Text(`${this.resultBook(key).aggregationCount}`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
      Text('结果')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
    }
    .width(64)
    .height(44)
    .margin({ left: AppSpacing.LG })
    .justifyContent(FlexAlign.Center)
  }


  // 小说是默认类型，不加角标。
  mediaBadge(book: SearchBook): string {
    const category = BookTypeSupport.mediaCategoryOf(book);
    if (category === BookTypeSupport.CATEGORY_COMIC) return '漫画';
    if (category === BookTypeSupport.CATEGORY_AUDIO) return '有声';
    if (category === BookTypeSupport.CATEGORY_VIDEO) return '视频';
    return '';
  }

  /** 简繁同搜开着时，书名里有繁体字就标“繁”；聚合组的代表条目优先取简体，标了说明整组都是繁体。 */
  isTraditionalTitle(book: SearchBook): boolean {
    if (!this.markTraditional) return false;
    const script = SearchChineseScriptRuntime.ready();
    return !!script && script.isTraditional(book.name || '');
  }

  sourceLine(book: SearchBook): string {
    if (book.aggregationCount > 1) {
      const traditional = this.markTraditional ? SearchResultAggregationStore.traditionalCount(book.aggregationKey) : 0;
      if (traditional > 0 && traditional < book.aggregationCount) {
        return `已聚合 ${book.aggregationCount} 个同名结果（含繁体 ${traditional} 个），点击展开`;
      }
      return `已聚合 ${book.aggregationCount} 个同名结果，点击展开`;
    }
    return this.safeText(book.originName, '');
  }

  getTags(book: SearchBook): string[] {
    if (!this.showResultTags) {
      return [];
    }
    const key = `${this.itemKey(book)}\n${book.kind || ''}\n${book.status || ''}`;
    const cached = this.tagCache.get(key);
    if (cached) return cached;
    const tags = BookDisplayHelper.splitTags(this.safeText(book.kind, ''), this.safeText(book.status, ''));
    this.tagCache.set(key, tags);
    return tags;
  }

  @Builder
  tagChip(tag: string, index: number) {
    Text(tag)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.isDarkMode()))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
      .attributeModifier(BookDisplayHelper.getGlassTagModifier(index, this.isDarkMode()))
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.XS })
  }

  @Builder
  resultCover(key: string, radius: number, decodeWidth: number, decodeHeight: number) {
    BookCover({
      preparedSelection: this.preparedCovers.get(key) || null,
      bookUrl: this.resultBook(key).bookUrl, origin: this.resultBook(key).origin,
      coverUrl: this.resultBook(key).coverUrl, name: this.resultBook(key).name, author: this.resultBook(key).author,
      useBookshelfCover: this.useBookshelfCoverGallery,
      placeholderColor: this.cardColor, cornerRadius: radius, decodeWidth, decodeHeight,
      onReadyCover: (url: ResourceStr): void => {
        if (this.readyCoverUrls.get(key) !== url) this.readyCoverUrls.set(key, url);
      }
    })
  }

  @Builder
  coverView(key: string) {
    Stack() {
      this.resultCover(key, 6, 180, 240)
    }
    .sharedTransition(this.resultSharedCoverId(key), { duration: 360, curve: Curve.Friction, type: SharedTransitionEffectType.Exchange })
    .width(54)
    .height(72)
    .borderRadius(6)
    .clip(true)
  }

  resultSharedCoverId(key: string): string {
    const book = this.resultBook(key);
    return book.aggregationCount > 1 ? '' : SharedElementMotion.coverId(this.sharedCoverScope, book.origin, book.bookUrl);
  }

  isDarkMode(): boolean {
    return this.appDarkMode;
  }

  backdropCover(book: SearchBook): ResourceStr {
    return this.readyCoverUrls.get(this.itemKey(book)) || '';
  }

  accentColor(): string {
    return this.isDarkMode() ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  metadataLine(book: SearchBook): string {
    const parts: string[] = [];
    if (this.safeText(book.wordCount, '')) parts.push(`字数：${this.safeText(book.wordCount, '')}`);
    if (this.safeText(book.latestChapterTitle, '')) parts.push(`最新：${this.safeText(book.latestChapterTitle, '')}`);
    if (this.safeText(book.updateTime, '')) parts.push(`更新：${this.safeText(book.updateTime, '')}`);
    return parts.join(' · ');
  }

  itemKey(book: SearchBook): string {
    if (book.aggregationKey) {
      return `aggregation:${book.aggregationKey}`;
    }
    const key = SearchBookShelfHelper.keyOf(book);
    return key || JSON.stringify([book.origin, book.bookUrl, book.name]);
  }

  listItemKey(book: SearchBook): string {
    const baseKey = this.itemKey(book);
    if (book.aggregationCount > 1) return baseKey;
    const shelfState = SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys) ? 'shelf' : 'not_shelf';
    return `${baseKey}|${shelfState}`;
  }

  safeText(value: string, fallback: string): string {
    const text = (value || '').trim();
    return text || fallback;
  }
}
