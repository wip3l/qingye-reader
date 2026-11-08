import { SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { SearchChineseScriptRuntime } from '../core/book/SearchChineseScriptRuntime';

export class SearchResultGroupSnapshot {
  token: string = '';
  title: string = '';
  books: SearchBook[] = [];
}

/**
 * Search aggregation is presentation-only. Raw SearchBook results stay intact so opening a group
 * can still select the exact source result, including its URL and runtime variables.
 */
export class SearchResultAggregationStore {
  private static readonly MAX_SNAPSHOTS: number = 12;
  private static serial: number = 0;
  private static snapshots: Map<string, SearchResultGroupSnapshot> = new Map();
  private static order: string[] = [];
  /** 最近一次聚合里每组繁体书名的条数（简繁同搜开着时才统计），结果卡片写“含繁体 N 个”。 */
  private static traditionalCounts: Map<string, number> = new Map();

  static aggregate(books: SearchBook[]): SearchBook[] {
    const groups: Map<string, SearchBook[]> = new Map();
    const order: string[] = [];
    for (const book of books) {
      const key = SearchResultAggregationStore.keyOf(book);
      const members = groups.get(key);
      if (members) {
        members.push(book);
      } else {
        groups.set(key, [book]);
        order.push(key);
      }
    }
    const result: SearchBook[] = [];
    const script = SearchChineseScriptRuntime.ready();
    SearchResultAggregationStore.traditionalCounts = new Map();
    for (const key of order) {
      const members = groups.get(key) || [];
      if (members.length === 0) continue;
      // 简繁同名合成一组时，代表条目优先取简体书名的那条。
      let lead = members[0];
      if (script && members.length > 1) {
        let traditional = 0;
        let simplified: SearchBook | null = null;
        for (const member of members) {
          if (script.isTraditional(member.name || '')) traditional++;
          else if (!simplified) simplified = member;
        }
        if (simplified) lead = simplified;
        if (traditional > 0) SearchResultAggregationStore.traditionalCounts.set(key, traditional);
      }
      const representative = SearchResultAggregationStore.cloneBook(lead);
      representative.aggregationKey = key;
      representative.aggregationCount = members.length;
      result.push(representative);
    }
    return result;
  }

  static traditionalCount(aggregationKey: string): number {
    return SearchResultAggregationStore.traditionalCounts.get(aggregationKey) || 0;
  }

  static members(books: SearchBook[], aggregationKey: string): SearchBook[] {
    if (!aggregationKey) return [];
    return books.filter((book: SearchBook): boolean =>
      SearchResultAggregationStore.keyOf(book) === aggregationKey);
  }

  static publish(title: string, books: SearchBook[]): string {
    const token = `search_group_${Date.now()}_${++SearchResultAggregationStore.serial}`;
    const snapshot = new SearchResultGroupSnapshot();
    snapshot.token = token;
    snapshot.title = title || books[0]?.name || '同名书籍';
    snapshot.books = books.map((book: SearchBook): SearchBook => SearchResultAggregationStore.cloneBook(book));
    SearchResultAggregationStore.snapshots.set(token, snapshot);
    SearchResultAggregationStore.order.push(token);
    while (SearchResultAggregationStore.order.length > SearchResultAggregationStore.MAX_SNAPSHOTS) {
      const removed = SearchResultAggregationStore.order.shift() || '';
      if (removed) SearchResultAggregationStore.snapshots.delete(removed);
    }
    return token;
  }

  static get(token: string): SearchResultGroupSnapshot | null {
    return SearchResultAggregationStore.snapshots.get(token) || null;
  }

  static keyOf(book: SearchBook): string {
    const title = SearchResultAggregationStore.normalizeTitle(book.name);
    // A novel, its comic and its audiobook share a title but are different things to open, so
    // they never fold into one group.
    if (title) return `title:${BookTypeSupport.mediaCategoryOf(book)}:${title}`;
    return `item:${book.origin || ''}::${book.bookUrl || ''}`;
  }

  /** `category` is one of BookTypeSupport.MEDIA_CATEGORIES; anything else keeps every result. */
  static filterByCategory(books: SearchBook[], category: string): SearchBook[] {
    if (!BookTypeSupport.MEDIA_CATEGORIES.includes(category)) return books;
    return books.filter((book: SearchBook): boolean => BookTypeSupport.mediaCategoryOf(book) === category);
  }

  static countByCategory(books: SearchBook[]): Map<string, number> {
    const counts: Map<string, number> = new Map();
    for (const book of books) {
      const category = BookTypeSupport.mediaCategoryOf(book);
      counts.set(category, (counts.get(category) || 0) + 1);
    }
    return counts;
  }

  private static normalizeTitle(value: string): string {
    const normalized = (value || '').trim().toLowerCase()
      .replace(/[\u200B-\u200D\uFEFF]/g, '')
      .replace(/\s+/g, '')
      .replace(/[《》【】\[\]（）()「」『』"“”'‘’.,，。:：;；!！?？、·_\-]/g, '');
    // 简繁同搜开着时按简体分组，「鬥破蒼穹」与「斗破苍穹」进同一组。
    const script = SearchChineseScriptRuntime.ready();
    return script ? script.fold(normalized) : normalized;
  }

  private static cloneBook(source: SearchBook): SearchBook {
    const target = new SearchBook();
    target.bookUrl = source.bookUrl || '';
    target.origin = source.origin || '';
    target.originName = source.originName || '';
    target.type = source.type || 0;
    target.name = source.name || '';
    target.author = source.author || '';
    target.kind = source.kind || '';
    target.status = source.status || '';
    target.coverUrl = source.coverUrl || '';
    target.intro = source.intro || '';
    target.latestChapterTitle = source.latestChapterTitle || '';
    target.wordCount = source.wordCount || '';
    target.updateTime = source.updateTime || '';
    target.tocUrl = source.tocUrl || '';
    target.variable = source.variable || '';
    target.bookSourceComment = source.bookSourceComment || '';
    target.customOrder = source.customOrder || 0;
    target.weight = source.weight || 0;
    target.aggregationKey = source.aggregationKey || '';
    target.aggregationCount = Math.max(1, source.aggregationCount || 1);
    target.mediaCategory = source.mediaCategory || '';
    return target;
  }
}
