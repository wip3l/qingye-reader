import { Context } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { Book, SearchBook } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookSourceSwitchTask } from '../core/book/BookSourceSwitchTask';
import { ChangeSourceResultCache } from './ChangeSourceResultCache';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from './HdsFeedback';

/**
 * The shelf keeps one online copy per work (see BookIdentity.workKeyOf). Adding the same work from
 * another entry offers to move the existing shelf book to that entry instead of adding a second copy;
 * the switch keeps reading progress, group and bookmarks.
 */
export class ShelfWorkDuplicatePrompt {
  /** Returns the switched shelf book, or null when the user declined or the switch failed. */
  static async offerSwitch(context: Context, uiContext: UIContext, shelfBook: Book,
    candidate: SearchBook): Promise<Book | null> {
    const dark = AppStorage.get<boolean>('appDarkMode') || false;
    const name = shelfBook.name || candidate.name;
    const target = candidate.originName || '当前书源';
    const message = shelfBook.origin === candidate.origin ?
      `《${name}》已在书架。要改用当前这个结果吗？阅读进度、分组和书签会保留。` :
      `《${name}》已在书架（来源：${shelfBook.originName || '其他书源'}）。要换到「${target}」吗？阅读进度、分组和书签会保留。`;
    try {
      const choice = await uiContext.getPromptAction().showDialog({
        title: '书架已有这本书',
        message: message,
        buttons: [
          { text: '取消', color: ThemeRuntime.subTextColor(dark) },
          { text: '换源', color: ThemeRuntime.primaryTextColor(dark) }
        ]
      });
      if (choice.index !== 1) return null;
    } catch (_) {
      return null;
    }

    HdsFeedback.showToast('正在换源…');
    try {
      const cache = await ChangeSourceResultCache.load(context, shelfBook);
      const task = new BookSourceSwitchTask(false);
      const switched = await task.run(context, cache.key, shelfBook, candidate, null,
        (_label: string): void => {}, (_book: Book, _previousUrl: string): void => {});
      await ShelfWorkDuplicatePrompt.dropLeftoverTemporaryBook(candidate.bookUrl, switched.bookUrl);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('已切换至 ' + (switched.originName || target));
      return switched;
    } catch (error) {
      console.error('同书换源失败:', error);
      HdsFeedback.showToast((error as Error).message || '换源失败，已保留原书源');
      return null;
    }
  }

  static candidateOf(book: Book): SearchBook {
    const candidate = new SearchBook();
    candidate.bookUrl = book.bookUrl;
    candidate.tocUrl = book.tocUrl;
    candidate.origin = book.origin;
    candidate.originName = book.originName;
    candidate.type = book.type;
    candidate.name = book.name;
    candidate.author = book.author;
    candidate.kind = book.kind;
    candidate.status = book.status;
    candidate.coverUrl = book.coverUrl;
    candidate.intro = book.intro;
    candidate.latestChapterTitle = book.latestChapterTitle;
    candidate.wordCount = book.wordCount;
    candidate.updateTime = book.updateTime;
    candidate.variable = book.variable;
    return candidate;
  }

  /** A temporary-read row of the candidate survives when the source rewrote its detail URL. */
  private static async dropLeftoverTemporaryBook(candidateUrl: string, switchedUrl: string): Promise<void> {
    if (!candidateUrl || candidateUrl === switchedUrl) return;
    try {
      const db = AppDatabase.getInstance();
      const leftover = await db.getBook(candidateUrl);
      if (SearchExplorePendingBook.isPendingAddToShelf(leftover)) {
        await db.deleteBook(candidateUrl, 'same_work_switch_temporary_cleanup');
      }
    } catch (error) {
      console.warn('清理临时阅读书籍失败:', error);
    }
  }
}
