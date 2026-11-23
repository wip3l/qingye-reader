export class VirtualListScrollbar {
  static thumbLength(viewportHeight: number, totalCount: number, visibleCount: number,
    minimumLength: number = 24): number {
    const viewport = Math.max(0, viewportHeight);
    if (viewport <= 0 || totalCount <= 0) return 0;
    const visible = Math.max(1, Math.min(visibleCount, totalCount));
    return Math.min(viewport, Math.max(minimumLength, viewport * visible / totalCount));
  }

  static thumbOffset(viewportHeight: number, thumbLength: number, totalCount: number,
    firstVisibleIndex: number, visibleCount: number): number {
    const travel = Math.max(0, viewportHeight - thumbLength);
    const maxFirstIndex = Math.max(0, totalCount - Math.max(1, visibleCount));
    if (travel <= 0 || maxFirstIndex <= 0) return 0;
    const first = Math.max(0, Math.min(firstVisibleIndex, maxFirstIndex));
    return travel * first / maxFirstIndex;
  }

  static firstVisibleIndex(viewportHeight: number, thumbLength: number, totalCount: number,
    visibleCount: number, thumbOffset: number): number {
    const travel = Math.max(0, viewportHeight - thumbLength);
    const maxFirstIndex = Math.max(0, totalCount - Math.max(1, visibleCount));
    if (travel <= 0 || maxFirstIndex <= 0) return 0;
    const offset = Math.max(0, Math.min(thumbOffset, travel));
    return Math.round(maxFirstIndex * offset / travel);
  }

  /**
   * 滑块是否已拖到底。可见行数含首尾露出一部分的行，按首行换算到底时最后一行可能只露出一截，
   * 所以到底时调用方应把最后一行贴底对齐（ScrollAlign.END），而不是定位首行。
   */
  static reachesEnd(viewportHeight: number, thumbLength: number, thumbOffset: number): boolean {
    const travel = Math.max(0, viewportHeight - thumbLength);
    return travel > 0 && thumbOffset >= travel - 0.5;
  }

  static clampThumbOffset(viewportHeight: number, thumbLength: number, thumbOffset: number): number {
    return Math.max(0, Math.min(thumbOffset, Math.max(0, viewportHeight - thumbLength)));
  }
}
