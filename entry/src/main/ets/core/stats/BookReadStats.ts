/** 一条阅读统计记录里单本书统计要用的字段。 */
export class BookReadStatsRecord {
  dayKey: string = '';
  durationMs: number = 0;
  /** 0 表示没有留下起始时刻（旧版本或导入的记录）。 */
  startedAt: number = 0;
}

export class BookReadStatsDay {
  dayKey: string = '';
  day: number = 0;
  durationMs: number = 0;
}

export class BookReadStatsMonth {
  /** 'YYYY-MM'。 */
  key: string = '';
  year: number = 0;
  month: number = 0;
  totalMs: number = 0;
  maxMs: number = 0;
  /** 有记录的日子，新的在前。 */
  days: BookReadStatsDay[] = [];
}

export class BookReadStatsSession {
  /** 0 表示没有起止时刻，只知道当天读了多久。 */
  startTs: number = 0;
  endTs: number = 0;
  durationMs: number = 0;
}

export class BookReadStatsTimelineDay {
  dayKey: string = '';
  sessions: BookReadStatsSession[] = [];
}

export class BookReadStatsCalendarCell {
  /** 0 是月初前的空位。 */
  day: number = 0;
  dayKey: string = '';
  durationMs: number = 0;
  /** 0 没读，1~4 越大读得越久（相对当月最久的一天）。 */
  level: number = 0;
}

/**
 * 单本书的阅读统计：累计、天数、单日最久，按月的每日时长，以及合并成段的时间线。
 * 只依赖阅读统计记录，书的进度和笔记数量由调用方另外读取。
 */
export class BookReadStats {
  /** 相邻两条记录间隔不超过这个值就并成一段。 */
  static readonly SESSION_GAP_MS: number = 5 * 60000;
  /** 时间线最多保留的天数，更早的只在统计和日历里体现。 */
  static readonly TIMELINE_DAY_LIMIT: number = 90;

  totalMs: number = 0;
  activeDays: number = 0;
  firstDayKey: string = '';
  lastDayKey: string = '';
  bestDayKey: string = '';
  bestDayMs: number = 0;
  /** 新的月份在前。 */
  months: BookReadStatsMonth[] = [];
  /** 新的日子在前，段落也是新的在前。 */
  timeline: BookReadStatsTimelineDay[] = [];
  timelineTruncated: boolean = false;

  static calculate(records: BookReadStatsRecord[]): BookReadStats {
    const result = new BookReadStats();
    const days = new Map<string, number>();
    const valid = records.filter((record: BookReadStatsRecord): boolean =>
      record.durationMs > 0 && /^\d{4}-\d{2}-\d{2}$/.test(record.dayKey));
    valid.forEach((record: BookReadStatsRecord): void => {
      result.totalMs += record.durationMs;
      days.set(record.dayKey, (days.get(record.dayKey) || 0) + record.durationMs);
    });
    const keys = Array.from(days.keys()).sort();
    result.activeDays = keys.length;
    if (keys.length === 0) return result;
    result.firstDayKey = keys[0];
    result.lastDayKey = keys[keys.length - 1];
    const months = new Map<string, BookReadStatsMonth>();
    keys.forEach((key: string): void => {
      const durationMs = days.get(key) || 0;
      // 时长相同取先到的那天。
      if (durationMs > result.bestDayMs) {
        result.bestDayMs = durationMs;
        result.bestDayKey = key;
      }
      const monthKey = key.substring(0, 7);
      let month = months.get(monthKey);
      if (!month) {
        month = new BookReadStatsMonth();
        month.key = monthKey;
        month.year = Number(key.substring(0, 4));
        month.month = Number(key.substring(5, 7));
        months.set(monthKey, month);
      }
      const day = new BookReadStatsDay();
      day.dayKey = key;
      day.day = Number(key.substring(8, 10));
      day.durationMs = durationMs;
      month.days.unshift(day);
      month.totalMs += durationMs;
      month.maxMs = Math.max(month.maxMs, durationMs);
    });
    result.months = Array.from(months.values()).sort((a: BookReadStatsMonth, b: BookReadStatsMonth): number =>
      a.key < b.key ? 1 : -1);
    BookReadStats.fillTimeline(result, valid, keys);
    return result;
  }

