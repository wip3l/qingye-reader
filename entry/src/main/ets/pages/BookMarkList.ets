import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { appDb } from '../model/data/AppDatabase';
import { BookMark, BookMarkRules, BookMarkStatus } from '../model/book/BookMark';
import { BookMarkService } from '../core/mark/BookMarkService';
import { BookCover } from '../components/book/BookCover';
import { BookMarkStars } from '../components/book/BookMarkStars';

const SORT_RECENT: string = 'recent';
const SORT_RATING: string = 'rating';

/**
 * 我的标记：在书籍详情页打过分、加过标签或写过短评的书，按作品一条。
 * 可按状态、标签筛选，按最近标记或评分排序；点一条回到这本书的详情页。标签的重命名、删除在“管理标签”面板里，
 * 同时改到书架上（标签和书架标签是同一套，见 BookMarkService）。
 */
@Entry
@Component
struct BookMarkListPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('bookMarkRevision') @Watch('onRevisionChanged') bookMarkRevision: number = 0;
  @State items: BookMark[] = [];
  @State categories: string[] = [];
  @State statusFilter: number = 0;
  @State categoryFilter: string = '';
  @State sortMode: string = SORT_RECENT;
  @State keyword: string = '';
  @State loaded: boolean = false;
  /** 打开“更多”菜单的那条标记的作品键。 */
  @State menuKey: string = '';
  @State showCategorySheet: boolean = false;
  /** 管理标签面板里正在改名的标签与输入。 */
  @State renamingCategory: string = '';
  @State renameInput: string = '';
  private visible: boolean = false;
  private loadGeneration: number = 0;

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

  readCount(): number {
    return this.items.filter((item: BookMark): boolean => item.status === BookMarkStatus.READ).length;
  }

  averageText(): string {
    const rated = this.items.filter((item: BookMark): boolean => item.rating > 0);
    if (rated.length === 0) return '–';
    const sum = rated.reduce((total: number, item: BookMark): number => total + item.rating, 0);
    return (sum / rated.length / 2).toFixed(1);
  }

  categoryCount(name: string): number {
    return this.items.filter((item: BookMark): boolean => item.categories.includes(name)).length;
  }

  build() {
    Stack() {
      PageScaffold({
        title: '我的标记',
        scrollable: false,
        collapsible: false,
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
  pageContent() {
    Column({ space: AppSpacing.MD }) {
      if (this.loaded && this.items.length === 0) {
        this.emptyState('还没有标记过书', '在书籍详情页点星星打分，或者加标签、写短评，标记过的书会收在这里。')
      } else if (this.loaded) {
        this.statsRow()
        this.searchField()
        this.statusChips()
        if (this.categories.length > 0) {
          this.categoryChips()
        }
        this.sortRow()
        if (this.visibleItems().length === 0) {
          this.emptyState('没有符合条件的书', '换个筛选条件或关键词试试。')
        } else {
          List({ space: AppSpacing.MD }) {
            ForEach(this.visibleItems(), (item: BookMark) => {
              ListItem() {
                this.markCard(item)
              }
            }, (item: BookMark) => `${item.workKey}|${item.updateTime}|${item.categories.join(',')}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .contentEndOffset((AppStorage.get<number>('navBarHeight') || 0) + AppSpacing.XXXL)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
  }

  @Builder
  statsRow() {
    Row({ space: AppSpacing.XXXL }) {
      this.statCell('已标记', 'all')
      this.statCell('读过', 'read')
      this.statCell('平均星级', 'average')
    }
    .width('100%')
    .padding({ left: AppSpacing.SM, right: AppSpacing.SM, bottom: AppSpacing.XS })
  }

  /** 数值在 builder 里按状态算：按值传入的参数不会随列表变化刷新。 */
  @Builder
  statCell(label: string, kind: string) {
    Column({ space: 2 }) {
      Text(kind === 'all' ? `${this.items.length}` : kind === 'read' ? `${this.readCount()}` : this.averageText())
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
  searchField() {
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

  @Builder
  statusChips() {
    Row({ space: AppSpacing.SM }) {
      ForEach([0, BookMarkStatus.WANT, BookMarkStatus.READING, BookMarkStatus.READ], (value: number) => {
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
  categoryChips() {
    List({ space: AppSpacing.SM }) {
      ListItem() {
        this.categoryChip('', '全部标签')
      }
      ForEach(this.categories, (name: string) => {
        ListItem() {
          this.categoryChip(name, name)
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
  categoryChip(name: string, label: string) {
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
  sortRow() {
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

  @Builder
  markCard(item: BookMark) {
    Row({ space: AppSpacing.LG }) {
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
          decodeWidth: 132,
          decodeHeight: 176
        })
      }
      .width(52)
      .height(70)
      .borderRadius(4)
      .clip(true)

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
          Text(this.dateText(item))
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
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  }

  @Builder
  itemMenu(item: BookMark) {
    Column() {
      PopupMenuAction($r('sys.symbol.doc_text'), '查看详情', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.menuKey = '';
        BookMarkService.openDetail(item);
      })
      PopupMenuAction($r('sys.symbol.trash'), '删除标记', ThemeRuntime.dangerColor(this.darkMode), () => {
        this.menuKey = '';
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

  dateText(item: BookMark): string {
    const finished = item.status === BookMarkStatus.READ && item.finishTime > 0;
    const date = new Date(finished ? item.finishTime : item.updateTime);
    const label = `${date.getMonth() + 1}月${date.getDate()}日`;
    const day = date.getFullYear() === new Date().getFullYear() ? label : `${date.getFullYear()}年${label}`;
    return finished ? `${day}读完` : day;
  }
}
