import { EpubChapterSegment } from './EpubChapterPlanner';
import { EpubHtmlConverter } from './EpubHtmlConverter';
import { EpubDuokanExtensions } from './EpubDuokanExtensions';

/** 一个章节片段对应文件的原始 XHTML。 */
export class EpubOriginalPiece {
  /** 文件相对解压目录的路径。 */
  path: string = '';
  html: string = '';
}

/** 页面要嵌进章节文档末尾的样式与脚本。 */
export class EpubOriginalInjection {
  style: string = '';
  script: string = '';
}

/**
 * 原版排版：把一章（可能来自多个文件，或一个文件里按锚点切出的一段）拼成一份 HTML 交给网页组件。
 * 书里的样式表、内联样式、字体、图片原样保留；所有相对地址改写成虚拟站点下的绝对地址，
 * 由网页组件的请求拦截从解压目录读出来。书里的脚本一律不执行。
 * 本模块不依赖系统 API，Node 回归脚本直接测这一份实现。
 */
export class EpubOriginalDocument {
  static readonly ORIGIN: string = 'https://epub.legado.local';
  /** 拼好的章节文档挂在这个目录下，不和书里的文件重名。 */
  static readonly CHAPTER_DIR: string = '__legado_chapter';
  /** 应用阅读字体在虚拟站点里的地址前缀，后面跟字体文件名（只用来带出扩展名）。 */
  static readonly READER_FONT_DIR: string = '__legado_reader_font';
  private static readonly VOID_TAGS: string =
    'area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr';

  /** 解压目录内的相对路径 → 虚拟地址。 */
  static urlFor(path: string, fragment: string = ''): string {
    const encoded = (path || '').split('/').map((part: string): string => encodeURIComponent(part)).join('/');
    return `${EpubOriginalDocument.ORIGIN}/${encoded}${fragment ? `#${encodeURIComponent(fragment)}` : ''}`;
  }

  static chapterUrl(index: number, serial: number): string {
    return `${EpubOriginalDocument.ORIGIN}/${EpubOriginalDocument.CHAPTER_DIR}/${index}-${serial}.html`;
  }

