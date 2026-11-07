import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 字体设置里“标题预览”的示例标题。只存本机，不同步；空串表示用默认示例。 */
export class ReaderTitlePreviewStore {
  static readonly DEFAULT_TEXT: string = '第七十四章：卖鸭蛋，卖粽子喽';
  private static readonly STORE: string = 'reader_title_preview';
  private static readonly TEXT_KEY: string = 'titlePreviewText';
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<string> {
    const store = await preferences.getPreferences(context, ReaderTitlePreviewStore.STORE);
    const value = await store.get(ReaderTitlePreviewStore.TEXT_KEY, '');
    return typeof value === 'string' && value.length > 0 ? value : ReaderTitlePreviewStore.DEFAULT_TEXT;
  }

  static save(context: Context, text: string): Promise<void> {
    const write = ReaderTitlePreviewStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderTitlePreviewStore.STORE);
      await store.put(ReaderTitlePreviewStore.TEXT_KEY, text);
      await store.flush();
    });
    ReaderTitlePreviewStore.writes = write.catch(() => {});
    return write;
  }
}
