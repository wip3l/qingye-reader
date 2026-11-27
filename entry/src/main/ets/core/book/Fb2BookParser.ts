import { MobiBook, MobiBookParser, MobiImage, MobiTocItem } from './MobiBookParser';
import type { MobiTextDecoder } from './MobiBookParser';

class Fb2Section {
  html: string = '';
  title: string = '';
  id: string = '';
}

/**
 * FB2（FictionBook 2，俄语区常见的 XML 电子书）转成和 MOBI 一样的 MobiBook，之后写文件、分章走同一套流程：
 * - 编码取 XML 声明（常见 utf-8、windows-1251），书名、作者、封面取自 <description><title-info>；
 * - 正文 <body> 每个顶层 <section> 一段，嵌套的 section 变成小一级标题，有标题的都进目录；
 * - 注释 <body name="notes"> 单独成一段，正文里指向注释的 <a l:href="#id"> 改成指向那一段的锚点；
 * - <binary> 里的 base64 图片解出来，<image l:href="#id"/> 换成图片文件。
 * FB2 元素换成对应的 HTML：emphasis→em、strikethrough→s、empty-line→br、poem/stanza/v→诗行、
 * epigraph/cite→引用、subtitle→小标题、text-author→署名。
 */
export class Fb2BookParser {
  private static readonly MAX_DEPTH: number = 5;

  /** 文件开头是否像 FB2：XML 里出现 <FictionBook。 */
  static looksLikeFb2(head: string): boolean {
    return /<FictionBook[\s>]/.test(head);
  }

