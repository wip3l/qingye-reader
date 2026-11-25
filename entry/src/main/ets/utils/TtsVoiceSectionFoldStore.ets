import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 音色管理页四个分区（离线、系统、云端、自定义）的折叠状态，只存本机。
 * 存的是收起的分区键，换行分隔；写进 Preferences 而不是 PersistentStorage：后者改过的值重启后会回到默认。
 */
export class TtsVoiceSectionFoldStore {
  static readonly LOCAL: string = 'local';
  static readonly SYSTEM: string = 'system';
  static readonly CLOUD: string = 'cloud';
  static readonly CUSTOM: string = 'custom';
  static readonly ALL: string[] = [
    TtsVoiceSectionFoldStore.LOCAL, TtsVoiceSectionFoldStore.SYSTEM,
    TtsVoiceSectionFoldStore.CLOUD, TtsVoiceSectionFoldStore.CUSTOM
  ];
  private static readonly STORE_NAME: string = 'tts_voice_sections';
  private static readonly KEY: string = 'folded';
  /** 进程内已知的值；null 表示还没读过。 */
  private static cached: string[] | null = null;
  private static writeQueue: Promise<void> = Promise.resolve();

  /** 只保留认识的分区键，按固定顺序、去重。 */
  static normalize(keys: string[]): string[] {
    return TtsVoiceSectionFoldStore.ALL.filter((key: string): boolean => keys.includes(key));
  }

  static parse(raw: string): string[] {
    return TtsVoiceSectionFoldStore.normalize((raw || '').split('\n').map((key: string): string => key.trim()));
  }

  static toggle(folded: string[], key: string): string[] {
    if (folded.includes(key)) return folded.filter((item: string): boolean => item !== key);
    return TtsVoiceSectionFoldStore.normalize(folded.concat([key]));
  }

  static async load(context: Context): Promise<string[]> {
    if (TtsVoiceSectionFoldStore.cached !== null) return TtsVoiceSectionFoldStore.cached.slice();
    try {
      const store = await preferences.getPreferences(context, TtsVoiceSectionFoldStore.STORE_NAME);
      const value = await store.get(TtsVoiceSectionFoldStore.KEY, '');
      // 读的途中用户已经点过折叠，就以点过的为准。
      if (TtsVoiceSectionFoldStore.cached === null) {
        TtsVoiceSectionFoldStore.cached = TtsVoiceSectionFoldStore.parse(typeof value === 'string' ? value : '');
      }
      return TtsVoiceSectionFoldStore.cached.slice();
    } catch (error) {
      console.warn('读取音色分区折叠状态失败:', error);
      return TtsVoiceSectionFoldStore.cached === null ? [] : TtsVoiceSectionFoldStore.cached.slice();
    }
  }

  static save(context: Context, folded: string[]): Promise<void> {
    const value = TtsVoiceSectionFoldStore.normalize(folded);
    TtsVoiceSectionFoldStore.cached = value;
    // 连续点击时按点击顺序落盘，最后一次为准。
    TtsVoiceSectionFoldStore.writeQueue = TtsVoiceSectionFoldStore.writeQueue.catch(() => {}).then(async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(context, TtsVoiceSectionFoldStore.STORE_NAME);
        await store.put(TtsVoiceSectionFoldStore.KEY, value.join('\n'));
        await store.flush();
      } catch (error) {
        console.warn('保存音色分区折叠状态失败:', error);
      }
    });
    return TtsVoiceSectionFoldStore.writeQueue;
  }
}
