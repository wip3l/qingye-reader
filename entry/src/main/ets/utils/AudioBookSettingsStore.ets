import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { TtsAudioSession } from './TtsAudioSession';

/** 有声书播放的设备设置，以及朗读和有声书共用的“与其他应用同时播放”。只存本机，不同步。离线下载相关的在 AudioOfflineSettingsStore。 */
export class AudioBookSettingsStore {
  private static readonly STORE: string = 'audio_book_settings';
  static readonly AUTO_PLAY_KEY: string = 'audioBookAutoPlay';
  static readonly MIX_WITH_OTHERS_KEY: string = TtsAudioSession.MIX_WITH_OTHERS_KEY;
  /** 字幕：当前章识别完后接着识别已下载的下一章开头。默认开。 */
  static readonly SUBTITLE_PREFETCH_KEY: string = 'audioSubtitlePrefetchNext';
  /** 播放面板选了“字幕”页签的书（bookUrl 列表，最近的在前）。 */
  static readonly SUBTITLE_BOOKS_KEY: string = 'audioSubtitleBooks';
  private static readonly SUBTITLE_BOOKS_LIMIT: number = 300;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
    const autoPlay = await store.get(AudioBookSettingsStore.AUTO_PLAY_KEY, true);
    AppStorage.setOrCreate(AudioBookSettingsStore.AUTO_PLAY_KEY, autoPlay !== false);
    const prefetch = await store.get(AudioBookSettingsStore.SUBTITLE_PREFETCH_KEY, true);
    AppStorage.setOrCreate(AudioBookSettingsStore.SUBTITLE_PREFETCH_KEY, prefetch !== false);
    const books = await store.get(AudioBookSettingsStore.SUBTITLE_BOOKS_KEY, '[]');
    AppStorage.setOrCreate(AudioBookSettingsStore.SUBTITLE_BOOKS_KEY, typeof books === 'string' ? books : '[]');
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

  static subtitlePrefetchNext(): boolean {
    return AppStorage.get<boolean>(AudioBookSettingsStore.SUBTITLE_PREFETCH_KEY) !== false;
  }

  static saveSubtitlePrefetchNext(context: Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(AudioBookSettingsStore.SUBTITLE_PREFETCH_KEY, value);
    return AudioBookSettingsStore.write(context, AudioBookSettingsStore.SUBTITLE_PREFETCH_KEY, value);
  }

  /** 这本书上次在播放面板里选的是不是“字幕”页签。 */
  static subtitleTab(bookUrl: string): boolean {
    return !!bookUrl && AudioBookSettingsStore.subtitleBooks().indexOf(bookUrl) >= 0;
  }

  static saveSubtitleTab(context: Context, bookUrl: string, subtitle: boolean): Promise<void> {
    if (!bookUrl) return Promise.resolve();
    const books = AudioBookSettingsStore.subtitleBooks().filter((url: string): boolean => url !== bookUrl);
    if (subtitle) books.unshift(bookUrl);
    const value = JSON.stringify(books.slice(0, AudioBookSettingsStore.SUBTITLE_BOOKS_LIMIT));
    AppStorage.setOrCreate(AudioBookSettingsStore.SUBTITLE_BOOKS_KEY, value);
    return AudioBookSettingsStore.write(context, AudioBookSettingsStore.SUBTITLE_BOOKS_KEY, value);
  }

  private static subtitleBooks(): string[] {
    try {
      const parsed = JSON.parse(AppStorage.get<string>(AudioBookSettingsStore.SUBTITLE_BOOKS_KEY) || '[]') as Object;
      return Array.isArray(parsed) ? (parsed as Object[]).filter((item: Object): boolean => typeof item === 'string')
        .map((item: Object): string => item as string) : [];
    } catch (_) {
      return [];
    }
  }

  private static write(context: Context, key: string, value: preferences.ValueType): Promise<void> {
    const write = AudioBookSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, AudioBookSettingsStore.STORE);
      await store.put(key, value);
      await store.flush();
    });
    AudioBookSettingsStore.writes = write.catch(() => {});
    return write;
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
