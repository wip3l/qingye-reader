import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ReaderContentSearchHit } from '../../core/reader/ReaderContentSearch';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** 查找结果列表的数据：只追加或整体清空，结果多时也只建可见的几行。 */
export class ReaderContentSearchDataSource implements IDataSource {
  private hits: ReaderContentSearchHit[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.hits.length;
  }

  getData(index: number): ReaderContentSearchHit {
    return this.hits[index] || new ReaderContentSearchHit();
  }

  hitAt(index: number): ReaderContentSearchHit | null {
    return index >= 0 && index < this.hits.length ? this.hits[index] : null;
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
    const start = this.hits.length;
    this.hits.push(...hits);
    for (const listener of this.listeners) {
      listener.onDatasetChange([{ type: DataOperationType.ADD, index: start, count: hits.length }]);
    }
  }

  clear(): void {
    if (this.hits.length === 0) return;
    this.hits = [];
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/**
 * 正文查找半模态：半模态自身承接系统沉浸光感，内容不铺第二层底板（与自动滚动调速面板同一写法）。
 * 配色跟阅读主题，与阅读页其它半模态一致。
 */
@Component
export struct ReaderContentSearchSheet {
  @Prop query: string = '';
  @Prop status: string = '';
  @Prop running: boolean = false;
  @Prop resultCount: number = 0;
  @Prop currentIndex: number = -1;
  /** 已完成一次查找且一处都没找到。 */
  @Prop empty: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#535963';
  @Prop accentColor: string = '#0A59F7';
  @Prop accentSurfaceColor: string = '#1A0A59F7';
  @Prop controlColor: string = '#0D000000';
  source: ReaderContentSearchDataSource = new ReaderContentSearchDataSource();
  onQueryChange: (value: string) => void = (_value: string): void => {};
  onSearch: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onSelect: (hit: ReaderContentSearchHit) => void = (_hit: ReaderContentSearchHit): void => {};
  onClose: () => void = (): void => {};
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.currentIndex > 0) {
      setTimeout((): void => this.scroller.scrollToIndex(this.currentIndex, false, ScrollAlign.CENTER), 0);
    }
  }

  @Builder
  hitRow(hit: ReaderContentSearchHit) {
    Column({ space: AppSpacing.XS }) {
      if (hit.ordinal === 0) {
        Text(hit.chapterTitle || `第 ${hit.chapterIndex + 1} 章`)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: hit.index === 0 ? 0 : AppSpacing.SM })
      }
      Text() {
        Span(hit.before ? `…${hit.before}` : '')
        Span(hit.text).fontColor(this.accentColor).fontWeight(FontWeight.Medium)
        Span(hit.after ? `${hit.after}…` : '')
      }
      .fontSize(AppFontSize.BODY)
      .fontColor(this.textColor)
      .lineHeight(22)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(16)
    .backgroundColor(hit.index === this.currentIndex ? this.accentSurfaceColor : Color.Transparent)
    .accessibilityText(`${hit.chapterTitle}，${hit.before}${hit.text}${hit.after}`)
    .onClick(() => this.onSelect(hit))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('正文查找').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.textColor)
          Text(this.status).fontSize(12).fontColor(this.subTextColor).maxLines(2)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20).fontColor([this.accentColor])
        }
        .width(44).height(44).backgroundColor(this.controlColor)
        .accessibilityText('收起正文查找').onClick(() => this.onClose())
      }.width('100%')

      Row({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([this.subTextColor])
          TextInput({ text: this.query, placeholder: '输入要查找的文字' })
            .layoutWeight(1)
            .height(44)
            .padding(0)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
            .placeholderColor(this.subTextColor)
            .caretColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .maxLength(64)
            .enterKeyType(EnterKeyType.Search)
            .defaultFocus(this.resultCount === 0 && !this.running)
            .onChange((value: string) => this.onQueryChange(value))
            .onSubmit(() => this.onSearch())
        }
        .layoutWeight(1).height(44).borderRadius(22).padding({ left: 14, right: 14 })
        .backgroundColor(this.controlColor)
        Button({ type: ButtonType.Capsule }) {
          Text(this.running ? '停止' : '查找').fontSize(16)
            .fontColor(this.running ? this.accentColor : ThemeRuntime.onAccentColor(this.accentColor))
        }
        .height(44).padding({ left: 20, right: 20 })
        .backgroundColor(this.running ? this.controlColor : this.accentColor)
        .enabled(this.running || this.query.trim().length > 0)
        .opacity(this.running || this.query.trim().length > 0 ? 1 : 0.5)
        .onClick(() => this.running ? this.onStop() : this.onSearch())
      }.width('100%')

      if (this.empty) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(32).fontColor([this.subTextColor])
          Text('没有找到这段文字').fontSize(AppFontSize.BODY).fontColor(this.subTextColor)
          Text('试试更短的关键字，或检查替换净化规则是否改动了正文').fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor).textAlign(TextAlign.Center)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 40 })
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.source, (hit: ReaderContentSearchHit) => {
            ListItem() {
              this.hitRow(hit)
            }
          }, (hit: ReaderContentSearchHit) => hit.key)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(6)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })
  }
}

