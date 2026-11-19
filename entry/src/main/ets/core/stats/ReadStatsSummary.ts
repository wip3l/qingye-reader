import { ReadStatsRow } from '../../model/data/AppDatabase';

export class ReadStatsPeriod {
  startKey: string = '';
  endKey: string = '';
  startTs: number = 0;
  endTs: number = 0;
}

export class ReadStatsBar {
  key: string = '';
  label: string = '';
  durationMs: number = 0;
}

export class ReadStatsRank {
  bookKey: string = '';
  recordBookKeys: string[] = [];
  bookUrl: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  onShelf: boolean = false;
  durationMs: number = 0;
  percent: number = 0;
  rank: number = 0;
}

class ReadWorkEdition {
  name: string = '';
  author: string = '';
  onShelf: boolean = false;
}

class ReadWorkTitleGroup {
  authored: Set<string> = new Set<string>();
  shelfWorks: Set<string> = new Set<string>();
  looseKeys: string[] = [];
}

/**
 * 把同一部作品的不同记录认到一起。记录键标识的是某个书源上的那一版，换源、换站后会变，
 * 同一本书在不同站点还可能一个是简体书名、一个是繁体书名，所以比较前先统一全半角、空白和简繁。
 */
export class ReadWorkIdentity {
  /** 书名或作者的比较写法；fold 是繁→简转换，没有字典时传 null，只统一全半角与空白。 */
  static text(value: string, fold: ((text: string) => string) | null): string {
    const normalized = (value || '').normalize('NFKC').trim().replace(/\s+/g, ' ');
    return fold ? fold(normalized) : normalized;
  }

  static workKey(name: string, author: string): string {
    return `work:${JSON.stringify([name, author])}`;
  }

  /**
   * 记录键 → 作品标识。书名和作者都有的按“书名 + 作者”归并。
   * 缺作者的记录只在不会认错时才并：同名的带作者作品最多一部，并且书架上同名的书恰好一本。
   */
  static resolve(rows: ReadStatsRow[], fold: ((text: string) => string) | null): Map<string, string> {
    const editions = new Map<string, ReadWorkEdition>();
    rows.forEach((row: ReadStatsRow): void => {
      const name = ReadWorkIdentity.text(row.name, fold);
      if (!name || name === '书名未留存') return;
      const known = editions.get(row.bookKey);
      if (known && !row.onShelf) return;
      const edition = new ReadWorkEdition();
      edition.name = name;
      edition.author = ReadWorkIdentity.text(row.author, fold);
      edition.onShelf = row.onShelf;
      editions.set(row.bookKey, edition);
    });
    const identities = new Map<string, string>();
    const titles = new Map<string, ReadWorkTitleGroup>();
    editions.forEach((edition: ReadWorkEdition, bookKey: string): void => {
      let group = titles.get(edition.name);
      if (!group) {
        group = new ReadWorkTitleGroup();
        titles.set(edition.name, group);
      }
      if (edition.author) {
        const work = ReadWorkIdentity.workKey(edition.name, edition.author);
        identities.set(bookKey, work);
        group.authored.add(work);
        if (edition.onShelf) group.shelfWorks.add(work);
      } else {
        group.looseKeys.push(bookKey);
        if (edition.onShelf) group.shelfWorks.add(`record:${bookKey}`);
      }
    });
    titles.forEach((group: ReadWorkTitleGroup, name: string): void => {
      if (group.looseKeys.length === 0 || group.authored.size > 1 || group.shelfWorks.size !== 1) return;
      const target = group.authored.size === 1 ? Array.from(group.authored)[0] : `title:${name}`;
      group.looseKeys.forEach((bookKey: string): void => {
        identities.set(bookKey, target);
      });
    });
    return identities;
  }
}

export class ReadStatsSummary {
  totalMs: number = 0;
  activeDays: number = 0;
  averageMs: number = 0;
  items: ReadStatsRank[] = [];
  bars: ReadStatsBar[] = [];

