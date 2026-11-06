import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/** 首页主题背景图开关，显式落盘；AppStorage 只负责通知界面，默认开启。 */
export class HomeBackdropSettingsStore {
  static readonly STORE_NAME: string = 'home_backdrop_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = HomeBackdropSettingsStore.revision;
    const store = await preferences.getPreferences(context, HomeBackdropSettingsStore.STORE_NAME);
    const value = await store.get(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, true);
    if (revision !== HomeBackdropSettingsStore.revision) return;
    AppStorage.setOrCreate(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED, value !== false);
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
