import { BookAnnotationStyles } from '../../model/reader/BookAnnotation';
import { AdaptiveColorPicker } from '../AdaptiveColorPicker';

/** 弹层种类：标注面板、笔记气泡、整屏笔记编辑、划线设置。 */
export class ReaderAnnotationLayerMode {
  static readonly NONE: string = '';
  static readonly PANEL: string = 'panel';
  static readonly BUBBLE: string = 'bubble';
  static readonly EDITOR: string = 'editor';
  static readonly CONFIG: string = 'config';
}

const PANEL_MAX_WIDTH: number = 420;
const PANEL_ESTIMATED_HEIGHT: number = 300;
const BUBBLE_ESTIMATED_HEIGHT: number = 110;
const ARROW_SIZE: number = 12;

/**
 * 正文划线的弹层，盖在阅读页最上层。面板、气泡贴着划线：上方放得下放上方，否则放下方。
 * 数据都在阅读页里，这里只显示和回调；笔记正文用 @Link 与阅读页共享草稿，关闭时由阅读页保存。
 */
@Component
export struct ReaderAnnotationLayer {
  @Prop mode: string = '';
  @Prop color: string = BookAnnotationStyles.DEFAULT_COLOR;
  @Prop styleId: string = BookAnnotationStyles.SOLID;
  @Prop quote: string = '';
  @Prop timeText: string = '';
  @Prop noteSaved: string = '';
  /** 划线位置（阅读页根节点坐标，vp）：首行顶、末行底、箭头指向的横坐标。 */
  @Prop anchorTop: number = 0;
  @Prop anchorBottom: number = 0;
  @Prop anchorX: number = 0;
  @Prop dark: boolean = false;
  @Prop panelColor: string = '#FFFFFF';
  @Prop textColor: string = '#222222';
  @Prop accentColor: string = '#3B82F6';
  @Prop safeTop: number = 0;
  @Prop safeBottom: number = 0;
  @Prop focusNote: boolean = false;
  @Prop autoPanel: boolean = true;
  @Prop showNoteDot: boolean = true;
  /** 当前划线是否已收进“我的摘录”。 */
  @Prop excerpt: boolean = false;
  @Link noteDraft: string;
  @State private viewWidth: number = 0;
  @State private viewHeight: number = 0;
  @State private panelHeight: number = PANEL_ESTIMATED_HEIGHT;
  @State private bubbleHeight: number = BUBBLE_ESTIMATED_HEIGHT;
  onClose: () => void = (): void => {};
  onColor: (color: string) => void = (_color: string): void => {};
  onStyle: (style: string) => void = (_style: string): void => {};
  onErase: () => void = (): void => {};
  onCopy: () => void = (): void => {};
  onShare: () => void = (): void => {};
  onExcerpt: () => void = (): void => {};
  onOpenConfig: () => void = (): void => {};
  onEditNote: () => void = (): void => {};
  onExpand: () => void = (): void => {};
  onEditorDone: () => void = (): void => {};
  onAutoPanelChange: (value: boolean) => void = (_value: boolean): void => {};
  onShowNoteDotChange: (value: boolean) => void = (_value: boolean): void => {};

  private lineColor(): string {
    return this.dark ? '#33FFFFFF' : '#1A000000';
  }

  private fieldColor(): string {
    return this.dark ? '#0DFFFFFF' : '#08000000';
  }

  private subColor(): string {
    return this.dark ? '#99FFFFFF' : '#8C000000';
  }

  private iconColor(): string {
    return this.dark ? '#DDFFFFFF' : '#CC000000';
  }

  private popupWidth(): number {
    return Math.max(200, Math.min(PANEL_MAX_WIDTH, this.viewWidth - 24));
  }

  private popupLeft(): number {
    return Math.max(12, (this.viewWidth - this.popupWidth()) / 2);
  }

  /** [top, 箭头方向 1=向下（弹层在上） -1=向上（弹层在下） 0=无] */
  private popupPlacement(height: number): number[] {
    const minTop = this.safeTop + 8;
    const maxBottom = this.viewHeight - this.safeBottom - 8;
    const above = this.anchorTop - height - ARROW_SIZE;
    if (above >= minTop) return [above, 1];
    const below = this.anchorBottom + ARROW_SIZE + 4;
    if (below + height <= maxBottom) return [below, -1];
    return [Math.max(minTop, maxBottom - height), 0];
  }