  /** XML 声明里的编码；没写时按 utf-8。 */
  static declaredEncoding(bytes: Uint8Array): string {
    let head = '';
    for (let i = 0; i < Math.min(bytes.length, 200); i++) head += String.fromCharCode(bytes[i]);
    const match = /encoding\s*=\s*["']([A-Za-z0-9_\-]+)["']/.exec(head);
    return match ? match[1].toLowerCase() : 'utf-8';
  }

  static parse(data: Uint8Array, decode: MobiTextDecoder, imageDir: string): MobiBook {
    const xml = decode(data, Fb2BookParser.declaredEncoding(data)).replace(/^﻿/, '');
    if (!Fb2BookParser.looksLikeFb2(xml.substring(0, 4096))) throw new Error('不是有效的 FB2 文件');
    const book = new MobiBook();

    // 图片：<binary id content-type>base64</binary>，按出现顺序编号。
    const imageNames: Map<string, string> = new Map<string, string>();
    const binary = /<binary\b([^>]*)>([\s\S]*?)<\/binary>/g;
    let match = binary.exec(xml);
    while (match) {
      const id = Fb2BookParser.attribute(match[1], 'id');
      const bytes = Fb2BookParser.base64(match[2]);
      const ext = MobiBookParser.imageExtension(bytes);
      if (id && ext) {
        const image = new MobiImage();
        image.recIndex = book.images.length + 1;
        image.bytes = bytes;
        image.ext = ext;
        book.images.push(image);
        imageNames.set(id, `${imageDir}/${MobiBookParser.imageName(image)}`);
      }
      match = binary.exec(xml);
    }

    const description = Fb2BookParser.firstElement(xml, 'description');
    const titleInfo = Fb2BookParser.firstElement(description, 'title-info');
    book.title = Fb2BookParser.plain(Fb2BookParser.firstElement(titleInfo, 'book-title'));
    const authors: string[] = [];
    const author = /<author\b[^>]*>([\s\S]*?)<\/author>/g;
    let authorMatch = author.exec(titleInfo);
    while (authorMatch) {
      const part = (name: string): string => Fb2BookParser.plain(Fb2BookParser.firstElement(authorMatch![1], name));
      const full = [part('first-name'), part('middle-name'), part('last-name')].filter((value: string): boolean => !!value)
        .join(' ') || part('nickname');
      if (full && !authors.includes(full)) authors.push(full);
      authorMatch = author.exec(titleInfo);
    }
    book.author = authors.join('、');
    const coverRef = /<image\b[^>]*?href\s*=\s*["']#([^"']+)["']/.exec(Fb2BookParser.firstElement(titleInfo, 'coverpage'));
    if (coverRef) {
      const name = imageNames.get(coverRef[1]);
      const image = name ? book.images.find((item: MobiImage): boolean =>
        name.endsWith(MobiBookParser.imageName(item))) : undefined;
      if (image) book.coverRecIndex = image.recIndex;
    }

    // 正文与注释：先按段收好，再统一改写链接（需要知道每个 id 落在哪一段）。
    const sections: Fb2Section[] = [];
    const tocDepths: number[] = [];
    const tocParts: number[] = [];
    const tocIds: string[] = [];
    const tocTitles: string[] = [];
    const bodies = /<body\b([^>]*)>([\s\S]*?)<\/body>/g;
    let bodyMatch = bodies.exec(xml);
    let anchorCount = 0;
    const nextId = (): string => `fb${++anchorCount}`;
    while (bodyMatch) {
      const name = Fb2BookParser.attribute(bodyMatch[1], 'name').toLowerCase();
      const content = bodyMatch[2];
      if (name === 'notes' || name === 'comments' || name === 'footnotes') {
        const section = new Fb2Section();
        section.title = Fb2BookParser.plain(Fb2BookParser.firstElement(content, 'title')) || '注释';
        section.id = nextId();
        section.html = `<h1 id="${section.id}">${Fb2BookParser.escape(section.title)}</h1>` +
          Fb2BookParser.convert(Fb2BookParser.withoutFirst(content, 'title'), 2, imageNames, nextId, null);
        sections.push(section);
        tocParts.push(sections.length - 1);
        tocIds.push(section.id);
        tocTitles.push(section.title);
        tocDepths.push(0);
      } else {
        const tops = Fb2BookParser.topSections(content);
        if (tops.length === 0) {
          const section = new Fb2Section();
          section.id = nextId();
          section.html = `<a id="${section.id}"></a>` + Fb2BookParser.convert(content, 1, imageNames, nextId, null);
          sections.push(section);
        } else {
          // 顶层 section 之前的书名页、题词等并进第一段。
          const lead = content.substring(0, content.indexOf(tops[0]));
          tops.forEach((top: string, index: number) => {
            const section = new Fb2Section();
            const partIndex = sections.length;
            const toc = (id: string, title: string, depth: number): void => {
              tocParts.push(partIndex);
              tocIds.push(id);
              tocTitles.push(title);
              tocDepths.push(depth);
            };
            section.html = (index === 0 && lead.trim() ? Fb2BookParser.convert(lead, 1, imageNames, nextId, null) : '') +
              Fb2BookParser.convert(top, 1, imageNames, nextId, toc);
            sections.push(section);
          });
        }
      }
      bodyMatch = bodies.exec(xml);
    }
    if (sections.length === 0) throw new Error('FB2 里没有正文');

    // id → 段号，改写 <a href="#id">。
    const idPart: Map<string, number> = new Map<string, number>();
    sections.forEach((section: Fb2Section, index: number) => {
      const ids = /\bid="([^"]+)"/g;
      let idMatch = ids.exec(section.html);
      while (idMatch) {
        if (!idPart.has(idMatch[1])) idPart.set(idMatch[1], index);
        idMatch = ids.exec(section.html);
      }
    });
    for (const section of sections) {
      book.parts.push(section.html.replace(/<a href="#([^"]+)"/g, (whole: string, id: string): string => {
        const part = idPart.get(id);
        return part === undefined ? whole : `<a href="${Fb2BookParser.partFile(part)}#${id}"`;
      }));
    }
    for (let i = 0; i < tocParts.length; i++) {
      const item = new MobiTocItem();
      item.part = tocParts[i];
      item.fragment = tocIds[i];
      item.title = tocDepths[i] > 0 ? tocTitles[i] : tocTitles[i];
      book.toc.push(item);
    }
    if (!book.title) book.title = book.toc.length > 0 ? book.toc[0].title : '';
    return book;
  }

  static partFile(index: number): string {
    return `part${`${index + 1}`.padStart(5, '0')}.html`;
  }

  /** content 里直接一层的 <section>…</section>（按嵌套配对，不被里面的 section 截断）。 */
  static topSections(content: string): string[] {
    const result: string[] = [];
    const tag = /<(\/?)section\b[^>]*>/g;
    let depth = 0;
    let start = -1;
    let match = tag.exec(content);
    while (match) {
      if (match[1] === '') {
        if (depth === 0) start = match.index;
        depth++;
      } else if (depth > 0) {
        depth--;
        if (depth === 0 && start >= 0) {
          result.push(content.substring(start, match.index + match[0].length));
          start = -1;
        }
      }
      match = tag.exec(content);
    }
    return result;
  }

  /**
   * FB2 片段 → HTML。section 的标题按层级变成 h1…h6，带上 id 记进目录（toc 为 null 时不记）。
   */
  static convert(fragment: string, depth: number, images: Map<string, string>, nextId: () => string,
    toc: ((id: string, title: string, depth: number) => void) | null): string {
    let out = '';
    const tag = /<(\/?)([A-Za-z][\w:-]*)([^>]*?)(\/?)>/g;
    let last = 0;
    let level = depth - 1;
    // 只在 title 里时把 <p> 换成换行；记下标题的 HTML 位置，结束时补上目录。
    let titleStart = -1;
    let titleId = '';
    let titleText = '';
    let inTitle = 0;
    const sectionIds: string[] = [];
    let match = tag.exec(fragment);
    while (match) {
      const text = fragment.substring(last, match.index);
      out += text;
      if (inTitle > 0) titleText += text;
      last = match.index + match[0].length;
      const closing = match[1] === '/';
      const name = match[2].toLowerCase().replace(/^[a-z]+:/, '');
      const attrs = match[3];
      const selfClosing = match[4] === '/' || /\/\s*$/.test(attrs);
      switch (name) {
        case 'section':
          if (closing) {
            out += '</div>';
            level--;
          } else {
            level++;
            const id = Fb2BookParser.attribute(attrs, 'id');
            sectionIds.push(id);
            out += id ? `<div id="${Fb2BookParser.escape(id)}">` : '<div>';
          }
          break;
        case 'title':
          if (closing) {
            inTitle = 0;
            const heading = Math.min(6, Math.max(1, level + 1));
            out += `</h${heading}>`;
            if (toc && titleStart >= 0 && level <= Fb2BookParser.MAX_DEPTH) {
              const title = Fb2BookParser.plain(titleText).replace(/\s+/g, ' ').trim();
              if (title) toc(titleId, title, Math.max(0, level));
            }
            titleStart = -1;
          } else {
            inTitle = 1;
            titleText = '';
            titleStart = out.length;
            titleId = nextId();
            const heading = Math.min(6, Math.max(1, level + 1));
            out += `<h${heading} id="${titleId}">`;
          }
          break;
        case 'p':
          if (inTitle > 0) {
            if (closing) {
              titleText += ' ';
            } else if (!/<h[1-6] id="[^"]*">\s*$/.test(out)) {
              out += '<br/>';
            }
          } else {
            out += closing ? '</p>' : '<p>';
          }
          break;
        case 'empty-line':
          out += '<br/>';
          break;
        case 'emphasis':
          out += closing ? '</em>' : '<em>';
          break;
        case 'strong':
          out += closing ? '</strong>' : '<strong>';
          break;
        case 'strikethrough':
          out += closing ? '</s>' : '<s>';
          break;
        case 'sub':
        case 'sup':
        case 'code':
        case 'table':
        case 'tr':
        case 'td':
        case 'th':
          out += closing ? `</${name}>` : `<${name}>`;
          break;
        case 'subtitle':
          out += closing ? '</strong></p>' : '<p><strong>';
          break;
        case 'epigraph':
        case 'cite':
          out += closing ? '</blockquote>' : '<blockquote>';
          break;
        case 'poem':
        case 'stanza':
        case 'annotation':
          out += closing ? '</div>' : '<div>';
          break;
        case 'v':
          out += closing ? '</p>' : '<p>';
          break;
        case 'text-author':
          out += closing ? '</em></p>' : '<p><em>';
          break;
        case 'image': {
          const ref = /href\s*=\s*["']#([^"']+)["']/.exec(attrs);
          const src = ref ? images.get(ref[1]) : undefined;
          if (src && !closing) out += `<img src="${src}"/>`;
          break;
        }
        case 'a':
          if (closing) {
            out += '</a>';
          } else {
            const href = /href\s*=\s*["']([^"']*)["']/.exec(attrs);
            out += href ? `<a href="${Fb2BookParser.escape(href[1])}">` : '<a>';
            if (selfClosing) out += '</a>';
          }
          break;
        default:
          // 认不得的元素只留内容。
          break;
      }
      match = tag.exec(fragment);
    }
    out += fragment.substring(last);
    return out;
  }

  /** 去掉 content 里第一个 <name>…</name>。 */
  private static withoutFirst(content: string, name: string): string {
    const match = new RegExp(`<${name}\\b[^>]*>[\\s\\S]*?<\\/${name}>`).exec(content);
    return match ? content.substring(0, match.index) + content.substring(match.index + match[0].length) : content;
  }

  static firstElement(xml: string, name: string): string {
    const match = new RegExp(`<${name}\\b[^>]*>([\\s\\S]*?)<\\/${name}>`).exec(xml || '');
    return match ? match[1] : '';
  }

  static attribute(attrs: string, name: string): string {
    const match = new RegExp(`(?:^|\\s)(?:[\\w-]+:)?${name}\\s*=\\s*["']([^"']*)["']`).exec(attrs || '');
    return match ? match[1] : '';
  }

  /** 去标签、还原常见实体后的纯文本。 */
  static plain(fragment: string): string {
    return (fragment || '').replace(/<[^>]*>/g, ' ')
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, '\'')
      .replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
  }

  private static escape(text: string): string {
    return text.replace(/&(?!(?:[a-z]+|#\d+|#x[0-9a-f]+);)/gi, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  }

  /** base64 解码（忽略空白与非法字符）。 */
  static base64(text: string): Uint8Array {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const clean = text.replace(/[^A-Za-z0-9+/]/g, '');
    const out = new Uint8Array(Math.floor(clean.length * 3 / 4));
    let buffer = 0;
    let bits = 0;
    let length = 0;
    for (let i = 0; i < clean.length; i++) {
      buffer = (buffer << 6) | alphabet.indexOf(clean[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out[length++] = (buffer >> bits) & 0xFF;
      }
    }
    return out.subarray(0, length);
  }
}
