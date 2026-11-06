import { common, Want } from '@kit.AbilityKit';
import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { LocalBookService } from '../core/book/LocalBookService';
import { ReaderProgressCheckpoint } from './ReaderProgressCheckpoint';
import { RecentReadShortcut } from './RecentReadShortcut';
import { HdsFeedback } from './HdsFeedback';

const PAYLOAD_KEY: string = 'qingyeContinueReading';
export const QYBOOK_EXTENSION: string = '.qybook';
export const QYBOOK_UTD: string = 'io.legado.read.qybook';
const PAYLOAD_VERSION: number = 1;
// 页码（durChapterPos）跟屏幕排版走，换设备后靠字符锚点恢复；这几项与数据备份保留的阅读进度一致。
const PROGRESS_VARIABLE_KEYS: string[] = ['readStarted', 'lastReadTime', 'readProgressChapterIndex',
  'readProgressPageCount', 'readProgressCharOffsetV2', 'readProgressCharOffsetChapterV2'];
const CHECKPOINT_WAIT_MS: number = 600;
// 接续参数整体上限约 100KB；书源运行时变量偶尔很大，超出时只带书籍基本信息。
const PAYLOAD_SOFT_LIMIT: number = 60 * 1024;
const TOAST_RETRY_MS: number = 800;
const TOAST_RETRY_LIMIT: number = 6;

class ContinuationBook {
  bookUrl: string = '';
  tocUrl: string = '';
  origin: string = '';
  originName: string = '';
  name: string = '';
  author: string = '';
  kind: string = '';
  status: string = '';
  coverUrl: string = '';
  intro: string = '';
  type: number = 0;
  latestChapterTitle: string = '';
  totalChapterNum: number = 0;
  wordCount: string = '';
  variable: string = '';
  pendingAddToShelf: boolean = false;
}

class ContinuationPayload {
  version: number = PAYLOAD_VERSION;
  localContentHash: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  chapterPos: number = 0;
  updatedAt: number = 0;
  progressVariables: Record<string, string> = {};
  book: ContinuationBook = new ContinuationBook();
}

/**
 * 跨设备接续：在读的书和进度随任务流转到另一台设备，对端直接打开到同一位置。
 * 不迁移页面栈，对端照常启动后按书籍地址打开阅读页；没有在读的书时只把应用接续过去。
 * API 12 起接续不需要 DISTRIBUTED_DATASYNC 权限，数据只走 wantParam，不要再加回启动时申请（上架检测判为提前索权）。
 */
