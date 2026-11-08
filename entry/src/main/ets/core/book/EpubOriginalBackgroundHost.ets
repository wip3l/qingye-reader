import { common } from '@kit.AbilityKit';
import { Book, BookChapter, ReaderActionMarker } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { LocalChapterContentLoader } from './LocalChapterContentLoader';
import { ReaderImageMarker } from './ReaderImageMarker';
import { EpubOriginalPosition, EpubOriginalSpot } from './EpubOriginalPosition';
import { EpubReadAloudHost, EpubSpeechText } from './EpubOriginalReadAloud';
import { ReaderProgressCheckpoint } from '../../utils/ReaderProgressCheckpoint';
import { HdsFeedback } from '../../utils/HdsFeedback';

/** 与文件排版页、普通阅读页共用的章内字符偏移（见 EpubOriginalReadBook 的同名常量）。 */
const NATIVE_OFFSET_KEY = 'readProgressCharOffsetV2';
const NATIVE_OFFSET_CHAPTER_KEY = 'readProgressCharOffsetChapterV2';
/** 后台朗读时最多隔这么久写一次进度（换章时立即写）。 */
const SAVE_INTERVAL_MS = 5000;

/** 离开文件排版页时页面交给后台朗读的东西：书、目录与显示用的封面。 */
export class EpubOriginalBackgroundSeed {
  context: common.UIAbilityContext | null = null;
  ui: UIContext | null = null;
  book: Book | null = null;
  chapters: BookChapter[] = [];
  chapterIndex: number = 0;
  /** 页面关掉时屏幕上的位置：朗读要从“当前屏”重新开始时（翻页后还没来得及重开）从这里念。 */
  spot: EpubOriginalSpot | null = null;
  cover: ResourceStr = '';
  coverRaw: ResourceStr = '';
  /** 朗读写进度的身份（与悬浮朗读会话同一个）。 */
  ownerId: string = '';
}

/**
 * 文件排版页关掉后接着朗读用的“页面”：网页没有了，文字改读应用排版的章节正文（与普通阅读页相同，
 * 偏移就是两种排版共用的章内偏移），念到哪里存到哪里；重新打开这本书时文件排版页按这个偏移定位并接手。
 * 普通阅读页（或文件排版页）在前台打开了同一本书时，ReaderProgressCheckpoint 不再让这里写进度。
 */
export class EpubOriginalBackgroundHost implements EpubReadAloudHost {
  private readonly seed: EpubOriginalBackgroundSeed;
  private readonly titles: string[];
  private chapter: number;
  private initialSpot: EpubOriginalSpot | null;
  private fraction: number = 0;
  /** 当前章的正文（未去标记）与朗读用文字（标记换成空格，长度不变）。 */
  private contentChapter: number = -1;
  private content: string = '';
  private speechText: string = '';
  private pendingOffset: number = -1;
  private pendingChapter: number = -1;
  private lastSavedAt: number = 0;
  private saveTask: Promise<void> = Promise.resolve();

  constructor(seed: EpubOriginalBackgroundSeed) {
    this.seed = seed;
    this.chapter = Math.max(0, Math.min(seed.chapters.length - 1, seed.chapterIndex));
    this.initialSpot = seed.spot && seed.spot.snippet ? seed.spot : null;
    this.titles = seed.chapters.map((chapter: BookChapter, index: number): string =>
      chapter.title || `第${index + 1}章`);
  }

  context = (): common.UIAbilityContext => this.seed.context as common.UIAbilityContext;
  bookUrl = (): string => this.seed.book?.bookUrl || '';
  bookName = (): string => this.seed.book?.name || '';
  author = (): string => this.seed.book?.author || '';
  chapterIndex = (): number => this.chapter;
  chapterTitles = (): string[] => this.titles;
  chapterProgress = (): number => this.fraction;
  positionLabel = (): string => `${Math.round(this.fraction * 100)}%`;
  cover = (): ResourceStr => this.seed.cover;
  coverRaw = (): ResourceStr => this.seed.coverRaw;
  clearFocus = (): void => {};
  changed = (): void => {};

  speech = async (): Promise<EpubSpeechText | null> => {
    const index = this.chapter;
    await this.loadContent(index);
    if (index !== this.chapter) return null;
    const speech = new EpubSpeechText();
    speech.text = this.speechText;
    speech.start = 0;
    const spot = this.initialSpot;
    if (spot && index === this.seed.chapterIndex && this.content) {
      speech.start = Math.max(0, EpubOriginalPosition.offsetFor(this.content, spot));
    }
    this.initialSpot = null;
    return speech;
  };

