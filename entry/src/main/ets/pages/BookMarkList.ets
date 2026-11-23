import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuAction, PopupMenuHeader } from '../components/common/PopupMenuAction';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { BookMarkListViewStore } from '../utils/BookMarkListViewStore';
import { appDb } from '../model/data/AppDatabase';
import { BookMark, BookMarkRules, BookMarkStatus } from '../model/book/BookMark';
import { BookMarkService } from '../core/mark/BookMarkService';
import { BookCover } from '../components/book/BookCover';
import { BookMarkStars } from '../components/book/BookMarkStars';

const SORT_RECENT: string = 'recent';
const SORT_RATING: string = 'rating';
/** 封面墙一格的最小宽度与格间距，列数按列表宽度算，手机上是三列。 */
const WALL_CELL_MIN_WIDTH: number = 108;
const WALL_GAP: number = 12;
/** 封面墙底部小卡大致的高度，小卡出现时列表末尾多留这么多，最后一行不被挡住。 */
const PEEK_CARD_RESERVE: number = 150;

/** 读书手账的一行：分段标题（mark 为空）或一本书。 */
class JournalRow {
  key: string = '';
  title: string = '';
  count: number = 0;
  mark: BookMark | null = null;
}

/**
 * 我的标记：在书籍详情页打过分、加过标签或写过短评的书，按作品一条。
 * 三种布局，在顶栏的布局按钮里选并记住上次用的（BookMarkListViewStore，默认读书手账）：
 * - 读书手账：按标记月份分段，写了短评的书以短评为正文；按评分排序时改为按星级分段。点一条进详情页。
 * - 卡片列表：改版前的排法，一本书一张卡、封面在左，短评全文显示。点一条进详情页，右上角“更多”或长按出菜单。
 * - 封面墙：多列封面，点一本在底部浮出小卡看日期、标签和短评，再从小卡进详情页。
 * 读书手账和封面墙：状态页签、标签行随内容一起滚动；搜索、排序、管理标签在顶栏按钮里。
 * 卡片列表整页沿用改版前的样子：统计、搜索框、状态与标签胶囊、排序行固定在列表上方，顶栏只留布局按钮。
 * 三种布局长按一本书都弹出操作菜单。
 * 标签的重命名、删除在“管理标签”面板里，同时改到书架上（标签和书架标签是同一套，见 BookMarkService）。
 */
