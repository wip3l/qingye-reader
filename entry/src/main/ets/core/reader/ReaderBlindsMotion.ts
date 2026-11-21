/**
 * 自动滚动“百叶窗”方式的逐行节奏。纯计算，不碰绘制，坐标都是栏内像素。
 *
 * - 画面不动，一条阅读线按速度往下走。正文按行切成叶片（band，[top, bottom]），一行整行被阅读线越过才翻走，
 *   露出下一页同一高度的内容。
 * - 读完本页之前只按本页叶片的下边落位，本页全部翻走后再按下一页叶片落位：下一页的叶片要等它占的高度完全
 *   让出来才翻出，两页的字永不重叠，交界处最多空出不到一行。
 * - 叶片先翻走、稍后再翻出，每片各记各的时刻；暂停、掉帧都不会让动画跳步。
 * - 双页时一栏读完再读下一栏（ReaderBlindsSpread）。
 * - 手指上下拖动可以把阅读线往回挪（seek）：已翻走的叶片反向翻回本页，已翻出的下一页叶片反向收起；
 *   拖动期间阅读线贴着手指（setFollow），松手后滑回叶片边界。
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
  /** 正在反向翻回的叶片：序号 → 反向动画的起点时刻。动画放完后清掉。 */
  private restoreOutAt: Map<number, number> = new Map<number, number>();
  private restoreInAt: Map<number, number> = new Map<number, number>();
  private following: boolean = false;

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
    this.restoreOutAt.clear();
    this.restoreInAt.clear();
    this.following = false;
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

  /** 把阅读线挪到 target（可往回挪）。下一页未知时不动。 */
  seek(target: number, now: number): void {
    if (this.next === null || !Number.isFinite(target)) return;
    this.cursor = Math.max(0, Math.min(this.endY(), target));
    this.update(now);
  }

  /** 拖动期间阅读线贴着手指画；结束时从手指位置滑回叶片边界。 */
  setFollow(follow: boolean, now: number): void {
    if (follow === this.following) return;
    if (!follow) {
      this.guideFrom = this.cursor;
      this.guideTo = this.reveal();
      this.guideAt = now;
    }
    this.following = follow;
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

  /** 本页第 index 片翻走的进度：0 还在，1 已经翻走。反向翻回时从 1 回到 0（先等下一页那片收起）。 */
  outProgress(index: number, now: number): number {
    if (index < this.hidden) {
      return ReaderBlindsMotion.progress(now - this.hiddenAt[index], 0, ReaderBlindsMotion.OUT_MS);
    }
    const at = this.restoreOutAt.get(index);
    if (at === undefined) return 0;
    return 1 - ReaderBlindsMotion.progress(now - at, ReaderBlindsMotion.IN_DELAY_MS, ReaderBlindsMotion.OUT_MS);
  }

  /** 下一页第 index 片翻出的进度：0 还没出来，1 已经立好。反向收起时从 1 回到 0。 */
  inProgress(index: number, now: number): number {
    if (index < this.shown) {
      return ReaderBlindsMotion.progress(now - this.shownAt[index], ReaderBlindsMotion.IN_DELAY_MS,
        ReaderBlindsMotion.IN_MS);
    }
    const at = this.restoreInAt.get(index);
    if (at === undefined) return 0;
    return 1 - ReaderBlindsMotion.progress(now - at, 0, ReaderBlindsMotion.IN_MS);
  }

  /** 本页从这片起往下都是原样（没翻走也不在翻回途中），可以整块画。 */
  outExtent(): number {
    let extent = this.hidden;
    for (const index of this.restoreOutAt.keys()) extent = Math.max(extent, index + 1);
    return extent;
  }

  /** 下一页要逐片画到这片之前（含正在收起的叶片）。 */
  inExtent(): number {
    let extent = this.shown;
    for (const index of this.restoreInAt.keys()) extent = Math.max(extent, index + 1);
    return extent;
  }

  /** 阅读线的显示位置：跟着叶片翻动从旧边界滑到新边界。 */
  guideY(now: number): number {
    if (this.following) return this.cursor;
    if (this.guideAt < 0) return this.guideTo;
    const t = ReaderBlindsMotion.progress(now - this.guideAt, 0, ReaderBlindsMotion.OUT_MS +
      ReaderBlindsMotion.IN_DELAY_MS);
    const eased = 1 - (1 - t) * (1 - t);
    return this.guideFrom + (this.guideTo - this.guideFrom) * eased;
  }

  animating(now: number): boolean {
    this.pruneRestores(now);
    if (this.restoreOutAt.size > 0 || this.restoreInAt.size > 0) return true;
    const total = ReaderBlindsMotion.IN_DELAY_MS + ReaderBlindsMotion.IN_MS;
    for (let index = 0; index < this.hidden; index++) {
      if (now - this.hiddenAt[index] < ReaderBlindsMotion.OUT_MS) return true;
    }
    for (let index = 0; index < this.shown; index++) {
      if (now - this.shownAt[index] < total) return true;
    }
    return this.guideAt >= 0 && now - this.guideAt < ReaderBlindsMotion.OUT_MS + ReaderBlindsMotion.IN_DELAY_MS;
  }

  /**
   * 按阅读线重算翻走/翻出的叶片数。往前越过的叶片开始翻，往回退出的叶片反向翻回；
   * 翻到一半掉头时从当前进度接着反向，不跳帧。
   */
  private update(now: number): void {
    const line = this.reveal();
    let hidden = 0;
    while (hidden < this.current.length && this.current[hidden][1] <= line) hidden++;
    const next = this.next || [];
    let shown = 0;
    while (shown < next.length && next[shown][1] <= line) shown++;
    const outMs = ReaderBlindsMotion.OUT_MS;
    const inMs = ReaderBlindsMotion.IN_MS;
    const delay = ReaderBlindsMotion.IN_DELAY_MS;
    if (hidden > this.hidden) {
      for (let index = this.hidden; index < hidden; index++) {
        const progress = this.outProgress(index, now);
        this.restoreOutAt.delete(index);
        this.hiddenAt.push(now - progress * outMs);
      }
    } else if (hidden < this.hidden) {
      for (let index = hidden; index < this.hidden; index++) {
        const progress = this.outProgress(index, now);
        if (progress > 0) this.restoreOutAt.set(index, progress >= 1 ? now : now - delay - (1 - progress) * outMs);
      }
      this.hiddenAt = this.hiddenAt.slice(0, hidden);
    }
    if (shown > this.shown) {
      for (let index = this.shown; index < shown; index++) {
        const progress = this.inProgress(index, now);
        this.restoreInAt.delete(index);
        this.shownAt.push(progress > 0 ? now - delay - progress * inMs : now);
      }
    } else if (shown < this.shown) {
      for (let index = shown; index < this.shown; index++) {
        const progress = this.inProgress(index, now);
        if (progress > 0) this.restoreInAt.set(index, now - (1 - progress) * inMs);
      }
      this.shownAt = this.shownAt.slice(0, shown);
    }
    this.pruneRestores(now);
    if (hidden !== this.hidden || shown !== this.shown) {
      this.guideFrom = this.guideY(now);
      this.guideTo = line;
      this.guideAt = now;
    }
    this.hidden = hidden;
    this.shown = shown;
  }

  private pruneRestores(now: number): void {
    for (const entry of Array.from(this.restoreOutAt.entries())) {
      if (now - entry[1] >= ReaderBlindsMotion.IN_DELAY_MS + ReaderBlindsMotion.OUT_MS) {
        this.restoreOutAt.delete(entry[0]);
      }
    }
    for (const entry of Array.from(this.restoreInAt.entries())) {
      if (now - entry[1] >= ReaderBlindsMotion.IN_MS) this.restoreInAt.delete(entry[0]);
    }
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

  /**
   * 手指拖动：delta > 0 往下走（同 advance），< 0 往回挪，从已经走过的最后一栏往前退。
   */
  shift(delta: number, now: number): void {
    if (!this.hasNext() || !Number.isFinite(delta)) return;
    if (delta > 0) {
      this.advance(delta, now);
      return;
    }
    let rest = -delta;
    for (let index = this.columns.length - 1; index >= 0 && rest > 0; index--) {
      const column = this.columns[index];
      const position = column.position();
      if (position <= 0) continue;
      const take = Math.min(rest, position);
      column.seek(position - take, now);
      rest -= take;
    }
  }

  setFollow(follow: boolean, now: number): void {
    for (const column of this.columns) column.setFollow(follow, now);
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