export class ReadingContinuation {
  static async collect(context: common.Context, wantParam: Record<string, Object>): Promise<void> {
    wantParam['ohos.extra.param.key.supportContinuePageStack'] = false;
    // 接续后本机不退出，正在听书的不会被打断。
    wantParam['ohos.extra.param.key.supportContinueSourceExit'] = false;
    const bookUrl = ReaderProgressCheckpoint.activeBookUrl();
    if (!bookUrl) return;
    await Promise.race([
      ReaderProgressCheckpoint.request('continuation'),
      new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, CHECKPOINT_WAIT_MS);
      })
    ]);
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const book = await db.getBook(bookUrl);
    const raw = book ? ReadingContinuation.payloadFor(book) : '';
    if (raw) wantParam[PAYLOAD_KEY] = raw;
  }

  /** 书和进度打包成文本；接续和碰一碰发出的 .qybook 文件共用。不能打包时返回空串。 */
  static payloadFor(book: Book): string {
    if (!book.name) return '';
    const payload = new ContinuationPayload();
    payload.localContentHash = LocalBookService.isLocalBook(book) ?
      ReadingContinuation.text(book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY)).trim() : '';
    if (LocalBookService.isLocalBook(book) && !payload.localContentHash) return '';
    payload.chapterTitle = book.durChapterTitle;
    payload.chapterIndex = book.durChapterIndex;
    payload.chapterPos = book.durChapterPos;
    payload.updatedAt = book.durChapterTime;
    for (const key of PROGRESS_VARIABLE_KEYS) {
      const value = ReadingContinuation.text(book.getVariable(key));
      if (value) payload.progressVariables[key] = value;
    }
    if (!LocalBookService.isLocalBook(book)) payload.book = ReadingContinuation.describe(book);
    payload.book.name = book.name;
    payload.book.author = book.author;
    let raw = JSON.stringify(payload);
    if (raw.length > PAYLOAD_SOFT_LIMIT) {
      payload.book.variable = '';
      payload.book.intro = '';
      raw = JSON.stringify(payload);
    }
    return raw.length <= PAYLOAD_SOFT_LIMIT ? raw : '';
  }

  /** 对端收到接续：有书就记下进度并排队打开，返回 true；没有书返回 false，照常启动。 */
  static accept(context: common.Context, want: Want): boolean {
    const raw = want.parameters ? want.parameters[PAYLOAD_KEY] : undefined;
    if (typeof raw !== 'string' || !raw) return false;
    ReadingContinuation.acceptRaw(context, raw);
    return true;
  }

  /** 打开碰一碰收到的 .qybook 文件，或接续带来的数据。 */
  static acceptRaw(context: common.Context, raw: string): void {
    ReadingContinuation.apply(context, raw).catch((error: Error): void => {
      console.warn('[ReadingContinuation] apply failed:', error);
      ReadingContinuation.toast('打开书籍失败，请在书架中打开');
    });
  }

  private static async apply(context: common.Context, raw: string): Promise<void> {
    const payload = ReadingContinuation.parse(raw);
    if (!payload) return;
    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    let book = payload.localContentHash ? await db.getBookByLocalContentHash(payload.localContentHash) :
      await db.getBook(payload.book.bookUrl);
    if (!book && !payload.localContentHash && payload.book.bookUrl && payload.book.origin &&
      await db.getBookSource(payload.book.origin)) {
      book = ReadingContinuation.restore(payload);
      await db.insertBook(book, 'continuation');
    } else if (book && (!Book.hasStartedReading(book) || payload.updatedAt >= book.durChapterTime)) {
      for (const key of ReadingContinuation.progressKeys(payload)) {
        book.putVariable(key, payload.progressVariables[key]);
      }
      await db.updateBookReadingProgress(book.bookUrl, payload.chapterTitle, payload.chapterIndex,
        payload.chapterPos, payload.updatedAt, book.variable);
    }
    if (!book) {
      const name = payload.book.name ? `《${payload.book.name}》` : '这本书';
      ReadingContinuation.toast(payload.localContentHash ? `这台设备上没有${name}的本地文件` :
        `这台设备上没有${name}的书源，请先导入书源`);
      return;
    }
    RecentReadShortcut.requestBook(book.bookUrl);
  }

  /**
   * 文件来自别的设备，字段逐个收敛成本地期望的类型，坏掉或伪造的文件不会把字符串页码之类写进数据库；
   * 版本不符或没有书籍信息时返回 null。
   */
  private static parse(raw: string): ContinuationPayload | null {
    const source = JSON.parse(raw) as Record<string, Object>;
    if (!source || typeof source !== 'object') return null;
    if (ReadingContinuation.integer(source['version'], 0) !== PAYLOAD_VERSION) return null;
    const bookSource = source['book'];
    if (!bookSource || typeof bookSource !== 'object') return null;
    const payload = new ContinuationPayload();
    payload.localContentHash = ReadingContinuation.text(source['localContentHash']).trim();
    payload.chapterTitle = ReadingContinuation.text(source['chapterTitle']);
    payload.chapterIndex = Math.max(0, ReadingContinuation.integer(source['chapterIndex'], 0));
    payload.chapterPos = Math.max(0, ReadingContinuation.integer(source['chapterPos'], 0));
    payload.updatedAt = Math.max(0, ReadingContinuation.integer(source['updatedAt'], 0));
    const variables = source['progressVariables'];
    if (variables && typeof variables === 'object') {
      const map = variables as Record<string, Object>;
      for (const key of PROGRESS_VARIABLE_KEYS) {
        const value = ReadingContinuation.text(map[key]);
        if (value) payload.progressVariables[key] = value;
      }
    }
    const book = bookSource as Record<string, Object>;
    payload.book.bookUrl = ReadingContinuation.text(book['bookUrl']);
    payload.book.tocUrl = ReadingContinuation.text(book['tocUrl']);
    payload.book.origin = ReadingContinuation.text(book['origin']);
    payload.book.originName = ReadingContinuation.text(book['originName']);
    payload.book.name = ReadingContinuation.text(book['name']);
    payload.book.author = ReadingContinuation.text(book['author']);
    payload.book.kind = ReadingContinuation.text(book['kind']);
    payload.book.status = ReadingContinuation.text(book['status']);
    payload.book.coverUrl = ReadingContinuation.text(book['coverUrl']);
    payload.book.intro = ReadingContinuation.text(book['intro']);
    payload.book.type = ReadingContinuation.integer(book['type'], 0);
    payload.book.latestChapterTitle = ReadingContinuation.text(book['latestChapterTitle']);
    payload.book.totalChapterNum = Math.max(0, ReadingContinuation.integer(book['totalChapterNum'], 0));
    payload.book.wordCount = ReadingContinuation.text(book['wordCount']);
    payload.book.variable = ReadingContinuation.text(book['variable']);
    payload.book.pendingAddToShelf = book['pendingAddToShelf'] === true;
    return payload;
  }

  private static text(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'string' ? value : (typeof value === 'number' || typeof value === 'boolean' ?
      String(value) : '');
  }

  private static integer(value: Object | undefined, fallback: number): number {
    const parsed = typeof value === 'number' ? value : Number(ReadingContinuation.text(value) || 'NaN');
    return Number.isFinite(parsed) ? Math.round(parsed) : fallback;
  }

  /** 冷启动接续时窗口可能还没加载，Toast 没有 UI 实例会抛错；等首页起来再试几次。 */
  private static toast(message: string, attempt: number = 0): void {
    try {
      HdsFeedback.showToast(message);
    } catch (error) {
      if (attempt >= TOAST_RETRY_LIMIT) {
        console.warn('[ReadingContinuation] toast dropped:', message, error);
        return;
      }
      setTimeout((): void => ReadingContinuation.toast(message, attempt + 1), TOAST_RETRY_MS);
    }
  }

  private static progressKeys(payload: ContinuationPayload): string[] {
    return payload.progressVariables ? Object.keys(payload.progressVariables) : [];
  }

  private static describe(book: Book): ContinuationBook {
    const result = new ContinuationBook();
    result.bookUrl = book.bookUrl;
    result.tocUrl = book.tocUrl;
    result.origin = book.origin;
    result.originName = book.originName;
    result.kind = book.kind;
    result.status = book.status;
    result.coverUrl = book.coverUrl;
    result.intro = book.intro;
    result.type = book.type;
    result.latestChapterTitle = book.latestChapterTitle;
    result.totalChapterNum = book.totalChapterNum;
    result.wordCount = book.wordCount;
    result.variable = book.variable;
    result.pendingAddToShelf = book.pendingAddToShelf;
    return result;
  }

  private static restore(payload: ContinuationPayload): Book {
    const source = payload.book;
    const book = new Book();
    book.bookUrl = source.bookUrl;
    book.tocUrl = source.tocUrl;
    book.origin = source.origin;
    book.originName = source.originName;
    book.name = source.name;
    book.author = source.author;
    book.kind = source.kind;
    book.status = source.status;
    book.coverUrl = source.coverUrl;
    book.intro = source.intro;
    book.type = source.type;
    book.latestChapterTitle = source.latestChapterTitle;
    book.totalChapterNum = source.totalChapterNum;
    book.wordCount = source.wordCount;
    book.variable = source.variable || '';
    book.pendingAddToShelf = source.pendingAddToShelf;
    book.durChapterTitle = payload.chapterTitle;
    book.durChapterIndex = payload.chapterIndex;
    book.durChapterPos = payload.chapterPos;
    book.durChapterTime = payload.updatedAt;
    for (const key of ReadingContinuation.progressKeys(payload)) {
      book.putVariable(key, payload.progressVariables[key]);
    }
    return book;
  }
}
