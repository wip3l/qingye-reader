import { Context } from '@kit.AbilityKit';
import { Book, SearchBook, BookFieldSanitizer, BookTypeSupport, SourceEngineHost } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ChangeSourceResultCache } from '../../utils/ChangeSourceResultCache';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { WebBookService } from './WebBookService';
import { SourceSwitchOperation } from './SourceSwitchOperation';

/** Owns preparation and commit independently of the dialog's lifetime. */
export class BookSourceSwitchTask {
  private static active: Set<string> = new Set();
  private static revisions: Map<string, number> = new Map();
  private static revisionSerial: number = 0;
  private operation: SourceSwitchOperation;
  private service: WebBookService;
  private markReadOnSwitch: boolean;

  constructor(markRead: boolean) {
    this.markReadOnSwitch = markRead;
    this.operation = new SourceSwitchOperation((): void => this.service.cancelPendingRequests());
    this.service = new WebBookService((): boolean => this.operation.isCancelled(), true);
  }

  cancel(): void { this.operation.cancel(); }
  isCommitting(): boolean { return this.operation.isCommitting(); }

  static revisionOf(book: Book): number {
    return BookSourceSwitchTask.revisions.get(book.origin + '\n' + book.bookUrl) || 0;
  }

  async run(context: Context, key: string, target: Book, candidate: SearchBook,
    beforeSwitch: (() => Promise<void>) | null, progress: (label: string) => void,
    committed: (book: Book, previousUrl: string) => void,
    expectedRevision: number = BookSourceSwitchTask.revisionOf(target)): Promise<Book> {
    if (BookSourceSwitchTask.active.has(key)) throw new Error('上一次换源仍在保存，请稍后重试');
    if (expectedRevision !== BookSourceSwitchTask.revisionOf(target)) {
      throw new Error('书籍已切换，请关闭后重新打开换源');
    }
    const previousUrl = target.bookUrl;
    const previousVersion = target.origin + '\n' + previousUrl;
    BookSourceSwitchTask.active.add(key);
    const op = this.operation;
    try {
      progress('正在保存阅读进度…');
      if (beforeSwitch) await op.stage('保存阅读进度', 10000, beforeSwitch);
      const db = AppDatabase.getInstance();
      await op.stage('读取书籍', 10000, async (): Promise<void> => { await db.initWithContext(context); });
      const oldBook = await op.stage('读取书籍', 10000, (): Promise<Book | null> => db.getBook(previousUrl));
      const source = await op.stage('读取书源', 10000, () => db.getBookSource(candidate.origin));
      if (!source || !source.enabled) throw new Error('书源不存在、已删除或已停用');
      const nextBook = this.buildSourceBook(candidate, oldBook || target);
      progress('正在读取新源详情…');
      const fullBook = await op.stage('读取新源详情', 25000, () => this.service.getBookInfo(source, nextBook));
      this.preserveSourceBookState(fullBook, nextBook, oldBook || target);
      if (BookTypeSupport.mediaCategoryOf(fullBook) !== BookTypeSupport.mediaCategoryOf(target)) {
        throw new Error('新源书籍类型与原书不同，已保留原书源');
      }
      progress('正在加载新源完整目录…');
      const chapters = await op.stage('加载新源目录', 60000, () => this.service.getChapterList(source, fullBook, 0, false));
      if (chapters.length === 0) throw new Error(SourceEngineHost.getError(source) || '新书源目录为空，已保留原书源');
      fullBook.totalChapterNum = chapters.length;
      const safeIndex = Math.max(0, Math.min((oldBook || target).durChapterIndex, chapters.length - 1));
      fullBook.durChapterIndex = safeIndex;
      fullBook.durChapterTitle = chapters[safeIndex].title;
      fullBook.latestChapterTitle = chapters[chapters.length - 1].title;
      op.check();
      // Bind aliases before the commit boundary, including rewritten detail URLs/metadata.
      ChangeSourceResultCache.rememberSwitch(context, key, oldBook || target);
      ChangeSourceResultCache.rememberSwitch(context, key, fullBook);
      await op.stage('保存换源记录', 5000, () => ChangeSourceResultCache.flush(context));
      op.beginCommit();
      progress('正在保存切换结果…');
      if (oldBook) {
        await db.commitBookSourceSwitch(previousUrl, fullBook, chapters);
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
      BookSourceSwitchTask.revisions.set(previousVersion, ++BookSourceSwitchTask.revisionSerial);
      // Delivery survives dialog disposal once the atomic commit has started.
      try { committed(fullBook, previousUrl); } catch (error) {
        console.error('换源已提交，页面更新失败:', error);
      }
      return fullBook;
    } finally {
      BookSourceSwitchTask.active.delete(key);
      op.cancel();
      this.service.cancelPendingRequests();
    }
  }

  buildSourceBook(searchBook: SearchBook, oldBook: Book): Book {
    const book = new Book();
    book.bookUrl = searchBook.bookUrl;
    book.tocUrl = searchBook.tocUrl;
    book.origin = searchBook.origin;
    book.originName = searchBook.originName;
    book.name = searchBook.name || oldBook.name;
    book.author = searchBook.author || oldBook.author;
    book.kind = BookFieldSanitizer.prefer(searchBook.kind, oldBook.kind);
    book.status = BookFieldSanitizer.prefer(searchBook.status, oldBook.status);
    book.coverUrl = CoverUrlNormalizer.prefer(searchBook.coverUrl, oldBook.coverUrl);
    book.customCoverUrl = oldBook.customCoverUrl;
    book.intro = BookFieldSanitizer.prefer(searchBook.intro, oldBook.intro);
    book.customIntro = oldBook.customIntro;
    book.latestChapterTitle = BookFieldSanitizer.prefer(searchBook.latestChapterTitle, oldBook.latestChapterTitle);
    book.updateTime = BookFieldSanitizer.prefer(searchBook.updateTime, oldBook.updateTime);
    book.wordCount = BookFieldSanitizer.prefer(searchBook.wordCount, oldBook.wordCount);
    book.variable = searchBook.variable || '';
    book.group = oldBook.group;
    book.isPinned = oldBook.isPinned;
    book.order = oldBook.order;
    book.originOrder = oldBook.originOrder;
    book.readConfig = oldBook.readConfig;
    book.canUpdate = oldBook.canUpdate;
    book.type = oldBook.type;
    book.durChapterIndex = oldBook.durChapterIndex;
    book.durChapterPos = oldBook.durChapterPos;
    book.durChapterTitle = oldBook.durChapterTitle;
    book.durChapterTime = oldBook.durChapterTime;
    book.pendingAddToShelf = oldBook.pendingAddToShelf;
    book.isPrivate = oldBook.isPrivate;
    if (this.markReadOnSwitch) {
      book.putVariable('readStarted', '1');
      book.putVariable('lastReadTime', `${Date.now()}`);
    }
    return book;
  }

  preserveSourceBookState(target: Book, source: Book, oldBook: Book): void {
    target.origin = source.origin;
    target.originName = source.originName;
    target.coverUrl = CoverUrlNormalizer.prefer(source.coverUrl, target.coverUrl);
    target.group = oldBook.group;
    target.isPinned = oldBook.isPinned;
    target.confirmedChapterUpdateTime = oldBook.confirmedChapterUpdateTime;
    target.order = oldBook.order;
    target.originOrder = oldBook.originOrder;
    target.customCoverUrl = oldBook.customCoverUrl;
    target.customIntro = oldBook.customIntro;
    target.readConfig = oldBook.readConfig;
    target.canUpdate = oldBook.canUpdate;
    target.durChapterIndex = oldBook.durChapterIndex;
    target.durChapterPos = oldBook.durChapterPos;
    target.durChapterTitle = oldBook.durChapterTitle;
    target.durChapterTime = oldBook.durChapterTime;
    target.syncTime = oldBook.syncTime;
    target.pendingAddToShelf = oldBook.pendingAddToShelf;
    target.isPrivate = oldBook.isPrivate;
    if (this.markReadOnSwitch) {
      target.putVariable('readStarted', '1');
      target.putVariable('lastReadTime', `${Date.now()}`);
    }
  }

}
