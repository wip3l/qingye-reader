import { Context } from '@kit.AbilityKit';
import { appDb } from '../../model/data/AppDatabase';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { BookMark } from '../../model/book/BookMark';
import { BookAnnotation } from '../../model/reader/BookAnnotation';
import { readStatsTracker } from '../stats/ReadStatsTracker';
import { BookReadStats, BookReadStatsDay, BookReadStatsMonth, BookReadStatsRecord } from '../stats/BookReadStats';
import { ReadingTicket, ReadingTicketRules } from './ReadingTicket';

/** 票背面要的内容：短评在票上，这里是一条摘录、划线数和阅读日历。 */
export class ReadingTicketBack {
  quote: string = '';
  annotationCount: number = 0;
  /** 28 格，0~4。 */
  calendar: number[] = [];
  /** 日历最后一格是哪天。 */
  calendarEndKey: string = '';
}

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
    return ReadingTicketRules.build(marks, rows);
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
    return ReadingTicketRules.compose(mark, days, number);
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
      // 优先最近收进摘录的一条，没有摘录用最近写了想法的划线。
      const pick = (list: BookAnnotation[]): BookAnnotation | null => {
        let best: BookAnnotation | null = null;
        list.forEach((item: BookAnnotation): void => {
          if (!item.quote.trim()) return;
          if (!best || item.updateTime > best.updateTime) best = item;
        });
        return best;
      };
      const chosen = pick(annotations.filter((item: BookAnnotation): boolean => item.excerpt)) ||
        pick(annotations.filter((item: BookAnnotation): boolean => !!item.note.trim()));
      if (chosen) back.quote = (chosen as BookAnnotation).quote.trim().replace(/\s+/g, ' ');
    }
    return back;
  }
}
