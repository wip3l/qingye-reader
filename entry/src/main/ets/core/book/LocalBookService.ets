import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import zlib from '@ohos.zlib';
import xml from '@ohos.xml';
import { appDb } from '../../model/data/AppDatabase';
import { Book, BookChapter } from '@legado/sourceengine';
import { ReaderImageMarker } from './ReaderImageMarker';
import { LocalChapterContentLoader } from './LocalChapterContentLoader';
import { EpubChapterPlanner, EpubPlannedChapter, EpubTocEntry } from './EpubChapterPlanner';
import { EpubConvertResult, EpubHtmlConverter } from './EpubHtmlConverter';
import { EpubTextOffsetMap } from './EpubTextOffsetMap';
import { MobiImportTask } from '../concurrency/MobiImportTask';
import { PdfBookService } from './pdf/PdfBookService';
import { LocalArchiveImport } from './LocalArchiveImport';
import { TxtChapterMatcher, TxtTocResolvedRule, TxtTocRules } from './TxtTocRules';
import { TxtTocRuleStore } from '../../utils/TxtTocRuleStore';


export class LocalBookExportResult {
  savedCount: number = 0;
  failedNames: string[] = [];
}

export class LocalBookFile {
  uri: string = '';
  name: string = '';
  addedAt: number = 0;
}

export class LocalBookScanResult {
  discovered: number = 0;
  imported: number = 0;
  failed: number = 0;
  failures: string[] = [];
  /** Files whose content is already on the shelf; nothing was imported for them. */
  duplicates: string[] = [];
}

class LocalImportOutcome {
  book: Book;
  duplicate: boolean;

  constructor(book: Book, duplicate: boolean) {
    this.book = book;
    this.duplicate = duplicate;
  }
}

class LocalChapterData {
  title: string = '';
  content: string = '';
  sourcePath: string = '';
  variable: string = '';
  imageOnly: boolean = false;
}

class XmlNodeData {
  name: string = '';
  text: string = '';
  attributes: Record<string, string> = {};
  children: XmlNodeData[] = [];
}

class EpubManifestItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

class EpubPackageData {
  title: string = '';
  author: string = '';
  coverPath: string = '';
  extractRoot: string = '';
  chapters: LocalChapterData[] = [];
  planned: EpubPlannedChapter[] = [];
  isComic: boolean = false;
}

class LocalSpineFile {
  path: string = '';
  isImage: boolean = false;
  /** spine 里 linear="no" 的辅助内容。 */
  nonLinear: boolean = false;
}

class LocalBookMetadata {
  title: string = '';
  author: string = '';
}

class DecodedLocalText {
  text: string = '';
  charset: string = 'utf-8';
}

class LocalTxtImportResult {
  chapterCount: number = 0;
  latestTitle: string = '';
  intro: string = '';
  /** 不到 TxtTocRules.SHORT_CHAPTER_CHARS 字的章节数。 */
  shortCount: number = 0;
  /** 每章正文在全书里的起始字符位置。 */
  chapterStarts: number[] = [];
  chapterTitles: string[] = [];
}

export class TxtTocPreviewItem {
  title: string = '';
  length: number = 0;
}

/** 用某条规则试分章的结果，不写数据库。 */
export class TxtTocPreview {
  chapterCount: number = 0;
  totalChars: number = 0;
  shortCount: number = 0;
  /** 是否一个标题都没认出来（整本书只能按长度自动分段）。 */
  noTitleMatched: boolean = false;
  items: TxtTocPreviewItem[] = [];
}

export class LocalBookService {
  static readonly ORIGIN: string = 'local';
  static readonly TYPE_TXT: number = 1;
  static readonly TYPE_EPUB: number = 2;
  static readonly TYPE_PDF: number = 4;
  static readonly LOCAL_CONTENT_HASH_KEY: string = 'localContentHash';
  static readonly EPUB_IMAGE_MARKER_PREFIX: string = ReaderImageMarker.PREFIX;
  static readonly EPUB_IMAGE_MARKER_SUFFIX: string = ReaderImageMarker.SUFFIX;

  private static readonly TXT_PARSER_VERSION: string = '10';
  // 10 / 2：注释编号换成可点的注释标记。
  private static readonly EPUB_PARSER_VERSION: string = '10';
  private static readonly MOBI_PARSER_VERSION: string = '2';
  /** 导入时同时预读的正文文件数。 */
  private static readonly IMPORT_READ_AHEAD: number = 4;
  /** 导入转换连续占用主线程的时长上限，超过后让出一次。 */
  private static readonly IMPORT_SLICE_MS: number = 32;

  /** 可导入的本地书格式。MOBI 解析后与 EPUB 一样按解压目录阅读，书籍类型同为 TYPE_EPUB。 */
  static readonly SUPPORTED_FORMATS: string[] = ['txt', 'epub', 'mobi', 'pdf'];
  static readonly UNSUPPORTED_FORMAT_MESSAGE: string = '仅支持 TXT、EPUB、MOBI 和 PDF 文件';
  private static readonly TXT_READ_CHUNK_BYTES: number = 256 * 1024;
  private static readonly TXT_MAX_CHAPTER_CHARS: number = 32 * 1024;
  private static readonly TXT_DB_BATCH_SIZE: number = 16;
  private static readonly TXT_CHARSET_OVERRIDE_KEY: string = 'localCharsetOverride';
  private static readonly LOCAL_INTRO_TARGET_LENGTH: number = 96;
  /** 本书用的目录规则引用（见 TxtTocRules.ref），空串表示智能识别。 */
  static readonly TXT_TOC_RULE_KEY: string = 'localTocRule';
  private static readonly TXT_TOC_SHORT_KEY: string = 'localTocShortChapters';
  private static readonly TXT_TOC_COUNT_KEY: string = 'localTocChapterCount';
  private static readonly TXT_TOC_HINT_DISMISSED_KEY: string = 'localTocHintDismissed';

  static isSupportedFormat(format: string): boolean {
    return LocalBookService.SUPPORTED_FORMATS.includes((format || '').toLowerCase());
  }

  static bookTypeForFormat(format: string): number {
    const value = (format || '').toLowerCase();
    if (value === 'pdf') return LocalBookService.TYPE_PDF;
    return value === 'epub' || value === 'mobi' ? LocalBookService.TYPE_EPUB : LocalBookService.TYPE_TXT;
  }

  /** 本地书的格式；早期导入没有记录 localFormat 时按书籍类型推断。 */
  static formatOf(book: Book): string {
    return (book.getVariable('localFormat') ||
      (book.type === LocalBookService.TYPE_PDF ? 'pdf' : book.type === LocalBookService.TYPE_EPUB ? 'epub' : 'txt')).toLowerCase();
  }

  static isPdfBook(book: Book | null): boolean {
    return !!book && book.origin === LocalBookService.ORIGIN && LocalBookService.formatOf(book) === 'pdf';
  }

  /** 书籍变量：'1' 表示这本 EPUB 用“文件排版”（原版 CSS，网页组件渲染）打开。 */
  static readonly EPUB_ORIGINAL_LAYOUT_KEY: string = 'epubOriginalLayout';

  /** 能用文件排版的书：本地 EPUB 的文字书（漫画仍走漫画阅读）。 */
  static canUseEpubOriginalLayout(book: Book | null): boolean {
    return !!book && book.origin === LocalBookService.ORIGIN && book.type === LocalBookService.TYPE_EPUB &&
      LocalBookService.formatOf(book) === 'epub' && book.getVariable('readerComicMode') !== '1';
  }

  static usesEpubOriginalLayout(book: Book | null): boolean {
    return LocalBookService.canUseEpubOriginalLayout(book) &&
      book?.getVariable(LocalBookService.EPUB_ORIGINAL_LAYOUT_KEY) === '1';
  }

  private static parserVersionFor(format: string): string {
    if (format === 'pdf') return PdfBookService.PARSER_VERSION;
    if (format === 'epub') return LocalBookService.EPUB_PARSER_VERSION;
    if (format === 'mobi') return LocalBookService.MOBI_PARSER_VERSION;
    return LocalBookService.TXT_PARSER_VERSION;
  }

  static isLocalBook(book: Book): boolean {
    return book.origin === LocalBookService.ORIGIN;
  }

  static isWebDavBook(book: Book | null): boolean {
    return !!book && book.getVariable('storageKind') === 'webdav';
  }

  static isPhysicalLocalBook(book: Book): boolean {
    return LocalBookService.isLocalBook(book) && !LocalBookService.isWebDavBook(book);
  }

  // 移出书架：删除数据库记录（章节与正文缓存随 deleteBook 级联清理），
  // 并清理本地源文件与 EPUB 解压目录；远端书库（WebDAV/OPDS）文件不受影响。
  static async deleteBookWithFiles(context: Context, bookUrl: string): Promise<void> {
    const book = await appDb.getBook(bookUrl);
    if (book) {
      const extractRoot = book.getVariable('localExtractRoot');
      if (extractRoot) LocalBookService.deleteLocalPath(context, extractRoot);
      const localPath = book.getVariable('localFilePath');
      if (localPath) LocalBookService.deleteLocalPath(context, localPath);
    }
    await appDb.deleteBook(bookUrl, 'remove_from_shelf');
  }

  static getTxtCharsetOverride(book: Book | null): string {
    if (!book || !LocalBookService.isLocalBook(book) || book.type !== LocalBookService.TYPE_TXT) return '';
    return LocalBookService.normalizeTxtCharset(book.getVariable(LocalBookService.TXT_CHARSET_OVERRIDE_KEY));
  }

