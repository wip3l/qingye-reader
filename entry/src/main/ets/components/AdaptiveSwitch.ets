import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/**
 * Theme-aware switch. API 26+ lets the system Toggle render its immersive
 * light-sense surface; older versions keep the standard Toggle appearance.
 * The checked color follows the app theme's button color unless selectedColor
 * is passed (reader overlays pass the reading theme's color).
 */
@Component
export struct AdaptiveSwitch {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop isOn: boolean = false;
  @Prop selectedColor?: ResourceColor;
  @Prop switchEnabled: boolean = true;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  accessibilityLabel: string = '';
  onChange: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    if (ImmersiveMaterialRuntime.supportsHds()) {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.checkedColor())
        .enabled(this.switchEnabled)
        .systemMaterial(this.material())
        .borderRadius(999)
        .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.appDarkMode))
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    } else {
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.checkedColor())
        .enabled(this.switchEnabled)
        .accessibilityText(this.accessibilityLabel)
        .onChange((isOn: boolean) => this.onChange(isOn));
    }
  }

  private checkedColor(): ResourceColor {
    if (this.selectedColor !== undefined) return this.selectedColor;
    // Reading themeRevision re-resolves the color when the theme pack changes without a dark-mode flip.
    return this.themeRevision >= 0 ? ThemeRuntime.buttonColor(this.appDarkMode) : '';
  }

  private material(): uiMaterial.Material {
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(this.immersiveLightLevel),
      materialColor: '#22FFFFFF',
      applyShadow: true,
      // 开关的手势与动画由原生 Toggle 管理。通用材质只提供静态表面，
      // 不叠加第二套触摸反馈，也不在触摸过程中替换材质、打断 Toggle 的切换。
      interactive: false,
      lightEffect: null
    }, this.immersiveLightLevel);
  }
}
