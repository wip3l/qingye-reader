import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';

/** 与账号同步共用安装身份。名称可变，不能作为统计记录的主键。 */
export class ReadStatsDevice {
  static readonly LEGACY_ID: string = 'legacy-import';
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
    const store = await preferences.getPreferences(context, 'account_cloud_sync_state');
    const existing = await store.get('device_id', '');
    if (typeof existing === 'string' && existing) return existing;
    const id = util.generateRandomUUID();
    await store.put('device_id', id);
    await store.flush();
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
