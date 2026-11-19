import { Context } from '@kit.AbilityKit';
import { Book, BookChapter, SearchBook, BookFieldSanitizer, BookTypeSupport, SourceEngineHost } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ChangeSourceResultCache } from '../../utils/ChangeSourceResultCache';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';
import { WebBookService } from './WebBookService';
import { SourceSwitchOperation } from './SourceSwitchOperation';
import { ChapterPositionMatcher } from './ChapterPositionMatcher';

/** 一个候选准备好的换源结果：新源详情与目录已取到、阅读位置已对好，还没有写库。 */
export class PreparedSourceSwitch {
  key: string = '';
  target: Book = new Book();
  candidate: SearchBook = new SearchBook();
  previousUrl: string = '';
  previousVersion: string = '';
  oldBook: Book | null = null;
  fullBook: Book = new Book();
  chapters: BookChapter[] = [];
}

/**
 * Owns preparation and commit independently of the dialog's lifetime.
 * 手动换源走 run（准备后立即提交）；批量换源对几个候选各 prepare 一次，挑好后另起一个任务 commit，
 * 这样每个任务的总时限只管自己那一段。
 */
export class BookSourceSwitchTask {
  private static active: Set<string> = new Set();
  private static revisions: Map<string, number> = new Map();
  private static revisionSerial: number = 0;
  private operation: SourceSwitchOperation;
  private service: WebBookService;
  private markReadOnSwitch: boolean;

  constructor(markRead: boolean, totalTimeoutMs: number = 90000) {
    this.markReadOnSwitch = markRead;
    this.operation = new SourceSwitchOperation((): void => this.service.cancelPendingRequests(), totalTimeoutMs);
    this.service = new WebBookService((): boolean => this.operation.isCancelled(), true);
  }

  cancel(): void { this.operation.cancel(); }
  isCommitting(): boolean { return this.operation.isCommitting(); }

  /** 用完后收尾：停掉还在途的请求。提交已开始时不会被打断。 */
  release(): void {
    this.operation.cancel();
    this.service.cancelPendingRequests();
  }

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
    BookSourceSwitchTask.active.add(key);
    try {
      const prepared = await this.prepare(context, key, target, candidate, beforeSwitch, progress);
      return await this.commitPrepared(context, prepared, progress, committed);
    } finally {
      BookSourceSwitchTask.active.delete(key);
      this.release();
    }
  }

  /** 取新源详情与目录并对好阅读位置；不写库，也不记换源历史。 */
  async prepare(context: Context, key: string, target: Book, candidate: SearchBook,
    beforeSwitch: (() => Promise<void>) | null, progress: (label: string) => void): Promise<PreparedSourceSwitch> {
    const previousUrl = target.bookUrl;
    const op = this.operation;
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
    progress('正在加载新源目录…');
    this.service.setCatalogProgress((pages: number, chapterCount: number): void => {
      if (!op.isCancelled()) progress(`正在加载新源目录：已读 ${pages} 页 · ${chapterCount} 章`);
    });
    const chapters = await op.stage('加载新源目录', 60000, () => this.service.getChapterList(source, fullBook, 0, false));
    this.service.setCatalogProgress(null);
    if (chapters.length === 0) throw new Error(SourceEngineHost.getError(source) || '新书源目录为空，已保留原书源');
    fullBook.totalChapterNum = chapters.length;
    const previous = oldBook || target;
    const safeIndex = ChapterPositionMatcher.match(previous.durChapterIndex, previous.durChapterTitle,
      previous.totalChapterNum, chapters);
    fullBook.durChapterIndex = safeIndex;
    fullBook.durChapterTitle = chapters[safeIndex].title;
    fullBook.latestChapterTitle = chapters[chapters.length - 1].title;
    op.check();
    const prepared = new PreparedSourceSwitch();
    prepared.key = key;
    prepared.target = target;
    prepared.candidate = candidate;
    prepared.previousUrl = previousUrl;
    prepared.previousVersion = target.origin + '\n' + previousUrl;
    prepared.oldBook = oldBook;
    prepared.fullBook = fullBook;
    prepared.chapters = chapters;
    return prepared;
  }

  /** 批量换源提交挑中的候选：同一本书不与别的换源同时保存，用完即收尾。 */
  async commit(context: Context, prepared: PreparedSourceSwitch, progress: (label: string) => void,
    committed: (book: Book, previousUrl: string) => void, expectedRevision: number): Promise<Book> {
    if (BookSourceSwitchTask.active.has(prepared.key)) throw new Error('上一次换源仍在保存，请稍后重试');
    if (expectedRevision !== BookSourceSwitchTask.revisionOf(prepared.target)) throw new Error('这本书已经换过源');
    BookSourceSwitchTask.active.add(prepared.key);
    try {
      return await this.commitPrepared(context, prepared, progress, committed);
    } finally {
      BookSourceSwitchTask.active.delete(prepared.key);
      this.release();
    }
  }

  private async commitPrepared(context: Context, prepared: PreparedSourceSwitch, progress: (label: string) => void,
    committed: (book: Book, previousUrl: string) => void): Promise<Book> {
    const op = this.operation;
    const fullBook = prepared.fullBook;
    op.check();
    // Bind aliases before the commit boundary, including rewritten detail URLs/metadata.
    ChangeSourceResultCache.rememberSwitch(context, prepared.key, prepared.oldBook || prepared.target);
    ChangeSourceResultCache.rememberSwitch(context, prepared.key, fullBook);
    ChangeSourceResultCache.rememberRename(context, prepared.key, fullBook.origin, prepared.candidate.bookUrl,
      fullBook.bookUrl);
    await op.stage('保存换源记录', 5000, () => ChangeSourceResultCache.flush(context));
    op.beginCommit();
    progress('正在保存切换结果…');
    if (prepared.oldBook) {
      await AppDatabase.getInstance().commitBookSourceSwitch(prepared.previousUrl, fullBook, prepared.chapters);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    }
    BookSourceSwitchTask.revisions.set(prepared.previousVersion, ++BookSourceSwitchTask.revisionSerial);
    // Delivery survives dialog disposal once the atomic commit has started.
    try { committed(fullBook, prepared.previousUrl); } catch (error) {
      console.error('换源已提交，页面更新失败:', error);
    }
    return fullBook;
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
