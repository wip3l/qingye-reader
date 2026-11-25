import { BookCover } from '../components/book/BookCover';
import { router, promptAction } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { appDb } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { OpdsBookService } from '../opds/OpdsBookService';
import { OpdsClient, OpdsDownloadHandle } from '../opds/OpdsClient';
import { OpdsError } from '../opds/OpdsError';
import {
  OpdsEntry,
  OpdsFacetGroup,
  OpdsFeed,
  OpdsFeedCacheEntry,
  OpdsLink,
  OpdsSearchTemplate,
  OpdsServerConfig
} from '../opds/OpdsModels';
import { OpdsSecretStore } from '../opds/OpdsSecretStore';
import { OpdsSettingsStore } from '../opds/OpdsSettingsStore';
import { BookCoverCache } from '../utils/BookCoverCache';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { KeywordMatch } from '../utils/KeywordMatch';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { DialogStyle } from '../theme/DialogStyle';
import { ThemedDialog } from '../utils/ThemedDialog';

/** 路径上的一层。离开这一层时记下已加载的条目和滚动位置，返回时直接恢复，不用重新联网。 */
class OpdsNavFrame {
  url: string = '';
  title: string = '';
  savedAt: number = 0;
  entries: OpdsEntry[] = [];
  facets: OpdsFacetGroup[] = [];
  nextUrl: string = '';
  pageCount: number = 0;
  hasMore: boolean = false;
  scrollOffset: number = 0;
}

class OpdsDownloadRow {
  key: string = '';
  link: OpdsLink = new OpdsLink();
  formatLabel: string = '';
  sizeText: string = '';
  kind: string = '';
  kindLabel: string = '';
  downloadable: boolean = false;
  exists: boolean = false;
  downloading: boolean = false;
  received: number = 0;
  total: number = 0;
}