@Entry
@Component
struct BookMarkListPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('bookMarkRevision') @Watch('onRevisionChanged') bookMarkRevision: number = 0;
  @State items: BookMark[] = [];
  @State categories: string[] = [];
  @State statusFilter: number = 0;
  @State categoryFilter: string = '';
  @State sortMode: string = SORT_RECENT;
  @State keyword: string = '';
  @State loaded: boolean = false;
  @State viewMode: string = BookMarkListViewStore.JOURNAL;
  @State showSearch: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showViewMenu: boolean = false;
  /** 卡片列表里打开“更多”菜单的那条标记的作品键。 */
  @State menuKey: string = '';
  /** 封面墙里底部小卡正在显示的那本书的作品键。 */
  @State peekKey: string = '';
  @State listWidth: number = 0;
  @State showCategorySheet: boolean = false;
  /** 管理标签面板里正在改名的标签与输入。 */
  @State renamingCategory: string = '';
  @State renameInput: string = '';
  private visible: boolean = false;
  private loadGeneration: number = 0;
  private viewRestored: boolean = false;

  onPageShow(): void {
    this.visible = true;
    syncSystemBars(getContext(this), this.darkMode, ThemeRuntime.pageColor(this.darkMode));
    // 从详情页回来时可能改过标记，每次显示都重读。
    this.load();
  }

  onPageHide(): void {
    this.visible = false;
  }

  onRevisionChanged(): void {
    if (this.visible) this.load();
  }

  async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    try {
      if (!this.viewRestored) {
        // 先定视图再出内容，免得先画成手账又跳成封面墙。
        this.viewMode = await BookMarkListViewStore.load(getContext(this));
        this.viewRestored = true;
      }
      await appDb.init(getContext(this));
      const items = await appDb.getAllBookMarks();
      if (generation !== this.loadGeneration) return;
      this.items = items;
      this.categories = BookMarkRules.collectCategories(items);
      if (this.categoryFilter && !this.categories.includes(this.categoryFilter)) this.categoryFilter = '';
    } catch (error) {
      console.warn('读取书籍标记失败:', error);
    } finally {
      if (generation === this.loadGeneration) this.loaded = true;
    }
  }

  visibleItems(): BookMark[] {
    const keyword = this.keyword.trim().toLowerCase();
    const result = this.items.filter((item: BookMark): boolean => {
      if (this.statusFilter && item.status !== this.statusFilter) return false;
      if (this.categoryFilter && !item.categories.includes(this.categoryFilter)) return false;
      if (!keyword) return true;
      return item.bookName.toLowerCase().includes(keyword) || item.author.toLowerCase().includes(keyword) ||
        item.review.toLowerCase().includes(keyword);
    });
    if (this.sortMode === SORT_RATING) {
      result.sort((a: BookMark, b: BookMark): number => (b.rating - a.rating) || (b.updateTime - a.updateTime));
    }
    return result;
  }

  /** 页签上的本数：不受标签和搜索影响，始终是这个状态一共多少本。 */
  statusCount(status: number): number {
    if (status === 0) return this.items.length;
    return this.items.filter((item: BookMark): boolean => item.status === status).length;
  }

  /** 跟着当前状态页签算，不受标签和搜索影响；“全部”不算弃读的书。 */
  averageText(): string {
    return BookMarkRules.averageRatingText(this.items, this.statusFilter);
  }

  categoryCount(name: string): number {
    return this.items.filter((item: BookMark): boolean => item.categories.includes(name)).length;
  }

  /**
   * 读书手账的行：相邻且分段名相同的书归到一段，段首插一行标题。
   * 最近标记按月份分，评分排序按星级分（按月份分在那种顺序下没有意义）。
   */
  journalRows(): JournalRow[] {
    const rows: JournalRow[] = [];
    const byRating = this.sortMode === SORT_RATING;
    const now = Date.now();
    let section: JournalRow | null = null;
    this.visibleItems().forEach((item: BookMark) => {
      const title = byRating ? BookMarkRules.ratingBand(item.rating) : BookMarkRules.monthLabel(item.updateTime, now);
      if (section === null || section.title !== title) {
        section = new JournalRow();
        section.title = title;
        section.key = `s:${title}:${rows.length}`;
        rows.push(section);
      }
      section.count++;
      const row = new JournalRow();
      row.mark = item;
      row.key = this.itemKey(item);
      rows.push(row);
    });
    return rows;
  }

  itemKey(item: BookMark): string {
    return `${item.workKey}|${item.updateTime}|${item.categories.join(',')}`;
  }

  wallColumns(): number {
    if (this.listWidth <= 0) return 3;
    return Math.max(3, Math.min(8, Math.floor((this.listWidth + WALL_GAP) / (WALL_CELL_MIN_WIDTH + WALL_GAP))));
  }

  wallRows(): BookMark[][] {
    const columns = this.wallColumns();
    const items = this.visibleItems();
    const rows: BookMark[][] = [];
    for (let i = 0; i < items.length; i += columns) {
      rows.push(items.slice(i, i + columns));
    }
    return rows;
  }

  /** 末行不满时补的空格数，让末行的封面和上面各行一样宽。 */
  wallFillers(used: number): number[] {
    const fillers: number[] = [];
    for (let i = used; i < this.wallColumns(); i++) {
      fillers.push(i);
    }
    return fillers;
  }

  /** 底部小卡对应的书；被筛掉或删掉后小卡跟着消失。 */
  peekItem(): BookMark | null {
    if (this.viewMode !== BookMarkListViewStore.WALL || !this.peekKey) return null;
    const found = this.visibleItems().find((item: BookMark): boolean => item.workKey === this.peekKey);
    return found === undefined ? null : found;
  }

  viewIcon(): Resource {
    if (this.viewMode === BookMarkListViewStore.WALL) return $r('sys.symbol.square_grid_2x2');
    if (this.viewMode === BookMarkListViewStore.LIST) return $r('sys.symbol.list_bullet');
    return $r('sys.symbol.doc_text');
  }

  /** 布局、排序菜单里某一项是不是当前选中的；kind 是 'view' 或 'sort'。 */
  isChoice(kind: string, value: string): boolean {
    return (kind === 'view' ? this.viewMode : this.sortMode) === value;
  }

  choose(kind: string, value: string): void {
    this.showMoreMenu = false;
    this.showViewMenu = false;
    if (kind !== 'view') {
      this.sortMode = value;
      return;
    }
    if (this.viewMode === value) return;
    this.viewMode = value;
    this.peekKey = '';
    if (value !== BookMarkListViewStore.LIST && this.keyword) this.showSearch = true;
    BookMarkListViewStore.save(getContext(this), value);
  }

  toggleSearch(): void {
    this.showSearch = !this.showSearch;
    if (!this.showSearch) this.keyword = '';
  }

  tagLine(item: BookMark): string {
    return item.categories.map((name: string): string => `# ${name}`).join('  ');
  }

  /** 手账里书名下面那行：作者和标签，哪个没有就不写。 */
  journalSubline(item: BookMark): string {
    const parts: string[] = [];
    if (item.author) parts.push(item.author);
    if (item.categories.length > 0) parts.push(this.tagLine(item));
    return parts.join(' · ');
  }

  build() {
    Stack() {
      PageScaffold({
        title: '我的标记',
        scrollable: false,
        collapsible: false,
        actions: () => {
          this.pageActions()
        },
        content: () => {
          this.pageContent()
        }
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showCategorySheet, this.categorySheet(), this.categorySheetOptions())
  }

  @Builder
  pageActions() {
    if (this.items.length > 0) {
      Row({ space: AppSpacing.MD }) {
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.coupon'),
          accessibilityLabel: '票夹',
          onTap: (): void => {
            router.pushUrl({ url: 'pages/TicketAlbum' }).catch((error: Error) => {
              console.warn('打开票夹失败:', error.message);
            });
          }
        })
        ImmersiveHeaderAction({
          icon: this.viewIcon(),
          accessibilityLabel: '切换布局',
          onTap: (): void => {
            this.showViewMenu = !this.showViewMenu;
          }
        })
          .bindPopup(this.showViewMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => {
              this.viewMenu();
            }, Placement.Bottom, this.darkMode, ThemeRuntime.accentColor(this.darkMode), (): void => {
              this.showViewMenu = false;
            }))
        if (this.viewMode !== BookMarkListViewStore.LIST) {
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.magnifyingglass'),
          tint: this.showSearch ? ThemeRuntime.accentColor(this.darkMode) : '',
          accessibilityLabel: this.showSearch ? '收起搜索' : '搜索',
          onTap: (): void => {
            this.toggleSearch();
          }
        })
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.more'),
          accessibilityLabel: '排序与管理标签',
          onTap: (): void => {
            this.showMoreMenu = !this.showMoreMenu;
          }
        })
          .bindPopup(this.showMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => {
              this.moreMenu();
            }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), (): void => {
              this.showMoreMenu = false;
            }))
        }
      }
      .margin({ right: AppSpacing.XL })
    }
  }

  @Builder
  viewMenu() {
    Column() {
      PopupMenuHeader('布局', ThemeRuntime.subTextColor(this.darkMode))
      this.menuChoiceRow('view', BookMarkListViewStore.JOURNAL, '读书手账')
      this.menuChoiceRow('view', BookMarkListViewStore.LIST, '卡片列表')
      this.menuChoiceRow('view', BookMarkListViewStore.WALL, '封面墙')
    }
    .width(170)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  moreMenu() {
    Column() {
      PopupMenuHeader('排序', ThemeRuntime.subTextColor(this.darkMode))
      this.menuChoiceRow('sort', SORT_RECENT, '最近标记')
      this.menuChoiceRow('sort', SORT_RATING, '评分从高到低')
      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.darkMode))
        .margin({ left: 12, right: 12, top: 4, bottom: 4 })
      PopupMenuAction(undefined, '管理标签', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.showMoreMenu = false;
        this.renamingCategory = '';
        this.showCategorySheet = true;
      }, this.categories.length > 0)
    }
    .width(190)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 布局、排序菜单的一行，尺寸与 PopupMenuAction 一致，当前项标强调色并打勾。选中状态在 builder 里读，不按值传。 */
  @Builder
  menuChoiceRow(kind: string, value: string, label: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.isChoice(kind, value) ? ThemeRuntime.accentColor(this.darkMode) :
          ThemeRuntime.primaryTextColor(this.darkMode))
        .maxLines(1)
        .layoutWeight(1)
      if (this.isChoice(kind, value)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([ThemeRuntime.accentColor(this.darkMode)])
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
    .accessibilityText(label)
    .accessibilitySelected(this.isChoice(kind, value))
    .onClick(() => {
      this.choose(kind, value);
    })
  }

  @Builder
  pageContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: this.viewMode === BookMarkListViewStore.LIST ? AppSpacing.MD : AppSpacing.SM }) {
        if (this.loaded && this.items.length === 0) {
          this.emptyState('还没有标记过书', '在书籍详情页点星星打分，或者加标签、写短评，标记过的书会收在这里。')
        } else if (this.loaded) {
          if (this.viewMode === BookMarkListViewStore.LIST) {
            this.classicStatsRow()
            this.searchField(false)
            this.classicStatusChips()
            if (this.categories.length > 0) {
              this.classicCategoryChips()
            }
            this.classicSortRow()
          } else if (this.showSearch) {
            this.searchField(true)
          }
          List({ space: AppSpacing.MD }) {
            if (this.viewMode !== BookMarkListViewStore.LIST) {
              ListItem() {
                this.filterHeader()
              }
            }
            if (this.visibleItems().length === 0) {
              ListItem() {
                this.emptyState('没有符合条件的书', '换个筛选条件或关键词试试。')
              }
            } else if (this.viewMode === BookMarkListViewStore.WALL) {
              ForEach(this.wallRows(), (row: BookMark[]) => {
                ListItem() {
                  this.wallRow(row)
                }
              }, (row: BookMark[]) => `${this.wallColumns()}#` +
                row.map((item: BookMark): string => this.itemKey(item)).join('#'))
            } else if (this.viewMode === BookMarkListViewStore.LIST) {
              ForEach(this.visibleItems(), (item: BookMark) => {
                ListItem() {
                  this.listCard(item)
                }
              }, (item: BookMark) => this.itemKey(item))
            } else {
              ForEach(this.journalRows(), (row: JournalRow) => {
                ListItem() {
                  if (row.mark !== null) {
                    this.journalCard(row.mark as BookMark)
                  } else {
                    this.sectionHeader(row)
                  }
                }
              }, (row: JournalRow) => row.mark !== null ? row.key : `${row.key}:${row.count}`)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .contentEndOffset(this.navBarHeight + AppSpacing.XXXL + (this.peekItem() !== null ? PEEK_CARD_RESERVE : 0))
          .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
            this.listWidth = Number(newValue.width) || 0;
          })
        }
      }
      .width('100%')
      .height('100%')

      if (this.peekItem() !== null) {
        this.peekCard(this.peekItem() as BookMark)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
  }

  /** 状态页签（带本数，右侧是平均星级）和标签行；是列表的第一项，跟着内容滚走。 */
  @Builder
  filterHeader() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        // 五个页签加均分在窄屏放不下，页签部分可以横向滑动，均分固定在右侧。
        Scroll() {
          Row({ space: AppSpacing.XL }) {
            ForEach([0, ...BookMarkStatus.ALL], (value: number) => {
              this.statusTab(value)
            }, (value: number) => `${value}`)
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.BottomStart)
        .layoutWeight(1)
        if (this.averageText()) {
          Row({ space: AppSpacing.XS }) {
            Text('均分')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            Text(this.averageText())
              .fontSize(AppFontSize.BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
              .fontFeature('"tnum" 1')
          }
          .padding({ bottom: AppSpacing.SM })
          .accessibilityGroup(true)
          .accessibilityText(
            `${this.statusFilter === 0 ? '' : BookMarkStatus.label(this.statusFilter)}平均 ${this.averageText()} 星`)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      .border({ width: { bottom: 0.5 }, color: ThemeRuntime.hairlineColor(this.darkMode) })

      if (this.categories.length > 0) {
        List({ space: AppSpacing.SM }) {
          ForEach(this.categories, (name: string) => {
            ListItem() {
              this.categoryChip(name)
            }
          }, (name: string) => name)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height(32)
      }
    }
    .width('100%')
  }

  @Builder
  statusTab(value: number) {
    Row({ space: 3 }) {
      Text(value === 0 ? '全部' : BookMarkStatus.label(value))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.statusFilter === value ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.statusFilter === value ? ThemeRuntime.primaryTextColor(this.darkMode) :
          ThemeRuntime.subTextColor(this.darkMode))
      Text(`${this.statusCount(value)}`)
        .fontSize(AppFontSize.MICRO + 1)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .fontFeature('"tnum" 1')
    }
    .alignItems(VerticalAlign.Bottom)
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
    .border({
      width: { bottom: 2 },
      color: this.statusFilter === value ? ThemeRuntime.accentColor(this.darkMode) : Color.Transparent
    })
    .accessibilityGroup(true)
    .accessibilityText(`${value === 0 ? '全部' : BookMarkStatus.label(value)}，${this.statusCount(value)} 本`)
    .accessibilitySelected(this.statusFilter === value)
    .onClick(() => {
      this.statusFilter = value;
    })
  }

  /** autoFocus：从顶栏搜索按钮点开时直接聚焦；卡片列表里常驻的搜索框不抢焦点。 */
  @Builder
  searchField(autoFocus: boolean) {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
      TextInput({ text: this.keyword, placeholder: '搜索书名、作者或短评' })
        .layoutWeight(1)
        .height(40)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
        .backgroundColor(Color.Transparent)
        .caretColor(ThemeRuntime.accentColor(this.darkMode))
        .padding({ left: 0, right: 0 })
        .defaultFocus(autoFocus)
        .onChange((value: string) => {
          this.keyword = value;
        })
      if (this.keyword) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(18)
          .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
          .accessibilityText('清除搜索')
          .onClick(() => {
            this.keyword = '';
          })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(22)
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
  }

  /** 标签筛选：点一下选中，再点一下取消。 */
  @Builder
  categoryChip(name: string) {
    Text(`# ${name}`)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.categoryFilter === name ? ThemeRuntime.accentColor(this.darkMode) :
        ThemeRuntime.primaryTextColor(this.darkMode))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 160 })
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .border({ width: 1, color: this.categoryFilter === name ? ThemeRuntime.accentColor(this.darkMode) :
        Color.Transparent })
      .backgroundColor(this.categoryFilter === name ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
        ThemeRuntime.cardColor(this.darkMode))
      .accessibilityText(`标签 ${name}`)
      .accessibilitySelected(this.categoryFilter === name)
      .onClick(() => {
        this.categoryFilter = this.categoryFilter === name ? '' : name;
      })
  }

  @Builder
  sectionHeader(row: JournalRow) {
    Row({ space: AppSpacing.SM }) {
      Text(row.title)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
      Text(`${row.count} 本`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .padding({ left: AppSpacing.XS, top: AppSpacing.XS })
  }

  /** 读书手账的一本书：有短评时短评是正文、书的信息在分隔线下面；没有短评时只有书的信息一行。 */
  @Builder
  journalCard(item: BookMark) {
    Column({ space: AppSpacing.MD }) {
      if (item.review.trim()) {
        Text(item.review.trim())
          .fontSize(AppFontSize.BODY_LARGE)
          .lineHeight(25)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .wordBreak(WordBreak.BREAK_WORD)
          .width('100%')
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.darkMode))
      }
      Row({ space: AppSpacing.MD }) {
        this.cover(item, 36, 48, 108, 144)
        Column({ space: 2 }) {
          Text(item.bookName)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.journalSubline(item)) {
            Text(this.journalSubline(item))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: AppSpacing.XS }) {
          this.ratingLine(item, 13)
          Text(this.dateText(item))
            .fontSize(AppFontSize.MICRO + 1)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(item.review.trim() ? AppSpacing.LG : AppSpacing.MD)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .onClick(() => {
      BookMarkService.openDetail(item);
    })
    .bindContextMenu(this.itemMenu(item), ResponseType.LongPress,
      ImmersiveMaterialRuntime.contextMenuOptions(this.immersiveLightLevel, ThemeRuntime.accentColor(this.darkMode),
        () => {}))
  }

  // ---- 卡片列表沿用的改版前顶部：统计、状态胶囊、标签胶囊（含“全部标签”“管理”）、排序行 ----

  readCount(): number {
    return this.items.filter((item: BookMark): boolean => item.status === BookMarkStatus.READ).length;
  }

  @Builder
  classicStatsRow() {
    Row({ space: AppSpacing.XXXL }) {
      this.classicStatCell('已标记', 'all')
      this.classicStatCell('读过', 'read')
      this.classicStatCell('平均星级', 'average')
    }
    .width('100%')
    .padding({ left: AppSpacing.SM, right: AppSpacing.SM, bottom: AppSpacing.XS })
  }

  /** 数值在 builder 里按状态算：按值传入的参数不会随列表变化刷新。 */
  @Builder
  classicStatCell(label: string, kind: string) {
    Column({ space: 2 }) {
      Text(kind === 'all' ? `${this.items.length}` : kind === 'read' ? `${this.readCount()}` :
        (this.averageText() || '–'))
        .fontSize(AppFontSize.SUBTITLE + 2)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .fontFeature('"tnum" 1')
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  classicStatusChips() {
    Row({ space: AppSpacing.SM }) {
      ForEach([0, ...BookMarkStatus.ALL], (value: number) => {
        Text(value === 0 ? '全部' : BookMarkStatus.label(value))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.statusFilter === value ? Color.White : ThemeRuntime.primaryTextColor(this.darkMode))
          .height(32)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(16)
          .backgroundColor(this.statusFilter === value ? ThemeRuntime.accentColor(this.darkMode) :
            ThemeRuntime.cardColor(this.darkMode))
          .onClick(() => {
            this.statusFilter = value;
          })
      }, (value: number) => `${value}`)
    }
    .width('100%')
  }

  @Builder
  classicCategoryChips() {
    List({ space: AppSpacing.SM }) {
      ListItem() {
        this.classicCategoryChip('', '全部标签')
      }
      ForEach(this.categories, (name: string) => {
        ListItem() {
          this.classicCategoryChip(name, name)
        }
      }, (name: string) => name)
      ListItem() {
        Row({ space: AppSpacing.XS }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(14)
            .fontColor([ThemeRuntime.accentColor(this.darkMode)])
          Text('管理')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.accentColor(this.darkMode))
        }
        .height(32)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
        .accessibilityText('管理标签')
        .onClick(() => {
          this.renamingCategory = '';
          this.showCategorySheet = true;
        })
      }
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(32)
  }

  @Builder
  classicCategoryChip(name: string, label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.categoryFilter === name ? ThemeRuntime.accentColor(this.darkMode) :
        ThemeRuntime.primaryTextColor(this.darkMode))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 160 })
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .border({ width: 1, color: this.categoryFilter === name ? ThemeRuntime.accentColor(this.darkMode) :
        Color.Transparent })
      .backgroundColor(this.categoryFilter === name ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
        ThemeRuntime.cardColor(this.darkMode))
      .onClick(() => {
        this.categoryFilter = name;
      })
  }

  @Builder
  classicSortRow() {
    Row() {
      Text(`${this.visibleItems().length} 本`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .layoutWeight(1)
      Row({ space: AppSpacing.XS }) {
        Text(this.sortMode === SORT_RATING ? '评分从高到低' : '最近标记')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        SymbolGlyph($r('sys.symbol.sort'))
          .fontSize(13)
          .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
      }
      .padding({ left: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .accessibilityText(`排序：${this.sortMode === SORT_RATING ? '评分从高到低' : '最近标记'}，点按切换`)
      .onClick(() => {
        this.sortMode = this.sortMode === SORT_RATING ? SORT_RECENT : SORT_RATING;
      })
    }
    .width('100%')
    .padding({ left: AppSpacing.SM, right: AppSpacing.XS })
  }

  /**
   * 卡片列表的一本书，沿用改版前的排法：封面在左，右边依次是书名与“更多”、作者、星级/状态/日期、标签、短评。
   * 短评全文显示。
   */
  @Builder
  listCard(item: BookMark) {
    Row({ space: AppSpacing.LG }) {
      this.cover(item, 52, 70, 132, 176)

      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.SM }) {
          Text(item.bookName)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Stack() {
            SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
              .fontSize(16)
              .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
          }
          .width(28)
          .height(24)
          .accessibilityText('更多操作')
          .onClick(() => {
            this.menuKey = this.menuKey === item.workKey ? '' : item.workKey;
          })
          .bindPopup(this.menuKey === item.workKey, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
            (): void => {
              this.itemMenu(item);
            }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
              if (this.menuKey === item.workKey) this.menuKey = '';
            }))
        }
        .width('100%')

        if (item.author) {
          Text(item.author)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: AppSpacing.SM }) {
          if (item.rating > 0) {
            BookMarkStars({
              rating: item.rating,
              starSize: 13,
              darkMode: this.darkMode,
              emptyColor: ThemeRuntime.softFillColor(this.darkMode)
            })
            Text(BookMarkRules.ratingLabel(item.rating))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          } else {
            Text('未打分')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          }
          if (item.status !== BookMarkStatus.NONE) {
            Text(BookMarkStatus.label(item.status))
              .fontSize(AppFontSize.MICRO + 1)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.accentColor(this.darkMode))
              .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
              .borderRadius(8)
              .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
          }
          Blank()
          Text(this.dateText(item, false))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (item.categories.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(item.categories, (name: string) => {
              Text(name)
                .fontSize(AppFontSize.MICRO + 1)
                .fontColor(ThemeRuntime.accentColor(this.darkMode))
                .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
                .borderRadius(8)
                .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
                .margin({ right: AppSpacing.XS, top: AppSpacing.XXS })
            }, (name: string) => name)
          }
          .width('100%')
        }

        if (item.review.trim()) {
          Text(item.review.trim())
            .fontSize(AppFontSize.BODY)
            .lineHeight(20)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .wordBreak(WordBreak.BREAK_WORD)
            .width('100%')
            .margin({ top: AppSpacing.XXS })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.LG, right: AppSpacing.SM, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .onClick(() => {
      BookMarkService.openDetail(item);
    })
    .bindContextMenu(this.itemMenu(item), ResponseType.LongPress,
      ImmersiveMaterialRuntime.contextMenuOptions(this.immersiveLightLevel, ThemeRuntime.accentColor(this.darkMode),
        () => {}))
  }

  @Builder
  wallRow(row: BookMark[]) {
    Row({ space: WALL_GAP }) {
      ForEach(row, (item: BookMark) => {
        this.wallCell(item)
      }, (item: BookMark) => this.itemKey(item))
      ForEach(this.wallFillers(row.length), (_index: number) => {
        Column()
          .layoutWeight(1)
      }, (index: number) => `f${index}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ bottom: AppSpacing.XS })
  }

  /** 封面墙的一格：想读、在读、弃读贴在封面左上角，写过短评的右上角有笔形记号；点按在底部小卡里看这本书。 */
  @Builder
  wallCell(item: BookMark) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        BookCover({
          bookUrl: item.bookUrl,
          origin: item.origin,
          coverUrl: item.coverUrl,
          name: item.bookName,
          author: item.author,
          useBookshelfCover: true,
          placeholderColor: ThemeRuntime.accentColor(this.darkMode),
          cornerRadius: 6,
          decodeWidth: 240,
          decodeHeight: 320
        })
        if (item.status !== BookMarkStatus.NONE && item.status !== BookMarkStatus.READ) {
          Text(BookMarkStatus.label(item.status))
            .fontSize(AppFontSize.MICRO)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
            .borderRadius({ topRight: 8, bottomRight: 8 })
            .backgroundColor('#8C000000')
            .margin({ top: 6 })
            .hitTestBehavior(HitTestMode.None)
        }
        if (item.review.trim()) {
          Row() {
            Blank()
            Stack() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(10)
                .fontColor([Color.White])
            }
            .width(18)
            .height(18)
            .borderRadius(9)
            .backgroundColor('#8C000000')
          }
          .width('100%')
          .padding(5)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .aspectRatio(0.75)
      .borderRadius(6)
      .clip(true)
      .outline({
        width: 2,
        radius: 8,
        color: this.peekKey === item.workKey ? ThemeRuntime.accentColor(this.darkMode) : Color.Transparent
      })

      Text(item.bookName)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      this.ratingLine(item, 12)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .accessibilityGroup(true)
    .accessibilityText(`${item.bookName}，${item.rating > 0 ? BookMarkRules.ratingText(item.rating) + ' 星' : '未打分'}`)
    .onClick(() => {
      this.peekKey = this.peekKey === item.workKey ? '' : item.workKey;
    })
    .bindContextMenu(this.itemMenu(item), ResponseType.LongPress,
      ImmersiveMaterialRuntime.contextMenuOptions(this.immersiveLightLevel, ThemeRuntime.accentColor(this.darkMode),
        () => {}))
  }

  /** 封面墙底部的小卡：书的日期、标签和短评；点卡片或“查看详情”进详情页，点 × 收起。 */
  @Builder
  peekCard(item: BookMark) {
    Row({ space: AppSpacing.LG }) {
      this.cover(item, 54, 72, 162, 216)
      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.SM }) {
          Text(item.bookName)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.ratingLine(item, 13)
          Stack() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
          }
          .width(28)
          .height(28)
          .accessibilityText('收起')
          .onClick(() => {
            this.peekKey = '';
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(item.author ? `${item.author} · ${this.dateText(item)}` : this.dateText(item))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.categories.length > 0) {
          Text(this.tagLine(item))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(item.review.trim() || '还没写短评')
          .fontSize(AppFontSize.BODY)
          .lineHeight(21)
          .fontColor(item.review.trim() ? ThemeRuntime.primaryTextColor(this.darkMode) :
            ThemeRuntime.subTextColor(this.darkMode))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .width('100%')
        Row({ space: 2 }) {
          Text('查看详情')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.accentColor(this.darkMode))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(11)
            .fontColor([ThemeRuntime.accentColor(this.darkMode)])
        }
        .height(26)
        .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
        .borderRadius(13)
        .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
        .margin({ top: AppSpacing.XXS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: 520 })
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.LG, right: AppSpacing.SM, top: AppSpacing.MD, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .shadow({ radius: 24, color: '#33000000', offsetY: 4 })
    .margin({ bottom: this.navBarHeight + AppSpacing.LG })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 40 }))
      .animation({ duration: 200, curve: Curve.FastOutSlowIn }))
    .onClick(() => {
      BookMarkService.openDetail(item);
    })
  }

  @Builder
  cover(item: BookMark, coverWidth: number, coverHeight: number, decodeWidth: number, decodeHeight: number) {
    Stack() {
      BookCover({
        bookUrl: item.bookUrl,
        origin: item.origin,
        coverUrl: item.coverUrl,
        name: item.bookName,
        author: item.author,
        useBookshelfCover: true,
        placeholderColor: ThemeRuntime.accentColor(this.darkMode),
        cornerRadius: 4,
        decodeWidth: decodeWidth,
        decodeHeight: decodeHeight
      })
    }
    .width(coverWidth)
    .height(coverHeight)
    .borderRadius(4)
    .clip(true)
  }

  @Builder
  ratingLine(item: BookMark, starSize: number) {
    if (item.rating > 0) {
      BookMarkStars({
        rating: item.rating,
        starSize: starSize,
        darkMode: this.darkMode,
        emptyColor: ThemeRuntime.softFillColor(this.darkMode)
      })
    } else {
      Text('未打分')
        .fontSize(AppFontSize.MICRO + 1)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
    }
  }

  /** 长按一本书的菜单。 */
  @Builder
  itemMenu(item: BookMark) {
    Column() {
      PopupMenuAction($r('sys.symbol.doc_text'), '查看详情', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.menuKey = '';
        ContextMenu.close();
        BookMarkService.openDetail(item);
      })
      PopupMenuAction($r('sys.symbol.trash'), '删除标记', ThemeRuntime.dangerColor(this.darkMode), () => {
        this.menuKey = '';
        ContextMenu.close();
        this.confirmDelete(item);
      })
    }
    .width(170)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  emptyState(title: string, description: string) {
    Column({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(40)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
      Text(description)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 80, left: AppSpacing.XL, right: AppSpacing.XL })
  }

  /** 管理标签：每行一个标签和用到它的标记本数，可改名（与已有标签同名时合并）或删除，书架上的同名标签一起改。 */
  @Builder
  categorySheet() {
    Column() {
      Text('管理标签')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .width('100%')
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL, bottom: AppSpacing.MD })
      Text('改名和删除会同时作用到书架上的同名标签；改成已有的标签名会把两个标签合并。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .width('100%')
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, bottom: AppSpacing.MD })
      if (this.categories.length === 0) {
        Text('没有标签了')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .padding(AppSpacing.XXXL)
      }
      List() {
        ForEach(this.categories, (name: string) => {
          ListItem() {
            this.categoryRow(name)
          }
        }, (name: string) => name)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: ThemeRuntime.hairlineColor(this.darkMode), startMargin: AppSpacing.XXL,
        endMargin: AppSpacing.XXL })
      .contentEndOffset((AppStorage.get<number>('navBarHeight') || 0) + AppSpacing.XL)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  categoryRow(name: string) {
    Row({ space: AppSpacing.MD }) {
      if (this.renamingCategory === name) {
        TextInput({ text: this.renameInput, placeholder: name })
          .layoutWeight(1)
          .height(40)
          .maxLength(BookMarkRules.MAX_CATEGORY_LENGTH)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
          .caretColor(ThemeRuntime.accentColor(this.darkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .defaultFocus(true)
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.renameInput = value;
          })
          .onSubmit(() => this.commitRename(name))
        Text('保存')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.accentColor(this.darkMode))
          .padding(AppSpacing.SM)
          .onClick(() => this.commitRename(name))
      } else {
        Column({ space: 2 }) {
          Text(name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.categoryCount(name)} 本`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Stack() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
        }
        .width(40)
        .height(40)
        .accessibilityText(`重命名${name}`)
        .onClick(() => {
          this.renameInput = name;
          this.renamingCategory = name;
        })
        Stack() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([ThemeRuntime.dangerColor(this.darkMode)])
        }
        .width(40)
        .height(40)
        .accessibilityText(`删除${name}`)
        .onClick(() => this.confirmDeleteCategory(name))
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: AppSpacing.XXL, right: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
  }

  categorySheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      detents: ['60%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.showCategorySheet = false;
        this.renamingCategory = '';
      }
    }, this.darkMode, ThemeRuntime.accentColor(this.darkMode));
  }

  async commitRename(oldName: string): Promise<void> {
    const target = BookMarkRules.normalizeCategory(this.renameInput);
    this.renamingCategory = '';
    if (!target || target === oldName) return;
    try {
      await appDb.init(getContext(this));
      await BookMarkService.renameCategory(oldName, target);
      if (this.categoryFilter === oldName) this.categoryFilter = target;
      await this.load();
      HdsFeedback.showToast('标签已重命名');
    } catch (error) {
      console.error('重命名标签失败:', error);
      HdsFeedback.showToast('重命名失败，请重试');
    }
  }

  confirmDeleteCategory(name: string): void {
    this.getUIContext().showAlertDialog({
      title: `删除标签“${name}”`,
      message: `${this.categoryCount(name)} 本标记的书和书架上的书都会去掉这个标签，评分和短评不受影响。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeRuntime.dangerColor(this.darkMode),
        action: (): void => {
          this.deleteCategory(name);
        }
      }
    });
  }

  async deleteCategory(name: string): Promise<void> {
    try {
      await appDb.init(getContext(this));
      await BookMarkService.deleteCategory(name);
      if (this.categoryFilter === name) this.categoryFilter = '';
      await this.load();
      HdsFeedback.showToast('标签已删除');
    } catch (error) {
      console.error('删除标签失败:', error);
      HdsFeedback.showToast('删除失败，请重试');
    }
  }

  confirmDelete(item: BookMark): void {
    this.getUIContext().showAlertDialog({
      title: '删除标记',
      message: `《${item.bookName}》的评分、状态、标签和短评都会删除，书架上的标签保留。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeRuntime.dangerColor(this.darkMode),
        action: (): void => {
          this.deleteMark(item);
        }
      }
    });
  }

  async deleteMark(item: BookMark): Promise<void> {
    try {
      await appDb.init(getContext(this));
      await BookMarkService.remove(item.workKey);
      this.items = this.items.filter((entry: BookMark): boolean => entry.workKey !== item.workKey);
      this.categories = BookMarkRules.collectCategories(this.items);
      HdsFeedback.showToast('已删除标记');
    } catch (error) {
      console.error('删除书籍标记失败:', error);
      HdsFeedback.showToast('删除失败，请重试');
    }
  }

  /** withStatus 为 false 时不带“在读 · ”这类状态前缀（卡片列表另有状态胶囊）。 */
  dateText(item: BookMark, withStatus: boolean = true): string {
    const finished = item.status === BookMarkStatus.READ && item.finishTime > 0;
    const date = new Date(finished ? item.finishTime : item.updateTime);
    const label = `${date.getMonth() + 1}月${date.getDate()}日`;
    const day = date.getFullYear() === new Date().getFullYear() ? label : `${date.getFullYear()}年${label}`;
    if (finished) return `${day}读完`;
    return withStatus && item.status !== BookMarkStatus.NONE ? `${BookMarkStatus.label(item.status)} · ${day}` : day;
  }
}
