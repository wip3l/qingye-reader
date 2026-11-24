import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { PlatformInfo } from '../platform/PlatformInfo';

/**
 * 智感握姿开关显式落盘。PersistentStorage 在 onCreate 时还没有界面实例，关掉后重启不会被写回，
 * 所以 AppStorage 只负责通知界面，开关值以这里的 Preferences 为准。
 */
export class SmartGripSettingsStore {
  static readonly KEY: string = 'smartGripEnabled';
  static readonly STORE_NAME: string = 'smart_grip_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  /** 握姿依赖系统的握持手检测，安卓上没有。 */
  static supported(): boolean {
    return !PlatformInfo.ANDROID;
  }

  static async load(context: Context): Promise<void> {
    if (!SmartGripSettingsStore.supported()) {
      AppStorage.setOrCreate(SmartGripSettingsStore.KEY, false);
      return;
    }
    const revision = SmartGripSettingsStore.revision;
    const store = await preferences.getPreferences(context, SmartGripSettingsStore.STORE_NAME);
    const value = await store.get(SmartGripSettingsStore.KEY, '');
    if (revision !== SmartGripSettingsStore.revision) return;
    if (typeof value !== 'boolean') {
      // 首次升级沿用旧 PersistentStorage 中仍可读取的值。
      await SmartGripSettingsStore.save(context, AppStorage.get<boolean>(SmartGripSettingsStore.KEY) ?? true);
      return;
    }
    AppStorage.setOrCreate(SmartGripSettingsStore.KEY, value);
  }

  static save(context: Context, enabled: boolean): Promise<void> {
    ++SmartGripSettingsStore.revision;
    AppStorage.setOrCreate(SmartGripSettingsStore.KEY, enabled);
    const write = SmartGripSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, SmartGripSettingsStore.STORE_NAME);
      await store.put(SmartGripSettingsStore.KEY, enabled);
      await store.flush();
    });
    SmartGripSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
