import { ImmersiveMaterialSurface } from './ImmersiveMaterialSurface';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';

/**
 * 二级页顶栏右侧的沉浸光感操作按钮，和左侧返回按钮同一种材质。
 * 传 label 时是文字胶囊（批量、选择、保存、点数等），否则是只有图标的圆钮。
 *   ImmersiveHeaderAction({ label: '选择', onTap: () => this.enterSelectionMode() })
 *   ImmersiveHeaderAction({ icon: $r('sys.symbol.trash'), accessibilityLabel: '清除', onTap: ... })
 * 页面自己用 margin 控制和屏幕右边的距离。
 */
@Component
export struct ImmersiveHeaderAction {
  static readonly SIZE: number = 40;
  private static readonly LABEL_PADDING: number = 16;

  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @Prop label: string = '';
  @Prop icon: Resource = $r('sys.symbol.more');
  /** 文字或图标颜色；为空时用主文字色。 */
  @Prop tint: string = '';
  @Prop actionEnabled: boolean = true;
  /** 为空时读 label。 */
  @Prop accessibilityLabel: string = '';
  onTap: () => void = () => {};

  build() {
    ImmersiveMaterialSurface({
      surfaceWidth: this.surfaceWidth(),
      surfaceHeight: ImmersiveHeaderAction.SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: ThemeRuntime.cardColor(this.appDarkMode),
      glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`
    }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.label) {
          Text(this.label)
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
            .maxLines(1)
        } else {
          SymbolGlyph(this.icon)
            .fontSize(20)
            .fontColor([this.contentColor()])
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.actionEnabled ? 1 : 0.45)
      .accessibilityGroup(true)
      .accessibilityText(this.accessibilityLabel || this.label)
      .onClick(() => {
        if (this.actionEnabled) this.onTap();
      })
    }
  }

  contentColor(): string {
    return this.tint || ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  /** 悬浮栏只接受具体宽度，按字符估算：中文按字号算宽，其余按字号的 0.6 倍。 */
  surfaceWidth(): number {
    if (!this.label) return ImmersiveHeaderAction.SIZE;
    let textWidth = 0;
    for (const char of this.label) {
      textWidth += char.charCodeAt(0) > 0xFF ? AppFontSize.BODY : AppFontSize.BODY * 0.6;
    }
    return Math.max(ImmersiveHeaderAction.SIZE,
      Math.ceil(textWidth) + ImmersiveHeaderAction.LABEL_PADDING * 2);
  }
}
