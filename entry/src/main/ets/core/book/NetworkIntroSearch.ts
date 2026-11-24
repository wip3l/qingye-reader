import { Book, BookFieldSanitizer, SearchBook } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { WebBookService } from './WebBookService';

/** 书的变量里记自定义简介取自哪个书源，详情页据此写“来自 某书源”；手写或改过的为空。 */
export const CUSTOM_INTRO_SOURCE_KEY = 'customIntroSource';

/** 书库里自定义简介的长度上限，与 AppDatabase 的截断迁移一致。 */
const INTRO_LIMIT = 65536;
/** 候选最多列这么多段，同名书多的时候不至于刷满一屏。 */
const CANDIDATE_LIMIT = 40;
/** 去掉空白和标点后短于这个字数的不算简介（“暂无简介”“待补充”之类）。 */
const MIN_INTRO_CHARS = 12;
/** 至少这么多字对得上，才把截短的简介当成同一段的前半截。 */
const PREFIX_MERGE_CHARS = 30;

/** 一段可选的网络简介；多个书源给出同一段时合并成一条，记下有几个书源。 */
export class NetworkIntroCandidate {
  key: string = '';
  intro: string = '';
  book: SearchBook = new SearchBook();
  sourceCount: number = 1;
  authorMatched: boolean = false;
  /** 已从详情页取过完整简介，不再重复请求。 */
  completed: boolean = false;
}

/**
 * 给本地书找简介：书源搜索结果自带的简介按内容去重、按作者是否一致排序；
 * 搜索列表里的简介常被截短，选中时再去该书源的详情页取完整的一段。
 */
export class NetworkIntroSearch {
  static cleanIntro(raw: string): string {
    const text = BookFieldSanitizer.clean(raw || '')
      .replace(/\r\n?/g, '\n')
      .split('\n')
      .map((line: string): string => line.replace(/^[\s　]+|[\s　]+$/g, ''))
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return text.length > INTRO_LIMIT ? text.substring(0, INTRO_LIMIT) : text;
  }

  /** 用户手写的简介只理空白，不按书源字段规则过滤（里面写了尖括号或代码片段也照存）。 */
  static normalizeManual(raw: string): string {
    const text = (raw || '')
      .replace(/\r\n?/g, '\n')
      .split('\n')
      .map((line: string): string => line.replace(/[\s　]+$/g, ''))
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return text.length > INTRO_LIMIT ? text.substring(0, INTRO_LIMIT) : text;
  }

  /** 比较用的键：去掉空白、标点和结尾省略号，被截短的简介能和完整的对上。 */
  static compactKey(text: string): string {
    return (text || '')
      .replace(/(?:\.{3,}|…+|。{3,})\s*$/, '')
      .replace(/[\s　，。、；：？！“”‘’「」『』（）《》〈〉【】…—～·,.;:?!"'()\[\]<>\-_~*#|\/\\]/g, '')
      .toLowerCase();
  }

  static normalizeAuthor(author: string): string {
    return (author || '')
      .replace(/^\s*(?:作者|作\s*者|著)\s*[:：]?\s*/, '')
      .replace(/[\s　·•.。,，()（）\[\]【】]/g, '')
      .toLowerCase();
  }

  /** 结尾带省略号或很短的，多半是搜索列表截过的，选中时去详情页补全。 */
  static looksTruncated(intro: string): boolean {
    const text = (intro || '').trim();
    return text.length < 120 || /(?:\.{3,}|…+|。{3,})$/.test(text);
  }

  /** 把新到的搜索结果并进候选；返回新数组，原数组不改。 */
  static merge(current: NetworkIntroCandidate[], results: SearchBook[], author: string): NetworkIntroCandidate[] {
    const merged = current.slice();
    const wantedAuthor = NetworkIntroSearch.normalizeAuthor(author);
    for (const result of results) {
      const intro = NetworkIntroSearch.cleanIntro(result.intro);
      const key = NetworkIntroSearch.compactKey(intro);
      if (key.length < MIN_INTRO_CHARS) continue;
      const authorMatched = !!wantedAuthor && NetworkIntroSearch.normalizeAuthor(result.author) === wantedAuthor;
      // 截短的简介按前缀并进完整的那段；太短的前缀可能只是相同的开场白，不并。
      const index = merged.findIndex((item: NetworkIntroCandidate): boolean => item.key === key ||
        (Math.min(item.key.length, key.length) >= PREFIX_MERGE_CHARS &&
          (item.key.startsWith(key) || key.startsWith(item.key))));
      if (index >= 0) {
        const existing = merged[index];
        const next = NetworkIntroSearch.copy(existing);
        next.sourceCount = existing.sourceCount + 1;
        // 同一段简介留最长的那份；一样长时作者一致的书源优先作展示来源。
        if (key.length > existing.key.length) {
          next.key = key;
          next.intro = intro;
          next.book = result;
        } else if (key.length === existing.key.length && authorMatched && !existing.authorMatched) {
          next.book = result;
        }
        next.authorMatched = existing.authorMatched || authorMatched;
        merged[index] = next;
        continue;
      }
      if (merged.length >= CANDIDATE_LIMIT) continue;
      const candidate = new NetworkIntroCandidate();
      candidate.key = key;
      candidate.intro = intro;
      candidate.book = result;
      candidate.authorMatched = authorMatched;
      merged.push(candidate);
    }
    return NetworkIntroSearch.sort(merged);
  }

  static sort(list: NetworkIntroCandidate[]): NetworkIntroCandidate[] {
    return list.slice().sort((a: NetworkIntroCandidate, b: NetworkIntroCandidate): number => {
      if (a.authorMatched !== b.authorMatched) return a.authorMatched ? -1 : 1;
      if (a.sourceCount !== b.sourceCount) return b.sourceCount - a.sourceCount;
      return b.intro.length - a.intro.length;
    });
  }

  static copy(item: NetworkIntroCandidate): NetworkIntroCandidate {
    const next = new NetworkIntroCandidate();
    next.key = item.key;
    next.intro = item.intro;
    next.book = item.book;
    next.sourceCount = item.sourceCount;
    next.authorMatched = item.authorMatched;
    next.completed = item.completed;
    return next;
  }

  /** 去书源详情页取完整简介；取不到或不比原来长时返回空串。不弹验证网页。 */
  static async fetchFullIntro(candidate: NetworkIntroCandidate): Promise<string> {
    const result = candidate.book;
    if (!result.origin || !result.bookUrl) return '';
    const source = await AppDatabase.getInstance().getBookSource(result.origin);
    if (!source) return '';
    const book = new Book();
    book.bookUrl = result.bookUrl;
    book.tocUrl = result.tocUrl;
    book.origin = result.origin;
    book.originName = result.originName;
    book.name = result.name;
    book.author = result.author;
    book.kind = result.kind;
    book.coverUrl = result.coverUrl;
    book.intro = result.intro;
    book.type = result.type;
    book.variable = result.variable;
    const full = await new WebBookService().setSourceInteraction((): boolean => false).getBookInfo(source, book);
    const intro = NetworkIntroSearch.cleanIntro(full.intro);
    return NetworkIntroSearch.compactKey(intro).length > candidate.key.length ? intro : '';
  }
}
