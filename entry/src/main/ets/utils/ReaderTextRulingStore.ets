import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderTextRuling, ReaderTextRulingSettings } from '../core/reader/ReaderTextRuling';

/**
 * 正文文字划线的本机设置，整份存成一条 JSON。与其他排版参数一样不进云同步。
 * 缓存放在本模块（进程单例），阅读页每次打开都能直接拿到上次的值。
 */
export class ReaderTextRulingStore {
  private static readonly STORE_NAME: string = 'reader_text_ruling';
  private static readonly KEY: string = 'settings';
  private static cached: ReaderTextRulingSettings | null = null;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<ReaderTextRulingSettings> {
    if (ReaderTextRulingStore.cached) return ReaderTextRuling.copy(ReaderTextRulingStore.cached);
    let settings = new ReaderTextRulingSettings();
    try {
      const store = await preferences.getPreferences(context, ReaderTextRulingStore.STORE_NAME);
      const raw = await store.get(ReaderTextRulingStore.KEY, '');
      settings = ReaderTextRuling.decode(typeof raw === 'string' ? raw : '');
    } catch (error) {
      console.warn('读取文字划线设置失败:', error);
    }
    // 读盘期间用户可能已经改过（save 先更新缓存），以缓存为准。
    if (ReaderTextRulingStore.cached) return ReaderTextRuling.copy(ReaderTextRulingStore.cached);
    ReaderTextRulingStore.cached = ReaderTextRuling.copy(settings);
    return settings;
  }

  static save(context: Context, settings: ReaderTextRulingSettings): Promise<void> {
    const value = ReaderTextRuling.copy(settings);
    ReaderTextRulingStore.cached = value;
    const raw = ReaderTextRuling.encode(value);
    const write = ReaderTextRulingStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderTextRulingStore.STORE_NAME);
      await store.put(ReaderTextRulingStore.KEY, raw);
      await store.flush();
    });
    ReaderTextRulingStore.writes = write.catch((error: Error) => {
      console.warn('保存文字划线设置失败:', error);
    });
    return ReaderTextRulingStore.writes;
  }
}
