import { BookMark, BookMarkStatus } from '../../model/book/BookMark';

/** 一行阅读统计：某本书（按地址）某天的合计时长，书名作者取书架或统计里登记的。 */
export class TicketStatsRow {
  bookUrl: string = '';
  name: string = '';
  author: string = '';
  dayKey: string = '';
  durationMs: number = 0;
}

/**
 * 票夹里的一张票：由“我的标记”和阅读统计现算出来，不单独存。
 * 只有读过、在读、弃读的书有票；想读和只打分没选状态的没有。
 */
export class ReadingTicket {
  workKey: string = '';
  bookName: string = '';
  author: string = '';
  bookUrl: string = '';
  origin: string = '';
  originName: string = '';
  coverUrl: string = '';
  bookType: number = 0;
  status: number = BookMarkStatus.NONE;
  /** 0–10，每 1 是半颗星。 */
  rating: number = 0;
  review: string = '';
  /** 第几本读完；只有读过的书有，在读、弃读为 0。 */
  number: number = 0;
  /** 第一天有阅读记录的日子；没有记录时用标记创建那天。 */
  startDayKey: string = '';
  /** 读过 = 标成读过那天；弃读 = 最后一天有记录的日子；在读为空。 */
  endDayKey: string = '';
  totalMs: number = 0;
  activeDays: number = 0;
  /** 票夹按月分组用：读过按读完那天，其余按最后读的那天（没有记录按标记更新时间）。 */
  monthKey: string = '';
  /** 同月里的先后，新的在前。 */
  sortTime: number = 0;
}

export class TicketMedia {
  static readonly NOVEL: string = 'novel';
  static readonly AUDIO: string = 'audio';
  static readonly COMIC: string = 'comic';
  private static readonly AUDIO_BIT: number = 32;
  private static readonly IMAGE_BIT: number = 64;

  static of(bookType: number): string {
    const type = Number(bookType) || 0;
    if ((type & TicketMedia.AUDIO_BIT) !== 0) return TicketMedia.AUDIO;
    if ((type & TicketMedia.IMAGE_BIT) !== 0) return TicketMedia.COMIC;
    return TicketMedia.NOVEL;
  }

  /** 票面上“总阅读时长”那一栏的叫法。 */
  static durationLabel(bookType: number): string {
    const media = TicketMedia.of(bookType);
    if (media === TicketMedia.AUDIO) return '总收听时长';
    if (media === TicketMedia.COMIC) return '总观看时长';
    return '总阅读时长';
  }

  static sessionLabel(bookType: number): string {
    return TicketMedia.of(bookType) === TicketMedia.AUDIO ? '收听专场' : '阅读专场';
  }
}

export class ReadingTicketRules {
  /** 有票的状态，也是票夹筛选页签的顺序。 */
  static readonly STATUSES: number[] = [BookMarkStatus.READ, BookMarkStatus.READING, BookMarkStatus.DROPPED];

  static hasTicket(mark: BookMark): boolean {
    return ReadingTicketRules.STATUSES.includes(mark.status);
  }

  static dayKey(ts: number): string {
    if (!(ts > 0)) return '';
    const date = new Date(ts);
    return `${date.getFullYear()}-${ReadingTicketRules.pad(date.getMonth() + 1)}-${ReadingTicketRules.pad(date.getDate())}`;
  }

  /**
   * 读过的书按读完时间排第几本，返回 workKey → 编号。读完时间相同按创建先后。
   * 改回在读再读完的书 finishTime 是新的，会排到最后。
   */
  static numbers(marks: BookMark[]): Map<string, number> {
    const read = marks.filter((mark: BookMark): boolean => mark.status === BookMarkStatus.READ && !!mark.workKey);
    read.sort((a: BookMark, b: BookMark): number =>
      (ReadingTicketRules.finishOf(a) - ReadingTicketRules.finishOf(b)) || (a.createTime - b.createTime) ||
        (a.workKey < b.workKey ? -1 : a.workKey > b.workKey ? 1 : 0));
    const result = new Map<string, number>();
    read.forEach((mark: BookMark, index: number): void => {
      result.set(mark.workKey, index + 1);
    });
    return result;
  }

