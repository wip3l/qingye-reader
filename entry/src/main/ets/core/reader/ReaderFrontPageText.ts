/** 书封扉页上的文字整理（纯逻辑）：分类标签、章数字数一行、页码换算。 */
export class ReaderFrontPageText {
  static readonly MAX_TAGS: number = 3;
  static readonly MAX_TAG_LENGTH: number = 6;

  /** 书源的分类字段常是“玄幻,东方玄幻 连载 2024-05-01”之类：拆开、去重，去掉日期、数字、状态和过长的词。 */
  static tags(kind: string): string[] {
    const result: string[] = [];
    for (const raw of (kind || '').split(/[,，、;；|/\\\s·•]+/)) {
      const tag = raw.trim();
      if (!tag || tag.length > ReaderFrontPageText.MAX_TAG_LENGTH || /\d/.test(tag)) continue;
      if (/^(连载|连载中|完结|已完结|完本|全本|暂停|断更|免费|VIP|vip|其他|其它|未知)$/.test(tag)) continue;
      if (!result.includes(tag)) result.push(tag);
      if (result.length >= ReaderFrontPageText.MAX_TAGS) break;
    }
    return result;
  }

  /** “共 312 章 · 98.6 万字”；字数是纯数字时换算成万字，其余原样保留，取不到就只写章数。 */
  static meta(chapterCount: number, wordCount: string): string {
    const parts: string[] = [];
    if (chapterCount > 0) parts.push(`共 ${chapterCount} 章`);
    const words = ReaderFrontPageText.words(wordCount);
    if (words) parts.push(words);
    return parts.join(' · ');
  }

  static words(wordCount: string): string {
    const value = (wordCount || '').trim();
    if (!value) return '';
    if (/^\d+$/.test(value)) {
      const count = Number(value);
      if (!Number.isFinite(count) || count <= 0) return '';
      return count >= 10000 ? `${(count / 10000).toFixed(1).replace(/\.0$/, '')} 万字` : `${count} 字`;
    }
    const normalized = value.replace(/\s+/g, '');
    return /字$/.test(normalized) ? normalized : `${normalized}字`;
  }

  /** 页脚和进度条用的本章页码：扉页之后从 0 数起。 */
  static contentPageIndex(rawPageIndex: number, frontPages: number): number {
    return Math.max(0, rawPageIndex - Math.max(0, frontPages));
  }

  /** 本章的正文页数（不算扉页）；未知（≤0）原样返回。 */
  static contentPageCount(rawPageCount: number, frontPages: number): number {
    if (rawPageCount <= 0) return rawPageCount;
    return Math.max(1, rawPageCount - Math.max(0, frontPages));
  }
}
