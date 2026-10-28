/** Paragraph bubble size in percent; chapter comments retain their original size. */
export class ReaderCommentBubbleSize {
  static readonly DEFAULT: number = 80;
  static readonly MIN: number = 10;
  static readonly MAX: number = 200;

  static normalize(value: number): number {
    if (!Number.isFinite(value)) return ReaderCommentBubbleSize.DEFAULT;
    return Math.max(ReaderCommentBubbleSize.MIN, Math.min(ReaderCommentBubbleSize.MAX, Math.round(value)));
  }

  static scale(label: string, size: number): number {
    return label.includes('本章说') ? 1 : ReaderCommentBubbleSize.normalize(size) / 100;
  }

  static isCount(label: string): boolean {
    return /^\d+\+?$/.test(label.replace(/[\s\u2060]/g, ''));
  }

  static labelFontSize(label: string, baseFontSize: number): number {
    return baseFontSize * (ReaderCommentBubbleSize.isCount(label) ? 0.8 : 1);
  }

  /** Counts are capped at 99+ by the document parser; reserve the same body width for every count. */
  static countWidth(baseFontSize: number): number {
    return baseFontSize * 2.4;
  }
}
