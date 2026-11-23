import display from '@ohos.display';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderBackgroundDisplay } from '../../utils/ReaderBackgroundDisplay';
import { ReaderSettingTabStrip } from './ReaderSettingGroups';
import { ReaderRasterAssets } from '../../core/reader/ReaderRasterAssets';

/**
 * 阅读背景整图的“图片显示”：裁切铺满 / 完整显示 / 拉伸铺满 / 平铺，裁切时的取景滑杆，完整显示时空白处怎么填。
 * 阅读页设置面板和“设置 › 阅读背景”共用，主题包整图和“自定义”背景图共用。只按传入的值显示，自己不记状态。
 * onChange 的 commit 为 false 是拖动取景途中的预览，松手时再来一次 commit 为 true 的。
 */
@Component
export struct ReaderBackgroundDisplayControl {
  @Prop fit: string = 'cover';
  /** 取景位置；叫 position 会和组件的 .position() 属性方法撞名。 */
  @Prop cropPosition: number = 50;
  @Prop gap: string = 'blur';
  /** 背景图本机路径，用来判断裁切铺满时哪条轴被裁（决定取景滑杆是上下还是左右，不裁就不显示）。 */
  @Prop imageUri: string = '';
  /** 背景实际铺开的大小（阅读页传页面大小，双页是整个跨页）；不传时按屏幕算。 */
  @Prop viewportWidth: number = 0;
  @Prop viewportHeight: number = 0;
  /** 主题作者的设定；空串表示没有“主题默认”可回（自定义背景图）。 */
  @Prop defaultFit: string = '';
  /** 读者在这台设备上改过（有记录）时显示“恢复主题默认”。 */
  @Prop overridden: boolean = false;
  @Prop title: string = '图片显示';
  @Prop hint: string = '';
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#666666';
  @Prop accentColor: string = '#0A59F7';
  @State private dragPosition: number = -1;
  onChange: (display: ReaderBackgroundDisplay, commit: boolean) => void = () => {};
  onReset: () => void = () => {};

  build() {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        Text(this.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
        if (this.showsDefaultTag()) {
          Text('主题默认')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.accentColor)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
            .border({ width: 0.5, color: this.accentColor })
        }
        Blank()
        if (this.overridden && this.defaultFit) {
          Text('恢复主题默认')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.accentColor)
            .padding({ top: 4, bottom: 4, left: 6 })
            .accessibilityText('恢复主题默认的图片显示方式')
            .onClick(() => this.onReset())
        }
      }
      .width('100%')

      ReaderSettingTabStrip({
        labels: ReaderBackgroundDisplay.FIT_LABELS,
        selected: Math.max(0, ReaderBackgroundDisplay.FITS.indexOf(ReaderBackgroundDisplay.normalizeFit(this.fit))),
        dense: true,
        dark: this.dark,
        textColor: this.textColor,
        subTextColor: this.subTextColor,
        onSelect: (index: number): void => this.selectFit(ReaderBackgroundDisplay.FITS[index])
      })

      if (this.fit === ReaderBackgroundDisplay.FIT_COVER && this.axis()) {
        Row({ space: AppSpacing.SM }) {
          Text('取景')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
          Text(this.axis() === 'v' ? '上' : '左')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
          Slider({ value: this.sliderValue(), min: 0, max: 100, step: 1 })
            .layoutWeight(1)
            .height(36)
            .selectedColor(this.accentColor)
            .blockColor(this.accentColor)
            .trackColor(this.dark ? '#33FFFFFF' : '#1F000000')
            .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK_UP)
            .accessibilityText(this.axis() === 'v' ? '取景位置，从上到下' : '取景位置，从左到右')
            .onChange((value: number, mode: SliderChangeMode) => this.onSlide(value, mode))
          Text(this.axis() === 'v' ? '下' : '右')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
        }
        .width('100%')
      }

      if (this.fit === ReaderBackgroundDisplay.FIT_CONTAIN) {
        Row({ space: AppSpacing.MD }) {
          Text('空白处')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
          ReaderSettingTabStrip({
            labels: ['模糊延展', '主题底色'],
            selected: this.gap === ReaderBackgroundDisplay.GAP_BLUR ? 0 : 1,
            dense: true,
            dark: this.dark,
            textColor: this.textColor,
            subTextColor: this.subTextColor,
            onSelect: (index: number): void => {
              this.emit(this.fit, this.cropPosition,
                index === 0 ? ReaderBackgroundDisplay.GAP_BLUR : ReaderBackgroundDisplay.GAP_COLOR, true);
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
      }

      if (this.hint) {
        Text(this.hint)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  private axis(): string {
    let width = this.viewportWidth;
    let height = this.viewportHeight;
    if (width <= 0 || height <= 0) {
      try {
        const screen = display.getDefaultDisplaySync();
        width = screen.width;
        height = screen.height;
      } catch (_) {
        return '';
      }
    }
    return ReaderBackgroundDisplay.croppedAxis(ReaderRasterAssets.imageAspect(this.imageUri), width, height);
  }

  private showsDefaultTag(): boolean {
    return !!this.defaultFit && !this.overridden;
  }

  private sliderValue(): number {
    return this.dragPosition >= 0 ? this.dragPosition : ReaderBackgroundDisplay.normalizePosition(this.cropPosition);
  }

  private selectFit(fit: string): void {
    // 新选“完整显示”时空白处默认模糊延展；已经是完整显示（比如作者设的露底色）就保持原样。
    const gap = fit === ReaderBackgroundDisplay.FIT_CONTAIN && this.fit !== ReaderBackgroundDisplay.FIT_CONTAIN ?
      ReaderBackgroundDisplay.GAP_BLUR : this.gap;
    this.emit(fit, this.cropPosition, gap, true);
  }

  private onSlide(value: number, mode: SliderChangeMode): void {
    const position = ReaderBackgroundDisplay.normalizePosition(value);
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.dragPosition = -1;
      this.emit(this.fit, position, this.gap, true);
      return;
    }
    if (position === this.dragPosition) return;
    this.dragPosition = position;
    this.emit(this.fit, position, this.gap, false);
  }

  private emit(fit: string, position: number, gap: string, commit: boolean): void {
    this.onChange(ReaderBackgroundDisplay.of(fit, position, gap), commit);
  }
}
