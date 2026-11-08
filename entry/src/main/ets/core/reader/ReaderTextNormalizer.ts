import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderParagraphIndent } from './ReaderParagraphIndent';

/**
 * 章节正文归一化（纯逻辑，不依赖 ArkUI）：换行与空白清理、软换行合并、段首缩进、重复标题剥离。
 * 分页偏移以这里的输出为基准，任何规则变化都会让已保存的字符偏移失效，改动前先跑
 * scripts/reader-text-normalizer-check.mjs。
 */
export class ReaderTextNormalizer {
  /** 标题行开头的章节号：第N章/节/回/卷…或 Chapter N。 */
  private static readonly HEADING_PREFIX: RegExp =
    /^(?:第\s*[\d０-９一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章节節回卷集部篇话話幕]|chapter\s*\d+)/i;
  /** 宽松比较标题时忽略的标点。 */
  private static readonly TITLE_PUNCTUATION: RegExp =
    /[!-\/:-@\[-`{-~、。，．：；！？…—–―·‧・“”‘’「」『』《》〈〉【】〔〕（）［］｛｝＂＇｀〜～｜／＼]/g;
  /** 首行以标题开头、后面直接接正文时，只有标题够长才剥离，免得“序”“楔子”截掉正文开头。 */
  private static readonly MIN_PREFIX_TITLE_LENGTH: number = 4;

  static isTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r' ||
      value === ' ' || value === '　' || value === '﻿' || value === '​' ||
      value === '‌' || value === '‍' || value === '⁠';
  }

  // 分页/分块起点只跳过换行与零宽字符，保留正文按字符数设置生成的段首缩进。
  static isPageStartTrimChar(value: string): boolean {
    return value === '\n' || value === '\r' || value === '﻿' ||
      value === '​' || value === '‌' || value === '‍' || value === '⁠';
  }

  static trim(text: string): string {
    const source = text || '';
    let start = 0;
    let end = source.length;
    while (start < end && ReaderTextNormalizer.isTrimChar(source.charAt(start))) {
      start++;
    }
    while (end > start && ReaderTextNormalizer.isTrimChar(source.charAt(end - 1))) {
      end--;
    }
    return source.substring(start, end);
  }

  static normalizeText(text: string): string {
    return ReaderTextNormalizer.trim((text || '')
      .replace(/\r\n/g, '\n')
      .replace(/ /g, ' ')
      .replace(/\n{3,}/g, '\n\n'));
  }

  /**
   * 传入 title 时同时剥离正文开头的重复标题。剥离放在软换行合并之前：标题行没有句末标点，又和较短的
   * 首段一起不足 48 字时会被并成一段，之后就认不出来了。合并前没认出来（如书源把标题拆成了两行）再合并后试一次。
   */
  static normalizeChapterBody(text: string, title: string = ''): string {
    const normalized = ReaderTextNormalizer.normalizeText(text);
    if (!title) {
      return ReaderTextNormalizer.mergeSoftWrappedLines(normalized);
    }
    const stripped = ReaderTextNormalizer.stripDuplicatedTitle(normalized, title);
    const merged = ReaderTextNormalizer.mergeSoftWrappedLines(stripped);
    return stripped !== normalized ? merged : ReaderTextNormalizer.stripDuplicatedTitle(merged, title);
  }

  static mergeSoftWrappedLines(text: string): string {
    if (!text || text.indexOf('\n') < 0) {
      return text;
    }
    const rawLines = text.split('\n');
    const result: string[] = [];
    let current = '';
    for (const rawLine of rawLines) {
      const line = rawLine.trim();
      if (!line) {
        if (current) {
          result.push(current);
          current = '';
        }
        if (result.length > 0 && result[result.length - 1] !== '') {
          result.push('');
        }
        continue;
      }
      if (!current) {
        current = line;
        continue;
      }
      if (ReaderTextNormalizer.shouldMergeSoftLine(current, rawLine)) {
        current += ReaderTextNormalizer.softLineJoiner(current, line) + line;
      } else {
        result.push(current);
        current = line;
      }
    }
    if (current) {
      result.push(current);
    }
    return result.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  static softLineJoiner(previous: string, next: string): string {
    const left = (previous || '').trim();
    const right = (next || '').trim();
    if (!left || !right || /[-‐‑‒–—]$/.test(left)) {
      return '';
    }
    return /[A-Za-z0-9,.:;\'"）)\]]$/.test(left) && /^[A-Za-z0-9]/.test(right) ? ' ' : '';
  }

  static shouldMergeSoftLine(previous: string, nextRaw: string): boolean {
    const prev = (previous || '').trim();
    const next = (nextRaw || '').trim();
    if (ReaderActionMarker.has(prev) || ReaderActionMarker.has(next)) {
      return false;
    }
    // 图片标记必须独占一行才会成为图片块；并进相邻段落后只能被当作行内标记隐藏掉。
    if (ReaderImageMarker.isMarker(prev) || ReaderImageMarker.isMarker(next)) {
      return false;
    }
    if (!prev || !next) {
      return false;
    }
    // 章节标题行自成一段，不与下一行合并。
    if (ReaderTextNormalizer.HEADING_PREFIX.test(prev)) {
      return false;
    }
    if (/^[　\s]/.test(nextRaw)) {
      return false;
    }
    if (/^[第卷章节回番外序楔引]\s*[\d一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾]/.test(next)) {
      return false;
    }
    if (/^[，,。！？!?；;：:、」』”）)]/.test(next)) {
      return true;
    }
    if (/[。！？!?；;」』”）)]$/.test(prev)) {
      return false;
    }
    return prev.length < 48 && next.length < 48;
  }

  static indentChapterBody(text: string, indentChars: number = ReaderParagraphIndent.DEFAULT): string {
    const normalized = ReaderTextNormalizer.normalizeChapterBody(text);
    if (!normalized) {
      return '';
    }
    return normalized
      .split('\n')
      .map((line: string) => ReaderTextNormalizer.indentLine(line, indentChars))
      .join('\n');
  }

  static indentLine(line: string, indentChars: number = ReaderParagraphIndent.DEFAULT): string {
    if (!line || line.trim().length === 0) {
      return line;
    }
    const trimmed = line.trim();
    // 图片标记是结构数据，不是正文段落；添加缩进会被分页器拆成一张不可见的文本页。
    if (ReaderImageMarker.isMarker(trimmed)) {
      return trimmed;
    }
    const indent = '　'.repeat(ReaderParagraphIndent.normalize(indentChars));
    return `${indent}${line.replace(/^[　\s]+/g, '')}`;
  }

  /**
   * 正文开头重复章节名时剥离。比较时忽略空白、零宽字符和行内交互标记：有的书源用零宽空格代替章节名里的
   * 空格，或者在标题行上挂段评。标题行前面的图片行（如卷首插图）和空行会被跳过并保留。
   * 认作标题行的情况：与标题相同；标题带章节号时只差标点（“第1章：开端”）或只差章节号（“开端”）。
   * 首行以标题开头、后面直接接着一句正文时只去掉标题部分，其余作为首段保留。
   */
  static stripDuplicatedTitle(body: string, title: string): string {
    if (!body || !title) {
      return body;
    }
    const wanted = ReaderTextNormalizer.titleKey(title);
    if (!wanted) {
      return body;
    }
    const lines = body.split('\n');
    let index = 0;
    while (index < lines.length && (!lines[index].trim() || ReaderImageMarker.isMarker(lines[index].trim()))) {
      index++;
    }
    if (index >= lines.length) {
      return body;
    }
    if (!ReaderTextNormalizer.isTitleLine(lines[index], title)) {
      const rest = ReaderTextNormalizer.stripTitlePrefix(lines[index], wanted);
      if (!rest) {
        return body;
      }
      lines[index] = rest;
      return ReaderTextNormalizer.trim(lines.join('\n'));
    }
    const rest = lines.slice(index + 1).join('\n').replace(/^\n+/, '');
    if (index === 0) {
      return ReaderTextNormalizer.trim(rest);
    }
    return ReaderTextNormalizer.trim(`${lines.slice(0, index).join('\n')}\n${rest}`);
  }

  private static isTitleLine(line: string, title: string): boolean {
    const lineKey = ReaderTextNormalizer.titleKey(line);
    const titleKey = ReaderTextNormalizer.titleKey(title);
    if (lineKey === titleKey) {
      return true;
    }
    // 宽松比较只用于带章节号的标题：不带章节号的标题可能本身就是一句话，只差句号的首行是正文。
    const prefix = ReaderTextNormalizer.HEADING_PREFIX.exec(titleKey);
    if (!prefix) {
      return false;
    }
    const looseLine = lineKey.replace(ReaderTextNormalizer.TITLE_PUNCTUATION, '');
    const looseTitle = titleKey.replace(ReaderTextNormalizer.TITLE_PUNCTUATION, '');
    if (looseTitle.length > 0 && looseLine === looseTitle) {
      return true;
    }
    // 只差章节号时要求逐字相同（含标点），“他笑了。”这样的首句不会被当成“第3章 他笑了”。
    const bare = titleKey.substring(prefix[0].length).replace(/^[:：、,，.．·\-—_|｜]+/, '');
    return bare.length >= 2 && lineKey === bare;
  }

  /** 行首是标题、后面紧接一句正文时返回去掉标题后的部分（保留其中的交互标记）；否则返回空串。 */
  private static stripTitlePrefix(line: string, key: string): string {
    if (key.length < ReaderTextNormalizer.MIN_PREFIX_TITLE_LENGTH) {
      return '';
    }
    let marker = ReaderActionMarker.findFirstRawRange(line, 0);
    let matched = 0;
    let pos = 0;
    while (pos < line.length && matched < key.length) {
      if (marker.length === 2 && pos >= marker[0]) {
        pos = Math.max(pos, marker[1]);
        marker = ReaderActionMarker.findFirstRawRange(line, pos);
        continue;
      }
      const char = line.charAt(pos);
      pos++;
      if (ReaderTextNormalizer.isTrimChar(char)) {
        continue;
      }
      if (char !== key.charAt(matched)) {
        return '';
      }
      matched++;
    }
    if (matched < key.length) {
      return '';
    }
    const rest = line.substring(pos).replace(/^[\s　:：、,，.．·\-—_|｜]+/, '');
    const plain = ReaderTextNormalizer.trim(ReaderActionMarker.strip(rest));
    // 剩下的得像一句正文：够长且带标点。“第一章 开端了”剩个“了”，说明首行只是碰巧以标题开头。
    return plain.length >= 6 && /[，。！？；…,.!?;]/.test(plain) ? rest : '';
  }

  /**
   * 把正文开头连续的图片行（中间可夹空行）拆出来：返回 [图片行, 其余正文]。开头不是图片时第一项为空串。
   */
  static splitLeadingImages(body: string): string[] {
    const lines = (body || '').split('\n');
    let index = 0;
    let lastImage = -1;
    while (index < lines.length && (!lines[index].trim() || ReaderImageMarker.isMarker(lines[index].trim()))) {
      if (lines[index].trim()) lastImage = index;
      index++;
    }
    if (lastImage < 0) {
      return ['', body || ''];
    }
    const images = lines.slice(0, lastImage + 1).map((line: string): string => line.trim())
      .filter((line: string): boolean => line.length > 0);
    // 只去掉开头的换行：正文已经缩进过，段首的全角空格要保留。
    return [images.join('\n\n'), lines.slice(lastImage + 1).join('\n').replace(/^\n+/, '')];
  }

  /** 两个标题去掉空白、零宽字符和交互标记后是否相同。 */
  static sameTitle(a: string, b: string): boolean {
    const key = ReaderTextNormalizer.titleKey(a);
    return key.length > 0 && key === ReaderTextNormalizer.titleKey(b);
  }

  /** 标题比较用的键：去掉交互标记和所有空白、零宽字符。 */
  private static titleKey(text: string): string {
    const plain = ReaderActionMarker.strip(text || '');
    let key = '';
    for (let index = 0; index < plain.length; index++) {
      const char = plain.charAt(index);
      if (!ReaderTextNormalizer.isTrimChar(char)) {
        key += char;
      }
    }
    return key;
  }

  /**
   * 把 [rawStart, rawEnd) 追加为一页；页首保留已有缩进，不给段落续行补缩进。
   * 裁掉首部换行与零宽字符、尾部空白；裁完为空则不追加。
   */
  static pushPage(source: string, rawStart: number, rawEnd: number, pages: string[], starts: number[],
    ends: number[]): void {
    let pageStart = Math.max(0, Math.min(rawStart, source.length));
    let pageEnd = Math.max(pageStart, Math.min(rawEnd, source.length));
    while (pageStart < pageEnd && ReaderTextNormalizer.isPageStartTrimChar(source.charAt(pageStart))) {
      pageStart++;
    }
    while (pageEnd > pageStart && ReaderTextNormalizer.isTrimChar(source.charAt(pageEnd - 1))) {
      pageEnd--;
    }
    const pageText = source.substring(pageStart, pageEnd);
    if (!pageText) {
      return;
    }
    pages.push(pageText);
    starts.push(pageStart);
    ends.push(pageEnd);
  }
}
