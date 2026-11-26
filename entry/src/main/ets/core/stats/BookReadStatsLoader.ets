import { Context } from '@kit.AbilityKit';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { readStatsTracker } from './ReadStatsTracker';
import { BookReadStats, BookReadStatsRecord } from './BookReadStats';
import { ReadWorkLinks } from './ReadStatsSummary';
import { ReadStatsFold } from './ReadStatsFold';
import { ReadWorkMergeStore } from '../../utils/ReadWorkMergeStore';

/** 详情页“统计”页签要显示的全部数据。 */
export class BookReadStatsSnapshot {
  stats: BookReadStats = new BookReadStats();
  /** 库里这本（当前书源）读到的章节下标；没读过或库里没有这本时为 -1。 */
  chapterIndex: number = -1;
  chapterTotal: number = 0;
  /** [全部划线, 写了想法的, 收进摘录的]。 */
  annotationCounts: number[] = [0, 0, 0];
}

export class BookReadStatsLoader {
  /**
   * 读这本书的阅读统计：当前账号加本机游客记录、所有设备合计，按作品归并（与阅读统计排行同一套规则）。
   * 时长跟作品走，进度和划线只看 bookUrl 这一本：换过源的书可能有时长而没有进度。
   */
  static async load(context: Context, bookUrl: string, name: string, author: string): Promise<BookReadStatsSnapshot> {
    const snapshot = new BookReadStatsSnapshot();
    if (!bookUrl) return snapshot;
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    await AccountSessionStore.load(context);
    const ownerId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
    // 刚从阅读页回来时最后一段还没入库。
    await readStatsTracker.flushAndWait();
    const records = await BookReadStatsLoader.workRecords(context, bookUrl, name, author, ownerId);
    snapshot.stats = BookReadStats.calculate(records);
    if (snapshot.stats.activeDays <= 0) return snapshot;
    const book = await db.getBook(bookUrl);
    if (book && Book.hasStartedReading(book)) {
      snapshot.chapterIndex = book.durChapterIndex;
      snapshot.chapterTotal = book.totalChapterNum > 0 ? book.totalChapterNum : await db.getBookChapterCount(bookUrl);
    }
    snapshot.annotationCounts = await db.getBookAnnotationCounts(bookUrl);
    return snapshot;
  }

  /** 这部作品（换过的各个书源、简繁写法、手动合并的）全部阅读记录；调用方先 init 数据库。 */
  static async workRecords(context: Context, bookUrl: string, name: string, author: string,
    ownerId: string): Promise<BookReadStatsRecord[]> {
    const links = await BookReadStatsLoader.links(context, ownerId);
    return AppDatabase.getInstance().getBookReadStatsRecords(links.urlsOf(bookUrl, name, author), ownerId);
  }

  static async links(context: Context, ownerId: string): Promise<ReadWorkLinks> {
    const editions = await AppDatabase.getInstance().getReadStatsEditions(ownerId);
    const fold = await ReadStatsFold.load(context);
    const merges = await ReadWorkMergeStore.load(context);
    return new ReadWorkLinks(editions, fold, merges);
  }
}
