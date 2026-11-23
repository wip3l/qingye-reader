import { Book, SourceEventCallback } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { HdsFeedback } from './HdsFeedback';

/**
 * 书籍加入、移出书架时通知书源的事件回调（兼容书源的 eventListener）。
 *
 * 只在用户自己加入或移除时调用：试读占位、云同步、换源清理这些不是用户对这本书的决定，不通知。
 * 调用不等待结果，回调失败也不影响书架操作；书源脚本给出的提示照常弹出。
 */
export class SourceShelfEvents {
  static added(book: Book | null | undefined): void {
    SourceShelfEvents.notify(book, SourceEventCallback.ADD_BOOK_SHELF);
  }

  /** 要在删除之前取好书籍对象再调用：回调要读书籍的目录地址和变量。 */
  static removed(book: Book | null | undefined): void {
    SourceShelfEvents.notify(book, SourceEventCallback.DEL_BOOK_SHELF);
  }

  private static notify(book: Book | null | undefined, event: string): void {
    if (!book || !book.origin) return;
    SourceShelfEvents.run(book, event).catch((error: Object): void => {
      console.warn('[SourceShelfEvents] failed:', event, error);
    });
  }

  private static async run(book: Book, event: string): Promise<void> {
    const source = await AppDatabase.getInstance().getBookSource(book.origin);
    if (!source || !SourceEventCallback.listens(source)) return;
    const result = await SourceEventCallback.dispatch(source, event, book, null);
    if (result.error) console.warn('[SourceShelfEvents]', source.bookSourceName, event, result.error);
    if (result.toastMessage) HdsFeedback.showToast(result.toastMessage);
  }
}
