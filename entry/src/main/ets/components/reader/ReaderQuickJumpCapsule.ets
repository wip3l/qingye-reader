import { AppFontSize } from '../../theme/AppFontSize';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

export const READER_QUICK_JUMP_CAPSULE_HEIGHT: number = 54;

/**
 * 快速跳转的浮动胶囊：拖动进度条时显示目标位置，松手直接跳转；跳转后右侧撤销键亮起，
 * 点一下回到第一次跳走前的位置。记原位置、执行跳转与撤销由各阅读页负责，菜单关闭即作废。
 */
@Component
export struct ReaderQuickJumpCapsule {
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop loading: boolean = false;
  @Prop canUndo: boolean = false;
  @Prop undoLabel: string = '回到跳转前的位置';
  @Prop capsuleWidth: number = 300;
  @Prop darkMode: boolean = false;
  @Prop fallbackColor: ResourceColor = '#FFFFFF';
  @Prop textColor: ResourceColor = '#E6000000';
  @Prop subTextColor: ResourceColor = '#99000000';
  @Prop dividerColor: ResourceColor = '#14000000';
  onUndo: () => void = (): void => {};

  build() {
    ReaderMaterialPanel({
      panelWidth: this.capsuleWidth,
      panelHeight: READER_QUICK_JUMP_CAPSULE_HEIGHT,
      cornerRadius: READER_QUICK_JUMP_CAPSULE_HEIGHT / 2,
      darkMode: this.darkMode,
      fallbackColor: this.fallbackColor
    }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            if (this.loading) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(this.subTextColor)
            }
            Text(this.loading ? '正在加载…' : this.detail)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .justifyContent(FlexAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 18, right: 8 })
        .accessibilityGroup(true)
        Divider()
          .vertical(true)
          .height(28)
          .strokeWidth(0.5)
          .color(this.dividerColor)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
            .fontSize(22)
            .fontColor([this.textColor])
        }
        .width(58)
        .height('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius({ topRight: READER_QUICK_JUMP_CAPSULE_HEIGHT / 2, bottomRight: READER_QUICK_JUMP_CAPSULE_HEIGHT / 2 })
        .enabled(this.canUndo)
        .opacity(this.canUndo ? 1 : 0.3)
        .accessibilityText(this.undoLabel)
        .onClick(() => this.onUndo())
      }
      .width('100%')
      .height('100%')
    }
  }
}
