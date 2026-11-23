import { router, promptAction } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { WebDavBookService } from '../webdav/WebDavBookService';
import { WebDavClient } from '../webdav/WebDavClient';
import { WebDavError } from '../webdav/WebDavError';
import { WebDavBrowsePrefs, WebDavConnection, WebDavEntry } from '../webdav/WebDavModels';
import { WebDavSecretStore } from '../webdav/WebDavSecretStore';
import { WebDavSettingsStore } from '../webdav/WebDavSettingsStore';
import { WebDavBrowseSupport, WebDavFolderSearch } from '../webdav/WebDavBrowseSupport';
import { KeywordMatch } from '../utils/KeywordMatch';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction, PopupMenuHeader } from '../components/common/PopupMenuAction';

/** listedPath 的初值：还没有列出过任何目录。 */
const NO_LISTING: string = '\u0000';

@Entry
@Component
struct WebDavBrowsePage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State connection: WebDavConnection = new WebDavConnection();
  @State pageTitle: string = '';
  @State connectionMissing: boolean = false;
  @State currentPath: string = '';
  @State entries: WebDavEntry[] = [];
  /** 正在消散的条目路径，见 ListDissolve。 */
  @State dissolvingPaths: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  @State busy: boolean = false;
  @State busyText: string = '';
  @State busyProgress: number = 0;
  @State errorMessage: string = '';
  @State showEntryActionMenu: boolean = false;
  @State actionEntryPath: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('onSystemDialogFlagChanged') showEntryNameDialog: boolean = false;
  @State entryNameMode: string = '';
  @State entryNameDraft: string = '';
  @State @Watch('onFileDetailFlagChanged') showFileDetail: boolean = false;
  @State fileDetailEntry: WebDavEntry = new WebDavEntry();
  @State fileDetailBook: Book | null = null;
  /** 连接配置和密码已读好，可以显示顶栏的上传与“⋯”。 */
  @State connected: boolean = false;
  @State headerCollapse: number = 0;
  @State searchEntryWidth: number = 0;
  @State searchFieldWidth: number = 0;
  /** entries 当前对应的目录；与 currentPath 不同说明新目录还没列出来，显示占位行。 */
  @State listedPath: string = NO_LISTING;
  @State folderEntries: WebDavEntry[] = [];
  @State bookEntries: WebDavEntry[] = [];
  @State otherEntries: WebDavEntry[] = [];
  /** 列目录中：顶部细进度条，不挡页面。上传、下载等慢操作仍用 busy 的居中进度框。 */
  @State loading: boolean = false;
  @State loadingSweep: boolean = false;
  @State sortMode: string = WebDavBrowsePrefs.SORT_NAME;
  @State showOthers: boolean = false;
  /** 本文件夹里临时展开了折叠的其他文件，换文件夹即复位。 */
  @State othersExpanded: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showSortMenu: boolean = false;
  @State shelfRevision: number = 0;
  @State searchActive: boolean = false;
  @State keyword: string = '';
  @State searchDeep: boolean = false;
  @State booksOnly: boolean = false;
  @State deepResults: WebDavEntry[] = [];
  @State deepSearching: boolean = false;
  @State deepFinished: boolean = false;
  @State deepStopped: boolean = false;
  @State deepScanned: number = 0;
  @State deepFailed: number = 0;
  @State deepTruncated: boolean = false;
  private pendingPreviewBook: Book | null = null;
  private readonly fileDetailDialogSession: SystemDialogSession = new SystemDialogSession();
  private entryNameDialogSession: SystemDialogSession = new SystemDialogSession();
  private password: string = '';
  private client: WebDavClient | null = null;
  private initialized: boolean = false;
  /** 本次浏览列过的目录：返回上一级先用它秒开再后台刷新，搜子文件夹时也复用。 */
  private listCache: Map<string, WebDavEntry[]> = new Map();
  /** 每次列目录加一，晚回来的旧请求据此丢弃。 */
  private listToken: number = 0;
  private shelfUrls: Set<string> = new Set();
  private folderSearch: WebDavFolderSearch | null = null;
  private searchTimer: number = -1;
  /** 当前列表每换一次加一，搜索结果缓存据此失效。 */
  private listingRevision: number = 0;
  private searchCacheKey: string = '';
  private searchCache: WebDavEntry[] = [];
  private readonly breadcrumbScroller: Scroller = new Scroller();
  private readonly listScroller: Scroller = new Scroller();
  private static readonly SEARCH_HEIGHT: number = 40;
  private static readonly SEARCH_INPUT_ID: string = 'webdav_browse_search_input';
  private readonly searchInputController: TextInputController = new TextInputController();

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
  }

  aboutToDisappear(): void {
    this.cancelDeepSearch();
  }

  onBackPress(): boolean {
    if (this.showEntryActionMenu) {
      this.closeEntryActions();
      return true;
    }
    if (this.searchActive) {
      this.exitSearch();
      return true;
    }
    if (this.currentPath) {
      if (!this.busy) this.goParent();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.currentTitle(), scrollable: false,
        externalCollapse: this.searchActive ? 0 : this.headerCollapse, actions: () => {
        this.pageActions()
      }, content: () => {
        this.pageContent()
      } })

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showEntryActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.entryActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showEntryActionMenu = false;
        }))

      if (this.busy) {
        Column({ space: AppSpacing.LG }) {
          Progress({ value: this.busyProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.accentColor())
          Text(this.busyText || '处理中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
        }
        .width('78%')
        .padding(AppSpacing.XXL)
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(this.cardColor())
        .shadow({ radius: 18, color: this.appDarkMode ? '#66000000' : '#28000000' })
        .position({ x: '11%', y: '42%' })
      }

      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('webdav_browse_root')
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageActions() {
    if (!this.connectionMissing && this.connected) {
      Row({ space: AppSpacing.MD }) {
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.arrow_up_icloud'),
          accessibilityLabel: '上传',
          onTap: (): void => {
            this.chooseAndUploadFiles();
          }
        })
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.more'),
          accessibilityLabel: '更多',
          onTap: (): void => {
            this.showMoreMenu = !this.showMoreMenu;
          }
        })
          .bindPopup(this.showMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => {
              this.moreMenu();
            }, Placement.BottomRight, this.appDarkMode, this.accentColor(), (): void => {
              this.showMoreMenu = false;
            }))
      }
      .margin({ right: AppSpacing.XL })
    }
  }

  @Builder
  moreMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.folder_badge_plus'), '新建文件夹', this.primaryTextColor(), () => {
        this.showMoreMenu = false;
        this.openCreateFolderDialog();
      }, !this.busy)
      PopupMenuAction($r('sys.symbol.arrow_clockwise'), '刷新', this.primaryTextColor(), () => {
        this.showMoreMenu = false;
        this.refreshFiles();
      })
      this.menuDivider()
      PopupMenuHeader('排序', this.subTextColor())
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_NAME, '名称')
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_MODIFIED, '修改时间（新的在前）')
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_SIZE, '大小（大的在前）')
      this.menuDivider()
      this.menuCheckRow('显示其他文件', this.showOthers, () => {
        this.showMoreMenu = false;
        this.setShowOthers(!this.showOthers);
      })
    }
    .width(220)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  sortMenu() {
    Column() {
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_NAME, '名称')
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_MODIFIED, '修改时间（新的在前）')
      this.sortChoiceRow(WebDavBrowsePrefs.SORT_SIZE, '大小（大的在前）')
    }
    .width(220)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  menuDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeRuntime.dividerColor(this.appDarkMode))
      .margin({ left: 12, right: 12, top: AppSpacing.XS, bottom: AppSpacing.XS })
  }

  @Builder
  sortChoiceRow(mode: string, label: string) {
    this.menuCheckRow(label, this.sortMode === mode, () => {
      this.showMoreMenu = false;
      this.showSortMenu = false;
      this.setSortMode(mode);
    })
  }

  @Builder
  menuCheckRow(label: string, checked: boolean, action: () => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(checked ? this.accentColor() : this.primaryTextColor())
        .maxLines(1)
        .layoutWeight(1)
      if (checked) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
    .stateStyles({
      normal: {
        .backgroundColor(Color.Transparent)
      },
      pressed: {
        .backgroundColor('#1A808080')
      }
    })
    .accessibilitySelected(checked)
    .onClick(action)
  }

  @Builder
  pageContent() {
    if (this.connectionMissing || (this.errorMessage && this.listedPath !== this.currentPath)) {
      this.errorView();
    } else {
      this.filesPanel();
    }
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([this.subTextColor()])
      Text(this.errorMessage || '连接配置不存在')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
      if (this.connectionMissing) {
        Button('返回')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => router.back())
      } else {
        Button('重试')
          .fontColor(Color.White)
          .backgroundColor(this.accentColor())
          .onClick(() => this.retry())
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(36)
  }

  @Builder
  filesPanel() {
    if (this.searchActive) {
      Column() {
        this.searchField()
        this.searchScopeRow()
        this.searchResultsList()
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      this.browseList()
    }
  }

  /** 浏览时列表顶部的搜索入口：与“我的”页同款沉浸光感胶囊，随列表滚走；点开进入搜索。悬浮栏材质只接受具体宽度，先量出行宽。 */
  @Builder
  searchEntry() {
    Row() {
      if (this.searchEntryWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.searchEntryWidth,
          surfaceHeight: WebDavBrowsePage.SEARCH_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: `#40${this.accentColor().substring(1)}`
        }) {
          Row({ space: AppSpacing.MD }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([this.subTextColor()])
            Text('搜索文件名')
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
    .height(WebDavBrowsePage.SEARCH_HEIGHT)
    .margin({ top: AppSpacing.XS, bottom: AppSpacing.MD })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.searchEntryWidth) this.searchEntryWidth = width;
    })
    .accessibilityGroup(true)
    .accessibilityText('搜索文件名')
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
            surfaceHeight: WebDavBrowsePage.SEARCH_HEIGHT,
            darkMode: this.appDarkMode,
            fallbackColor: this.cardColor(),
            glowColor: `#40${this.accentColor().substring(1)}`
          }) {
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([this.subTextColor()])
                .margin({ left: AppSpacing.LG })
              TextInput({ text: this.keyword, placeholder: '搜索文件名', controller: this.searchInputController })
                .id(WebDavBrowsePage.SEARCH_INPUT_ID)
                .layoutWeight(1)
                .height(WebDavBrowsePage.SEARCH_HEIGHT)
                .enterKeyType(EnterKeyType.Search)
                .backgroundColor(Color.Transparent)
                .fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor())
                .caretColor(this.accentColor())
                .padding({ left: AppSpacing.SM, right: AppSpacing.XS })
                .onChange((value: string) => {
                  this.onKeywordChange(value);
                })
                .onSubmit(() => {
                  this.scheduleDeepSearch(0);
                })
              if (this.keyword) {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(18)
                  .fontColor([this.subTextColor()])
                  .width(36)
                  .height(36)
                  .margin({ right: AppSpacing.XS })
                  .accessibilityText('清除搜索')
                  .onClick(() => {
                    this.onKeywordChange('');
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
      .height(WebDavBrowsePage.SEARCH_HEIGHT)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = Math.floor(Number(newValue.width));
        if (Number.isFinite(width) && width > 0 && width !== this.searchFieldWidth) this.searchFieldWidth = width;
      })

      Text('取消')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.accentColor())
        .height(WebDavBrowsePage.SEARCH_HEIGHT)
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        .onClick(() => {
          this.exitSearch();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XS, bottom: AppSpacing.MD })
  }

  @Builder
  breadcrumbRow() {
    Row({ space: AppSpacing.XS }) {
      Scroll(this.breadcrumbScroller) {
        Row() {
          // 标题已是连接名，路径条起点写“根目录”，免得同屏两个连接名。
          this.breadcrumbSegment('根目录', '')
          ForEach(WebDavBrowseSupport.breadcrumbPaths(this.currentPath), (path: string) => {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([this.subTextColor()])
            this.breadcrumbSegment(WebDavBrowseSupport.lastSegment(path), path)
          }, (path: string) => path)
        }
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Start)
      .layoutWeight(1)

      Row({ space: AppSpacing.XS }) {
        SymbolGlyph($r('sys.symbol.sort'))
          .fontSize(15)
          .fontColor([this.subTextColor()])
        Text(WebDavBrowseSupport.sortLabel(this.sortMode))
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      .height(36)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .accessibilityText(`排序：${WebDavBrowseSupport.sortLabel(this.sortMode)}`)
      .onClick(() => {
        this.showSortMenu = !this.showSortMenu;
      })
      .bindPopup(this.showSortMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
        this.sortMenu();
      }, Placement.BottomRight, this.appDarkMode, this.accentColor(), (): void => {
        this.showSortMenu = false;
      }))
    }
    .width('100%')
    .height(36)
    .margin({ bottom: AppSpacing.XS })
  }

  @Builder
  breadcrumbSegment(label: string, path: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(path === this.currentPath ? this.primaryTextColor() : this.accentColor())
      .fontWeight(path === this.currentPath ? FontWeight.Medium : FontWeight.Normal)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 180 })
      .height(36)
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
      .onClick(() => {
        if (path !== this.currentPath) this.navigateTo(path);
      })
  }

  @Builder
  searchScopeRow() {
    Row({ space: AppSpacing.MD }) {
      this.scopeChip(`仅“${this.currentFolderLabel()}”`, !this.searchDeep, () => this.setSearchDeep(false))
      this.scopeChip('含子文件夹', this.searchDeep, () => this.setSearchDeep(true))
      this.scopeChip('只看书籍', this.booksOnly, () => this.toggleBooksOnly())
    }
    .width('100%')
    .height(36)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ bottom: AppSpacing.XS })
  }

  @Builder
  scopeChip(label: string, selected: boolean, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(selected ? ThemeRuntime.onAccentColor(this.accentColor()) : this.accentColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 150 })
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .backgroundColor(selected ? this.accentColor() : ThemeRuntime.accentSurfaceColor(this.appDarkMode))
      .accessibilitySelected(selected)
      .onClick(action)
  }

  /** 列目录时的细进度条；平时也占着 3vp，出现消失时下面的列表不跳。 */
  @Builder
  loadingBar() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.loading) {
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
   * 浏览列表：与 WebDAV 连接页一样从页面顶部铺下来，顶部留出标题行高度；上滑时标题行跟手收起，
   * 搜索入口和路径条在列表里随内容滚走。
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
      ListItem() {
        this.loadingBar()
      }
      if (this.listedPath !== this.currentPath) {
        ListItem() {
          this.skeletonList()
        }
      } else if (this.entries.length === 0) {
        ListItem() {
          Column({ space: AppSpacing.MD }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(40)
              .fontColor([this.subTextColor()])
            Text('这个目录还是空的')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 120, bottom: 40 })
        }
      } else {
        if (this.folderEntries.length > 0) {
          ListItem() {
            this.groupHeader(`文件夹 · ${this.folderEntries.length}`)
          }
          ForEach(this.folderEntries, (entry: WebDavEntry, index: number) => {
            ListItem() {
              this.entryRow(entry, index, this.folderEntries.length, false)
            }
          }, (entry: WebDavEntry) => this.entryKey(entry))
        }
        if (this.bookEntries.length > 0) {
          ListItem() {
            this.groupHeader(`书籍 · ${this.bookEntries.length}`)
          }
          ForEach(this.bookEntries, (entry: WebDavEntry, index: number) => {
            ListItem() {
              this.entryRow(entry, index, this.bookEntries.length, false)
            }
          }, (entry: WebDavEntry) => this.entryKey(entry))
        }
        if (this.otherEntries.length > 0) {
          if (this.showOthers || this.othersExpanded) {
            ListItem() {
              this.groupHeader(`其他文件 · ${this.otherEntries.length}`)
            }
            ForEach(this.otherEntries, (entry: WebDavEntry, index: number) => {
              ListItem() {
                this.entryRow(entry, index, this.otherEntries.length, false)
              }
            }, (entry: WebDavEntry) => this.entryKey(entry))
          } else {
            ListItem() {
              this.collapsedOthersRow()
            }
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
    // 顶栏收起时外层留白同步减少，列表顶边保持贴住页面顶部。
    .margin({ top: -(this.listTopInset() - this.headerCollapse) })
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
  groupHeader(label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XS, top: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  @Builder
  collapsedOthersRow() {
    Row({ space: AppSpacing.MD }) {
      Text(this.collapsedOthersLabel())
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(15)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(48)
    .margin({ top: AppSpacing.LG })
    .padding({ left: AppSpacing.XL, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.softColor())
    .onClick(() => {
      this.othersExpanded = true;
    })
  }

  /** inSearch：搜索结果里名字高亮关键词，第二行写所在位置，不响应长按。 */
  @Builder
  entryRow(entry: WebDavEntry, index: number, count: number, inSearch: boolean) {
    Row({ space: AppSpacing.LG }) {
      this.entryIcon(entry)
      Column({ space: AppSpacing.XXS }) {
        if (inSearch) {
          this.highlightedName(KeywordMatch.split(entry.name, this.keyword))
        } else {
          Text(entry.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (inSearch || !entry.directory) {
          Text(this.entrySubtitle(entry, inSearch))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (entry.directory) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.subTextColor()])
      } else if (entry.readableBook() && this.isOnShelf(entry)) {
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
    .constraintSize({ minHeight: entry.directory && !inSearch ? 54 : 68 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .borderRadius(this.rowRadius(index, count))
    .border({ width: { bottom: index < count - 1 ? 0.5 : 0 }, color: ThemeRuntime.dividerColor(this.appDarkMode) })
    .opacity(ListDissolve.opacity(this.isEntryDissolving(entry)) *
      (!entry.directory && !entry.readableBook() ? 0.6 : 1))
    .scale(ListDissolve.scale(this.isEntryDissolving(entry)))
    .blur(ListDissolve.blur(this.isEntryDissolving(entry)))
    .hitTestBehavior(this.isEntryDissolving(entry) ? HitTestMode.None : HitTestMode.Default)
    .id(inSearch ? `webdav_search_${encodeURIComponent(entry.relativePath)}` :
      this.entryCardElementId(entry.relativePath))
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!this.busy && !inSearch) this.openEntryActions(entry, event);
        })
    )
    .onClick(() => {
      if (this.showEntryActionMenu || this.showEntryNameDialog) return;
      if (inSearch) {
        this.openSearchResult(entry);
      } else {
        this.openEntry(entry);
      }
    })
  }

  @Builder
  entryIcon(entry: WebDavEntry) {
    if (entry.directory) {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(26)
          .fontColor([this.accentColor()])
      }
      .width(34)
      .justifyContent(FlexAlign.Center)
    } else if (entry.readableBook()) {
      // 书脊色块：按格式上色，底部印格式名。
      Text(entry.format().toUpperCase())
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(34)
        .height(44)
        .align(Alignment.Bottom)
        .padding({ bottom: 5 })
        .borderRadius({ topLeft: 4, bottomLeft: 4, topRight: 7, bottomRight: 7 })
        .backgroundColor(WebDavBrowseSupport.formatColor(entry.format()))
    } else {
      Row() {
        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(26)
          .fontColor([this.subTextColor()])
      }
      .width(34)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  highlightedName(match: KeywordMatch) {
    Text() {
      Span(match.before)
      Span(match.hit)
        .fontColor(this.accentColor())
        .fontWeight(FontWeight.Medium)
      Span(match.after)
    }
    .fontSize(AppFontSize.BODY_LARGE)
    .fontColor(this.primaryTextColor())
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  skeletonList() {
    Column() {
      ForEach([0, 1, 2], (index: number) => {
        Row({ space: AppSpacing.LG }) {
          Row()
            .width(34)
            .height(44)
            .borderRadius({ topLeft: 4, bottomLeft: 4, topRight: 7, bottomRight: 7 })
            .backgroundColor(this.softColor())
          Column({ space: AppSpacing.MD }) {
            Row()
              .width(index === 1 ? '48%' : '64%')
              .height(12)
              .borderRadius(6)
              .backgroundColor(this.softColor())
            Row()
              .width('32%')
              .height(10)
              .borderRadius(5)
              .backgroundColor(this.softColor())
              .opacity(0.7)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(68)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .border({ width: { bottom: index < 2 ? 0.5 : 0 }, color: ThemeRuntime.dividerColor(this.appDarkMode) })
      }, (index: number) => `${index}`)
    }
    .width('100%')
    .margin({ top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .clip(true)
    .accessibilityText('正在读取')
  }

  @Builder
  searchResultsList() {
    if (!WebDavBrowseSupport.normalizeKeyword(this.keyword)) {
      Column({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(36)
          .fontColor([this.subTextColor()])
        Text(this.searchDeep ? `输入文件名，在“${this.currentFolderLabel()}”及其子文件夹里搜索` :
          `输入文件名，在“${this.currentFolderLabel()}”里搜索`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 36, right: 36, bottom: 80 })
    } else {
      List() {
        ListItem() {
          this.groupHeader(this.searchSummary())
        }
        ForEach(this.searchResults(), (entry: WebDavEntry, index: number) => {
          ListItem() {
            this.entryRow(entry, index, this.searchResultCount(), true)
          }
        }, (entry: WebDavEntry) => `search_${this.entryKey(entry)}`)
        ListItem() {
          this.searchStatusRow()
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
      .onScrollStart(() => {
        // 滑动结果时收起键盘，便于看全列表。
        this.searchInputController.stopEditing();
      })
    }
  }

  @Builder
  searchStatusRow() {
    if (!this.searchDeep) {
      if (this.folderEntries.length > 0) {
        Row({ space: AppSpacing.MD }) {
          Text(this.searchResultCount() === 0 ? '当前文件夹没有匹配项' : '子文件夹里的文件这里搜不到')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .layoutWeight(1)
          Text('搜子文件夹')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .height(32)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .borderRadius(16)
            .backgroundColor(this.cardColor())
            .onClick(() => this.setSearchDeep(true))
        }
        .width('100%')
        .height(48)
        .margin({ top: AppSpacing.LG })
        .padding({ left: AppSpacing.XL, right: AppSpacing.SM })
        .borderRadius(24)
        .backgroundColor(this.softColor())
      } else if (this.searchResultCount() === 0) {
        this.searchNote('当前文件夹没有匹配项')
      }
    } else if (this.deepSearching) {
      Row({ space: AppSpacing.MD }) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.accentColor())
        Text(`正在查子文件夹… 已查 ${this.deepScanned} 个`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        Text('停止')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .height(32)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(16)
          .backgroundColor(this.cardColor())
          .onClick(() => this.stopDeepSearch())
      }
      .width('100%')
      .height(48)
      .margin({ top: AppSpacing.LG })
      .padding({ left: AppSpacing.LG, right: AppSpacing.SM })
      .borderRadius(24)
      .backgroundColor(this.softColor())
    } else if (this.deepStopped) {
      Row({ space: AppSpacing.MD }) {
        Text(`已停止，查了 ${this.deepScanned} 个子文件夹`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        Text('继续查')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .height(32)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(16)
          .backgroundColor(this.cardColor())
          .onClick(() => this.scheduleDeepSearch(0))
      }
      .width('100%')
      .height(48)
      .margin({ top: AppSpacing.LG })
      .padding({ left: AppSpacing.XL, right: AppSpacing.SM })
      .borderRadius(24)
      .backgroundColor(this.softColor())
    } else if (this.deepFinished) {
      this.searchNote(this.deepFinishedNote())
    }
  }

  @Builder
  searchNote(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  entryActionMenu() {
    Scroll() {
      Column() {
        this.entryContextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(),
          () => this.openRenameEntryDialog())
        this.entryContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode),
          () => this.confirmDeleteEntry())

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  entryContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showEntryNameDialog) this.entryNameDialogSession.close(this.getUIContext());
  }

  openEntryNameDialog(): void {
    this.showEntryNameDialog = true;
    this.entryNameDialogSession.open(this.getUIContext(), (): void => {
      this.entryNameDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示文件命名弹窗失败:',
      onDismiss: (): void => {
        this.showEntryNameDialog = false;
      }
    });
  }

  @Builder
  entryNameDialogContent() {
    Column() {
      Text(this.entryNameMode === 'create' ? '创建文件夹' : '重命名')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })
      TextInput({ text: this.entryNameDraft,
        placeholder: this.entryNameMode === 'create' ? '文件夹名称' : '新名称' })
        .width('100%')
        .height(44)
        .backgroundColor(this.softColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((value: string) => {
          this.entryNameDraft = value;
        })
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.softColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeEntryNameDialog())
        Button(this.entryNameMode === 'create' ? '创建' : '保存')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.submitEntryNameDialog())
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .padding(AppSpacing.XXL)
  }

  async bootstrap(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const connectionId = params?.['connectionId'] || '';
    const pageTitle = (params?.['title'] || '').trim();
    const context = getContext(this);
    let connections: WebDavConnection[] = [];
    try {
      connections = await WebDavSettingsStore.loadConnections(context);
    } catch (error) {
      this.errorMessage = this.message(error);
      return;
    }
    const found = connections.find((item: WebDavConnection): boolean => item.id === connectionId);
    if (!found) {
      this.connectionMissing = true;
      this.errorMessage = '连接配置不存在';
      return;
    }
    this.connection = found;
    this.pageTitle = pageTitle || found.name;
    try {
      this.password = await WebDavSecretStore.password(context, found.id);
    } catch (_) {
      this.password = '';
    }
    const prefs = await WebDavSettingsStore.loadBrowsePrefs(context, found.id);
    this.sortMode = prefs.sortMode;
    this.showOthers = prefs.showOthers;
    this.searchDeep = prefs.searchDeep;
    this.booksOnly = prefs.booksOnly;
    this.client = new WebDavClient(found, this.password);
    this.connected = true;
    this.loadShelfUrls();
    await this.refreshFiles();
  }

  /** 列出当前目录：本次浏览列过的先直接显示，再后台刷新；没列过的显示占位行。 */
  async refreshFiles(): Promise<void> {
    const client = this.client;
    if (!client) return;
    const path = this.currentPath;
    const token = ++this.listToken;
    const cached = this.listCache.get(path);
    if (cached && this.listedPath !== path) this.showListing(path, cached);
    this.loading = true;
    try {
      const entries = await client.list(path);
      if (token !== this.listToken) return;
      this.setListing(path, entries);
      this.errorMessage = '';
    } catch (error) {
      if (token !== this.listToken) return;
      if (this.listedPath === path) {
        HdsFeedback.showToast(`刷新失败：${this.message(error)}`);
      } else {
        this.errorMessage = `读取失败：${this.message(error)}`;
      }
    } finally {
      if (token === this.listToken) this.loading = false;
    }
  }

  navigateTo(path: string): void {
    this.currentPath = path;
    this.othersExpanded = false;
    this.errorMessage = '';
    this.refreshFiles();
    // 路径条换成新位置后滚到末尾，让当前文件夹露出来。
    setTimeout(() => {
      this.breadcrumbScroller.scrollEdge(Edge.End);
    }, 50);
  }

  /** 记下某个目录的列表；是当前目录就同时显示出来。 */
  setListing(path: string, entries: WebDavEntry[]): void {
    this.listCache.set(path, entries);
    if (path === this.currentPath) this.showListing(path, entries);
  }

  private showListing(path: string, entries: WebDavEntry[]): void {
    if (path !== this.listedPath) {
      // 换了文件夹：回到列表顶部，标题行展开。
      this.headerCollapse = 0;
      try {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      } catch (_) {
      }
    }
    this.entries = entries;
    this.listingRevision++;
    this.listedPath = path;
    this.regroupEntries();
  }

  private regroupEntries(): void {
    const sorted = WebDavBrowseSupport.sortEntries(this.entries, this.sortMode);
    this.folderEntries = sorted.filter((entry: WebDavEntry): boolean => entry.directory);
    this.bookEntries = sorted.filter((entry: WebDavEntry): boolean => !entry.directory && entry.readableBook());
    this.otherEntries = sorted.filter((entry: WebDavEntry): boolean => !entry.directory && !entry.readableBook());
  }

  /** 改名、删除文件夹后，它和它下面的目录记录都作废。 */
  private forgetListings(path: string): void {
    const keys: string[] = [];
    this.listCache.forEach((_value: WebDavEntry[], key: string) => {
      if (key === path || key.startsWith(`${path}/`)) keys.push(key);
    });
    keys.forEach((key: string) => this.listCache.delete(key));
  }

  /** 搜子文件夹用：列过的目录直接复用，没列过的去云盘取并记下。 */
  private async listForSearch(path: string): Promise<WebDavEntry[]> {
    const cached = this.listCache.get(path);
    if (cached) return cached;
    const client = this.client;
    if (!client) return [];
    const entries = await client.list(path);
    this.listCache.set(path, entries);
    return entries;
  }

  retry(): void {
    if (this.connectionMissing) return;
    this.errorMessage = '';
    if (!this.client) {
      this.bootstrap();
      return;
    }
    this.refreshFiles();
  }

  loadShelfUrls(): void {
    const connectionId = this.connection.id;
    if (!connectionId) return;
    const run = async (): Promise<void> => {
      try {
        const db = AppDatabase.getInstance();
        await db.initWithContext(getContext(this));
        const urls = await db.getBookUrlsWithPrefix(LocalBookService.webDavBookUrlPrefix(connectionId));
        this.shelfUrls = new Set(urls);
        this.shelfRevision++;
      } catch (_) {
      }
    };
    run();
  }

  isOnShelf(entry: WebDavEntry): boolean {
    if (this.shelfRevision < 0 || this.shelfUrls.size === 0) return false;
    return this.shelfUrls.has(LocalBookService.webDavBookUrl(this.connection.id, entry.relativePath));
  }

  setSortMode(mode: string): void {
    if (this.sortMode === mode) return;
    this.sortMode = mode;
    this.regroupEntries();
    this.saveBrowsePrefs();
  }

  setShowOthers(show: boolean): void {
    this.showOthers = show;
    this.othersExpanded = false;
    this.saveBrowsePrefs();
  }

  private saveBrowsePrefs(): void {
    const prefs = new WebDavBrowsePrefs();
    prefs.sortMode = this.sortMode;
    prefs.showOthers = this.showOthers;
    prefs.searchDeep = this.searchDeep;
    prefs.booksOnly = this.booksOnly;
    WebDavSettingsStore.saveBrowsePrefs(getContext(this), this.connection.id, prefs).catch((error: Error) => {
      console.warn('保存远程书籍浏览偏好失败:', error.message);
    });
  }

  enterSearch(): void {
    if (this.searchActive) return;
    this.searchActive = true;
    this.focusSearchInputSoon();
  }

  focusSearchInputSoon(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(WebDavBrowsePage.SEARCH_INPUT_ID);
      } catch (_) {
      }
    }, 120);
  }

  listTopInset(): number {
    return PageScaffold.BAR_HEIGHT + this.statusBarHeight;
  }

  exitSearch(): void {
    this.cancelDeepSearch();
    this.keyword = '';
    this.deepResults = [];
    this.searchActive = false;
    this.searchInputController.stopEditing();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_) {
    }
  }

  onKeywordChange(value: string): void {
    this.keyword = value;
    if (value && !this.searchActive) this.searchActive = true;
    this.scheduleDeepSearch(350);
  }

  setSearchDeep(deep: boolean): void {
    if (this.searchDeep === deep) return;
    this.searchDeep = deep;
    this.saveBrowsePrefs();
    this.scheduleDeepSearch(0);
  }

  toggleBooksOnly(): void {
    this.booksOnly = !this.booksOnly;
    this.saveBrowsePrefs();
    this.scheduleDeepSearch(0);
  }

  /** 关键词或范围变了：先停掉上一轮，停顿 delay 毫秒后从当前文件夹往下重新查。 */
  scheduleDeepSearch(delay: number): void {
    this.cancelDeepSearch();
    this.deepResults = [];
    this.deepFinished = false;
    this.deepStopped = false;
    this.deepScanned = 0;
    this.deepFailed = 0;
    this.deepTruncated = false;
    if (!this.searchDeep || !WebDavBrowseSupport.normalizeKeyword(this.keyword)) return;
    this.deepSearching = true;
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.startDeepSearch();
    }, Math.max(50, delay));
  }

  private async startDeepSearch(): Promise<void> {
    const search = new WebDavFolderSearch((path: string): Promise<WebDavEntry[]> => this.listForSearch(path),
      this.keyword, this.booksOnly);
    this.folderSearch = search;
    this.deepSearching = true;
    let start: WebDavEntry[] = this.entries;
    if (this.listedPath !== this.currentPath) {
      try {
        start = await this.listForSearch(this.currentPath);
      } catch (_) {
        start = [];
      }
      if (search !== this.folderSearch) return;
    }
    search.run(start, (matches: WebDavEntry[]): void => {
      if (search !== this.folderSearch) return;
      this.deepScanned = search.scanned;
      if (matches.length > 0) this.deepResults = this.deepResults.concat(matches);
    }).then((): void => {
      if (search !== this.folderSearch || search.isCancelled()) return;
      this.folderSearch = null;
      this.deepScanned = search.scanned;
      this.deepFailed = search.failed;
      this.deepTruncated = search.truncated;
      this.deepSearching = false;
      this.deepFinished = true;
    });
  }

  stopDeepSearch(): void {
    this.cancelDeepSearch();
    this.deepStopped = true;
  }

  private cancelDeepSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.folderSearch) {
      this.folderSearch.cancel();
      this.folderSearch = null;
    }
    this.deepSearching = false;
  }

  /** 当前文件夹里的命中项在前（按当前排序），子文件夹里查到的按查到的先后接在后面。 */
  searchResults(): WebDavEntry[] {
    const keyword = WebDavBrowseSupport.normalizeKeyword(this.keyword);
    if (!keyword) return [];
    // 每行都会问一次总数，按输入记住上次结果，避免逐行重新筛选排序。
    const key = `${keyword}|${this.booksOnly}|${this.searchDeep}|${this.sortMode}|${this.listingRevision}|` +
      `${this.deepResults.length}`;
    if (key === this.searchCacheKey) return this.searchCache;
    const local = WebDavBrowseSupport.sortEntries(this.entries, this.sortMode)
      .filter((entry: WebDavEntry): boolean => WebDavBrowseSupport.matchesSearch(entry, keyword, this.booksOnly));
    this.searchCache = this.searchDeep ? local.concat(this.deepResults) : local;
    this.searchCacheKey = key;
    return this.searchCache;
  }

  searchResultCount(): number {
    return this.searchResults().length;
  }

  searchSummary(): string {
    const count = this.searchResultCount();
    if (count === 0) return this.searchDeep && this.deepSearching ? '正在查找…' : '没有找到';
    return `找到 ${count} 项`;
  }

  deepFinishedNote(): string {
    let note = `已查完 ${this.deepScanned} 个子文件夹`;
    if (this.deepTruncated) note = `已查 ${this.deepScanned} 个子文件夹，结果太多先停在这里，换个更具体的关键词试试`;
    if (this.deepFailed > 0) note += `，${this.deepFailed} 个读取失败`;
    return note;
  }

  currentFolderLabel(): string {
    return this.currentPath ? WebDavBrowseSupport.lastSegment(this.currentPath) : '根目录';
  }

  collapsedOthersLabel(): string {
    const first = this.otherEntries.length > 0 ? this.otherEntries[0].name : '';
    return this.otherEntries.length > 1 ? `其他文件 ${this.otherEntries.length} 个（${first} 等，不能阅读）` :
      `其他文件 1 个（${first}，不能阅读）`;
  }

  openSearchResult(entry: WebDavEntry): void {
    if (entry.directory) {
      this.exitSearch();
      this.navigateTo(entry.relativePath);
      return;
    }
    if (!entry.readableBook()) {
      HdsFeedback.showToast('当前仅支持 TXT、EPUB、MOBI 和 PDF');
      return;
    }
    this.searchInputController.stopEditing();
    this.openFileDetail(entry);
  }

  async openEntry(entry: WebDavEntry): Promise<void> {
    if (entry.directory) {
      this.navigateTo(entry.relativePath);
      return;
    }
    if (!entry.readableBook()) {
      HdsFeedback.showToast('当前仅支持 TXT、EPUB、MOBI 和 PDF');
      return;
    }
    this.openFileDetail(entry);
  }

  onFileDetailFlagChanged(): void {
    if (!this.showFileDetail) this.fileDetailDialogSession.close(this.getUIContext());
  }

  openFileDetail(entry: WebDavEntry): void {
    if (this.busy) return;
    const run = async (): Promise<void> => {
      let book: Book | null = null;
      try {
        const db = AppDatabase.getInstance();
        await db.initWithContext(getContext(this));
        const identity = LocalBookService.webDavBookUrl(this.connection.id, entry.relativePath);
        book = await db.getBook(identity);
      } catch (_) {
        book = null;
      }
      this.fileDetailEntry = entry;
      this.fileDetailBook = book;
      this.showFileDetail = true;
      this.fileDetailDialogSession.open(this.getUIContext(), (): void => {
        this.fileDetailDialogContent();
      }, {
        autoCancel: true,
        maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
        warnTag: '显示书籍详情弹窗失败:',
        onDismiss: (): void => {
          this.showFileDetail = false;
        }
      });
    };
    run();
  }

  @Builder
  fileDetailDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(30)
          .fontColor([this.accentColor()])
        Column({ space: AppSpacing.XS }) {
          Text(this.fileDetailEntry.name || '未命名')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`/${this.fileDetailEntry.relativePath}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Column({ space: AppSpacing.XS }) {
        Text(`格式：${this.fileDetailEntry.format().toUpperCase()}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        Text(`大小：${this.formatSize(this.fileDetailEntry.size)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        Text(`修改时间：${this.formatDate(this.fileDetailEntry.lastModified)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      .width('100%')
      .padding(AppSpacing.LG)
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.softColor())

      Row({ space: AppSpacing.MD }) {
        if (this.fileDetailBook) {
          Button('立即阅读')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor())
            .onClick(() => this.readFileBookNow())
          Button('移出书架')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.removeFileBook())
        } else {
          Button('在线预览')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.softColor())
            .onClick(() => this.previewFileBook())
          Button('加入书架')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.accentColor())
            .onClick(() => this.addFileBookToShelf())
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  private prepareFileBook(onReady: (book: Book) => void): void {
    if (this.busy) return;
    const entry = this.fileDetailEntry;
    this.showFileDetail = false;
    this.busy = true;
    this.busyText = '正在准备远程书籍...';
    this.busyProgress = 1;
    WebDavBookService.openOrImport(getContext(this), this.connection, this.password, entry,
      (message: string, percent: number): void => {
        this.busyText = message;
        this.busyProgress = percent;
      }).then((book: Book): void => {
        this.busy = false;
        this.busyText = '';
        this.busyProgress = 0;
        this.loadShelfUrls();
        onReady(book);
      }).catch((error: Object): void => {
        this.busy = false;
        this.busyText = '';
        this.busyProgress = 0;
        HdsFeedback.showToast(`下载失败：${this.message(error)}`);
      });
  }

  previewFileBook(): void {
    this.prepareFileBook((book: Book): void => {
      this.pendingPreviewBook = book;
      router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
        .catch((error: Error) => {
          HdsFeedback.showToast(`打开阅读失败：${this.message(error)}`);
        });
    });
  }

  addFileBookToShelf(): void {
    this.prepareFileBook((_book: Book): void => {
      HdsFeedback.showToast('已加入书架');
    });
  }

  readFileBookNow(): void {
    const book = this.fileDetailBook;
    if (!book) return;
    this.showFileDetail = false;
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: book.bookUrl } })
      .catch((error: Error) => {
        HdsFeedback.showToast(`打开阅读失败：${this.message(error)}`);
      });
  }

  removeFileBook(): void {
    const book = this.fileDetailBook;
    if (!book) return;
    promptAction.showDialog({
      title: '移出书架',
      message: `《${book.name}》`,
      buttons: [
        { text: '取消', color: this.primaryTextColor() },
        { text: '移出', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse): void => {
      if (data.index !== 1) return;
      const run = async (): Promise<void> => {
        try {
          await LocalBookService.deleteBookWithFiles(getContext(this), book.bookUrl);
          this.showFileDetail = false;
          this.loadShelfUrls();
          HdsFeedback.showToast('已移出书架');
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${this.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  private confirmPreviewShelf(book: Book): void {
    promptAction.showDialog({
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
          this.loadShelfUrls();
          HdsFeedback.showToast('已移出书架');
        } catch (error) {
          HdsFeedback.showToast(`移出失败：${this.message(error as Object)}`);
        }
      };
      run();
    }).catch(() => {});
  }

  goParent(): void {
    this.navigateTo(WebDavBrowseSupport.parentPath(this.currentPath));
  }

  openCreateFolderDialog(): void {
    if (this.busy) return;
    this.actionEntryPath = '';
    this.entryNameMode = 'create';
    this.entryNameDraft = '';
    this.openEntryNameDialog();
  }

  openEntryActions(entry: WebDavEntry, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionEntryPath = entry.relativePath;
    this.showEntryActionMenu = true;
  }

  closeEntryActions(): void {
    this.showEntryActionMenu = false;
    this.actionEntryPath = '';
  }

  actionEntry(): WebDavEntry | null {
    return this.entries.find((entry: WebDavEntry): boolean => entry.relativePath === this.actionEntryPath) || null;
  }

  openRenameEntryDialog(): void {
    const entry = this.actionEntry();
    if (!entry) return;
    this.showEntryActionMenu = false;
    this.entryNameMode = 'rename';
    this.entryNameDraft = entry.name;
    this.openEntryNameDialog();
  }

  closeEntryNameDialog(): void {
    this.showEntryNameDialog = false;
    this.entryNameMode = '';
    this.entryNameDraft = '';
    this.actionEntryPath = '';
  }

  async submitEntryNameDialog(): Promise<void> {
    if (this.busy) return;
    const name = this.entryNameDraft.trim();
    const validation = this.validateEntryName(name);
    if (validation) {
      HdsFeedback.showToast(validation);
      return;
    }
    const entry = this.entryNameMode === 'rename' ? this.actionEntry() : null;
    if (this.entryNameMode === 'rename' && !entry) {
      this.closeEntryNameDialog();
      return;
    }
    const duplicate = this.entries.some((item: WebDavEntry): boolean =>
      item.name === name && (!entry || item.relativePath !== entry.relativePath));
    if (duplicate) {
      HdsFeedback.showToast('同名文件或文件夹已存在');
      return;
    }
    const mode = this.entryNameMode;
    const client = this.client;
    if (!client) return;
    this.showEntryNameDialog = false;
    this.busy = true;
    this.busyText = mode === 'create' ? '正在创建文件夹...' : '正在重命名...';
    this.busyProgress = 45;
    try {
      const path = this.currentPath;
      if (mode === 'create') {
        await client.createLibraryFolder(path, name);
      } else if (entry) {
        await client.renameLibraryEntry(entry.relativePath, name, entry.directory);
        if (entry.directory) this.forgetListings(entry.relativePath);
      }
      this.busyProgress = 80;
      this.setListing(path, await client.list(path));
      this.busyProgress = 100;
      HdsFeedback.showToast(mode === 'create' ? '文件夹已创建' : '重命名完成');
    } catch (error) {
      HdsFeedback.showToast(`${mode === 'create' ? '创建' : '重命名'}失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
      this.entryNameMode = '';
      this.entryNameDraft = '';
      this.actionEntryPath = '';
    }
  }

  async confirmDeleteEntry(): Promise<void> {
    const entry = this.actionEntry();
    if (!entry || this.busy) return;
    this.closeEntryActions();
    const confirmation = await promptAction.showDialog({
      title: entry.directory ? '删除文件夹' : '删除文件',
      message: entry.directory ? `确定删除“${entry.name}”及其中的全部内容吗？此操作无法撤销。` :
        `确定删除“${entry.name}”吗？此操作无法撤销。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1) return;
    const client = this.client;
    if (!client) return;
    this.busy = true;
    this.busyText = entry.directory ? '正在删除文件夹...' : '正在删除文件...';
    this.busyProgress = 45;
    const path = this.currentPath;
    try {
      await client.deleteLibraryEntry(entry.relativePath, entry.directory);
      if (entry.directory) this.forgetListings(entry.relativePath);
      this.busyProgress = 80;
      const next = await client.list(path);
      this.busyProgress = 100;
      // 先收起进度提示露出列表，被删的条目消散后再换成新列表。
      this.busy = false;
      const keys = [entry.relativePath];
      await ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
        this.dissolvingPaths = [...this.dissolvingPaths, key];
      }, ListDissolve.particles('webdav_browse_root', [this.accentColor(), this.primaryTextColor(), this.subTextColor()],
        (key: string): string => this.entryCardElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
        (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
      ListDissolve.commit(this.getUIContext(), () => {
        this.setListing(path, next);
      }, () => {
        this.dissolvingPaths = ListDissolve.without(this.dissolvingPaths, keys);
      });
      HdsFeedback.showToast('删除完成');
    } catch (error) {
      HdsFeedback.showToast(`删除失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  async chooseAndUploadFiles(): Promise<void> {
    if (this.busy) return;
    const client = this.client;
    if (!client) return;
    let selected: string[] = [];
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FILE;
      options.maxSelectNumber = 20;
      selected = await new picker.DocumentViewPicker(getContext(this)).select(options);
    } catch (error) {
      const message = this.message(error);
      if (!message.toLowerCase().includes('cancel')) {
        HdsFeedback.showToast(`选择文件失败：${message}`);
      }
      return;
    }
    if (!selected || selected.length === 0) return;
    this.busy = true;
    this.busyProgress = 1;
    let uploaded = 0;
    let failed = 0;
    let firstFailure = '';
    const path = this.currentPath;
    try {
      for (let index = 0; index < selected.length; index++) {
        const uri = selected[index];
        const name = this.fileNameFromUri(uri, index);
        this.busyText = selected.length > 1 ? `正在上传 ${index + 1}/${selected.length}：${name}` : `正在上传：${name}`;
        try {
          await client.uploadLibraryFile(getContext(this), uri, path, name,
            (sent: number, total: number): void => {
              const ratio = total > 0 ? Math.min(1, sent / total) : 0;
              this.busyProgress = Math.max(1, Math.min(94,
                Math.floor(((index + ratio) / selected.length) * 94)));
            });
          uploaded++;
        } catch (error) {
          failed++;
          if (!firstFailure) firstFailure = `${name}：${this.message(error)}`;
        }
      }
      this.busyText = '正在刷新远端目录...';
      this.busyProgress = 96;
      this.setListing(path, await client.list(path));
      this.busyProgress = 100;
      if (failed === 0) {
        HdsFeedback.showToast(`已上传 ${uploaded} 个文件`);
      } else {
        HdsFeedback.showToast(`上传完成：成功 ${uploaded}，失败 ${failed}；${firstFailure}`);
      }
    } catch (error) {
      HdsFeedback.showToast(`上传失败：${this.message(error)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
      this.busyProgress = 0;
    }
  }

  validateEntryName(name: string): string {
    if (!name) return '请输入名称';
    if (name === '.' || name === '..') return '名称不能是“.”或“..”';
    if (name.includes('/') || name.includes('\\')) return '名称不能包含路径分隔符';
    if (name.length > 255) return '名称不能超过 255 个字符';
    return '';
  }

  fileNameFromUri(uri: string, index: number): string {
    const clean = (uri || '').split('?')[0].split('#')[0].replace(/\/+$/, '');
    let decoded = clean;
    try { decoded = decodeURIComponent(clean); } catch (_) {}
    const separator = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    const name = (separator >= 0 ? decoded.substring(separator + 1) : decoded).trim();
    return name || `upload_${Date.now()}_${index + 1}`;
  }

  currentTitle(): string {
    return this.pageTitle || this.connection.name || 'WebDAV';
  }

  entrySubtitle(entry: WebDavEntry, inSearch: boolean): string {
    if (inSearch) {
      const location = WebDavBrowseSupport.locationLabel(entry, this.currentPath);
      return entry.directory ? `${location} · 文件夹` : `${location} · ${this.formatSize(entry.size)}`;
    }
    if (entry.readableBook()) return `${this.formatSize(entry.size)} · ${this.formatShortDate(entry.lastModified)}`;
    const dot = entry.name.lastIndexOf('.');
    const extension = dot > 0 && dot < entry.name.length - 1 ? entry.name.substring(dot + 1).toUpperCase() : '文件';
    return `${extension} · ${this.formatSize(entry.size)}`;
  }

  entryKey(entry: WebDavEntry): string {
    return `${entry.relativePath}_${entry.etag}_${entry.lastModified}`;
  }

  /** 同组各行连成一张卡片：首行上圆角、末行下圆角。 */
  rowRadius(index: number, count: number): BorderRadiuses {
    const radius = ThemeRuntime.cardRadius();
    const top = index === 0 ? radius : 0;
    const bottom = index === count - 1 ? radius : 0;
    return { topLeft: top, topRight: top, bottomLeft: bottom, bottomRight: bottom };
  }

  formatShortDate(timestamp: number): string {
    if (timestamp <= 0) return '时间未知';
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    if (size < 1024 * 1024 * 1024) return `${(size / 1024 / 1024).toFixed(1)} MB`;
    return `${(size / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  formatDate(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '时间未知';
  }

  message(error: Object): string {
    return WebDavError.message(error);
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }

  entryCardElementId(path: string): string {
    return `webdav_entry_card_${encodeURIComponent(path)}`;
  }

  isEntryDissolving(entry: WebDavEntry): boolean {
    return this.dissolvingPaths.length > 0 && this.dissolvingPaths.indexOf(entry.relativePath) >= 0;
  }
  softColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
}
