import { AuthorFold, ChangeSourceAuthorMatch } from './ChangeSourceAuthorMatch';

/**
 * 批量自动换源的取舍规则。手动换源由人挑候选，这里没人把关，所以只收认得准的：
 * 作者必须对得上；原书没有作者时，候选的作者要么都没写、要么只有一种写法。
 * 候选逐个取目录验证，章节数够得着已读位置的才算数，其中取章节最多的。
 */
export class BatchSourceSwitchPolicy {
  /** 同时处理几本书。 */
  static readonly CONCURRENCY: number = 2;
  /** 每本书搜索候选的时限。 */
  static readonly SEARCH_TIMEOUT_MS: number = 20000;
  /** 每本书最多验证出几个能取到目录的候选。 */
  static readonly MAX_VERIFIED: number = 5;
  /** 每本书最多试几个候选（含取不到目录的）。 */
  static readonly MAX_ATTEMPTS: number = 8;
  /** 单个候选取详情与目录的总时限。 */
  static readonly CANDIDATE_TIMEOUT_MS: number = 30000;

  /** 能自动换过去的候选下标，保持搜索给出的先后。authors 是各候选的作者。 */
  static eligible(bookAuthor: string, authors: string[], fold: AuthorFold = null): number[] {
    const indexes: number[] = [];
    if (ChangeSourceAuthorMatch.normalize(bookAuthor, fold)) {
      authors.forEach((author: string, index: number): void => {
        if (ChangeSourceAuthorMatch.compare(bookAuthor, author, fold) === ChangeSourceAuthorMatch.SAME) {
          indexes.push(index);
        }
      });
      return indexes;
    }
    const known: string[] = [];
    authors.forEach((author: string): void => {
      const normalized = ChangeSourceAuthorMatch.normalize(author, fold);
      if (normalized && !known.includes(normalized)) known.push(normalized);
    });
    // 同名书有两位以上作者，分不清哪本才是原书。
    if (known.length > 1) return indexes;
    authors.forEach((_author: string, index: number): void => {
      indexes.push(index);
    });
    return indexes;
  }

  /** 这个候选已经不比原来的目录短，后面的不用再验证。原书没有目录数时不提前结束。 */
  static enough(chapterCount: number, oldTotal: number, readIndex: number): boolean {
    return oldTotal > 0 && chapterCount >= oldTotal && chapterCount > readIndex;
  }

  /** 在验证过的候选里挑一个：章节数要超过已读到的章序号，取最多的，并列取靠前的；都不够返回 -1。 */
  static pick(chapterCounts: number[], readIndex: number): number {
    let best = -1;
    chapterCounts.forEach((count: number, index: number): void => {
      if (count <= Math.max(0, readIndex)) return;
      if (best < 0 || count > chapterCounts[best]) best = index;
    });
    return best;
  }
}
