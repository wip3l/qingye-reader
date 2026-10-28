import { Context } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Book, SearchBook } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
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
}

export class ResultCoverOptions {
  showCover: boolean = true;
  useBookshelf: boolean = false;
  darkMode: boolean = false;
  themeEnabled: boolean = false;
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

  /** Custom albums take the direct path when applicable, even when source covers are also enabled. */
  static albumCovers(book: Book, options: ResultCoverOptions): string[] {
    const settings = options.gallery;
    return CoverGallerySettings.getDisplayCoverList(book, options.darkMode, settings.albumsRaw,
      settings.lightAlbumId, settings.darkAlbumId, settings.applyScope, settings.targetBooksRaw,
      true, settings.coverMode);
  }

  static async prepare(context: Context, result: SearchBook, options: ResultCoverOptions): Promise<PreparedResultCover> {
    const prepared = new PreparedResultCover();
    if (!options.showCover) return prepared;
    let book = ResultCoverPreparation.bookOf(result);
    let candidates: ResourceStr[] = [];
    let frame: ResourceStr = '';
    if (options.useBookshelf && ThemeBookCoverSettings.enabled(options.darkMode, options.themeEnabled)) {
      candidates = ThemeBookCoverSettings.covers(book, options.darkMode);
      frame = ThemeBookCoverSettings.frame(options.darkMode);
      prepared.interval = ThemeBookCoverSettings.interval(book);
    } else if (options.useBookshelf) {
      candidates = ResultCoverPreparation.albumCovers(book, options);
      if (candidates.length === 0) {
        await AppDatabase.getInstance().initWithContext(context);
        const shelfBook = await SearchBookShelfHelper.findShelfBookByKey(BookIdentity.keyOfBook(book));
        if (shelfBook) book = shelfBook;
        if (!book.coverUrl && !book.customCoverUrl && !options.gallery.ignoreSourceCover) {
          book = await ResultCoverPreparation.completeSourceCover(book);
        }
        candidates = BookCoverResolver.sourceCovers(book, options.darkMode, options.gallery);
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
    if (options.useBookshelf && candidates.length > 0 && !options.gallery.ignoreSourceCover) {
      // A broken/missing custom image is not proof that the source book has no cover.
      const fallback = new ResultCoverOptions();
      fallback.darkMode = options.darkMode;
      return ResultCoverPreparation.prepare(context, result, fallback);
    }
    return prepared;
  }

  private static async completeSourceCover(book: Book): Promise<Book> {
    if (!book.origin || !book.bookUrl) return book;
    try {
      const source = await AppDatabase.getInstance().getBookSource(book.origin);
      if (!source || !(source.bookInfoRule.coverUrl || '').trim()) return book;
      return await new WebBookService().getBookInfo(source, book);
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
