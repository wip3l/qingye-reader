import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { HexColor } from './HexColor';

/**
 * 首页底栏设置：样式（悬浮/平铺）、平铺底栏的不透明度与磨砂、第四个页签（无/听/足迹），显式落盘；
 * AppStorage 只负责通知界面。悬浮底栏要系统支持 HDS 页签，不支持时首页一律用平铺底栏，存的值不改。
 */
export class HomeTabBarSettingsStore {
  static readonly STORE_NAME: string = 'home_tab_bar_settings';
  static readonly KEY_STYLE: string = 'homeTabBarStyle';
  static readonly KEY_EXTRA_TAB: string = 'homeExtraTab';
  /** 平铺底栏底色的不透明度 0~100；低于 100 时页面内容延伸到底栏下面，主题背景图不会被纯色底栏截断。 */
  static readonly KEY_FLAT_OPACITY: string = 'homeTabBarFlatOpacity';
  /** 平铺底栏半透明时，先把底下的内容模糊再透出来。 */
  static readonly KEY_FLAT_FROSTED: string = 'homeTabBarFlatFrosted';
  static readonly STYLE_FLOATING: string = 'floating';
  static readonly STYLE_FLAT: string = 'flat';
  /** 早先短暂存在过的全透明样式，读到时迁成平铺 + 不透明度 0。 */
  private static readonly LEGACY_STYLE_TRANSPARENT: string = 'transparent';
  static readonly EXTRA_NONE: string = 'none';
  static readonly EXTRA_LISTEN: string = 'listen';
  static readonly EXTRA_FOOTPRINT: string = 'footprint';
  static readonly FLAT_OPACITY_DEFAULT: number = 100;
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static normalizeStyle(value: string | undefined | null): string {
    return value === HomeTabBarSettingsStore.STYLE_FLAT || value === HomeTabBarSettingsStore.LEGACY_STYLE_TRANSPARENT ?
      HomeTabBarSettingsStore.STYLE_FLAT : HomeTabBarSettingsStore.STYLE_FLOATING;
  }

  static normalizeExtraTab(value: string | undefined | null): string {
    return value === HomeTabBarSettingsStore.EXTRA_LISTEN || value === HomeTabBarSettingsStore.EXTRA_FOOTPRINT ?
      value : HomeTabBarSettingsStore.EXTRA_NONE;
  }

  static normalizeFlatOpacity(value: number | undefined | null): number {
    const number = Number(value);
    if (!Number.isFinite(number)) return HomeTabBarSettingsStore.FLAT_OPACITY_DEFAULT;
    return Math.max(0, Math.min(100, Math.round(number)));
  }

  /** 平铺底栏底色：主题卡片色（自带的透明度也算上）乘以用户设的不透明度；首页底栏和设置页示意条共用。 */
  static flatBarColor(cardColor: string, opacity: number): string {
    const base = HexColor.alpha(cardColor) / 255;
    return HexColor.withOpacity(cardColor, base * HomeTabBarSettingsStore.normalizeFlatOpacity(opacity) / 100);
  }

  /** 磨砂的模糊半径，和顶栏 HeaderBackdrop 一致；只模糊不着色，颜色仍由不透明度决定。 */
  static flatBarFrostEffect(frosted: boolean): BackgroundEffectOptions {
    const effect: BackgroundEffectOptions = { radius: frosted ? 32 : 0, saturation: frosted ? 1.05 : 1, brightness: 1 };
    return effect;
  }

  static async load(context: Context): Promise<void> {
    const revision = HomeTabBarSettingsStore.revision;
    const store = await preferences.getPreferences(context, HomeTabBarSettingsStore.STORE_NAME);
    const style = String(await store.get(HomeTabBarSettingsStore.KEY_STYLE, HomeTabBarSettingsStore.STYLE_FLOATING));
    const extra = await store.get(HomeTabBarSettingsStore.KEY_EXTRA_TAB, HomeTabBarSettingsStore.EXTRA_NONE);
    let opacity = HomeTabBarSettingsStore.normalizeFlatOpacity(Number(await store.get(
      HomeTabBarSettingsStore.KEY_FLAT_OPACITY, HomeTabBarSettingsStore.FLAT_OPACITY_DEFAULT)));
    const frosted = (await store.get(HomeTabBarSettingsStore.KEY_FLAT_FROSTED, false)) === true;
    if (style === HomeTabBarSettingsStore.LEGACY_STYLE_TRANSPARENT) {
      opacity = 0;
      await store.put(HomeTabBarSettingsStore.KEY_STYLE, HomeTabBarSettingsStore.STYLE_FLAT);
      await store.put(HomeTabBarSettingsStore.KEY_FLAT_OPACITY, opacity);
      await store.flush();
    }
    if (revision !== HomeTabBarSettingsStore.revision) return;
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_STYLE, HomeTabBarSettingsStore.normalizeStyle(style));
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_EXTRA_TAB,
      HomeTabBarSettingsStore.normalizeExtraTab(String(extra)));
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_FLAT_OPACITY, opacity);
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_FLAT_FROSTED, frosted);
  }

  static saveStyle(context: Context, style: string): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_STYLE,
      HomeTabBarSettingsStore.normalizeStyle(style));
  }

  static saveExtraTab(context: Context, extra: string): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_EXTRA_TAB,
      HomeTabBarSettingsStore.normalizeExtraTab(extra));
  }

  static saveFlatOpacity(context: Context, opacity: number): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_FLAT_OPACITY,
      HomeTabBarSettingsStore.normalizeFlatOpacity(opacity));
  }

  static saveFlatFrosted(context: Context, frosted: boolean): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_FLAT_FROSTED, frosted);
  }

  private static save(context: Context, key: string, value: string | number | boolean): Promise<void> {
    ++HomeTabBarSettingsStore.revision;
    AppStorage.setOrCreate(key, value);
    const write = HomeTabBarSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, HomeTabBarSettingsStore.STORE_NAME);
      await store.put(key, value);
      await store.flush();
    });
    HomeTabBarSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
