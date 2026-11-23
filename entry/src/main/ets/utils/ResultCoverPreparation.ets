import { Context } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { fileUri } from '../platform/FileUri';
import { Book, SearchBook } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { BookDisplayHelper } from './BookDisplayHelper';
import { BookIdentity } from './BookIdentity';
import { BookCoverResolver } from './BookCoverResolver';
import { CoverGallerySnapshot, CoverGalleryStore } from './CoverGalleryStore';
import { CoverGallerySettings } from './CoverGallerySettings';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';
import { SearchBookShelfHelper } from './SearchBookShelfHelper';
import { ThemeBookCoverSettings } from './ThemeBookCoverSettings';

/** Only settled selections reach a visible result card. An empty selection is a final fallback. */
export class PreparedResultCover {
  firstImage: string = '';
  covers: ResourceStr[] = [];
  frame: string = '';
  interval: number = 3500;
  /** 用的是主题自带的书籍封面（可能没有书框），深色模式调暗封面时不调暗。 */
  themeCover: boolean = false;
}

export class ResultCoverOptions {
  showCover: boolean = true;
  useBookshelf: boolean = false;
  darkMode: boolean = false;
  themeEnabled: boolean = false;
  frameEnabled: boolean = false;
  themeRevision: number = 0;
  shelfRevision: number = 0;
  gallery: CoverGallerySnapshot = new CoverGallerySnapshot();
}

export class ResultCoverPreparation {
  private static validating: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private static validated: Set<string> = new Set<string>();

  static options(showCover: boolean, useBookshelf: boolean, darkMode: boolean): ResultCoverOptions {
    const options = new ResultCoverOptions();
    options.showCover = showCover;
    options.useBookshelf = useBookshelf;
    options.darkMode = darkMode;
    options.themeEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    options.frameEnabled = ThemeBookCoverSettings.frameEnabledFromStorage();
    options.themeRevision = AppStorage.get<number>('themeRevision') || 0;
    options.shelfRevision = AppStorage.get<number>('shelfUpdateTime') || 0;
    options.gallery = CoverGalleryStore.snapshotFromStorage();
    return options;
  }

  static signature(book: SearchBook, options: ResultCoverOptions): string {
    return JSON.stringify([book.origin, book.bookUrl, book.coverUrl, book.name, book.author, options]);
  }

  static bookOf(result: SearchBook): Book {
    const book = new Book();
    book.bookUrl = result.bookUrl;
    book.origin = result.origin;
    book.originName = result.originName;
    book.name = result.name;
    book.author = result.author;
    book.coverUrl = result.coverUrl;
    book.type = result.type;
    book.tocUrl = result.tocUrl;
    book.variable = result.variable;
    return book;
  }