  static dayKey(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}-${ReadStatsSummary.pad(d.getMonth() + 1)}-${ReadStatsSummary.pad(d.getDate())}`;
  }

  static dayDate(key: string): Date {
    const parts = key.split('-').map((part: string): number => Number(part));
    return new Date(parts[0], parts[1] - 1, parts[2]);
  }

  private static pad(n: number): string { return n < 10 ? `0${n}` : `${n}`; }

  static range(mode: string, anchor: number): ReadStatsPeriod {
    const d = new Date(anchor);
    let start = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    let end = new Date(start);
    if (mode === 'week') {
      start.setDate(start.getDate() - (start.getDay() + 6) % 7);
      end = new Date(start);
      end.setDate(end.getDate() + 6);
    } else if (mode === 'month') {
      start = new Date(d.getFullYear(), d.getMonth(), 1);
      end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    } else if (mode === 'year') {
      start = new Date(d.getFullYear(), 0, 1);
      end = new Date(d.getFullYear(), 11, 31);
    }
    const result = new ReadStatsPeriod();
    result.startTs = start.getTime();
    result.endTs = end.getTime();
    result.startKey = mode === 'all' ? '0000-00-00' : ReadStatsSummary.dayKey(result.startTs);
    result.endKey = mode === 'all' ? '9999-99-99' : ReadStatsSummary.dayKey(result.endTs);
    return result;
  }

  static shift(mode: string, anchor: number, step: number): number {
    const d = new Date(anchor);
    if (mode === 'day' || mode === 'week') {
      return new Date(d.getFullYear(), d.getMonth(), d.getDate() + step * (mode === 'week' ? 7 : 1)).getTime();
    }
    if (mode === 'month') return new Date(d.getFullYear(), d.getMonth() + step, 1).getTime();
    if (mode === 'year') return new Date(d.getFullYear() + step, 0, 1).getTime();
    return anchor;
  }

  static duration(ms: number): string {
    if (ms > 0 && ms < 60000) return '不足1分钟';
    const minutes = Math.max(0, Math.floor(ms / 60000));
    if (minutes < 60) return `${minutes}分钟`;
    return `${Math.floor(minutes / 60)}小时${minutes % 60 ? `${minutes % 60}分` : ''}`;
  }

  static calculate(rows: ReadStatsRow[], mode: string, anchor: number, now: number,
    fold: ((text: string) => string) | null = null): ReadStatsSummary {
    const result = new ReadStatsSummary();
    const books = new Map<string, ReadStatsRank>();
    const dates = new Set<string>();
    const buckets = new Map<string, ReadStatsBar>();
    const range = ReadStatsSummary.range(mode, anchor);
    // Record/sync keys identify a source edition. Ranking identifies the work, so changing sources or
    // script (简/繁) does not split its duration. Keep original keys for scoped deletion.
    const identities = ReadWorkIdentity.resolve(rows, fold);
    let firstKey = '';
    rows.forEach((row: ReadStatsRow): void => {
      if (row.durationMs <= 0 || row.dayKey < range.startKey || row.dayKey > range.endKey) return;
      result.totalMs += row.durationMs;
      dates.add(row.dayKey);
      if (!firstKey || row.dayKey < firstKey) firstKey = row.dayKey;
      const identity = identities.get(row.bookKey) || `record:${row.bookKey}`;
      let item = books.get(identity);
      if (!item) {
        item = new ReadStatsRank();
        item.bookKey = row.bookKey;
        item.bookUrl = row.bookUrl;
        item.name = row.name || '书名未留存';
        item.author = row.author;
        item.coverUrl = row.coverUrl;
        books.set(identity, item);
      }
      if (!item.recordBookKeys.includes(row.bookKey)) item.recordBookKeys.push(row.bookKey);
      // Prefer the actionable local shelf edition, including its cover, regardless of query row order.
      if (row.onShelf || !item.name || item.name === '书名未留存') {
        if (row.name) item.name = row.name;
        if (row.author) item.author = row.author;
        if (row.bookUrl) item.bookUrl = row.bookUrl;
      }
      if (row.coverUrl && (row.onShelf || !item.coverUrl)) item.coverUrl = row.coverUrl;
      item.onShelf = item.onShelf || row.onShelf;
      item.durationMs += row.durationMs;
      const key = mode === 'all' ? row.dayKey.substring(0, 4) :
        mode === 'year' ? row.dayKey.substring(0, 7) : row.dayKey;
      let bar = buckets.get(key);
      if (!bar) {
        bar = new ReadStatsBar();
        bar.key = key;
        buckets.set(key, bar);
      }
      bar.durationMs += row.durationMs;
    });
    result.activeDays = dates.size;
    result.items = Array.from(books.values()).sort((a: ReadStatsRank, b: ReadStatsRank): number => b.durationMs - a.durationMs);
    result.items.forEach((item: ReadStatsRank, index: number): void => {
      item.rank = index + 1;
      item.percent = result.totalMs > 0 ? item.durationMs * 100 / result.totalMs : 0;
    });
    const first = mode === 'all' ? ReadStatsSummary.dayDate(firstKey || ReadStatsSummary.dayKey(now)) : new Date(range.startTs);
    const last = new Date(Math.min(mode === 'all' ? now : range.endTs, now));
    // 日历日相减使用 UTC 日期，避免夏令时切换使一天变成 23/25 小时。
    const days = Math.max(1, Math.round((Date.UTC(last.getFullYear(), last.getMonth(), last.getDate()) -
      Date.UTC(first.getFullYear(), first.getMonth(), first.getDate())) / 86400000) + 1);
    result.averageMs = result.totalMs / days;
    if (mode === 'day') return result;
    const cursor = new Date(first);
    if (mode === 'all') { cursor.setMonth(0, 1); }
    if (mode === 'year') { cursor.setDate(1); }
    const chartEnd = mode === 'all' ? now : range.endTs;
    while (cursor.getTime() <= chartEnd) {
      const dateKey = ReadStatsSummary.dayKey(cursor.getTime());
      const key = mode === 'all' ? dateKey.substring(0, 4) : mode === 'year' ? dateKey.substring(0, 7) : dateKey;
      const bar = buckets.get(key) || new ReadStatsBar();
      bar.key = key;
      bar.label = mode === 'all' ? `${cursor.getFullYear()}` : mode === 'year' ? `${cursor.getMonth() + 1}` :
        mode === 'week' ? ['日', '一', '二', '三', '四', '五', '六'][cursor.getDay()] : `${cursor.getDate()}`;
      result.bars.push(bar);
      if (mode === 'all') cursor.setFullYear(cursor.getFullYear() + 1);
      else if (mode === 'year') cursor.setMonth(cursor.getMonth() + 1);
      else cursor.setDate(cursor.getDate() + 1);
    }
    return result;
  }
}
