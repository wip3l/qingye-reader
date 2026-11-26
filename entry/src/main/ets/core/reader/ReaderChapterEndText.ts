/** 章末卡片上的文字整理（纯逻辑）。 */
export class ReaderChapterEndText {
  private static readonly NUMBERED: RegExp =
    /^\s*(第\s*[0-9０-９零〇一二两三四五六七八九十百千万]+\s*[章节回卷集话篇幕])/;

  /** 卡片标题：章节名带“第几章”时写“第十二章 读完”，否则“本章读完”。 */
  static headLabel(chapterTitle: string): string {
    const match = ReaderChapterEndText.NUMBERED.exec(chapterTitle || '');
    return match ? `${match[1].replace(/\s+/g, '')} 读完` : '本章读完';
  }

  /** 读完这一章时的全书进度，按章数算，取整；读完最后一章是 100%。 */
  static bookPercent(chapterIndex: number, chapterCount: number): string {
    if (chapterCount <= 0) return '';
    const percent = Math.max(0, Math.min(100, Math.round((chapterIndex + 1) / chapterCount * 100)));
    return `全书 ${percent}%`;
  }

  /** 数字按千分位写，例如 3,186。 */
  static number(value: number): string {
    const rounded = Math.max(0, Math.round(value));
    return `${rounded}`.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  /** 今天读了多久：不足 1 分钟算 1 分钟；没有记录（统计关着、还没取到或还是 0）返回空串，卡片上写“—”。 */
  static todayMinutes(ms: number): string {
    if (ms <= 0) return '';
    return `${Math.max(1, Math.round(ms / 60000))}`;
  }

  /** 最后一章时“下一章”那一行换成的话：本地书写“全书完”，网络书写“已读到最新一章”。 */
  static endOfBook(localBook: boolean): string {
    return localBook ? '全书完' : '已读到最新一章';
  }

  /** 去掉章节名前后的空白和书源常见的序号重复，用作“下一章”。 */
  static nextTitle(title: string): string {
    return (title || '').replace(/\s+/g, ' ').trim();
  }
}
