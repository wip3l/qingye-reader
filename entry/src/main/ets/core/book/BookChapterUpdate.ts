import { BookChapter } from '@legado/sourceengine';

export class BookChapterUpdate {
  /** A first catalog, a renamed last chapter, or a shortened catalog is not an update. */
  static hasNewChapters(previous: BookChapter[], next: BookChapter[]): boolean {
    if (previous.length === 0 || next.length < previous.length) return false;
    const oldLast = previous[previous.length - 1];
    const newLast = next[next.length - 1];
    if (oldLast.url && oldLast.url === newLast.url) return false;
    if (oldLast.title.trim() === newLast.title.trim()) return false;
    if (next.length > previous.length) return true;
    // Some sources keep a fixed-size rolling catalog. Require the old tail before the new tail.
    return !!oldLast.url && next.slice(0, -1).some((chapter: BookChapter): boolean =>
      chapter.url === oldLast.url);
  }

  /**
   * 两份目录在 book_chapters 表里存的每一列都相同时为 true。目录刷新据此跳过整表删除重插，
   * 也就保住了按目录算好的分页缓存；任何一列不同（含坏链接修复）都照常重写。
   */
  static sameStoredCatalog(previous: BookChapter[], next: BookChapter[]): boolean {
    if (previous.length !== next.length || previous.length === 0) return false;
    for (let i = 0; i < next.length; i++) {
      const a = previous[i];
      const b = next[i];
      if ((a.url || '') !== (b.url || '') || (a.title || '') !== (b.title || '') ||
        (a.bookUrl || '') !== (b.bookUrl || '') || (a.index || 0) !== (b.index || 0) ||
        !!a.isVip !== !!b.isVip || !!a.isPay !== !!b.isPay ||
        (a.resourceUrl || '') !== (b.resourceUrl || '') || (a.tag || '') !== (b.tag || '') ||
        (a.start || 0) !== (b.start || 0) || (a.end || 0) !== (b.end || 0) ||
        (a.variable || '') !== (b.variable || '')) {
        return false;
      }
    }
    return true;
  }
}
