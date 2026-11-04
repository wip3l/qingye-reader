import { Context } from '@kit.AbilityKit';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReaderTtsFloatingSession } from './ReaderTtsFloatingSession';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';

/**
 * 从搜索、发现试听（或试读时开了朗读）后选“不加入书架”，这本书还在后台播放时先不删临时书，
 * 等播放结束再删。书架上的播放面板封面、从胶囊重开听书页、进度保存和边听边下都按 bookUrl
 * 读这条记录，播放中删掉就会丢封面、打不开。临时书本来就不在书架上显示。
 *
 * 只记在内存里：进程退出时还没删的临时书留在库里不显示，和关掉“返回提示加入书架”时一样。
 */
export class PendingTrialBookCleanup {
  /** 会话清掉后等一会儿再确认：换章、重开听书页接管时会先清再发布。 */
  private static readonly RELEASE_CONFIRM_MS: number = 1500;
  private static pending: Map<string, Context> = new Map();

  static deleteAfterPlayback(context: Context, bookUrl: string): void {
    if (!bookUrl) return;
    PendingTrialBookCleanup.pending.set(bookUrl, context);
    ReaderTtsFloatingSession.setReleaseListener((released: string): void => {
      PendingTrialBookCleanup.onPlaybackReleased(released);
    });
  }

  /** 又从详情页打开了这本书，删不删交回给详情页的返回提示。 */
  static cancel(bookUrl: string): void {
    PendingTrialBookCleanup.pending.delete(bookUrl);
  }

  private static onPlaybackReleased(bookUrl: string): void {
    if (!PendingTrialBookCleanup.pending.has(bookUrl)) return;
    setTimeout(() => {
      const context = PendingTrialBookCleanup.pending.get(bookUrl);
      if (!context || ReaderTtsFloatingSession.isPlayingBook(bookUrl)) return;
      PendingTrialBookCleanup.pending.delete(bookUrl);
      PendingTrialBookCleanup.deleteIfStillPending(context, bookUrl).catch((error: Error) => {
        console.warn('删除试听后未加入书架的临时书失败:', error);
      });
    }, PendingTrialBookCleanup.RELEASE_CONFIRM_MS);
  }

  private static async deleteIfStillPending(context: Context, bookUrl: string): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    // 播放期间可能已经从书架胶囊或别处加入了书架，那就留着。
    if (!SearchExplorePendingBook.isPendingAddToShelf(await db.getBook(bookUrl))) return;
    await db.deleteBook(bookUrl, 'temporary_read_declined');
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
  }
}