  /** 虚拟地址 → 解压目录内的相对路径（不含锚点与查询串）；不是虚拟站点或越出解压目录时返回空串。 */
  static pathOf(url: string): string {
    const value = url || '';
    const prefix = `${EpubOriginalDocument.ORIGIN}/`;
    if (!value.startsWith(prefix)) return '';
    let path = value.substring(prefix.length);
    const cut = path.search(/[?#]/);
    if (cut >= 0) path = path.substring(0, cut);
    try {
      path = decodeURIComponent(path).replace(/\\/g, '/');
    } catch (_) {
      return '';
    }
    if (path.startsWith('/') || path.split('/').includes('..')) return '';
    return EpubHtmlConverter.normalizePath(path);
  }

  /** 文件所在目录（相对解压目录）；文件在根目录时为空串。 */
  static directoryOf(path: string): string {
    const normalized = EpubHtmlConverter.normalizePath(path || '');
    const slash = normalized.lastIndexOf('/');
    return slash > 0 ? normalized.substring(0, slash) : '';
  }

  static fragmentOf(url: string): string {
    return EpubHtmlConverter.fragmentOf(url || '');
  }

  static readerFontUrl(fileName: string): string {
    return `${EpubOriginalDocument.ORIGIN}/${EpubOriginalDocument.READER_FONT_DIR}/${encodeURIComponent(fileName || 'font.ttf')}`;
  }

  static isReaderFontUrl(url: string): boolean {
    return (url || '').startsWith(`${EpubOriginalDocument.ORIGIN}/${EpubOriginalDocument.READER_FONT_DIR}/`);
  }

  static isChapterUrl(url: string): boolean {
    return (url || '').startsWith(`${EpubOriginalDocument.ORIGIN}/${EpubOriginalDocument.CHAPTER_DIR}/`);
  }

  static mimeType(path: string): string {
    const extension = (/\.([a-z0-9]+)$/i.exec(path || '') || ['', ''])[1].toLowerCase();
    const types: Record<string, string> = {
      'css': 'text/css', 'xhtml': 'application/xhtml+xml', 'html': 'text/html', 'htm': 'text/html',
      'xml': 'application/xml', 'svg': 'image/svg+xml', 'png': 'image/png', 'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp', 'avif': 'image/avif',
      'ttf': 'font/ttf', 'otf': 'font/otf', 'woff': 'font/woff', 'woff2': 'font/woff2',
      'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'mp4': 'video/mp4'
    };
    return types[extension] || 'application/octet-stream';
  }

  /** 文本类资源需要声明编码。 */
  static isText(mime: string): boolean {
    return mime.startsWith('text/') || mime.endsWith('+xml') || mime === 'application/xml';
  }

  /** 书里的脚本不执行：拦截时对这些地址返回空响应。 */
  static isScript(path: string): boolean {
    return /\.(?:m?js)$/i.test(path || '');
  }

  static build(pieces: EpubOriginalPiece[], segments: EpubChapterSegment[], injection: EpubOriginalInjection,
    title: string): string {
    const byPath = new Map<string, string>();
    for (const piece of pieces) byPath.set(piece.path, piece.html);
    const heads: string[] = [];
    const seenHeads = new Set<string>();
    const bodies: string[] = [];
    let htmlAttributes = '';
    let bodyAttributes = '';
    for (const segment of segments) {
      const html = byPath.get(segment.path);
      if (html === undefined) continue;
      const source = html.replace(/^﻿/, '');
      const baseDir = EpubOriginalDocument.directoryOf(segment.path);
      if (bodies.length === 0) {
        htmlAttributes = EpubOriginalDocument.attributesOf(source, 'html');
        bodyAttributes = EpubOriginalDocument.attributesOf(source, 'body');
      }
      if (!seenHeads.has(segment.path)) {
        seenHeads.add(segment.path);
        heads.push(EpubOriginalDocument.headOf(source, baseDir, segment.path));
      }
      const body = EpubHtmlConverter.sliceBody(EpubHtmlConverter.bodyOf(source), segment.startId, segment.endId);
      bodies.push(`<div data-legado-file="${EpubOriginalDocument.escapeAttribute(segment.path)}">` +
        `${EpubOriginalDocument.rewrite(body, baseDir, segment.path)}</div>`);
    }
    return '<!DOCTYPE html>\n' +
      `<html${EpubOriginalDocument.rewrite(htmlAttributes, '', '')}><head><meta charset="utf-8">` +
      '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">' +
      `<title>${EpubOriginalDocument.escapeText(title)}</title>${heads.join('')}` +
      `<style id="legado-layout">${injection.style}</style></head>` +
      `<body${EpubOriginalDocument.rewrite(bodyAttributes, '', '')}>${bodies.join('')}` +
      `<script>${injection.script}</script></body></html>`;
  }

  /** 头部只留样式：样式表链接与 <style>，地址改成绝对的。 */
  private static headOf(source: string, baseDir: string, filePath: string): string {
    const head = /<head\b[^>]*>([\s\S]*?)<\/head\s*>/i.exec(source);
    if (!head) return '';
    const parts: string[] = [];
    const pattern = /<link\b[^>]*>|<style\b[^>]*>[\s\S]*?<\/style\s*>/gi;
    let match = pattern.exec(head[1]);
    while (match) {
      const tag = match[0];
      if (/^<link/i.test(tag)) {
        const rel = EpubHtmlConverter.findHtmlAttribute(tag, ['rel']).toLowerCase();
        if (rel.split(/\s+/).includes('stylesheet') && !/\balternate\b/.test(rel)) {
          parts.push(EpubOriginalDocument.rewrite(tag.replace(/\/>$/, '>'), baseDir, filePath));
        }
      } else {
        parts.push(EpubOriginalDocument.rewriteCss(tag, baseDir));
      }
      match = pattern.exec(head[1]);
    }
    return parts.join('');
  }

  private static attributesOf(source: string, name: string): string {
    const match = new RegExp(`<${name}\\b([^>]*)>`, 'i').exec(source);
    if (!match) return '';
    // xmlns 一类声明在 HTML 解析里没有意义，留着也无害；去掉自闭合斜杠。
    return match[1].replace(/\/\s*$/, '');
  }

  /**
   * 地址改写与 XHTML → HTML 的修补：src/href/poster/data 与内联样式、<style> 里的 url() 改成虚拟站点的绝对地址；
   * 非空元素的自闭合写法（<a id="x"/>、<div/>）在 HTML 解析下会吞掉后面的内容，改成成对标签。
   */
  static rewrite(html: string, baseDir: string, filePath: string): string {
    let result = (html || '')
      .replace(/<script\b[\s\S]*?<\/script\s*>/gi, '')
      .replace(/<script\b[^>]*\/>/gi, '')
      .replace(/\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*')/gi, '');
    result = result.replace(/(\s(?:src|href|xlink:href|poster|data)\s*=\s*)(["'])([^"']*)\2/gi,
      (all: string, prefix: string, quote: string, value: string): string => {
        const url = EpubOriginalDocument.absolute(EpubHtmlConverter.decodeEntities(value), baseDir, filePath);
        return url === null ? all : `${prefix}${quote}${EpubOriginalDocument.escapeAttribute(url)}${quote}`;
      });
    result = result.replace(/(\sstyle\s*=\s*)(?:"([^"]*)"|'([^']*)')/gi,
      (all: string, prefix: string, double: string | undefined, single: string | undefined): string =>
        double !== undefined ? `${prefix}"${EpubOriginalDocument.rewriteCss(double, baseDir)}"` :
          `${prefix}'${EpubOriginalDocument.rewriteCss(single || '', baseDir)}'`);
    result = result.replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi,
      (block: string): string => EpubOriginalDocument.rewriteCss(block, baseDir));
    const voidTags = new RegExp(`^(?:${EpubOriginalDocument.VOID_TAGS})$`, 'i');
    return result.replace(/<([a-zA-Z][\w:-]*)(\s[^<>]*?)?\s*\/>/g,
      (all: string, name: string, attributes: string | undefined): string => {
        if (voidTags.test(name)) return all;
        // svg 内部的自闭合元素（path、circle）由 HTML 解析器按外来元素正确处理。
        if (/^(?:path|circle|rect|line|polyline|polygon|ellipse|stop|use|image)$/i.test(name)) return all;
        return `<${name}${attributes || ''}></${name}>`;
      });
  }

  /** 样式里的 url() 改成虚拟站点的绝对地址，同时还原多看扩展（字体名、出血，见 EpubDuokanExtensions）。 */
  static rewriteCss(css: string, baseDir: string): string {
    return EpubDuokanExtensions.rewriteCss(css).replace(/url\(\s*(["']?)([^"')]+)\1\s*\)/gi, (all: string, quote: string, value: string): string => {
      const url = EpubOriginalDocument.absolute(value.trim(), baseDir, '');
      return url === null ? all : `url(${quote}${url}${quote})`;
    });
  }

  /** 相对地址 → 虚拟站点绝对地址；外部地址、data: 等保持原样（返回 null）。 */
  private static absolute(value: string, baseDir: string, filePath: string): string | null {
    const raw = (value || '').trim();
    if (!raw) return null;
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return null;
    if (raw.startsWith('#')) {
      if (!filePath) return null;
      return EpubOriginalDocument.urlFor(filePath, EpubHtmlConverter.fragmentOf(raw));
    }
    // 以 "/" 开头的地址相对于容器根目录，也就是解压目录。
    const relative = raw.startsWith('/') || !baseDir;
    const path = EpubHtmlConverter.resolvePath(relative ? '' : baseDir, raw.replace(/^\/+/, '')).replace(/^\/+/, '');
    if (!path) return null;
    return EpubOriginalDocument.urlFor(path, EpubHtmlConverter.fragmentOf(raw));
  }

  private static escapeAttribute(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;');
  }

  private static escapeText(value: string): string {
    return (value || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
