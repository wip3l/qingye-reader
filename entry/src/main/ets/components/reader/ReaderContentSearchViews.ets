import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ReaderContentSearchHit } from '../../core/reader/ReaderContentSearch';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** 结果列表的一行：章节标题行，或一处命中。 */
export class ReaderContentSearchItem {
  static readonly HEADER: number = 0;
  static readonly HIT: number = 1;
  kind: number = ReaderContentSearchItem.HIT;
  hit: ReaderContentSearchHit | null = null;
  chapterIndex: number = 0;
  chapterTitle: string = '';
  /** 标题行：本章已列出的处数。 */
  count: number = 0;
  key: string = '';
}

/**
 * 查找结果列表的数据：按章分组，每章前面一行章节标题；只追加或整体清空，结果多时也只建可见的几行。
 * 宿主按“整次查找里的第几处”取结果（hitAt），列表按行号滚动（listIndexOf）。
 */
export class ReaderContentSearchDataSource implements IDataSource {
  private items: ReaderContentSearchItem[] = [];
  private hits: ReaderContentSearchHit[] = [];
  private hitRows: number[] = [];
  private lastHeaderRow: number = -1;
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ReaderContentSearchItem {
    return this.items[index] || new ReaderContentSearchItem();
  }

  hitAt(index: number): ReaderContentSearchHit | null {
    return index >= 0 && index < this.hits.length ? this.hits[index] : null;
  }

