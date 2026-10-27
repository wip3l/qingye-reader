import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';

/** 与账号同步共用安装身份。名称可变，不能作为统计记录的主键。 */
export class ReadStatsDevice {
  static readonly LEGACY_ID: string = 'legacy-import';
  private static readonly IDENTITY_STORE: string = 'account_device_identity';
  private static readonly LEGACY_STORE: string = 'account_cloud_sync_state';
  private static readonly ID_KEY: string = 'device_id';
  private static pending: Promise<string> | null = null;

  static id(context: Context): Promise<string> {
    if (!ReadStatsDevice.pending) {
      ReadStatsDevice.pending = ReadStatsDevice.loadId(context).catch((error: Error): never => {
        ReadStatsDevice.pending = null;
        throw error;
      });
    }
    return ReadStatsDevice.pending;
  }

  private static async loadId(context: Context): Promise<string> {
    // Installation identity must outlive resets/rebuilds of the much larger sync-state store.
    // Keep this store out of portable backups: importing it elsewhere would clone this device.
    const store = await preferences.getPreferences(context, ReadStatsDevice.IDENTITY_STORE);
    const existing = await store.get(ReadStatsDevice.ID_KEY, '');
    if (typeof existing === 'string' && existing) {
      // A previous flush may have failed after put updated the in-process preference cache.
      await store.flush();
      return existing;
    }
    const legacyStore = await preferences.getPreferences(context, ReadStatsDevice.LEGACY_STORE);
    const legacyId = await legacyStore.get(ReadStatsDevice.ID_KEY, '');
    const id = typeof legacyId === 'string' && legacyId ? legacyId : util.generateRandomUUID();
    await store.put(ReadStatsDevice.ID_KEY, id);
    await store.flush();
    // Preserve compatibility with old builds; migration must not register a new cloud device.
    if (!legacyId) {
      await legacyStore.put(ReadStatsDevice.ID_KEY, id);
      await legacyStore.flush();
    }
    return id;
  }

  static displayName(): string {
    try {
      return deviceInfo.marketName || deviceInfo.productModel || '本机';
    } catch (_) {
      return '本机';
    }
  }
}