class OpdsEntryDataSource implements IDataSource {
  private entries: OpdsEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): OpdsEntry {
    return this.entries[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(entries: OpdsEntry[]): void {
    this.entries = entries.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

@Entry
@Component
struct OpdsBrowsePage {
  private static readonly FEED_TTL_MS: number = 5 * 60 * 1000;
  private static readonly MAX_PAGES: number = 50;
  private static readonly MAX_COVER_BYTES: number = 5 * 1024 * 1024;
  private static readonly SEARCH_HEIGHT: number = 40;
  private static readonly SEARCH_INPUT_ID: string = 'opds_browse_search_input';
  /** 搜索范围：书库自己的搜索（OpenSearch）/ 只筛当前这一层已加载的条目。 */
  private static readonly SCOPE_SERVER: string = 'server';
  private static readonly SCOPE_LOCAL: string = 'local';

  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @StorageProp('searchExploreUseBookshelfCoverGallery') useBookshelfCover: boolean = false;
  @State server: OpdsServerConfig = new OpdsServerConfig();
  @State serverMissing: boolean = false;
  @State stack: OpdsNavFrame[] = [];
  @State @Watch('onEntriesChanged') entries: OpdsEntry[] = [];
  @State facets: OpdsFacetGroup[] = [];
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State hasMore: boolean = false;
  @State errorCode: string = '';
  @State errorMessage: string = '';
  @State emptyHint: string = '这个书库还是空的';
  @State searchAvailable: boolean = false;
  @State searchMode: boolean = false;
  @State searchInput: string = '';
  @State searchScope: string = 'local';
  /** “整个书库”范围下已按搜索键发出请求，列表显示书库返回的结果。 */
  @State searchSubmitted: boolean = false;
  @State searchCount: number = 0;
  @State headerCollapse: number = 0;
  @State searchEntryWidth: number = 0;
  @State searchFieldWidth: number = 0;
  @State loadingSweep: boolean = false;
  @State shelfRevision: number = 0;
  @State coverMap: Map<string, string> = new Map();
  @State @Watch('onDetailFlagChanged') showDetail: boolean = false;
  @State detailEntry: OpdsEntry = new OpdsEntry();
  @State detailText: string = '';
  @State detailTextLong: boolean = false;
  @State detailTextExpanded: boolean = false;
  @State downloadRows: OpdsDownloadRow[] = [];
  @State downloadBusy: boolean = false;
  @State downloadText: string = '';
  @State downloadProgress: number = 0;

  private password: string = '';
  private client: OpdsClient | null = null;
  private searchTemplate: OpdsSearchTemplate | null = null;
  private feedCache: Map<string, OpdsFeedCacheEntry> = new Map();
  private pendingCovers: Set<string> = new Set();
  private readonly entrySource: OpdsEntryDataSource = new OpdsEntryDataSource();
  private requestSeq: number = 0;
  private nextUrl: string = '';
  private pageCount: number = 0;
  private lastSearchQuery: string = '';
  private activeDownload: OpdsDownloadHandle | null = null;
  private keepDownloadOnDetailClose: boolean = false;
  private detailBestRow: OpdsDownloadRow | null = null;
  private detailImportedBook: Book | null = null;
  private pendingPreviewBook: Book | null = null;
  private retryOnPageShow: boolean = false;
  private initialized: boolean = false;
  private readonly detailDialogSession: SystemDialogSession = new SystemDialogSession();
  private readonly searchController: TextInputController = new TextInputController();
  private readonly searchSource: OpdsEntryDataSource = new OpdsEntryDataSource();
  private readonly listScroller: Scroller = new Scroller();
  private readonly searchScroller: Scroller = new Scroller();
  private readonly breadcrumbScroller: Scroller = new Scroller();
  private shelfUrls: Set<string> = new Set();

  aboutToAppear(): void {
    this.syncBars();
    if (this.initialized) return;
    this.initialized = true;
    this.bootstrap();
  }

  onPageShow(): void {
    this.syncBars();
    if (this.client) this.loadShelfUrls();
    if (this.pendingPreviewBook) {
      const book = this.pendingPreviewBook;
      this.pendingPreviewBook = null;
      this.confirmPreviewShelf(book);
    }
    if (!this.retryOnPageShow) return;
    this.retryOnPageShow = false;
    this.retry();
  }

  onBackPress(): boolean {
    if (this.searchMode) {
      this.exitSearch();
      return true;
    }
    if (this.stack.length > 1) {
      this.goBack();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.rootTitle(), scrollable: false,
        externalCollapse: this.searchMode ? 0 : this.headerCollapse,
        onBack: (): void => this.goBack(), content: () => {
        this.pageContent()
      } })

      if (this.downloadBusy) {
        Column({ space: AppSpacing.LG }) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.accentColor())
          Text(this.downloadText || '正在下载...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .maxLines(2)
            .textAlign(TextAlign.Center)
          Button('取消')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.cancelActiveDownload())
        }
        .width('78%')
        .padding(AppSpacing.XXL)
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(this.cardColor())
        .shadow({ radius: 18, color: this.appDarkMode ? '#66000000' : '#28000000' })
        .position({ x: '11%', y: '42%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    if (this.serverMissing || (this.errorMessage && !this.searchMode)) {
      this.errorView();
    } else if (this.searchMode) {
      Column() {
        this.searchField()
        this.searchScopeRow()
        this.searchList()
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      this.browseList();
    }
  }

  /** 浏览时列表顶部的搜索入口：沉浸光感胶囊，随列表滚走；点开进入搜索。悬浮栏材质只接受具体宽度，先量出行宽。 */
  @Builder
  searchEntry() {
    Row() {
      if (this.searchEntryWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.searchEntryWidth,
          surfaceHeight: OpdsBrowsePage.SEARCH_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: `#40${this.accentColor().substring(1)}`
        }) {
          Row({ space: AppSpacing.MD }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([this.subTextColor()])
            Text('搜索书名或作者')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width('100%')
    .height(OpdsBrowsePage.SEARCH_HEIGHT)
    .margin({ top: AppSpacing.XS, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.searchEntryWidth) this.searchEntryWidth = width;
    })
    .accessibilityGroup(true)
    .accessibilityText('搜索书名或作者')
    .onClick(() => {
      this.enterSearch();
    })
  }

  /** 搜索中固定在顶栏下的输入框，与“我的”页设置搜索里的输入框同款。 */
  @Builder
  searchField() {
    Row({ space: AppSpacing.MD }) {
      Row() {
        if (this.searchFieldWidth > 0) {
          ImmersiveMaterialSurface({
            surfaceWidth: this.searchFieldWidth,
            surfaceHeight: OpdsBrowsePage.SEARCH_HEIGHT,
            darkMode: this.appDarkMode,
            fallbackColor: this.cardColor(),
            glowColor: `#40${this.accentColor().substring(1)}`
          }) {
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([this.subTextColor()])
                .margin({ left: AppSpacing.LG })
              TextInput({ text: this.searchInput, placeholder: '搜索书名或作者', controller: this.searchController })
                .id(OpdsBrowsePage.SEARCH_INPUT_ID)
                .layoutWeight(1)
                .height(OpdsBrowsePage.SEARCH_HEIGHT)
                .enterKeyType(EnterKeyType.Search)
                .backgroundColor(Color.Transparent)
                .fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor())
                .caretColor(this.accentColor())
                .padding({ left: AppSpacing.SM, right: AppSpacing.XS })
                .onChange((value: string) => {
                  this.onSearchInputChange(value);
                })
                .onSubmit(() => {
                  this.submitSearch();
                })
              if (this.searchInput) {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(18)
                  .fontColor([this.subTextColor()])
                  .width(36)
                  .height(36)
                  .margin({ right: AppSpacing.XS })
                  .accessibilityText('清除搜索')
                  .onClick(() => {
                    this.onSearchInputChange('');
                    this.focusSearchInputSoon();
                  })
              }
            }
            .width('100%')
            .height('100%')
            .alignItems(VerticalAlign.Center)
          }
        }
      }
      .layoutWeight(1)
      .height(OpdsBrowsePage.SEARCH_HEIGHT)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = Math.floor(Number(newValue.width));
        if (Number.isFinite(width) && width > 0 && width !== this.searchFieldWidth) this.searchFieldWidth = width;
      })

      Text('取消')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.accentColor())
        .height(OpdsBrowsePage.SEARCH_HEIGHT)
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        .onClick(() => {
          this.exitSearch();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XS, bottom: AppSpacing.MD })
  }

  @Builder
  searchScopeRow() {
    Row({ space: AppSpacing.MD }) {
      if (this.searchAvailable) {
        this.chip('整个书库', this.searchScope === OpdsBrowsePage.SCOPE_SERVER,
          () => this.setSearchScope(OpdsBrowsePage.SCOPE_SERVER))
      }
      this.chip(`仅“${this.currentTitle()}”已加载`, this.searchScope === OpdsBrowsePage.SCOPE_LOCAL,
        () => this.setSearchScope(OpdsBrowsePage.SCOPE_LOCAL))
    }
    .width('100%')
    .height(36)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ bottom: AppSpacing.XS })
  }

  @Builder
  chip(label: string, selected: boolean, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(selected ? ThemeRuntime.onAccentColor(this.accentColor()) : this.accentColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 200 })
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .backgroundColor(selected ? this.accentColor() : ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      .accessibilitySelected(selected)
      .onClick(action)
  }

  /** 路径条：各级目录名，点任一级直接回到那一层；当前层加粗不可点。 */
  @Builder
  breadcrumbRow() {
    Scroll(this.breadcrumbScroller) {
      Row() {
        ForEach(this.stack, (frame: OpdsNavFrame, index: number) => {
          if (index > 0) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([this.subTextColor()])
          }
          Text(index === 0 ? '书库首页' : (frame.title || '目录'))
            .fontSize(AppFontSize.BODY)
            .fontColor(index === this.stack.length - 1 ? this.primaryTextColor() : this.accentColor())
            .fontWeight(index === this.stack.length - 1 ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 180 })
            .height(36)
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
            .onClick(() => {
              if (index < this.stack.length - 1) this.jumpToLevel(index);
            })
        }, (frame: OpdsNavFrame, index: number) => `${index}_${frame.url}`)
      }
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .align(Alignment.Start)
    .width('100%')
    .height(36)
    .margin({ bottom: AppSpacing.XS })
  }

  /** 书库给的筛选与排序（facet）：每组一行胶囊，随列表滚走。 */
  @Builder
  facetRows() {
    Column({ space: AppSpacing.SM }) {
      ForEach(this.facets, (group: OpdsFacetGroup) => {
        Scroll() {
          Row({ space: AppSpacing.MD }) {
            ForEach(group.links, (link: OpdsLink) => {
              this.chip(this.facetLabel(group, link), link.activeFacet, () => this.openFacet(link))
            }, (link: OpdsLink) => `${group.group}:${link.href}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.Start)
        .width('100%')
        .height(34)
      }, (group: OpdsFacetGroup) => group.group)
    }
    .width('100%')
    .margin({ bottom: AppSpacing.SM })
  }

  /** 列表加载中的细进度条；平时也占着 3vp，出现消失时下面的列表不跳。 */
  @Builder
  loadingBar() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.loading && this.entries.length > 0) {
        Row()
          .width('35%')
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.accentColor())
          .translate({ x: this.loadingSweep ? '290%' : '-100%' })
          .animation({ duration: 1100, curve: Curve.EaseInOut, iterations: -1 })
          .onAppear(() => {
            this.loadingSweep = true;
          })
          .onDisAppear(() => {
            this.loadingSweep = false;
          })
      }
    }
    .width('100%')
    .height(3)
    .clip(true)
  }

  /**
   * 浏览列表：从页面顶部铺下来，顶部留出标题行高度；上滑时标题行跟手收起，
   * 搜索入口、路径条和筛选在列表里随内容滚走。
   */
  @Builder
  browseList() {
    List({ scroller: this.listScroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.listTopInset())
          .hitTestBehavior(HitTestMode.None)
      }
      ListItem() {
        this.searchEntry()
      }
      ListItem() {
        this.breadcrumbRow()
      }
      if (this.facets.length > 0) {
        ListItem() {
          this.facetRows()
        }
      }
      ListItem() {
        this.loadingBar()
      }
      if (this.loading && this.entries.length === 0) {
        ListItem() {
          this.skeletonList()
        }
      } else if (this.entries.length === 0) {
        ListItem() {
          this.emptyView(this.emptyHint)
        }
      } else {
        ListItem() {
          this.groupHeader(this.entriesSummary())
        }
        LazyForEach(this.entrySource, (entry: OpdsEntry, index: number) => {
          ListItem() {
            this.feedItem(entry, index, this.entries.length, '')
          }
        }, (entry: OpdsEntry, index: number) => this.entryKey(entry, index))
        ListItem() {
          this.listFooter()
        }
      }
      ListItem() {
        Row()
          .height(this.navBarHeight + AppSpacing.XXXL)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    // 顶栏收起时外层留白同步减少，列表顶边保持贴住页面顶部。
    .margin({ top: -(this.listTopInset() - this.headerCollapse) })
    .onReachEnd(() => this.onListReachEnd())
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.listScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.listScroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  @Builder
  searchList() {
    if (this.searchScope === OpdsBrowsePage.SCOPE_SERVER && !this.searchSubmitted) {
      this.searchHint('输入书名或作者，按键盘上的搜索键在整个书库里查找')
    } else if (this.searchScope === OpdsBrowsePage.SCOPE_LOCAL && !this.searchInput.trim()) {
      this.searchHint(this.searchAvailable ? `输入书名或作者，筛选“${this.currentTitle()}”里已加载的条目` :
        `这个书库不支持在线搜索，可以筛选“${this.currentTitle()}”里已加载的条目`)
    } else {
      List({ scroller: this.searchScroller }) {
        if (this.searchScope === OpdsBrowsePage.SCOPE_SERVER && this.loading && this.entries.length === 0) {
          ListItem() {
            this.skeletonList()
          }
        } else if (this.searchCount === 0) {
          ListItem() {
            this.emptyView(this.searchScope === OpdsBrowsePage.SCOPE_LOCAL ?
              '已加载的条目里没有匹配项' : '没有找到相关书籍')
          }
        } else {
          ListItem() {
            this.groupHeader(this.searchScope === OpdsBrowsePage.SCOPE_LOCAL ?
              `已加载的条目里找到 ${this.searchCount} 项` : `书库返回 ${this.searchCount} 项`)
          }
          LazyForEach(this.searchSource, (entry: OpdsEntry, index: number) => {
            ListItem() {
              this.feedItem(entry, index, this.searchCount, this.searchInput)
            }
          }, (entry: OpdsEntry, index: number) => `search_${this.entryKey(entry, index)}`)
          if (this.searchScope === OpdsBrowsePage.SCOPE_SERVER) {
            ListItem() {
              this.listFooter()
            }
          }
        }
        ListItem() {
          Row()
            .height(this.navBarHeight + AppSpacing.XXXL)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .layoutWeight(1)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .onReachEnd(() => {
        if (this.searchScope === OpdsBrowsePage.SCOPE_SERVER) this.onListReachEnd();
      })
      .onScrollStart(() => {
        this.searchController.stopEditing();
      })
    }
  }

  @Builder
  searchHint(text: string) {
    Column({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(36)
        .fontColor([this.subTextColor()])
      Text(text)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 36, right: 36, bottom: 80 })
  }

  @Builder
  emptyView(text: string) {
    Column({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.book'))
        .fontSize(40)
        .fontColor([this.subTextColor()])
      Text(text)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 100, bottom: 40 })
  }

  @Builder
  groupHeader(label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XS, top: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  @Builder
  listFooter() {
    if (this.loadingMore) {
      Row({ space: AppSpacing.MD }) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor())
        Text('加载中...')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
    } else {
      Text(this.hasMore ? '上滑加载更多' : '没有更多了')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
    }
  }

  @Builder
  skeletonList() {
    Column() {
      ForEach([0, 1, 2], (index: number) => {
        Row({ space: AppSpacing.LG }) {
          Row()
            .width(48)
            .height(64)
            .borderRadius(4)
            .backgroundColor(this.softColor())
          Column({ space: AppSpacing.MD }) {
            Row()
              .width(index === 1 ? '46%' : '62%')
              .height(12)
              .borderRadius(6)
              .backgroundColor(this.softColor())
            Row()
              .width('34%')
              .height(10)
              .borderRadius(5)
              .backgroundColor(this.softColor())
              .opacity(0.7)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(84)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .border({ width: { bottom: index < 2 ? 0.5 : 0 }, color: ThemeRuntime.dividerColor(this.appDarkMode) })
      }, (index: number) => `${index}`)
    }
    .width('100%')
    .margin({ top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .clip(true)
    .accessibilityText('正在加载')
  }

  /** keyword 非空时（搜索结果）标题里高亮关键词。同一列表的行连成一张卡片。 */
  @Builder
  feedItem(entry: OpdsEntry, index: number, count: number, keyword: string) {
    Row({ space: AppSpacing.LG }) {
      if (entry.isPublication()) {
        this.entryCover(entry)
      } else {
        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(26)
            .fontColor([this.accentColor()])
        }
        .width(34)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: AppSpacing.XS }) {
        this.entryTitle(entry, keyword)
        if (this.entrySubtitle(entry)) {
          Text(this.entrySubtitle(entry))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (!entry.isPublication()) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.subTextColor()])
      } else if (this.isOnShelf(entry)) {
        Text('已在书架')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.accentColor())
          .height(22)
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
          .borderRadius(11)
          .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      }
    }
    .width('100%')
    .height(entry.isPublication() ? 84 : 62)
    .padding({ left: entry.isPublication() ? AppSpacing.LG : AppSpacing.XL, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(this.rowRadius(index, count))
    .border({ width: { bottom: index < count - 1 ? 0.5 : 0 }, color: ThemeRuntime.dividerColor(this.appDarkMode) })
    .onClick(() => {
      if (entry.isPublication()) {
        this.searchController.stopEditing();
        this.openDetail(entry);
      } else {
        this.openNavEntry(entry);
      }
    })
  }

  @Builder
  entryTitle(entry: OpdsEntry, keyword: string) {
    if (keyword.trim()) {
      Text() {
        Span(KeywordMatch.split(this.entryDisplayTitle(entry), keyword).before)
        Span(KeywordMatch.split(this.entryDisplayTitle(entry), keyword).hit)
          .fontColor(this.accentColor())
          .fontWeight(FontWeight.Medium)
        Span(KeywordMatch.split(this.entryDisplayTitle(entry), keyword).after)
      }
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(this.primaryTextColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
    } else {
      Text(this.entryDisplayTitle(entry))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
  }

  @Builder
  entryCover(entry: OpdsEntry) {
    BookCover({ bookUrl: entry.id, origin: 'opds', name: entry.title, author: entry.authors.join('、'),
      coverUrl: this.coverOf(entry.artworkThumbnail()), useBookshelfCover: this.useBookshelfCover,
      placeholderColor: this.accentColor() })
      .width(48)
      .height(64)
    .onAppear(() => this.ensureEntryCover(entry))
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([this.subTextColor()])
      Text(this.errorMessage || '服务器配置不存在')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      if (this.serverMissing) {
        Button('返回')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => router.back())
      } else {
        Button('重试')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.retry())
        if (this.errorCode === 'auth') {
          Button('网页登录')
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.openWebLogin())
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(36)
  }

  @Builder
  detailDialogContent() {
    Scroll() {
      Column({ space: AppSpacing.LG }) {
        Row({ space: AppSpacing.LG }) {
          this.detailCoverView()
          Column({ space: AppSpacing.SM }) {
            Text(this.detailEntry.title || '未命名')
              .fontSize(AppFontSize.SUBTITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
            if (this.detailEntry.displayAuthor()) {
              Text(this.detailEntry.displayAuthor())
                .fontSize(AppFontSize.BODY)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.publisher) {
              Text(`出版社：${this.detailEntry.publisher}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.series) {
              Text(`系列：${this.detailEntry.series}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailEntry.language) {
              Text(`语言：${this.detailEntry.language}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        if (this.detailText) {
          Column({ space: AppSpacing.SM }) {
            Text(this.detailText)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .maxLines(this.detailTextExpanded ? 100 : 8)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.detailTextLong) {
              Text(this.detailTextExpanded ? '收起' : '展开')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.accentColor())
                .width('100%')
                .onClick(() => {
                  this.detailTextExpanded = !this.detailTextExpanded;
                })
            }
          }
          .width('100%')
          .padding(AppSpacing.LG)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(DialogStyle.rowFill(this.appDarkMode))
        }

        this.detailPrimaryActions()

        if (this.downloadRows.length > 0) {
          Text('获取本书')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
          ForEach(this.downloadRows, (row: OpdsDownloadRow) => {
            this.downloadRowView(row)
          }, (row: OpdsDownloadRow) => row.key)
        } else {
          Text('该书库没有提供获取链接')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
        }
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .constraintSize({ maxHeight: 460 })
    .padding(AppSpacing.XXL)
  }

  @Builder
  detailCoverView() {
    BookCover({ bookUrl: this.detailEntry.id, origin: 'opds', name: this.detailEntry.title, author: this.detailEntry.authors.join('、'),
      coverUrl: this.coverOf(this.detailArtworkRaw()), useBookshelfCover: this.useBookshelfCover,
      placeholderColor: this.accentColor(), cornerRadius: 8 })
      .width(96)
      .height(128)
  }

  @Builder
  detailPrimaryActions() {
    Row({ space: AppSpacing.MD }) {
      if (this.detailImportedBook) {
        Button('立即阅读')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(DialogStyle.text('primary', this.appDarkMode))
          .backgroundColor(DialogStyle.fill('primary', this.appDarkMode))
          .onClick(() => this.readDetailBook())
        Button('移出书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .backgroundColor(DialogStyle.fill('cancel', this.appDarkMode))
          .onClick(() => this.removeDetailBook())
      } else if (this.detailBestRow && this.detailBestRow.downloadable) {
        Button('在线预览')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .backgroundColor(DialogStyle.fill('cancel', this.appDarkMode))
          .onClick(() => this.startBestPreview())
        Button('加入书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(DialogStyle.text('primary', this.appDarkMode))
          .backgroundColor(DialogStyle.fill('primary', this.appDarkMode))
          .onClick(() => this.addBestToShelf())
      } else if (this.downloadRows.length > 0) {
        Text('该获取方式暂不支持，请到书库网页端操作')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
  }

  addBestToShelf(): void {
    const row = this.detailBestRow;
    if (!row) return;
    this.startDownload(row);
  }

  startBestPreview(): void {
    const row = this.detailBestRow;
    if (!row || row.downloading || this.downloadBusy || this.activeDownload) return;
    row.downloading = true;
    row.received = 0;
    row.total = 0;
    this.refreshDownloadRows();
    this.downloadBusy = true;
    this.downloadProgress = 0;
    this.downloadText = `正在下载《${this.detailEntry.title}》...`;
    this.keepDownloadOnDetailClose = true;
    this.showDetail = false;
    let lastUpdate = 0;
    const onProgress = (received: number, total: number): void => {
      row.received = received;
      row.total = total;
      const now = Date.now();
      if (now - lastUpdate > 200 || (total > 0 && received >= total)) {
        lastUpdate = now;
        this.updateDownloadFeedback(received, total);
      }
    };
    OpdsBookService.downloadAndImport(getContext(this), this.server, this.password, row.link,
      this.detailEntry.title, onProgress, (handle: OpdsDownloadHandle): void => {
        this.activeDownload = handle;
      }).then((book: Book): void => {
        row.downloading = false;
        row.exists = true;
        this.loadShelfUrls();
        this.activeDownload = null;
        this.downloadBusy = false;
        this.pendingPreviewBook = book;
        this.refreshDownloadRows();
        router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
          .catch((error: Error) => {
            HdsFeedback.showToast(`打开阅读失败：${OpdsError.message(error)}`);
          });
      }).catch((error: Object): void => {
        row.downloading = false;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        if (error instanceof OpdsError && error.code === 'cancelled') return;
        HdsFeedback.showToast(`下载失败：${OpdsError.message(error)}`);
      });
  }

  readDetailBook(): void {
    const book = this.detailImportedBook;
    if (!book) return;
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`打开阅读失败：${OpdsError.message(error)}`);
      });
  }

  removeDetailBook(): void {
    const book = this.detailImportedBook;
    if (!book) return;
    const run = async (): Promise<void> => {
      try {
        await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
        this.detailImportedBook = null;
        const row = this.detailBestRow;
        if (row) row.exists = false;
        this.refreshDownloadRows();
        HdsFeedback.showToast('已移出书架');
        this.loadShelfUrls();
      } catch (error) {
        HdsFeedback.showToast(`移出失败：${OpdsError.message(error as Object)}`);
      }
    };
    run();
  }

  private confirmPreviewShelf(book: Book): void {
    ThemedDialog.showDialog(this.getUIContext(), {
      title: '是否加入书架',
      message: `《${book.name}》已下载到本地缓存`,
      buttons: [
        { text: '移出', color: this.primaryTextColor() },
        { text: '加入书架', color: this.accentColor() }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse): void => {
      if (data.index === 1) {
        HdsFeedback.showToast('已加入书架');
        return;
      }
      const run = async (): Promise<void> => {
        try {
          await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
          HdsFeedback.showToast('已移出书架');
          this.loadShelfUrls();
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${OpdsError.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  @Builder
  downloadRowView(row: OpdsDownloadRow) {
    Row({ space: AppSpacing.MD }) {
      Text(row.formatLabel)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .backgroundColor(DialogStyle.rowFill(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
      if (row.sizeText) {
        Text(row.sizeText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      Text(row.kindLabel)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  async bootstrap(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const serverId = params?.['serverId'] || '';
    const pageTitle = (params?.['title'] || '').trim();
    const context = getContext(this);
    let servers: OpdsServerConfig[] = [];
    try {
      servers = await OpdsSettingsStore.loadServers(context);
    } catch (error) {
      this.errorMessage = OpdsError.message(error, '读取服务器配置失败');
      return;
    }
    const found = servers.find((item: OpdsServerConfig): boolean => item.id === serverId);
    if (!found) {
      this.serverMissing = true;
      this.errorMessage = '服务器配置不存在';
      return;
    }
    this.server = found;
    try {
      this.password = await OpdsSecretStore.password(context, found.id);
    } catch (_) {
      this.password = '';
    }
    this.client = new OpdsClient(found, this.password);
    this.loadShelfUrls();
    const root = new OpdsNavFrame();
    root.url = found.baseUrl;
    root.title = pageTitle || found.name;
    this.stack = [root];
    this.loadBrowseFeed(found.baseUrl, true);
  }

  loadBrowseFeed(url: string, useCache: boolean): void {
    const client = this.client;
    if (!client || this.serverMissing) return;
    const seq = ++this.requestSeq;
    this.loading = true;
    this.errorCode = '';
    this.errorMessage = '';
    this.emptyHint = '这个书库还是空的';
    const run = async (): Promise<void> => {
      let catalogUrl = url;
      try {
        let feed: OpdsFeed | null = useCache ? this.cachedFeed(url) : null;
        if (!feed) {
          if (this.stack.length === 1 && url === this.server.baseUrl) {
            const catalog = await client.fetchCatalog(url);
            feed = catalog.feed;
            catalogUrl = catalog.url;
          } else {
            feed = await client.fetchFeed(url);
          }
          this.rememberFeed(url, feed);
        }
        if (seq !== this.requestSeq) return;
        if (catalogUrl !== url && this.stack.length === 1) {
          // 入口地址被自动纠正（尾斜杠、/opds）：后续相对链接、搜索都以实际地址为准，
          // 并存回配置，下次打开不用再试错
          this.rememberFeed(catalogUrl, feed);
          this.stack[0].url = catalogUrl;
          this.server.baseUrl = catalogUrl;
          OpdsSettingsStore.saveServer(getContext(this), this.server).catch((): void => {});
        }
        this.applyFeed(feed);
        if (this.stack.length === 1 && !this.searchTemplate) {
          this.resolveSearchTemplate(catalogUrl, feed, seq);
        }
      } catch (error) {
        if (seq !== this.requestSeq) return;
        this.entries = [];
        this.facets = [];
        this.hasMore = false;
        this.nextUrl = '';
        this.setError(error);
      } finally {
        if (seq === this.requestSeq) this.loading = false;
      }
    };
    run();
  }

  resolveSearchTemplate(feedUrl: string, feed: OpdsFeed, seq: number): void {
    const client = this.client;
    if (!client) return;
    const run = async (): Promise<void> => {
      const template = await client.resolveSearchTemplate(feedUrl, feed);
      if (seq !== this.requestSeq) return;
      if (template) {
        this.searchTemplate = template;
        this.searchAvailable = true;
      }
    };
    run();
  }

  applyFeed(feed: OpdsFeed): void {
    this.entries = feed.entries.slice();
    this.facets = feed.facetGroups();
    this.pageCount = 1;
    const next = feed.nextLink();
    this.nextUrl = next ? next.href : '';
    this.hasMore = !!next && this.pageCount < OpdsBrowsePage.MAX_PAGES;
  }

  cachedFeed(url: string): OpdsFeed | null {
    const hit = this.feedCache.get(url);
    if (!hit) return null;
    if (Date.now() - hit.fetchedAt > OpdsBrowsePage.FEED_TTL_MS) {
      this.feedCache.delete(url);
      return null;
    }
    return hit.feed;
  }

  rememberFeed(url: string, feed: OpdsFeed): void {
    const entry = new OpdsFeedCacheEntry();
    entry.feed = feed;
    entry.fetchedAt = Date.now();
    this.feedCache.set(url, entry);
  }

  openNavEntry(entry: OpdsEntry): void {
    const link = entry.navigationLink();
    if (!link) return;
    if (this.searchMode) this.leaveSearchMode();
    this.saveTopSnapshot();
    const frame = new OpdsNavFrame();
    frame.url = link.href;
    frame.title = entry.title || link.title || '目录';
    this.stack = [...this.stack, frame];
    this.showFrame(frame, false);
  }

  openFacet(link: OpdsLink): void {
    if (this.stack.length === 0) return;
    const top = this.stack[this.stack.length - 1];
    top.url = link.href;
    top.savedAt = 0;
    this.stack = this.stack.slice();
    // 筛选换的是同一层的内容：旧列表先留着，顶部细进度条表示在加载。
    this.loadBrowseFeed(link.href, true);
  }

  goBack(): void {
    if (this.searchMode) {
      this.exitSearch();
      return;
    }
    if (this.stack.length > 1) {
      this.jumpToLevel(this.stack.length - 2);
      return;
    }
    router.back();
  }

  /** 回到路径上的第 index 层（返回手势或点路径条）。 */
  jumpToLevel(index: number): void {
    if (index < 0 || index >= this.stack.length - 1) return;
    this.stack = this.stack.slice(0, index + 1);
    this.showFrame(this.stack[index], false);
  }

  /** 离开当前层前记下它的列表和滚动位置。 */
  private saveTopSnapshot(): void {
    if (this.stack.length === 0) return;
    const top = this.stack[this.stack.length - 1];
    top.entries = this.entries;
    top.facets = this.facets;
    top.nextUrl = this.nextUrl;
    top.pageCount = this.pageCount;
    top.hasMore = this.hasMore;
    top.scrollOffset = this.listScroller.currentOffset().yOffset;
    top.savedAt = this.entries.length > 0 && !this.loading ? Date.now() : 0;
  }

  /**
   * 显示某一层：记下的列表还新鲜（或 force）就直接恢复并滚回原处；
   * 否则清空列表显示占位行，联网读取（5 分钟内读过的页面仍走 feedCache）。
   */
  private showFrame(frame: OpdsNavFrame, force: boolean): void {
    this.headerCollapse = 0;
    const fresh = frame.savedAt > 0 && (force || Date.now() - frame.savedAt < OpdsBrowsePage.FEED_TTL_MS);
    if (fresh) {
      this.requestSeq++;
      this.loading = false;
      this.loadingMore = false;
      this.errorCode = '';
      this.errorMessage = '';
      this.entries = frame.entries;
      this.facets = frame.facets;
      this.nextUrl = frame.nextUrl;
      this.pageCount = frame.pageCount;
      this.hasMore = frame.hasMore;
      const offset = frame.scrollOffset;
      setTimeout(() => {
        try {
          this.listScroller.scrollTo({ xOffset: 0, yOffset: offset });
        } catch (_) {
        }
      }, 50);
    } else {
      this.entries = [];
      this.facets = [];
      this.nextUrl = '';
      this.hasMore = false;
      try {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      } catch (_) {
      }
      this.loadBrowseFeed(frame.url, true);
    }
    setTimeout(() => {
      this.breadcrumbScroller.scrollEdge(Edge.End);
    }, 50);
  }

  onListReachEnd(): void {
    if (this.loading || this.loadingMore || !this.hasMore) return;
    if (this.pageCount >= OpdsBrowsePage.MAX_PAGES) {
      this.hasMore = false;
      return;
    }
    this.loadNextPage();
  }

  loadNextPage(): void {
    const client = this.client;
    const url = this.nextUrl;
    if (!client || !url) return;
    const seq = this.requestSeq;
    this.loadingMore = true;
    const run = async (): Promise<void> => {
      try {
        const feed = await client.fetchFeed(url);
        if (seq !== this.requestSeq) return;
        this.rememberFeed(url, feed);
        this.pageCount++;
        this.entries = [...this.entries, ...feed.entries];
        const next = feed.nextLink();
        this.nextUrl = next ? next.href : '';
        this.hasMore = !!next && this.pageCount < OpdsBrowsePage.MAX_PAGES;
      } catch (error) {
        if (seq !== this.requestSeq) return;
        HdsFeedback.showToast(`加载失败：${OpdsError.message(error)}`);
      } finally {
        if (seq === this.requestSeq) this.loadingMore = false;
      }
    };
    run();
  }

  /** 进入搜索：先记下当前层，书库自带搜索时默认搜整个书库，否则只筛已加载的条目。 */
  enterSearch(): void {
    if (this.searchMode) return;
    this.saveTopSnapshot();
    this.searchMode = true;
    this.searchInput = '';
    this.searchSubmitted = false;
    this.searchScope = this.searchAvailable && this.searchTemplate ? OpdsBrowsePage.SCOPE_SERVER :
      OpdsBrowsePage.SCOPE_LOCAL;
    this.syncSearchSource();
    this.focusSearchInputSoon();
  }

  focusSearchInputSoon(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(OpdsBrowsePage.SEARCH_INPUT_ID);
      } catch (_) {
      }
    }, 120);
  }

  onSearchInputChange(value: string): void {
    this.searchInput = value;
    if (this.searchScope === OpdsBrowsePage.SCOPE_LOCAL) this.syncSearchSource();
  }

  setSearchScope(scope: string): void {
    if (this.searchScope === scope) return;
    this.searchScope = scope;
    if (scope === OpdsBrowsePage.SCOPE_SERVER && this.searchInput.trim()) {
      this.submitSearch();
      return;
    }
    this.syncSearchSource();
  }

  submitSearch(): void {
    const query = this.searchInput.trim();
    if (!query) {
      HdsFeedback.showToast('请输入搜索关键词');
      return;
    }
    this.searchController.stopEditing();
    const template = this.searchTemplate;
    if (this.searchScope !== OpdsBrowsePage.SCOPE_SERVER || !template) return;
    this.runSearch(query, template);
  }

  /** 书库搜索结果放进 entries，沿用翻页逻辑；当前层在进入搜索时已记下，退出时恢复。 */
  runSearch(query: string, template: OpdsSearchTemplate): void {
    const client = this.client;
    if (!client) return;
    const seq = ++this.requestSeq;
    this.lastSearchQuery = query;
    this.searchSubmitted = true;
    this.entries = [];
    this.nextUrl = '';
    this.hasMore = false;
    this.loading = true;
    this.errorCode = '';
    this.errorMessage = '';
    const run = async (): Promise<void> => {
      try {
        const feed = await client.search(template, query);
        if (seq !== this.requestSeq) return;
        this.applyFeed(feed);
      } catch (error) {
        if (seq !== this.requestSeq) return;
        HdsFeedback.showToast(OpdsError.message(error));
      } finally {
        if (seq === this.requestSeq) this.loading = false;
      }
    };
    run();
  }

  exitSearch(): void {
    this.leaveSearchMode();
    if (this.stack.length > 0) this.showFrame(this.stack[this.stack.length - 1], true);
  }

  private leaveSearchMode(): void {
    this.requestSeq++;
    this.searchMode = false;
    this.searchSubmitted = false;
    this.searchInput = '';
    this.searchController.stopEditing();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_) {
    }
  }

  /** 搜索列表的数据：整个书库=书库返回的结果；当前列表=按书名、作者筛进入搜索时那一层已加载的条目。 */
  syncSearchSource(): void {
    let list: OpdsEntry[] = [];
    if (this.searchMode) {
      if (this.searchScope === OpdsBrowsePage.SCOPE_SERVER) {
        list = this.searchSubmitted ? this.entries : [];
      } else {
        const keyword = this.searchInput.trim().toLowerCase();
        const top = this.stack.length > 0 ? this.stack[this.stack.length - 1] : null;
        const source = top && top.savedAt > 0 ? top.entries : this.entries;
        list = keyword ? source.filter((entry: OpdsEntry): boolean =>
          (entry.title || '').toLowerCase().includes(keyword) ||
          entry.displayAuthor().toLowerCase().includes(keyword)) : [];
      }
    }
    this.searchSource.replace(list);
    this.searchCount = list.length;
  }

  retry(): void {
    if (this.serverMissing) return;
    if (!this.client) {
      this.bootstrap();
      return;
    }
    if (this.searchMode && this.lastSearchQuery && this.searchTemplate) {
      this.runSearch(this.lastSearchQuery, this.searchTemplate);
      return;
    }
    if (this.stack.length > 0) {
      this.loadBrowseFeed(this.stack[this.stack.length - 1].url, false);
    }
  }

  openWebLogin(): void {
    const url = this.stack.length > 0 ? this.stack[this.stack.length - 1].url : this.server.baseUrl;
    this.retryOnPageShow = true;
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.server.name,
        requireLoginCookie: 'false'
      }
    });
  }

  async openDetail(entry: OpdsEntry): Promise<void> {
    this.detailEntry = entry;
    this.detailText = this.computeDetailText(entry);
    this.detailTextLong = this.detailText.length > 160;
    this.detailTextExpanded = false;
    this.downloadRows = this.buildDownloadRows(entry);
    const best = this.downloadRows.find((item: OpdsDownloadRow): boolean => item.downloadable) || null;
    this.detailBestRow = best;
    this.detailImportedBook = null;
    if (best) {
      try {
        const identity = OpdsBookService.bookIdentityUrl(this.server.id, best.link.href);
        this.detailImportedBook = await appDb.getBook(identity);
      } catch (_) {
        this.detailImportedBook = null;
      }
    }
    this.showDetail = true;
    this.detailDialogSession.open(this.getUIContext(), (): void => {
      this.detailDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示书籍详情弹窗失败:',
      onDismiss: (): void => {
        this.showDetail = false;
      }
    });
    this.ensureCover(this.detailArtworkRaw());
    this.prefetchImportedStates();
  }

  onDetailFlagChanged(): void {
    if (this.showDetail) return;
    this.detailDialogSession.close(this.getUIContext());
    if (this.keepDownloadOnDetailClose) {
      this.keepDownloadOnDetailClose = false;
      return;
    }
    if (this.activeDownload) {
      this.activeDownload.cancel();
      this.activeDownload = null;
    }
  }

  buildDownloadRows(entry: OpdsEntry): OpdsDownloadRow[] {
    const rows: OpdsDownloadRow[] = [];
    const links = entry.acquisitionLinks();
    for (let i = 0; i < links.length; i++) {
      const link = links[i];
      const row = new OpdsDownloadRow();
      row.key = `${entry.id}|${link.href}`;
      row.link = link;
      const format = OpdsBookService.formatOfLink(link);
      row.formatLabel = (format || '文件').toUpperCase();
      row.sizeText = link.length > 0 ? this.formatSize(link.length) : '';
      row.kind = link.acquisitionKind();
      row.kindLabel = this.acquisitionKindLabel(link);
      row.downloadable = OpdsBookService.isDownloadableFormat(format) &&
        (row.kind === 'open-access' || row.kind === 'generic' || row.kind === '');
      rows.push(row);
    }
    return rows;
  }

  prefetchImportedStates(): void {
    const run = async (): Promise<void> => {
      const rows = this.downloadRows;
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row.downloadable) continue;
        try {
          const exists = await OpdsBookService.isAlreadyImported(this.server.id, row.link.href);
          if (exists) row.exists = true;
        } catch (_) {}
      }
      if (this.showDetail) this.downloadRows = this.downloadRows.slice();
    };
    run();
  }

  startDownload(row: OpdsDownloadRow): void {
    if (row.downloading) return;
    if (this.activeDownload || this.downloadBusy) {
      HdsFeedback.showToast('已有下载在进行中，请先完成或取消');
      return;
    }
    row.downloading = true;
    row.received = 0;
    row.total = 0;
    this.refreshDownloadRows();
    this.downloadBusy = true;
    this.downloadProgress = 0;
    this.downloadText = `正在下载《${this.detailEntry.title}》...`;
    // 系统弹窗盖在页面层之上，进度浮层会被遮挡；开始下载时收起详情弹窗
    this.keepDownloadOnDetailClose = true;
    this.showDetail = false;
    let lastUpdate = 0;
    const onProgress = (received: number, total: number): void => {
      row.received = received;
      row.total = total;
      const now = Date.now();
      if (now - lastUpdate > 200 || (total > 0 && received >= total)) {
        lastUpdate = now;
        this.refreshDownloadRows();
        this.updateDownloadFeedback(received, total);
      }
    };
    OpdsBookService.downloadAndImport(getContext(this), this.server, this.password, row.link,
      this.detailEntry.title, onProgress, (handle: OpdsDownloadHandle): void => {
        this.activeDownload = handle;
      }).then((_book: Book): void => {
        row.downloading = false;
        row.exists = true;
        this.loadShelfUrls();
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        HdsFeedback.showToast('已加入书架');
      }).catch((error: Object): void => {
        row.downloading = false;
        this.activeDownload = null;
        this.downloadBusy = false;
        this.refreshDownloadRows();
        if (error instanceof OpdsError && error.code === 'cancelled') return;
        HdsFeedback.showToast(`下载失败：${OpdsError.message(error)}`);
      });
  }

  private updateDownloadFeedback(received: number, total: number): void {
    if (total > 0) {
      this.downloadProgress = Math.min(100, Math.floor(received / total * 100));
      this.downloadText = `正在下载《${this.detailEntry.title}》... ${this.downloadProgress}%`;
    } else {
      this.downloadText = `正在下载《${this.detailEntry.title}》... ${(received / 1024 / 1024).toFixed(1)} MB`;
    }
  }

  cancelActiveDownload(): void {
    const handle = this.activeDownload;
    if (handle) handle.cancel();
  }

  refreshDownloadRows(): void {
    this.downloadRows = this.downloadRows.slice();
  }

  computeDetailText(entry: OpdsEntry): string {
    const raw = entry.displayText();
    if (!raw) return '';
    if (entry.contentIsHtml || entry.summaryIsHtml) return OpdsBrowsePage.stripHtml(raw);
    return raw.trim();
  }

  ensureEntryCover(entry: OpdsEntry): void {
    const raw = entry.artworkThumbnail();
    if (!raw) return;
    this.ensureCover(raw);
  }

  ensureCover(raw: string): void {
    if (!raw) return;
    if (this.coverMap.has(raw) || this.pendingCovers.has(raw)) return;
    this.pendingCovers.add(raw);
    const run = async (): Promise<void> => {
      try {
        const context = getContext(this);
        const local = await BookCoverCache.resolveCachedCoverAsync(context, raw) ||
          await this.fetchProtectedCover(raw) ||
          await BookCoverCache.resolveCover(context, raw);
        if (!local) return;
        const next = new Map(this.coverMap);
        next.set(raw, local);
        this.coverMap = next;
      } catch (_) {
      } finally {
        this.pendingCovers.delete(raw);
      }
    };
    run();
  }

  // 开启登录的书库（如 Calibre）封面也要带凭据，通用封面缓存不带认证头取不到
  async fetchProtectedCover(raw: string): Promise<string> {
    const client = this.client;
    if (!client || !client.usesCredentialsFor(raw)) return '';
    try {
      const data = await client.fetchBinary(raw, OpdsBrowsePage.MAX_COVER_BYTES);
      return await BookCoverCache.storeCover(getContext(this), raw, data);
    } catch (_) {
      return '';
    }
  }

  coverOf(raw: string): string {
    const hit = this.coverMap.get(raw);
    return hit || '';
  }

  detailArtworkRaw(): string {
    const image = this.detailEntry.artworkImage();
    return image ? image : this.detailEntry.artworkThumbnail();
  }

  currentTitle(): string {
    if (this.stack.length === 0) return '';
    return this.stack[this.stack.length - 1].title;
  }

  entryKey(entry: OpdsEntry, index: number): string {
    return entry.id || `${index}_${entry.title}`;
  }

  navSubtitle(entry: OpdsEntry): string {
    const raw = entry.displayText();
    if (!raw) return '';
    const text = entry.contentIsHtml || entry.summaryIsHtml ? OpdsBrowsePage.stripHtml(raw) : raw;
    return text.trim();
  }

  bookFormatLabel(entry: OpdsEntry): string {
    const links = entry.acquisitionLinks();
    if (links.length === 0) return '';
    const format = OpdsBookService.formatOfLink(links[0]);
    const label = (format || '文件').toUpperCase();
    const sizeText = links[0].length > 0 ? ` · ${this.formatSize(links[0].length)}` : '';
    return `${label}${sizeText}`;
  }

  facetLabel(group: OpdsFacetGroup, link: OpdsLink): string {
    const base = link.title || group.group || '筛选';
    return link.facetCount > 0 ? `${base}（${link.facetCount}）` : base;
  }

  acquisitionKindLabel(link: OpdsLink): string {
    const kind = link.acquisitionKind();
    if (kind === 'buy') {
      if (!link.price) return '购买';
      const currency = link.priceCurrency ? ` ${link.priceCurrency}` : '';
      return `购买 · ${link.price}${currency}`;
    }
    if (kind === 'borrow') return '借阅';
    if (kind === 'sample') return '试读';
    if (kind === 'subscribe') return '订阅';
    if (kind === 'open-access' || kind === '') return '免费获取';
    return '获取';
  }

  formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    if (size < 1024 * 1024 * 1024) return `${(size / 1024 / 1024).toFixed(1)} MB`;
    return `${(size / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  setError(error: Object): void {
    if (error instanceof OpdsError) {
      this.errorCode = error.code;
      this.errorMessage = error.userMessage;
    } else {
      this.errorCode = 'unknown';
      this.errorMessage = OpdsError.message(error);
    }
  }

  onEntriesChanged(): void {
    this.entrySource.replace(this.entries);
    if (this.searchMode && this.searchScope === OpdsBrowsePage.SCOPE_SERVER) this.syncSearchSource();
  }

  rootTitle(): string {
    return this.stack.length > 0 ? this.stack[0].title : this.server.name;
  }

  listTopInset(): number {
    return PageScaffold.BAR_HEIGHT + this.statusBarHeight;
  }

  entriesSummary(): string {
    const count = this.entries.length;
    const books = this.entries.filter((entry: OpdsEntry): boolean => entry.isPublication()).length;
    const loaded = this.hasMore ? '已加载 ' : '';
    if (books === 0) return `目录 · ${loaded}${count}`;
    if (books === count) return `书籍 · ${loaded}${count} 本`;
    return `共 ${loaded}${count} 项`;
  }

  entryDisplayTitle(entry: OpdsEntry): string {
    return entry.title || (entry.isPublication() ? '未命名' : '未命名目录');
  }

  /** 目录：书库给的说明；书：作者 · 格式 · 大小，只能购买/借阅的写明到网页端操作。 */
  entrySubtitle(entry: OpdsEntry): string {
    if (!entry.isPublication()) return this.navSubtitle(entry);
    const parts: string[] = [];
    const author = entry.displayAuthor() || entry.publisher;
    if (author) parts.push(author);
    const links = entry.acquisitionLinks();
    const downloadable = links.filter((link: OpdsLink): boolean => {
      const kind = link.acquisitionKind();
      return OpdsBookService.isDownloadableFormat(OpdsBookService.formatOfLink(link)) &&
        (kind === 'open-access' || kind === 'generic' || kind === '');
    });
    if (downloadable.length > 0) {
      const formats: string[] = [];
      downloadable.forEach((link: OpdsLink) => {
        const format = (OpdsBookService.formatOfLink(link) || '').toUpperCase();
        if (format && formats.indexOf(format) < 0) formats.push(format);
      });
      if (formats.length > 0) parts.push(formats.join(' / '));
      if (downloadable[0].length > 0) parts.push(this.formatSize(downloadable[0].length));
    } else if (links.length > 0) {
      parts.push(`${this.acquisitionKindLabel(links[0])}，在书库网页端操作`);
    }
    return parts.length > 0 ? parts.join(' · ') : '作者未知';
  }

  rowRadius(index: number, count: number): BorderRadiuses {
    const radius = ThemeRuntime.cardRadius();
    const top = index === 0 ? radius : 0;
    const bottom = index === count - 1 ? radius : 0;
    return { topLeft: top, topRight: top, bottomLeft: bottom, bottomRight: bottom };
  }

  loadShelfUrls(): void {
    const serverId = this.server.id;
    if (!serverId) return;
    const run = async (): Promise<void> => {
      try {
        const urls = await appDb.getBookUrlsWithPrefix(LocalBookService.opdsBookUrlPrefix(serverId));
        this.shelfUrls = new Set(urls);
        this.shelfRevision++;
      } catch (_) {
      }
    };
    run();
  }

  /** 任一获取链接对应的书已在书架即算。 */
  isOnShelf(entry: OpdsEntry): boolean {
    if (this.shelfRevision < 0 || this.shelfUrls.size === 0) return false;
    return entry.acquisitionLinks().some((link: OpdsLink): boolean =>
      this.shelfUrls.has(OpdsBookService.bookIdentityUrl(this.server.id, link.href)));
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  static stripHtml(input: string): string {
    let text = (input || '').replace(/<[^>]+>/g, ' ');
    text = text.split('&amp;').join('&')
      .split('&lt;').join('<')
      .split('&gt;').join('>')
      .split('&quot;').join('"')
      .split('&apos;').join("'");
    return text.replace(/[ \t\r\n]+/g, ' ').trim();
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }
}
