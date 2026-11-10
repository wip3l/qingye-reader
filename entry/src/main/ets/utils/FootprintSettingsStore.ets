import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 足迹页内容（footprintLayout，JSON 串，空串是默认）和本月日历收起状态显式落盘。
 * PersistentStorage 在 onCreate 时还没有界面实例，改过的值重启后会回到默认，
 * 所以 AppStorage 只负责通知界面，值以这里的 Preferences 为准。
 */
export class FootprintSettingsStore {
  static readonly LAYOUT_KEY: string = 'footprintLayout';
  static readonly MONTH_COLLAPSED_KEY: string = 'footprintMonthCollapsed';
  static readonly STORE_NAME: string = 'footprint_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = FootprintSettingsStore.revision;
    const store = await preferences.getPreferences(context, FootprintSettingsStore.STORE_NAME);
    // 空串是合法值（默认布局），所以用 has 区分“存过空串”和“从没存过”。
    const hasLayout = await store.has(FootprintSettingsStore.LAYOUT_KEY);
    const layout = await store.get(FootprintSettingsStore.LAYOUT_KEY, '');
    const collapsed = await store.get(FootprintSettingsStore.MONTH_COLLAPSED_KEY, '');
    // 启动途中用户已经改过，就不拿旧值盖回去。
    if (revision !== FootprintSettingsStore.revision) return;
    // 首次升级时偏好里没有，沿用旧 PersistentStorage 中仍可读取的值。
    if (hasLayout && typeof layout === 'string') {
      AppStorage.setOrCreate<string>(FootprintSettingsStore.LAYOUT_KEY, layout);
    } else {
      await FootprintSettingsStore.saveLayout(context,
        AppStorage.get<string>(FootprintSettingsStore.LAYOUT_KEY) ?? '');
    }
    if (typeof collapsed === 'boolean') {
      AppStorage.setOrCreate<boolean>(FootprintSettingsStore.MONTH_COLLAPSED_KEY, collapsed);
    } else {
      await FootprintSettingsStore.saveMonthCollapsed(context,
        AppStorage.get<boolean>(FootprintSettingsStore.MONTH_COLLAPSED_KEY) ?? false);
    }
  }

  static saveLayout(context: Context, raw: string): Promise<void> {
    AppStorage.setOrCreate<string>(FootprintSettingsStore.LAYOUT_KEY, raw);
    return FootprintSettingsStore.write(context, FootprintSettingsStore.LAYOUT_KEY, raw);
  }

  static saveMonthCollapsed(context: Context, collapsed: boolean): Promise<void> {
    AppStorage.setOrCreate<boolean>(FootprintSettingsStore.MONTH_COLLAPSED_KEY, collapsed);
    return FootprintSettingsStore.write(context, FootprintSettingsStore.MONTH_COLLAPSED_KEY, collapsed);
  }

  private static write(context: Context, key: string, value: string | boolean): Promise<void> {
    ++FootprintSettingsStore.revision;
    const write = FootprintSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, FootprintSettingsStore.STORE_NAME);
      await store.put(key, value);
      await store.flush();
    });
    FootprintSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
