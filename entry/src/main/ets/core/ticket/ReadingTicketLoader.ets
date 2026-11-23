import { Context } from '@kit.AbilityKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { appDb } from '../../model/data/AppDatabase';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { BookMark } from '../../model/book/BookMark';
import { BookAnnotation } from '../../model/reader/BookAnnotation';
import { readStatsTracker } from '../stats/ReadStatsTracker';
import { BookReadStats, BookReadStatsDay, BookReadStatsMonth, BookReadStatsRecord } from '../stats/BookReadStats';
import { ReadStatsPosterRenderer } from '../stats/ReadStatsPosterRenderer';
import { ReadingTicket, ReadingTicketRules, TicketAccentRules } from './ReadingTicket';

/** 票背面要的内容：短评在票上，这里是一条摘录、划线数和阅读日历。 */
export class ReadingTicketBack {
  quote: string = '';
  annotationCount: number = 0;
  /** 28 格，0~4。 */
  calendar: number[] = [];
  /** 日历最后一格是哪天。 */
  calendarEndKey: string = '';
}

/** 封面地址 → 取到的强调色（空串 = 取不到，用默认色）；进程内共用，换封面地址才重新取。 */
const accentCache: Map<string, string> = new Map<string, string>();

export class ReadingTicketLoader {
  /** 当前账号加本机游客记录。 */
  private static async ownerId(context: Context): Promise<string> {
    await AccountSessionStore.load(context);
    return AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
  }

  /** 全部票，月份新的在前。 */
  static async loadAll(context: Context): Promise<ReadingTicket[]> {
    await appDb.init(context);
    const ownerId = await ReadingTicketLoader.ownerId(context);
    // 刚从阅读页回来时最后一段还没入库。
    await readStatsTracker.flushAndWait();
    const marks = await appDb.getAllBookMarks();
    if (!marks.some((mark: BookMark): boolean => ReadingTicketRules.hasTicket(mark))) return [];
    const rows = await appDb.getTicketStatsRows(ownerId);
    const tickets = ReadingTicketRules.build(marks, rows);
    await ReadingTicketLoader.fillQuotes(tickets);
    ReadingTicketLoader.applyCachedAccents(tickets);
    return tickets;
  }

  /** 每本书最近的一条摘录（按书的地址），没有摘录的书不填。 */
  private static async fillQuotes(tickets: ReadingTicket[]): Promise<void> {
    const excerpts = await appDb.getExcerptAnnotations();
    const latest = new Map<string, BookAnnotation>();
    excerpts.forEach((item: BookAnnotation): void => {
      if (!item.quote.trim()) return;
      const current = latest.get(item.bookUrl);
      if (!current || item.updateTime > current.updateTime) latest.set(item.bookUrl, item);
    });
    tickets.forEach((ticket: ReadingTicket): void => {
      const item = latest.get(ticket.bookUrl);
      if (item) ticket.quote = ReadingTicketLoader.cleanQuote(item.quote);
    });
  }

  private static cleanQuote(text: string): string {
    return text.trim().replace(/\s+/g, ' ');
  }

  /** 已经取过颜色的直接填上，免得票夹先画一遍默认色再跳色。 */
  static applyCachedAccents(tickets: ReadingTicket[]): void {
    tickets.forEach((ticket: ReadingTicket): void => {
      const cached = accentCache.get(ticket.coverUrl);
      if (cached !== undefined) ticket.accent = cached;
    });
  }

  /** 这些票里还没取过颜色的封面数量。 */
  static pendingAccents(tickets: ReadingTicket[]): number {
    return tickets.filter((ticket: ReadingTicket): boolean => !!ticket.coverUrl && !accentCache.has(ticket.coverUrl))
      .length;
  }

  /**
   * 逐张取封面颜色，每取完 batch 张回调一次让页面刷新。封面读不到（没缓存且网络不通）时记空串，用默认深红。
   * isAlive 返回 false 时停下（页面已关）。
   */
  static async fillAccents(context: Context, tickets: ReadingTicket[], batch: number, onBatch: () => void,
    isAlive: () => boolean): Promise<void> {
    let done = 0;
    for (const ticket of tickets) {
      if (!isAlive()) return;
      if (!ticket.coverUrl) continue;
      const cached = accentCache.get(ticket.coverUrl);
      if (cached !== undefined) {
        ticket.accent = cached;
        continue;
      }
      ticket.accent = await ReadingTicketLoader.accentOf(context, ticket.coverUrl);
      done++;
      if (done % batch === 0) onBatch();
    }
    if (done % batch !== 0) onBatch();
  }

