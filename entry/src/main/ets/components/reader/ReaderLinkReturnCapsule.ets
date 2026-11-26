import { AppFontSize } from '../../theme/AppFontSize';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 点书内链接跳走后停在页脚上方的“返回原处”胶囊：左边回到点链接前的位置，右边三个小点表示还能翻几页，
 * 翻满 TURN_LIMIT 页（往后读下去，说明不打算回了）由阅读页收起；× 直接收起。
 * 记原位置、数翻页、执行返回都由阅读页负责（应用排版与文件排版共用这个胶囊）。
 */
@Component
export struct ReaderLinkReturnCapsule {
  static readonly WIDTH: number = 252;
  static readonly HEIGHT: number = 44;
  static readonly TURN_LIMIT: number = 3;

  /** 原处所在的章节名与页码，如“第三章 旧书铺”“6/9”。 */
  @Prop where: string = '';
  @Prop pageText: string = '';
  @Prop turns: number = 0;
  @Prop darkMode: boolean = false;
  @Prop panelColor: ResourceColor = '#FFFFFF';
  @Prop textColor: ResourceColor = '#E6000000';
  @Prop subTextColor: ResourceColor = '#99000000';
  @Prop accentColor: ResourceColor = '#3A7BD5';
  onBack: () => void = (): void => {};
  onClose: () => void = (): void => {};

  build() {
    ReaderMaterialPanel({
      panelWidth: ReaderLinkReturnCapsule.WIDTH,
      panelHeight: ReaderLinkReturnCapsule.HEIGHT,
      cornerRadius: ReaderLinkReturnCapsule.HEIGHT / 2,
      darkMode: this.darkMode,
      fallbackColor: this.panelColor
    }) {
      this.capsuleBody()
    }
  }

  @Builder
  capsuleBody() {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
            .fontSize(18)
            .fontColor([this.accentColor])
          Text('返回原处')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
            .maxLines(1)
          Text(this.where)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.pageText) {
            Text(this.pageText)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor)
              .maxLines(1)
              .flexShrink(0)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 4 })
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius({ topLeft: ReaderLinkReturnCapsule.HEIGHT / 2, bottomLeft: ReaderLinkReturnCapsule.HEIGHT / 2 })
      .accessibilityText(`返回原处 ${this.where} ${this.pageText}`)
      .onClick(() => this.onBack())

      Row({ space: 3 }) {
        ForEach([0, 1, 2], (index: number) => {
          Circle()
            .width(5)
            .height(5)
            .fill(this.subTextColor)
            .opacity(index < this.turns ? 0.18 : 0.75)
        }, (index: number): string => `${index}`)
      }
      .margin({ left: 2 })
      .accessibilityText(`再翻 ${Math.max(0, ReaderLinkReturnCapsule.TURN_LIMIT - this.turns)} 页后收起`)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([this.subTextColor])
      }
      .width(32)
      .height(32)
      .margin({ left: 2, right: 6 })
      .backgroundColor(Color.Transparent)
      .accessibilityText('关闭')
      .onClick(() => this.onClose())
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }
}