  /**
   * 把标记和阅读统计拼成票。统计按作品归并，规则与详情页“统计”页签一致：
   * 地址相同，或书名作者都有且相同的记录都算这本。返回顺序：月份新的在前，同月新的在前。
   */
  static build(marks: BookMark[], rows: TicketStatsRow[]): ReadingTicket[] {
    const byUrl = new Map<string, Map<string, number>>();
    const urlsByWork = new Map<string, Set<string>>();
    rows.forEach((row: TicketStatsRow): void => {
      if (!row.bookUrl || !(row.durationMs > 0) || !/^\d{4}-\d{2}-\d{2}$/.test(row.dayKey)) return;
      let days = byUrl.get(row.bookUrl);
      if (!days) {
        days = new Map<string, number>();
        byUrl.set(row.bookUrl, days);
      }
      days.set(row.dayKey, (days.get(row.dayKey) || 0) + row.durationMs);
      const work = ReadingTicketRules.workOf(row.name, row.author);
      if (work) {
        let urls = urlsByWork.get(work);
        if (!urls) {
          urls = new Set<string>();
          urlsByWork.set(work, urls);
        }
        urls.add(row.bookUrl);
      }
    });
    const numbers = ReadingTicketRules.numbers(marks);
    const tickets: ReadingTicket[] = [];
    marks.forEach((mark: BookMark): void => {
      if (!ReadingTicketRules.hasTicket(mark) || !mark.workKey) return;
      const urls = new Set<string>();
      if (mark.bookUrl) urls.add(mark.bookUrl);
      const work = ReadingTicketRules.workOf(mark.bookName, mark.author);
      if (work) {
        const matched = urlsByWork.get(work);
        if (matched) matched.forEach((url: string): void => {
          urls.add(url);
        });
      }
      const days = new Map<string, number>();
      urls.forEach((url: string): void => {
        const source = byUrl.get(url);
        if (source) source.forEach((ms: number, key: string): void => {
          days.set(key, (days.get(key) || 0) + ms);
        });
      });
      tickets.push(ReadingTicketRules.compose(mark, days, numbers.get(mark.workKey) || 0));
    });
    return ReadingTicketRules.sort(tickets);
  }

  /** 由一本书的标记和它每天的时长拼一张票；详情页已经读过统计时直接用这个。 */
  static compose(mark: BookMark, days: Map<string, number>, ticketNumber: number): ReadingTicket {
    const ticket = new ReadingTicket();
    ticket.workKey = mark.workKey;
    ticket.bookName = mark.bookName;
    ticket.author = mark.author;
    ticket.bookUrl = mark.bookUrl;
    ticket.origin = mark.origin;
    ticket.originName = mark.originName;
    ticket.coverUrl = mark.coverUrl;
    ticket.bookType = mark.bookType;
    ticket.status = mark.status;
    ticket.rating = mark.rating;
    ticket.review = mark.review;
    ticket.number = mark.status === BookMarkStatus.READ ? ticketNumber : 0;
    const keys = Array.from(days.keys()).filter((key: string): boolean => (days.get(key) || 0) > 0).sort();
    keys.forEach((key: string): void => {
      ticket.totalMs += days.get(key) || 0;
    });
    ticket.activeDays = keys.length;
    const firstKey = keys.length > 0 ? keys[0] : '';
    const lastKey = keys.length > 0 ? keys[keys.length - 1] : '';
    const finishKey = ReadingTicketRules.dayKey(mark.finishTime);
    ticket.startDayKey = firstKey || ReadingTicketRules.dayKey(mark.createTime) || finishKey;
    if (mark.status === BookMarkStatus.READ) {
      ticket.endDayKey = finishKey || lastKey;
      // 补标的旧书可能先标读过、后来才有记录，开始日不能晚于读完日。
      if (ticket.endDayKey && ticket.startDayKey > ticket.endDayKey) ticket.startDayKey = ticket.endDayKey;
    } else if (mark.status === BookMarkStatus.DROPPED) {
      ticket.endDayKey = lastKey || ReadingTicketRules.dayKey(mark.updateTime);
    }
    const anchorKey = mark.status === BookMarkStatus.READ ? ticket.endDayKey :
      (lastKey || ReadingTicketRules.dayKey(mark.updateTime));
    ticket.monthKey = anchorKey ? anchorKey.substring(0, 7) : '';
    ticket.sortTime = mark.status === BookMarkStatus.READ && mark.finishTime > 0 ? mark.finishTime :
      Math.max(ReadingTicketRules.parseDay(lastKey), mark.updateTime);
    return ticket;
  }

  static sort(tickets: ReadingTicket[]): ReadingTicket[] {
    return tickets.sort((a: ReadingTicket, b: ReadingTicket): number => {
      if (a.monthKey !== b.monthKey) return a.monthKey < b.monthKey ? 1 : -1;
      return (b.sortTime - a.sortTime) || (b.number - a.number);
    });
  }

  /** 票夹页顶部的四个数：张数、读过几本、合计小时、平均分（0 = 没有打过分）。 */
  static summary(tickets: ReadingTicket[]): number[] {
    let read = 0;
    let totalMs = 0;
    let ratingSum = 0;
    let rated = 0;
    tickets.forEach((ticket: ReadingTicket): void => {
      if (ticket.status === BookMarkStatus.READ) read++;
      totalMs += ticket.totalMs;
      if (ticket.rating > 0) {
        ratingSum += ticket.rating;
        rated++;
      }
    });
    return [tickets.length, read, Math.round(totalMs / 360000) / 10, rated > 0 ? ratingSum / rated / 2 : 0];
  }

