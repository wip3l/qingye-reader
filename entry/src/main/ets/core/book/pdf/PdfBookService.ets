import { Context } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { Book, BookChapter } from '@legado/sourceengine';
import { appDb } from '../../../model/data/AppDatabase';
import { PdfImportTask } from '../../concurrency/PdfImportTask';
import { PdfOutlineEntry, PdfPagePosition } from './PdfModels';

export class PdfBookService {
  static readonly PARSER_VERSION: string = '1';
  private static serial: number = 0;
  private static queue: Promise<void> = Promise.resolve();

  /** Original and derived files form one immutable revision. The database switches revisions atomically. */
  static async import(context: Context, book: Book, source: string, id: string,
    fallbackTitle: string, fallbackAuthor: string, hashFile: (path: string) => Promise<string>): Promise<Book> {
    const previous = PdfBookService.queue;
    let release: () => void = (): void => {};
    PdfBookService.queue = new Promise<void>((resolve: () => void): void => { release = resolve; });
    await previous;
    try { return await PdfBookService.importRevision(context, book, source, id, fallbackTitle, fallbackAuthor, hashFile); }
    finally { release(); }
  }

  private static async importRevision(context: Context, book: Book, source: string, id: string,
    fallbackTitle: string, fallbackAuthor: string, hashFile: (path: string) => Promise<string>): Promise<Book> {
    const oldPath = book.getVariable('localFilePath');
    const oldRoot = book.getVariable('localExtractRoot');
    const root = `${context.filesDir}/local_books/${id}_pdf_${Date.now()}_${++PdfBookService.serial}`;
    const path = `${root}/source.pdf`;
    let committed = false;
    fs.mkdirSync(root, true);
    try {
      await fs.copy(source.startsWith('/') ? fileUri.getUriFromPath(source) : source, fileUri.getUriFromPath(path));
      const summary = await PdfImportTask.extract(path, root);
      let hash = '';
      try { hash = await hashFile(path); } catch (error) { console.warn('[PDF] fingerprint unavailable:', error); }
      const indexFile = fs.openSync(`${root}/outline.json`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(indexFile.fd, JSON.stringify(summary.outline)); } finally { fs.closeSync(indexFile); }
      book.name = book.getVariable('localMetadataCustomized') === '1' ? book.getVariable('localCustomName') :
        (summary.title || fallbackTitle || '未命名 PDF');
      book.author = book.getVariable('localMetadataCustomized') === '1' ? book.getVariable('localCustomAuthor') :
        (summary.author || fallbackAuthor);
      book.coverUrl = summary.coverPath ? fileUri.getUriFromPath(summary.coverPath) : '';
      book.totalChapterNum = summary.pageCount;
      book.latestChapterTitle = PdfPagePosition.title(summary.pageCount - 1);
      book.latestChapterTime = Date.now();
      book.durChapterIndex = PdfPagePosition.clamp(book.durChapterIndex, summary.pageCount);
      book.durChapterPos = 0;
      book.durChapterTitle = PdfPagePosition.title(book.durChapterIndex);
      book.putVariable('localFilePath', path);
      book.putVariable('localExtractRoot', root);
      book.putVariable('localContentHash', hash);
      book.putVariable('localParserVersion', PdfBookService.PARSER_VERSION);
      book.putVariable('readerComicAutoDetected', '0');
      book.putVariable('readerComicMode', '0');
      book.putVariable('readerComicManualMode', 'text');
      const chapters: BookChapter[] = [];
      for (let i = 0; i < summary.pageCount; i++) {
        const chapter = new BookChapter();
        chapter.bookUrl = book.bookUrl; chapter.index = i;
        chapter.title = PdfPagePosition.title(i); chapter.url = `${book.bookUrl}#page=${i}`;
        chapter.resourceUrl = path;
        chapters.push(chapter);
        if (i > 0 && i % 256 === 0) await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
      }
      await appDb.commitBookSourceSwitch(book.bookUrl, book, chapters, true);
      committed = true;
      // Retain the old revision until the transaction succeeds. Cleanup failure is harmless.
      PdfBookService.cleanup(context, oldRoot);
      PdfBookService.cleanup(context, oldPath);
      return book;
    } finally { if (!committed) PdfBookService.cleanup(context, root); }
  }

  static async outline(book: Book): Promise<PdfOutlineEntry[]> {
    try {
      const path = `${book.getVariable('localExtractRoot')}/outline.json`;
      const raw = JSON.parse(await fs.readText(path)) as PdfOutlineEntry[];
      if (!Array.isArray(raw)) return [];
      return raw.filter((entry: PdfOutlineEntry): boolean => !!entry && typeof entry.title === 'string' &&
        Number.isInteger(entry.pageIndex) && entry.pageIndex >= 0 && entry.pageIndex < book.totalChapterNum).slice(0, 4096);
    } catch (_) { return []; }
  }

  static hasIndex(book: Book): boolean {
    try { return fs.accessSync(`${book.getVariable('localExtractRoot')}/outline.json`); } catch (_) { return false; }
  }

  private static cleanup(context: Context, path: string): void {
    const prefix = `${context.filesDir}/local_books/`;
    if (!path || !path.startsWith(prefix) || path.substring(prefix.length).split('/').includes('..')) return;
    try {
      if (!fs.accessSync(path)) return;
      if (fs.statSync(path).isDirectory()) fs.rmdirSync(path);
      else fs.unlinkSync(path);
    } catch (error) { console.warn('[PDF] revision cleanup failed:', error); }
  }
}
