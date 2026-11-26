import { BookCover } from './book/BookCover';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VirtualListScrollbar } from '../utils/VirtualListScrollbar';
import { ImmersiveBackButton } from './ImmersiveBackButton';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

/**
 * The catalog list feeds on chapter *titles*, not chapter records. Declaring the
 * narrowed return type here makes a mismatched data source a compile error
 * instead of a silently blank list — `LazyForEach` cannot check it for us
 * because `IDataSource.getData()` is typed `any`.
 */
export interface CatalogTitleSource extends IDataSource {
  getData(index: number): string;
}

/** The one title data source every caller of this sheet should use. */
export class CatalogTitleDataSource implements CatalogTitleSource {
  private titles: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.titles.length; }

  getData(index: number): string { return this.titles[index] || ''; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(titles: string[]): void {
    this.titles = titles.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/** 搜索结果的数据源：每一项是命中章节在目录里的显示序号。 */
class CatalogMatchDataSource implements IDataSource {
  private indexes: number[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.indexes.length; }

  getData(index: number): number { return this.indexes[index] ?? 0; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(indexes: number[]): void {
    this.indexes = indexes;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

const CATALOG_SCROLLBAR_MIN_SCROLL_INTERVAL_MS = 90;
const CATALOG_SEARCH_INPUT_KEY = 'tts_catalog_search_input';
const CATALOG_COVER_WIDTH = 52;
const CATALOG_COVER_HEIGHT = 68;

/**
 * The single catalog sheet behind every TTS / audio-book entry point: the reader's
 * floating player, the standalone audio-book page and the shelf. It deliberately
 * mirrors the reader's own table of contents
 * (ReadBook.readerFloatingTocPanel / tocPanelSummary / tocChapterList):
 *   - shown by the host as a system half-modal sheet (immersive material on API 26+)
 *   - cover + book name (+ optional subtitle) header with a circular close button
 *   - summary row carrying "共 N 章", the order toggle, title search and optional actions
 *   - list rows with a `•` / `·` leader, hairline separators and a cache chip
 *
 * The caller keeps the data source in *display order*, so every index this
 * component receives and emits is a display index; the caller converts it back
 * to a canonical chapter index.
 */
@Component
export struct TtsCatalogSheet {
  @Prop darkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop primaryTextColor: string = '#18191C';
  @Prop subTextColor: string = '#8A8A8E';
  @Prop controlIconColor: string = '#FF202124';
  @Prop bookName: string = '';
  @Prop bookInitial: string = '书';
  @Prop bookUrl: string = '';
  @Prop cover: ResourceStr = '';
  @Prop bookSubtitle: string = '';
  @Prop @Watch('onCatalogChanged') count: number = 0;
  @Prop currentDisplayIndex: number = 0;
  @Prop @Watch('onCatalogChanged') reverseOrder: boolean = false;
  @Prop bottomInset: number = 0;
  @Prop viewportHeight: number = 720;
  /** 章节标记文字；有声书标的是音频已下载。 */
  @Prop cachedLabel: string = '已缓存';
  /** 目录摘要行右侧的操作入口，为空时不显示。 */
  @Prop actionLabel: string = '';
  /** 接在"共 N 章"后面的说明，比如已下载多少章。 */
  @Prop noteText: string = '';
  @State listViewportHeight: number = 0;
  @State firstVisibleIndex: number = 0;
  @State visibleItemCount: number = 1;
  @State scrollbarDragging: boolean = false;
  @State dragOffset: number = 0;
  @State searchVisible: boolean = false;
  @State searchQuery: string = '';
  /** 已按关键词筛过：列表只显示命中的章节。 */
  @State searchActive: boolean = false;
  @State searchMatchCount: number = 0;
  private matchSource: CatalogMatchDataSource = new CatalogMatchDataSource();
  private searchScroller: ListScroller = new ListScroller();
  scroller: ListScroller = new ListScroller();
  source: CatalogTitleSource = new CatalogTitleDataSource();
  isCached: (displayIndex: number) => boolean = () => false;
  onToggleOrder: () => void = () => {};
  onSelect: (displayIndex: number) => void = () => {};
  onClose: () => void = () => {};
  onAction: () => void = () => {};
  /** 长按某一章；不需要时保持空实现，长按就没有效果。 */
  onLongPress: ((displayIndex: number) => void) | null = null;
  private pointerAnchor: number = 0;
  private lastScrollbarScrollAt: number = 0;

  build() {
    Column() {
      this.catalogHeader()
      this.catalogSummary()
      this.catalogChapterList()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: this.bottomInset + 12 })
  }

  @Builder
  catalogHeader() {
    Row({ space: AppSpacing.LG }) {
      if (this.bookUrl) {
        BookCover({ bookUrl: this.bookUrl, name: this.bookName, placeholderColor: this.accentColor, cornerRadius: 8 })
          .width(CATALOG_COVER_WIDTH)
          .height(CATALOG_COVER_HEIGHT)
      } else if (this.cover !== '') {
        Image(this.cover)
          .width(CATALOG_COVER_WIDTH)
          .height(CATALOG_COVER_HEIGHT)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.bookInitial || '书')
          .fontSize(AppFontSize.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.onAccentColor())
          .textAlign(TextAlign.Center)
          .width(CATALOG_COVER_WIDTH)
          .height(CATALOG_COVER_HEIGHT)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(this.accentColor)
      }

      Column({ space: AppSpacing.XS }) {
        Text(this.bookName || '目录')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // Optional: entries that cannot reach the author (e.g. the shelf, whose
        // TTS session only publishes book name + cover) render a single line
        // instead of a misleading "未知作者".
        if (this.bookSubtitle) {
          Text(this.bookSubtitle)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      ImmersiveBackButton({
        icon: $r('sys.symbol.xmark'),
        iconOffsetX: 0,
        iconColor: this.controlIconColor,
        darkMode: this.darkMode,
        buttonSize: 40,
        containerWidth: 40,
        containerHeight: 40,
        startInset: 0,
        materialScale: 0.83,
        compactLayout: true,
        accessibilityLabel: '关闭目录',
        onBack: () => this.onClose()
      })
        .alignSelf(ItemAlign.Start)
        .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 目录摘要行：左边章数和排序按钮（有声书再加一行已下载说明），右边操作按钮。
   * 按钮与右上角关闭按钮一样用沉浸光感按钮；听书页和书架胶囊打开的目录共用这一行，布局一致。
   */
  @Builder
  catalogSummary() {
    Column({ space: AppSpacing.MD }) {
    Row({ space: AppSpacing.SM }) {
      Column({ space: AppSpacing.XXS }) {
        Row() {
          Text(this.searchActive ? `找到 ${this.searchMatchCount} 章` : `共 ${this.count} 章`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor)
            .height(34)
            .textAlign(TextAlign.Center)
          ImmersiveBackButton({
            icon: $r('sys.symbol.text_arrow_up_and_down'),
            iconOffsetX: 0,
            iconColor: this.reverseOrder ? this.accentColor : this.controlIconColor,
            darkMode: this.darkMode,
            buttonSize: 34,
            containerWidth: 34,
            containerHeight: 34,
            startInset: 0,
            materialScale: 0.7,
            compactLayout: true,
            accessibilityLabel: this.reverseOrder ? '切换为正序目录' : '切换为倒序目录',
            onBack: () => this.onToggleOrder()
          })
            .margin({ left: AppSpacing.XS })
        }
        .alignItems(VerticalAlign.Center)
        if (this.noteText) {
          Text(this.noteText)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpacing.MD })

      ImmersiveBackButton({
        icon: $r('sys.symbol.magnifyingglass'),
        iconOffsetX: 0,
        iconSize: 18,
        iconColor: this.searchVisible ? this.accentColor : this.controlIconColor,
        darkMode: this.darkMode,
        buttonSize: 36,
        containerWidth: 36,
        containerHeight: 36,
        startInset: 0,
        materialScale: 0.75,
        compactLayout: true,
        accessibilityLabel: this.searchVisible ? '关闭目录搜索' : '搜索目录',
        onBack: () => this.toggleSearch()
      })

      if (this.actionLabel) {
        ImmersiveBackButton({
          icon: $r('sys.symbol.download'),
          iconOffsetX: 0,
          iconSize: 18,
          iconColor: this.controlIconColor,
          darkMode: this.darkMode,
          buttonSize: 36,
          containerWidth: 36,
          containerHeight: 36,
          startInset: 0,
          materialScale: 0.75,
          compactLayout: true,
          accessibilityLabel: this.actionLabel,
          onBack: () => this.onAction()
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    if (this.searchVisible) {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.subTextColor])
        TextInput({ text: this.searchQuery, placeholder: '搜索章节名称' })
          .key(CATALOG_SEARCH_INPUT_KEY)
          .defaultFocus(true)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor)
          .layoutWeight(1)
          .height(38)
          .padding({ left: 0, right: 0 })
          .backgroundColor(Color.Transparent)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .onSubmit(() => this.submitSearch())
        if (this.searchQuery) {
          Text('×')
            .fontSize(AppFontSize.TITLE)
            .fontColor(this.subTextColor)
            .width(32)
            .height(38)
            .textAlign(TextAlign.Center)
            .accessibilityText('清空目录搜索')
            .onClick(() => {
              this.clearSearchResult();
              setTimeout(() => focusControl.requestFocus(CATALOG_SEARCH_INPUT_KEY), 50);
            })
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
      .borderRadius(20)
      .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
    }
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  catalogChapterList() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 半模态的内容在宿主把它打开之后才创建，宿主那时调 scrollToIndex 列表还没挂上，是空操作。
      // 所以定位到当前章由这里负责：首次布局从当前章附近排起，挂上后再居中。
      if (this.searchActive) {
        List({ space: 0, scroller: this.searchScroller }) {
          if (this.searchMatchCount === 0) {
            ListItem() {
              Column({ space: AppSpacing.MD }) {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(28)
                  .fontColor([this.subTextColor])
                Text('未找到匹配章节')
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.subTextColor)
              }
              .width('100%')
              .padding({ top: 44, bottom: 44 })
            }
          }
          LazyForEach(this.matchSource, (displayIndex: number) => {
            ListItem() {
              this.catalogRow(this.source.getData(displayIndex), displayIndex)
            }
          }, (displayIndex: number) => `m_${displayIndex}_${this.isCached(displayIndex) ? 1 : 0}`)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .onScrollIndex((start: number, end: number) => {
          this.firstVisibleIndex = Math.max(0, start);
          this.visibleItemCount = Math.max(1, end - start + 1);
        })
      } else {
      List({ space: 0, scroller: this.scroller, initialIndex: this.initialListIndex() }) {
        LazyForEach(this.source, (title: string, index: number) => {
          ListItem() {
            this.catalogRow(title, index)
          }
          // 标记变了键也跟着变，数据源重载时这一行才会重建；否则目录开着时下载完的章节不显示标记。
        }, (title: string, index: number) => `${index}_${title}_${this.isCached(index) ? 1 : 0}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onAppear(() => this.centerCurrentChapter())
      .onScrollIndex((start: number, end: number) => {
        this.firstVisibleIndex = Math.max(0, start);
        this.visibleItemCount = Math.max(1, end - start + 1);
      })
      }

      this.catalogScrollbar()
    }
    .layoutWeight(1)
    .width('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.listViewportHeight = Number(newValue.height);
    })
  }

  /** 目录的一行；index 始终是完整目录里的显示序号，搜索结果里也一样。 */
  @Builder
  catalogRow(title: string, index: number) {
    Row({ space: AppSpacing.MD }) {
      Text(index === this.currentDisplayIndex ? '•' : '·')
        .fontSize(index === this.currentDisplayIndex ? 22 : 18)
        .fontColor(index === this.currentDisplayIndex ? this.accentColor : this.subTextColor)
        .width(18)
        .textAlign(TextAlign.Center)

      Text(title || `第${this.canonicalIndex(index) + 1}章`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(index === this.currentDisplayIndex ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.catalogTitleColor(index))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.isCached(index)) {
        Text(this.cachedLabel)
          .fontSize(AppFontSize.MICRO)
          .fontColor(ThemeRuntime.successColor(this.darkMode))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
          .backgroundColor(ThemeRuntime.successSurfaceColor(this.darkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(index === this.currentDisplayIndex ?
      this.selectedRowBackgroundColor() : Color.Transparent)
    .border({ width: { bottom: 0.5 },
      color: ThemeRuntime.softFillColor(this.darkMode) })
    .onClick(() => this.onSelect(index))
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      if (this.onLongPress) this.onLongPress(index);
    }))
  }

  @Builder
  catalogScrollbar() {
    if (this.shouldShowScrollbar()) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width(3)
          .height(this.listViewportHeight)
          .borderRadius(2)
          .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
          .margin({ right: AppSpacing.XXS })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.scrollbarDragging ? 6 : 4)
          .height(this.thumbLength())
          .borderRadius(3)
          .backgroundColor(this.subTextColor)
          .margin({ right: AppSpacing.XXS })
          .translate({ y: this.displayedThumbOffset() })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(24)
      .height(this.listViewportHeight)
      .zIndex(10)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Vertical, distance: 1 })
            .onActionStart((event: GestureEvent) => this.beginScrollbarDrag(event))
            .onActionUpdate((event: GestureEvent) => this.updateScrollbarDrag(event))
            .onActionEnd((event: GestureEvent) => this.endScrollbarDrag(event))
            .onActionCancel(() => this.cancelScrollbarDrag()),
          TapGesture().onAction((event: GestureEvent) => this.jumpScrollbarToPointer(event))
        )
      )
    }
  }

  /** 半模态高度：约八成屏高，至少 280。宿主把它传给 bindSheet。 */
  static sheetHeight(viewportHeight: number): number {
    const viewport = viewportHeight > 0 ? viewportHeight : 720;
    const availableHeight = Math.max(1, viewport - 12);
    const minimumHeight = Math.min(280, availableHeight);
    return Math.min(availableHeight, Math.max(minimumHeight, viewport * 0.81));
  }

  /** 首次布局的起始行：当前章上方留两行，居中那一步没生效时当前章也在可见范围内。 */
  private initialListIndex(): number {
    if (this.count <= 0) return 0;
    return Math.max(0, Math.min(this.count - 1, this.currentDisplayIndex - 2));
  }

  private centerCurrentChapter(): void {
    if (this.count <= 0 || this.currentDisplayIndex < 0 || this.currentDisplayIndex >= this.count) return;
    try {
      this.scroller.scrollToIndex(this.currentDisplayIndex, false, ScrollAlign.CENTER);
    } catch (_) {}
  }

  /** 当前列表的行数：搜索时是命中的章数。 */
  private listCount(): number {
    return this.searchActive ? this.searchMatchCount : this.count;
  }

  private activeScroller(): ListScroller {
    return this.searchActive ? this.searchScroller : this.scroller;
  }

  /** 目录换了顺序或章数变了，显示序号跟着变，搜索结果要重算。 */
  onCatalogChanged(): void {
    if (!this.searchActive) return;
    setTimeout(() => {
      if (this.searchActive) this.submitSearch();
    }, 50);
  }

  private toggleSearch(): void {
    if (this.searchVisible) {
      this.searchVisible = false;
      this.clearSearchResult();
      return;
    }
    this.searchVisible = true;
    setTimeout(() => focusControl.requestFocus(CATALOG_SEARCH_INPUT_KEY), 50);
  }

  private submitSearch(): void {
    const keyword = this.searchQuery.trim().toLowerCase();
    if (!keyword) {
      this.clearSearchResult();
      return;
    }
    const total = this.source.totalCount();
    const matches: number[] = [];
    for (let index = 0; index < total; index++) {
      if (this.source.getData(index).toLowerCase().includes(keyword)) matches.push(index);
    }
    this.matchSource.replace(matches);
    this.searchMatchCount = matches.length;
    this.firstVisibleIndex = 0;
    this.visibleItemCount = 1;
    if (this.searchActive) {
      try {
        this.searchScroller.scrollToIndex(0, false, ScrollAlign.START);
      } catch (_) {}
    }
    this.searchActive = true;
  }

  /** 退出筛选；完整目录的列表会重新创建，并回到当前章。 */
  private clearSearchResult(): void {
    this.searchQuery = '';
    if (!this.searchActive) return;
    this.searchActive = false;
    this.searchMatchCount = 0;
    this.matchSource.replace([]);
    this.firstVisibleIndex = 0;
    this.visibleItemCount = 1;
  }

  canonicalIndex(displayIndex: number): number {
    return this.reverseOrder ? this.count - 1 - displayIndex : displayIndex;
  }

  catalogTitleColor(displayIndex: number): string {
    if (displayIndex === this.currentDisplayIndex) return this.accentColor;
    if (this.isCached(displayIndex)) return this.darkMode ? '#DDEFE5' : '#244B35';
    return this.darkMode ? '#B8BDC7' : '#333333';
  }

  selectedRowBackgroundColor(): string {
    return this.accentTint('11');
  }

  private accentTint(alpha: string): string {
    const color = this.accentColor;
    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return `#${alpha}${color.substring(1)}`;
    }
    return this.darkMode ? '#112A6FCC' : '#11007DFF';
  }

  shouldShowScrollbar(): boolean {
    return this.listViewportHeight > 0 && this.listCount() > this.visibleItemCount;
  }

  thumbLength(): number {
    return VirtualListScrollbar.thumbLength(this.listViewportHeight, this.listCount(), this.visibleItemCount);
  }

  thumbOffset(): number {
    return VirtualListScrollbar.thumbOffset(this.listViewportHeight, this.thumbLength(),
      this.listCount(), this.firstVisibleIndex, this.visibleItemCount);
  }

  displayedThumbOffset(): number {
    return this.scrollbarDragging ? this.dragOffset : this.thumbOffset();
  }

  scrollbarPointerY(event: GestureEvent): number {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? finger.localY : 0;
  }

  beginScrollbarDrag(event: GestureEvent): void {
    const thumbLength = this.thumbLength();
    const currentOffset = this.thumbOffset();
    const pointerY = this.scrollbarPointerY(event);
    this.scrollbarDragging = true;
    this.dragOffset = currentOffset;
    if (pointerY >= currentOffset && pointerY <= currentOffset + thumbLength) {
      this.pointerAnchor = pointerY - currentOffset;
    } else {
      this.pointerAnchor = thumbLength / 2;
      this.scrollToPointer(pointerY);
    }
  }

  updateScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    this.scrollToPointer(this.scrollbarPointerY(event));
  }

  endScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    // 先结束拖动再定位，松手这一下不受拖动节流影响。
    this.scrollbarDragging = false;
    this.scrollToPointer(this.scrollbarPointerY(event));
  }

  cancelScrollbarDrag(): void {
    this.scrollbarDragging = false;
  }

  jumpScrollbarToPointer(event: GestureEvent): void {
    this.pointerAnchor = this.thumbLength() / 2;
    this.scrollToPointer(this.scrollbarPointerY(event));
  }

  scrollToPointer(pointerY: number): void {
    const thumbLength = this.thumbLength();
    const offset = VirtualListScrollbar.clampThumbOffset(this.listViewportHeight, thumbLength,
      pointerY - this.pointerAnchor);
    this.dragOffset = offset;
    // 滑块到底时最后一行贴底，否则按首行定位。
    const atEnd = VirtualListScrollbar.reachesEnd(this.listViewportHeight, thumbLength, offset);
    const targetIndex = atEnd ? this.listCount() - 1 : VirtualListScrollbar.firstVisibleIndex(this.listViewportHeight,
      thumbLength, this.listCount(), this.visibleItemCount, offset);
    this.firstVisibleIndex = targetIndex;
    const now = Date.now();
    if (this.scrollbarDragging && now - this.lastScrollbarScrollAt < CATALOG_SCROLLBAR_MIN_SCROLL_INTERVAL_MS) {
      return;
    }
    this.lastScrollbarScrollAt = now;
    try {
      this.activeScroller().scrollToIndex(targetIndex, false, atEnd ? ScrollAlign.END : ScrollAlign.START);
    } catch (_) {}
  }
}
