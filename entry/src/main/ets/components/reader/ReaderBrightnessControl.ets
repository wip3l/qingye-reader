import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { AppFontSize } from '../../theme/AppFontSize';

@Component
export struct ReaderBrightnessControl {
  static readonly WIDTH: number = 48;
  @Prop value: number = -1;
  @Prop lastManualValue: number = 50;
  @Prop panelHeight: number = 280;
  @Prop ready: boolean = false;
  @Prop dark: boolean = false;
  @Prop panelColor: string = '';
  @Prop textColor: string = '';
  @Prop subTextColor: string = '';
  @Prop accentColor: string = '';
  @Prop trackColor: string = '';
  @Prop thumbColor: string = '';
  onChange: (value: number, persist: boolean) => void = (_value: number, _persist: boolean): void => {};

  build() {
    Stack() {
      ReaderMaterialPanel({
        panelWidth: ReaderBrightnessControl.WIDTH, panelHeight: this.panelHeight,
        cornerRadius: ReaderBrightnessControl.WIDTH / 2,
        darkMode: this.dark, fallbackColor: this.panelColor
      }) {
        Column({ space: 4 }) {
          if (this.panelHeight >= 220) {
            Text('亮度')
              .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor).height(18)
          }
          Text(this.value < 0 ? '' : `${this.value}%`)
            .fontSize(AppFontSize.CAPTION).fontColor(this.textColor).height(22)
            .maxLines(1).minFontSize(AppFontSize.MICRO).maxFontSize(AppFontSize.CAPTION)
          if (this.panelHeight >= 220) {
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(18).fontColor([this.textColor]).height(20)
          }
          Slider({ value: this.value < 0 ? this.lastManualValue : this.value,
            min: 1, max: 100, step: 1, direction: Axis.Vertical, reverse: true })
            .width(44).layoutWeight(1)
            .trackThickness(4).trackColor(this.trackColor).selectedColor(this.accentColor)
            .blockColor(this.thumbColor)
            .enabled(this.ready)
            .accessibilityText(this.value < 0 ? '阅读亮度，跟随系统，拖动后手动调整' : `阅读亮度，${this.value}%`)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.onChange(Math.round(value), mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
            })
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_reader_brightness_auto'))
              .width(22).height(22)
              .fillColor(this.value < 0 ? this.accentColor : this.textColor)
          }
            // Fill the material's inner width and sit flush against its bottom semicircle.
            // The native material keeps its own 1vp rim; the fallback surface has no inner inset.
            .width('100%').aspectRatio(1).padding(0)
            .backgroundColor(this.value < 0 ? this.trackColor : Color.Transparent)
            .enabled(this.ready)
            .accessibilityText(this.value < 0 ? '跟随系统亮度，已开启' : '跟随系统亮度')
            .onClick((): void => this.onChange(-1, true))
        }
        .width('100%').height('100%').padding({ top: 12 })
      }
    }
    .width(ReaderBrightnessControl.WIDTH).height(this.panelHeight)
    .onTouch((event: TouchEvent): void => event.stopPropagation())
  }
}
