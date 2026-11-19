import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/** 首页主题背景图、顶栏磨砂与“我的”页搜索栏三个开关，显式落盘；AppStorage 只负责通知界面，默认都开启。 */
export class HomeBackdropSettingsStore {
  static readonly STORE_NAME: string = 'home_backdrop_settings';
  /** 所有页面顶栏背后的实时毛玻璃；关闭后 HeaderBackdrop 完全透明。 */
  static readonly KEY_HEADER_FROSTED: string = 'headerFrosted';
  /** “我的”页标题下的设置项搜索栏；关闭后不显示入口。 */
  static readonly KEY_MINE_SEARCH_ENTRY: string = 'mineSearchEntryVisible';
  private static revision: number = 0;
  private static frostedRevision: number = 0;
  private static searchEntryRevision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = HomeBackdropSettingsStore.revision;
    const store = await preferences.getPreferences(context, HomeBackdropSettingsStore.STORE_NAME);
    const frostedRevision = HomeBackdropSettingsStore.frostedRevision;
    const value = await store.get(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, true);
    const frosted = await store.get(HomeBackdropSettingsStore.KEY_HEADER_FROSTED, true);
    const searchEntryRevision = HomeBackdropSettingsStore.searchEntryRevision;
    const searchEntry = await store.get(HomeBackdropSettingsStore.KEY_MINE_SEARCH_ENTRY, true);
    if (searchEntryRevision === HomeBackdropSettingsStore.searchEntryRevision) {
      AppStorage.setOrCreate(HomeBackdropSettingsStore.KEY_MINE_SEARCH_ENTRY, searchEntry !== false);
    }
    if (frostedRevision === HomeBackdropSettingsStore.frostedRevision) {
      AppStorage.setOrCreate(HomeBackdropSettingsStore.KEY_HEADER_FROSTED, frosted !== false);
    }
    if (revision !== HomeBackdropSettingsStore.revision) return;
    AppStorage.setOrCreate(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, value !== false);
  }

  static saveHeaderFrosted(context: Context, frosted: boolean): Promise<void> {
    ++HomeBackdropSettingsStore.frostedRevision;
    AppStorage.setOrCreate(HomeBackdropSettingsStore.KEY_HEADER_FROSTED, frosted);
    const write = HomeBackdropSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, HomeBackdropSettingsStore.STORE_NAME);
      await store.put(HomeBackdropSettingsStore.KEY_HEADER_FROSTED, frosted);
      await store.flush();
    });
    HomeBackdropSettingsStore.writes = write.catch(() => {});
    return write;
  }

  static saveMineSearchEntry(context: Context, visible: boolean): Promise<void> {
    ++HomeBackdropSettingsStore.searchEntryRevision;
    AppStorage.setOrCreate(HomeBackdropSettingsStore.KEY_MINE_SEARCH_ENTRY, visible);
    const write = HomeBackdropSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, HomeBackdropSettingsStore.STORE_NAME);
      await store.put(HomeBackdropSettingsStore.KEY_MINE_SEARCH_ENTRY, visible);
      await store.flush();
    });
    HomeBackdropSettingsStore.writes = write.catch(() => {});
    return write;
  }

  static save(context: Context, enabled: boolean): Promise<void> {
    ++HomeBackdropSettingsStore.revision;
    AppStorage.setOrCreate(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, enabled);
    const write = HomeBackdropSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, HomeBackdropSettingsStore.STORE_NAME);
      await store.put(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, enabled);
      await store.flush();
    });
    HomeBackdropSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
