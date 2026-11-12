import { Book, BookChapter, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from './ImmersiveBackButton';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { TocVolumeFold } from '../core/reader/TocVolumeFold';

const LOAD_LOADING: string = 'loading';
const LOAD_READY: string = 'ready';
const LOAD_EMPTY: string = 'empty';
const LOAD_ERROR: string = 'error';
const CATALOG_SEARCH_INPUT_KEY: string = 'book_catalog_sheet_search_input';

class CatalogSheetDataSource implements IDataSource {
  private chapters: BookChapter[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.chapters.length;
  }

  getData(index: number): BookChapter {
    return this.chapters[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(chapters: BookChapter[]): void {
    this.chapters = [...chapters];
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/**
 * 书籍详情页的目录面板，作为半模态（bindSheet）的内容使用。
 * 版式与阅读器内的目录面板（ReaderTocPanel）保持一致：圆形操作按钮、章节行的圆点与"已缓存"标记、
 * 当前章节高亮。详情页上方已经露出封面和作者，这里不再重复；也没有书签页签和按序号跳转。
 * 只负责取目录、搜索、排序与展示；点中章节后交给宿主页面落库并跳转，
 * 这样临时阅读书的写入与"加入书架"提示仍走详情页自己的那一套。
 * 宿主页面必须挂着 WebBookFetchRuntimeHost，否则需要 Web 通道的书源取不到目录。
 * 分卷的书点卷名收起或展开这一卷，长按卷名全部收起或全部展开（见 TocVolumeFold）；搜索结果不受收起影响。
 */
@Component
export struct BookCatalogSheet {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  /** 宿主按当前详情拼出的书籍；目录规则可能依赖其中的 variable。 */
  book: Book = new Book();
  onChapterSelected: (chapter: BookChapter) => void = (_chapter: BookChapter): void => {
  };
  onLoaded: (count: number) => void = (_count: number): void => {
  };
  onClose: () => void = (): void => {
  };

  @State loadState: string = LOAD_LOADING;
  @State errorMessage: string = '';
  @State chapters: BookChapter[] = [];
  @State displayedCount: number = 0;
  @State reverseOrder: boolean = false;
  @State currentIndex: number = -1;
  @State keyword: string = '';
  @State searchVisible: boolean = false;
  /** 收起的卷（卷首章在 chapters 里的位置）。 */
  @State collapsedVolumes: number[] = [];
  private volumeStarts: number[] = [];
  /** 当前列表按顺序对应的章节位置。 */
  private displayPositions: number[] = [];
  private alive: boolean = true;
  private dataSource: CatalogSheetDataSource = new CatalogSheetDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    this.loadChapters();
  }

  aboutToDisappear(): void {
    // The source runtime keeps its own request lifecycle. Only guard against a late response
    // writing into a sheet the user already dismissed.
    this.alive = false;
  }

  build() {
    // 材质交给宿主 bindSheet；内容直接随可用空间布局，拖动时不再测量尺寸并回写状态。
    this.panelBody()
  }

  @Builder
  panelBody() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text(this.isEpisodic() ? '选集' : '目录')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.subtitleText())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭目录',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      this.summaryBar()

      if (this.loadState === LOAD_LOADING) {
        this.statusView(this.isEpisodic() ? '正在获取选集…' : '正在获取该规则的目录…', '')
      } else if (this.loadState === LOAD_ERROR) {
        this.statusView(this.errorMessage || '目录加载失败', '重试')
      } else if (this.loadState === LOAD_EMPTY) {
        this.statusView(this.errorMessage || '该规则未解析出章节', '重试')
      } else if (this.displayedCount === 0) {
        this.statusView(this.isEpisodic() ? '未找到匹配选集' : '未找到匹配章节', '')
      } else {
        this.chapterList()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  summaryBar() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text(this.countText())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .height(34)
          .textAlign(TextAlign.Center)
          .margin({ left: AppSpacing.SM })

        if (this.loadState === LOAD_READY) {
          Stack({ alignContent: Alignment.Center }) {
            Column({ space: 0 }) {
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(11)
                .fontColor([this.reverseOrder ? this.accentColor() : this.primaryTextColor()])
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(11)
                .fontColor([this.reverseOrder ? this.accentColor() : this.primaryTextColor()])
            }
            .alignItems(HorizontalAlign.Center)
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(this.reverseOrder ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
            ThemeRuntime.softFillColor(this.appDarkMode))
          .accessibilityText(this.reverseOrder ? '切换为正序目录' : '切换为倒序目录')
          .onClick((): void => {
            this.toggleOrder();
          })
          .margin({ left: AppSpacing.MD })
        }

        Blank()
          .layoutWeight(1)

        if (this.loadState === LOAD_READY) {
          ImmersiveBackButton({
            icon: $r('sys.symbol.magnifyingglass'),
            iconOffsetX: 0,
            iconColor: this.searchVisible ? this.accentColor() : this.primaryTextColor(),
            darkMode: this.appDarkMode,
            buttonSize: 34,
            containerWidth: 34,
            containerHeight: 34,
            startInset: 0,
            materialScale: 0.7,
            compactLayout: true,
            accessibilityLabel: '搜索目录',
            onBack: () => this.toggleSearch()
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.searchVisible) {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([this.subTextColor()])
          TextInput({ text: this.keyword, placeholder: this.isEpisodic() ? '搜索选集名称' : '搜索章节名称' })
            .key(CATALOG_SEARCH_INPUT_KEY)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .layoutWeight(1)
            .height(38)
            .padding({ left: 0, right: 0 })
            .backgroundColor(Color.Transparent)
            .enterKeyType(EnterKeyType.Search)
            .onChange((value: string): void => {
              this.keyword = value;
              this.rebuildDisplayList();
            })
          if (this.keyword) {
            Text('×')
              .fontSize(AppFontSize.TITLE)
              .fontColor(this.subTextColor())
              .width(32)
              .height(38)
              .textAlign(TextAlign.Center)
              .accessibilityText('清空目录搜索')
              .onClick((): void => {
                this.keyword = '';
                this.rebuildDisplayList();
                this.focusSearchInput();
              })
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
        .borderRadius(20)
        .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusView(message: string, action: string) {
    Column({ space: AppSpacing.LG }) {
      if (this.loadState === LOAD_LOADING) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.accentColor())
      }

      Text(message)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .padding({ left: 32, right: 32 })

      if (action) {
        Button(action)
          .height(38)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick((): void => {
            this.loadChapters();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 60 })
  }

  @Builder
  chapterList() {
    List({ scroller: this.scroller }) {
      LazyForEach(this.dataSource, (chapter: BookChapter) => {
        ListItem() {
          Column() {
            if (this.volumeHeadOf(chapter) >= 0) {
              Row({ space: AppSpacing.SM }) {
                Text(BookChapter.volumeTitleOf(this.chapters[this.volumeHeadOf(chapter)]))
                  .fontSize(AppFontSize.BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isVolumeCollapsed(this.volumeHeadOf(chapter)) &&
                    this.volumeContainsCurrent(this.volumeHeadOf(chapter)) ? this.accentColor() : this.subTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (!this.searchActive()) {
                  if (this.isVolumeCollapsed(this.volumeHeadOf(chapter))) {
                    Text(`${this.volumeChapterCount(this.volumeHeadOf(chapter))} ${this.unitText()}`)
                      .fontSize(AppFontSize.CAPTION)
                      .fontColor(this.subTextColor())
                  }
                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(14)
                    .fontColor([this.subTextColor()])
                    .rotate({ angle: this.isVolumeCollapsed(this.volumeHeadOf(chapter)) ? -90 : 0 })
                }
              }
              .width('100%')
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG,
                bottom: this.isVolumeCollapsed(this.volumeHeadOf(chapter)) ? AppSpacing.LG : AppSpacing.SM })
              .border({ width: { bottom: this.isVolumeCollapsed(this.volumeHeadOf(chapter)) ? 0.5 : 0 },
                color: ThemeRuntime.softFillColor(this.appDarkMode) })
              .accessibilityText(this.isVolumeCollapsed(this.volumeHeadOf(chapter)) ? '展开本卷' : '收起本卷')
              .onClick((): void => this.toggleVolume(this.volumeHeadOf(chapter)))
              .gesture(LongPressGesture({ repeat: false })
                .onAction((): void => this.toggleAllVolumes(this.volumeHeadOf(chapter))))
            }
            if (!this.isVolumeCollapsed(this.volumeHeadOf(chapter))) {
            Row({ space: AppSpacing.MD }) {
              Text(chapter.index === this.currentIndex ? '•' : '·')
                .fontSize(chapter.index === this.currentIndex ? 22 : 18)
                .fontColor(chapter.index === this.currentIndex ? this.accentColor() : this.subTextColor())
                .width(18)
                .textAlign(TextAlign.Center)

              Text(chapter.title || `第${chapter.index + 1}${this.unitText()}`)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(chapter.index === this.currentIndex ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(chapter.index === this.currentIndex ? this.accentColor() : this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(ThemeRuntime.successColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.mediumRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .backgroundColor(chapter.index === this.currentIndex ?
              ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
            .border({ width: { bottom: 0.5 }, color: ThemeRuntime.softFillColor(this.appDarkMode) })
            .onClick((): void => {
              this.onChapterSelected(chapter);
            })
            }
          }
        }
        // 卷头行收起/展开时换个键重建这一项，LazyForEach 重载数据时不会漏掉它的变化。
      }, (chapter: BookChapter): string => `${chapter.index}_${chapter.url || chapter.title}` +
        `${this.isVolumeCollapsed(this.volumeHeadOf(chapter)) ? '_c' : ''}_${this.reverseOrder ? 'r' : 'f'}`)
    }
    .width('100%')
    .layoutWeight(1)
    .contentEndOffset(this.navBarHeight + 16)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(6)
  }

  private async loadChapters(): Promise<void> {
    const bookUrl = this.book.bookUrl;
    if (!bookUrl || !this.book.origin) {
      this.loadState = LOAD_ERROR;
      this.errorMessage = '书籍信息不完整，无法加载目录';
      return;
    }
    this.loadState = LOAD_LOADING;
    this.errorMessage = '';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      if (!this.alive) return;

      const cached = await db.getBookChapters(bookUrl);
      if (!this.alive) return;
      if (cached.length > 0) {
        this.applyChapters(cached);
        await this.resolveCurrentIndex(db);
        return;
      }

      const source = await db.getBookSource(this.book.origin);
      if (!this.alive) return;
      if (!source) {
        this.loadState = LOAD_ERROR;
        this.errorMessage = '该规则已被删除或未启用，无法获取目录';
        return;
      }

      BookTypeSupport.applyBookType(this.book, source);
      // maxChapters = 0 keeps the whole catalog; the reader needs a full index anyway.
      const fetched = await new WebBookService().getChapterList(source, this.book, 0, false);
      if (!this.alive) return;
      if (fetched.length === 0) {
        this.loadState = LOAD_EMPTY;
        this.errorMessage = AppStorage.get<string>('bookSourceStageLastError') ||
          '该规则未解析出章节，可能需要在该规则中补充目录规则';
        return;
      }

      for (const chapter of fetched) {
        chapter.bookUrl = bookUrl;
      }
      await db.insertBookChapters(fetched);
      await this.persistChapterCount(db, fetched.length);
      if (!this.alive) return;

      this.applyChapters(fetched);
      await this.resolveCurrentIndex(db);
    } catch (e) {
      if (!this.alive) return;
      this.loadState = LOAD_ERROR;
      this.errorMessage = `目录加载失败：${e}`;
    }
  }

  private applyChapters(list: BookChapter[]): void {
    this.chapters = list;
    const starts: number[] = [];
    for (let i = 0; i < list.length; i++) {
      if (BookChapter.volumeTitleOf(list[i])) starts.push(i);
    }
    this.volumeStarts = starts;
    this.collapsedVolumes = TocVolumeFold.sanitize(starts, TocVolumeFold.recall(this.foldMemoryKey()));
    this.loadState = LOAD_READY;
    this.rebuildDisplayList();
    this.onLoaded(list.length);
  }

  private rebuildDisplayList(): void {
    const keyword = this.keyword.trim();
    let positions: number[] = [];
    if (keyword.length > 0) {
      const total = this.chapters.length;
      for (let i = 0; i < total; i++) {
        const position = this.reverseOrder ? total - 1 - i : i;
        if (this.chapters[position].title.includes(keyword)) positions.push(position);
      }
    } else {
      positions = TocVolumeFold.visiblePositions(this.volumeStarts, this.collapsedVolumes,
        this.chapters.length, this.reverseOrder);
    }
    this.displayPositions = positions;
    this.displayedCount = positions.length;
    this.dataSource.replace(positions.map((position: number): BookChapter => this.chapters[position]));
  }

  private searchActive(): boolean {
    return this.keyword.trim().length > 0;
  }

  private foldMemoryKey(): string {
    const bookUrl = this.book.bookUrl || '';
    return bookUrl ? `${bookUrl}|${this.chapters.length}` : '';
  }

  private positionOf(chapter: BookChapter): number {
    const index = chapter.index;
    if (index >= 0 && index < this.chapters.length && this.chapters[index] === chapter) return index;
    const found = this.chapters.indexOf(chapter);
    return found >= 0 ? found : index;
  }

  /** 这一行上方要画卷头时返回卷首位置，否则 -1。 */
  private volumeHeadOf(chapter: BookChapter): number {
    if (this.volumeStarts.length === 0) return -1;
    return TocVolumeFold.headVolumeAt(this.volumeStarts, this.positionOf(chapter), this.chapters.length,
      this.reverseOrder);
  }

  private isVolumeCollapsed(start: number): boolean {
    return start >= 0 && !this.searchActive() && this.collapsedVolumes.indexOf(start) >= 0;
  }

  private volumeChapterCount(start: number): number {
    return TocVolumeFold.volumeEnd(this.volumeStarts, start, this.chapters.length) - start;
  }

  private volumeContainsCurrent(start: number): boolean {
    return this.currentIndex >= 0 && TocVolumeFold.volumeOf(this.volumeStarts, this.currentIndex) === start;
  }

  private setCollapsedVolumes(collapsed: number[]): void {
    this.collapsedVolumes = collapsed;
    TocVolumeFold.remember(this.foldMemoryKey(), collapsed);
    this.rebuildDisplayList();
  }

  private toggleVolume(start: number): void {
    if (start < 0 || this.searchActive()) return;
    this.setCollapsedVolumes(this.collapsedVolumes.indexOf(start) >= 0 ?
      this.collapsedVolumes.filter((item: number): boolean => item !== start) : this.collapsedVolumes.concat([start]));
  }

  /** 长按卷名：有展开的卷就全部收起，否则全部展开；之后把长按的那一卷移到顶部。 */
  private toggleAllVolumes(start: number): void {
    if (start < 0 || this.searchActive()) return;
    const collapseAll = this.collapsedVolumes.length < this.volumeStarts.length;
    this.setCollapsedVolumes(collapseAll ? this.volumeStarts.slice() : []);
    const head = TocVolumeFold.headPosition(this.volumeStarts, start, this.chapters.length, this.reverseOrder);
    const displayIndex = this.displayPositions.indexOf(head);
    if (displayIndex < 0) return;
    setTimeout((): void => {
      if (!this.alive) return;
      try {
        this.scroller.scrollToIndex(displayIndex, false, ScrollAlign.START);
      } catch (e) {
        console.warn('定位分卷失败:', e);
      }
    }, 0);
  }

  private toggleOrder(): void {
    this.reverseOrder = !this.reverseOrder;
    this.rebuildDisplayList();
    this.scrollToCurrentChapter();
  }

  private toggleSearch(): void {
    this.searchVisible = !this.searchVisible;
    if (this.searchVisible) {
      this.focusSearchInput();
      return;
    }
    if (this.keyword) {
      this.keyword = '';
      this.rebuildDisplayList();
      this.scrollToCurrentChapter();
    }
  }

  private focusSearchInput(): void {
    setTimeout((): void => {
      if (!this.alive || !this.searchVisible) return;
      focusControl.requestFocus(CATALOG_SEARCH_INPUT_KEY);
    }, 60);
  }

  private async resolveCurrentIndex(db: AppDatabase): Promise<void> {
    try {
      const stored = await db.getBook(this.book.bookUrl);
      this.currentIndex = stored ? stored.durChapterIndex : -1;
    } catch (e) {
      this.currentIndex = -1;
    }
    this.scrollToCurrentChapter();
  }

  private scrollToCurrentChapter(): void {
    if (this.currentIndex < 0 || this.keyword.trim().length > 0) return;
    const total = this.chapters.length;
    if (this.currentIndex >= total) return;
    // 打开目录时总能看到当前章节：它所在的卷收起着就先展开。
    const currentVolume = TocVolumeFold.volumeOf(this.volumeStarts, this.currentIndex);
    if (currentVolume >= 0 && this.collapsedVolumes.indexOf(currentVolume) >= 0) {
      this.setCollapsedVolumes(this.collapsedVolumes.filter((item: number): boolean => item !== currentVolume));
    }
    const displayIndex = TocVolumeFold.displayIndexOf(this.displayPositions, this.volumeStarts,
      this.collapsedVolumes, this.currentIndex, total, this.reverseOrder);
    if (displayIndex < 0 || displayIndex >= this.displayPositions.length) return;
    // Let the list finish its first layout pass before scrolling; index scrolling on a
    // just-attached List is otherwise a no-op.
    setTimeout((): void => {
      if (!this.alive) return;
      try {
        this.scroller.scrollToIndex(displayIndex, false, ScrollAlign.CENTER);
      } catch (e) {
        console.warn('定位当前章节失败:', e);
      }
    }, 120);
  }

  private async persistChapterCount(db: AppDatabase, count: number): Promise<void> {
    try {
      const stored = await db.getBook(this.book.bookUrl);
      if (!stored || stored.totalChapterNum === count) return;
      stored.totalChapterNum = count;
      await db.updateBook(stored, true, 'catalog_sheet_count_sync');
    } catch (e) {
      console.warn('回写章节总数失败:', e);
    }
  }

  private isEpisodic(): boolean {
    return BookTypeSupport.isVideo(this.book) || BookTypeSupport.isAudio(this.book);
  }

  private unitText(): string {
    return this.isEpisodic() ? '集' : '章';
  }

  private countText(): string {
    if (this.loadState !== LOAD_READY) return this.isEpisodic() ? '选集' : '章节';
    if (this.keyword.trim().length > 0) return `找到 ${this.displayedCount} ${this.unitText()}`;
    return `共 ${this.chapters.length} ${this.unitText()}`;
  }

  private subtitleText(): string {
    const name = this.book.name || '';
    const source = this.book.originName || '';
    return name && source ? `${name} · ${source}` : (name || source);
  }

  private primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  private buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  private accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }
}
