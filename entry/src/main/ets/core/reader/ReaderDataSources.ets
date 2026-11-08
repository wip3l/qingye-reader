/** 滚动阅读列表里的一项：一段正文/一张图片，或两章之间的分隔。 */
export class ReaderScrollItem {
  static readonly PAGE: number = 0;
  static readonly SEPARATOR: number = 1;
  kind: number = ReaderScrollItem.PAGE;
  /** 正文项所属章节；分隔项为它后面那一章。 */
  chapterIndex: number = 0;
  /** 章内序号（与该章分页结果的下标一致）；分隔项为 -1。 */
  pageIndex: number = -1;
  text: string = '';
  /** 分隔项：后面那一章还没装进列表（加载中）。 */
  pending: boolean = false;
  /** 分隔项：后面那一章加载失败。 */
  failed: boolean = false;
  key: string = '';

  isPage(): boolean {
    return this.kind === ReaderScrollItem.PAGE;
  }
}

/** 一章的滚动分块及其在章节源文本里的位置，与该章的分页结果一一对应。 */
export class ReaderScrollSegment {
  chapterIndex: number = 0;
  pages: string[] = [];
  starts: number[] = [];
  ends: number[] = [];
  source: string = '';
}

/**
 * 滚动阅读（条漫与小说滚动模式）的列表数据：按章节顺序排列的若干章，相邻两章之间一个分隔项，
 * 最后一章后面再挂一个指向下一章的分隔项（下一章加载期间显示提示）。
 * 阅读页仍只把一章当作“当前章”，列表序号与章内序号通过 offsetOf() 换算。
 * 增删都按区间通知，配合 List.maintainVisibleContentPosition 在可见区上方插入/删除时画面不动。
 */
