import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * “隐藏底部小白条”开关显式落盘。PersistentStorage 在 onCreate 时还没有界面实例，改过的值重启后会回到默认，
 * 所以 AppStorage 只负责通知各阅读页，开关值以这里的 Preferences 为准。
 */
export class ReaderNavIndicatorStore {
  static readonly KEY: string = 'readerHideNavIndicator';
  static readonly STORE_NAME: string = 'reader_nav_indicator_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = ReaderNavIndicatorStore.revision;
    const store = await preferences.getPreferences(context, ReaderNavIndicatorStore.STORE_NAME);
    const value = await store.get(ReaderNavIndicatorStore.KEY, false);
    if (revision !== ReaderNavIndicatorStore.revision) return;
    AppStorage.setOrCreate(ReaderNavIndicatorStore.KEY, value === true);
  }

  static save(context: Context, hidden: boolean): Promise<void> {
    ++ReaderNavIndicatorStore.revision;
    AppStorage.setOrCreate(ReaderNavIndicatorStore.KEY, hidden);
    const write = ReaderNavIndicatorStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderNavIndicatorStore.STORE_NAME);
      await store.put(ReaderNavIndicatorStore.KEY, hidden);
      await store.flush();
    });
    ReaderNavIndicatorStore.writes = write.catch(() => {});
    return write;
  }
}
