import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { Book, BookChapter, ReaderActionMarker } from '@legado/sourceengine';
import { EpubChapterPlanner, EpubChapterSegment } from './EpubChapterPlanner';
import { EpubCssBackground, EpubCssBackgroundRule, EpubPageStyle } from './EpubCssBackground';
import { EpubConvertResult, EpubHtmlConverter, EpubImageRef } from './EpubHtmlConverter';
import { EpubLinkLocation, EpubLinkTarget } from './EpubLinkTarget';
import { EpubNoteLink } from './EpubNoteLink';
import { ReaderImageMarker } from './ReaderImageMarker';

/** 书内链接目标所在的章节，以及这一章里目标文件的那一段；找不到时 index 为 -1。 */
export class EpubTargetChapter {
  index: number = -1;
  segment: EpubChapterSegment = new EpubChapterSegment();

  constructor(index: number, segment: EpubChapterSegment) {
    this.index = index;
    this.segment = segment;
  }
}

export class LocalChapterContentLoader {
  // 纯图片段（漫画、图集）的图片按整页显示，不需要逐张读取尺寸；超过这个数量就不再读。
  private static readonly MAX_SIZED_IMAGES_WITHOUT_TEXT: number = 24;
  private static readonly IMAGE_SIZE_CACHE_LIMIT: number = 512;
  private static imageSizeCache: Map<string, number[]> = new Map<string, number[]>();
  private static readonly STYLESHEET_CACHE_LIMIT: number = 32;
  /** 解析过的样式表（只留背景图规则），键里带文件大小和修改时间，书重新解压后不会读到旧的。 */
  private static stylesheetCache: Map<string, EpubCssBackgroundRule[]> = new Map<string, EpubCssBackgroundRule[]>();

  static async load(book: Book, chapter: BookChapter): Promise<string> {
    if (book.getVariable('localFormat') === 'pdf') return '';
    if (book.origin !== 'local' || book.type !== 2) return '';
    const extractRoot = EpubHtmlConverter.normalizePath(book.getVariable('localExtractRoot'));
    if (!extractRoot) return '';
    let segments = EpubChapterPlanner.decodeSegments(chapter.variable);
    if (segments.length === 0) {
      const path = EpubHtmlConverter.normalizePath(EpubHtmlConverter.withoutFragment((chapter.resourceUrl || '').trim()));
      if (!path) return '';
      if (path.startsWith(`${extractRoot}/`) && this.isDirectory(path)) return this.loadImageDirectory(path);
      const whole = new EpubChapterSegment();
      whole.path = path;
      segments = [whole];
    }
    let content = '';
    let cachedPath = '';
    let cachedBody = '';
    let cachedStyle: EpubPageStyle | null = null;
    for (const segment of segments) {
      const path = EpubHtmlConverter.normalizePath(segment.path);
      if (!path.startsWith(`${extractRoot}/`) || !this.exists(path)) continue;
      let piece = '';
      if (EpubHtmlConverter.isImagePath(path)) {
        piece = ReaderImageMarker.create(path);
      } else {
        if (cachedPath !== path) {
          const html = await this.readHtmlFile(path);
          cachedBody = EpubHtmlConverter.bodyOf(html);
          cachedStyle = await this.pageStyle(html, path, extractRoot);
          cachedPath = path;
        }
        piece = (await this.convertBody(cachedBody, path, extractRoot, segment.startId, segment.endId,
          cachedStyle)).content;
      }
      if (!piece) continue;
      // 与 EpubChapterPlanner.addPiece 的拼接方式保持一致，缓存被清理后重建的正文偏移才不会变化。
      content = content ? `${content}\n\n${piece}` : piece;
    }
    return content;
  }