  static async accentOf(context: Context, coverUrl: string): Promise<string> {
    if (!coverUrl) return '';
    const cached = accentCache.get(coverUrl);
    if (cached !== undefined) return cached;
    let pixelMap: image.PixelMap | null = null;
    let accent = '';
    try {
      pixelMap = await ReadStatsPosterRenderer.loadImage(context, coverUrl, true);
      if (pixelMap) {
        const picker = await effectKit.createColorPicker(pixelMap);
        const colors: number[][] = [];
        for (const color of picker.getTopProportionColors(6)) {
          if (color) colors.push([color.red, color.green, color.blue]);
        }
        accent = TicketAccentRules.pick(colors);
      }
    } catch (error) {
      console.warn('票面取色失败:', error);
    } finally {
      if (pixelMap) pixelMap.release();
    }
    accentCache.set(coverUrl, accent);
    return accent;
  }

  /**
   * 单本书的票（详情页标记页签、标成读过时出票）：编号看全部标记，时长只查这本，
   * 归并规则与 loadAll 一致。没有票的状态返回 null。
   */
  static async loadOne(context: Context, mark: BookMark): Promise<ReadingTicket | null> {
    if (!ReadingTicketRules.hasTicket(mark)) return null;
    await appDb.init(context);
    const ownerId = await ReadingTicketLoader.ownerId(context);
    await readStatsTracker.flushAndWait();
    const marks = await appDb.getAllBookMarks();
    if (!marks.some((item: BookMark): boolean => item.workKey === mark.workKey)) marks.push(mark);
    const number = ReadingTicketRules.numbers(marks.map((item: BookMark): BookMark =>
      item.workKey === mark.workKey ? mark : item)).get(mark.workKey) || 0;
    const records = mark.bookUrl ? await appDb.getBookReadStatsRecords(mark.bookUrl, mark.bookName.trim(),
      mark.author.trim(), ownerId) : [];
    const days = new Map<string, number>();
    records.forEach((record: BookReadStatsRecord): void => {
      if (record.durationMs > 0 && /^\d{4}-\d{2}-\d{2}$/.test(record.dayKey)) {
        days.set(record.dayKey, (days.get(record.dayKey) || 0) + record.durationMs);
      }
    });
    const ticket = ReadingTicketRules.compose(mark, days, number);
    if (mark.bookUrl) {
      const annotations = await appDb.getBookAnnotations(mark.bookUrl);
      const quote = ReadingTicketLoader.pickQuote(annotations);
      if (quote) ticket.quote = quote;
    }
    ticket.accent = await ReadingTicketLoader.accentOf(context, ticket.coverUrl);
    return ticket;
  }

  /** 优先最近收进摘录的一条，没有摘录用最近写了想法的划线。 */
  private static pickQuote(annotations: BookAnnotation[]): string {
    const latest = (list: BookAnnotation[]): BookAnnotation | null => {
      let best: BookAnnotation | null = null;
      for (const item of list) {
        if (!item.quote.trim()) continue;
        if (best === null || item.updateTime > (best as BookAnnotation).updateTime) best = item;
      }
      return best;
    };
    const chosen = latest(annotations.filter((item: BookAnnotation): boolean => item.excerpt)) ||
      latest(annotations.filter((item: BookAnnotation): boolean => !!item.note.trim()));
    return chosen ? ReadingTicketLoader.cleanQuote((chosen as BookAnnotation).quote) : '';
  }

  static async loadBack(context: Context, ticket: ReadingTicket): Promise<ReadingTicketBack> {
    const back = new ReadingTicketBack();
    await appDb.init(context);
    const ownerId = await ReadingTicketLoader.ownerId(context);
    const records = await appDb.getBookReadStatsRecords(ticket.bookUrl, ticket.bookName.trim(), ticket.author.trim(),
      ownerId);
    const stats = BookReadStats.calculate(records);
    const days = new Map<string, number>();
    stats.months.forEach((month: BookReadStatsMonth): void => {
      month.days.forEach((day: BookReadStatsDay): void => {
        days.set(day.dayKey, day.durationMs);
      });
    });
    back.calendarEndKey = ticket.endDayKey || stats.lastDayKey || ReadingTicketRules.dayKey(Date.now());
    back.calendar = ReadingTicketRules.calendarLevels(days, back.calendarEndKey);
    if (ticket.bookUrl) {
      const annotations = await appDb.getBookAnnotations(ticket.bookUrl);
      back.annotationCount = annotations.length;
      back.quote = ReadingTicketLoader.pickQuote(annotations);
    }
    return back;
  }
}
