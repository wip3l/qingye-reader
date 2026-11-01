/** Serializable PDF raster metadata; native PDF/image objects stay in their task. */
export class PdfRasterPage {
  pageIndex: number = 0;
  pageWidth: number = 0;
  pageHeight: number = 0;
  rectLeft: number = 0;
  rectTop: number = 0;
  rectRight: number = 0;
  rectBottom: number = 0;
  imagePath: string = '';
  eligible: boolean = false;
  reason: string = '';
  error: string = '';
}

/** Shared limits and geometry, independent of native PDF objects. */
export class PdfRasterPolicy {
  static readonly MAX_INPUT_WIDTH: number = 1024;
  static readonly MAX_INPUT_PIXELS: number = 1024 * 1024;
  static readonly MAX_RETAINED_PAGES: number = 3;

  static inputWidth(width: number, height: number, intrinsicWidth: number, displayWidth: number): number {
    if (![width, height, intrinsicWidth, displayWidth].every((n: number): boolean => Number.isFinite(n) && n > 0)) return 0;
    // Never downsample an already detailed scan merely to make it eligible for AI.
    if (intrinsicWidth >= displayWidth * 2) return 0;
    return Math.max(1, Math.floor(Math.min(PdfRasterPolicy.MAX_INPUT_WIDTH, displayWidth,
      Math.max(128, intrinsicWidth), Math.sqrt(PdfRasterPolicy.MAX_INPUT_PIXELS * width / height))));
  }

  static candidates(index: number, count: number): number[] {
    const pages: number[] = [];
    for (const page of [index, index + 1, index - 1]) {
      if (Number.isInteger(page) && page >= 0 && page < count && !pages.includes(page)) pages.push(page);
    }
    return pages;
  }
}