  static async prepare(context: Context, result: SearchBook, options: ResultCoverOptions): Promise<PreparedResultCover> {
    const prepared = new PreparedResultCover();
    if (!options.showCover) return prepared;
    let book = ResultCoverPreparation.bookOf(result);
    let candidates: ResourceStr[] = [];
    // 主题边框和封面来源无关，用书架封面时都套。
    const frame: ResourceStr = options.useBookshelf ? ThemeBookCoverSettings.frameIf(options.darkMode, options.frameEnabled) : '';
    // 书架上的同一本书单独设置过封面时，搜索/发现结果也只显示那张，不走主题封面和图集。
    const customShelfBook = options.useBookshelf ?
      await ResultCoverPreparation.shelfBookWithCustomCover(context, book) : null;
    if (customShelfBook) {
      book = customShelfBook;
      candidates = BookCoverResolver.sourceCovers(book, options.darkMode, options.gallery);
    } else if (options.useBookshelf && ThemeBookCoverSettings.enabled(options.darkMode, options.themeEnabled)) {
      candidates = ThemeBookCoverSettings.covers(book, options.darkMode, options.gallery.coverMode);
      prepared.themeCover = true;
      prepared.interval = ThemeBookCoverSettings.interval(book);
    } else if (options.useBookshelf) {
      // 统一封面只用图集的书不必知道它有没有封面；其余情况（和自带封面轮播、只给没有封面的书兜底）要先把书源封面补上。
      candidates = CoverGallerySettings.replaceOnlyAlbumCovers(book, options.darkMode, options.gallery);
      if (candidates.length === 0) {
        await AppDatabase.getInstance().initWithContext(context);
        const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(BookIdentity.keyOfBook(book));
        if (shelfBook) book = shelfBook;
        if (!book.coverUrl && !book.customCoverUrl) book = await ResultCoverPreparation.completeSourceCover(book);
        candidates = BookCoverResolver.sourceCovers(book, options.darkMode, options.gallery);
        if (candidates.length === 0 && ThemeBookCoverSettings.enabledFor(book, options.darkMode, false, options.gallery)) {
          candidates = ThemeBookCoverSettings.covers(book, options.darkMode, options.gallery.coverMode);
          prepared.themeCover = true;
          prepared.interval = ThemeBookCoverSettings.interval(book);
        }
      }
    } else {
      if (!book.coverUrl) book = await ResultCoverPreparation.completeSourceCover(book);
      const sourceCover = CoverUrlNormalizer.normalize(book.coverUrl);
      candidates = sourceCover ? [sourceCover] : [];
    }
    for (let index = 0; index < candidates.length; index++) {
      const first = await ResultCoverPreparation.prepareImage(context, candidates[index]);
      if (!first) continue;
      prepared.firstImage = first;
      // Keep the remaining carousel choices, but never start by displaying an unresolved source.
      prepared.covers = [first, ...candidates.slice(index + 1)];
      if (frame) prepared.frame = await ResultCoverPreparation.prepareImage(context, frame);
      return prepared;
    }
    if (options.useBookshelf && candidates.length > 0 && (!options.gallery.replaceAlbum || options.gallery.albumMix)) {
      // A broken/missing custom image is not proof that the source book has no cover.
      const fallback = new ResultCoverOptions();
      fallback.darkMode = options.darkMode;
      return ResultCoverPreparation.prepare(context, result, fallback);
    }
    // 没有图时显示首字占位，边框照样套，和书架一致。
    if (frame) prepared.frame = await ResultCoverPreparation.prepareImage(context, frame);
    return prepared;
  }

  private static async shelfBookWithCustomCover(context: Context, book: Book): Promise<Book | null> {
    try {
      await AppDatabase.getInstance().initWithContext(context);
      const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(BookIdentity.keyOfBook(book));
      return shelfBook && BookDisplayHelper.hasCustomCover(shelfBook) ? shelfBook : null;
    } catch (e) {
      return null;
    }
  }

  private static async completeSourceCover(book: Book): Promise<Book> {
    if (!book.origin || !book.bookUrl) return book;
    try {
      const source = await AppDatabase.getInstance().getBookSource(book.origin);
      if (!source || !(source.bookInfoRule.coverUrl || '').trim()) return book;
      // 给搜索、发现结果补封面是后台工作，不弹验证网页。
      return await new WebBookService().setSourceInteraction((): boolean => false).getBookInfo(source, book);
    } catch (_) {
      // A failed details request has no usable cover; it must not leave the result hidden forever.
      return book;
    }
  }

  static async prepareImage(context: Context, cover: ResourceStr): Promise<string> {
    const key = JSON.stringify(cover);
    const existing = ResultCoverPreparation.validating.get(key);
    if (existing) return existing;
    const task = ResultCoverPreparation.decodeImage(context, cover);
    ResultCoverPreparation.validating.set(key, task);
    try {
      return await task;
    } finally {
      if (ResultCoverPreparation.validating.get(key) === task) ResultCoverPreparation.validating.delete(key);
    }
  }

  private static async decodeImage(context: Context, cover: ResourceStr): Promise<string> {
    let source: image.ImageSource | null = null;
    let pixels: image.PixelMap | null = null;
    try {
      const path = await BookCoverResolver.prepareFile(context, cover);
      if (!path || !(await fs.access(path))) return '';
      if (!ResultCoverPreparation.validated.has(path)) {
        source = image.createImageSource(path);
        pixels = await source.createPixelMap({ desiredSize: { width: 360, height: 480 } });
        if (ResultCoverPreparation.validated.size >= 256) ResultCoverPreparation.validated.clear();
        ResultCoverPreparation.validated.add(path);
      }
      return fileUri.getUriFromPath(path);
    } catch (_) {
      return '';
    } finally {
      // Do not retain a decoded bitmap for every search result (hundreds of covers).
      if (pixels) await pixels.release();
      if (source) await source.release();
    }
  }
}
