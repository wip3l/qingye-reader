export class ReaderQuickJumpTarget {
  chapterIndex: number = 0;
  chapterRatio: number = 0;
}

/** Inverse of ReaderInfoBarText.bookPercent: each chapter has equal weight. */
export class ReaderQuickJumpModel {
  static normalizeMode(mode: string): string {
    return mode === 'percent' || mode === 'page' ? mode : 'chapter';
  }

  static clampPercent(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 0;
  }

  static fromPercent(value: number, chapterCount: number): ReaderQuickJumpTarget {
    const target = new ReaderQuickJumpTarget();
    const count = Number.isFinite(chapterCount) ? Math.max(0, Math.floor(chapterCount)) : 0;
    if (count === 0) return target;
    const position = ReaderQuickJumpModel.clampPercent(value) * count / 100;
    // A chapter boundary denotes the preceding chapter's final page, not the next first page.
    target.chapterIndex = Math.max(0, Math.min(count - 1, Math.ceil(position - 1e-9) - 1));
    target.chapterRatio = Math.max(0, Math.min(1, position - target.chapterIndex));
    return target;
  }

  static pageIndex(ratio: number, pageCount: number): number {
    const count = Number.isFinite(pageCount) ? Math.max(1, Math.floor(pageCount)) : 1;
    const fraction = Number.isFinite(ratio) ? Math.max(0, Math.min(1, ratio)) : 0;
    return Math.max(0, Math.min(count - 1, Math.ceil(fraction * count - 1e-9) - 1));
  }
}