  /** 出现过的年份，新的在前；用读完或最后读的月份算。 */
  static years(tickets: ReadingTicket[]): number[] {
    const years: number[] = [];
    tickets.forEach((ticket: ReadingTicket): void => {
      const year = Number(ticket.monthKey.substring(0, 4));
      if (year > 0 && !years.includes(year)) years.push(year);
    });
    return years.sort((a: number, b: number): number => b - a);
  }

  static filter(tickets: ReadingTicket[], status: number, year: number): ReadingTicket[] {
    return tickets.filter((ticket: ReadingTicket): boolean =>
      (status === 0 || ticket.status === status) &&
        (year === 0 || Number(ticket.monthKey.substring(0, 4)) === year));
  }

  /** 'No.0042'；没编号返回空串。 */
  static numberText(ticket: ReadingTicket): string {
    return ticket.number > 0 ? `No.${String(ticket.number).padStart(4, '0')}` : '';
  }

  /** 12.5 小时、40 分钟；不足一分钟也写 1 分钟，没有记录写“—”。 */
  static durationValue(ms: number): string[] {
    if (!(ms > 0)) return ['—', ''];
    if (ms >= 3600000) {
      const hours = Math.round(ms / 360000) / 10;
      return [hours >= 100 ? `${Math.round(hours)}` : `${hours}`, '小时'];
    }
    return [`${Math.max(1, Math.round(ms / 60000))}`, '分钟'];
  }

  /** 2026.11.03 */
  static dottedDate(dayKey: string): string {
    return dayKey ? dayKey.replace(/-/g, '.') : '';
  }

  /** 11.03 */
  static shortDate(dayKey: string): string {
    return dayKey ? dayKey.substring(5).replace('-', '.') : '';
  }

  /** 藏书卡页脚：2026.11.03 至 11.08；跨年写全；在读写“起”。 */
  static rangeText(ticket: ReadingTicket): string {
    const start = ReadingTicketRules.dottedDate(ticket.startDayKey);
    if (!start) return '';
    if (!ticket.endDayKey) return `${start} 起`;
    if (ticket.endDayKey === ticket.startDayKey) return start;
    const end = ticket.endDayKey.substring(0, 4) === ticket.startDayKey.substring(0, 4) ?
      ReadingTicketRules.shortDate(ticket.endDayKey) : ReadingTicketRules.dottedDate(ticket.endDayKey);
    return `${start} 至 ${end}`;
  }

  /** ★ 4.5；没打分写“未评分”。 */
  static ratingText(rating: number): string {
    if (!(rating > 0)) return '未评分';
    const stars = rating / 2;
    return `★ ${Number.isInteger(stars) ? stars : stars.toFixed(1)}`;
  }

  /** 印章上的字。 */
  static stampText(status: number): string {
    if (status === BookMarkStatus.READ) return '已读';
    if (status === BookMarkStatus.READING) return '在读';
    if (status === BookMarkStatus.DROPPED) return '弃读';
    return '';
  }

  /** 电影票根上的检票状态。 */
  static checkText(status: number): string {
    if (status === BookMarkStatus.READ) return '已检票';
    if (status === BookMarkStatus.READING) return '未检票';
    return '中途离场';
  }

  /**
   * 背面的阅读日历：截至读完那天（没读完就是最后一天有记录的日子）往前 28 天，
   * 每格 0~4，越大读得越久（相对这 28 天里最久的一天）。
   */
  static calendarLevels(days: Map<string, number>, endDayKey: string, count: number = 28): number[] {
    const end = ReadingTicketRules.parseDay(endDayKey);
    const levels: number[] = [];
    if (!(end > 0)) return new Array<number>(count).fill(0);
    const values: number[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = new Date(end);
      date.setDate(date.getDate() - i);
      values.push(days.get(ReadingTicketRules.dayKey(date.getTime())) || 0);
    }
    const max = Math.max(0, ...values);
    values.forEach((ms: number): void => {
      levels.push(ms > 0 && max > 0 ? Math.max(1, Math.min(4, Math.ceil(ms / max * 4))) : 0);
    });
    return levels;
  }

  /** 条码的线宽（1~3），由书名定，同一本书每次一样。 */
  static barcode(seed: string, count: number = 30): number[] {
    let hash = 2166136261;
    for (let i = 0; i < seed.length; i++) {
      hash ^= seed.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    let state = (hash >>> 0) || 1;
    const result: number[] = [];
    for (let i = 0; i < count; i++) {
      state ^= state << 13;
      state ^= state >>> 17;
      state ^= state << 5;
      result.push(1 + ((state >>> 0) % 3));
    }
    return result;
  }

  private static workOf(name: string, author: string): string {
    const n = (name || '').trim();
    const a = (author || '').trim();
    return n && a ? `${n}\u0001${a}` : '';
  }

  private static finishOf(mark: BookMark): number {
    return mark.finishTime > 0 ? mark.finishTime : mark.updateTime;
  }

  private static parseDay(dayKey: string): number {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey || '')) return 0;
    return new Date(Number(dayKey.substring(0, 4)), Number(dayKey.substring(5, 7)) - 1,
      Number(dayKey.substring(8, 10))).getTime();
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