  static async setTxtCharsetOverride(context: Context, book: Book, charset: string): Promise<void> {
    if (!LocalBookService.isLocalBook(book) || book.type !== LocalBookService.TYPE_TXT) {
      throw new Error('仅本地 TXT 书籍支持切换字符编码');
    }
    const requested = (charset || '').trim();
    const normalized = LocalBookService.normalizeTxtCharset(requested);
    if (requested && !normalized) {
      throw new Error(`不支持的字符编码：${requested}`);
    }
    if (normalized) {
      // Validate device support before deleting the existing parsed chapter cache.
      util.TextDecoder.create(normalized);
    }
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) {
      throw new Error('本地 TXT 文件不存在，请重新导入');
    }
    await appDb.initWithContext(context);
    const previousOverride = book.getVariable(LocalBookService.TXT_CHARSET_OVERRIDE_KEY);
    const previousCharset = book.charset;
    book.putVariable(LocalBookService.TXT_CHARSET_OVERRIDE_KEY, normalized);
    book.putVariable('localParserVersion', 'importing');
    await appDb.updateBook(book);
    try {
      await LocalBookService.rebuildTxtBook(context, book, localPath);
    } catch (e) {
      book.putVariable(LocalBookService.TXT_CHARSET_OVERRIDE_KEY, previousOverride);
      book.charset = previousCharset;
      // Keep the parser marked stale so the next open repairs any partially rebuilt cache.
      book.putVariable('localParserVersion', 'importing');
      await appDb.updateBook(book);
      console.error('[LocalBookService] Failed to rebuild TXT with selected charset', e);
      throw new Error('TXT 字符编码重新解析失败');
    }
  }

  static isLocalTxtBook(book: Book | null): boolean {
    return !!book && LocalBookService.isLocalBook(book) && book.type === LocalBookService.TYPE_TXT;
  }

  static getTxtTocRuleRef(book: Book | null): string {
    if (!book || !LocalBookService.isLocalTxtBook(book)) return '';
    return book.getVariable(LocalBookService.TXT_TOC_RULE_KEY) || '';
  }

  /**
   * 目录里短章太多、而用户还没为这本书选过规则时，提示可能把正文认成了标题。
   * 统计在解析时记下；从没按新版解析过的书不提示。
   */
  static shouldHintTxtToc(book: Book | null): boolean {
    if (!book || !LocalBookService.isLocalTxtBook(book)) return false;
    if (book.getVariable(LocalBookService.TXT_TOC_RULE_KEY) ||
      book.getVariable(LocalBookService.TXT_TOC_HINT_DISMISSED_KEY) === '1') return false;
    const shortCount = Number(book.getVariable(LocalBookService.TXT_TOC_SHORT_KEY));
    const count = Number(book.getVariable(LocalBookService.TXT_TOC_COUNT_KEY));
    return LocalBookService.looksOverSplit(shortCount, count);
  }

  static txtTocShortChapterCount(book: Book | null): number {
    const value = Number(book?.getVariable(LocalBookService.TXT_TOC_SHORT_KEY));
    return Number.isFinite(value) ? value : 0;
  }

  static looksOverSplit(shortCount: number, chapterCount: number): boolean {
    return Number.isFinite(shortCount) && Number.isFinite(chapterCount) && shortCount >= 10 &&
      shortCount >= chapterCount * 0.15;
  }

  static async dismissTxtTocHint(context: Context, book: Book): Promise<void> {
    await appDb.initWithContext(context);
    book.putVariable(LocalBookService.TXT_TOC_HINT_DISMISSED_KEY, '1');
    await appDb.updateBook(book);
  }

  /** 换用另一条目录规则并重新解析；阅读位置按全书字符位置换算到新章节上。失败时恢复原规则。 */
  static async setTxtTocRule(context: Context, book: Book, ref: string): Promise<void> {
    if (!LocalBookService.isLocalTxtBook(book)) throw new Error('仅本地 TXT 书籍支持目录规则');
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) {
      throw new Error('本地 TXT 文件不存在，请重新导入');
    }
    await appDb.initWithContext(context);
    const previousRef = book.getVariable(LocalBookService.TXT_TOC_RULE_KEY);
    // 明确选过规则（哪怕选回智能识别）就不再提示“可能切错了”。
    book.putVariable(LocalBookService.TXT_TOC_HINT_DISMISSED_KEY, '1');
    book.putVariable(LocalBookService.TXT_TOC_RULE_KEY, ref);
    book.putVariable('localParserVersion', 'importing');
    await appDb.updateBook(book);
    try {
      await LocalBookService.rebuildTxtBook(context, book, localPath, true);
    } catch (e) {
      book.putVariable(LocalBookService.TXT_TOC_RULE_KEY, previousRef);
      book.putVariable('localParserVersion', 'importing');
      await appDb.updateBook(book);
      console.error('[LocalBookService] Failed to rebuild TXT with selected toc rule', e);
      throw new Error('按新目录规则重新解析失败');
    }
  }

  /** 用某条规则试着分章，只统计不落库；sampleCount 是返回的开头章节数。 */
  static async previewTxtToc(context: Context, book: Book, ref: string,
    sampleCount: number = 5): Promise<TxtTocPreview> {
    return LocalBookService.previewTxtTocWithRule(book, await TxtTocRuleStore.resolve(context, ref), sampleCount);
  }

  /** 同 previewTxtToc，但直接给规则（编辑中还没保存的规则）。 */
  static async previewTxtTocWithRule(book: Book, resolved: TxtTocResolvedRule,
    sampleCount: number = 5): Promise<TxtTocPreview> {
    if (!LocalBookService.isLocalTxtBook(book)) throw new Error('仅本地 TXT 书籍支持目录规则');
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) {
      throw new Error('本地 TXT 文件不存在，请重新导入');
    }
    const charset = book.charset || LocalBookService.getTxtCharsetOverride(book) ||
      await LocalBookService.detectTextFileCharset(localPath);
    const matcher = new TxtChapterMatcher(resolved);
    const preview = new TxtTocPreview();
    let matchedTitle = false;
    await LocalBookService.scanTxtChapters(localPath, charset, matcher,
      async (title: string, body: string): Promise<void> => {
        preview.chapterCount++;
        preview.totalChars += body.length;
        if (body.length < TxtTocRules.SHORT_CHAPTER_CHARS) preview.shortCount++;
        if (!matcher.isWordSplit() && title !== '正文' && !title.startsWith('正文（')) matchedTitle = true;
        if (preview.items.length < sampleCount) {
          const item = new TxtTocPreviewItem();
          item.title = title;
          item.length = body.length;
          preview.items.push(item);
        }
      });
    preview.noTitleMatched = !matcher.isWordSplit() && !matchedTitle;
    return preview;
  }

  static isEpubImageMarker(value: string): boolean {
    const text = (value || '').trim();
    return text.startsWith(LocalBookService.EPUB_IMAGE_MARKER_PREFIX) &&
      text.endsWith(LocalBookService.EPUB_IMAGE_MARKER_SUFFIX);
  }

  static hasEpubImageMarkers(value: string): boolean {
    return (value || '').indexOf(LocalBookService.EPUB_IMAGE_MARKER_PREFIX) >= 0;
  }

  static epubImagePathFromMarker(value: string): string {
    return ReaderImageMarker.parse(value).source;
  }

  static createReaderImageMarker(source: string): string {
    return ReaderImageMarker.create(source);
  }

  static stripEpubImageMarkers(value: string, preserveOffsets: boolean = false): string {
    const source = value || '';
    let result = '';
    let cursor = 0;
    while (cursor < source.length) {
      const start = source.indexOf(LocalBookService.EPUB_IMAGE_MARKER_PREFIX, cursor);
      if (start < 0) {
        result += source.substring(cursor);
        break;
      }
      result += source.substring(cursor, start);
      const suffix = source.indexOf(LocalBookService.EPUB_IMAGE_MARKER_SUFFIX,
        start + LocalBookService.EPUB_IMAGE_MARKER_PREFIX.length);
      if (suffix < 0) {
        // A damaged image marker is metadata, never prose. Remove only its current line when the suffix is
        // missing so TTS cannot read a URL/dimension such as "10x2", while preserving following paragraphs.
        const lineEnd = source.indexOf('\n', start + LocalBookService.EPUB_IMAGE_MARKER_PREFIX.length);
        const end = lineEnd >= 0 ? lineEnd : source.length;
        if (preserveOffsets) result += ' '.repeat(Math.max(0, end - start));
        cursor = Math.max(start + 1, end);
        continue;
      }
      const end = suffix + LocalBookService.EPUB_IMAGE_MARKER_SUFFIX.length;
      if (preserveOffsets) {
        result += ' '.repeat(end - start);
      }
      cursor = end;
    }
    return result;
  }

  static async chooseBookFiles(context: Context): Promise<LocalBookFile[]> {
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FILE;
    options.maxSelectNumber = 500;
    options.fileSuffixFilters = ['电子书|.txt,.epub,.mobi,.pdf,.zip'];
    const result = await new picker.DocumentViewPicker(context).select(options);
    const paths: LocalBookFile[] = [];
    for (const uri of result) {
      if (!uri || paths.some((item: LocalBookFile) => item.uri === uri)) continue;
      const path = new LocalBookFile();
      path.uri = uri;
      path.name = LocalBookService.displayName(path.uri);
      path.addedAt = Date.now();
      paths.push(path);
    }
    return paths;
  }

  static async importSelectedFiles(context: Context, selected: LocalBookFile[]): Promise<LocalBookScanResult> {
    const result = new LocalBookScanResult();
    await appDb.initWithContext(context);
    result.discovered = selected.length;
    for (const path of selected) {
      if (LocalArchiveImport.isArchiveFormat(LocalBookService.extensionOf(path.uri))) {
        await LocalBookService.importArchive(context, path, result);
        continue;
      }
      try {
        const outcome = await LocalBookService.importLocalFile(context, path.uri);
        if (outcome.duplicate) {
          result.duplicates.push(`${path.name || LocalBookService.displayName(path.uri)}（书架中为《${outcome.book.name}》）`);
        } else {
          result.imported++;
        }
      } catch (e) {
        result.failed++;
        result.failures.push(`${path.name || LocalBookService.displayName(path.uri)}：${e instanceof Error ? e.message : '文件读取失败'}`);
        console.error('[LocalBook] import failed:', path.uri, e);
      }
    }
    return result;
  }

  /** 压缩包按包里的每本书计数；包本身打不开时算一次失败。 */
  private static async importArchive(context: Context, archive: LocalBookFile,
    result: LocalBookScanResult): Promise<void> {
    const archiveName = archive.name || LocalBookService.displayName(archive.uri);
    const workDir = `${context.cacheDir}/archive_import/${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    try {
      const extracted = await LocalArchiveImport.extractBooks(archive.uri, workDir, LocalBookService.SUPPORTED_FORMATS);
      result.discovered += extracted.files.length + extracted.failures.length - 1;
      for (const failure of extracted.failures) {
        result.failed++;
        result.failures.push(`${archiveName}/${failure}`);
      }
      if (extracted.files.length === 0 && extracted.failures.length === 0) {
        result.failed++;
        result.failures.push(`${archiveName}：压缩包内没有可导入的书籍`);
      }
      for (const file of extracted.files) {
        try {
          const outcome = await LocalBookService.importLocalFile(context, file.path, file.format, file.name,
            file.identity);
          if (outcome.duplicate) {
            result.duplicates.push(`${file.name}（书架中为《${outcome.book.name}》）`);
          } else {
            result.imported++;
          }
        } catch (e) {
          result.failed++;
          result.failures.push(`${archiveName}/${file.name}：${e instanceof Error ? e.message : '文件读取失败'}`);
          console.error('[LocalBook] archive entry import failed:', file.identity, e);
        }
      }
    } catch (e) {
      result.failed++;
      result.failures.push(`${archiveName}：${e instanceof Error ? e.message : '压缩包读取失败'}`);
      console.error('[LocalBook] archive import failed:', archive.uri, e);
    } finally {
      LocalArchiveImport.removeWorkDir(workDir);
    }
  }

  static async importExternalBook(context: Context, sourceUri: string,
    formatHint: string = '', sourceName: string = ''): Promise<Book> {
    await appDb.initWithContext(context);
    const format = LocalBookService.isSupportedFormat(formatHint) ? formatHint.toLowerCase() :
      LocalBookService.extensionOf(sourceUri);
    if (!LocalBookService.isSupportedFormat(format)) {
      throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    }
    return (await LocalBookService.importLocalFile(context, sourceUri, format, sourceName)).book;
  }

  /**
   * Importing the same file again through another path or as a copy reuses the shelf book with
   * identical content instead of adding a second one. Re-importing the same URI still refreshes it.
   */
  private static async importLocalFile(context: Context, sourceUri: string,
    formatHint: string = '', sourceName: string = '', identityUri: string = ''): Promise<LocalImportOutcome> {
    const extension = (formatHint || LocalBookService.extensionOf(sourceUri)).toLowerCase();
    if (!LocalBookService.isSupportedFormat(extension)) throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    let contentHash = '';
    if (!await appDb.getBook(`local://${LocalBookService.hashText(identityUri || sourceUri)}`)) {
      try {
        contentHash = await LocalBookService.hashFile(sourceUri);
      } catch (e) {
        console.warn('[LocalBookService] Unable to fingerprint import source:', e);
      }
      const existing = await LocalBookService.findImportedBookByContentHash(contentHash);
      if (existing) return new LocalImportOutcome(existing, true);
    }
    const book = await LocalBookService.importBook(context, sourceUri, extension, sourceName,
      '', '', '', '', 0, 0, null, '', contentHash, identityUri);
    return new LocalImportOutcome(book, false);
  }

  /** Only device-local imports count; WebDAV/OPDS copies are managed by their own libraries. */
  private static async findImportedBookByContentHash(contentHash: string): Promise<Book | null> {
    if (!contentHash) return null;
    const books = await appDb.getAllBooks();
    for (const book of books) {
      if (LocalBookService.isLocalBook(book) && !book.getVariable('storageKind') &&
        book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY) === contentHash &&
        LocalBookService.exists(book.getVariable('localFilePath'))) {
        return book;
      }
    }
    return null;
  }

  /**
   * 把云端下载的本地书导入到既有书架行（云端占位书）：沿用其书架地址、分组和阅读进度，
   * 并清掉占位标记。
   */
  static async importCloudBook(context: Context, sourcePath: string, format: string, sourceName: string,
    bookUrl: string, clearVariables: string[] = []): Promise<Book> {
    if (!LocalBookService.isSupportedFormat(format)) throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    await appDb.initWithContext(context);
    const previous = await appDb.getBook(bookUrl);
    const book = await LocalBookService.importBook(context, sourcePath, format, sourceName, bookUrl);
    if (previous) {
      book.group = previous.group;
      if (!book.author && previous.author) book.author = previous.author;
    }
    for (const key of clearVariables) book.putVariable(key, '');
    await appDb.updateBook(book, true, 'cloud_book_downloaded');
    return book;
  }

  static async importWebDavBook(context: Context, sourcePath: string, connectionId: string,
    remotePath: string, remoteName: string, format: string, etag: string,
    lastModified: number, remoteSize: number): Promise<Book> {
    if (!LocalBookService.isSupportedFormat(format)) throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    const identity = LocalBookService.webDavBookUrl(connectionId, remotePath);
    return await LocalBookService.importBook(context, sourcePath, format, remoteName, identity,
      connectionId, remotePath, etag, lastModified, remoteSize);
  }

  static webDavBookUrl(connectionId: string, remotePath: string): string {
    return `webdav://${connectionId}/${LocalBookService.hashText(remotePath)}`;
  }

  static opdsBookUrl(serverId: string, acquisitionUrl: string): string {
    return `opds://${serverId}/${LocalBookService.hashText(acquisitionUrl)}`;
  }

  static async importOpdsBook(context: Context, sourcePath: string, serverId: string,
    name: string, format: string, acquisitionUrl: string, remoteSize: number): Promise<Book> {
    if (!LocalBookService.isSupportedFormat(format)) throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    const identity = LocalBookService.opdsBookUrl(serverId, acquisitionUrl);
    const storageVariables: Record<string, string> = {
      'storageKind': 'opds',
      'opdsServerId': serverId,
      'opdsAcquisitionUrl': acquisitionUrl,
      'opdsDownloadedAt': `${Date.now()}`
    };
    return await LocalBookService.importBook(context, sourcePath, format, name, identity,
      '', '', '', 0, 0, storageVariables, 'OPDS');
  }

  static sanitizeFileName(value: string): string {
    const cleaned = value.replace(/[\\/:*?"<>|\r\n\t]/g, ' ').replace(/\s+/g, ' ').trim();
    return cleaned || '未命名';
  }

  static async exportSourceFile(context: Context, book: Book): Promise<string> {
    const localPath = book.getVariable('localFilePath') || '';
    const format = (book.getVariable('localFormat') || 'txt').toLowerCase();
    if (!localPath || !LocalBookService.exists(localPath)) {
      throw new Error('源文件不存在或已被清理');
    }
    const author = book.author ? ` - ${book.author}` : '';
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`${LocalBookService.sanitizeFileName(book.name + author)}.${format}`];
    const result = await new picker.DocumentViewPicker(context).save(options);
    if (!result || result.length === 0) {
      return '';
    }
    await fs.copy(fileUri.getUriFromPath(localPath), result[0]);
    return result[0];
  }

  /**
   * 批量导出源文件：和单本保存一样拉起保存选择器，由用户选择保存位置，一次存入全部文件。
   * 用户取消时返回 null。
   */
  static async exportSourceFiles(context: Context, books: Book[]): Promise<LocalBookExportResult | null> {
    const result = new LocalBookExportResult();
    const localPaths: string[] = [];
    const fileNames: string[] = [];
    const bookNames: string[] = [];
    for (const book of books) {
      const localPath = book.getVariable('localFilePath') || '';
      if (!localPath || !LocalBookService.exists(localPath)) {
        result.failedNames.push(book.name);
        continue;
      }
      const format = (book.getVariable('localFormat') || 'txt').toLowerCase();
      const author = book.author ? ` - ${book.author}` : '';
      const baseName = LocalBookService.sanitizeFileName(book.name + author);
      // 同名的书（同一本书的不同版本）要给出不同的文件名，否则会互相覆盖。
      let fileName = `${baseName}.${format}`;
      for (let index = 1; fileNames.includes(fileName); index++) {
        fileName = `${baseName} (${index}).${format}`;
      }
      localPaths.push(localPath);
      fileNames.push(fileName);
      bookNames.push(book.name);
    }
    if (fileNames.length === 0) {
      return result;
    }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = fileNames;
    const savedUris = await new picker.DocumentViewPicker(context).save(options);
    if (!savedUris || savedUris.length === 0) {
      return null;
    }
    for (let index = 0; index < localPaths.length; index++) {
      if (index >= savedUris.length) {
        result.failedNames.push(bookNames[index]);
        continue;
      }
      try {
        await fs.copy(fileUri.getUriFromPath(localPaths[index]), savedUris[index]);
        result.savedCount++;
      } catch (e) {
        console.warn('导出本地书籍源文件失败:', bookNames[index], e);
        result.failedNames.push(bookNames[index]);
      }
    }
    return result;
  }

  private static async importBook(context: Context, sourceUri: string,
    formatHint: string = '', sourceName: string = '', bookUrlOverride: string = '',
    webDavConnectionId: string = '', webDavRemotePath: string = '', webDavETag: string = '',
    webDavLastModified: number = 0, webDavRemoteSize: number = 0,
    storageVariables: Record<string, string> | null = null,
    storageOriginName: string = '', knownContentHash: string = '', identityUri: string = ''): Promise<Book> {
    const extension = (formatHint || LocalBookService.extensionOf(sourceUri)).toLowerCase();
    if (!LocalBookService.isSupportedFormat(extension)) throw new Error(LocalBookService.UNSUPPORTED_FORMAT_MESSAGE);
    // 压缩包里的书 sourceUri 是临时解压文件，身份另用“压缩包 URI#包内路径”。
    const identity = identityUri || sourceUri;
    const sourceId = LocalBookService.hashText(identity);
    const bookUrl = bookUrlOverride || `local://${sourceId}`;
    const id = bookUrlOverride ? LocalBookService.hashText(bookUrl) : sourceId;
    const sourceStat = await fs.stat(sourceUri);
    const oldBook = await appDb.getBook(bookUrl);
    if (extension === 'pdf') {
      if (oldBook && oldBook.getVariable('localParserVersion') === PdfBookService.PARSER_VERSION &&
        oldBook.getVariable('localSourceMtime') === `${sourceStat.mtime}` &&
        oldBook.getVariable('localSourceSize') === `${sourceStat.size}` &&
        LocalBookService.exists(oldBook.getVariable('localFilePath')) && PdfBookService.hasIndex(oldBook) &&
        await appDb.getBookChapterCount(bookUrl) === oldBook.totalChapterNum && oldBook.totalChapterNum > 0) return oldBook;
      const book = oldBook || new Book();
      book.bookUrl = bookUrl; book.tocUrl = bookUrl; book.origin = LocalBookService.ORIGIN;
      book.originName = storageOriginName || (webDavConnectionId ? 'WebDAV' : 'PDF');
      book.type = LocalBookService.TYPE_PDF; book.canUpdate = false;
      book.putVariable('localFormat', 'pdf'); book.putVariable('localSourceUri', identity);
      book.putVariable('localSourceMtime', `${sourceStat.mtime}`); book.putVariable('localSourceSize', `${sourceStat.size}`);
      book.putVariable('bookAddTime', book.getVariable('bookAddTime') || `${Date.now()}`);
      if (webDavConnectionId) {
        book.putVariable('storageKind', 'webdav'); book.putVariable('webdavConnectionId', webDavConnectionId);
        book.putVariable('webdavRemotePath', webDavRemotePath); book.putVariable('webdavETag', webDavETag);
        book.putVariable('webdavLastModified', `${Math.max(0, webDavLastModified)}`);
        book.putVariable('webdavRemoteSize', `${Math.max(0, webDavRemoteSize)}`);
        book.putVariable('webdavCachedAt', `${Date.now()}`);
      }
      if (storageVariables) for (const key of Object.keys(storageVariables)) book.putVariable(key, storageVariables[key]);
      const fallback = LocalBookService.parseFileNameMetadata(sourceName || sourceUri);
      return await PdfBookService.import(context, book, sourceUri, id,
        fallback.title || LocalBookService.fileStem(sourceName || sourceUri), fallback.author,
        (path: string): Promise<string> => knownContentHash ? Promise.resolve(knownContentHash) :
          LocalBookService.hashFile(path));
    }
    const oldChapterCount = oldBook ? await appDb.getBookChapterCount(bookUrl) : 0;
    const root = `${context.filesDir}/local_books`;
    LocalBookService.ensureDir(root);
    const localPath = `${root}/${id}.${extension}`;
    const oldParserVersion = oldBook?.getVariable('localParserVersion') || '';
    const parserIsCurrent = oldParserVersion === LocalBookService.parserVersionFor(extension);
    if (oldBook && parserIsCurrent &&
      oldBook.getVariable('localSourceMtime') === `${sourceStat.mtime}` &&
      oldBook.getVariable('localSourceSize') === `${sourceStat.size}` &&
      LocalBookService.exists(localPath) && oldChapterCount > 0) {
      if (!oldBook.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY)) {
        let contentHash = '';
        try {
          contentHash = await LocalBookService.hashFile(localPath);
        } catch (e) {
          console.warn('[LocalBookService] Unable to backfill local content hash:', e);
        }
        if (contentHash) {
          oldBook.putVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY, contentHash);
          await appDb.updateBook(oldBook, false, 'backfill_local_content_hash');
        }
      }
      return oldBook;
    }
    if (LocalBookService.exists(localPath)) {
      fs.unlinkSync(localPath);
    }
    const copySource = sourceUri.startsWith('/') ? fileUri.getUriFromPath(sourceUri) : sourceUri;
    await fs.copy(copySource, fileUri.getUriFromPath(localPath));

    const book = oldBook || new Book();
    book.bookUrl = bookUrl;
    book.tocUrl = bookUrl;
    book.origin = LocalBookService.ORIGIN;
    book.originName = extension.toUpperCase();
    book.canUpdate = false;
    book.group = 0;
    book.type = LocalBookService.bookTypeForFormat(extension);
    book.putVariable('localSourceUri', identity);
    book.putVariable('localFilePath', localPath);
    book.putVariable('localFormat', extension);
    book.putVariable('localParserVersion', 'importing');
    book.putVariable('localSourceMtime', `${sourceStat.mtime}`);
    book.putVariable('localSourceSize', `${sourceStat.size}`);
    let contentHash = knownContentHash;
    try {
      if (!contentHash) contentHash = await LocalBookService.hashFile(localPath);
    } catch (e) {
      // Fingerprinting is an enhancement for cross-device progress sync; a
      // crypto capability issue must not make the local import fail.
      console.warn('[LocalBookService] Unable to fingerprint local book:', e);
    }
    if (contentHash) {
      book.putVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY, contentHash);
    }
    book.putVariable('bookAddTime', oldBook?.getVariable('bookAddTime') || `${Date.now()}`);
    if (webDavConnectionId) {
      book.originName = 'WebDAV';
      book.putVariable('storageKind', 'webdav');
      book.putVariable('webdavConnectionId', webDavConnectionId);
      book.putVariable('webdavRemotePath', webDavRemotePath);
      book.putVariable('webdavETag', webDavETag);
      book.putVariable('webdavLastModified', `${Math.max(0, webDavLastModified)}`);
      book.putVariable('webdavRemoteSize', `${Math.max(0, webDavRemoteSize)}`);
      book.putVariable('webdavCachedAt', `${Date.now()}`);
    }
    if (storageVariables) {
      const storageKeys: string[] = Object.keys(storageVariables);
      for (let i = 0; i < storageKeys.length; i++) {
        const key = storageKeys[i];
        book.putVariable(key, storageVariables[key]);
      }
      if (storageOriginName) book.originName = storageOriginName;
    }
    const metadataSource = sourceName || sourceUri;
    const fileMetadata = LocalBookService.parseFileNameMetadata(metadataSource);
    const hasCustomMetadata = book.getVariable('localMetadataCustomized') === '1';

    if (extension === 'txt') {
      book.name = hasCustomMetadata ? book.getVariable('localCustomName') :
        (fileMetadata.title || LocalBookService.fileStem(metadataSource));
      book.author = hasCustomMetadata ? book.getVariable('localCustomAuthor') : fileMetadata.author;
      book.coverUrl = '';
      book.putVariable('localExtractRoot', '');
      book.putVariable('localParserVersion', 'importing');
      if (!oldBook && !book.getVariable(LocalBookService.TXT_TOC_RULE_KEY)) {
        const tocSettings = await TxtTocRuleStore.load(context);
        if (tocSettings.defaultRuleRef) book.putVariable(LocalBookService.TXT_TOC_RULE_KEY, tocSettings.defaultRuleRef);
      }
      if (oldBook) {
        await appDb.updateBook(book);
      } else {
        await appDb.insertBook(book);
      }
      await LocalBookService.rebuildTxtBook(context, book, localPath);
      return book;
    }

    let chapters: LocalChapterData[] = [];
    const epub = extension === 'mobi' ? await LocalBookService.parseMobi(context, localPath, id) :
      await LocalBookService.parseEpub(context, localPath, id);
    const oldChapterPath = oldBook ? await LocalBookService.currentEpubChapterPath(book) : '';
    const oldChapterContent = oldBook ? await LocalBookService.currentEpubChapterContent(book) : '';
    book.name = hasCustomMetadata ? book.getVariable('localCustomName') :
      (epub.title || fileMetadata.title || LocalBookService.fileStem(metadataSource));
    book.author = hasCustomMetadata ? book.getVariable('localCustomAuthor') : (epub.author || fileMetadata.author);
    book.coverUrl = epub.coverPath ? fileUri.getUriFromPath(epub.coverPath) : '';
    const oldExtractRoot = book.getVariable('localExtractRoot');
    if (oldExtractRoot && oldExtractRoot !== epub.extractRoot) {
      LocalBookService.deleteLocalPath(context, oldExtractRoot);
    }
    book.putVariable('localExtractRoot', epub.extractRoot);
    book.putVariable('localParserVersion', LocalBookService.parserVersionFor(extension));
    book.putVariable('readerComicAutoDetected', epub.isComic ? '1' : '0');
    book.putVariable('readerComicMode', epub.isComic ? '1' : '0');
    chapters = epub.chapters;

    if (chapters.length === 0) {
      const chapter = new LocalChapterData();
      chapter.title = book.name || '正文';
      chapter.content = '暂无可阅读内容';
      chapters.push(chapter);
    }
    book.totalChapterNum = chapters.length;
    book.latestChapterTitle = chapters[chapters.length - 1].title;
    book.latestChapterTime = Date.now();
    book.intro = '';
    book.putVariable('localContentIntroVersion', '6');
    LocalBookService.migrateEpubProgress(book, oldChapterPath, oldChapterContent, epub);

    if (oldBook) {
      await appDb.updateBook(book);
    } else {
      await appDb.insertBook(book);
    }
    await LocalBookService.persistEpubChapters(bookUrl, chapters);
    return book;
  }

  static async ensureTxtParserCurrent(context: Context, book: Book): Promise<boolean> {
    if (!LocalBookService.isLocalBook(book) || book.type !== LocalBookService.TYPE_TXT ||
      book.getVariable('localParserVersion') === LocalBookService.TXT_PARSER_VERSION) {
      return false;
    }
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) {
      return false;
    }
    await appDb.initWithContext(context);
    book.putVariable('localParserVersion', 'importing');
    await appDb.updateBook(book);
    await LocalBookService.rebuildTxtBook(context, book, localPath);
    return true;
  }

  static async ensureLocalParserCurrent(context: Context, book: Book): Promise<boolean> {
    if (!LocalBookService.isLocalBook(book)) return false;
    if (LocalBookService.isPdfBook(book)) {
      const path = book.getVariable('localFilePath');
      if (!path || !LocalBookService.exists(path)) return false;
      if (book.getVariable('localParserVersion') === PdfBookService.PARSER_VERSION && PdfBookService.hasIndex(book) &&
        await appDb.getBookChapterCount(book.bookUrl) === book.totalChapterNum) return false;
      await PdfBookService.import(context, book, path, LocalBookService.hashText(book.bookUrl), book.name, book.author,
        (filePath: string): Promise<string> => LocalBookService.hashFile(filePath));
      return true;
    }
    if (book.type === LocalBookService.TYPE_TXT) {
      return await LocalBookService.ensureTxtParserCurrent(context, book);
    }
    if (book.type !== LocalBookService.TYPE_EPUB ||
      book.getVariable('localParserVersion') === LocalBookService.parserVersionFor(LocalBookService.formatOf(book))) {
      return false;
    }
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) return false;
    await appDb.initWithContext(context);
    book.putVariable('localParserVersion', 'importing');
    await appDb.updateBook(book);
    await LocalBookService.rebuildEpubIndex(context, book, localPath);
    return true;
  }

  /** Ensures a local book has a device-independent content fingerprint. */
  static async ensureContentHash(book: Book): Promise<string> {
    if (!book || !LocalBookService.isLocalBook(book)) return '';
    const existing = book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY).trim();
    if (existing) return existing;
    const localPath = book.getVariable('localFilePath');
    if (!localPath || !LocalBookService.exists(localPath)) return '';
    let contentHash = '';
    try {
      contentHash = await LocalBookService.hashFile(localPath);
    } catch (e) {
      console.warn('[LocalBookService] Unable to fingerprint local book:', e);
    }
    if (contentHash) book.putVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY, contentHash);
    return contentHash;
  }

  private static async rebuildEpubIndex(context: Context, book: Book, localPath: string): Promise<void> {
    const id = book.bookUrl.startsWith('local://') ? book.bookUrl.substring('local://'.length) :
      LocalBookService.hashText(localPath);
    const format = LocalBookService.formatOf(book);
    const epub = format === 'mobi' ? await LocalBookService.parseMobi(context, localPath, id) :
      await LocalBookService.parseEpub(context, localPath, id);
    const oldChapterPath = await LocalBookService.currentEpubChapterPath(book);
    const oldChapterContent = await LocalBookService.currentEpubChapterContent(book);
    if (book.getVariable('localMetadataCustomized') === '1') {
      book.name = book.getVariable('localCustomName');
      book.author = book.getVariable('localCustomAuthor');
    } else {
      if (epub.title) book.name = epub.title;
      if (epub.author) book.author = epub.author;
    }
    book.coverUrl = epub.coverPath ? fileUri.getUriFromPath(epub.coverPath) : book.coverUrl;
    const oldExtractRoot = book.getVariable('localExtractRoot');
    if (oldExtractRoot && oldExtractRoot !== epub.extractRoot) {
      LocalBookService.deleteLocalPath(context, oldExtractRoot);
    }
    book.putVariable('localExtractRoot', epub.extractRoot);
    book.putVariable('localParserVersion', LocalBookService.parserVersionFor(format));
    book.putVariable('readerComicAutoDetected', epub.isComic ? '1' : '0');
    book.putVariable('readerComicMode', epub.isComic ? '1' : '0');

    const chapters = epub.chapters;

    if (chapters.length === 0) {
      const emptyChapter = new LocalChapterData();
      emptyChapter.title = book.name || '正文';
      emptyChapter.content = '暂无可阅读内容';
      chapters.push(emptyChapter);
    }
    book.totalChapterNum = chapters.length;
    book.latestChapterTitle = chapters[chapters.length - 1].title;
    book.latestChapterTime = Date.now();
    LocalBookService.migrateEpubProgress(book, oldChapterPath, oldChapterContent, epub);
    await appDb.updateBook(book);
    await LocalBookService.persistEpubChapters(book.bookUrl, chapters);
  }

  // 章节与正文在一个事务里写入：导入时已经转换过的正文直接进缓存，打开章节时不必再转换一遍。
  private static async persistEpubChapters(bookUrl: string, chapters: LocalChapterData[]): Promise<void> {
    await appDb.deleteBookChapters(bookUrl);
    await appDb.deleteBookCachedContent(bookUrl);
    const dbChapters: BookChapter[] = [];
    const contents: string[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const data = chapters[i];
      const chapter = new BookChapter();
      chapter.bookUrl = bookUrl;
      chapter.index = i;
      chapter.title = data.title || `第${i + 1}章`;
      chapter.url = `${bookUrl}#chapter=${i}`;
      chapter.resourceUrl = data.sourcePath;
      chapter.variable = data.variable;
      dbChapters.push(chapter);
      contents.push(data.content || chapter.title);
    }
    await appDb.insertBookChaptersWithContents(bookUrl, dbChapters, contents);
  }

  /** 重新解析前，当前阅读章节对应的 spine 文件路径。 */
  private static async currentEpubChapterPath(book: Book): Promise<string> {
    try {
      const oldChapters = await appDb.getBookChapters(book.bookUrl);
      const index = book.durChapterIndex;
      if (index < 0 || index >= oldChapters.length) return '';
      return EpubHtmlConverter.withoutFragment(oldChapters[index].resourceUrl || '');
    } catch (e) {
      console.warn('[LocalBook] 读取旧章节失败:', e);
      return '';
    }
  }

  /** 重新解析前，当前阅读章节缓存的旧正文；用来把章内字符偏移换算到新正文上。 */
  private static async currentEpubChapterContent(book: Book): Promise<string> {
    if (book.getVariable('readProgressCharOffsetChapterV2') !== `${book.durChapterIndex}`) return '';
    try {
      return await appDb.getCachedChapterContent(book.bookUrl, book.durChapterIndex);
    } catch (e) {
      console.warn('[LocalBook] 读取旧章节正文失败:', e);
      return '';
    }
  }

  // 章节划分方式变化后旧的章节序号不再对应原来的内容，按所在文件重新定位阅读进度。
  private static migrateEpubProgress(book: Book, oldChapterPath: string, oldChapterContent: string,
    epub: EpubPackageData): void {
    const count = epub.chapters.length;
    const index = !epub.isComic && oldChapterPath ?
      EpubChapterPlanner.chapterIndexForPath(epub.planned, oldChapterPath) : -1;
    if (index >= 0 && index < count) {
      // 旧章节的文件仍然是新章节的开头时，章内字符偏移继续有效；否则只能回到新章节的开头。
      const first = epub.planned[index].segments[0];
      const offsetStillValid = first.path === oldChapterPath && !first.startId;
      if (!offsetStillValid) {
        book.durChapterPos = 0;
        book.putVariable('readProgressCharOffsetV2', '');
      } else if (oldChapterContent) {
        // 正文里多了注释标记、少了脚注块，同一位置的偏移跟着变。
        const offset = Number(book.getVariable('readProgressCharOffsetV2'));
        if (Number.isFinite(offset) && offset > 0) {
          book.putVariable('readProgressCharOffsetV2',
            `${EpubTextOffsetMap.map(oldChapterContent, epub.chapters[index].content || '', offset)}`);
        }
      }
      if (index !== book.durChapterIndex) {
        book.durChapterTitle = epub.chapters[index].title;
        if (book.getVariable('readProgressChapterIndex')) book.putVariable('readProgressChapterIndex', `${index}`);
        if (book.getVariable('readProgressCharOffsetChapterV2')) {
          book.putVariable('readProgressCharOffsetChapterV2', `${index}`);
        }
      }
      book.durChapterIndex = index;
      return;
    }
    if (book.durChapterIndex >= count) {
      book.durChapterIndex = 0;
      book.durChapterPos = 0;
      book.durChapterTitle = '';
    }
  }

  static async ensureContentIntro(book: Book): Promise<boolean> {
    if (LocalBookService.isPdfBook(book)) return false;
    if (!LocalBookService.isLocalBook(book) ||
      (book.getVariable('localContentIntroVersion') === '6' && !!book.intro.trim())) {
      return false;
    }
    const chapters = await appDb.getBookChapters(book.bookUrl);
    let intro = '';
    const inspectCount = Math.min(chapters.length, book.type === LocalBookService.TYPE_EPUB ? 8 : 100);
    for (let i = 0; i < inspectCount && intro.length < LocalBookService.LOCAL_INTRO_TARGET_LENGTH; i++) {
      let content = await appDb.getCachedChapterContent(book.bookUrl, chapters[i].index);
      if (!content && book.type === LocalBookService.TYPE_EPUB) {
        content = await LocalChapterContentLoader.load(book, chapters[i]);
        if (content) {
          await appDb.saveCachedChapterContent(book.bookUrl, chapters[i], content);
        }
      }
      intro = LocalBookService.appendContentIntro(
        intro, content, chapters[i].title, book.name, book.author);
    }
    if (!intro) {
      return false;
    }
    book.intro = intro;
    book.putVariable('localContentIntroVersion', '6');
    await appDb.updateBook(book);
    return true;
  }

  /**
   * 重新解析本地 TXT。remapProgress 为 true 时（换了分章规则），把阅读位置换算成全书字符位置，
   * 再落到新的章节上；否则沿用原来的章节序号。
   */
  private static async rebuildTxtBook(context: Context, book: Book, localPath: string,
    remapProgress: boolean = false): Promise<void> {
    const charsetOverride = LocalBookService.getTxtCharsetOverride(book);
    book.charset = charsetOverride || await LocalBookService.detectTextFileCharset(localPath);
    const matcher = new TxtChapterMatcher(
      await TxtTocRuleStore.resolve(context, LocalBookService.getTxtTocRuleRef(book)));
    const previousChapterCount = Math.max(book.totalChapterNum,
      await appDb.getBookChapterCount(book.bookUrl));
    const previousChapterIndex = Math.max(0, book.durChapterIndex);
    const targetCharPosition = remapProgress ? await LocalBookService.currentTxtCharPosition(book) : -1;
    await appDb.deleteBookChapters(book.bookUrl);
    await appDb.deleteBookCachedContent(book.bookUrl);
    const imported = await LocalBookService.importTxtChapters(
      book.bookUrl, localPath, book.charset, book.name, book.author, matcher);
    book.totalChapterNum = imported.chapterCount;
    book.latestChapterTitle = imported.latestTitle;
    book.latestChapterTime = Date.now();
    book.intro = imported.intro;
    book.putVariable('localContentIntroVersion', '6');
    book.putVariable(LocalBookService.TXT_TOC_SHORT_KEY, `${imported.shortCount}`);
    book.putVariable(LocalBookService.TXT_TOC_COUNT_KEY, `${imported.chapterCount}`);
    if (targetCharPosition >= 0 && imported.chapterCount > 0) {
      LocalBookService.moveTxtProgressTo(book, imported, targetCharPosition);
    } else if (previousChapterCount > imported.chapterCount * 4 && imported.chapterCount > 0) {
      // Parser v7 could classify nearly every short body line as a title. When repairing
      // such an over-split book, retain an approximate whole-book position instead of
      // dropping the reader at an unrelated chapter or resetting all progress.
      const progress = previousChapterCount > 1 ? previousChapterIndex / (previousChapterCount - 1) : 0;
      book.durChapterIndex = Math.min(imported.chapterCount - 1,
        Math.max(0, Math.round(progress * (imported.chapterCount - 1))));
      book.durChapterPos = 0;
      book.durChapterTitle = '';
    } else if (book.durChapterIndex >= imported.chapterCount) {
      book.durChapterIndex = 0;
      book.durChapterPos = 0;
      book.durChapterTitle = '';
    }
    book.putVariable('localParserVersion', LocalBookService.TXT_PARSER_VERSION);
    await appDb.updateBook(book);
  }

  /** 重新解析前的阅读位置在全书正文里的字符位置（按缓存正文的字数累加）；读不到时返回 -1。 */
  private static async currentTxtCharPosition(book: Book): Promise<number> {
    try {
      const lengths = await appDb.getCachedChapterContentLengths(book.bookUrl);
      const index = Math.max(0, book.durChapterIndex);
      if (lengths.length === 0 || index >= lengths.length) return -1;
      let position = 0;
      for (let i = 0; i < index; i++) position += lengths[i] || 0;
      const offset = Number(book.getVariable('readProgressCharOffsetV2'));
      if (book.getVariable('readProgressCharOffsetChapterV2') === `${index}` && Number.isFinite(offset) && offset > 0) {
        position += Math.min(offset, lengths[index] || 0);
      }
      return position;
    } catch (e) {
      console.warn('[LocalBookService] 读取 TXT 阅读位置失败:', e);
      return -1;
    }
  }

  private static moveTxtProgressTo(book: Book, imported: LocalTxtImportResult, position: number): void {
    const starts = imported.chapterStarts;
    let index = 0;
    for (let i = 0; i < starts.length; i++) {
      if (starts[i] <= position) index = i;
      else break;
    }
    index = Math.min(imported.chapterCount - 1, index);
    const offset = Math.max(0, Math.round(position - (starts[index] || 0)));
    book.durChapterIndex = index;
    book.durChapterPos = 0;
    book.durChapterTitle = imported.chapterTitles[index] || '';
    book.putVariable('readProgressCharOffsetV2', `${offset}`);
    book.putVariable('readProgressCharOffsetChapterV2', `${index}`);
    if (book.getVariable('readProgressChapterIndex')) book.putVariable('readProgressChapterIndex', `${index}`);
  }

  private static async importTxtChapters(bookUrl: string, path: string, charset: string, bookName: string,
    bookAuthor: string, matcher: TxtChapterMatcher): Promise<LocalTxtImportResult> {
    const result = new LocalTxtImportResult();
    let chapterBatch: BookChapter[] = [];
    let contentBatch: string[] = [];
    let position = 0;

    const flushBatch = async (): Promise<void> => {
      if (chapterBatch.length === 0) return;
      const pendingChapters = chapterBatch;
      const pendingContents = contentBatch;
      chapterBatch = [];
      contentBatch = [];
      await appDb.insertBookChaptersWithContents(bookUrl, pendingChapters, pendingContents);
    };

    const sink = async (title: string, body: string): Promise<void> => {
      const content = body || title;
      const dbChapter = new BookChapter();
      dbChapter.bookUrl = bookUrl;
      dbChapter.index = result.chapterCount;
      dbChapter.title = title;
      dbChapter.url = `${bookUrl}#chapter=${dbChapter.index}`;
      dbChapter.resourceUrl = path;
      chapterBatch.push(dbChapter);
      contentBatch.push(content);
      if (result.intro.length < LocalBookService.LOCAL_INTRO_TARGET_LENGTH) {
        result.intro = LocalBookService.appendContentIntro(result.intro, content, title, bookName, bookAuthor);
      }
      result.chapterStarts.push(position);
      result.chapterTitles.push(title);
      position += content.length;
      if (body.length < TxtTocRules.SHORT_CHAPTER_CHARS) result.shortCount++;
      result.chapterCount++;
      result.latestTitle = title;
      if (chapterBatch.length >= LocalBookService.TXT_DB_BATCH_SIZE) {
        await flushBatch();
      }
    };

    await LocalBookService.scanTxtChapters(path, charset, matcher, sink);
    if (result.chapterCount === 0) {
      await sink('正文', '暂无可阅读内容');
      result.shortCount = 0;
    }
    await flushBatch();
    return result;
  }

  /**
   * 按规则逐行扫描 TXT，每分出一章调用一次 sink(标题, 正文)。正文已去掉首尾空白，可能为空串
   * （标题后紧跟下一个标题）。导入和预览共用这一段，保证预览看到的就是应用后的结果。
   */
  private static async scanTxtChapters(path: string, charset: string, matcher: TxtChapterMatcher,
    sink: (title: string, body: string) => Promise<void>): Promise<void> {
    const wordSplit = matcher.isWordSplit();
    let currentTitle = '';
    let currentPart = 1;
    let currentHasPersisted = false;
    let emitted = 0;
    let bodyParts: string[] = [];
    let bodyLength = 0;

    const persistCurrent = async (allowEmptyTitle: boolean): Promise<boolean> => {
      const content = bodyParts.join('').trim();
      bodyParts = [];
      bodyLength = 0;
      if (wordSplit) {
        if (!content) return false;
        emitted++;
        await sink(`${emitted}. ${LocalBookService.txtLeadSentence(content)}`, content);
        return true;
      }
      if (!content && (!allowEmptyTitle || !currentTitle || currentHasPersisted)) {
        return false;
      }
      const baseTitle = currentTitle || '正文';
      emitted++;
      await sink(currentPart > 1 ? `${baseTitle}（${currentPart}）` : baseTitle, content);
      currentHasPersisted = true;
      return true;
    };

    const appendBodyText = async (text: string): Promise<void> => {
      let remaining = text;
      while (remaining.length > 0) {
        const capacity = Math.max(1, LocalBookService.TXT_MAX_CHAPTER_CHARS - bodyLength);
        const take = Math.min(capacity, remaining.length);
        bodyParts.push(remaining.substring(0, take));
        bodyLength += take;
        remaining = remaining.substring(take);
        if (bodyLength >= LocalBookService.TXT_MAX_CHAPTER_CHARS) {
          const persisted = await persistCurrent(false);
          if (persisted) currentPart++;
        }
      }
    };

    const consumeLine = async (rawLine: string, forceBody: boolean = false): Promise<void> => {
      const line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      if (wordSplit) {
        await appendBodyText(`${line}\n`);
        // 只在行尾切，不把一句话拦腰截断。
        if (bodyLength >= matcher.wordsPerChapter) await persistCurrent(false);
        return;
      }
      const candidate = LocalBookService.normalizeTxtChapterCandidate(line);
      if (!forceBody && matcher.isTitle(line, candidate)) {
        await persistCurrent(true);
        currentTitle = candidate;
        currentPart = 1;
        currentHasPersisted = false;
      } else {
        await appendBodyText(`${line}\n`);
      }
    };

    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const decoder = util.TextDecoder.create(charset || 'utf-8');
    let carry = '';
    let carryIsBody = false;
    let isFirstChunk = true;
    try {
      while (true) {
        const buffer = new ArrayBuffer(LocalBookService.TXT_READ_CHUNK_BYTES);
        const readSize = await fs.read(file.fd, buffer);
        if (readSize <= 0) break;
        const bytes = new Uint8Array(buffer, 0, readSize);
        let decoded = decoder.decodeWithStream(bytes, { stream: true });
        if (isFirstChunk) {
          decoded = decoded.replace(/^\uFEFF/, '');
          isFirstChunk = false;
        }
        const decodedText = carry + decoded;
        let lineStart = 0;
        let lineEnd = decodedText.indexOf('\n', lineStart);
        while (lineEnd >= 0) {
          const line = decodedText.substring(lineStart, lineEnd);
          await consumeLine(line, carryIsBody && lineStart === 0);
          carryIsBody = false;
          lineStart = lineEnd + 1;
          lineEnd = decodedText.indexOf('\n', lineStart);
        }
        carry = decodedText.substring(lineStart);
        while (carry.length > LocalBookService.TXT_MAX_CHAPTER_CHARS) {
          await appendBodyText(carry.substring(0, LocalBookService.TXT_MAX_CHAPTER_CHARS));
          carry = carry.substring(LocalBookService.TXT_MAX_CHAPTER_CHARS);
          carryIsBody = true;
        }
      }
      const tail = decoder.decodeWithStream(new Uint8Array(0), { stream: false });
      carry += tail;
      if (carry || carryIsBody) {
        await consumeLine(carry, carryIsBody);
      }
      await persistCurrent(true);
    } finally {
      await fs.close(file);
    }
  }

  /** 按字数分章时的章节标题：取章首第一句，过长截断。 */
  private static txtLeadSentence(content: string): string {
    const text = content.replace(/^[\s\u3000]+/, '');
    const end = text.search(/[。！？!?…\n]/);
    let sentence = (end > 0 ? text.substring(0, end) : text).replace(/\s+/g, ' ').trim();
    if (sentence.length > 18) sentence = `${sentence.substring(0, 18)}…`;
    return sentence || '正文';
  }

  private static normalizeTxtChapterCandidate(value: string): string {
    // trim() does not remove zero-width characters. Treat formatting-only lines as
    // blank before applying the chapter-title grammar.
    return (value || '').replace(/[\u200B-\u200D\u2060\uFEFF]/g, '').trim();
  }

  private static appendContentIntro(currentIntro: string, content: string, chapterTitle: string = '',
    bookName: string = '', bookAuthor: string = ''): string {
    let intro = currentIntro.trim();
    const normalizedTitle = chapterTitle.replace(/\s+/g, ' ').trim();
    const normalizedBookName = bookName.replace(/\s+/g, ' ').trim();
    const normalizedAuthor = bookAuthor.replace(/\s+/g, ' ').trim();
    const paragraphs = content.replace(/\r\n?/g, '\n').split(/\n+/);
    for (const paragraph of paragraphs) {
      const text = paragraph.replace(/[\uFEFF\u200B-\u200D\u2060]/g, '').replace(/\s+/g, ' ').trim();
      if (!text || text === normalizedTitle || text === normalizedBookName || text === normalizedAuthor) continue;
      if (LocalBookService.isEpubImageMarker(text)) continue;
      if (/^[【\[（(\s]*(?:书\s*名|作\s*者|作者名|内容简介|简介|文案|标签|分类|状态|来源|网址|更新|版权)\s*[】\]）)]?\s*[：:：\-—]/.test(text)) {
        continue;
      }
      if (/^(?:前言|序言|序|引言|楔子|目录|正文|内容简介|作品简介|作者简介|版权信息|书籍信息|出版说明|编辑推荐|文案)[！!。.]?$/.test(text)) {
        continue;
      }
      if (/^(?:第\s*)?[零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+[章节卷部篇回册集幕]\s*.{0,24}$/.test(text) ||
        /^[零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+\s+.{1,24}$/.test(text)) {
        continue;
      }
      if (text.length < 20 && !/[。！？!?，,；;：:]/.test(text)) {
        continue;
      }
      intro = intro ? `${intro} ${text}` : text;
      if (intro.length >= LocalBookService.LOCAL_INTRO_TARGET_LENGTH) {
        break;
      }
    }
    return intro.length > 240 ? `${intro.substring(0, 240).trim()}…` : intro;
  }

  private static async detectTextFileCharset(path: string): Promise<string> {
    const stat = await fs.stat(path);
    const sampleSize = Math.min(stat.size, 64 * 1024);
    if (sampleSize <= 0) return 'utf-8';
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(sampleSize);
      const readSize = await fs.read(file.fd, buffer);
      const bytes = new Uint8Array(buffer, 0, Math.max(0, readSize));
      return LocalBookService.detectCharset(bytes, readSize < stat.size);
    } finally {
      await fs.close(file);
    }
  }

  private static async parseEpub(context: Context, epubPath: string, id: string): Promise<EpubPackageData> {
    const stat = await fs.stat(epubPath);
    const extractRoot = `${context.filesDir}/local_books/${id}_${stat.mtime}`;
    if (!LocalBookService.exists(extractRoot)) {
      LocalBookService.ensureDir(extractRoot);
      await zlib.decompressFile(epubPath, extractRoot);
    }
    const containerPath = `${extractRoot}/META-INF/container.xml`;
    const containerText = (await LocalBookService.readTextFile(containerPath, 'utf-8')).text;
    const container = LocalBookService.parseXml(containerText);
    const rootfile = LocalBookService.findFirstNode(container, 'rootfile');
    const opfRelative = rootfile?.attributes['full-path'] || '';
    if (!opfRelative) {
      throw new Error('EPUB container.xml 缺少 OPF 路径');
    }
    const opfPath = LocalBookService.normalizePath(`${extractRoot}/${opfRelative}`);
    const opfDir = LocalBookService.parentPath(opfPath);
    const opfText = (await LocalBookService.readTextFile(opfPath, 'utf-8')).text;
    const opf = LocalBookService.parseXml(opfText);
    const result = new EpubPackageData();
    result.extractRoot = extractRoot;
    const metadata = LocalBookService.extractEpubMetadata(opf);
    result.title = metadata.title;
    result.author = metadata.author;

    const manifestNodes = LocalBookService.findNodes(opf, 'item');
    const manifest: Record<string, EpubManifestItem> = {};
    const manifestItems: EpubManifestItem[] = [];
    let navItem: EpubManifestItem | null = null;
    let ncxItem: EpubManifestItem | null = null;
    for (const node of manifestNodes) {
      const item = new EpubManifestItem();
      item.id = node.attributes['id'] || '';
      item.href = node.attributes['href'] || '';
      item.mediaType = node.attributes['media-type'] || '';
      item.properties = node.attributes['properties'] || '';
      if (item.id) {
        manifest[item.id] = item;
        manifestItems.push(item);
      }
      if (item.properties.split(/\s+/).includes('nav')) navItem = item;
      if (item.mediaType === 'application/x-dtbncx+xml') ncxItem = item;
    }

    const metadataNodes = LocalBookService.findNodes(opf, 'meta');
    let coverId = '';
    for (const node of metadataNodes) {
      if ((node.attributes['name'] || '').toLowerCase() === 'cover') {
        coverId = node.attributes['content'] || '';
      }
    }
    let coverItem = coverId ? manifest[coverId] : null;
    if (!coverItem) {
      for (const item of manifestItems) {
        if (item.properties.split(/\s+/).includes('cover-image')) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem?.href) {
      result.coverPath = LocalBookService.resolveBookPath(opfDir, coverItem.href);
    }

    let tocEntries: EpubTocEntry[] = [];
    if (navItem?.href) {
      const navPath = LocalBookService.resolveBookPath(opfDir, navItem.href);
      const navText = (await LocalBookService.readTextFile(navPath, 'utf-8')).text;
      tocEntries = EpubChapterPlanner.parseNavToc(navText, LocalBookService.parentPath(navPath), extractRoot);
    }
    if (tocEntries.length === 0 && ncxItem?.href) {
      const ncxPath = LocalBookService.resolveBookPath(opfDir, ncxItem.href);
      const ncxText = (await LocalBookService.readTextFile(ncxPath, 'utf-8')).text;
      tocEntries = EpubChapterPlanner.parseNcxToc(ncxText, LocalBookService.parentPath(ncxPath), extractRoot);
    }
    const spineNodes = LocalBookService.findNodes(opf, 'itemref');
    const files: LocalSpineFile[] = [];
    for (const spine of spineNodes) {
      const idref = spine.attributes['idref'] || '';
      const item = manifest[idref];
      if (!item || !item.href) continue;
      const chapterPath = EpubHtmlConverter.resolvePath(opfDir, item.href, extractRoot);
      if (!chapterPath || !LocalBookService.exists(chapterPath)) continue;
      const file = new LocalSpineFile();
      file.path = chapterPath;
      file.isImage = item.mediaType.toLowerCase().startsWith('image/');
      file.nonLinear = (spine.attributes['linear'] || '').toLowerCase() === 'no';
      files.push(file);
    }
    await LocalBookService.planSpineChapters(files, tocEntries, extractRoot, result);
    return result;
  }

  /**
   * MOBI 先拆成若干 HTML 文件和图片写进解压目录，之后与 EPUB 走同一套分章、转换和阅读时重建正文的流程。
   * 目录锚点是 filepos 位置插入的 id="fileposN"。解析和写文件在 TaskPool 里做，主线程只等结果。
   */
  private static async parseMobi(context: Context, mobiPath: string, id: string): Promise<EpubPackageData> {
    const stat = await fs.stat(mobiPath);
    const extractRoot = `${context.filesDir}/local_books/${id}_${stat.mtime}`;
    const mobi = await MobiImportTask.extract(mobiPath, extractRoot);
    const result = new EpubPackageData();
    result.extractRoot = extractRoot;
    result.title = mobi.title;
    result.author = mobi.author;
    result.coverPath = mobi.coverPath;
    const files: LocalSpineFile[] = [];
    for (const path of mobi.partPaths) {
      const file = new LocalSpineFile();
      file.path = path;
      files.push(file);
    }
    const tocEntries: EpubTocEntry[] = [];
    for (const item of mobi.toc) {
      if (item.part < 0 || item.part >= files.length) continue;
      const entry = new EpubTocEntry();
      entry.path = files[item.part].path;
      entry.fragment = item.fragment;
      entry.title = item.title;
      tocEntries.push(entry);
    }
    await LocalBookService.planSpineChapters(files, tocEntries, extractRoot, result);
    return result;
  }

  /**
   * 按 spine 顺序转换并分章；EPUB 与 MOBI（拆成多个 HTML 文件后）共用。
   * 读文件预读后面几个，与当前文件的转换并行；转换连续占用主线程超过一帧左右就让出一次，导入大书时界面不卡死。
   */
  private static async planSpineChapters(files: LocalSpineFile[], tocEntries: EpubTocEntry[],
    extractRoot: string, result: EpubPackageData): Promise<void> {
    const tocByPath = EpubChapterPlanner.groupTocByPath(tocEntries);
    const planner = new EpubChapterPlanner(tocByPath.size > 0);
    const included = (file: LocalSpineFile): boolean =>
      // linear="no" 的辅助内容（弹注、答案页）不在正文阅读顺序里，除非目录明确列出。
      !file.nonLinear || (tocByPath.get(file.path) || []).length > 0;
    const reads = new Map<number, Promise<string>>();
    const startRead = (index: number): void => {
      if (index >= files.length || reads.has(index) || files[index].isImage || !included(files[index])) return;
      const read = LocalChapterContentLoader.readHtmlFile(files[index].path);
      // 预读失败在轮到这个文件时处理，这里先标记为已处理，避免未处理的拒绝。
      read.catch((): void => {});
      reads.set(index, read);
    };
    let sliceStart = Date.now();
    const yieldIfBusy = async (): Promise<void> => {
      if (Date.now() - sliceStart < LocalBookService.IMPORT_SLICE_MS) return;
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });
      sliceStart = Date.now();
    };
    for (let index = 0; index < files.length; index++) {
      const file = files[index];
      const chapterPath = file.path;
      const entries = tocByPath.get(chapterPath) || [];
      if (!included(file)) continue;
      planner.beginFile();
      if (file.isImage) {
        const imagePiece = new EpubConvertResult();
        imagePiece.content = LocalBookService.createReaderImageMarker(chapterPath);
        imagePiece.imagePaths = [chapterPath];
        planner.addPiece(chapterPath, '', '', entries.length > 0 ? entries[0].title : '', imagePiece);
      } else {
        for (let ahead = index; ahead <= index + LocalBookService.IMPORT_READ_AHEAD; ahead++) startRead(ahead);
        try {
          const chapterHtml = await (reads.get(index) as Promise<string>);
          const body = EpubHtmlConverter.bodyOf(chapterHtml);
          const documentTitle = EpubHtmlConverter.titleOf(chapterHtml);
          const fallbackTitle = documentTitle && documentTitle !== result.title ? documentTitle : '';
          for (const cut of EpubChapterPlanner.planFileCuts(body, entries)) {
            const converted = await LocalChapterContentLoader.convertBody(body, chapterPath, extractRoot,
              cut.startId, cut.endId);
            planner.addPiece(chapterPath, cut.startId, cut.endId, cut.title, converted, fallbackTitle);
            await yieldIfBusy();
          }
        } catch (error) {
          console.warn('预解析 EPUB spine 内容失败:', chapterPath, error);
        } finally {
          reads.delete(index);
        }
      }
      planner.endFile();
      await yieldIfBusy();
    }
    EpubHtmlConverter.clearAnchorIndex();

    if (planner.isComicDominant()) {
      const waterfall = new LocalChapterData();
      waterfall.title = result.title || (planner.chapters.length > 0 ? planner.chapters[0].title : '') || '漫画正文';
      waterfall.content = planner.chapters
        .map((chapter: EpubPlannedChapter): string => chapter.content)
        .filter((content: string): boolean => !!content.trim())
        .join('\n\n');
      waterfall.imageOnly = LocalBookService.hasEpubImageMarkers(waterfall.content);
      result.chapters.push(waterfall);
      result.isComic = true;
    } else {
      result.planned = planner.chapters;
      for (const planned of planner.chapters) {
        const chapter = new LocalChapterData();
        chapter.title = planned.title;
        chapter.content = planned.content;
        chapter.sourcePath = planned.segments.length > 0 ? planned.segments[0].path : '';
        chapter.variable = EpubChapterPlanner.encodeVariable(planned.segments, planned.headings);
        chapter.imageOnly = planned.imageOnly;
        result.chapters.push(chapter);
      }
    }
  }

  private static extractEpubMetadata(opf: XmlNodeData): LocalBookMetadata {
    const result = new LocalBookMetadata();
    const metadataRoot = LocalBookService.findFirstNode(opf, 'metadata') || opf;
    const metaNodes = LocalBookService.findNodes(metadataRoot, 'meta');
    const mainTitleIds: string[] = [];
    const authorCreatorIds: string[] = [];

    for (const meta of metaNodes) {
      const property = (meta.attributes['property'] || meta.attributes['name'] || '').toLowerCase();
      const refines = (meta.attributes['refines'] || '').replace(/^#/, '');
      const value = LocalBookService.nodeText(meta) || meta.attributes['content'] || '';
      if (refines && LocalBookService.epubPropertyIs(property, 'title-type') &&
        value.trim().toLowerCase() === 'main') {
        mainTitleIds.push(refines);
      }
      if (refines && LocalBookService.epubPropertyIs(property, 'role') &&
        LocalBookService.isEpubAuthorRole(value)) {
        authorCreatorIds.push(refines);
      }
    }

    const titleNodes = LocalBookService.findNodes(metadataRoot, 'title');
    let titleNode: XmlNodeData | null = null;
    for (const node of titleNodes) {
      if (mainTitleIds.includes(node.attributes['id'] || '')) {
        titleNode = node;
        break;
      }
    }
    if (!titleNode && titleNodes.length > 0) {
      titleNode = titleNodes[0];
    }
    result.title = LocalBookService.cleanBookTitle(LocalBookService.nodeText(titleNode));
    if (!result.title) {
      result.title = LocalBookService.cleanBookTitle(
        LocalBookService.findEpubMetaValue(metaNodes, ['title']));
    }

    const creatorNodes = LocalBookService.findNodes(metadataRoot, 'creator');
    const authors: string[] = [];
    let hasExplicitAuthorRole = false;
    for (const node of creatorNodes) {
      const id = node.attributes['id'] || '';
      const role = node.attributes['role'] || '';
      if (authorCreatorIds.includes(id) || LocalBookService.isEpubAuthorRole(role)) {
        LocalBookService.appendUniqueMetadataValue(authors,
          LocalBookService.cleanBookAuthor(LocalBookService.nodeText(node)));
        hasExplicitAuthorRole = true;
      }
    }
    if (!hasExplicitAuthorRole) {
      for (const node of creatorNodes) {
        LocalBookService.appendUniqueMetadataValue(authors,
          LocalBookService.cleanBookAuthor(LocalBookService.nodeText(node)));
      }
    }
    if (authors.length === 0) {
      LocalBookService.appendUniqueMetadataValue(authors, LocalBookService.cleanBookAuthor(
        LocalBookService.findEpubMetaValue(metaNodes, ['creator', 'author'])));
    }
    result.author = authors.join('、');
    return result;
  }

  private static findEpubMetaValue(nodes: XmlNodeData[], propertyNames: string[]): string {
    for (const node of nodes) {
      const property = (node.attributes['property'] || node.attributes['name'] || '').toLowerCase();
      for (const name of propertyNames) {
        if (LocalBookService.epubPropertyIs(property, name)) {
          return LocalBookService.nodeText(node) || node.attributes['content'] || '';
        }
      }
    }
    return '';
  }

  private static epubPropertyIs(property: string, expected: string): boolean {
    const value = property.trim().toLowerCase();
    const suffix = expected.toLowerCase();
    return value === suffix || value.endsWith(`:${suffix}`) || value.endsWith(`/${suffix}`);
  }

  private static isEpubAuthorRole(role: string): boolean {
    const value = role.trim().toLowerCase();
    return value === 'aut' || value.endsWith(':aut') || value.endsWith('/aut');
  }

  private static appendUniqueMetadataValue(target: string[], value: string): void {
    if (value && !target.includes(value)) {
      target.push(value);
    }
  }

  private static parseXml(text: string): XmlNodeData {
    const root = new XmlNodeData();
    root.name = '#document';
    const stack: XmlNodeData[] = [root];
    // TextDecoder may preserve a UTF-8 BOM as U+FEFF; XmlPullParser then treats
    // the XML declaration as a processing instruction outside the document start.
    const encoded = new util.TextEncoder().encodeInto(text.replace(/^\uFEFF/, ''));
    const bytes = new ArrayBuffer(encoded.length);
    new Uint8Array(bytes).set(encoded);
    const parser = new xml.XmlPullParser(bytes, 'utf-8');
    parser.parse({
      supportDoctype: false,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, info: xml.ParseInfo): boolean => {
        if (eventType === xml.EventType.START_TAG) {
          const node = new XmlNodeData();
          node.name = LocalBookService.localName(info.getName());
          stack[stack.length - 1].children.push(node);
          stack.push(node);
        } else if (eventType === xml.EventType.TEXT || eventType === xml.EventType.CDSECT) {
          stack[stack.length - 1].text += info.getText();
        } else if (eventType === xml.EventType.END_TAG && stack.length > 1) {
          stack.pop();
        }
        return true;
      },
      attributeValueCallbackFunction: (name: string, value: string): boolean => {
        if (stack.length > 1) {
          stack[stack.length - 1].attributes[LocalBookService.localName(name)] = value;
        }
        return true;
      }
    });
    return root;
  }

  private static findFirstNode(root: XmlNodeData, name: string): XmlNodeData | null {
    if (root.name === name) return root;
    for (const child of root.children) {
      const found = LocalBookService.findFirstNode(child, name);
      if (found) return found;
    }
    return null;
  }

  private static findNodes(root: XmlNodeData, name: string): XmlNodeData[] {
    const result: XmlNodeData[] = [];
    LocalBookService.appendNodes(root, name, result);
    return result;
  }

  private static appendNodes(root: XmlNodeData, name: string, target: XmlNodeData[]): void {
    if (root.name === name) target.push(root);
    for (const child of root.children) {
      LocalBookService.appendNodes(child, name, target);
    }
  }

  private static nodeText(node: XmlNodeData | null): string {
    if (!node) return '';
    let text = node.text;
    for (const child of node.children) text += ` ${LocalBookService.nodeText(child)}`;
    return LocalBookService.decodeEntities(text).replace(/\s+/g, ' ').trim();
  }

  private static decodeEntities(value: string): string {
    return EpubHtmlConverter.decodeEntities(value);
  }

  private static async readTextFile(path: string, preferredCharset: string): Promise<DecodedLocalText> {
    const stat = await fs.stat(path);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const bytes = new Uint8Array(buffer);
      const charset = preferredCharset || LocalBookService.detectCharset(bytes);
      let text = '';
      try {
        text = util.TextDecoder.create(charset).decodeWithStream(bytes, { stream: false });
      } catch (e) {
        text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      }
      const result = new DecodedLocalText();
      result.text = text;
      result.charset = charset;
      return result;
    } finally {
      await fs.close(file);
    }
  }

  private static detectCharset(bytes: Uint8Array, sampleEndsBeforeFile: boolean = false): string {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) return 'utf-8';
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) return 'utf-16le';
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) return 'utf-16be';
    const utf16 = LocalBookService.detectBomlessUtf16(bytes);
    if (utf16) return utf16;
    try {
      // Keep the decoder stream open when this is only a file prefix. An incomplete UTF-8
      // character at the sampling boundary is then buffered instead of emitted as U+FFFD.
      const utf8 = util.TextDecoder.create('utf-8')
        .decodeWithStream(bytes, { stream: sampleEndsBeforeFile });
      const replacements = (utf8.match(/\uFFFD/g) || []).length;
      // GBK/GB18030 文件可能绝大多数是英文，仅夹少量中文；任何非法 UTF-8 都应触发中文编码回退。
      if (replacements === 0) return 'utf-8';
    } catch (e) {
    }
    return 'gb18030';
  }

  private static normalizeTxtCharset(charset: string): string {
    const value = (charset || '').trim().toLowerCase().replace(/_/g, '-');
    if (!value || value === 'auto') return '';
    if (value === 'gbk' || value === 'gb2312' || value === 'gb18030') return 'gb18030';
    if (value === 'utf8' || value === 'utf-8' || value === 'utf8-bom' || value === 'utf-8-bom') {
      return 'utf-8';
    }
    if (value === 'utf16-le' || value === 'utf16le' || value === 'utf-16le') return 'utf-16le';
    if (value === 'utf16-be' || value === 'utf16be' || value === 'utf-16be') return 'utf-16be';
    if (value === 'big5') return 'big5';
    if (value === 'koi8-r') return 'koi8-r';
    if (value === 'euc-kr') return 'euc-kr';
    if (value === 'euc-jp') return 'euc-jp';
    if (value === 'shift-jis' || value === 'sjis') return 'shift_jis';
    if (value === 'windows1250' || value === 'windows-1250') return 'windows-1250';
    if (value === 'ibm866') return 'ibm866';
    return '';
  }

  private static detectBomlessUtf16(bytes: Uint8Array): string {
    const length = Math.min(bytes.length - (bytes.length % 2), 4096);
    if (length < 8) return '';
    let evenNulls = 0;
    let oddNulls = 0;
    const pairs = length / 2;
    for (let i = 0; i < length; i += 2) {
      if (bytes[i] === 0) evenNulls++;
      if (bytes[i + 1] === 0) oddNulls++;
    }
    const threshold = Math.max(2, Math.floor(pairs * 0.2));
    if (oddNulls >= threshold && oddNulls > evenNulls * 3) return 'utf-16le';
    if (evenNulls >= threshold && evenNulls > oddNulls * 3) return 'utf-16be';
    return '';
  }

  private static parseFileNameMetadata(path: string): LocalBookMetadata {
    const result = new LocalBookMetadata();
    const stem = LocalBookService.fileStem(path).replace(/\s+/g, ' ').trim();
    const titleMatch = stem.match(/《\s*([^《》]+?)\s*》/);
    if (titleMatch) {
      result.title = LocalBookService.cleanBookTitle(titleMatch[1]);
    }

    const authorLabel = /(?:作\s*者|作者名)\s*[：:]\s*/.exec(stem);
    if (authorLabel && authorLabel.index >= 0) {
      if (!result.title && authorLabel.index > 0) {
        const titleText = stem.substring(0, authorLabel.index)
          .replace(/^[\s【\[（(]+/, '')
          .replace(/[\s】\]）)_—·|｜-]+$/, '');
        result.title = LocalBookService.cleanBookTitle(titleText);
      }
      let authorText = stem.substring(authorLabel.index + authorLabel[0].length);
      const titleBoundary = authorText.indexOf('《');
      if (titleBoundary >= 0) {
        authorText = authorText.substring(0, titleBoundary);
      }
      const wrapperBoundary = authorText.search(/[】\]）)]/);
      if (wrapperBoundary >= 0) {
        authorText = authorText.substring(0, wrapperBoundary);
      }
      const metadataBoundary = authorText.search(/\s+(?:书\s*名|内容简介|简介|分类|标签|状态|来源)\s*[：:]/);
      if (metadataBoundary >= 0) {
        authorText = authorText.substring(0, metadataBoundary);
      }
      authorText = authorText.replace(
        /\s*(?:[-—_·|｜]\s*)?(?:精校(?:版)?|校对版?|全本|全集|完结(?:版)?|出版(?:版)?|网络版)\s*$/,
        '');
      result.author = LocalBookService.cleanBookAuthor(authorText);
    }
    return result;
  }

  private static cleanBookTitle(value: string): string {
    let text = LocalBookService.normalizeMetadataText(value)
      .replace(/^书\s*名\s*[：:]\s*/, '')
      .trim();
    const wrapped = text.match(/^《\s*([^《》]+?)\s*》$/);
    if (wrapped) {
      text = wrapped[1].trim();
    }
    return text;
  }

  private static cleanBookAuthor(value: string): string {
    return LocalBookService.normalizeMetadataText(value)
      .replace(/^(?:作\s*者|作者名)\s*[：:]\s*/, '')
      .replace(/^[\s【\[（(]+/, '')
      .replace(/[\s】\]）)]+$/, '')
      .replace(/^[\s_—·|｜]+|[\s_—·|｜]+$/g, '')
      .trim();
  }

  private static normalizeMetadataText(value: string): string {
    return LocalBookService.decodeEntities(value || '')
      .replace(/[\u0000\u200B-\u200D\u2060\uFEFF]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  static extensionOf(path: string): string {
    const resourcePath = LocalBookService.withoutFragment(path).split('?')[0];
    let clean = resourcePath.toLowerCase();
    try {
      clean = decodeURIComponent(resourcePath).toLowerCase();
    } catch (_) {
    }
    const index = clean.lastIndexOf('.');
    return index >= 0 ? clean.substring(index + 1) : '';
  }

  static fileStem(path: string): string {
    const name = LocalBookService.displayName(path);
    const index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }

  private static displayName(path: string): string {
    const clean = decodeURIComponent(LocalBookService.withoutFragment(path).replace(/\/+$/, ''));
    const index = clean.lastIndexOf('/');
    return index >= 0 ? clean.substring(index + 1) : clean;
  }

  private static resolveBookPath(baseDir: string, relative: string): string {
    const decoded = decodeURIComponent(LocalBookService.withoutFragment(relative));
    return LocalBookService.normalizePath(`${baseDir}/${decoded}`);
  }

  private static normalizePath(path: string): string {
    const prefix = path.startsWith('/') ? '/' : '';
    const parts = path.replace(/\\/g, '/').split('/');
    const normalized: string[] = [];
    for (const part of parts) {
      if (!part || part === '.') continue;
      if (part === '..') {
        normalized.pop();
      } else {
        normalized.push(part);
      }
    }
    return `${prefix}${normalized.join('/')}`;
  }

  private static parentPath(path: string): string {
    const normalized = LocalBookService.normalizePath(path);
    const index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  private static withoutFragment(value: string): string {
    const index = value.indexOf('#');
    return index >= 0 ? value.substring(0, index) : value;
  }

  private static localName(value: string): string {
    const index = value.indexOf(':');
    return (index >= 0 ? value.substring(index + 1) : value).toLowerCase();
  }

  private static ensureDir(path: string): void {
    if (!LocalBookService.exists(path)) fs.mkdirSync(path, true);
  }

  static deleteLocalBookFiles(context: Context, book: Book): void {
    if (!LocalBookService.isLocalBook(book)) return;
    LocalBookService.deleteLocalPath(context, book.getVariable('localFilePath'));
    LocalBookService.deleteLocalPath(context, book.getVariable('localExtractRoot'));
  }

  private static deleteLocalPath(context: Context, path: string): void {
    const root = `${context.filesDir}/local_books`;
    if (!path || !path.startsWith(root) || !LocalBookService.exists(path)) return;
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const names = fs.listFileSync(path);
        for (const name of names) {
          LocalBookService.deleteLocalPath(context, `${path}/${name}`);
        }
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('[LocalBook] cleanup failed:', path, e);
    }
  }

  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static hashText(value: string): string {
    let hash = 2166136261;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private static async hashFile(path: string): Promise<string> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const digest = cryptoFramework.createMd('SHA256');
    const chunkSize = 256 * 1024;
    try {
      while (true) {
        const buffer = new ArrayBuffer(chunkSize);
        const readSize = await fs.read(file.fd, buffer);
        if (readSize <= 0) break;
        digest.updateSync({ data: new Uint8Array(buffer, 0, readSize) });
      }
      const data = digest.digestSync().data;
      let result = '';
      for (const byte of data) result += byte.toString(16).padStart(2, '0');
      return result;
    } finally {
      await fs.close(file);
    }
  }
}
