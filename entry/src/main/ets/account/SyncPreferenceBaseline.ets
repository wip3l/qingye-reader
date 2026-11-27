import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 新装机时记下各项同步设置的初始内容摘要。
 *
 * 首次同步时，本机内容摘要仍等于这里记下的值，说明用户自安装以来没改过这项设置。这类设置不上传，
 * 直接用云端的，即使首次同步选了“本地为主”也一样：否则新装机的默认设置会覆盖云端和其他设备。
 *
 * 只在全新安装（安装时间等于更新时间）的第一次启动记录。升级安装的设备无从判断用户改没改过，
 * 不记录，首次同步照用户选的方式处理。摘要因版本升级等原因对不上时，同样按“改过”处理。
 */
export class SyncPreferenceBaseline {
  private static readonly STORE_NAME: string = 'cloud_sync_preference_baseline';
  private static readonly KEY_CHECKED: string = 'checked';
  private static readonly KEY_HASHES: string = 'hashes';

  /** 已判断过是否新装机（无论结果）。 */
  static async checked(context: Context): Promise<boolean> {
    const store = await preferences.getPreferences(context, SyncPreferenceBaseline.STORE_NAME);
    return (await store.get(SyncPreferenceBaseline.KEY_CHECKED, false)) === true;
  }

  /** hashes 为空表示不是新装机。 */
  static async save(context: Context, hashes: Record<string, string>): Promise<void> {
    const store = await preferences.getPreferences(context, SyncPreferenceBaseline.STORE_NAME);
    await store.put(SyncPreferenceBaseline.KEY_HASHES, JSON.stringify(hashes));
    await store.put(SyncPreferenceBaseline.KEY_CHECKED, true);
    await store.flush();
  }

  static async load(context: Context): Promise<Record<string, string>> {
    const store = await preferences.getPreferences(context, SyncPreferenceBaseline.STORE_NAME);
    const raw = await store.get(SyncPreferenceBaseline.KEY_HASHES, '');
    if (typeof raw !== 'string' || !raw) return {};
    try {
      const parsed = JSON.parse(raw) as Record<string, string>;
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (e) {
      return {};
    }
  }
}
