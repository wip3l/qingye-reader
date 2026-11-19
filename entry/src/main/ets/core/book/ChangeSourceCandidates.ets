import { Book, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { BookIdentity } from '../../utils/BookIdentity';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';

/** 换源候选的基本筛选，换源面板与批量换源共用。 */
export class ChangeSourceCandidates {
  /**
   * 去掉导航项、重复项、其他类型的结果和正在读的这一本；同一书源（尤其聚合书源的其他子站）的同名书照常保留。
   * aliases 是同书源下指向当前这本的其他地址（换源时被详情改写前的搜索地址）。
   */
  static filter(results: SearchBook[], target: Book, aliases: string[]): SearchBook[] {
    const filtered: SearchBook[] = [];
    const seen = new Set<string>();
    // 历史结果可能是旧版本不分类型时存下的，这里同样按原书类型过滤。
    const category = BookTypeSupport.mediaCategoryOf(target);
    // 按书籍身份比对，聚合书源轮换接口主机后也认得出是同一本。
    const currentKey = BookIdentity.keyOfUrl(target.bookUrl, target.origin);
    for (const result of results) {
      if (!result.bookUrl || SearchBookShelfHelper.isNavigationResult(result) ||
        (result.origin === target.origin && (result.bookUrl === target.bookUrl ||
          aliases.includes(result.bookUrl) ||
          BookIdentity.keyOfSearchBook(result) === currentKey)) ||
        BookTypeSupport.mediaCategoryOf(result) !== category) continue;
      const key = `${result.origin || ''}\n${result.bookUrl}`;
      if (seen.has(key)) continue;
      seen.add(key);
      filtered.push(result);
    }
    return filtered;
  }
}