  /** 记下念到哪里：本章的偏移若是网页文字里的（刚离开页面那一章），按文字片段换算成正文偏移。 */
  focus = (start: number, _end: number, text: string): void => {
    const index = this.chapter;
    this.fraction = text.length > 0 ? Math.max(0, Math.min(1, start / text.length)) : 0;
    this.loadContent(index).then((): void => {
      if (index !== this.chapter) return;
      const offset = text === this.speechText ? start :
        EpubOriginalPosition.offsetFor(this.content, EpubOriginalPosition.spotAt(text, start));
      this.queueSave(index, offset, false);
    }).catch((error: Error): void => console.warn('[EpubTtsBackground] focus failed:', error));
  };

  openChapter = (index: number): Promise<boolean> => {
    if (index < 0 || index >= this.titles.length) return Promise.resolve(false);
    this.chapter = index;
    this.fraction = 0;
    this.queueSave(index, 0, true);
    return Promise.resolve(true);
  };

  openMimoSettings = (): void => {
    const ui = this.seed.ui;
    if (!ui) {
      HdsFeedback.showToast('请在阅读页里打开 MiMo 朗读设置');
      return;
    }
    ui.getRouter().pushUrl({ url: 'pages/MimoSettings' }).catch((error: Error): void => {
      console.warn('[EpubTtsBackground] open MiMo settings failed:', error);
    });
  };

  /** 朗读停了：把最后的位置写下去，并通知书架刷新进度。 */
  stopped = (): void => {
    this.flush(true);
  };

  private async loadContent(index: number): Promise<void> {
    if (this.contentChapter === index) return;
    const book = this.seed.book;
    const chapter = this.seed.chapters[index];
    let content = '';
    try {
      content = book ? await appDb.getCachedChapterContent(book.bookUrl, index) : '';
      if (!content && book && chapter) content = await LocalChapterContentLoader.load(book, chapter);
    } catch (error) {
      console.warn('[EpubTtsBackground] load chapter failed:', index, error);
    }
    this.contentChapter = index;
    this.content = content || '';
    this.speechText = EpubOriginalBackgroundHost.speakable(this.content);
  }

  /** 正文里的图片、注释等标记换成同样长度的空格：念的时候跳过，偏移仍与正文一致。 */
  static speakable(content: string): string {
    let result = '';
    let cursor = 0;
    while (cursor < content.length) {
      const action = ReaderActionMarker.findFirstRawRange(content, cursor);
      const imageStart = content.indexOf(ReaderImageMarker.PREFIX, cursor);
      const imageEnd = imageStart >= 0 ? content.indexOf(ReaderImageMarker.SUFFIX, imageStart) : -1;
      const nextAction = action.length >= 2 ? action[0] : content.length;
      const nextImage = imageStart >= 0 && imageEnd >= 0 ? imageStart : content.length;
      const next = Math.min(nextAction, nextImage);
      result += content.substring(cursor, next);
      if (next >= content.length) break;
      const end = next === nextAction ? action[1] : imageEnd + ReaderImageMarker.SUFFIX.length;
      result += ' '.repeat(Math.max(0, end - next));
      cursor = end;
    }
    return result;
  }

  private queueSave(index: number, offset: number, chapterChanged: boolean): void {
    this.pendingChapter = index;
    this.pendingOffset = Math.max(0, Math.round(offset));
    if (chapterChanged || Date.now() - this.lastSavedAt >= SAVE_INTERVAL_MS) this.flush(chapterChanged);
  }

  private flush(notifyShelf: boolean): void {
    const index = this.pendingChapter;
    const offset = this.pendingOffset;
    const book = this.seed.book;
    if (index < 0 || !book || !ReaderProgressCheckpoint.canWrite(this.seed.ownerId)) return;
    this.lastSavedAt = Date.now();
    const timestamp = this.lastSavedAt;
    const title = this.titles[index] || '';
    const fraction = this.fraction;
    this.saveTask = this.saveTask.catch((): void => {}).then(async (): Promise<void> => {
      const latest = await appDb.getBook(book.bookUrl);
      if (!latest) return;
      const pageCount = Math.max(1, Number(latest.getVariable('readProgressPageCount')) || 1);
      latest.putVariable('readStarted', '1');
      latest.putVariable('lastReadTime', `${timestamp}`);
      latest.putVariable('readProgressChapterIndex', `${index}`);
      latest.putVariable(NATIVE_OFFSET_KEY, `${offset}`);
      latest.putVariable(NATIVE_OFFSET_CHAPTER_KEY, `${index}`);
      await appDb.updateBookReadingProgress(book.bookUrl, title, index,
        Math.min(pageCount - 1, Math.floor(fraction * pageCount)), timestamp, latest.variable, true);
      if (notifyShelf) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    }).catch((error: Error): void => console.warn('[EpubTtsBackground] save progress failed:', error));
  }
}
