import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 智感握姿开关显式落盘。PersistentStorage 在 onCreate 时还没有界面实例，关掉后重启不会被写回，
 * 所以 AppStorage 只负责通知界面，开关值以这里的 Preferences 为准。
 */
export class SmartGripSettingsStore {
  static readonly KEY: string = 'smartGripEnabled';
  static readonly STORE_NAME: string = 'smart_grip_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
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
