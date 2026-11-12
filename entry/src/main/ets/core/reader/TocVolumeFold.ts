/**
 * 目录分卷的收起与展开。
 *
 * 卷名记在每卷第一章上（BookChapter.volumeTitleOf），这里只处理位置：volumeStarts 是这些章节在章节数组里的
 * 位置（升序）；第一个卷名之前的章节不属于任何卷，始终显示。
 *
 * 卷头画在这一卷在列表里最先出现的那一章上面：正序是卷首章，倒序是卷末章。收起一卷后只留卷头所在的那一行
 * （只画卷头、不画章节行），其余章节不进列表，所以收起和展开只影响卷头下方的内容，上方的列表项和滚动位置不动。
 */
export class TocVolumeFold {
  /** position 所在卷的卷首位置；不在任何卷里返回 -1。 */
  static volumeOf(volumeStarts: number[], position: number): number {
    let low = 0;
    let high = volumeStarts.length - 1;
    let found = -1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (volumeStarts[mid] <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found >= 0 ? volumeStarts[found] : -1;
  }

  /** 卷首为 start 的这一卷结束的位置（不含）。 */
  static volumeEnd(volumeStarts: number[], start: number, total: number): number {
    let low = 0;
    let high = volumeStarts.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (volumeStarts[mid] <= start) low = mid + 1;
      else high = mid - 1;
    }
    return low < volumeStarts.length ? Math.min(total, volumeStarts[low]) : total;
  }

  /** 这一卷在列表里画卷头的那一章：正序是卷首章，倒序是卷末章。 */
  static headPosition(volumeStarts: number[], start: number, total: number, reverse: boolean): number {
    return reverse ? TocVolumeFold.volumeEnd(volumeStarts, start, total) - 1 : start;
  }

  /** position 这一行上方要画卷头时返回卷首位置，否则返回 -1。 */
  static headVolumeAt(volumeStarts: number[], position: number, total: number, reverse: boolean): number {
    const start = TocVolumeFold.volumeOf(volumeStarts, position);
    if (start < 0) return -1;
    return TocVolumeFold.headPosition(volumeStarts, start, total, reverse) === position ? start : -1;
  }

  /** 收起的卷里，position 这一章不进列表时返回 true（卷头那一行仍在列表里）。 */
  static isHidden(volumeStarts: number[], collapsed: number[], position: number, total: number,
    reverse: boolean): boolean {
    if (collapsed.length === 0) return false;
    const start = TocVolumeFold.volumeOf(volumeStarts, position);
    if (start < 0 || collapsed.indexOf(start) < 0) return false;
    return TocVolumeFold.headPosition(volumeStarts, start, total, reverse) !== position;
  }

  /** 收起后仍在列表里、能代表 position 的那一行：没被收起时就是它自己，被收起时是所在卷的卷头行。 */
  static representative(volumeStarts: number[], collapsed: number[], position: number, total: number,
    reverse: boolean): number {
    if (!TocVolumeFold.isHidden(volumeStarts, collapsed, position, total, reverse)) return position;
    const start = TocVolumeFold.volumeOf(volumeStarts, position);
    return TocVolumeFold.headPosition(volumeStarts, start, total, reverse);
  }

  /** 按列表顺序列出要显示的章节位置。 */
  static visiblePositions(volumeStarts: number[], collapsed: number[], total: number, reverse: boolean): number[] {
    const result: number[] = [];
    if (collapsed.length === 0) {
      for (let i = 0; i < total; i++) result.push(reverse ? total - 1 - i : i);
      return result;
    }
    const collapsedSet = new Set<number>(collapsed);
    for (let i = 0; i < total; i++) {
      const position = reverse ? total - 1 - i : i;
      const start = TocVolumeFold.volumeOf(volumeStarts, position);
      if (start < 0 || !collapsedSet.has(start) ||
        TocVolumeFold.headPosition(volumeStarts, start, total, reverse) === position) {
        result.push(position);
      }
    }
    return result;
  }

  /** visiblePositions 的结果里 position 所在的下标；被收起的章节落到所在卷的卷头行。 */
  static displayIndexOf(order: number[], volumeStarts: number[], collapsed: number[], position: number,
    total: number, reverse: boolean): number {
    if (order.length === 0) return 0;
    const target = TocVolumeFold.representative(volumeStarts, collapsed, position, total, reverse);
    let low = 0;
    let high = order.length - 1;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (reverse ? order[mid] > target : order[mid] < target) low = mid + 1;
      else high = mid;
    }
    return low;
  }

  /** 去掉已经不是卷首的位置（目录刷新后卷可能变了）。 */
  static sanitize(volumeStarts: number[], collapsed: number[]): number[] {
    if (collapsed.length === 0) return collapsed;
    const starts = new Set<number>(volumeStarts);
    return collapsed.filter((start: number) => starts.has(start));
  }

  private static memory: Map<string, number[]> = new Map<string, number[]>();

  /** 阅读页目录面板每次打开都重新创建，收起状态按书记在进程内，下次打开沿用。 */
  static remember(key: string, collapsed: number[]): void {
    if (!key) return;
    if (collapsed.length === 0) TocVolumeFold.memory.delete(key);
    else TocVolumeFold.memory.set(key, collapsed.slice());
  }

  static recall(key: string): number[] {
    const saved = key ? TocVolumeFold.memory.get(key) : undefined;
    return saved ? saved.slice() : [];
  }
}
