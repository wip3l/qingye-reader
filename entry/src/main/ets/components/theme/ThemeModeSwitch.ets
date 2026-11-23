import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

const SWITCH_INSET: number = 4;

/**
 * 主题相关页面共用的浅色/深色切换：沉浸光感胶囊底板上两段等宽选项（图标 + 文字），
 * 选中项下面垫一块滑动的强调色底。只切页面正在编辑或预览的那一套，不改应用当前显示模式。
 *
 * 颜色由调用方传入：主题设置页用应用当前配色，主题详情用正在预览的那套主题配色。
 */
@Component
export struct ThemeModeSwitch {
  /** 当前选中的是否为深色。 */
  @Prop selectedDark: boolean = false;
  /** 底板材质跟随的显示模式。 */
  @Prop darkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop subTextColor: string = '#888888';
  /** 没有沉浸光感材质时的底色。 */
  @Prop fallbackColor: string = '#FFFFFF';
  @Prop switchWidth: number = 152;
  @Prop switchHeight: number = 40;
  /** 读屏文字前缀，例如“预览”“编辑”。 */
  @Prop accessibilityPrefix: string = '预览';
  onChange: (dark: boolean) => void = () => {
  };

  optionWidth(): number {
    return this.switchWidth / 2;
  }

  /** 选中底：强调色加透明度，深色底上略浓一些。 */
  selectionColor(): string {
    const accent = this.accentColor || '';
    if (/^#[0-9A-Fa-f]{6}$/.test(accent)) {
      return `#${this.darkMode ? '33' : '1F'}${accent.substring(1)}`;
    }
    if (/^#[0-9A-Fa-f]{8}$/.test(accent)) {
      return `#${this.darkMode ? '33' : '1F'}${accent.substring(3)}`;
    }
    return ThemeRuntime.accentSurfaceColor(this.darkMode);
  }

  glowColor(): string {
    const accent = this.accentColor || '';
    if (/^#[0-9A-Fa-f]{6}$/.test(accent)) return `#40${accent.substring(1)}`;
    if (/^#[0-9A-Fa-f]{8}$/.test(accent)) return `#40${accent.substring(3)}`;
    return '#33FFFFFF';
  }

  build() {
    Stack() {
      this.surface()
    }
    .width(this.switchWidth)
    .height(this.switchHeight)
  }

  @Builder
  surface() {
    ImmersiveMaterialSurface({
      surfaceWidth: this.switchWidth,
      surfaceHeight: this.switchHeight,
      darkMode: this.darkMode,
      fallbackColor: this.fallbackColor,
      glowColor: this.glowColor()
    }) {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(this.optionWidth() - SWITCH_INSET * 2)
          .height(this.switchHeight - SWITCH_INSET * 2)
          .borderRadius((this.switchHeight - SWITCH_INSET * 2) / 2)
          .backgroundColor(this.selectionColor())
          .translate({ x: SWITCH_INSET + (this.selectedDark ? this.optionWidth() : 0) })
          .animation({ duration: 280, curve: Curve.Friction })
          .hitTestBehavior(HitTestMode.None)
        Row() {
          this.option(false)
          this.option(true)
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  option(dark: boolean) {
    Row({ space: AppSpacing.XS }) {
      SymbolGlyph(dark ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
        .fontSize(15)
        .fontColor([this.selectedDark === dark ? this.accentColor : this.subTextColor])
      Text(dark ? '深色' : '浅色')
        .fontSize(AppFontSize.BODY)
        .fontWeight(this.selectedDark === dark ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedDark === dark ? this.accentColor : this.subTextColor)
        .maxLines(1)
        .animation({ duration: 180, curve: Curve.Friction })
    }
    .width(this.optionWidth())
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(`${this.accessibilityPrefix}${dark ? '深色' : '浅色'}模式`)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .accessibilitySelected(this.selectedDark === dark)
    .onClick(() => {
      if (this.selectedDark !== dark) this.onChange(dark);
    })
  }
}
