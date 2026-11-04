import { ReaderActionMarker } from '@legado/sourceengine';
import { EpubNoteLink } from './EpubNoteLink';
import { ReaderImageMarker } from './ReaderImageMarker';

/** 已解析到磁盘上的 EPUB 图片；宽高未知时为 0。 */
export class EpubImageRef {
  path: string = '';
  width: number = 0;
  height: number = 0;
}

/** 正文中的一个标题元素（h1-h6）。 */
export class EpubHeading {
  level: number = 0;
  text: string = '';
}

export class EpubConvertResult {
  content: string = '';
  /** 片段内的全部标题，供阅读器把对应段落按标题样式排版。 */
  headings: EpubHeading[] = [];
  /** 以块级标记输出的图片路径（去重，按出现顺序）。 */
  imagePaths: string[] = [];
  hasText: boolean = false;
  /** 第一个标题元素（h1-h6）的文本，供没有目录条目的章节取名。 */
  headingText: string = '';
}

export type EpubImageResolver = (source: string) => EpubImageRef | null;

/** 把正文里的注释链接（href 原样，相对当前文件）解析成 EpubNoteLink 地址；目标不在书内时返回空串。 */
export type EpubLinkResolver = (href: string) => string;

class EpubPendingImage {
  ref: EpubImageRef;
  alt: string;

  constructor(ref: EpubImageRef, alt: string) {
    this.ref = ref;
    this.alt = alt;
  }
}

/**
 * EPUB XHTML → 阅读器纯文本（段落以换行分隔，图片为独立的 ReaderImageMarker 行）。
 * 本模块不依赖任何系统 API：导入、阅读时重建以及 Node 回归脚本共用这一份实现。
 */
export class EpubHtmlConverter {
  /** 行内图片（外字、小图标）的最大边长，超过即视为插图。 */
  static readonly INLINE_IMAGE_MAX_SIDE: number = 64;

  private static readonly IMAGE_OPEN: string = '\uE000';
  private static readonly IMAGE_CLOSE: string = '\uE001';
  private static readonly PRE_NEWLINE: string = '\uE002';
  private static readonly SOFT_BREAK: string = '\uE003';
  private static readonly MAX_HEADINGS: number = 64;
  private static readonly MAX_HEADING_LENGTH: number = 80;
  private static readonly SUPERSCRIPT_DIGITS: string = '⁰¹²³⁴⁵⁶⁷⁸⁹';
  private static readonly SUBSCRIPT_DIGITS: string = '₀₁₂₃₄₅₆₇₈₉';
  private static readonly CJK: string = '\\u2E80-\\u9FFF\\uF900-\\uFAFF\\uFF00-\\uFFEF';
  private static readonly BLOCK_TAGS: string =
    'p|div|section|article|aside|header|footer|nav|main|figure|figcaption|h[1-6]|li|ul|ol|dl|dt|dd|' +
    'blockquote|table|thead|tbody|tfoot|tr|caption|pre|address|form|fieldset|center|details|summary';
  /** 链接文字超过这个长度就不当注释编号：显示文字整个放进动作标记，太长会被截断。 */
  private static readonly MAX_NOTE_LABEL_LENGTH: number = 40;
  private static readonly MAX_NOTE_HTML_LENGTH: number = 24000;
  private static readonly NOTE_CORE: string = '(?:\\d{1,4}|[０-９]{1,4}|[一二三四五六七八九十]{1,3}|[⁰¹²³⁴⁵⁶⁷⁸⁹]{1,4}|' +
    '[\\u2460-\\u24FF\\u2776-\\u2793\\u3251-\\u325F\\u32B1-\\u32BF]|[*＊†‡§]{1,3})';
  /** 像注释编号的链接文字：1、[1]、［注1］、①、¹、*、注。 */
  private static readonly NOTE_LABEL: RegExp = new RegExp('^[\\[［(（【〔〈]?\\s*(?:(?:注|註|note)\\s*' +
    `${EpubHtmlConverter.NOTE_CORE}?|${EpubHtmlConverter.NOTE_CORE})\\s*[\\]］)）】〕〉]?$`, 'i');
  private static readonly NOTE_CLASS: RegExp = /footnote|endnote|noteref|note-ref|notelink/i;
  private static readonly NOTE_SEMANTICS: RegExp = /\b(?:doc-)?(?:foot|end|rear)?notes?\b/;
  private static readonly NOTE_BLOCK_TAGS: string =
    'p|li|div|aside|section|article|dd|dt|td|blockquote|figure|ol|ul|dl|table|h[1-6]';
  private static namedEntities: Record<string, string> | null = null;
  /** 最近一次统计过“本文件内被注释链接引用的锚点”的 body，同一个文件切成多章时只统计一次。 */
  private static noteIdsBody: string = '';
  private static noteIds: Set<string> = new Set<string>();
  /** 最近一次建过锚点索引的 body。同一个文件按目录切成多章时，每切一章都要查两次锚点。 */
  private static anchorIndexBody: string = '';
  private static anchorIndex: Map<string, number> = new Map<string, number>();