  private arrowLeft(): number {
    return Math.max(18, Math.min(this.popupWidth() - 18 - ARROW_SIZE, this.anchorX - this.popupLeft() - ARROW_SIZE / 2));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 点弹层外面关闭；整屏编辑和设置盖一层淡色遮罩。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.mode === ReaderAnnotationLayerMode.EDITOR ||
          this.mode === ReaderAnnotationLayerMode.CONFIG ? '#66000000' : Color.Transparent)
        .onClick(() => this.onClose())

      if (this.viewWidth > 0 && this.mode === ReaderAnnotationLayerMode.PANEL) {
        this.anchored(true)
      } else if (this.viewWidth > 0 && this.mode === ReaderAnnotationLayerMode.BUBBLE) {
        this.anchored(false)
      } else if (this.mode === ReaderAnnotationLayerMode.EDITOR) {
        this.editorSheet()
      } else if (this.mode === ReaderAnnotationLayerMode.CONFIG) {
        this.configSheet()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.viewWidth = Number(area.width);
      this.viewHeight = Number(area.height);
    })
  }

  @Builder
  anchored(panel: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.popupPlacement(panel ? this.panelHeight : this.bubbleHeight)[1] !== 0) {
        Row()
          .width(ARROW_SIZE)
          .height(ARROW_SIZE)
          .backgroundColor(this.panelColor)
          .border({ width: 0.5, color: this.lineColor() })
          .rotate({ angle: 45 })
          .position({
            x: this.arrowLeft(),
            y: this.popupPlacement(panel ? this.panelHeight : this.bubbleHeight)[1] > 0 ?
              (panel ? this.panelHeight : this.bubbleHeight) - ARROW_SIZE / 2 - 1 : -ARROW_SIZE / 2 + 1
          })
      }
      Column() {
        if (panel) {
          this.panelBody()
        } else {
          this.bubbleBody()
        }
      }
      .width('100%')
      .backgroundColor(this.panelColor)
      .borderRadius(20)
      .border({ width: 0.5, color: this.lineColor() })
      // 阴影跟着圆角主体走；挂在外层直角的容器上会在四角露出方形的阴影尖角。
      .shadow({ radius: 24, color: this.dark ? '#80000000' : '#33000000', offsetY: 6 })
      .onAreaChange((_old: Area, area: Area) => {
        if (panel) this.panelHeight = Number(area.height);
        else this.bubbleHeight = Number(area.height);
      })
    }
    .width(this.popupWidth())
    .position({ x: this.popupLeft(), y: this.popupPlacement(panel ? this.panelHeight : this.bubbleHeight)[0] })
    .onClick(() => {})
  }

  @Builder
  panelBody() {
    Column() {
      Row() {
        ForEach(BookAnnotationStyles.PRESET_COLORS, (color: string) => {
          this.swatch(color)
        }, (color: string) => color)
        this.customSwatch()
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 4, right: 4, bottom: 10 })
      .border({ width: { bottom: 0.5 }, color: this.lineColor() })

      Row() {
        ForEach(BookAnnotationStyles.ALL, (style: string) => {
          this.styleButton(style)
        }, (style: string) => style)
      }
      .width('100%')
      .padding({ top: 8 })

      Row() {
        this.actionButton($r('sys.symbol.trash'), '擦除', () => this.onErase())
        this.actionButton($r('sys.symbol.rectangle_on_rectangle'), '复制', () => this.onCopy())
        this.excerptButton()
        this.actionButton($r('sys.symbol.share'), '分享', () => this.onShare())
        this.actionButton($r('sys.symbol.gearshape'), '配置', () => this.onOpenConfig())
      }
      .width('100%')
      .padding({ top: 2 })

      Column() {
        TextArea({ text: $$this.noteDraft, placeholder: '写下想法…' })
          .height(72)
          .fontSize(15)
          .fontColor(this.textColor)
          .placeholderColor(this.subColor())
          .backgroundColor(Color.Transparent)
          // 输入框不能去掉内边距：为 0 时首字和提示文字的上沿、左沿会被裁掉。
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .caretColor(this.accentColor)
          .defaultFocus(this.focusNote)
          .id('reader_annotation_note_input')
          .onAppear(() => {
            if (this.focusNote) {
              setTimeout(() => {
                try {
                  this.getUIContext().getFocusController().requestFocus('reader_annotation_note_input');
                } catch (_) {
                }
              }, 60);
            }
          })
        Row() {
          Text(this.noteSaved ? this.timeText : '')
            .fontSize(12)
            .fontColor(this.subColor())
            .padding({ left: 10 })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
            .fontSize(18)
            .fontColor([this.iconColor()])
            .padding(6)
            .accessibilityText('展开编辑')
            .onClick(() => this.onExpand())
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 8 })
      .padding({ left: 2, right: 6, top: 4, bottom: 4 })
      .borderRadius(14)
      .backgroundColor(this.fieldColor())
      .border({ width: 0.5, color: this.lineColor() })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 10 })
  }

  @Builder
  swatch(color: string) {
    Stack() {
      if (color.toUpperCase() === this.color.toUpperCase()) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([Color.White])
      }
    }
    .width(26)
    .height(26)
    .borderRadius(13)
    .backgroundColor(color)
    .accessibilityText(`颜色 ${color}`)
    .onClick(() => this.onColor(color))
  }

  @Builder
  customSwatch() {
    Stack() {
      Stack() {
        if (BookAnnotationStyles.PRESET_COLORS.indexOf(this.color.toUpperCase()) < 0) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([Color.White])
        } else {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(13)
            .fontColor([this.iconColor()])
        }
      }
      .width(26)
      .height(26)
      .borderRadius(13)
      .backgroundColor(BookAnnotationStyles.PRESET_COLORS.indexOf(this.color.toUpperCase()) < 0 ?
        this.color : Color.Transparent)
      .border({ width: 1, color: this.lineColor() })
      .hitTestBehavior(HitTestMode.None)
      // 透明的取色按钮盖在圆点上，点开自定义颜色。
      AdaptiveColorPicker({
        value: this.color,
        placeholder: this.color,
        appDarkMode: this.dark,
        accentColor: this.accentColor,
        optionTitle: '划线颜色',
        hideOptionTrigger: true,
        onColorChange: (color: string) => this.onColor(color)
      })
    }
    .width(26)
    .height(26)
    .clip(true)
    .accessibilityText('自定义颜色')
  }

  @Builder
  styleButton(style: string) {
    Column({ space: 4 }) {
      Text('文')
        .fontSize(20)
        .height(28)
        .fontColor(style === BookAnnotationStyles.TEXT ? this.color : this.iconColor())
        .backgroundColor(style === BookAnnotationStyles.BACKGROUND ? this.withAlpha(this.color, '52') : Color.Transparent)
        .borderRadius(3)
        .padding({ left: 2, right: 2 })
        .decoration({
          type: style === BookAnnotationStyles.SOLID || style === BookAnnotationStyles.WAVY ||
            style === BookAnnotationStyles.DASHED ? TextDecorationType.Underline : TextDecorationType.None,
          color: this.color,
          style: style === BookAnnotationStyles.WAVY ? TextDecorationStyle.WAVY :
            (style === BookAnnotationStyles.DASHED ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID)
        })
      Text(BookAnnotationStyles.label(style))
        .fontSize(12)
        .fontColor(this.iconColor())
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .border({ width: style === this.styleId ? 0.5 : 0, color: this.lineColor() })
    .backgroundColor(style === this.styleId ? this.fieldColor() : Color.Transparent)
    .accessibilityText(BookAnnotationStyles.label(style))
    .onClick(() => this.onStyle(style))
  }

  @Builder
  actionButton(icon: Resource, label: string, action: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.iconColor()])
        .height(28)
      Text(label)
        .fontSize(12)
        .fontColor(this.iconColor())
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .accessibilityText(label)
    .onClick(action)
  }

  /** 摘录开关：收进后图标填成划线颜色。 */
  @Builder
  excerptButton() {
    Column({ space: 4 }) {
      SymbolGlyph(this.excerpt ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
        .fontSize(22)
        .fontColor([this.excerpt ? this.color : this.iconColor()])
        .height(28)
      Text(this.excerpt ? '已摘录' : '摘录')
        .fontSize(12)
        .fontColor(this.excerpt ? this.color : this.iconColor())
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .accessibilityText(this.excerpt ? '已摘录，点按移出摘录' : '加入摘录')
    .onClick(() => this.onExcerpt())
  }

  @Builder
  bubbleBody() {
    Column({ space: 6 }) {
      Scroll() {
        Text(this.noteSaved)
          .fontSize(16)
          .lineHeight(25)
          .fontColor(this.textColor)
          .width('100%')
          .wordBreak(WordBreak.BREAK_WORD)
      }
      .constraintSize({ maxHeight: 200 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      Row() {
        Text(this.timeText)
          .fontSize(12)
          .fontColor(this.subColor())
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(18)
          .fontColor([this.iconColor()])
          .padding(6)
          .accessibilityText('编辑笔记')
          .onClick(() => this.onEditNote())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 10, top: 12, bottom: 4 })
  }

  @Builder
  sheetHeader(title: string, done: () => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .layoutWeight(1)
      Text('完成')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .padding({ left: 12, top: 6, bottom: 6 })
        .onClick(done)
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  @Builder
  editorSheet() {
    Column() {
      this.sheetHeader('笔记', () => this.onEditorDone())
      Text(this.quote)
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.subColor())
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 10 })
        .border({ width: { left: 2 }, color: this.color })
        .margin({ bottom: 12 })
      TextArea({ text: $$this.noteDraft, placeholder: '写下想法…' })
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(this.textColor)
        .placeholderColor(this.subColor())
        .backgroundColor(this.fieldColor())
        .borderRadius(12)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .caretColor(this.accentColor)
        .id('reader_annotation_editor_input')
        .onAppear(() => {
          setTimeout(() => {
            try {
              this.getUIContext().getFocusController().requestFocus('reader_annotation_editor_input');
            } catch (_) {
            }
          }, 80);
        })
    }
    .width('100%')
    .height('78%')
    .padding({ left: 16, right: 16, top: 14, bottom: 16 + this.safeBottom })
    .backgroundColor(this.panelColor)
    .borderRadius({ topLeft: 22, topRight: 22 })
    .position({ x: 0, y: '22%' })
    .onClick(() => {})
  }

  @Builder
  configSheet() {
    Column() {
      this.sheetHeader('划线设置', () => this.onClose())
      this.switchRow('划线后弹出面板', '关闭后点“划线”只画线，点划线才打开面板', this.autoPanel,
        (value: boolean) => this.onAutoPanelChange(value))
      this.switchRow('显示笔记标记', '有笔记的划线末尾显示小圆点', this.showNoteDot,
        (value: boolean) => this.onShowNoteDotChange(value))
      Row() {
        Column({ space: 2 }) {
          Text('新划线的样式')
            .fontSize(15)
            .fontColor(this.textColor)
          Text('沿用上一次选的颜色和样式')
            .fontSize(12)
            .fontColor(this.subColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Row({ space: 6 }) {
          Row().width(10).height(10).borderRadius(5).backgroundColor(this.color)
          Text(BookAnnotationStyles.label(this.styleId))
            .fontSize(13)
            .fontColor(this.subColor())
        }
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 16 + this.safeBottom })
    .backgroundColor(this.panelColor)
    .borderRadius({ topLeft: 22, topRight: 22 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .onClick(() => {})
  }

  @Builder
  switchRow(title: string, description: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor(this.textColor)
        Text(description)
          .fontSize(12)
          .fontColor(this.subColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.accentColor)
        .onChange((isOn: boolean) => onChange(isOn))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 0.5 }, color: this.lineColor() })
  }

  private withAlpha(color: string, alphaHex: string): string {
    const normalized = BookAnnotationStyles.normalizeColor(color);
    return `#${alphaHex}${normalized.substring(1)}`;
  }
}