  /**
   * CBZ 的章节是一个图片目录（见 LocalArchiveImport.extractComic），图片按序号命名，
   * 按文件名排序即阅读顺序；拼接方式与导入时一致。
   */
  private static loadImageDirectory(dir: string): string {
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      console.warn('[LocalChapterContentLoader] list comic dir failed:', dir, e);
      return '';
    }
    return names.filter((name: string): boolean => EpubHtmlConverter.isImagePath(name))
      .sort()
      .map((name: string): string => ReaderImageMarker.create(`${dir}/${name}`))
      .join('\n\n');
  }

  private static isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
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
    endId: string, pageStyle: EpubPageStyle | null = null): Promise<EpubConvertResult> {
    const root = EpubHtmlConverter.normalizePath(extractRoot);
    const file = EpubHtmlConverter.normalizePath(filePath);
    const baseDir = EpubHtmlConverter.parentPath(file);
    const sizes = new Map<string, number[]>();
    const resolveLink = (href: string, note: boolean): string => {
      const target = href.startsWith('#') ? file : EpubHtmlConverter.resolvePath(baseDir, href, root);
      if (!target || !target.startsWith(`${root}/`)) return '';
      const relative = target.substring(root.length + 1);
      if (note) return EpubNoteLink.create(relative, EpubHtmlConverter.fragmentOf(href));
      // 书内链接只认正文文件：指向图片、样式表等的链接留作普通文字。
      if (EpubHtmlConverter.isImagePath(target) || !/\.(?:x?html?|xml)$/i.test(target)) return '';
      return EpubNoteLink.createLink(relative, EpubHtmlConverter.fragmentOf(href));
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
    const first = EpubHtmlConverter.convertBody(body, resolve, startId, endId, resolveLink, pageStyle);
    if ((first.imagePaths.length === 0 && first.backgroundPaths.length === 0) ||
      (!first.hasText && first.imagePaths.length > LocalChapterContentLoader.MAX_SIZED_IMAGES_WITHOUT_TEXT)) {
      return first;
    }
    for (const path of first.imagePaths.concat(first.backgroundPaths)) {
      sizes.set(path, await this.imageSize(path));
    }
    return EpubHtmlConverter.convertBody(body, resolve, startId, endId, resolveLink, pageStyle);
  }

  /**
   * 一个 XHTML 文件的样式上下文（链接的样式表、<style>、<html>/<body> 标签），供应用排版找出当插图用的背景图。
   * 外部样式表里 url() 相对样式表本身，这里换成以解压目录为根的绝对写法（/OEBPS/...），转换时照常解析。
   */
  static async pageStyle(html: string, filePath: string, extractRoot: string): Promise<EpubPageStyle> {
    const style = new EpubPageStyle();
    style.rootTags = EpubCssBackground.rootTags(html);
    const root = EpubHtmlConverter.normalizePath(extractRoot);
    const baseDir = EpubHtmlConverter.parentPath(EpubHtmlConverter.normalizePath(filePath));
    for (const href of EpubCssBackground.stylesheetHrefs(html)) {
      const cssPath = EpubHtmlConverter.resolvePath(baseDir, EpubHtmlConverter.decodeEntities(href), root);
      if (!cssPath || !cssPath.startsWith(`${root}/`) || !this.exists(cssPath)) continue;
      const rules = await this.stylesheetRules(cssPath, root, style.rules.length);
      style.rules = style.rules.concat(rules);
    }
    style.rules = style.rules.concat(EpubCssBackground.parseRules(EpubCssBackground.styleBlocks(html), null,
      style.rules.length));
    return style;
  }

  private static async stylesheetRules(cssPath: string, root: string,
    orderBase: number): Promise<EpubCssBackgroundRule[]> {
    let key = cssPath;
    try {
      const stat = fs.statSync(cssPath);
      key = `${cssPath}|${stat.size}|${stat.mtime}`;
    } catch (_) {
    }
    let rules = this.stylesheetCache.get(key);
    if (!rules) {
      let css = '';
      try {
        css = await this.readHtmlFile(cssPath);
      } catch (error) {
        console.warn('[LocalChapterContentLoader] read stylesheet failed:', cssPath, error);
      }
      const cssDir = EpubHtmlConverter.parentPath(cssPath);
      rules = EpubCssBackground.parseRules(css, (url: string): string => {
        const target = EpubHtmlConverter.resolvePath(cssDir, url, root);
        return target.startsWith(`${root}/`) ? target.substring(root.length) : '';
      });
      this.stylesheetCache.set(key, rules);
      while (this.stylesheetCache.size > LocalChapterContentLoader.STYLESHEET_CACHE_LIMIT) {
        const oldest = this.stylesheetCache.keys().next().value as string | undefined;
        if (oldest === undefined) break;
        this.stylesheetCache.delete(oldest);
      }
    }
    // 同一份样式表被多个文件共用，顺序号按本文件里的位置重新编。
    return rules.map((rule: EpubCssBackgroundRule, index: number): EpubCssBackgroundRule => {
      const copy = new EpubCssBackgroundRule();
      copy.tag = rule.tag;
      copy.id = rule.id;
      copy.classes = rule.classes;
      copy.specificity = rule.specificity;
      copy.order = orderBase + index;
      copy.url = rule.url;
      copy.repeat = rule.repeat;
      return copy;
    });
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

  /**
   * 书内链接指向的章节：同一个文件切成多章时按锚点所在位置挑。rawPath 是解压目录里的绝对路径。
   */
  static async chapterForTarget(chapters: BookChapter[], rawPath: string,
    fragment: string): Promise<EpubTargetChapter> {
    const path = EpubHtmlConverter.normalizePath(rawPath);
    const candidates: number[] = [];
    const ranges: EpubChapterSegment[] = [];
    for (let index = 0; index < chapters.length; index++) {
      const chapter = chapters[index];
      const segments = EpubChapterPlanner.decodeSegments(chapter.variable);
      if (segments.length === 0 &&
        EpubHtmlConverter.normalizePath(EpubHtmlConverter.withoutFragment(chapter.resourceUrl || '')) === path) {
        const whole = new EpubChapterSegment();
        whole.path = path;
        candidates.push(index);
        ranges.push(whole);
        continue;
      }
      for (const segment of segments) {
        if (EpubHtmlConverter.normalizePath(segment.path) !== path) continue;
        candidates.push(index);
        ranges.push(segment);
        break;
      }
    }
    if (candidates.length === 0) return new EpubTargetChapter(-1, new EpubChapterSegment());
    if (candidates.length === 1 || !fragment) return new EpubTargetChapter(candidates[0], ranges[0]);
    try {
      const body = EpubHtmlConverter.bodyOf(await LocalChapterContentLoader.readHtmlFile(path));
      const offset = EpubHtmlConverter.findAnchorOffset(body, fragment);
      if (offset >= 0) {
        for (let index = candidates.length - 1; index >= 0; index--) {
          const startId = ranges[index].startId;
          const start = startId ? EpubHtmlConverter.findAnchorOffset(body, startId) : 0;
          if (start >= 0 && start <= offset) return new EpubTargetChapter(candidates[index], ranges[index]);
        }
      }
    } catch (error) {
      console.warn('[LocalChapter] locate link target failed:', error);
    }
    return new EpubTargetChapter(candidates[0], ranges[0]);
  }

  /**
   * 应用排版里点了书内链接：找出目标所在章节，以及锚点后面的一小段文字和锚点前正文的长度，
   * 阅读页在目标章的源文本里按这段文字找回落点（见 EpubLinkTarget）。找不到目标章时返回 null。
   */
  static async locateLink(book: Book, chapters: BookChapter[], url: string): Promise<EpubLinkLocation | null> {
    const target = EpubNoteLink.parseLink(url);
    const root = EpubHtmlConverter.normalizePath(book.getVariable('localExtractRoot'));
    if (!target || !root) return null;
    const path = EpubHtmlConverter.normalizePath(`${root}/${target.path}`);
    if (!path.startsWith(`${root}/`) || !this.exists(path)) return null;
    const found = await LocalChapterContentLoader.chapterForTarget(chapters, path, target.fragment);
    if (found.index < 0) return null;
    const location = new EpubLinkLocation();
    location.chapterIndex = found.index;
    const segment = found.segment;
    const html = await this.readHtmlFile(path);
    const body = EpubHtmlConverter.bodyOf(html);
    const style = await this.pageStyle(html, path, root);
    // 锚点就是这一章的起点、或文件里找不到这个锚点时，落在这一段的开头。
    const anchor = target.fragment && target.fragment !== segment.startId &&
      EpubHtmlConverter.findAnchorOffset(body, target.fragment) >= 0 ? target.fragment : '';
    const plain = (content: string): string => ReaderActionMarker.strip(content.replace(
      new RegExp(`${LocalChapterContentLoader.escape(ReaderImageMarker.PREFIX)}[\\s\\S]*?` +
        `${LocalChapterContentLoader.escape(ReaderImageMarker.SUFFIX)}`, 'g'), ''));
    const after = await this.convertBody(body, path, root, anchor || segment.startId, segment.endId, style);
    location.needle = EpubLinkTarget.needle(plain(after.content));
    if (anchor) {
      const before = await this.convertBody(body, path, root, segment.startId, anchor, style);
      location.estimate = plain(before.content).length;
    }
    return location;
  }

  private static escape(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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
