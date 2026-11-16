/**
 * 自动滚动“百叶窗”方式的逐行节奏。纯计算，不碰绘制，坐标都是栏内像素。
 *
 * - 画面不动，一条阅读线按速度往下走。正文按行切成叶片（band，[top, bottom]），一行整行被阅读线越过才翻走，
 *   露出下一页同一高度的内容。
 * - 读完本页之前只按本页叶片的下边落位，本页全部翻走后再按下一页叶片落位：下一页的叶片要等它占的高度完全
 *   让出来才翻出，两页的字永不重叠，交界处最多空出不到一行。
 * - 叶片先翻走、稍后再翻出，每片各记各的时刻；暂停、掉帧都不会让动画跳步。
 * - 双页时一栏读完再读下一栏（ReaderBlindsSpread）。
 */
export class ReaderBlindsMotion {
  static readonly OUT_MS: number = 180;
  static readonly IN_DELAY_MS: number = 120;
  static readonly IN_MS: number = 200;
  /** 两个区间重叠超过这么多才算同一片叶子；同段上下相邻的两行正好首尾相接，仍是两片。 */
  private static readonly MERGE_OVERLAP_PX: number = 0.5;

  private current: number[][] = [];
  /** null 表示下一页还不知道（跨章还没排好），这时不往下走。空数组表示下一页这一栏本来就是空的。 */
  private next: number[][] | null = null;
  private cursor: number = 0;
  private hidden: number = 0;
  private shown: number = 0;
  private hiddenAt: number[] = [];
  private shownAt: number[] = [];
  private guideFrom: number = 0;
  private guideTo: number = 0;
  private guideAt: number = -1;

  /** 把各元素的上下边合并成按顶边排序、互不重叠的叶片。 */
  static mergeBands(intervals: number[][]): number[][] {
    const sorted = intervals.filter((item: number[]): boolean => item.length >= 2 && Number.isFinite(item[0]) &&
      Number.isFinite(item[1]) && item[1] > item[0])
      .map((item: number[]): number[] => [item[0], item[1]])
      .sort((a: number[], b: number[]): number => a[0] - b[0] || a[1] - b[1]);
    const merged: number[][] = [];
    for (const item of sorted) {
      const last = merged.length > 0 ? merged[merged.length - 1] : null;
      if (last && item[0] < last[1] - ReaderBlindsMotion.MERGE_OVERLAP_PX) {
        last[1] = Math.max(last[1], item[1]);
      } else {
        merged.push(item);
      }
    }
    return merged;
  }

  reset(current: number[][], next: number[][] | null): void {
    this.current = current;
    this.next = next;
    this.cursor = 0;
    this.hidden = 0;
    this.shown = 0;
    this.hiddenAt = [];
    this.shownAt = [];
    this.guideFrom = 0;
    this.guideTo = 0;
    this.guideAt = -1;
  }

  setNext(next: number[][]): void {
    this.next = next;
  }

  hasNext(): boolean {
    return this.next !== null;
  }

  currentBands(): number[][] {
    return this.current;
  }

  nextBands(): number[][] {
    return this.next || [];
  }

  position(): number {
    return this.cursor;
  }

  /** 阅读线走完本栏的位置：两页里更靠下的那片叶子的下边。 */
  endY(): number {
    const currentEnd = this.current.length > 0 ? this.current[this.current.length - 1][1] : 0;
    const next = this.next || [];
    const nextEnd = next.length > 0 ? next[next.length - 1][1] : 0;
    return Math.max(currentEnd, nextEnd);
  }

  reachedEnd(): boolean {
    return this.next !== null && this.cursor >= this.endY();
  }

  /** 往下走 delta，返回没用完的部分（本栏已到底时交给下一栏）。下一页未知时原地不动。 */
  advance(delta: number, now: number): number {
    if (this.next === null || !(delta > 0)) return 0;
    const end = this.endY();
    const target = this.cursor + delta;
    this.cursor = Math.min(end, target);
    this.update(now);
    return Math.max(0, target - end);
  }

