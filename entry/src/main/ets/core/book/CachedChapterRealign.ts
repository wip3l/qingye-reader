/** 已缓存正文的一行，只取定位用的列，不读正文。 */
export interface CachedChapterRow {
  index: number;
  url: string;
  title: string;
}

/** 目录里的一章，只用到定位用的字段。 */
export interface CachedChapterTarget {
  index: number;
  url: string;
  title: string;
}

/** 一行缓存正文在新目录里的位置；from 与 to 相同时只可能需要改记下的地址和章名。 */
export interface CachedChapterAssignment {
  from: number;
  to: number;
  url: string;
  title: string;
  relabel: boolean;
}

/** 一条书签在 (书, 章, 页) 唯一约束里的位置。 */
export interface ChapterBookmarkSlot {
  id: number;
  index: number;
  page: number;
}

export class CachedChapterRealignPlan {
  assignments: CachedChapterAssignment[] = [];
  drops: number[] = [];

  /** 每行都留在原序号、地址章名也没变：不用写库。 */
  isUnchanged(): boolean {
    return this.drops.length === 0 &&
      this.assignments.every((item: CachedChapterAssignment): boolean => item.from === item.to && !item.relabel);
  }
}

/**
 * 已缓存正文按 (bookUrl, chapterIndex) 存。目录换新后前面多了或少了几章，序号整体挪动，
 * 不跟着挪的话第 N 章会读到旧目录第 N 章的正文。这里按章节地址找每行在新目录里的位置，
 * 地址对不上（站点换了地址格式）再看章名；都对不上的行删掉，下次阅读重新联网取。
 */
export class CachedChapterRealign {
  private static norm(text: string | undefined): string {
    return (text || '').trim();
  }

  /** 读缓存时核对：记下的地址或章名与目录里这一章对得上（任一边没有地址时只看能比的）。 */
  static matches(rowUrl: string, rowTitle: string, chapter: CachedChapterTarget): boolean {
    const url = CachedChapterRealign.norm(rowUrl);
    const chapterUrl = CachedChapterRealign.norm(chapter.url);
    if (!url || !chapterUrl || url === chapterUrl) return true;
    const title = CachedChapterRealign.norm(rowTitle);
    return !!title && title === CachedChapterRealign.norm(chapter.title);
  }

  /**
   * 书签、划线只记了章名。刷新前的目录里这一章章名与记下的一致时借它的地址，按地址对位更准；
   * 不一致（记录本来就过期、旧目录是临时通用目录）只按章名对。
   */
  static markRows(titles: Map<number, string>, previous: CachedChapterTarget[]): CachedChapterRow[] {
    const byIndex: Map<number, CachedChapterTarget> = new Map();
    for (const chapter of previous) byIndex.set(chapter.index, chapter);
    const rows: CachedChapterRow[] = [];
    titles.forEach((title: string, index: number): void => {
      const old = byIndex.get(index);
      const url = old && CachedChapterRealign.norm(old.title) === CachedChapterRealign.norm(title) ? old.url || '' : '';
      rows.push({ index: index, url: url, title: title });
    });
    return rows;
  }

  /**
   * 书签有 (书, 章, 页) 唯一约束：挪过去会撞上留在原处的书签时，这条不挪；因此连锁撞上的也一并留下。
   * indexMap 是旧序号 → 新序号（只含要挪的）。返回 id → 新序号，只含真要挪的书签。
   */
  static bookmarkMoves(slots: ChapterBookmarkSlot[], indexMap: Map<number, number>): Map<number, number> {
    const target: Map<number, number> = new Map();
    for (const slot of slots) {
      const next = indexMap.get(slot.index);
      target.set(slot.id, next === undefined ? slot.index : next);
    }
    let changed = true;
    while (changed) {
      changed = false;
      const seen: Map<string, ChapterBookmarkSlot[]> = new Map();
      for (const slot of slots) {
        const key = `${target.get(slot.id)}|${slot.page}`;
        const list = seen.get(key);
        if (list) list.push(slot); else seen.set(key, [slot]);
      }
      seen.forEach((list: ChapterBookmarkSlot[]): void => {
        if (list.length < 2) return;
        for (const slot of list) {
          if (target.get(slot.id) === slot.index) continue;
          target.set(slot.id, slot.index);
          changed = true;
        }
      });
    }
    const moves: Map<number, number> = new Map();
    for (const slot of slots) {
      const next = target.get(slot.id) as number;
      if (next !== slot.index) moves.set(slot.id, next);
    }
    return moves;
  }

