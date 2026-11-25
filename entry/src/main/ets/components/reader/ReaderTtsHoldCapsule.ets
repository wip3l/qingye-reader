import { AppFontSize } from '../../theme/AppFontSize';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 朗读不跟随翻页时的底部胶囊：左边回到朗读正在读的那一页，右边从当前这一页读起。
 * 朗读设置为“停留 3 秒后”时，耳机外圈有一段弧在 countdownMs 内绕一圈，绕完由阅读页接着从本页读；
 * countdownKey 每变一次重新计时，为 0 时外圈隐藏。何时显示、点了做什么都由阅读页决定。
 *
 * 底板与其他阅读页胶囊一样用沉浸光感材质。它盖在正文上，正文翻动时材质要跟着重算，所以阅读页在翻页
 * （含手指拖动）期间把胶囊设为 Hidden，不卸载、不重新布局，停稳再显示。
 * 外圈只在开始计时时发起一次旋转动画，由渲染线程跑，不在 UI 线程逐帧改状态；外圈节点常驻，只改透明度。
 */
@Component
export struct ReaderTtsHoldCapsule {
  static readonly WIDTH: number = 188;
  static readonly HEIGHT: number = 46;
  private static readonly BACK_WIDTH: number = 56;
  private static readonly RING_SIZE: number = 28;
  private static readonly RING_STROKE: number = 2;

  @Prop @Watch('onCountdownChanged') countdownKey: number = 0;
  @Prop countdownMs: number = 3000;
  @Prop darkMode: boolean = false;
  @Prop panelColor: ResourceColor = '#FFFFFF';
  @Prop textColor: ResourceColor = '#E6000000';
  @Prop dividerColor: ResourceColor = '#14000000';
  @Prop backLabel: string = '回到朗读处';
  @State ringAngle: number = 0;
  @State ringVisible: boolean = false;
  private ringSerial: number = 0;
  onBack: () => void = (): void => {};
  onListenHere: () => void = (): void => {};

  aboutToAppear(): void {
    this.onCountdownChanged();
  }

  onCountdownChanged(): void {
    const serial = ++this.ringSerial;
    // 先不带动画回到起点，下一帧再发起一整圈的线性旋转；中途取消时直接停在隐藏状态。
    this.ringVisible = this.countdownKey > 0;
    this.ringAngle = 0;
    if (this.countdownKey <= 0) return;
    setTimeout((): void => {
      if (serial !== this.ringSerial || this.countdownKey <= 0) return;
      this.getUIContext().animateTo({ duration: Math.max(1, this.countdownMs), curve: Curve.Linear }, () => {
        this.ringAngle = 360;
      });
    }, 0);
  }

  private ringDash(): number[] {
    const radius = (ReaderTtsHoldCapsule.RING_SIZE - ReaderTtsHoldCapsule.RING_STROKE) / 2;
    const circumference = 2 * Math.PI * radius;
    return [circumference / 4, circumference];
  }

  build() {
    ReaderMaterialPanel({
      panelWidth: ReaderTtsHoldCapsule.WIDTH,
      panelHeight: ReaderTtsHoldCapsule.HEIGHT,
      cornerRadius: ReaderTtsHoldCapsule.HEIGHT / 2,
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
        SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
          .fontSize(20)
          .fontColor([this.textColor])
      }
      .width(ReaderTtsHoldCapsule.BACK_WIDTH)
      .height('100%')
      .padding({ left: 6 })
      .backgroundColor(Color.Transparent)
      .borderRadius({ topLeft: ReaderTtsHoldCapsule.HEIGHT / 2, bottomLeft: ReaderTtsHoldCapsule.HEIGHT / 2 })
      .accessibilityText(this.backLabel)
      .onClick(() => this.onBack())

      Divider()
        .vertical(true)
        .height(20)
        .strokeWidth(0.5)
        .color(this.dividerColor)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 7 }) {
          Stack() {
            Circle()
              .width(ReaderTtsHoldCapsule.RING_SIZE)
              .height(ReaderTtsHoldCapsule.RING_SIZE)
              .fill(Color.Transparent)
              .stroke(this.textColor)
              .strokeWidth(ReaderTtsHoldCapsule.RING_STROKE)
              .strokeLineCap(LineCapStyle.Round)
              .strokeDashArray(this.ringDash())
              .rotate({ angle: this.ringAngle - 90 })
              .opacity(this.ringVisible ? 0.9 : 0)
            SymbolGlyph($r('sys.symbol.earphone'))
              .fontSize(17)
              .fontColor([this.textColor])
          }
          .width(ReaderTtsHoldCapsule.RING_SIZE)
          .height(ReaderTtsHoldCapsule.RING_SIZE)

          Text('从本页听')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor)
            .maxLines(1)
        }
        .padding({ left: 10, right: 18 })
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius({ topRight: ReaderTtsHoldCapsule.HEIGHT / 2, bottomRight: ReaderTtsHoldCapsule.HEIGHT / 2 })
      .accessibilityText(this.ringVisible ? '从本页听，停留 3 秒后自动开始' : '从本页听')
      .onClick(() => this.onListenHere())
    }
    .width('100%')
    .height('100%')
  }
}
