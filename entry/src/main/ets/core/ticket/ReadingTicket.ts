import { BookMark, BookMarkStatus } from '../../model/book/BookMark';

/** 一行阅读统计：某本书（按地址）某天的合计时长，书名作者取书架或统计里登记的。 */
export class TicketStatsRow {
  bookUrl: string = '';
  name: string = '';
  author: string = '';
  dayKey: string = '';
  durationMs: number = 0;
}

/** 借书卡上的一行：某天读了多久、到那天为止一共读了多久。 */
export class TicketDay {
  dayKey: string = '';
  durationMs: number = 0;
  cumulativeMs: number = 0;
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
  /** 最近几天有记录的日子，旧的在前（借书卡每天一行）。 */
  log: TicketDay[] = [];
  /** 标记里的标签，最多两个。 */
  tags: string[] = [];
  /** 一条摘录（没有摘录用写了想法的划线），由读取方补上；空串表示没有。 */
  quote: string = '';
  /** 从封面取的强调色（#RRGGBB），由读取方补上；空串用默认深红。 */
  accent: string = '';
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

  static typeLabel(bookType: number): string {
    const media = TicketMedia.of(bookType);
    if (media === TicketMedia.AUDIO) return '有声书';
    if (media === TicketMedia.COMIC) return '漫画';
    return '小说';
  }

  static sessionLabel(bookType: number): string {
    return TicketMedia.of(bookType) === TicketMedia.AUDIO ? '收听专场' : '阅读专场';
  }
}

export class ReadingTicketRules {
  /** 有票的状态，也是票夹筛选页签的顺序。 */
  static readonly STATUSES: number[] = [BookMarkStatus.READ, BookMarkStatus.READING, BookMarkStatus.DROPPED];
  /** 借书卡最多列几天。 */
  static readonly LOG_DAYS: number = 6;

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
    ticket.tags = mark.categories.slice(0, 2);
    ticket.number = mark.status === BookMarkStatus.READ ? ticketNumber : 0;
    const keys = Array.from(days.keys()).filter((key: string): boolean => (days.get(key) || 0) > 0).sort();
    keys.forEach((key: string): void => {
      ticket.totalMs += days.get(key) || 0;
      const day = new TicketDay();
      day.dayKey = key;
      day.durationMs = days.get(key) || 0;
      day.cumulativeMs = ticket.totalMs;
      ticket.log.push(day);
    });
    ticket.log = ticket.log.slice(Math.max(0, ticket.log.length - ReadingTicketRules.LOG_DAYS));
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

  /** 车票上的日期：11月03日。 */
  static monthDayText(dayKey: string): string {
    return dayKey ? `${dayKey.substring(5, 7)}月${dayKey.substring(8, 10)}日` : '';
  }

  /** 车票到达站：读过=读完（有声书听完），在读=途中，弃读=下车。返回 [站名, 小字]。 */
  static arrivalText(status: number, bookType: number): string[] {
    if (status === BookMarkStatus.READ) return [TicketMedia.of(bookType) === TicketMedia.AUDIO ? '听完' : '读完', '到达'];
    if (status === BookMarkStatus.READING) return ['……', '途中'];
    return ['下车', '中途'];
  }

  /** 车票左上角票号：读过 A0042，其余写“在途”“已下车”。 */
  static trainNumberText(ticket: ReadingTicket): string {
    if (ticket.number > 0) return `A${String(ticket.number).padStart(4, '0')}`;
    return ticket.status === BookMarkStatus.READING ? '在途' : '已下车';
  }