  /** 阅读线落到的叶片边界：它以上是下一页，以下是本页。 */
  reveal(): number {
    let line = 0;
    for (const band of this.current) {
      if (band[1] <= this.cursor) line = band[1];
      else break;
    }
    const next = this.next || [];
    const currentDone = this.current.length === 0 || this.cursor >= this.current[this.current.length - 1][1];
    if (currentDone) {
      for (const band of next) {
        if (band[1] <= this.cursor) line = Math.max(line, band[1]);
        else break;
      }
    }
    return line;
  }

  hiddenCount(): number {
    return this.hidden;
  }

  shownCount(): number {
    return this.shown;
  }

  /** 本页第 index 片翻走的进度：0 还在，1 已经翻走。 */
  outProgress(index: number, now: number): number {
    if (index >= this.hidden) return 0;
    return ReaderBlindsMotion.progress(now - this.hiddenAt[index], 0, ReaderBlindsMotion.OUT_MS);
  }

  /** 下一页第 index 片翻出的进度：0 还没出来，1 已经立好。 */
  inProgress(index: number, now: number): number {
    if (index >= this.shown) return 0;
    return ReaderBlindsMotion.progress(now - this.shownAt[index], ReaderBlindsMotion.IN_DELAY_MS,
      ReaderBlindsMotion.IN_MS);
  }

  /** 阅读线的显示位置：跟着叶片翻动从旧边界滑到新边界。 */
  guideY(now: number): number {
    if (this.guideAt < 0) return this.guideTo;
    const t = ReaderBlindsMotion.progress(now - this.guideAt, 0, ReaderBlindsMotion.OUT_MS +
      ReaderBlindsMotion.IN_DELAY_MS);
    const eased = 1 - (1 - t) * (1 - t);
    return this.guideFrom + (this.guideTo - this.guideFrom) * eased;
  }

  animating(now: number): boolean {
    const total = ReaderBlindsMotion.IN_DELAY_MS + ReaderBlindsMotion.IN_MS;
    for (let index = 0; index < this.hidden; index++) {
      if (now - this.hiddenAt[index] < ReaderBlindsMotion.OUT_MS) return true;
    }
    for (let index = 0; index < this.shown; index++) {
      if (now - this.shownAt[index] < total) return true;
    }
    return this.guideAt >= 0 && now - this.guideAt < ReaderBlindsMotion.OUT_MS + ReaderBlindsMotion.IN_DELAY_MS;
  }

  private update(now: number): void {
    const line = this.reveal();
    let hidden = this.hidden;
    while (hidden < this.current.length && this.current[hidden][1] <= line) {
      this.hiddenAt.push(now);
      hidden++;
    }
    const next = this.next || [];
    let shown = this.shown;
    while (shown < next.length && next[shown][1] <= line) {
      this.shownAt.push(now);
      shown++;
    }
    if (hidden !== this.hidden || shown !== this.shown) {
      this.guideFrom = this.guideY(now);
      this.guideTo = line;
      this.guideAt = now;
    }
    this.hidden = hidden;
    this.shown = shown;
  }

  private static progress(elapsed: number, delay: number, duration: number): number {
    if (!(elapsed > delay)) return 0;
    return Math.min(1, (elapsed - delay) / Math.max(1, duration));
  }
}

/** 一个跨页的几栏：单页一栏，双页左右两栏，前一栏走完才走下一栏。 */
export class ReaderBlindsSpread {
  columns: ReaderBlindsMotion[] = [];

  ensureColumns(count: number): void {
    while (this.columns.length < count) this.columns.push(new ReaderBlindsMotion());
    if (this.columns.length > count) this.columns = this.columns.slice(0, count);
  }

  advance(delta: number, now: number): void {
    // 任何一栏的下一页还不知道就整体等着，免得左栏先翻走、右栏却露不出东西。
    if (!this.hasNext()) return;
    let rest = delta;
    for (const column of this.columns) {
      if (column.reachedEnd()) continue;
      rest = column.advance(rest, now);
      if (!(rest > 0)) return;
    }
  }

  hasNext(): boolean {
    return this.columns.length > 0 && this.columns.every((column: ReaderBlindsMotion): boolean => column.hasNext());
  }

  reachedEnd(): boolean {
    return this.hasNext() && this.columns.every((column: ReaderBlindsMotion): boolean => column.reachedEnd());
  }

  animating(now: number): boolean {
    return this.columns.some((column: ReaderBlindsMotion): boolean => column.animating(now));
  }
}