/**
 * 跳到查找结果后留在页底的胶囊：上一处、下一处、回到查找前的位置、结束查找；点文字重新打开结果列表。
 * 与朗读、自动滚动胶囊同一种沉浸光感面板。
 */
@Component
export struct ReaderContentSearchCapsule {
  @Prop index: number = 0;
  @Prop count: number = 0;
  @Prop running: boolean = false;
  @Prop chapterTitle: string = '';
  @Prop canReturn: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#535963';
  @Prop accentColor: string = '#0A59F7';
  @Prop panelColor: string = '#FFFFFF';
  @Prop dark: boolean = false;
  @Prop capsuleWidth: number = ReaderContentSearchCapsule.WIDTH;
  onOpen: () => void = (): void => {};
  onStep: (direction: number) => void = (_direction: number): void => {};
  onReturn: () => void = (): void => {};
  onClose: () => void = (): void => {};

  static readonly WIDTH: number = 288;
  static readonly HEIGHT: number = 46;

  @Builder
  iconButton(icon: Resource, label: string, enabled: boolean, color: string, size: number, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(size).fontColor([color])
    }
    .width(32).height(34).padding(0).borderRadius(17).backgroundColor(Color.Transparent)
    .enabled(enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityText(label)
    .onClick(action)
  }

  build() {
    ReaderMaterialPanel({
      panelWidth: this.capsuleWidth, panelHeight: ReaderContentSearchCapsule.HEIGHT,
      cornerRadius: ReaderContentSearchCapsule.HEIGHT / 2, darkMode: this.dark, fallbackColor: this.panelColor
    }) {
      Row({ space: AppSpacing.XS }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: AppSpacing.SM }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(30).height(30).fill(this.accentColor)
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(15).fontColor([ThemeRuntime.onAccentColor(this.accentColor)])
            }
            Column({ space: 1 }) {
              Text(this.count > 0 ? `第 ${this.index + 1} / ${this.count}${this.running ? '+' : ''} 处` : '正文查找')
                .fontSize(AppFontSize.CAPTION).fontWeight(FontWeight.Medium).fontColor(this.textColor)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.chapterTitle)
                .fontSize(9).fontColor(this.subTextColor).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
        }
        .layoutWeight(1).height(34).padding(0)
        .borderRadius(17).backgroundColor(Color.Transparent)
        .accessibilityText(`查找结果第 ${this.index + 1} 处，共 ${this.count} 处，点击查看全部结果`)
        .onClick(() => this.onOpen())
        this.iconButton($r('sys.symbol.chevron_up'), '上一处', this.index > 0, this.textColor, 17,
          () => this.onStep(-1))
        this.iconButton($r('sys.symbol.chevron_down'), '下一处', this.index < this.count - 1, this.textColor, 17,
          () => this.onStep(1))
        if (this.canReturn) {
          this.iconButton($r('sys.symbol.arrow_counterclockwise_clock'), '回到查找前的位置', true,
            this.textColor, 16, () => this.onReturn())
        }
        this.iconButton($r('sys.symbol.xmark'), '结束查找', true, this.subTextColor, 14, () => this.onClose())
      }.width('100%').height('100%').padding({ left: AppSpacing.MD, right: AppSpacing.XS })
    }
  }
}
