import { AppFontSize } from '../../theme/AppFontSize';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** Shared content for the system-material surface and the ordinary reader panel. */
@Component
export struct ReaderQuickJumpContent {
  @Prop mode: string = 'chapter';
  @Prop chapterLabel: string = '章节';
  @Prop chapterUnit: string = '章';
  @Prop value: number = 0;
  @Prop chapterCount: number = 0;
  @Prop currentChapter: number = 0;
  @Prop valueLabel: string = '';
  @Prop busy: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '';
  @Prop subTextColor: string = '';
  @Prop accentColor: string = '';
  @Prop trackColor: string = '';
  @Prop thumbColor: string = '';
  onModeChange: (mode: string) => void = (_mode: string): void => {};
  onChange: (value: number, mode: SliderChangeMode) => void = (_value: number, _mode: SliderChangeMode): void => {};
  onStep: (direction: number) => void = (_direction: number): void => {};

  @Builder
  modeButton(mode: string, label: string) {
    Button(label, { type: ButtonType.Capsule, stateEffect: true })
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === mode ? this.textColor : this.subTextColor)
      .backgroundColor(Color.Transparent)
      .height(36)
      .layoutWeight(1)
      .padding({ left: 6, right: 6 })
      .enabled(!this.busy && this.chapterCount > 0)
      .accessibilityText(`${label}跳转${this.mode === mode ? '，已选中' : ''}`)
      .onClick(() => this.onModeChange(mode))
  }

  @Builder
  stepButton(direction: number) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
        .fontSize(24)
        .fontColor([this.textColor])
    }
    .width(44)
    .height(48)
    .backgroundColor(Color.Transparent)
    .enabled(!this.busy && this.chapterCount > 0 &&
      (direction < 0 ? this.currentChapter > 0 : this.currentChapter < this.chapterCount - 1))
    .accessibilityText(`${direction < 0 ? '上一' : '下一'}${this.chapterUnit}`)
    .onClick(() => this.onStep(direction))
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('50%')
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.thumbColor)
            .translate({ x: this.mode === 'percent' ? '100%' : 0 })
            .animation({ duration: 180, curve: Curve.EaseOut })
          Row() {
            this.modeButton('chapter', this.chapterLabel)
            this.modeButton('percent', '百分比')
          }
          .width('100%')
        }
        .width('56%')
        .constraintSize({ maxWidth: 188 })
        .height(44)
        .padding(4)
        .borderRadius(22)
        .backgroundColor(ThemeRuntime.softFillColor(this.dark))
        Text(this.valueLabel)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.busy ? this.subTextColor : this.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(2)
      }
      .width('100%')
      .padding({ left: 12, right: 16 })
      Row() {
        this.stepButton(-1)
        Slider({
          value: this.value,
          min: 0,
          max: this.mode === 'percent' ? 100 : Math.max(1, this.chapterCount - 1),
          step: this.mode === 'percent' ? 0.1 : 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(48)
          .trackThickness(24)
          .blockSize({ width: 26, height: 26 })
          .selectedColor(this.accentColor)
          .trackColor(this.trackColor)
          .blockColor(this.thumbColor)
          .showSteps(false)
          .enabled(!this.busy && (this.mode === 'percent' ? this.chapterCount > 0 : this.chapterCount > 1))
          .accessibilityText(`${this.mode === 'percent' ? '全书百分比' : this.chapterLabel}，${this.valueLabel}`)
          .onChange((value: number, mode: SliderChangeMode) => this.onChange(value, mode))
        this.stepButton(1)
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6, bottom: 6 })
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