  /**
   * 车票右下角的装饰二维码，size×size 格，true 为深色。三个角是定位框，其余由书名定，同一本书每次一样。
   */
  static qrCells(seed: string, size: number = 9): boolean[] {
    const random = ReadingTicketRules.barcode(seed, size * size);
    const far = size - 4;
    const cells: boolean[] = [];
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        // 左上、右上、左下各留 4×4 区域：3×3 空心方框加一圈留白。
        const left = x <= 3;
        const right = x >= far;
        const top = y <= 3;
        const bottom = y >= far;
        if ((left && top) || (right && top) || (left && bottom)) {
          const lx = left ? x : x - far - 1;
          const ly = top ? y : y - far - 1;
          const inBox = lx >= 0 && lx <= 2 && ly >= 0 && ly <= 2;
          cells.push(inBox && !(lx === 1 && ly === 1));
        } else {
          cells.push(random[y * size + x] !== 2);
        }
      }
    }
    return cells;
  }

  /** 影票书名下第二行：标签，没有标签写类型。 */
  static tagLine(ticket: ReadingTicket): string {
    return ticket.tags.length > 0 ? ticket.tags.join(' · ') : TicketMedia.typeLabel(ticket.bookType);
  }

  /** 影票书名下第三行：2026 读完 / 时长：12.5 小时。 */
  static yearLine(ticket: ReadingTicket): string {
    const key = ticket.endDayKey || ticket.startDayKey;
    const verb = ticket.status === BookMarkStatus.READ ? (TicketMedia.of(ticket.bookType) === TicketMedia.AUDIO ? '听完' : '读完') :
      (ticket.status === BookMarkStatus.READING ? '开读' : '放下');
    const label = TicketMedia.of(ticket.bookType) === TicketMedia.AUDIO ? '收听' : '时长';
    const duration = ReadingTicketRules.durationValue(ticket.totalMs).join(' ').trim();
    return `${key ? key.substring(0, 4) + ' ' : ''}${verb} / ${label}：${duration}`;
  }

  /** 影票字段格里的日期：2026-11-03；没有写“未完待续”。 */
  static fullDate(dayKey: string, empty: string): string {
    return dayKey || empty;
  }

  /** 暗场票最后一行：5 天 · 12.5 小时 · ★ 5。 */
  static summaryLine(ticket: ReadingTicket): string {
    const parts: string[] = [];
    if (ticket.activeDays > 0) parts.push(`${ticket.activeDays} 天`);
    if (ticket.totalMs > 0) parts.push(ReadingTicketRules.durationValue(ticket.totalMs).join(' '));
    if (ticket.rating > 0) parts.push(ReadingTicketRules.ratingText(ticket.rating));
    return parts.join(' · ') || ReadingTicketRules.stampText(ticket.status);
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

/** 票的裁切形状：圆角矩形，两侧在 notchY 处挖半圆缺口，上/下边可以挖一排齿孔。尺寸都是同一单位（px）。 */
export class TicketShapeSpec {
  width: number = 0;
  height: number = 0;
  corner: number = 0;
  /** 缺口圆心到顶边的距离；小于 0 表示没有缺口。 */
  notchY: number = -1;
  notchR: number = 0;
  scallopR: number = 0;
  scallopStep: number = 0;
  topScallops: boolean = false;
  bottomScallops: boolean = false;
}

export class TicketShapeRules {
  /** 一条边上齿孔圆心的横坐标：等距、整体居中，离圆角至少留出一个半径。 */
  static scallopCenters(spec: TicketShapeSpec): number[] {
    if (!(spec.scallopR > 0) || !(spec.scallopStep > spec.scallopR * 2)) return [];
    const usable = spec.width - 2 * (spec.corner + spec.scallopR);
    if (usable < 0) return [];
    const count = Math.floor(usable / spec.scallopStep) + 1;
    const start = (spec.width - (count - 1) * spec.scallopStep) / 2;
    const centers: number[] = [];
    for (let i = 0; i < count; i++) centers.push(start + i * spec.scallopStep);
    return centers;
  }

  /** SVG 路径；所有缺口都向票内挖（圆弧 sweep=0），四角是外凸圆角。 */
  static path(spec: TicketShapeSpec): string {
    const w = spec.width;
    const h = spec.height;
    const c = Math.max(0, Math.min(spec.corner, w / 2, h / 2));
    const r = spec.scallopR;
    const n = spec.notchR;
    const f = (value: number): string => `${Math.round(value * 100) / 100}`;
    const centers = TicketShapeRules.scallopCenters(spec);
    const hasNotch = spec.notchY - n > c && spec.notchY + n < h - c && n > 0;
    const parts: string[] = [`M${f(c)} 0`];
    if (spec.topScallops) {
      centers.forEach((x: number): void => {
        parts.push(`L${f(x - r)} 0`, `A${f(r)} ${f(r)} 0 0 0 ${f(x + r)} 0`);
      });
    }
    parts.push(`L${f(w - c)} 0`);
    if (c > 0) parts.push(`A${f(c)} ${f(c)} 0 0 1 ${f(w)} ${f(c)}`);
    if (hasNotch) parts.push(`L${f(w)} ${f(spec.notchY - n)}`, `A${f(n)} ${f(n)} 0 0 0 ${f(w)} ${f(spec.notchY + n)}`);
    parts.push(`L${f(w)} ${f(h - c)}`);
    if (c > 0) parts.push(`A${f(c)} ${f(c)} 0 0 1 ${f(w - c)} ${f(h)}`);
    if (spec.bottomScallops) {
      centers.slice().reverse().forEach((x: number): void => {
        parts.push(`L${f(x + r)} ${f(h)}`, `A${f(r)} ${f(r)} 0 0 0 ${f(x - r)} ${f(h)}`);
      });
    }
    parts.push(`L${f(c)} ${f(h)}`);
    if (c > 0) parts.push(`A${f(c)} ${f(c)} 0 0 1 0 ${f(h - c)}`);
    if (hasNotch) parts.push(`L0 ${f(spec.notchY + n)}`, `A${f(n)} ${f(n)} 0 0 0 0 ${f(spec.notchY - n)}`);
    parts.push(`L0 ${f(c)}`);
    if (c > 0) parts.push(`A${f(c)} ${f(c)} 0 0 1 ${f(c)} 0`);
    parts.push('Z');
    return parts.join(' ');
  }
}

/** 从封面颜色里挑票面强调色。 */
export class TicketAccentRules {
  static readonly FALLBACK: string = '#B3352E';

  /**
   * colors 按占比从高到低，每项 [r, g, b]（0~255）。挑够鲜艳、不太亮也不太黑的一种，占比靠前的优先；
   * 再把亮度压到适合印在米白纸上的范围。都不合适时用深红。
   */
  static pick(colors: number[][]): string {
    let chosen: number[] = [];
    let bestScore = 0;
    for (let index = 0; index < colors.length; index++) {
      const rgb = colors[index];
      if (!rgb || rgb.length < 3) continue;
      const hsl = TicketAccentRules.toHsl(rgb[0], rgb[1], rgb[2]);
      if (hsl[1] < 0.2 || hsl[2] > 0.88 || hsl[2] < 0.06) continue;
      const score = hsl[1] * Math.max(0.3, 1 - index * 0.12);
      if (score > bestScore) {
        bestScore = score;
        chosen = hsl;
      }
    }
    if (chosen.length < 3) return TicketAccentRules.FALLBACK;
    const saturation = Math.min(0.78, Math.max(0.38, chosen[1]));
    const lightness = Math.min(0.44, Math.max(0.3, chosen[2]));
    return TicketAccentRules.toHex(chosen[0], saturation, lightness);
  }

  /** [色相 0~360, 饱和度 0~1, 亮度 0~1]。 */
  static toHsl(r: number, g: number, b: number): number[] {
    const rn = r / 255;
    const gn = g / 255;
    const bn = b / 255;
    const max = Math.max(rn, gn, bn);
    const min = Math.min(rn, gn, bn);
    const l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let hue = 0;
    if (max === rn) hue = (gn - bn) / d + (gn < bn ? 6 : 0);
    else if (max === gn) hue = (bn - rn) / d + 2;
    else hue = (rn - gn) / d + 4;
    return [hue * 60, s, l];
  }

  static toHex(hue: number, s: number, l: number): string {
    const k = (n: number): number => (n + hue / 30) % 12;
    const a = s * Math.min(l, 1 - l);
    const channel = (n: number): string => {
      const value = l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
      return Math.round(value * 255).toString(16).padStart(2, '0');
    };
    return `#${channel(0)}${channel(8)}${channel(4)}`.toUpperCase();
  }
}