  static plan(rows: CachedChapterRow[], chapters: CachedChapterTarget[]): CachedChapterRealignPlan {
    const plan = new CachedChapterRealignPlan();
    const norm = CachedChapterRealign.norm;
    const byIndex: Map<number, CachedChapterTarget> = new Map();
    const byUrl: Map<string, number[]> = new Map();
    const byTitle: Map<string, number[]> = new Map();
    for (const chapter of chapters) {
      byIndex.set(chapter.index, chapter);
      const url = norm(chapter.url);
      if (url) {
        const list = byUrl.get(url);
        if (list) list.push(chapter.index); else byUrl.set(url, [chapter.index]);
      }
      const title = norm(chapter.title);
      if (title) {
        const list = byTitle.get(title);
        if (list) list.push(chapter.index); else byTitle.set(title, [chapter.index]);
      }
    }
    const used: Set<number> = new Set();
    const assigned: Set<CachedChapterRow> = new Set();
    const assign = (row: CachedChapterRow, to: number): void => {
      const target = byIndex.get(to) as CachedChapterTarget;
      used.add(to);
      assigned.add(row);
      plan.assignments.push({
        from: row.index,
        to: to,
        url: target.url || '',
        title: target.title || '',
        relabel: (row.url || '') !== (target.url || '') || (row.title || '') !== (target.title || '')
      });
    };
    const sorted = rows.slice().sort((a: CachedChapterRow, b: CachedChapterRow): number => a.index - b.index);

    // 1. 原序号上还是同一个地址：最常见的“目录没挪”，先占住，免得被别的行抢走。
    for (const row of sorted) {
      const target = byIndex.get(row.index);
      const url = norm(row.url);
      if (target && url && url === norm(target.url)) assign(row, row.index);
    }
    // 2. 地址在新目录别处：挪过去。地址重复时先挑章名相同的，再挑离原序号最近的。
    for (const row of sorted) {
      if (assigned.has(row)) continue;
      const url = norm(row.url);
      const candidates = (url ? byUrl.get(url) || [] : []).filter((index: number): boolean => !used.has(index));
      if (candidates.length === 0) continue;
      const title = norm(row.title);
      const sameTitle = candidates.filter((index: number): boolean =>
        !!title && norm(byIndex.get(index)?.title) === title);
      const pool = sameTitle.length > 0 ? sameTitle : candidates;
      let best = pool[0];
      for (const index of pool) {
        if (Math.abs(index - row.index) < Math.abs(best - row.index)) best = index;
      }
      assign(row, best);
    }
    // 3. 地址在新目录里找不到（站点换了地址格式、地址带时效参数）：原序号上章名相同就留着。
    for (const row of sorted) {
      if (assigned.has(row)) continue;
      const target = byIndex.get(row.index);
      const title = norm(row.title);
      if (target && !used.has(row.index) && title && title === norm(target.title) &&
        !byUrl.has(norm(row.url))) {
        assign(row, row.index);
      }
    }
    // 4. 章名在新目录里只出现一次、剩下的行里也只有这一行叫这个名字：按章名挪过去。
    const remainingTitles: Map<string, number> = new Map();
    for (const row of sorted) {
      if (assigned.has(row)) continue;
      const title = norm(row.title);
      if (title) remainingTitles.set(title, (remainingTitles.get(title) || 0) + 1);
    }
    for (const row of sorted) {
      if (assigned.has(row)) continue;
      const title = norm(row.title);
      const candidates = title ? byTitle.get(title) || [] : [];
      if (candidates.length === 1 && remainingTitles.get(title) === 1 && !used.has(candidates[0]) &&
        !byUrl.has(norm(row.url))) {
        assign(row, candidates[0]);
      } else {
        plan.drops.push(row.index);
      }
    }
    return plan;
  }
}
