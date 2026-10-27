import { ReadStatsSummary, ReadStatsRank, ReadStatsBar } from './ReadStatsSummary';

/** A detached snapshot: changing filters or receiving cloud data cannot change an open poster. */
export class ReadStatsPosterSnapshot {
  ownerId: string = '';
  mode: string = 'week';
  period: string = '';
  device: string = '';
  nickname: string = '';
  avatar: string = '';
  totalMs: number = 0;
  activeDays: number = 0;
  averageMs: number = 0;
  books: ReadStatsRank[] = [];
  bars: ReadStatsBar[] = [];

  static capture(summary: ReadStatsSummary, ownerId: string, mode: string, period: string,
    device: string, nickname: string, avatar: string): ReadStatsPosterSnapshot {
    const result = new ReadStatsPosterSnapshot();
    result.ownerId = ownerId;
    result.mode = mode;
    result.period = period;
    result.device = device;
    result.nickname = nickname;
    result.avatar = avatar;
    result.totalMs = summary.totalMs;
    result.activeDays = summary.activeDays;
    result.averageMs = summary.averageMs;
    result.books = summary.items.map((item: ReadStatsRank): ReadStatsRank => {
      const copy = new ReadStatsRank();
      copy.bookKey = item.bookKey;
      copy.name = item.name;
      copy.coverUrl = item.coverUrl;
      copy.durationMs = item.durationMs;
      copy.rank = item.rank;
      return copy;
    });
    result.bars = summary.bars.map((bar: ReadStatsBar): ReadStatsBar => {
      const copy = new ReadStatsBar();
      copy.key = bar.key;
      copy.label = bar.label;
      copy.durationMs = bar.durationMs;
      return copy;
    });
    return result;
  }

  title(): string {
    if (this.mode === 'day') return '我的阅读日报';
    if (this.mode === 'month') return '我的阅读月报';
    if (this.mode === 'year') return '我的阅读年报';
    if (this.mode === 'all') return '我的阅读时光';
    return '我的阅读周报';
  }
}

export class ReadStatsPosterOptions {
  style: number = 0;
  rankLimit: number = 5;
  profile: boolean = false;
  avatar: boolean = true;
  nickname: boolean = true;
  signature: boolean = true;
  alias: string = '';
  quote: string = '';

  static normalize(input: ReadStatsPosterOptions): ReadStatsPosterOptions {
    const result = new ReadStatsPosterOptions();
    result.style = [0, 1, 2, 3].includes(input.style) ? input.style : 0;
    result.rankLimit = [0, 3, 5, 10, -1].includes(input.rankLimit) ? input.rankLimit : 5;
    result.profile = input.profile === true;
    result.avatar = input.avatar !== false;
    result.nickname = input.nickname !== false;
    result.signature = input.signature !== false;
    result.alias = ReadStatsPosterOptions.clean(input.alias, 24);
    result.quote = ReadStatsPosterOptions.clean(input.quote, 40);
    return result;
  }

  private static clean(input: string, length: number): string {
    return typeof input === 'string' ? Array.from(input.replace(/[\r\n\t]/g, ' ')).slice(0, length).join('') : '';
  }
}

export class ReadStatsPosterPage {
  index: number = 0;
  count: number = 1;
  books: ReadStatsRank[] = [];
  height: number = 0;
}

export class ReadStatsPosterLayout {
  static readonly WIDTH: number = 1080;
  static readonly BOOKS_PER_PAGE: number = 10;
  static readonly STYLE_NAMES: string[] = ['清新简约', '纸上时光', '夜读星光', '阅读简报'];

  static hasProfile(snapshot: ReadStatsPosterSnapshot, options: ReadStatsPosterOptions): boolean {
    return options.profile && (options.avatar || (options.nickname && !!(options.alias || snapshot.nickname)) ||
      (options.signature && !!options.quote));
  }

  static pages(snapshot: ReadStatsPosterSnapshot, options: ReadStatsPosterOptions): ReadStatsPosterPage[] {
    const selected = options.rankLimit === -1 ? snapshot.books : snapshot.books.slice(0, options.rankLimit);
    const count = Math.max(1, Math.ceil(selected.length / ReadStatsPosterLayout.BOOKS_PER_PAGE));
    const result: ReadStatsPosterPage[] = [];
    for (let index = 0; index < count; index++) {
      const page = new ReadStatsPosterPage();
      page.index = index;
      page.count = count;
      page.books = selected.slice(index * ReadStatsPosterLayout.BOOKS_PER_PAGE, (index + 1) * ReadStatsPosterLayout.BOOKS_PER_PAGE);
      // Same dimensions are used for drawing, preview aspect ratio and image export.
      page.height = 630 + (snapshot.mode !== 'day' && snapshot.bars.length > 0 ? 310 : 0) +
        (page.books.length > 0 ? 85 + page.books.length * 108 : 0) +
        (ReadStatsPosterLayout.hasProfile(snapshot, options) ? 190 : 60);
      result.push(page);
    }
    return result;
  }
}

/** In-memory handoff only; no statistics in router URLs, preferences or logs. */
export class ReadStatsPosterSession {
  private static pending: ReadStatsPosterSnapshot | null = null;
  static put(snapshot: ReadStatsPosterSnapshot): void { ReadStatsPosterSession.pending = snapshot; }
  static take(): ReadStatsPosterSnapshot | null {
    const result = ReadStatsPosterSession.pending;
    ReadStatsPosterSession.pending = null;
    return result;
  }
}
