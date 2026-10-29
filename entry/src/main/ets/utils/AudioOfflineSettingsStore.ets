import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';

/** 有声书离线下载的设备设置：仅 Wi-Fi 下载、离线音频上限、边听边下章数。只存本机，不同步。 */
export class AudioOfflineSettingsStore {
  private static readonly STORE: string = 'audio_offline_settings';
  /** 上限选项（字节），0 表示不限。 */
  static readonly CAP_OPTIONS: number[] = [0, 2 * 1024 * 1024 * 1024, 5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024, 20 * 1024 * 1024 * 1024];
  /** 边听边下章数选项，0 表示关闭。 */
  static readonly PREFETCH_OPTIONS: number[] = [0, 3, 5, 10];
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, AudioOfflineSettingsStore.STORE);
    const wifiOnly = await store.get(AudioOfflineStore.WIFI_ONLY_KEY, false);
    const cap = await store.get(AudioOfflineStore.CAP_KEY, 0);
    const prefetch = await store.get(AudioOfflineStore.PREFETCH_KEY, 0);
    AppStorage.setOrCreate(AudioOfflineStore.WIFI_ONLY_KEY, wifiOnly === true);
    AppStorage.setOrCreate(AudioOfflineStore.CAP_KEY, typeof cap === 'number' ? Math.max(0, cap) : 0);
    AppStorage.setOrCreate(AudioOfflineStore.PREFETCH_KEY, typeof prefetch === 'number' ? Math.max(0, prefetch) : 0);
  }

  static saveWifiOnly(context: Context, value: boolean): Promise<void> {
    return AudioOfflineSettingsStore.save(context, AudioOfflineStore.WIFI_ONLY_KEY, value);
  }

  static saveCap(context: Context, bytes: number): Promise<void> {
    return AudioOfflineSettingsStore.save(context, AudioOfflineStore.CAP_KEY, Math.max(0, bytes));
  }

  static savePrefetch(context: Context, count: number): Promise<void> {
    return AudioOfflineSettingsStore.save(context, AudioOfflineStore.PREFETCH_KEY, Math.max(0, count));
  }

  static capLabel(bytes: number): string {
    return bytes > 0 ? `${Math.round(bytes / (1024 * 1024 * 1024))} GB` : '不限';
  }

  private static save(context: Context, key: string, value: boolean | number): Promise<void> {
    AppStorage.setOrCreate(key, value);
    const write = AudioOfflineSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, AudioOfflineSettingsStore.STORE);
      await store.put(key, value);
      await store.flush();
    });
    AudioOfflineSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