export class ReaderContinuousDataSource implements IDataSource {
  private items: ReaderScrollItem[] = [];
  private segments: ReaderScrollSegment[] = [];
  private listeners: DataChangeListener[] = [];
  /** 整体重建的次数；异步装入相邻章节时用它判断列表是否已被替换。 */
  private generationValue: number = 0;

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ReaderScrollItem {
    return this.items[index] || new ReaderScrollItem();
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  generation(): number {
    return this.generationValue;
  }

  itemAt(index: number): ReaderScrollItem | null {
    return index >= 0 && index < this.items.length ? this.items[index] : null;
  }

  segment(chapterIndex: number): ReaderScrollSegment | null {
    for (const segment of this.segments) {
      if (segment.chapterIndex === chapterIndex) return segment;
    }
    return null;
  }

  firstChapter(): number {
    return this.segments.length > 0 ? this.segments[0].chapterIndex : -1;
  }

  lastChapter(): number {
    return this.segments.length > 0 ? this.segments[this.segments.length - 1].chapterIndex : -1;
  }

  /** 该章第 0 项的列表序号；不在列表里时为 -1。 */
  offsetOf(chapterIndex: number): number {
    let offset = 0;
    for (let i = 0; i < this.segments.length; i++) {
      if (i > 0) offset++;
      if (this.segments[i].chapterIndex === chapterIndex) return offset;
      offset += this.segments[i].pages.length;
    }
    return -1;
  }

  /** 末尾分隔项指向的章节；没有时为 -1。 */
  trailingChapter(): number {
    const last = this.items.length > 0 ? this.items[this.items.length - 1] : null;
    return last && !last.isPage() ? last.chapterIndex : -1;
  }

  reset(): void {
    this.segments = [];
    this.rebuild(true);
  }

  /**
   * 发布当前章。列表里已有这一章且分块相同：不动；只是在原有分块后追加：按区间插入；
   * 其他情况（不在列表里、分块被重排）整体换成只含这一章。返回是否整体重建。
   * relayout：已挂载项的排版作废（主题/日夜切换只改颜色，分块文字不变），必须整体重建才会换掉旧节点。
   */
  setCurrent(segment: ReaderScrollSegment, nextChapter: number, relayout: boolean = false): boolean {
    const existing = this.segment(segment.chapterIndex);
    if (relayout) {
      this.segments = [this.copySegment(segment)];
      this.rebuild(true, nextChapter);
      return true;
    }
    if (existing && this.samePages(existing.pages, segment.pages)) {
      existing.starts = segment.starts;
      existing.ends = segment.ends;
      existing.source = segment.source;
      return false;
    }
    if (existing && this.isPrefix(existing.pages, segment.pages)) {
      const insertAt = this.offsetOf(segment.chapterIndex) + existing.pages.length;
      const added = segment.pages.length - existing.pages.length;
      existing.pages = [...segment.pages];
      existing.starts = segment.starts;
      existing.ends = segment.ends;
      existing.source = segment.source;
      this.rebuild(false);
      this.notifyAdd(insertAt, added);
      return false;
    }
    this.segments = [this.copySegment(segment)];
    this.rebuild(true, nextChapter);
    return true;
  }

  /** 在末尾接上下一章；chapterIndex 必须紧接当前最后一章。 */
  append(segment: ReaderScrollSegment, nextChapter: number): boolean {
    if (this.segments.length === 0 || segment.chapterIndex !== this.lastChapter() + 1) return false;
    const trailingIndex = this.items.length - 1;
    const hadTrailing = this.trailingChapter() === segment.chapterIndex;
    const oldCount = this.items.length;
    this.segments.push(this.copySegment(segment));
    this.rebuild(false, nextChapter);
    if (hadTrailing) {
      this.notifyChange(trailingIndex);
      this.notifyAdd(oldCount, this.items.length - oldCount);
    } else {
      this.notifyAdd(oldCount, this.items.length - oldCount);
    }
    return true;
  }

  /** 在开头接上上一章（连同它和原第一章之间的分隔项）。 */
  prepend(segment: ReaderScrollSegment): boolean {
    if (this.segments.length === 0 || segment.chapterIndex !== this.firstChapter() - 1) return false;
    const nextChapter = this.trailingChapter();
    this.segments.unshift(this.copySegment(segment));
    this.rebuild(false, nextChapter);
    this.notifyAdd(0, segment.pages.length + 1);
    return true;
  }

  /** 去掉 [keepFirst, keepLast] 以外的章节（不会去掉 keep 区间内的章）。 */
  trim(keepFirst: number, keepLast: number): void {
    const nextChapter = this.trailingChapter();
    while (this.segments.length > 1 && this.segments[0].chapterIndex < keepFirst) {
      const count = this.segments[0].pages.length + 1;
      this.segments.shift();
      this.rebuild(false, nextChapter);
      this.notifyDelete(0, count);
    }
    while (this.segments.length > 1 && this.segments[this.segments.length - 1].chapterIndex > keepLast) {
      const removed = this.segments[this.segments.length - 1];
      const start = this.offsetOf(removed.chapterIndex) - 1;
      const oldCount = this.items.length;
      this.segments.pop();
      this.rebuild(false, removed.chapterIndex);
      // 被去掉的章前面的分隔项留下来，改作末尾分隔项。
      this.notifyChange(start);
      this.notifyDelete(start + 1, oldCount - start - 1);
    }
  }

  /** 末尾分隔项的加载状态。 */
  setTrailingState(pending: boolean, failed: boolean): void {
    const index = this.items.length - 1;
    const last = this.itemAt(index);
    if (!last || last.isPage() || (last.pending === pending && last.failed === failed)) return;
    const next = this.separator(last.chapterIndex, pending, failed);
    this.items[index] = next;
    this.notifyChange(index);
  }

  private samePages(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  private isPrefix(prefix: string[], full: string[]): boolean {
    if (prefix.length >= full.length) return false;
    for (let i = 0; i < prefix.length; i++) if (prefix[i] !== full[i]) return false;
    return true;
  }

  private copySegment(segment: ReaderScrollSegment): ReaderScrollSegment {
    const copy = new ReaderScrollSegment();
    copy.chapterIndex = segment.chapterIndex;
    copy.pages = [...segment.pages];
    copy.starts = segment.starts;
    copy.ends = segment.ends;
    copy.source = segment.source;
    return copy;
  }

  private static hash(text: string): number {
    let hash = 0;
    for (let i = 0; i < text.length; i++) hash = ((hash * 31) + text.charCodeAt(i)) & 0x7fffffff;
    return hash;
  }

  private separator(chapterIndex: number, pending: boolean, failed: boolean): ReaderScrollItem {
    const item = new ReaderScrollItem();
    item.kind = ReaderScrollItem.SEPARATOR;
    item.chapterIndex = chapterIndex;
    item.pending = pending;
    item.failed = failed;
    item.key = `sep_${chapterIndex}_${pending ? 'p' : ''}${failed ? 'f' : ''}`;
    return item;
  }

  /** 按 segments 重建 items。trailing 为末尾分隔项指向的章节，-1 表示保留原来的设置。 */
  private rebuild(reload: boolean, trailing: number = -2): void {
    const previousTrailing = this.trailingChapter();
    const previousLast = this.items.length > 0 ? this.items[this.items.length - 1] : null;
    const items: ReaderScrollItem[] = [];
    for (let s = 0; s < this.segments.length; s++) {
      const segment = this.segments[s];
      if (s > 0) items.push(this.separator(segment.chapterIndex, false, false));
      for (let p = 0; p < segment.pages.length; p++) {
        const item = new ReaderScrollItem();
        item.chapterIndex = segment.chapterIndex;
        item.pageIndex = p;
        item.text = segment.pages[p];
        item.key = `page_${segment.chapterIndex}_${p}_${ReaderContinuousDataSource.hash(segment.pages[p])}`;
        items.push(item);
      }
    }
    const nextChapter = trailing === -2 ? previousTrailing : trailing;
    if (this.segments.length > 0 && nextChapter === this.lastChapter() + 1) {
      const keepState = previousLast && !previousLast.isPage() && previousLast.chapterIndex === nextChapter;
      items.push(this.separator(nextChapter, keepState ? previousLast!.pending : true,
        keepState ? previousLast!.failed : false));
    }
    this.items = items;
    if (reload) {
      this.generationValue++;
      // 同一个数据源只能用 onDatasetChange 一套接口：与 onDataReloaded 等旧接口混用时，
      // LazyForEach 会在下一次通知时抛错（加载正文、刷新本章都会因此失败）。
      for (const listener of this.listeners) listener.onDatasetChange([{ type: DataOperationType.RELOAD }]);
    }
  }

  private notifyAdd(index: number, count: number): void {
    if (count <= 0) return;
    for (const listener of this.listeners) {
      listener.onDatasetChange([{ type: DataOperationType.ADD, index: index, count: count }]);
    }
  }

  private notifyDelete(index: number, count: number): void {
    if (count <= 0) return;
    for (const listener of this.listeners) {
      listener.onDatasetChange([{ type: DataOperationType.DELETE, index: index, count: count }]);
    }
  }

  private notifyChange(index: number): void {
    if (index < 0 || index >= this.items.length) return;
    for (const listener of this.listeners) {
      listener.onDatasetChange([{ type: DataOperationType.CHANGE, index: index }]);
    }
  }
}
