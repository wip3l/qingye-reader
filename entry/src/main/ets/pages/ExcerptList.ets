import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ReaderAnnotationShare } from '../utils/ReaderAnnotationShare';
import { appDb } from '../model/data/AppDatabase';
import { BookAnnotation } from '../model/reader/BookAnnotation';
import { Book } from '@legado/sourceengine';
import { BookCover } from '../components/book/BookCover';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';

/** 摘录里出现过的一本书，书名筛选条用。 */
class ExcerptBookChip {
  bookUrl: string = '';
  bookName: string = '';
  count: number = 0;
}

/**
 * 我的摘录：阅读时点“摘录”或在划线面板里点星标收进来的句子和段落，跨书按最近收藏排列。
 * 摘录就是带 excerpt 标记的划线，删书时留着；书不在书架上时只能复制、分享，不能回原文。
 */
@Entry
@Component
struct ExcerptListPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State items: BookAnnotation[] = [];
  @State books: ExcerptBookChip[] = [];
  @State bookFilter: string = '';
  @State keyword: string = '';
  @State loaded: boolean = false;
  /** 打开“更多”菜单的那条摘录 id，0 是都没开。 */
  @State menuId: number = 0;
  @State shelfUrls: string[] = [];
  /** 正在消散的摘录 id（字符串），见 ListDissolve。 */
  @State dissolvingKeys: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  /** 书架上的书，封面按书架的规则取（自定义封面、书源封面、占位）。 */
  private shelfBooks: Map<string, Book> = new Map<string, Book>();
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && typeof params['bookUrl'] === 'string') this.bookFilter = params['bookUrl'];
  }

  onPageShow(): void {
    syncSystemBars(getContext(this), this.darkMode, ThemeRuntime.pageColor(this.darkMode));
    // 从阅读页回来时可能改过笔记、移出过摘录，每次显示都重读。
    this.load();
  }

  async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    try {
      await appDb.init(getContext(this));
      const items = await appDb.getExcerptAnnotations();
      const books = await appDb.getAllBooks();
      if (generation !== this.loadGeneration) return;
      this.shelfBooks = new Map<string, Book>(books.map((book: Book): [string, Book] => [book.bookUrl, book]));
      this.shelfUrls = books.map((book: Book): string => book.bookUrl);
      this.applyItems(items);
    } catch (error) {
      console.warn('读取摘录失败:', error);
    } finally {
      if (generation === this.loadGeneration) this.loaded = true;
    }
  }

  applyItems(items: BookAnnotation[]): void {
    this.items = items;
    const chips: ExcerptBookChip[] = [];
    const index = new Map<string, ExcerptBookChip>();
    for (const item of items) {
      let chip = index.get(item.bookUrl);
      if (!chip) {
        chip = new ExcerptBookChip();
        chip.bookUrl = item.bookUrl;
        chip.bookName = item.bookName || '未知书籍';
        index.set(item.bookUrl, chip);
        chips.push(chip);
      }
      chip.count++;
    }
    this.books = chips;
    if (this.bookFilter && !index.has(this.bookFilter)) this.bookFilter = '';
  }

  visibleItems(): BookAnnotation[] {
    const keyword = this.keyword.trim().toLowerCase();
    return this.items.filter((item: BookAnnotation): boolean => {
      if (this.bookFilter && item.bookUrl !== this.bookFilter) return false;
      if (!keyword) return true;
      return item.quote.toLowerCase().includes(keyword) || item.note.toLowerCase().includes(keyword) ||
        item.bookName.toLowerCase().includes(keyword) || item.chapterName.toLowerCase().includes(keyword);
    });
  }

  onShelf(item: BookAnnotation): boolean {
    return this.shelfUrls.indexOf(item.bookUrl) >= 0;
  }

  build() {
    Stack() {
      PageScaffold({
        title: '我的摘录',
        scrollable: false,
        collapsible: false,
        content: () => {
          this.pageContent()
        }
      })

      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('excerpt_list_root')
    .width('100%')
    .height('100%')
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.MD }) {
      if (this.items.length > 0) {
        this.searchField()
        if (this.books.length > 1) {
          this.bookChips()
        }
      }
      if (this.loaded && this.items.length === 0) {
        this.emptyState('还没有摘录', '阅读时选中文字点“摘录”，或在划线面板里点星标，喜欢的句子和段落会收在这里。')
      } else if (this.loaded && this.visibleItems().length === 0) {
        this.emptyState('没有找到', '换个关键词或书名试试。')
      } else if (this.loaded) {
        List({ space: AppSpacing.MD }) {
          ForEach(this.visibleItems(), (item: BookAnnotation) => {
            ListItem() {
              this.excerptCard(item)
            }
          }, (item: BookAnnotation) => `${item.id}|${item.updateTime}|${item.color}`)
          ListItem() {
            Text(`${this.visibleItems().length} 条摘录`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: AppSpacing.SM, bottom: AppSpacing.XXXL })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .contentEndOffset(AppStorage.get<number>('navBarHeight') || 0)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
  }

  @Builder
  searchField() {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
      TextInput({ text: this.keyword, placeholder: '搜索摘录、想法或书名' })
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
  bookChips() {
    List({ space: AppSpacing.SM }) {
      ListItem() {
        this.chip('', `全部 ${this.items.length}`)
      }
      ForEach(this.books, (book: ExcerptBookChip) => {
        ListItem() {
          this.chip(book.bookUrl, `${book.bookName} ${book.count}`)
        }
      }, (book: ExcerptBookChip) => `${book.bookUrl}|${book.count}`)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(32)
  }

  @Builder
  chip(bookUrl: string, label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.bookFilter === bookUrl ? Color.White : ThemeRuntime.primaryTextColor(this.darkMode))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 180 })
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .backgroundColor(this.bookFilter === bookUrl ? ThemeRuntime.accentColor(this.darkMode) :
        ThemeRuntime.cardColor(this.darkMode))
      .onClick(() => {
        this.bookFilter = bookUrl;
      })
  }

  /**
   * 一条摘录：原文左边是划线颜色的竖线，有想法另起一块，底部一行小封面 + 书名、章节和时间。
   * 竖线用左边框画：在 List 里给竖条写 100% 高度会撑满整个列表。
   */
  @Builder
  excerptCard(item: BookAnnotation) {
    Column({ space: AppSpacing.MD }) {
      Text(item.quote)
        .fontSize(AppFontSize.BODY_LARGE)
        .lineHeight(26)
        .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .maxLines(10)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .wordBreak(WordBreak.BREAK_WORD)
        .width('100%')
        .padding({ left: AppSpacing.LG })
        .border({ width: { left: 3 }, color: item.color })

      if (item.note.trim()) {
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(14)
            .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
            .margin({ top: 2 })
          Text(item.note.trim())
            .fontSize(AppFontSize.BODY)
            .lineHeight(21)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_WORD)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding(AppSpacing.MD)
        .borderRadius(10)
        .backgroundColor(this.darkMode ? '#0DFFFFFF' : '#08000000')
      }

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.darkMode))

      Row({ space: AppSpacing.MD }) {
        this.bookCover(item)
        Column({ space: 2 }) {
          Text(item.bookName || '未知书籍')
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.metaText(item))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Stack() {
          SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
            .fontSize(18)
            .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
        }
        .width(36)
        .height(36)
        .accessibilityText('更多操作')
        .onClick(() => {
          this.menuId = this.menuId === item.id ? 0 : item.id;
        })
        .bindPopup(this.menuId === item.id, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.itemMenu(item);
          }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
            if (this.menuId === item.id) this.menuId = 0;
          }))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.SM, top: AppSpacing.LG, bottom: AppSpacing.MD })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .opacity(ListDissolve.opacity(this.isDissolving(item)))
    .scale(ListDissolve.scale(this.isDissolving(item)))
    .blur(ListDissolve.blur(this.isDissolving(item)))
    .hitTestBehavior(this.isDissolving(item) ? HitTestMode.None : HitTestMode.Default)
    .id(this.cardElementId(`${item.id}`))
    .onClick(() => this.openInBook(item))
  }

  isDissolving(item: BookAnnotation): boolean {
    return this.dissolvingKeys.length > 0 && this.dissolvingKeys.indexOf(`${item.id}`) >= 0;
  }

  cardElementId(key: string): string {
    return `excerpt_card_${key}`;
  }

  /** 书在书架上就和书架一样取封面；删了的书只剩书名，画占位封面并压暗。 */
  @Builder
  bookCover(item: BookAnnotation) {
    Stack() {
      if (this.shelfBooks.has(item.bookUrl)) {
        BookCover({
          bookUrl: item.bookUrl,
          origin: this.shelfBooks.get(item.bookUrl)?.origin || '',
          coverUrl: this.shelfBooks.get(item.bookUrl)?.coverUrl || '',
          customCoverUrl: this.shelfBooks.get(item.bookUrl)?.customCoverUrl || '',
          name: item.bookName,
          author: this.shelfBooks.get(item.bookUrl)?.author || '',
          useBookshelfCover: true,
          placeholderColor: ThemeRuntime.accentColor(this.darkMode),
          cornerRadius: 3,
          decodeWidth: 84,
          decodeHeight: 112
        })
      } else {
        BookCover({
          name: item.bookName,
          useBookshelfCover: false,
          placeholderColor: ThemeRuntime.subTextColor(this.darkMode),
          cornerRadius: 3,
          decodeWidth: 84,
          decodeHeight: 112
        })
      }
    }
    .width(28)
    .height(38)
    .borderRadius(3)
    .clip(true)
    .opacity(this.onShelf(item) ? 1 : 0.55)
  }

  @Builder
  itemMenu(item: BookAnnotation) {
    Column() {
      PopupMenuAction($r('sys.symbol.book'), '回到原文', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.menuId = 0;
        this.openInBook(item);
      }, this.onShelf(item))
      PopupMenuAction($r('sys.symbol.rectangle_on_rectangle'), '复制', ThemeRuntime.primaryTextColor(this.darkMode),
        () => {
          this.menuId = 0;
          ReaderAnnotationShare.copy(item);
        })
      PopupMenuAction($r('sys.symbol.share'), '分享图片', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.menuId = 0;
        ReaderAnnotationShare.openPoster(item, this.shelfBooks.get(item.bookUrl) || null);
      })
      PopupMenuAction($r('sys.symbol.star_slash'), '移出摘录', ThemeRuntime.dangerColor(this.darkMode), () => {
        this.menuId = 0;
        this.removeExcerpt(item);
      })
    }
    .width(180)
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

  /** 封面右边第二行：章节（书已删时换成“已不在书架”）· 时间。 */
  metaText(item: BookAnnotation): string {
    const place = this.onShelf(item) ? item.chapterName : '已不在书架';
    const time = ReaderAnnotationShare.timeLabel(item.updateTime || item.createTime);
    return place ? `${place} · ${time}` : time;
  }

  openInBook(item: BookAnnotation): void {
    if (!this.onShelf(item)) {
      HdsFeedback.showToast('这本书已不在书架上，可以复制或分享');
      return;
    }
    router.pushUrl({
      url: 'pages/ReadBook',
      params: { bookUrl: item.bookUrl, annotationId: `${item.id}` }
    }).catch((error: Error) => {
      console.error('从摘录打开书籍失败:', error);
    });
  }

  /** 书还在书架上只去掉摘录标记、划线留着；书已删了就整条删掉，否则没处显示。 */
  async removeExcerpt(item: BookAnnotation): Promise<void> {
    const keys = [`${item.id}`];
    // 从“更多”菜单里点的，等菜单收起再开始消散。
    const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingKeys = [...this.dissolvingKeys, key];
    }, ListDissolve.particles('excerpt_list_root', [ThemeRuntime.accentColor(this.darkMode),
      ThemeRuntime.primaryTextColor(this.darkMode), ThemeRuntime.subTextColor(this.darkMode)],
      (key: string): string => this.cardElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
      (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
    try {
      await appDb.init(getContext(this));
      if (this.onShelf(item)) {
        const updated = item.clone();
        updated.excerpt = false;
        updated.updateTime = Date.now();
        await appDb.updateBookAnnotation(updated);
      } else {
        await appDb.deleteBookAnnotationsById([item.id]);
      }
    } catch (error) {
      console.error('移出摘录失败:', error);
      await fade;
      this.dissolvingKeys = ListDissolve.without(this.dissolvingKeys, keys);
      HdsFeedback.showToast('移出失败，请重试');
      return;
    }
    await fade;
    ListDissolve.commit(this.getUIContext(), () => {
      this.applyItems(this.items.filter((entry: BookAnnotation): boolean => entry.id !== item.id));
    }, () => {
      this.dissolvingKeys = ListDissolve.without(this.dissolvingKeys, keys);
    });
    ReaderAnnotationShare.notifyExcerptsChanged();
    HdsFeedback.showToast('已移出摘录');
  }
}
