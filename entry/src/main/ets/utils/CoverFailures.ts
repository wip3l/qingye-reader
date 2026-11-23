/**
 * 确认取不到的封面地址。书带着封面地址但图取不到（站点关了、换了域名，或是别的设备上的本地路径）时，
 * 取图入口把它当作没有封面，继续往下用书籍自带封面或“没有封面时”的兜底。
 * 记录隔一段时间失效，届时会再试一次，站点恢复后原封面能回来。
 */
export class CoverFailures {
  static readonly RETRY_AFTER_MS: number = 2 * 24 * 60 * 60 * 1000;
  static readonly MAX_ENTRIES: number = 3000;
  private static failedAt: Map<string, number> = new Map();

  static has(url: string, now: number = Date.now()): boolean {
    if (!url || CoverFailures.failedAt.size === 0) return false;
    const at = CoverFailures.failedAt.get(url);
    return at !== undefined && now - at < CoverFailures.RETRY_AFTER_MS;
  }

  /** 记下一次失败；这个地址原先不算失败（没记过或已过期）时返回 true，调用方据此刷新界面。 */
  static mark(url: string, now: number = Date.now()): boolean {
    if (!url) return false;
    const fresh = !CoverFailures.has(url, now);
    CoverFailures.failedAt.delete(url);
    CoverFailures.failedAt.set(url, now);
    while (CoverFailures.failedAt.size > CoverFailures.MAX_ENTRIES) {
      const oldest = CoverFailures.failedAt.keys().next();
      if (oldest.done) break;
      CoverFailures.failedAt.delete(oldest.value);
    }
    return fresh;
  }

  /** 取到了：撤掉记录。原先算失败时返回 true。 */
  static clear(url: string, now: number = Date.now()): boolean {
    const failed = CoverFailures.has(url, now);
    CoverFailures.failedAt.delete(url);
    return failed;
  }

  /** 去掉其中确认取不到的地址。 */
  static usable(covers: string[], now: number = Date.now()): string[] {
    if (CoverFailures.failedAt.size === 0) return covers;
    return covers.filter((cover: string): boolean => !CoverFailures.has(cover, now));
  }

  static serialize(): string {
    const entries: (string | number)[][] = [];
    CoverFailures.failedAt.forEach((at: number, url: string): void => {
      entries.push([url, at]);
    });
    return JSON.stringify(entries);
  }

  /** 读入落盘的记录，过期的不要；格式不对时当作没有记录。 */
  static load(raw: string, now: number = Date.now()): void {
    const next = new Map<string, number>();
    try {
      const entries = JSON.parse(raw || '[]') as (string | number)[][];
      if (Array.isArray(entries)) {
        for (const entry of entries) {
          if (!Array.isArray(entry) || typeof entry[0] !== 'string' || typeof entry[1] !== 'number') continue;
          if (now - entry[1] < CoverFailures.RETRY_AFTER_MS) next.set(entry[0], entry[1]);
        }
      }
    } catch (_) {
      // 读不出来就从空的开始。
    }
    // 读盘期间已经记下的失败保留。
    CoverFailures.failedAt.forEach((at: number, url: string): void => {
      next.set(url, at);
    });
    CoverFailures.failedAt = next;
  }
}
