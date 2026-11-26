import { BookChapter } from '@legado/sourceengine';

/**
 * 目录里显示的章节字数。书源目录给了字数（章节变量 wordCount）时用书源的；没给的，按缓存正文算出的字数显示，
 * 只在这一章仍有缓存时显示。算出的字数在写入正文缓存时存进 book_contents.contentChars，读各章缓存时间时一并取回，
 * 按书记在进程内，打开目录不读正文。
 */
export class ChapterWordCounts {
  private static readonly MAX_BOOKS: number = 12;
  private static books: Map<string, Map<number, number>> = new Map();

  /**
   * 只数文字：去掉图片、段评按钮等占位标记、HTML 标签和实体，空白不算，代理对算一个字。
   * 标记名里带数字（LEGADO_READER_ACTION_V3），段评标记每段一个、带编码后的热评，漏去掉会把字数撑大好几倍。
   */
  static count(content: string): number {
    if (!content) return 0;
    const text = content
      .replace(/\[\[LEGADO_[A-Z0-9_]+:[\s\S]*?\]\]/g, '')
      .replace(/<[^>]*>/g, '')
      .replace(/&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);/g, ' ');
    let total = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code >= 0xDC00 && code <= 0xDFFF) continue;
      if (code <= 0x20 || code === 0x3000 || code === 0xA0 || code === 0xFEFF ||
        (code >= 0x2000 && code <= 0x200B) || code === 0x2028 || code === 0x2029) {
        continue;
      }
      total++;
    }
    return total;
  }

  /** 用一本书全部缓存章节的字数替换进程内记录；值小于 0 表示还没补算。 */
  static replaceBook(bookUrl: string, counts: Map<number, number>): void {
    if (!bookUrl) return;
    ChapterWordCounts.books.delete(bookUrl);
    ChapterWordCounts.books.set(bookUrl, counts);
    while (ChapterWordCounts.books.size > ChapterWordCounts.MAX_BOOKS) {
      const oldest = ChapterWordCounts.books.keys().next().value as string;
      ChapterWordCounts.books.delete(oldest);
    }
  }

  /** 单章写入缓存后记下字数；这本书还没读过整本记录时不新建，等下次读目录。 */
  static remember(bookUrl: string, chapterIndex: number, count: number): void {
    const counts = ChapterWordCounts.books.get(bookUrl);
    if (counts) counts.set(chapterIndex, count);
  }

  static countOf(chapter: BookChapter, bookUrl: string): number {
    if (!chapter || chapter.cacheDate <= 0) return 0;
    const counts = ChapterWordCounts.books.get(bookUrl || chapter.bookUrl);
    const count = counts ? counts.get(chapter.index) : undefined;
    return count !== undefined && count > 0 ? count : 0;
  }

  static format(count: number): string {
    if (count >= 10000) {
      const wan = Math.round(count / 1000) / 10;
      return `${wan}万字`;
    }
    return `${count}字`;
  }

  /** 章节名下面一行：书源给的更新时间、字数；书源没给字数时补上缓存正文的字数。 */
  static metaText(chapter: BookChapter, bookUrl: string): string {
    const base = BookChapter.metaTextOf(chapter);
    if (ChapterWordCounts.hasSourceWordCount(chapter)) return base;
    const count = ChapterWordCounts.countOf(chapter, bookUrl);
    if (count <= 0) return base;
    const words = ChapterWordCounts.format(count);
    return base ? `${base} · ${words}` : words;
  }

  private static hasSourceWordCount(chapter: BookChapter): boolean {
    const variable = chapter ? chapter.variable : '';
    if (!variable || variable.indexOf('"wordCount"') < 0) return false;
    try {
      const parsed = JSON.parse(variable) as Record<string, Object>;
      return String(parsed['wordCount'] ?? '').trim().length > 0;
    } catch (e) {
      return false;
    }
  }
}
