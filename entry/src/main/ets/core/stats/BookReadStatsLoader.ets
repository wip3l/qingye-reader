import { Context } from '@kit.AbilityKit';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { readStatsTracker } from './ReadStatsTracker';
import { BookReadStats } from './BookReadStats';

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
   * 读这本书的阅读统计：当前账号加本机游客记录、所有设备合计，按作品归并。
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
    const records = await db.getBookReadStatsRecords(bookUrl, name.trim(), author.trim(), ownerId);
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
}
