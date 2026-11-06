import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 光感材质的分段切换栏：同一块胶囊滑到选中项，再通知调用方换内容。
 * 胶囊先动、内容晚一个动画时长再挂载，切到字体、正则这类较重的控件时滑动不卡；
 * 连续快点只换最后一次。
 *   MaterialSegmentTabs({ labels: ['正文', '标题'], selectedIndex: this.tab, tabsWidth: 320,
 *     onSelect: (index: number) => { this.tab = index; } })
 */
@Component
export struct MaterialSegmentTabs {
  static readonly SWITCH_DURATION: number = 180;
  private static readonly OUTER_HEIGHT: number = 44;
  private static readonly INNER_HEIGHT: number = 36;
  private static readonly INSET: number = 4;

  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @Prop labels: string[] = [];
  @Prop @Watch('syncVisualIndex') selectedIndex: number = 0;
  @Prop tabsWidth: number = 320;
  @Prop idPrefix: string = 'segment_tab';
  @State visualIndex: number = 0;
  onSelect: (index: number) => void = (_index: number): void => {};
  private switchTimer: number = -1;

  aboutToAppear(): void {
    this.visualIndex = this.selectedIndex;
  }

  aboutToDisappear(): void {
    this.cancelSwitch();
  }

  syncVisualIndex(): void {
    this.cancelSwitch();
    this.visualIndex = this.selectedIndex;
  }

  select(index: number): void {
    if (index < 0 || index >= this.labels.length || index === this.visualIndex) return;
    this.cancelSwitch();
    this.visualIndex = index;
    this.switchTimer = setTimeout(() => {
      this.switchTimer = -1;
      if (index !== this.selectedIndex) this.onSelect(index);
    }, MaterialSegmentTabs.SWITCH_DURATION);
  }

  cancelSwitch(): void {
    if (this.switchTimer >= 0) {
      clearTimeout(this.switchTimer);
      this.switchTimer = -1;
    }
  }

  innerWidth(): number {
    return Math.max(1, this.tabsWidth - MaterialSegmentTabs.INSET * 2);
  }

  segmentWidth(): number {
    return Math.max(1, this.innerWidth() / Math.max(1, this.labels.length));
  }

  build() {
    ImmersiveMaterialSurface({ surfaceWidth: this.tabsWidth, surfaceHeight: MaterialSegmentTabs.OUTER_HEIGHT,
      darkMode: this.appDarkMode, fallbackColor: ThemeRuntime.cardColor(this.appDarkMode),
      glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}` }) {
      Stack({ alignContent: Alignment.Start }) {
        Stack() {
          ImmersiveMaterialSurface({ surfaceWidth: this.segmentWidth(), surfaceHeight: MaterialSegmentTabs.INNER_HEIGHT,
            darkMode: this.appDarkMode, fallbackColor: ThemeRuntime.accentSurfaceColor(this.appDarkMode),
            glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}` }) {
            Stack()
          }
        }
        .id(`${this.idPrefix}_indicator`)
        .width(this.segmentWidth())
        .height(MaterialSegmentTabs.INNER_HEIGHT)
        .translate({ x: this.visualIndex * this.segmentWidth() })
        .animation({ duration: MaterialSegmentTabs.SWITCH_DURATION, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
        Row() {
          ForEach(this.labels, (label: string, index: number) => {
            Button(label, { type: ButtonType.Capsule, stateEffect: true })
              .id(`${this.idPrefix}_${index}`)
              .height(MaterialSegmentTabs.INNER_HEIGHT)
              .layoutWeight(1)
              .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
              .fontSize(AppFontSize.BODY)
              .fontWeight(this.visualIndex === index ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.visualIndex === index ? ThemeRuntime.accentColor(this.appDarkMode) :
                ThemeRuntime.subTextColor(this.appDarkMode))
              .backgroundColor(Color.Transparent)
              .accessibilitySelected(this.visualIndex === index)
              .onClick(() => { this.select(index); })
          }, (label: string) => label)
        }
        .width('100%')
        .height(MaterialSegmentTabs.INNER_HEIGHT)
      }
      .width(this.innerWidth())
      .height(MaterialSegmentTabs.INNER_HEIGHT)
    }
  }
}
