import { AppFontSize } from '../../theme/AppFontSize';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 朗读不跟随翻页时的底部胶囊：左边回到朗读正在读的那一页，右边从当前这一页读起。
 * 朗读设置为“停留 3 秒后”时，耳机外圈按 countdownMs 走一圈，走完由阅读页接着从本页读；
 * countdownKey 每变一次重新计时，为 0 时不显示外圈。何时显示、点了做什么都由阅读页决定。
 */
@Component
export struct ReaderTtsHoldCapsule {
  static readonly WIDTH: number = 188;
  static readonly HEIGHT: number = 46;
  private static readonly BACK_WIDTH: number = 56;
  private static readonly TICK_MS: number = 100;

  @Prop @Watch('onCountdownChanged') countdownKey: number = 0;
  @Prop countdownMs: number = 3000;
  @Prop darkMode: boolean = false;
  @Prop fallbackColor: ResourceColor = '#FFFFFF';
  @Prop textColor: ResourceColor = '#E6000000';
  @Prop dividerColor: ResourceColor = '#14000000';
  @Prop backLabel: string = '回到朗读处';
  @State countdownProgress: number = 0;
  private countdownTimerId: number = -1;
  private countdownStartedAt: number = 0;
  onBack: () => void = (): void => {};
  onListenHere: () => void = (): void => {};

  aboutToAppear(): void {
    this.onCountdownChanged();
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  onCountdownChanged(): void {
    this.stopCountdown();
    this.countdownProgress = 0;
    if (this.countdownKey <= 0) return;
    this.countdownStartedAt = Date.now();
    this.countdownTimerId = setInterval(() => {
      const elapsed = Date.now() - this.countdownStartedAt;
      this.countdownProgress = Math.min(100, elapsed * 100 / Math.max(1, this.countdownMs));
      if (this.countdownProgress >= 100) this.stopCountdown();
    }, ReaderTtsHoldCapsule.TICK_MS);
  }

  private stopCountdown(): void {
    if (this.countdownTimerId < 0) return;
    clearInterval(this.countdownTimerId);
    this.countdownTimerId = -1;
  }

  build() {
    ReaderMaterialPanel({
      panelWidth: ReaderTtsHoldCapsule.WIDTH,
      panelHeight: ReaderTtsHoldCapsule.HEIGHT,
      cornerRadius: ReaderTtsHoldCapsule.HEIGHT / 2,
      darkMode: this.darkMode,
      fallbackColor: this.fallbackColor
    }) {
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
              if (this.countdownKey > 0) {
                Progress({ value: this.countdownProgress, total: 100, type: ProgressType.Ring })
                  .width(28)
                  .height(28)
                  .color(this.textColor)
                  .backgroundColor(Color.Transparent)
                  .style({ strokeWidth: 2, enableSmoothEffect: true })
              }
              SymbolGlyph($r('sys.symbol.earphone'))
                .fontSize(17)
                .fontColor([this.textColor])
            }
            .width(28)
            .height(28)

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
        .accessibilityText(this.countdownKey > 0 ? '从本页听，停留 3 秒后自动开始' : '从本页听')
        .onClick(() => this.onListenHere())
      }
      .width('100%')
      .height('100%')
    }
  }
}