  private static fillTimeline(result: BookReadStats, records: BookReadStatsRecord[], keys: string[]): void {
    const shown = keys.slice(Math.max(0, keys.length - BookReadStats.TIMELINE_DAY_LIMIT));
    result.timelineTruncated = shown.length < keys.length;
    const byDay = new Map<string, BookReadStatsRecord[]>();
    records.forEach((record: BookReadStatsRecord): void => {
      const list = byDay.get(record.dayKey);
      if (list) list.push(record);
      else byDay.set(record.dayKey, [record]);
    });
    for (let i = shown.length - 1; i >= 0; i--) {
      const entry = new BookReadStatsTimelineDay();
      entry.dayKey = shown[i];
      const list = (byDay.get(shown[i]) || []).slice().sort((a: BookReadStatsRecord, b: BookReadStatsRecord): number =>
        a.startedAt - b.startedAt);
      let untimed = 0;
      let current: BookReadStatsSession | null = null;
      list.forEach((record: BookReadStatsRecord): void => {
        if (record.startedAt <= 0) {
          untimed += record.durationMs;
          return;
        }
        const end = record.startedAt + record.durationMs;
        if (current && record.startedAt - current.endTs <= BookReadStats.SESSION_GAP_MS) {
          current.endTs = Math.max(current.endTs, end);
          current.durationMs += record.durationMs;
          return;
        }
        current = new BookReadStatsSession();
        current.startTs = record.startedAt;
        current.endTs = end;
        current.durationMs = record.durationMs;
        entry.sessions.unshift(current);
      });
      if (untimed > 0) {
        const session = new BookReadStatsSession();
        session.durationMs = untimed;
        entry.sessions.push(session);
      }
      result.timeline.push(entry);
    }
  }

  /** 某个月的日历格子：按周一开头补空位，返回值长度是 7 的倍数。 */
  static calendar(year: number, month: number, source: BookReadStatsMonth | null): BookReadStatsCalendarCell[] {
    const cells: BookReadStatsCalendarCell[] = [];
    const lead = (new Date(year, month - 1, 1).getDay() + 6) % 7;
    for (let i = 0; i < lead; i++) cells.push(new BookReadStatsCalendarCell());
    const durations = new Map<number, number>();
    if (source) source.days.forEach((day: BookReadStatsDay): void => { durations.set(day.day, day.durationMs); });
    const maxMs = source ? source.maxMs : 0;
    const count = new Date(year, month, 0).getDate();
    for (let day = 1; day <= count; day++) {
      const cell = new BookReadStatsCalendarCell();
      cell.day = day;
      cell.dayKey = `${year}-${BookReadStats.pad(month)}-${BookReadStats.pad(day)}`;
      cell.durationMs = durations.get(day) || 0;
      cell.level = cell.durationMs > 0 && maxMs > 0 ? Math.max(1, Math.ceil(cell.durationMs * 4 / maxMs)) : 0;
      cells.push(cell);
    }
    while (cells.length % 7 !== 0) cells.push(new BookReadStatsCalendarCell());
    return cells;
  }

  /** 交替的数字与单位，如 ['6', '小时', '17', '分钟']，供大数字配小单位的排版。 */
  static durationParts(ms: number): string[] {
    if (ms > 0 && ms < 60000) return ['<1', '分钟'];
    const minutes = Math.max(0, Math.floor(ms / 60000));
    if (minutes < 60) return [`${minutes}`, '分钟'];
    const parts = [`${Math.floor(minutes / 60)}`, '小时'];
    if (minutes % 60) parts.push(`${minutes % 60}`, '分钟');
    return parts;
  }

  static durationText(ms: number): string {
    const parts = BookReadStats.durationParts(ms);
    return parts[0] === '<1' ? '不足 1 分钟' : parts.join(' ');
  }

  /** '2026-10-27' → '26/10/27'。 */
  static shortDate(dayKey: string): string {
    return dayKey.length === 10 ? `${dayKey.substring(2, 4)}/${dayKey.substring(5, 7)}/${dayKey.substring(8, 10)}` : '';
  }

  /** '2026-10-27' → '10/27'。 */
  static monthDay(dayKey: string): string {
    return dayKey.length === 10 ? `${dayKey.substring(5, 7)}/${dayKey.substring(8, 10)}` : '';
  }

  static clock(ts: number): string {
    const date = new Date(ts);
    return `${BookReadStats.pad(date.getHours())}:${BookReadStats.pad(date.getMinutes())}`;
  }

  static sessionText(session: BookReadStatsSession): string {
    const duration = BookReadStats.durationText(session.durationMs);
    if (session.startTs <= 0) return `当天累计 · ${duration}`;
    return `${BookReadStats.clock(session.startTs)} – ${BookReadStats.clock(session.endTs)} · ${duration}`;
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
