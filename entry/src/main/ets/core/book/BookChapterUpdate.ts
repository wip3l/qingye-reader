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
}
