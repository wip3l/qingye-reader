/**
 * 正文划线（可带笔记）。位置记在章节正文（净化、替换后的分页源文本）里，同时存选中原文和前后文，
 * 章节文本变化（改净化规则、重新下载、换源）后按原文重新找位置，见 BookAnnotationAnchor。
 */
export class BookAnnotation {
  id: number = 0;
  bookUrl: string = '';
  bookName: string = '';
  chapterIndex: number = 0;
  chapterName: string = '';
  /** 章节源文本里的起止下标（左闭右开）。 */
  start: number = 0;
  end: number = 0;
  quote: string = '';
  prefix: string = '';
  suffix: string = '';
  /** '#RRGGBB'。 */
  color: string = BookAnnotationStyles.DEFAULT_COLOR;
  style: string = BookAnnotationStyles.SOLID;
  note: string = '';
  createTime: number = 0;
  updateTime: number = 0;

  clone(): BookAnnotation {
    const copy = new BookAnnotation();
    copy.id = this.id;
    copy.bookUrl = this.bookUrl;
    copy.bookName = this.bookName;
    copy.chapterIndex = this.chapterIndex;
    copy.chapterName = this.chapterName;
    copy.start = this.start;
    copy.end = this.end;
    copy.quote = this.quote;
    copy.prefix = this.prefix;
    copy.suffix = this.suffix;
    copy.color = this.color;
    copy.style = this.style;
    copy.note = this.note;
    copy.createTime = this.createTime;
    copy.updateTime = this.updateTime;
    return copy;
  }
}

export class BookAnnotationStyles {
  static readonly SOLID: string = 'solid';
  static readonly WAVY: string = 'wavy';
  static readonly DASHED: string = 'dashed';
  static readonly BACKGROUND: string = 'bg';
  static readonly TEXT: string = 'text';
  static readonly ALL: string[] = ['solid', 'wavy', 'dashed', 'bg', 'text'];
  static readonly DEFAULT_COLOR: string = '#3B82F6';
  static readonly PRESET_COLORS: string[] = [
    '#EF4444', '#22C55E', '#3B82F6', '#A855F7', '#F97316', '#EC4899', '#14B8A6', '#9A4F1A'
  ];

  static normalizeStyle(style: string): string {
    return BookAnnotationStyles.ALL.indexOf(style) >= 0 ? style : BookAnnotationStyles.SOLID;
  }

  static normalizeColor(color: string): string {
    const text = (color || '').trim();
    return /^#[0-9a-fA-F]{6}$/.test(text) ? text.toUpperCase() : BookAnnotationStyles.DEFAULT_COLOR;
  }

  static label(style: string): string {
    switch (style) {
      case 'wavy': return '波浪线';
      case 'dashed': return '虚线';
      case 'bg': return '背景色';
      case 'text': return '字体色';
      default: return '单实线';
    }
  }

  /** 不透明 ARGB。 */
  static argb(color: string): number {
    const normalized = BookAnnotationStyles.normalizeColor(color);
    return (0xFF000000 | parseInt(normalized.substring(1), 16)) >>> 0;
  }
}

/** 一条划线在某章当前文本里解析出的位置。 */
export class BookAnnotationRange {
  annotation: BookAnnotation;
  start: number;
  end: number;

  constructor(annotation: BookAnnotation, start: number, end: number) {
    this.annotation = annotation;
    this.start = start;
    this.end = end;
  }
}

export class BookAnnotationAnchor {
  static readonly CONTEXT_LENGTH: number = 16;
  private static readonly MAX_CANDIDATES: number = 256;

  /** 按章节源文本取选中原文和前后文。 */
  static capture(annotation: BookAnnotation, source: string, start: number, end: number): void {
    const safeStart = Math.max(0, Math.min(source.length, start));
    const safeEnd = Math.max(safeStart, Math.min(source.length, end));
    annotation.start = safeStart;
    annotation.end = safeEnd;
    annotation.quote = source.substring(safeStart, safeEnd);
    annotation.prefix = source.substring(Math.max(0, safeStart - BookAnnotationAnchor.CONTEXT_LENGTH), safeStart);
    annotation.suffix = source.substring(safeEnd, Math.min(source.length, safeEnd + BookAnnotationAnchor.CONTEXT_LENGTH));
  }

  /**
   * 原位置上的文字没变就用原位置；否则在全章里找同样的原文，前后文吻合多的、离原位置近的优先。
   * 找不到返回 null，这条划线不画。
   */
  static resolve(annotation: BookAnnotation, source: string): number[] | null {
    const quote = annotation.quote;
    if (!quote || !source) return null;
    if (annotation.start >= 0 && annotation.end <= source.length &&
      source.substring(annotation.start, annotation.end) === quote) {
      return [annotation.start, annotation.end];
    }
    let best = -1;
    let bestScore = -1;
    let bestDistance = Number.MAX_VALUE;
    let from = 0;
    for (let count = 0; count < BookAnnotationAnchor.MAX_CANDIDATES; count++) {
      const index = source.indexOf(quote, from);
      if (index < 0) break;
      const score = BookAnnotationAnchor.suffixMatch(source.substring(0, index), annotation.prefix) +
        BookAnnotationAnchor.prefixMatch(source.substring(index + quote.length), annotation.suffix);
      const distance = Math.abs(index - annotation.start);
      if (score > bestScore || (score === bestScore && distance < bestDistance)) {
        best = index;
        bestScore = score;
        bestDistance = distance;
      }
      from = index + 1;
    }
    return best >= 0 ? [best, best + quote.length] : null;
  }

  /** 一章内所有能定位的划线，按起点排序。 */
  static resolveAll(annotations: BookAnnotation[], source: string): BookAnnotationRange[] {
    const result: BookAnnotationRange[] = [];
    for (const annotation of annotations) {
      const range = BookAnnotationAnchor.resolve(annotation, source);
      if (range) result.push(new BookAnnotationRange(annotation, range[0], range[1]));
    }
    result.sort((left: BookAnnotationRange, right: BookAnnotationRange): number =>
      left.start - right.start || left.annotation.createTime - right.annotation.createTime);
    return result;
  }

  /** 去掉选区首尾的空白和换行。返回 [start, end]，空选区返回 null。 */
  static trim(source: string, start: number, end: number): number[] | null {
    let safeStart = Math.max(0, Math.min(source.length, start));
    let safeEnd = Math.max(safeStart, Math.min(source.length, end));
    while (safeStart < safeEnd && /[\s　​￼]/.test(source.charAt(safeStart))) safeStart++;
    while (safeEnd > safeStart && /[\s　​￼]/.test(source.charAt(safeEnd - 1))) safeEnd--;
    return safeEnd > safeStart ? [safeStart, safeEnd] : null;
  }

  private static suffixMatch(text: string, expected: string): number {
    let count = 0;
    while (count < expected.length && count < text.length &&
      text.charAt(text.length - 1 - count) === expected.charAt(expected.length - 1 - count)) {
      count++;
    }
    return count;
  }

  private static prefixMatch(text: string, expected: string): number {
    let count = 0;
    while (count < expected.length && count < text.length && text.charAt(count) === expected.charAt(count)) count++;
    return count;
  }
}