  listIndexOf(hitIndex: number): number {
    return hitIndex >= 0 && hitIndex < this.hitRows.length ? this.hitRows[hitIndex] : -1;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  append(hits: ReaderContentSearchHit[]): void {
    if (hits.length === 0) return;
    const start = this.items.length;
    const operations: DataOperation[] = [];
    let index = 0;
    while (index < hits.length) {
      const chapterIndex = hits[index].chapterIndex;
      let end = index;
      while (end < hits.length && hits[end].chapterIndex === chapterIndex) end++;
      const header = this.lastHeaderRow >= 0 ? this.items[this.lastHeaderRow] : null;
      if (header && header.chapterIndex === chapterIndex) {
        // 同一章分两批送来时，只把已有标题行的处数加上。
        header.count += end - index;
        header.key = `header_${chapterIndex}_${header.count}`;
        operations.push({ type: DataOperationType.CHANGE, index: this.lastHeaderRow, key: header.key });
      } else {
        const item = new ReaderContentSearchItem();
        item.kind = ReaderContentSearchItem.HEADER;
        item.chapterIndex = chapterIndex;
        item.chapterTitle = hits[index].chapterTitle || `第 ${chapterIndex + 1} 章`;
        item.count = end - index;
        item.key = `header_${chapterIndex}_${item.count}`;
        this.items.push(item);
        this.lastHeaderRow = this.items.length - 1;
      }
      for (let cursor = index; cursor < end; cursor++) {
        const item = new ReaderContentSearchItem();
        item.hit = hits[cursor];
        item.chapterIndex = chapterIndex;
        item.key = hits[cursor].key;
        this.items.push(item);
        this.hits.push(hits[cursor]);
        this.hitRows.push(this.items.length - 1);
      }
      index = end;
    }
    operations.push({ type: DataOperationType.ADD, index: start, count: this.items.length - start });
    for (const listener of this.listeners) listener.onDatasetChange(operations);
  }

  clear(): void {
    if (this.items.length === 0) return;
    this.items = [];
    this.hits = [];
    this.hitRows = [];
    this.lastHeaderRow = -1;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/**
 * 正文查找半模态：半模态自身承接系统沉浸光感，内容不铺第二层底板，配色跟阅读主题。
 * 与其它沉浸光感组件一样只用中性色，唯一的颜色是关键字底色，与正文里的命中高亮一致。
 */
@Component
export struct ReaderContentSearchSheet {
  @Prop query: string = '';
  @Prop status: string = '';
  @Prop running: boolean = false;
  @Prop scanned: number = 0;
  @Prop total: number = 0;
  @Prop resultCount: number = 0;
  @Prop currentIndex: number = -1;
  @Prop canReturn: boolean = false;
  /** 已完成一次查找且一处都没找到。 */
  @Prop empty: boolean = false;
  @Prop emptyTitle: string = '没有找到这段文字';
  @Prop emptyHint: string = '';
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#535963';
  @Prop controlColor: string = '#0D000000';
  @Prop dividerColor: string = '#14000000';
  @Prop highlightColor: string = '#73FFC53D';
  source: ReaderContentSearchDataSource = new ReaderContentSearchDataSource();
  onQueryChange: (value: string) => void = (_value: string): void => {};
  onSearch: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onReturn: () => void = (): void => {};
  onSelect: (hit: ReaderContentSearchHit) => void = (_hit: ReaderContentSearchHit): void => {};
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const row = this.source.listIndexOf(this.currentIndex);
    if (row > 0) {
      setTimeout((): void => this.scroller.scrollToIndex(row, false, ScrollAlign.CENTER), 0);
    }
  }

  canSubmit(): boolean {
    return this.running || this.query.trim().length > 0;
  }

  @Builder
  headerRow(item: ReaderContentSearchItem) {
    Row({ space: AppSpacing.SM }) {
      Text(item.chapterTitle)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${item.count} 处`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: AppSpacing.LG, bottom: AppSpacing.XS })
  }

  @Builder
  hitRow(hit: ReaderContentSearchHit) {
    Text() {
      Span(hit.before ? `…${hit.before}` : '')
      Span(hit.text).textBackgroundStyle({ color: this.highlightColor, radius: 3 })
      Span(hit.after ? `${hit.after}…` : '')
    }
    .fontSize(AppFontSize.BODY)
    .fontColor(this.textColor)
    .lineHeight(22)
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .width('100%')
    .padding({ left: 24, right: 24, top: 10, bottom: 10 })
    .backgroundColor(hit.index === this.currentIndex ? this.controlColor : Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.dividerColor })
    .accessibilityText(`${hit.chapterTitle}，${hit.before}${hit.text}${hit.after}`)
    .onClick(() => this.onSelect(hit))
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([this.subTextColor])
          TextInput({ text: this.query, placeholder: '输入要查找的文字' })
            .layoutWeight(1)
            .height(40)
            .padding(0)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
            .placeholderColor(this.subTextColor)
            .caretColor(this.textColor)
            .backgroundColor(Color.Transparent)
            .maxLength(64)
            .enterKeyType(EnterKeyType.Search)
            .defaultFocus(this.resultCount === 0 && !this.running)
            .onChange((value: string) => this.onQueryChange(value))
            .onSubmit(() => this.onSearch())
          if (this.query.length > 0 && !this.running) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([this.subTextColor])
            }
            .width(28).height(28).backgroundColor(Color.Transparent)
            .accessibilityText('清空关键字')
            .onClick(() => this.onQueryChange(''))
          }
        }
        .layoutWeight(1).height(40).borderRadius(20).padding({ left: 12, right: 6 })
        .backgroundColor(this.controlColor)
        Text(this.running ? '停止' : '查找')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .opacity(this.canSubmit() ? 1 : 0.4)
          .height(40)
          .padding({ left: 4, right: 4 })
          .accessibilityText(this.running ? '停止查找' : '开始查找')
          .onClick(() => {
            if (this.running) this.onStop();
            else if (this.canSubmit()) this.onSearch();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      if (this.running) {
        Progress({ value: this.scanned, total: Math.max(1, this.total), type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.subTextColor)
          .backgroundColor(this.dividerColor)
          .style({ strokeWidth: 2 })
          .padding({ left: 24, right: 24 })
          .margin({ top: 10 })
      }

      Row({ space: AppSpacing.SM }) {
        Text(this.status)
          .fontSize(12)
          .fontColor(this.subTextColor)
          .maxLines(2)
          .layoutWeight(1)
        if (this.canReturn) {
          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left')).fontSize(13).fontColor([this.textColor])
            Text('回到原位置').fontSize(12).fontColor(this.textColor)
          }
          .height(28)
          .accessibilityText('回到查找前的位置')
          .onClick(() => this.onReturn())
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 28 })
      .padding({ left: 24, right: 24, top: this.running ? 4 : 8 })

      if (this.empty) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(32).fontColor([this.subTextColor])
          Text(this.emptyTitle).fontSize(AppFontSize.BODY).fontColor(this.subTextColor)
          Text(this.emptyHint).fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor).textAlign(TextAlign.Center)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ left: 24, right: 24, bottom: 40 })
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.source, (item: ReaderContentSearchItem) => {
            ListItem() {
              if (item.kind === ReaderContentSearchItem.HEADER) {
                this.headerRow(item)
              } else if (item.hit) {
                this.hitRow(item.hit)
              }
            }
          }, (item: ReaderContentSearchItem) => item.key)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(6)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
        .margin({ top: AppSpacing.XS })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4, bottom: 16 })
  }
}

/**
 * 跳到查找结果后留在页底的切换胶囊：一段上一处 / 当前第几处 / 下一处，旁边单独一个结束按钮；
 * 点中间重新打开结果列表。与朗读、自动滚动胶囊同一种沉浸光感面板，只用中性色。
 */
@Component
export struct ReaderContentSearchCapsule {
  @Prop index: number = 0;
  @Prop count: number = 0;
  @Prop running: boolean = false;
  @Prop chapterTitle: string = '';
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#535963';
  @Prop dividerColor: string = '#14000000';
  @Prop panelColor: string = '#FFFFFF';
  @Prop dark: boolean = false;
  onOpen: () => void = (): void => {};
  onStep: (direction: number) => void = (_direction: number): void => {};
  onClose: () => void = (): void => {};

  static readonly PILL_WIDTH: number = 212;
  static readonly HEIGHT: number = 46;
  static readonly GAP: number = 8;
  static readonly WIDTH: number = ReaderContentSearchCapsule.PILL_WIDTH + ReaderContentSearchCapsule.GAP +
    ReaderContentSearchCapsule.HEIGHT;

  @Builder
  stepButton(icon: Resource, label: string, enabled: boolean, direction: number) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(18).fontColor([this.textColor])
    }
    .width(40).height('100%').padding(0).backgroundColor(Color.Transparent)
    .enabled(enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityText(label)
    .onClick(() => this.onStep(direction))
  }

  @Builder
  separator() {
    Divider().vertical(true).height(20).strokeWidth(0.5).color(this.dividerColor)
  }

  build() {
    Row({ space: ReaderContentSearchCapsule.GAP }) {
      ReaderMaterialPanel({
        panelWidth: ReaderContentSearchCapsule.PILL_WIDTH, panelHeight: ReaderContentSearchCapsule.HEIGHT,
        cornerRadius: ReaderContentSearchCapsule.HEIGHT / 2, darkMode: this.dark, fallbackColor: this.panelColor
      }) {
        Row() {
          this.stepButton($r('sys.symbol.chevron_up'), '上一处', this.index > 0, -1)
          this.separator()
          Column({ space: 1 }) {
            Text(`${this.index + 1} / ${this.count}${this.running ? '+' : ''}`)
              .fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium).fontColor(this.textColor).maxLines(1)
            Text(this.chapterTitle)
              .fontSize(11).fontColor(this.subTextColor).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1).height('100%').padding({ left: AppSpacing.SM, right: AppSpacing.SM })
          .justifyContent(FlexAlign.Center)
          .accessibilityText(`查找结果第 ${this.index + 1} 处，共 ${this.count} 处，点击查看全部结果`)
          .onClick(() => this.onOpen())
          this.separator()
          this.stepButton($r('sys.symbol.chevron_down'), '下一处', this.index < this.count - 1, 1)
        }
        .width('100%').height('100%').padding({ left: 2, right: 2 })
      }
      ReaderMaterialPanel({
        panelWidth: ReaderContentSearchCapsule.HEIGHT, panelHeight: ReaderContentSearchCapsule.HEIGHT,
        cornerRadius: ReaderContentSearchCapsule.HEIGHT / 2, darkMode: this.dark, fallbackColor: this.panelColor
      }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([this.subTextColor])
        }
        .width('100%').height('100%').backgroundColor(Color.Transparent)
        .accessibilityText('结束查找')
        .onClick(() => this.onClose())
      }
    }
  }
}