  /** 返回 <body> 的内部 HTML；没有 body 时去掉 head 后原样返回。 */
  static bodyOf(html: string): string {
    const source = (html || '').replace(/^\uFEFF/, '');
    const body = /<body\b[^>]*>([\s\S]*?)<\/body>/i.exec(source);
    if (body) return body[1];
    const open = /<body\b[^>]*>/i.exec(source);
    if (open) return source.substring(open.index + open[0].length);
    return source.replace(/<head\b[\s\S]*?<\/head>/gi, '');
  }

  /** <title> 文本，供没有目录条目的章节取名。 */
  static titleOf(html: string): string {
    const match = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html || '');
    return match ? EpubHtmlConverter.inlineText(match[1]) : '';
  }

  static inlineText(html: string): string {
    return EpubHtmlConverter.decodeEntities((html || '')
      .replace(/<r[tp]\b[^>]*>[\s\S]*?<\/r[tp]>/gi, '')
      .replace(/<[^>]+>/g, ' '))
      .replace(/\s+/g, ' ').trim();
  }

  /**
   * 带有给定 id/name 的元素起始标签在 body 中的偏移；找不到返回 -1。
   * 第一次查某个 body 时扫一遍建好全部锚点的索引，之后同一个 body 直接查表：
   * 单文件里放着上千章的书逐章查锚点时，不再每次从头扫整个文件。
   */
  static findAnchorOffset(body: string, id: string): number {
    const target = (id || '').trim();
    if (!target) return 0;
    const source = body || '';
    if (source !== EpubHtmlConverter.anchorIndexBody) {
      EpubHtmlConverter.anchorIndex = EpubHtmlConverter.buildAnchorIndex(source);
      EpubHtmlConverter.anchorIndexBody = source;
    }
    const offset = EpubHtmlConverter.anchorIndex.get(target);
    return offset === undefined ? -1 : offset;
  }

  /** 导入结束后释放索引引用的整份 body。 */
  static clearAnchorIndex(): void {
    EpubHtmlConverter.anchorIndexBody = '';
    EpubHtmlConverter.anchorIndex = new Map<string, number>();
    EpubHtmlConverter.noteIdsBody = '';
    EpubHtmlConverter.noteIds = new Set<string>();
  }

  /** body 中每个 id/name 第一次出现的元素起始标签偏移。 */
  static buildAnchorIndex(body: string): Map<string, number> {
    const index = new Map<string, number>();
    const tag = /<[a-zA-Z][^<>]*>/g;
    const attribute = /\s(?:xml:)?(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    let match = tag.exec(body);
    while (match) {
      const text = match[0];
      // 绝大多数标签没有 id/name，先用 indexOf 粗筛。
      if (text.indexOf('id') >= 0 || text.indexOf('name') >= 0) {
        attribute.lastIndex = 0;
        let found = attribute.exec(text);
        while (found) {
          const value = found[1] !== undefined ? found[1] : (found[2] || '');
          if (!index.has(value)) index.set(value, match.index);
          found = attribute.exec(text);
        }
      }
      match = tag.exec(body);
    }
    return index;
  }


  /** 按锚点切出 [startId, endId) 之间的 body 片段；空 id 表示文件开头/结尾。 */
  static sliceBody(body: string, startId: string, endId: string): string {
    const source = body || '';
    let start = 0;
    if (startId) {
      const offset = EpubHtmlConverter.findAnchorOffset(source, startId);
      if (offset > 0) start = offset;
    }
    let end = source.length;
    if (endId) {
      const offset = EpubHtmlConverter.findAnchorOffset(source, endId);
      if (offset > start) end = offset;
    }
    return source.substring(start, end);
  }

  static convert(html: string, resolveImage: EpubImageResolver, startId: string = '',
    endId: string = ''): EpubConvertResult {
    return EpubHtmlConverter.convertBody(EpubHtmlConverter.bodyOf(html), resolveImage, startId, endId);
  }

  /**
   * resolveLink 为空时链接按普通文字处理（注释弹窗里的注释正文就是这样转换的）；
   * 给出时注释编号换成可点的动作标记，本文件里被这些编号引用的脚注块不再留在正文里。
   */
  static convertBody(body: string, resolveImage: EpubImageResolver, startId: string = '',
    endId: string = '', resolveLink: EpubLinkResolver | null = null): EpubConvertResult {
    const result = new EpubConvertResult();
    const images: EpubPendingImage[] = [];
    let source = EpubHtmlConverter.sliceBody(body, startId, endId)
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '')
      .replace(/<(script|style|template|head|title)\b[\s\S]*?<\/\1\s*>/gi, '')
      // 注音只保留被注的正文：<rt> 的读音与 <rp> 的括号都不属于正文。
      .replace(/<r[tp]\b[^>]*>[\s\S]*?<\/r[tp]\s*>/gi, '');
    if (resolveLink) {
      source = EpubHtmlConverter.removeReferencedNotes(source, EpubHtmlConverter.referencedNoteIds(body));
    }

    const headingPattern = /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1\s*>/gi;
    let headingMatch = headingPattern.exec(source);
    while (headingMatch && result.headings.length < EpubHtmlConverter.MAX_HEADINGS) {
      const headingText = EpubHtmlConverter.inlineText(headingMatch[2].replace(/<(?:img|image)\b[^>]*>/gi, ''));
      if (headingText && headingText.length <= EpubHtmlConverter.MAX_HEADING_LENGTH) {
        const heading = new EpubHeading();
        heading.level = parseInt(headingMatch[1], 10);
        heading.text = headingText;
        result.headings.push(heading);
      }
      headingMatch = headingPattern.exec(source);
    }
    if (result.headings.length > 0) result.headingText = result.headings[0].text;

    if (resolveLink) source = EpubHtmlConverter.replaceNoteLinks(source, body, resolveLink);
    source = EpubHtmlConverter.mapScriptDigits(source);

    // <pre> 内的换行是内容，其它位置的换行只是 HTML 空白。
    source = source.replace(/<pre\b[^>]*>[\s\S]*?<\/pre\s*>/gi, (block: string): string =>
      block.replace(/\r\n?|\n/g, EpubHtmlConverter.PRE_NEWLINE));

    const pushImage = (ref: EpubImageRef | null, alt: string): string => {
      if (!ref || !ref.path) return ' ';
      images.push(new EpubPendingImage(ref, alt));
      return `${EpubHtmlConverter.IMAGE_OPEN}${images.length - 1}${EpubHtmlConverter.IMAGE_CLOSE}`;
    };
    source = source
      .replace(/<(?:img|image)\b[^>]*>/gi, (tag: string): string => {
        const src = EpubHtmlConverter.findHtmlAttribute(tag, ['src', 'xlink:href', 'href']);
        if (!src || /^(?:data:|https?:)/i.test(src)) return ' ';
        return pushImage(resolveImage(EpubHtmlConverter.decodeEntities(src)),
          EpubHtmlConverter.decodeEntities(EpubHtmlConverter.findHtmlAttribute(tag, ['alt'])).trim());
      })
      .replace(/<object\b[^>]*>/gi, (tag: string): string => {
        const src = EpubHtmlConverter.findHtmlAttribute(tag, ['data']);
        if (!src || /^(?:data:|https?:)/i.test(src)) return ' ';
        const mediaType = EpubHtmlConverter.findHtmlAttribute(tag, ['type']).toLowerCase();
        if (!mediaType.startsWith('image/') && !EpubHtmlConverter.isImagePath(src)) return ' ';
        return pushImage(resolveImage(EpubHtmlConverter.decodeEntities(src)), '');
      });

    const cjk = EpubHtmlConverter.CJK;
    source = source
      // 两侧都是中日韩文字时，源码换行不应变成空格（CSS segment break 规则）。
      .replace(new RegExp(`([${cjk}])[ \\t]*(?:\\r\\n?|\\n)[ \\t]*(?=[${cjk}])`, 'g'), '$1')
      .replace(/[ \t\r\n\f]+/g, ' ')
      .replace(/<br\b[^>]*>/gi, EpubHtmlConverter.SOFT_BREAK)
      .replace(/<hr\b[^>]*>/gi, '\n')
      .replace(/<\/t[dh]\s*>\s*<t[dh]\b[^>]*>/gi, ' | ')
      .replace(/<li\b[^>]*>/gi, '\n　• ')
      .replace(new RegExp(`</?(?:${EpubHtmlConverter.BLOCK_TAGS})\\b[^>]*>`, 'gi'), '\n')
      .replace(/<[^>]+>/g, '');
    source = EpubHtmlConverter.decodeEntities(source)
      .replace(new RegExp(EpubHtmlConverter.PRE_NEWLINE, 'g'), '\n')
      .replace(/\u00A0/g, ' ');

    // 块级元素的边界是确定的段落边界，用空行分隔；<br> 只是块内换行，用单个换行分隔。
    // 阅读器会把相邻的短行当作软换行合并，空行让它不会把标题、短对话和下一段粘在一起。
    const paragraphs: string[] = [];
    const softBreakBefore: boolean[] = [];
    const imageToken = new RegExp(`${EpubHtmlConverter.IMAGE_OPEN}(\\d+)${EpubHtmlConverter.IMAGE_CLOSE}`, 'g');
    for (const block of source.split('\n')) {
      const blockStart = paragraphs.length;
      const pushText = (value: string): void => {
        // 只裁掉半角空白：段首的全角缩进属于正文，交给阅读器的缩进设置处理。
        const line = EpubHtmlConverter.trimAsciiSpace(value);
        if (!line.trim() || line.trim() === '•') return;
        softBreakBefore.push(paragraphs.length > blockStart);
        paragraphs.push(line);
        result.hasText = true;
      };
      for (const line of block.split(EpubHtmlConverter.SOFT_BREAK)) {
        if (line.indexOf(EpubHtmlConverter.IMAGE_OPEN) < 0) {
          pushText(line);
          continue;
        }
        const surroundingText = line.replace(imageToken, '').trim();
        let text = '';
        let cursor = 0;
        imageToken.lastIndex = 0;
        let match = imageToken.exec(line);
        while (match) {
          text += line.substring(cursor, match.index);
          cursor = match.index + match[0].length;
          const image = images[parseInt(match[1], 10)];
          if (image) {
            // 与文字同行且尺寸很小的图片是外字/小图标：用 alt 文本顶替，不再把段落截断成独立图片页。
            const longSide = Math.max(image.ref.width, image.ref.height);
            const inline = !!surroundingText && longSide > 0 &&
              longSide <= EpubHtmlConverter.INLINE_IMAGE_MAX_SIDE;
            if (inline) {
              text += image.alt;
            } else {
              pushText(text);
              text = '';
              softBreakBefore.push(false);
              paragraphs.push(ReaderImageMarker.create(image.ref.path, image.ref.width, image.ref.height));
              if (!result.imagePaths.includes(image.ref.path)) result.imagePaths.push(image.ref.path);
            }
          }
          match = imageToken.exec(line);
        }
        pushText(text + line.substring(cursor));
      }
    }

    let content = '';
    for (let index = 0; index < paragraphs.length; index++) {
      const paragraph = paragraphs[index];
      if (index === 0) {
        content = paragraph;
        continue;
      }
      const soft = softBreakBefore[index] && !ReaderImageMarker.isMarker(paragraphs[index - 1]);
      content += (soft ? '\n' : '\n\n') + paragraph;
    }
    result.content = content;
    return result;
  }

  /**
   * 纯数字的上标/下标（脚注编号、指数、化学式）换成对应的 Unicode 字符，
   * 否则去掉标签后 "正文<sup>1</sup>" 会变成 "正文1"。
   */
  private static mapScriptDigits(html: string): string {
    return html.replace(/<su([pb])\b[^>]*>([\s\S]*?)<\/su\1\s*>/gi,
      (all: string, kind: string, inner: string): string => {
        const digits = inner.replace(/<[^>]+>/g, '').trim();
        if (!/^\d{1,4}$/.test(digits)) return all;
        return EpubHtmlConverter.scriptDigits(digits, kind.toLowerCase() === 'p');
      });
  }

  private static scriptDigits(digits: string, superscript: boolean): string {
    const table = superscript ? EpubHtmlConverter.SUPERSCRIPT_DIGITS : EpubHtmlConverter.SUBSCRIPT_DIGITS;
    let mapped = '';
    for (let index = 0; index < digits.length; index++) mapped += table.charAt(digits.charCodeAt(index) - 48);
    return mapped;
  }

  /** 注释编号换成动作标记；标记的显示文字就是编号原来的文字，正文看起来和以前一样。 */
  private static replaceNoteLinks(source: string, body: string, resolveLink: EpubLinkResolver): string {
    if (source.search(/<a\b/i) < 0) return source;
    return source.replace(/<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi,
      (all: string, attributes: string, inner: string, offset: number, whole: string): string => {
        const before = whole.substring(Math.max(0, offset - 240), offset);
        const href = EpubHtmlConverter.noteHref(attributes, inner, before, body);
        if (!href) return all;
        const label = EpubHtmlConverter.noteLabel(inner, before);
        if (label.length > EpubHtmlConverter.MAX_NOTE_LABEL_LENGTH) return all;
        const url = resolveLink(href);
        const marker = url ? ReaderActionMarker.create(label, url) : '';
        return marker || all;
      });
  }

  /** 是注释编号时返回链接的 href，否则返回空串。before 是链接前面的一小段 HTML。 */
  private static noteHref(attributes: string, inner: string, before: string, body: string): string {
    const tag = `<a ${attributes}>`;
    const href = EpubHtmlConverter.decodeEntities(EpubHtmlConverter.findHtmlAttribute(tag, ['href', 'xlink:href']))
      .trim();
    if (!href || /^[a-z][a-z0-9+.-]*:/i.test(href) || !EpubHtmlConverter.fragmentOf(href)) return '';
    const semantics = EpubHtmlConverter.semanticsOf(tag);
    if (/\b(?:doc-)?backlink\b|\breferrer\b/.test(semantics)) return '';
    if (/\b(?:doc-)?noteref\b/.test(semantics) ||
      EpubHtmlConverter.NOTE_CLASS.test(EpubHtmlConverter.findHtmlAttribute(tag, ['class']))) {
      return href;
    }
    // 尾注列表里每条注释开头的编号是返回正文的链接，不是注释。
    if (EpubHtmlConverter.atBlockStart(before)) return '';
    if (href.startsWith('#') && EpubHtmlConverter.isNoteElement(body, EpubHtmlConverter.fragmentOf(href))) return href;
    const text = EpubHtmlConverter.inlineText(inner);
    if (!text) return /<(?:img|image)\b/i.test(inner) ? href : '';
    return EpubHtmlConverter.NOTE_LABEL.test(text) ? href : '';
  }

  private static noteLabel(inner: string, before: string): string {
    const text = EpubHtmlConverter.inlineText(EpubHtmlConverter.mapScriptDigits(inner));
    if (!text) return EpubNoteLink.ICON_LABEL;
    // <sup><a>1</a></sup>：上标包在链接外面。
    if (/^\d{1,4}$/.test(text) && /<sup\b[^>]*>\s*$/i.test(before)) return EpubHtmlConverter.scriptDigits(text, true);
    return text;
  }

  private static semanticsOf(tag: string): string {
    return `${EpubHtmlConverter.findHtmlAttribute(tag, ['epub:type'])} ` +
      `${EpubHtmlConverter.findHtmlAttribute(tag, ['role'])}`.toLowerCase();
  }

  /** before 的末尾是不是一个块的开头（中间只有标签和空白）。 */
  private static atBlockStart(before: string): boolean {
    const block = new RegExp(`</?(?:${EpubHtmlConverter.BLOCK_TAGS}|br)\\b[^>]*>`, 'gi');
    let last = -1;
    let match = block.exec(before);
    while (match) {
      last = match.index + match[0].length;
      match = block.exec(before);
    }
    return !EpubHtmlConverter.inlineText(last >= 0 ? before.substring(last) : before);
  }

  /** 锚点所在元素是不是脚注/尾注（本身是 aside 或注释语义的元素，或者在 aside 里）。 */
  private static isNoteElement(body: string, fragment: string): boolean {
    const offset = EpubHtmlConverter.findAnchorOffset(body, fragment);
    if (offset < 0) return false;
    const close = body.indexOf('>', offset);
    const tag = close > offset ? body.substring(offset, close + 1) : '';
    if (/^<aside\b/i.test(tag) || EpubHtmlConverter.NOTE_SEMANTICS.test(EpubHtmlConverter.semanticsOf(tag)) ||
      /duokan-footnote/i.test(EpubHtmlConverter.findHtmlAttribute(tag, ['class']))) {
      return true;
    }
    const aside = body.lastIndexOf('<aside', offset);
    return aside >= 0 && EpubHtmlConverter.elementEnd(body, aside, 'aside') > offset;
  }

  /** body 里被注释编号引用、且就在本文件内的锚点。 */
  private static referencedNoteIds(body: string): Set<string> {
    const source = body || '';
    if (source === EpubHtmlConverter.noteIdsBody) return EpubHtmlConverter.noteIds;
    const ids = new Set<string>();
    const anchor = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi;
    let match = anchor.exec(source);
    while (match) {
      const href = EpubHtmlConverter.noteHref(match[1], match[2],
        source.substring(Math.max(0, match.index - 240), match.index), source);
      if (href.startsWith('#')) ids.add(EpubHtmlConverter.fragmentOf(href));
      match = anchor.exec(source);
    }
    EpubHtmlConverter.noteIdsBody = source;
    EpubHtmlConverter.noteIds = ids;
    return ids;
  }

  /** 去掉含有被引用锚点的脚注块：aside、多看注释列表、带脚注语义的列表或区块。 */
  private static removeReferencedNotes(source: string, ids: Set<string>): string {
    if (ids.size === 0) return source;
    const open = /<(aside|ol|ul|div|section)\b[^>]*>/gi;
    let result = '';
    let cursor = 0;
    let match = open.exec(source);
    while (match) {
      const name = match[1].toLowerCase();
      const container = name === 'aside' ||
        /duokan-footnote-content/i.test(EpubHtmlConverter.findHtmlAttribute(match[0], ['class'])) ||
        EpubHtmlConverter.NOTE_SEMANTICS.test(EpubHtmlConverter.semanticsOf(match[0]));
      if (container) {
        const end = EpubHtmlConverter.elementEnd(source, match.index, name);
        if (EpubHtmlConverter.containsId(source.substring(match.index, end), ids)) {
          result += source.substring(cursor, match.index);
          cursor = end;
          open.lastIndex = end;
        }
      }
      match = open.exec(source);
    }
    return cursor === 0 ? source : result + source.substring(cursor);
  }

  private static containsId(html: string, ids: Set<string>): boolean {
    const attribute = /\s(?:xml:)?(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    let found = attribute.exec(html);
    while (found) {
      if (ids.has(found[1] !== undefined ? found[1] : (found[2] || ''))) return true;
      found = attribute.exec(html);
    }
    return false;
  }

  /** 从 start 处的 <name ...> 起，找到与它配对的结束标签之后的偏移；没有配对时到末尾。 */
  private static elementEnd(source: string, start: number, name: string): number {
    const pattern = new RegExp(`<(/?)${name}\\b[^>]*?(/?)>`, 'gi');
    pattern.lastIndex = start;
    let depth = 0;
    let match = pattern.exec(source);
    while (match) {
      if (match[1]) {
        depth--;
        if (depth <= 0) return match.index + match[0].length;
      } else if (!match[2]) {
        depth++;
      } else if (depth === 0) {
        return match.index + match[0].length;
      }
      match = pattern.exec(source);
    }
    return source.length;
  }

  /**
   * 注释锚点处的注释 HTML。锚点在块元素上时取整个块；在行内元素（如 <a id>）上时取包着它的块里、
   * 从锚点到下一个锚点之间的部分（一个段落里用 <br> 排着好几条注释的书）；取到的内容没有文字时取后面一个块。
   */
  static noteHtml(body: string, fragment: string): string {
    const source = body || '';
    const offset = EpubHtmlConverter.findAnchorOffset(source, fragment);
    if (offset < 0) return '';
    const nameMatch = /^<([a-zA-Z][\w:-]*)/.exec(source.substring(offset, offset + 64));
    const name = nameMatch ? nameMatch[1].toLowerCase() : '';
    const blockName = new RegExp(`^(?:${EpubHtmlConverter.NOTE_BLOCK_TAGS})$`, 'i');
    let html = '';
    let end = offset;
    if (blockName.test(name)) {
      end = EpubHtmlConverter.elementEnd(source, offset, name);
      html = source.substring(offset, end);
    } else {
      const block = new RegExp(`<(${EpubHtmlConverter.NOTE_BLOCK_TAGS})\\b[^>]*>`, 'gi');
      const lookStart = Math.max(0, offset - 4000);
      const lookBehind = source.substring(lookStart, offset);
      const starts: number[] = [];
      const names: string[] = [];
      let match = block.exec(lookBehind);
      while (match) {
        starts.push(lookStart + match.index);
        names.push(match[1].toLowerCase());
        match = block.exec(lookBehind);
      }
      end = source.length;
      for (let index = starts.length - 1; index >= 0 && index >= starts.length - 12; index--) {
        const blockEnd = EpubHtmlConverter.elementEnd(source, starts[index], names[index]);
        if (blockEnd > offset) {
          end = blockEnd;
          break;
        }
      }
      const nextAnchor = /<a\b[^>]*\s(?:id|name)\s*=/gi;
      nextAnchor.lastIndex = source.indexOf('>', offset) + 1;
      const next = nextAnchor.exec(source);
      if (next && next.index < end) end = next.index;
      html = source.substring(offset, end);
    }
    if (!EpubHtmlConverter.inlineText(EpubHtmlConverter.stripBacklinks(html))) {
      const following = new RegExp(`<(${EpubHtmlConverter.NOTE_BLOCK_TAGS})\\b[^>]*>`, 'gi');
      following.lastIndex = end;
      const next = following.exec(source);
      if (next) html += source.substring(next.index, EpubHtmlConverter.elementEnd(source, next.index,
        next[1].toLowerCase()));
    }
    return html.length > EpubHtmlConverter.MAX_NOTE_HTML_LENGTH ?
      html.substring(0, EpubHtmlConverter.MAX_NOTE_HTML_LENGTH) : html;
  }

  /** 注释正文：去掉返回正文的编号链接后按普通正文转换。 */
  static convertNote(body: string, fragment: string, resolveImage: EpubImageResolver): EpubConvertResult {
    const html = EpubHtmlConverter.stripBacklinks(EpubHtmlConverter.noteHtml(body, fragment));
    const result = EpubHtmlConverter.convertBody(html, resolveImage);
    // 编号链接去掉后，"1. 注释" 只剩下开头的标点。
    result.content = result.content.replace(/^[\s.．、,，:：]+/, '');
    return result;
  }

  private static stripBacklinks(html: string): string {
    return html.replace(/<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi, (all: string, attributes: string, inner: string): string => {
      const tag = `<a ${attributes}>`;
      if (!EpubHtmlConverter.findHtmlAttribute(tag, ['href', 'xlink:href'])) return all;
      if (/\b(?:doc-)?backlink\b|\breferrer\b/.test(EpubHtmlConverter.semanticsOf(tag))) return '';
      const text = EpubHtmlConverter.inlineText(EpubHtmlConverter.mapScriptDigits(inner));
      return !text || EpubHtmlConverter.NOTE_LABEL.test(text) || /^[↩↑⇧⤴^]|^返回|^back$/i.test(text) ? '' : all;
    });
  }

  private static trimAsciiSpace(value: string): string {
    return (value || '').replace(/[ \t]+/g, ' ').replace(/^ +| +$/g, '');
  }

  static isImagePath(value: string): boolean {
    return /\.(?:avif|bmp|gif|jpe?g|png|svg|webp)$/i.test(EpubHtmlConverter.withoutFragment(value || '').split('?')[0]);
  }

  static findHtmlAttribute(tag: string, names: string[]): string {
    for (const name of names) {
      const escaped = name.replace(':', '\\:');
      const match = new RegExp(`(?:^|[\\s"'])${escaped}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))`, 'i')
        .exec(tag || '');
      if (!match) continue;
      const value = match[1] !== undefined ? match[1] : (match[2] !== undefined ? match[2] : (match[3] || ''));
      if (value) return value;
    }
    return '';
  }

  static decodeEntities(value: string): string {
    const named = EpubHtmlConverter.entityTable();
    return (value || '').replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi,
      (raw: string, entity: string): string => {
        if (entity.charAt(0) === '#') {
          const hex = entity.charAt(1) === 'x' || entity.charAt(1) === 'X';
          const code = parseInt(entity.substring(hex ? 2 : 1), hex ? 16 : 10);
          if (!Number.isFinite(code) || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
            return raw;
          }
          return String.fromCodePoint(code);
        }
        const exact = named[entity];
        if (exact !== undefined) return exact;
        const lower = named[entity.toLowerCase()];
        if (lower === undefined) return raw;
        // Eacute/Ntilde 等大写字母实体与小写实体成对出现；AMP/LT 这类全大写写法按小写处理。
        return entity.charAt(0) !== entity.charAt(0).toLowerCase() && entity.substring(1) === entity.substring(1)
          .toLowerCase() && lower.length === 1 && lower.toUpperCase().length === 1 ? lower.toUpperCase() : lower;
      });
  }

  /**
   * 从 XML 声明、BOM 或 meta 中读取 XHTML 声明的编码，未声明时返回空串。
   * 返回值是 TextDecoder 可接受的标签。
   */
  static sniffCharset(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) return 'utf-8';
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) return 'utf-16le';
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) return 'utf-16be';
    if (bytes.length >= 4 && bytes[0] === 0x3C && bytes[1] === 0 && bytes[2] === 0x3F && bytes[3] === 0) {
      return 'utf-16le';
    }
    if (bytes.length >= 4 && bytes[0] === 0 && bytes[1] === 0x3C && bytes[2] === 0 && bytes[3] === 0x3F) {
      return 'utf-16be';
    }
    let head = '';
    const limit = Math.min(bytes.length, 1024);
    for (let index = 0; index < limit; index++) {
      const code = bytes[index];
      head += code < 0x80 ? String.fromCharCode(code) : '?';
    }
    const declared = /<\?xml\b[^>]*\bencoding\s*=\s*["']([A-Za-z0-9._-]+)["']/i.exec(head) ||
      /<meta\b[^>]*\bcharset\s*=\s*["']?([A-Za-z0-9._-]+)/i.exec(head);
    return declared ? EpubHtmlConverter.normalizeCharset(declared[1]) : '';
  }

  static normalizeCharset(value: string): string {
    const name = (value || '').trim().toLowerCase().replace(/_/g, '-');
    if (!name) return '';
    if (name === 'utf8' || name === 'utf-8') return 'utf-8';
    if (name === 'gbk' || name === 'gb2312' || name === 'gb18030' || name === 'x-gbk' || name === 'cp936') {
      return 'gb18030';
    }
    if (name === 'big5' || name === 'big5-hkscs' || name === 'cp950') return 'big5';
    if (name === 'shift-jis' || name === 'sjis' || name === 'x-sjis' || name === 'windows-31j' ||
      name === 'cp932') {
      return 'shift_jis';
    }
    if (name === 'euc-jp' || name === 'euc-kr') return name;
    if (name === 'utf-16' || name === 'utf-16le' || name === 'utf16le') return 'utf-16le';
    if (name === 'utf-16be' || name === 'utf16be') return 'utf-16be';
    if (name === 'iso-8859-1' || name === 'latin1' || name === 'windows-1252' || name === 'cp1252') {
      return 'windows-1252';
    }
    if (/^(?:windows-125\d|iso-8859-\d{1,2}|koi8-r|koi8-u|ibm866)$/.test(name)) return name;
    return '';
  }

  /** 把 EPUB 内的相对引用解析为绝对路径；以 "/" 开头的引用相对于容器根目录。 */
  static resolvePath(baseDir: string, value: string, containerRoot: string = ''): string {
    let clean = EpubHtmlConverter.withoutFragment((value || '').replace(/\\/g, '/')).split('?')[0];
    if (!clean) return '';
    try {
      clean = decodeURIComponent(clean);
    } catch (_) {
    }
    if (clean.startsWith('/')) {
      return EpubHtmlConverter.normalizePath(containerRoot ? `${containerRoot}/${clean}` : clean);
    }
    return EpubHtmlConverter.normalizePath(`${baseDir}/${clean}`);
  }

  static normalizePath(value: string): string {
    const source = (value || '').replace(/\\/g, '/');
    const prefix = source.startsWith('/') ? '/' : '';
    const parts: string[] = [];
    for (const part of source.split('/')) {
      if (!part || part === '.') continue;
      if (part === '..') {
        if (parts.length > 0) parts.pop();
      } else {
        parts.push(part);
      }
    }
    return prefix + parts.join('/');
  }

  static parentPath(path: string): string {
    const normalized = EpubHtmlConverter.normalizePath(path);
    const index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  static withoutFragment(value: string): string {
    const index = (value || '').indexOf('#');
    return index >= 0 ? value.substring(0, index) : (value || '');
  }

  static fragmentOf(value: string): string {
    const index = (value || '').indexOf('#');
    if (index < 0) return '';
    const fragment = value.substring(index + 1);
    try {
      return decodeURIComponent(fragment);
    } catch (_) {
      return fragment;
    }
  }

  private static entityTable(): Record<string, string> {
    if (EpubHtmlConverter.namedEntities) return EpubHtmlConverter.namedEntities;
    const table: Record<string, string> = {};
    const pairs: string[] = [
      'amp', '&', 'lt', '<', 'gt', '>', 'quot', '"', 'apos', "'", 'nbsp', ' ',
      'ensp', '\u2002', 'emsp', '\u2003', 'thinsp', '\u2009', 'shy', '', 'zwj', '\u200D', 'zwnj', '\u200C',
      'lrm', '', 'rlm', '', 'mdash', '—', 'ndash', '–', 'hellip', '…', 'lsquo', '‘', 'rsquo', '’',
      'sbquo', '‚', 'ldquo', '“', 'rdquo', '”', 'bdquo', '„', 'laquo', '«', 'raquo', '»',
      'lsaquo', '‹', 'rsaquo', '›', 'copy', '©', 'reg', '®', 'trade', '™', 'middot', '·', 'bull', '•',
      'deg', '°', 'times', '×', 'divide', '÷', 'plusmn', '±', 'minus', '−', 'sect', '§', 'para', '¶',
      'euro', '€', 'pound', '£', 'yen', '¥', 'cent', '¢', 'curren', '¤', 'frac12', '½', 'frac14', '¼',
      'frac34', '¾', 'sup1', '¹', 'sup2', '²', 'sup3', '³', 'prime', '′', 'Prime', '″',
      'larr', '←', 'rarr', '→', 'uarr', '↑', 'darr', '↓', 'harr', '↔', 'iexcl', '¡', 'iquest', '¿',
      'dagger', '†', 'Dagger', '‡', 'permil', '‰', 'ne', '≠', 'le', '≤', 'ge', '≥', 'infin', '∞',
      'micro', 'µ', 'ordf', 'ª', 'ordm', 'º', 'not', '¬', 'macr', '¯', 'acute', '´', 'cedil', '¸',
      'uml', '¨', 'tilde', '˜', 'circ', 'ˆ', 'brvbar', '¦', 'szlig', 'ß', 'aelig', 'æ', 'oelig', 'œ',
      'eth', 'ð', 'thorn', 'þ', 'oslash', 'ø', 'aring', 'å', 'ccedil', 'ç', 'ntilde', 'ñ', 'yacute', 'ý',
      'yuml', 'ÿ', 'scaron', 'š',
      'aacute', 'á', 'agrave', 'à', 'acirc', 'â', 'auml', 'ä', 'atilde', 'ã',
      'eacute', 'é', 'egrave', 'è', 'ecirc', 'ê', 'euml', 'ë',
      'iacute', 'í', 'igrave', 'ì', 'icirc', 'î', 'iuml', 'ï',
      'oacute', 'ó', 'ograve', 'ò', 'ocirc', 'ô', 'ouml', 'ö', 'otilde', 'õ',
      'uacute', 'ú', 'ugrave', 'ù', 'ucirc', 'û', 'uuml', 'ü'
    ];
    for (let index = 0; index + 1 < pairs.length; index += 2) table[pairs[index]] = pairs[index + 1];
    EpubHtmlConverter.namedEntities = table;
    return table;
  }
}
