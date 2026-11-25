import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { AppFontSize } from '../../theme/AppFontSize';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { ReaderEyeCare } from '../../utils/ReaderEyeCare';
import { HdsFeedback } from '../../utils/HdsFeedback';

@Component
export struct ReaderBrightnessControl {
  static readonly WIDTH: number = 48;
  static readonly EDGE_GAP: number = 12;
  private static readonly EYE_CARE_ON_TOP: string = '#FFC27E';
  private static readonly EYE_CARE_ON_BOTTOM: string = '#E07F22';
  private static readonly EYE_CARE_ON_TOP_DARK: string = '#E9A15A';
  private static readonly EYE_CARE_ON_BOTTOM_DARK: string = '#B4651A';

  /** 亮度条的左边：默认贴右边，智感握姿识别到左手握持（onLeft）时贴左边。 */
  static left(viewportWidth: number, onLeft: boolean): number {
    return onLeft ? ReaderBrightnessControl.EDGE_GAP :
      Math.max(0, viewportWidth - ReaderBrightnessControl.WIDTH - ReaderBrightnessControl.EDGE_GAP);
  }
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('readerEyeCareOn') eyeCareOn: boolean = false;
  @StorageProp('readerEyeCareLevel') eyeCareLevel: number = ReaderEyeCare.DEFAULT_LEVEL;
  @Prop value: number = -1;
  @Prop lastManualValue: number = 50;
  @Prop panelHeight: number = 280;
  @Prop ready: boolean = false;
  @Prop dark: boolean = false;
  /** 亮度条贴在左边时，强度弹层向右弹出。 */
  @Prop onLeft: boolean = false;
  @Prop panelColor: string = '';
  @Prop textColor: string = '';
  @Prop accentColor: string = '';
  @Prop trackColor: string = '';
  @Prop thumbColor: string = '';
  @State private showEyeCareLevel: boolean = false;
  onChange: (value: number, persist: boolean) => void = (_value: number, _persist: boolean): void => {};

  private toggleEyeCare(): void {
    if (ReaderEyeCare.setOn(!this.eyeCareOn)) HdsFeedback.showToast('长按护眼按钮可调强度');
  }

  private openEyeCareLevel(): void {
    if (!this.eyeCareOn) ReaderEyeCare.setOn(true);
    this.showEyeCareLevel = true;
  }

  @Builder
  eyeCareLevelPanel() {
    Column({ space: 6 }) {
      Row() {
        Text('护眼强度').fontSize(AppFontSize.BODY).fontColor(this.textColor).layoutWeight(1)
        Text(`${this.eyeCareLevel}`).fontSize(AppFontSize.CAPTION).fontColor(this.textColor).opacity(0.6)
      }
      .width('100%')
      Slider({ value: this.eyeCareLevel, min: 1, max: 100, step: 1 })
        .width('100%')
        .trackThickness(6)
        .trackColor(this.dark ? '#5A4A39' : '#FBE2C4')
        .selectedColor(this.dark ? ReaderBrightnessControl.EYE_CARE_ON_BOTTOM_DARK :
          ReaderBrightnessControl.EYE_CARE_ON_BOTTOM)
        .blockColor(this.thumbColor)
        .accessibilityText(`护眼强度，${this.eyeCareLevel}`)
        .onChange((value: number, mode: SliderChangeMode): void => {
          ReaderEyeCare.setLevel(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
      Row() {
        Text('微暖').fontSize(AppFontSize.MICRO).fontColor(this.textColor).opacity(0.6).layoutWeight(1)
        Text('深琥珀').fontSize(AppFontSize.MICRO).fontColor(this.textColor).opacity(0.6)
      }
      .width('100%')
    }
    .width(236)
    .padding({ left: 18, right: 18, top: 14, bottom: 12 })
  }

  @Builder
  eyeCareButton() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.eye'))
        .fontSize(22)
        .fontColor([this.eyeCareOn ? '#FFFFFF' : this.textColor])
    }
      // 和底部“自动”按钮对称：铺满材质内宽，贴住顶部半圆。
      .width('100%').aspectRatio(1).padding(0)
      .backgroundColor(Color.Transparent)
      .linearGradient(this.eyeCareOn ? {
        angle: 180,
        colors: this.dark ?
          [[ReaderBrightnessControl.EYE_CARE_ON_TOP_DARK, 0], [ReaderBrightnessControl.EYE_CARE_ON_BOTTOM_DARK, 1]] :
          [[ReaderBrightnessControl.EYE_CARE_ON_TOP, 0], [ReaderBrightnessControl.EYE_CARE_ON_BOTTOM, 1]]
      } : { angle: 180, colors: [[Color.Transparent, 0], [Color.Transparent, 1]] })
      .enabled(this.ready)
      .accessibilityText(this.eyeCareOn ? '护眼模式，已开启，长按调强度' : '护眼模式，长按调强度')
      .gesture(GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 450 }).onAction((): void => this.openEyeCareLevel()),
        TapGesture().onAction((): void => this.toggleEyeCare())
      ))
      .bindPopup(this.showEyeCareLevel, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
        (): void => {
          this.eyeCareLevelPanel()
        }, this.onLeft ? Placement.Right : Placement.Left, this.dark, this.accentColor, (): void => {
          this.showEyeCareLevel = false;
        }))
  }

  build() {
    Stack() {
      ReaderMaterialPanel({
        panelWidth: ReaderBrightnessControl.WIDTH, panelHeight: this.panelHeight,
        cornerRadius: ReaderBrightnessControl.WIDTH / 2,
        darkMode: this.dark, fallbackColor: this.panelColor
      }) {
        Column({ space: 4 }) {
          // 上下两端各一个圆钮：顶部护眼、底部跟随系统亮度。跟随系统时没有数值可显示，
          // 数值格不占位，让滑块向上延长，状态由底部自动按钮高亮表示。横屏等短条上也收起数值，给滑块留长度。
          this.eyeCareButton()
          if (this.value >= 0 && this.panelHeight >= 180) {
            Text(`${this.value}%`)
              .fontSize(AppFontSize.CAPTION).fontColor(this.textColor).height(22)
              .maxLines(1).minFontSize(AppFontSize.MICRO).maxFontSize(AppFontSize.CAPTION)
          }
          Slider({ value: this.value < 0 ? this.lastManualValue : this.value,
            min: 1, max: 100, step: 1, direction: Axis.Vertical, reverse: true })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
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
        .width('100%').height('100%')
      }
    }
    .width(ReaderBrightnessControl.WIDTH).height(this.panelHeight)
    .onTouch((event: TouchEvent): void => event.stopPropagation())
  }
}
