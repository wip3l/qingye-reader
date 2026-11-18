import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 图文书里视频章的播放进度：按“书 + 章节地址”记秒数，只存本机、不同步。
 * 这类书的 durChapterIndex / durChapterPos 是阅读进度，播放页不能写它们。
 */
export class MixedVideoProgress {
  private static readonly STORE: string = 'mixed_video_progress';
  private static writes: Promise<void> = Promise.resolve();

  static async get(context: Context, bookUrl: string, chapterUrl: string): Promise<number> {
    try {
      const store = await preferences.getPreferences(context, MixedVideoProgress.STORE);
      const value = await store.get(MixedVideoProgress.keyOf(bookUrl, chapterUrl), 0);
      return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
    } catch (e) {
      return 0;
    }
  }

  static put(context: Context, bookUrl: string, chapterUrl: string, second: number): Promise<void> {
    const key = MixedVideoProgress.keyOf(bookUrl, chapterUrl);
    const value = Math.max(0, Math.floor(second));
    const write = MixedVideoProgress.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, MixedVideoProgress.STORE);
      await store.put(key, value);
      await store.flush();
    });
    MixedVideoProgress.writes = write.catch(() => {});
    return write;
  }

  /** Preferences 的键最长 1024 字节，地址可能更长：用两段 32 位哈希拼成定长键。 */
  private static keyOf(bookUrl: string, chapterUrl: string): string {
    const text = `${bookUrl}\n${chapterUrl}`;
    let a = 0x811c9dc5;
    let b = 5381;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      a = Math.imul(a ^ code, 0x01000193) >>> 0;
      b = (Math.imul(b, 33) + code) >>> 0;
    }
    return `v_${a.toString(16)}_${b.toString(16)}`;
  }
}
