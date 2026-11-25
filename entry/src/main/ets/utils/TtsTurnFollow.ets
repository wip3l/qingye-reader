import { preferences } from '@kit.ArkData';

/**
 * 朗读中手动翻页后，朗读要不要跟到新页（存本机，三档）：
 * - now：立即跟随，从翻到的这一页页首重新读（原有做法，默认）；
 * - delay：先不打断，在一页停留 DELAY_MS 没再翻页才跟过来，期间可回到朗读处；
 * - off：不跟随，朗读接着读原处，要换位置时点“从本页听”。
 * 不跟随期间阅读页底部显示“回到朗读处 | 从本页听”胶囊。
 * 这个键单独存取（同 LocalTtsSelection），免得整体保存朗读设置的页面把它覆盖掉。
 */
export class TtsTurnFollow {
  static readonly NOW: string = 'now';
  static readonly DELAY: string = 'delay';
  static readonly OFF: string = 'off';
  static readonly STORAGE_KEY: string = 'ttsTurnFollow';
  static readonly DELAY_MS: number = 3000;
  static readonly LABELS: string[] = ['立即跟随', '停留 3 秒后', '不跟随'];
  private static readonly VALUES: string[] = [TtsTurnFollow.NOW, TtsTurnFollow.DELAY, TtsTurnFollow.OFF];
  private static readonly STORE_NAME: string = 'tts_settings';

  static async load(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, TtsTurnFollow.STORE_NAME);
      const value = await store.get(TtsTurnFollow.STORAGE_KEY, TtsTurnFollow.NOW) as string;
      AppStorage.setOrCreate(TtsTurnFollow.STORAGE_KEY, TtsTurnFollow.normalize(value));
    } catch (error) {
      console.warn('[TTS] load turn follow mode failed:', error);
      AppStorage.setOrCreate(TtsTurnFollow.STORAGE_KEY, TtsTurnFollow.NOW);
    }
  }

  static normalize(value: string): string {
    return TtsTurnFollow.VALUES.indexOf(value) >= 0 ? value : TtsTurnFollow.NOW;
  }

  static current(): string {
    return TtsTurnFollow.normalize(AppStorage.get<string>(TtsTurnFollow.STORAGE_KEY) || '');
  }

  static indexOf(value: string): number {
    return Math.max(0, TtsTurnFollow.VALUES.indexOf(TtsTurnFollow.normalize(value)));
  }

  static valueAt(index: number): string {
    return TtsTurnFollow.VALUES[index] ?? TtsTurnFollow.NOW;
  }

  static description(value: string): string {
    const mode = TtsTurnFollow.normalize(value);
    if (mode === TtsTurnFollow.DELAY) return '翻页后先不打断，在一页停留 3 秒没再翻才从这页读起';
    if (mode === TtsTurnFollow.OFF) return '朗读接着读原处，想换位置时点底部的“从本页听”';
    return '翻到哪页，朗读马上从那页页首读起';
  }

  static save(context: Context, value: string): void {
    const mode = TtsTurnFollow.normalize(value);
    AppStorage.setOrCreate(TtsTurnFollow.STORAGE_KEY, mode);
    preferences.getPreferences(context, TtsTurnFollow.STORE_NAME).then(async (store): Promise<void> => {
      await store.put(TtsTurnFollow.STORAGE_KEY, mode);
      await store.flush();
    }).catch((error: Error): void => {
      console.warn('[TTS] save turn follow mode failed:', error);
    });
  }
}
