/** 正文里的一处命中：start/end 是在被查文本里的字符位置，before/text/after 是给结果列表看的摘录。 */
export class ReaderContentSearchMatch {
  start: number = 0;
  end: number = 0;
  /** 本章第几处（从 0 起），跳转后在阅读页的排版文本里按它重新找回同一处。 */
  ordinal: number = 0;
  before: string = '';
  text: string = '';
  after: string = '';
}

/**
 * 正文查找的匹配与摘录（纯逻辑）：普通文字、不区分大小写。
 * 图片、段评按钮等内部标记（[[LEGADO_…]]）不是书的正文，落在标记里的命中不算，摘录里也不出现标记。
 */
export class ReaderContentSearchMatcher {
  static readonly CONTEXT_BEFORE: number = 16;
  static readonly CONTEXT_AFTER: number = 40;
  static readonly MAX_QUERY_LENGTH: number = 64;

  static normalizeQuery(query: string): string {
    return (query || '').trim().substring(0, ReaderContentSearchMatcher.MAX_QUERY_LENGTH);
  }

  /** 按出现顺序返回 text 里 query 的命中，最多 limit 处。 */
  static find(text: string, query: string, limit: number = Number.MAX_SAFE_INTEGER): ReaderContentSearchMatch[] {
    const result: ReaderContentSearchMatch[] = [];
    const needle = ReaderContentSearchMatcher.normalizeQuery(query);
    if (!text || !needle || limit <= 0) return result;
    const markers = ReaderContentSearchMatcher.markerRanges(text);
    const pattern = new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
    let markerIndex = 0;
    let ordinal = 0;
    let found = pattern.exec(text);
    while (found) {
      const start = found.index;
      const end = start + found[0].length;
      while (markerIndex < markers.length && markers[markerIndex][1] <= start) markerIndex++;
      const marker = markerIndex < markers.length ? markers[markerIndex] : null;
      if (marker && marker[0] < end) {
        // 命中落进标记：从标记末尾接着找。
        pattern.lastIndex = marker[1];
      } else {
        const match = new ReaderContentSearchMatch();
        match.start = start;
        match.end = end;
        match.ordinal = ordinal++;
        match.text = found[0];
        match.before = ReaderContentSearchMatcher.excerpt(text, markers,
          Math.max(0, start - ReaderContentSearchMatcher.CONTEXT_BEFORE * 3), start, false);
        match.after = ReaderContentSearchMatcher.excerpt(text, markers,
          end, Math.min(text.length, end + ReaderContentSearchMatcher.CONTEXT_AFTER * 3), true);
        result.push(match);
        if (result.length >= limit) break;
      }
      found = pattern.exec(text);
    }
    return result;
  }

  /**
   * 在阅读页实际排版的文本里找回查找结果那一处。排版文本可能比查找时多出标题行、缩进或图片尺寸标注，
   * 所以先认上下文：同一序号且摘录一致最可靠，其次是摘录一致、序号最接近的一处，最后才按序号取。
   */
  static locate(text: string, query: string, ordinal: number, before: string,
    after: string): ReaderContentSearchMatch | null {
    const matches = ReaderContentSearchMatcher.find(text, query);
    if (matches.length === 0) return null;
    const sameContext = (match: ReaderContentSearchMatch): boolean => {
      const a = ReaderContentSearchMatcher.compact(match.before);
      const b = ReaderContentSearchMatcher.compact(before);
      const c = ReaderContentSearchMatcher.compact(match.after);
      const d = ReaderContentSearchMatcher.compact(after);
      return (a.endsWith(b) || b.endsWith(a)) && (c.startsWith(d) || d.startsWith(c));
    };
    const exact = ordinal >= 0 && ordinal < matches.length ? matches[ordinal] : null;
    if (exact && sameContext(exact)) return exact;
    let best: ReaderContentSearchMatch | null = null;
    for (const match of matches) {
      if (!sameContext(match)) continue;
      if (!best || Math.abs(match.ordinal - ordinal) < Math.abs(best.ordinal - ordinal)) best = match;
    }
    return best || exact || matches[matches.length - 1];
  }

  /** [[LEGADO_…]] 标记所在的 [start, end) 区间，按位置排好。 */
  static markerRanges(text: string): number[][] {
    const ranges: number[][] = [];
    if (text.indexOf('[[LEGADO_') < 0) return ranges;
    const pattern = /\[\[LEGADO_[A-Z0-9_]+:[\s\S]*?\]\]/g;
    let found = pattern.exec(text);
    while (found) {
      ranges.push([found.index, found.index + found[0].length]);
      found = pattern.exec(text);
    }
    return ranges;
  }

  /** 取 [from, to) 的摘录：去掉标记、空白折成一个空格，再从靠近命中的一端截到上下文长度。 */
  private static excerpt(text: string, markers: number[][], from: number, to: number, forward: boolean): string {
    let start = from;
    let end = to;
    for (const marker of markers) {
      if (marker[0] < start && marker[1] > start) start = marker[1];
      if (marker[0] < end && marker[1] > end) end = marker[0];
    }
    if (end <= start) return '';
    const value = text.substring(start, end)
      .replace(/\[\[LEGADO_[A-Z0-9_]+:[\s\S]*?\]\]/g, ' ')
      .replace(/\s+/g, ' ');
    if (forward) {
      return value.replace(/^ /, '').substring(0, ReaderContentSearchMatcher.CONTEXT_AFTER);
    }
    const trimmed = value.replace(/ $/, '');
    return trimmed.substring(Math.max(0, trimmed.length - ReaderContentSearchMatcher.CONTEXT_BEFORE));
  }

  private static compact(value: string): string {
    return (value || '').replace(/\s+/g, '');
  }
}
