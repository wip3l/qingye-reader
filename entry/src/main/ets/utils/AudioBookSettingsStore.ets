import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { TtsAudioSession } from './TtsAudioSession';

/** 有声书播放的设备设置，以及朗读和有声书共用的“与其他应用同时播放”。只存本机，不同步。离线下载相关的在 AudioOfflineSettingsStore。 */
export class AudioBookSettingsStore {
  private static readonly STORE: string = 'audio_book_settings';
  static readonly AUTO_PLAY_KEY: string = 'audioBookAutoPlay';
  static readonly MIX_WITH_OTHERS_KEY: string = TtsAudioSession.MIX_WITH_OTHERS_KEY;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
    const autoPlay = await store.get(AudioBookSettingsStore.AUTO_PLAY_KEY, true);
    AppStorage.setOrCreate(AudioBookSettingsStore.AUTO_PLAY_KEY, autoPlay !== false);
    const mix = await store.get(AudioBookSettingsStore.MIX_WITH_OTHERS_KEY, false);
    AppStorage.setOrCreate(AudioBookSettingsStore.MIX_WITH_OTHERS_KEY, mix === true);
    TtsAudioSession.refreshConcurrencyMode();
  }

  /** 朗读和有声书共用：开启后与其他应用的声音同时播放。会话读的是 AppStorage 里的同名键，这里改完通知它重新激活。 */
  static saveMixWithOthers(context: Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(AudioBookSettingsStore.MIX_WITH_OTHERS_KEY, value);
    TtsAudioSession.refreshConcurrencyMode();
    const write = AudioBookSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
      await store.put(AudioBookSettingsStore.MIX_WITH_OTHERS_KEY, value);
      await store.flush();
    });
    AudioBookSettingsStore.writes = write.catch(() => {});
    return write;
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
