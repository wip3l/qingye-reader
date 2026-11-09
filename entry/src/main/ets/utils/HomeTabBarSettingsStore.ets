import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 首页底栏设置：样式（悬浮/平铺）与第四个页签（无/听/足迹），显式落盘；AppStorage 只负责通知界面。
 * 悬浮底栏要系统支持 HDS 页签，不支持时首页一律用平铺底栏，存的值不改。
 */
export class HomeTabBarSettingsStore {
  static readonly STORE_NAME: string = 'home_tab_bar_settings';
  static readonly KEY_STYLE: string = 'homeTabBarStyle';
  static readonly KEY_EXTRA_TAB: string = 'homeExtraTab';
  static readonly STYLE_FLOATING: string = 'floating';
  static readonly STYLE_FLAT: string = 'flat';
  static readonly EXTRA_NONE: string = 'none';
  static readonly EXTRA_LISTEN: string = 'listen';
  static readonly EXTRA_FOOTPRINT: string = 'footprint';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static normalizeStyle(value: string | undefined | null): string {
    return value === HomeTabBarSettingsStore.STYLE_FLAT ? HomeTabBarSettingsStore.STYLE_FLAT :
      HomeTabBarSettingsStore.STYLE_FLOATING;
  }

  static normalizeExtraTab(value: string | undefined | null): string {
    return value === HomeTabBarSettingsStore.EXTRA_LISTEN || value === HomeTabBarSettingsStore.EXTRA_FOOTPRINT ?
      value : HomeTabBarSettingsStore.EXTRA_NONE;
  }

  static async load(context: Context): Promise<void> {
    const revision = HomeTabBarSettingsStore.revision;
    const store = await preferences.getPreferences(context, HomeTabBarSettingsStore.STORE_NAME);
    const style = await store.get(HomeTabBarSettingsStore.KEY_STYLE, HomeTabBarSettingsStore.STYLE_FLOATING);
    const extra = await store.get(HomeTabBarSettingsStore.KEY_EXTRA_TAB, HomeTabBarSettingsStore.EXTRA_NONE);
    if (revision !== HomeTabBarSettingsStore.revision) return;
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_STYLE, HomeTabBarSettingsStore.normalizeStyle(String(style)));
    AppStorage.setOrCreate(HomeTabBarSettingsStore.KEY_EXTRA_TAB,
      HomeTabBarSettingsStore.normalizeExtraTab(String(extra)));
  }

  static saveStyle(context: Context, style: string): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_STYLE,
      HomeTabBarSettingsStore.normalizeStyle(style));
  }

  static saveExtraTab(context: Context, extra: string): Promise<void> {
    return HomeTabBarSettingsStore.save(context, HomeTabBarSettingsStore.KEY_EXTRA_TAB,
      HomeTabBarSettingsStore.normalizeExtraTab(extra));
  }

  private static save(context: Context, key: string, value: string): Promise<void> {
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
