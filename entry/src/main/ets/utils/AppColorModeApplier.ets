import { common, ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 应用级深浅色的唯一出口。applicationContext.setColorMode 每调一次，ArkUI 都会把整棵组件树（连同栈里的首页）
 * 强制重建一遍，手机上一次两百多毫秒。setColorMode 会同步回调 EntryAbility.onConfigurationUpdate，那里还要按
 * 当前模式再设一遍；各页面自己直接调用时它记着的是旧值，同样的模式就会再设一次、多重建一遍。所以只在真的变了时才调。
 */
export class AppColorModeApplier {
  private static applied: number = -1;

  static colorModeFor(mode: string): ConfigurationConstant.ColorMode {
    if (mode === 'dark') return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (mode === 'light') return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  static apply(context: common.Context, colorMode: ConfigurationConstant.ColorMode): void {
    if (AppColorModeApplier.applied === colorMode) return;
    AppColorModeApplier.applied = colorMode;
    context.getApplicationContext().setColorMode(colorMode);
  }
}
