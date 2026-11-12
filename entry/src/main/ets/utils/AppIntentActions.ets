import { WebParseSettingsStore } from './WebParseSettingsStore';
import { router } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { RecentReadShortcut } from './RecentReadShortcut';

/** 小艺等系统入口调起的应用动作；沿用桌面快捷方式与作者搜索已有的 AppStorage 通道。 */
export class AppIntentActions {
  private static abilityContext: Context | null = null;

  /** 意图执行器拿到的是 InsightIntentContext，读数据库要用主 Ability 的上下文。 */
  static install(context: Context): void {
    AppIntentActions.abilityContext = context;
  }

  /** 打开书架里匹配书名的书，书名为空时打开最近在读的书；没有可打开的书返回 null。 */
  static async continueReading(bookName: string): Promise<Book | null> {
    const context = AppIntentActions.abilityContext;
    if (!context) throw new Error('ability context not ready');
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const books = (await db.getAllBooks()).filter((book: Book): boolean => !book.pendingAddToShelf && !book.isPrivate &&
      WebParseSettingsStore.visibleBook(book.origin));
    const target = AppIntentActions.normalize(bookName);
    let candidates = books;
    if (target) {
      const exact = books.filter((book: Book): boolean => AppIntentActions.normalize(book.name) === target);
      candidates = exact.length > 0 ? exact :
        books.filter((book: Book): boolean => AppIntentActions.normalize(book.name).includes(target));
    } else {
      candidates = books.filter((book: Book): boolean => Book.hasStartedReading(book));
    }
    if (candidates.length === 0) return null;
    const book = candidates.reduce((best: Book, item: Book): Book =>
      item.durChapterTime > best.durChapterTime ? item : best);
    RecentReadShortcut.requestBook(book.bookUrl);
    return book;
  }

  static search(keyword: string): void {
    const text = keyword.trim();
    if (!text) return;
    const nonce = AppStorage.get<number>('globalSearchPendingNonce') || 0;
    AppStorage.setOrCreate('globalSearchPendingKeyword', text);
    AppStorage.setOrCreate('globalSearchPendingNonce', nonce + 1);
    try {
      const state = router.getState();
      // 首页上面叠着别的页面时退回首页，首页再切到发现页签并打开搜索层。
      if (state && state.name !== 'Index' && state.name !== 'Startup') router.back({ url: 'pages/Index' });
    } catch (_) {
    }
  }

  private static normalize(name: string): string {
    return (name || '').replace(/[《》\s]/g, '').toLowerCase();
  }
}
