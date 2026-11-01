/** Fixed physical-page navigation. Independent of platform objects and text pagination. */
export class PdfPagePosition {
  static clamp(index: number, count: number): number {
    if (!Number.isFinite(count) || count <= 0) return 0;
    return Math.max(0, Math.min(Math.floor(count) - 1, Number.isFinite(index) ? Math.floor(index) : 0));
  }

  static title(index: number): string { return `第 ${Math.max(0, Math.floor(index)) + 1} 页`; }

  static percent(index: number, count: number, started: boolean = true): number {
    return started && count > 0 ? (PdfPagePosition.clamp(index, count) + 1) * 100 / count : 0;
  }

  static fromPercent(percent: number, count: number): number {
    const ratio = Number.isFinite(percent) ? Math.max(0, Math.min(100, percent)) / 100 : 0;
    return PdfPagePosition.clamp(Math.ceil(ratio * count - 1e-9) - 1, count);
  }
}

export class PdfOutlineEntry {
  /** Position in the flattened outline, used as its stable UI key. */
  id: string = '';
  title: string = '';
  /** Zero-based physical page, never a printed page label. */
  pageIndex: number = 0;
  depth: number = 0;
}

export class PdfImportSummary {
  title: string = '';
  author: string = '';
  pageCount: number = 0;
  coverPath: string = '';
  outline: PdfOutlineEntry[] = [];
  error: string = '';
}

export class PdfSearchRect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  static of(left: number, top: number, right: number, bottom: number): PdfSearchRect {
    const rect = new PdfSearchRect();
    rect.left = left; rect.top = top; rect.right = right; rect.bottom = bottom;
    return rect;
  }
}

export class PdfSearchHit {
  pageIndex: number = 0;
  rects: PdfSearchRect[] = [];
}

export class PdfSearchSummary {
  hits: PdfSearchHit[] = [];
  truncated: boolean = false;
  error: string = '';
}
