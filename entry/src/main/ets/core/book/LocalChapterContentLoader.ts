import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { Book, BookChapter } from '@legado/sourceengine';
import { EpubChapterPlanner, EpubChapterSegment } from './EpubChapterPlanner';
import { EpubConvertResult, EpubHtmlConverter, EpubImageRef } from './EpubHtmlConverter';
import { EpubNoteLink } from './EpubNoteLink';
import { ReaderImageMarker } from './ReaderImageMarker';

export class LocalChapterContentLoader {
  // 纯图片段（漫画、图集）的图片按整页显示，不需要逐张读取尺寸；超过这个数量就不再读。
  private static readonly MAX_SIZED_IMAGES_WITHOUT_TEXT: number = 24;
  private static readonly IMAGE_SIZE_CACHE_LIMIT: number = 512;
  private static imageSizeCache: Map<string, number[]> = new Map<string, number[]>();

  static async load(book: Book, chapter: BookChapter): Promise<string> {
    if (book.getVariable('localFormat') === 'pdf') return '';
    if (book.origin !== 'local' || book.type !== 2) return '';
    const extractRoot = EpubHtmlConverter.normalizePath(book.getVariable('localExtractRoot'));
    if (!extractRoot) return '';
    let segments = EpubChapterPlanner.decodeSegments(chapter.variable);
    if (segments.length === 0) {
      const path = EpubHtmlConverter.normalizePath(EpubHtmlConverter.withoutFragment((chapter.resourceUrl || '').trim()));
      if (!path) return '';
      const whole = new EpubChapterSegment();
      whole.path = path;
      segments = [whole];
    }
    let content = '';
    let cachedPath = '';
    let cachedBody = '';
    for (const segment of segments) {
      const path = EpubHtmlConverter.normalizePath(segment.path);
      if (!path.startsWith(`${extractRoot}/`) || !this.exists(path)) continue;
      let piece = '';
      if (EpubHtmlConverter.isImagePath(path)) {
        piece = ReaderImageMarker.create(path);
      } else {
        if (cachedPath !== path) {
          cachedBody = EpubHtmlConverter.bodyOf(await this.readHtmlFile(path));
          cachedPath = path;
        }
        piece = (await this.convertBody(cachedBody, path, extractRoot, segment.startId, segment.endId)).content;
      }
      if (!piece) continue;
      // 与 EpubChapterPlanner.addPiece 的拼接方式保持一致，缓存被清理后重建的正文偏移才不会变化。
      content = content ? `${content}\n\n${piece}` : piece;
    }
    return content;
  }

  /** 按文档声明的编码读取 XHTML；未声明且不是合法 UTF-8 时按 GB18030 处理。 */
  static async readHtmlFile(path: string): Promise<string> {
    const stat = await fs.stat(path);
    if (stat.size <= 0) return '';
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const bytes = new Uint8Array(buffer);
      const declared = EpubHtmlConverter.sniffCharset(bytes);
      let text = '';
      try {
        text = util.TextDecoder.create(declared || 'utf-8').decodeWithStream(bytes, { stream: false });
      } catch (_) {
        text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      }
      if (!declared && text.indexOf('�') >= 0) {
        try {
          text = util.TextDecoder.create('gb18030').decodeWithStream(bytes, { stream: false });
        } catch (_) {
        }
      }
      return text;
    } finally {
      await fs.close(file);
    }
  }

  /**
   * 转换一个文件片段。图文混排的片段会先读取图片原始尺寸再转换一次：
   * 尺寸写入图片标记供分页使用，同时用来识别行内小图。
   */
  static async convertBody(body: string, filePath: string, extractRoot: string, startId: string,
    endId: string): Promise<EpubConvertResult> {
    const root = EpubHtmlConverter.normalizePath(extractRoot);
    const file = EpubHtmlConverter.normalizePath(filePath);
    const baseDir = EpubHtmlConverter.parentPath(file);
    const sizes = new Map<string, number[]>();
    const resolveLink = (href: string): string => {
      const target = href.startsWith('#') ? file : EpubHtmlConverter.resolvePath(baseDir, href, root);
      if (!target || !target.startsWith(`${root}/`)) return '';
      return EpubNoteLink.create(target.substring(root.length + 1), EpubHtmlConverter.fragmentOf(href));
    };
    const resolve = (source: string): EpubImageRef | null => {
      const path = EpubHtmlConverter.resolvePath(baseDir, source, root);
      if (!path || !path.startsWith(`${root}/`) || !this.exists(path)) return null;
      const ref = new EpubImageRef();
      ref.path = path;
      const size = sizes.get(path);
      if (size && size.length === 2) {
        ref.width = size[0];
        ref.height = size[1];
      }
      return ref;
    };
    const first = EpubHtmlConverter.convertBody(body, resolve, startId, endId, resolveLink);
    if (first.imagePaths.length === 0 ||
      (!first.hasText && first.imagePaths.length > LocalChapterContentLoader.MAX_SIZED_IMAGES_WITHOUT_TEXT)) {
      return first;
    }
    for (const path of first.imagePaths) {
      sizes.set(path, await this.imageSize(path));
    }
    return EpubHtmlConverter.convertBody(body, resolve, startId, endId, resolveLink);
  }

  /** 读出注释链接指向的注释正文；找不到时返回 null。 */
  static async loadNote(book: Book, url: string): Promise<EpubConvertResult | null> {
    const target = EpubNoteLink.parse(url);
    const root = EpubHtmlConverter.normalizePath(book.getVariable('localExtractRoot'));
    if (!target || !root) return null;
    const path = EpubHtmlConverter.normalizePath(`${root}/${target.path}`);
    if (!path.startsWith(`${root}/`) || !this.exists(path)) return null;
    const body = EpubHtmlConverter.bodyOf(await this.readHtmlFile(path));
    const baseDir = EpubHtmlConverter.parentPath(path);
    const note = EpubHtmlConverter.convertNote(body, target.fragment, (source: string): EpubImageRef | null => {
      const image = EpubHtmlConverter.resolvePath(baseDir, source, root);
      if (!image || !image.startsWith(`${root}/`) || !this.exists(image)) return null;
      const ref = new EpubImageRef();
      ref.path = image;
      return ref;
    });
    return note.content ? note : null;
  }

  /** 只解码图片头部，返回 [宽, 高]；无法识别（如 SVG）时返回 [0, 0]。 */
  static async imageSize(path: string): Promise<number[]> {
    const cached = this.imageSizeCache.get(path);
    if (cached) return cached;
    let size: number[] = [0, 0];
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      if (info.size.width > 0 && info.size.height > 0) size = [info.size.width, info.size.height];
    } catch (_) {
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (_) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
    this.imageSizeCache.set(path, size);
    while (this.imageSizeCache.size > LocalChapterContentLoader.IMAGE_SIZE_CACHE_LIMIT) {
      const oldest = this.imageSizeCache.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.imageSizeCache.delete(oldest);
    }
    return size;
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }
}
