/** 只需要章节名的最小形状，便于纯逻辑回归脚本直接传对象。 */
export interface ChapterTitleItem {
  title: string;
}

/**
 * 换源后在新目录里找回原来读到的那一章（纯逻辑）。
 *
 * 不同书源的目录常多出或少了公告、卷名、请假条，直接沿用章节序号会偏几章。做法：以原序号和按目录长度
 * 折算的序号为中心，在附近窗口里依次找完整章名相同、去掉章号后的章名相同、章号相同、章名互相包含的章节，
 * 同类里取离中心最近的；窗口里都找不到时，整本目录里只有一章完整章名相同才认它；再不行退回原序号。
 */
export class ChapterPositionMatcher {
  static readonly WINDOW: number = 15;
  private static readonly MIN_CONTAIN_LENGTH: number = 4;
  private static readonly NUMBER_PATTERN: RegExp =
    /第\s*([0-9零〇一二两三四五六七八九十百千万]+)\s*[章节回集话篇幕]/;
  private static readonly LEADING_NUMBER_PATTERN: RegExp = /^\s*(\d+)(?=[\s.、:：\-_)）]|$)/;

  static match(oldIndex: number, oldTitle: string, oldTotal: number, chapters: ChapterTitleItem[]): number {
    const total = chapters.length;
    if (total === 0) return 0;
    const baseIndex = Math.max(0, Math.round(oldIndex || 0));
    const fallback = Math.min(baseIndex, total - 1);
    const fullName = ChapterPositionMatcher.compact(oldTitle);
    if (!fullName) return fallback;
    const scaled = oldTotal > 0 ? Math.round(baseIndex * total / oldTotal) : baseIndex;
    const low = Math.max(0, Math.min(baseIndex, scaled) - ChapterPositionMatcher.WINDOW);
    const high = Math.min(total - 1, Math.max(baseIndex, scaled) + ChapterPositionMatcher.WINDOW);
    if (low > high) return ChapterPositionMatcher.uniqueFullMatch(fullName, chapters, fallback);

    const pureName = ChapterPositionMatcher.pureName(oldTitle);
    const number = ChapterPositionMatcher.chapterNumber(oldTitle);
    const distance = (index: number): number => Math.min(Math.abs(index - baseIndex), Math.abs(index - scaled));
    let bestRank = Number.MAX_SAFE_INTEGER;
    let bestDistance = Number.MAX_SAFE_INTEGER;
    let bestIndex = -1;
    for (let index = low; index <= high; index++) {
      const title = chapters[index].title || '';
      const rank = ChapterPositionMatcher.rank(fullName, pureName, number, title);
      if (rank < 0) continue;
      const gap = distance(index);
      if (rank < bestRank || (rank === bestRank && gap < bestDistance)) {
        bestRank = rank;
        bestDistance = gap;
        bestIndex = index;
      }
    }
    if (bestIndex >= 0) return bestIndex;
    return ChapterPositionMatcher.uniqueFullMatch(fullName, chapters, fallback);
  }

  /** 越小越可信；-1 表示不算匹配。 */
  private static rank(fullName: string, pureName: string, number: number, title: string): number {
    if (ChapterPositionMatcher.compact(title) === fullName) return 0;
    const candidatePure = ChapterPositionMatcher.pureName(title);
    const candidateNumber = ChapterPositionMatcher.chapterNumber(title);
    const numbersAgree = number < 0 || candidateNumber < 0 || number === candidateNumber;
    if (pureName && candidatePure === pureName && numbersAgree) return 1;
    if (number >= 0 && candidateNumber === number) return 2;
    if (pureName.length >= ChapterPositionMatcher.MIN_CONTAIN_LENGTH &&
      candidatePure.length >= ChapterPositionMatcher.MIN_CONTAIN_LENGTH && numbersAgree &&
      (candidatePure.includes(pureName) || pureName.includes(candidatePure))) {
      return 3;
    }
    return -1;
  }

  private static uniqueFullMatch(fullName: string, chapters: ChapterTitleItem[], fallback: number): number {
    let found = -1;
    for (let index = 0; index < chapters.length; index++) {
      if (ChapterPositionMatcher.compact(chapters[index].title || '') !== fullName) continue;
      if (found >= 0) return fallback;
      found = index;
    }
    return found >= 0 ? found : fallback;
  }

  /** 全角转半角、去空白与标点，只留文字和数字。 */
  static compact(title: string): string {
    return (title || '')
      .replace(/[！-～]/g, (char: string): string => String.fromCharCode(char.charCodeAt(0) - 0xFEE0))
      .replace(/　/g, ' ')
      .toLowerCase()
      .replace(/[\s\p{P}\p{S}]+/gu, '');
  }

  /** 去掉“第几章”或开头的数字章号后的章名。 */
  static pureName(title: string): string {
    const halfWidth = (title || '')
      .replace(/[！-～]/g, (char: string): string => String.fromCharCode(char.charCodeAt(0) - 0xFEE0));
    const stripped = halfWidth
      .replace(new RegExp(ChapterPositionMatcher.NUMBER_PATTERN.source, 'g'), ' ')
      .replace(ChapterPositionMatcher.LEADING_NUMBER_PATTERN, ' ');
    return ChapterPositionMatcher.compact(stripped);
  }

  /** 章号；认不出时返回 -1。 */
  static chapterNumber(title: string): number {
    const halfWidth = (title || '')
      .replace(/[０-９]/g, (char: string): string => String.fromCharCode(char.charCodeAt(0) - 0xFEE0));
    const marked = halfWidth.match(ChapterPositionMatcher.NUMBER_PATTERN);
    if (marked) return ChapterPositionMatcher.parseNumber(marked[1]);
    const leading = halfWidth.match(ChapterPositionMatcher.LEADING_NUMBER_PATTERN);
    return leading ? ChapterPositionMatcher.parseNumber(leading[1]) : -1;
  }

  static parseNumber(text: string): number {
    if (/^\d+$/.test(text)) return Number.parseInt(text, 10);
    const digits: Record<string, number> = {
      '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9
    };
    const units: Record<string, number> = { '十': 10, '百': 100, '千': 1000 };
    if (!/[十百千万]/.test(text)) {
      // “二〇二三”这类逐位写法。
      let value = 0;
      for (const char of text) {
        const digit = /\d/.test(char) ? Number.parseInt(char, 10) : digits[char];
        if (digit === undefined) return -1;
        value = value * 10 + digit;
      }
      return value;
    }
    let result = 0;
    let section = 0;
    let digit = -1;
    for (const char of text) {
      if (char === '万') {
        section += digit > 0 ? digit : 0;
        result += (section > 0 ? section : 1) * 10000;
        section = 0;
        digit = -1;
        continue;
      }
      const unit = units[char];
      if (unit !== undefined) {
        // “十二”省略了前面的“一”。
        section += (digit >= 0 ? (digit === 0 ? 1 : digit) : 1) * unit;
        digit = -1;
        continue;
      }
      const value = /\d/.test(char) ? Number.parseInt(char, 10) : digits[char];
      if (value === undefined) return -1;
      digit = value;
    }
    return result + section + (digit > 0 ? digit : 0);
  }
}
