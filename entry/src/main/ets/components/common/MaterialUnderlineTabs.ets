import { curves } from '@kit.ArkUI';
import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';

/**
 * 沉浸光感切换条，外观与书架顶部的类型分类栏一致：一整条光感胶囊底板，各项等宽，
 * 选中项强调色文字，下方 18vp 指示条用弹簧动画滑过去。宽度跟随父容器，量到宽度后才画底板
 * （光感底板只接受具体宽度）。
 *   MaterialUnderlineTabs({ labels: ['藏书卡', '电影票'], selectedIndex: this.index,
 *     onSelect: (index: number) => { this.index = index; } })
 */
@Component
export struct MaterialUnderlineTabs {
  static readonly HEIGHT: number = 44;
  private static readonly PADDING: number = 6;
  private static readonly INDICATOR_WIDTH: number = 18;

  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  @State barWidth: number = 0;
  onSelect: (index: number) => void = (_index: number): void => {
  };

  private accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  /** 指示条居中在选中项下方；各项等宽平分去掉两侧留白后的宽度。 */
  private indicatorX(): number {
    const count = Math.max(1, this.labels.length);
    const itemWidth = (this.barWidth - MaterialUnderlineTabs.PADDING * 2) / count;
    return MaterialUnderlineTabs.PADDING + itemWidth * Math.max(0, this.selectedIndex) +
      (itemWidth - MaterialUnderlineTabs.INDICATOR_WIDTH) / 2;
  }

  build() {
    Row() {
      if (this.barWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.barWidth,
          surfaceHeight: MaterialUnderlineTabs.HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: ThemeRuntime.cardColor(this.appDarkMode),
          glowColor: `#40${this.accentColor().substring(1)}`
        }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Row() {
              ForEach(this.labels, (label: string, index: number) => {
                Text(label)
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.selectedIndex === index ? this.accentColor() :
                    ThemeRuntime.subTextColor(this.appDarkMode))
                  .animation({ duration: 180, curve: Curve.Friction })
                  .maxLines(1)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height('100%')
                  .accessibilityText(label)
                  .accessibilitySelected(this.selectedIndex === index)
                  .onClick(() => {
                    if (index !== this.selectedIndex) this.onSelect(index);
                  })
              }, (label: string) => label)
            }
            .width('100%')
            .height('100%')
            .padding({ left: MaterialUnderlineTabs.PADDING, right: MaterialUnderlineTabs.PADDING })

            Row()
              .width(MaterialUnderlineTabs.INDICATOR_WIDTH)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentColor())
              .translate({ x: this.indicatorX(), y: -5 })
              .animation({ curve: curves.springMotion(0.3, 1) })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .width('100%')
    .height(MaterialUnderlineTabs.HEIGHT)
    .borderRadius(MaterialUnderlineTabs.HEIGHT / 2)
    .clip(true)
    // 底板自带的阴影被这一层 clip 裁掉了，阴影挂在裁剪层上，与书架分类栏一致。
    .shadow(ThemeRuntime.floatingControlShadow(this.appDarkMode))
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.barWidth) this.barWidth = width;
    })
  }
}
