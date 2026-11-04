import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 有声书播放的设备设置。只存本机，不同步。离线下载相关的在 AudioOfflineSettingsStore。 */
export class AudioBookSettingsStore {
  private static readonly STORE: string = 'audio_book_settings';
  static readonly AUTO_PLAY_KEY: string = 'audioBookAutoPlay';
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
    const autoPlay = await store.get(AudioBookSettingsStore.AUTO_PLAY_KEY, true);
    AppStorage.setOrCreate(AudioBookSettingsStore.AUTO_PLAY_KEY, autoPlay !== false);
  }

  /** 打开有声书时是否直接开始播放。设置还没读出来时按默认的开启处理。 */
  static autoPlay(): boolean {
    return AppStorage.get<boolean>(AudioBookSettingsStore.AUTO_PLAY_KEY) !== false;
  }

  static saveAutoPlay(context: Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(AudioBookSettingsStore.AUTO_PLAY_KEY, value);
    const write = AudioBookSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
      await store.put(AudioBookSettingsStore.AUTO_PLAY_KEY, value);
      await store.flush();
    });
    AudioBookSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
