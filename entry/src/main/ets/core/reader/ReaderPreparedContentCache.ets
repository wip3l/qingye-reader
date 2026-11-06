/**
 * 替换净化等预处理之后的正文，进程内共享。预处理在 TaskPool 里跑，一趟来回约 130ms，占了再次开书时正文就绪时间的大头；
 * 同一本书在进程内再次打开时直接取用，翻开封面前正文就已排好。键里带正文长度与哈希、规则数与规则更新时间，
 * 正文或规则变了自然失配，不需要主动失效；按书清理只是为了省内存。
 * 放在 core 模块而不是页面静态字段：pages/*.ets 里的类静态每次开页都是新的。
 */
export class ReaderPreparedContentCache {
  private static entries: Map<string, string> = new Map<string, string>();
  private static chars: number = 0;
  private static readonly MAX_ENTRIES: number = 32;
  private static readonly MAX_CHARS: number = 3000000;

  static key(bookUrl: string, chapterIndex: number, content: string, contentHash: number,
    rulesCount: number, rulesUpdateTime: number, textConvert: string = ''): string {
    return `${bookUrl}|${chapterIndex}_${content.length}_${contentHash}_${rulesCount}_${rulesUpdateTime}_${textConvert}`;
  }

  /** 命中时移到最新，淘汰从最旧开始。 */
  static get(key: string): string | undefined {
    const value = ReaderPreparedContentCache.entries.get(key);
    if (value === undefined) return undefined;
    ReaderPreparedContentCache.entries.delete(key);
    ReaderPreparedContentCache.entries.set(key, value);
    return value;
  }

  static set(key: string, value: string): void {
    const previous = ReaderPreparedContentCache.entries.get(key);
    if (previous !== undefined) {
      ReaderPreparedContentCache.entries.delete(key);
      ReaderPreparedContentCache.chars -= previous.length;
    }
    ReaderPreparedContentCache.entries.set(key, value);
    ReaderPreparedContentCache.chars += value.length;
    while (ReaderPreparedContentCache.entries.size > ReaderPreparedContentCache.MAX_ENTRIES ||
      (ReaderPreparedContentCache.chars > ReaderPreparedContentCache.MAX_CHARS &&
        ReaderPreparedContentCache.entries.size > 1)) {
      const oldest = ReaderPreparedContentCache.entries.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      const dropped = ReaderPreparedContentCache.entries.get(oldest) || '';
      ReaderPreparedContentCache.entries.delete(oldest);
      ReaderPreparedContentCache.chars -= dropped.length;
    }
  }

  /** 这本书的正文来源变了（手动刷新本章、登录态变化、规则更新）：丢掉它的条目，键失配本来也不会再命中。 */
  static forgetBook(bookUrl: string): void {
    const prefix = `${bookUrl}|`;
    const keys = Array.from(ReaderPreparedContentCache.entries.keys());
    for (const key of keys) {
      if (!key.startsWith(prefix)) continue;
      const dropped = ReaderPreparedContentCache.entries.get(key) || '';
      ReaderPreparedContentCache.entries.delete(key);
      ReaderPreparedContentCache.chars -= dropped.length;
    }
  }
}
