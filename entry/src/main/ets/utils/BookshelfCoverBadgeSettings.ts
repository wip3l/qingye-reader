/** 四角顺序：左上、右上、左下、右下。空角保留分隔符，旧数据缺字段才迁移。 */
export class BookshelfCoverBadgeSettings {
  static readonly DEFAULT: string = 'pin|update,unread|type|source';
  /** offline 是后加的，默认不放到任何角，已有配置也不受影响。 */
  static readonly ITEMS: string[] = ['type', 'source', 'update', 'pin', 'unread', 'offline'];
  static readonly CORNERS: number[] = [0, 1, 2, 3];

  static normalize(raw: string, showType: boolean = true, showSource: boolean = true): string {
    const fallback = `pin|update,unread|${showType ? 'type' : ''}|${showSource ? 'source' : ''}`;
    const parts = typeof raw === 'string' && raw.split('|').length === 4 ? raw.split('|') : fallback.split('|');
    const used: string[] = [];
    return parts.map((part: string): string => {
      const items: string[] = [];
      for (const item of part.split(',')) {
        if (items.length < 2 && BookshelfCoverBadgeSettings.ITEMS.indexOf(item) >= 0 && used.indexOf(item) < 0) {
          items.push(item);
          used.push(item);
        }
      }
      return items.join(',');
    }).join('|');
  }

  static items(raw: string, corner: number): string[] {
    return (BookshelfCoverBadgeSettings.normalize(raw).split('|')[corner] || '').split(',')
      .filter((item: string): boolean => item.length > 0);
  }

  static move(raw: string, corner: number, selected: string[]): string {
    if (corner < 0 || corner > 3 || !Number.isInteger(corner)) return BookshelfCoverBadgeSettings.normalize(raw);
    const chosen = BookshelfCoverBadgeSettings.ITEMS.filter((item: string): boolean => selected.indexOf(item) >= 0).slice(0, 2);
    return BookshelfCoverBadgeSettings.CORNERS.map((position: number): string => {
      if (position === corner) return chosen.join(',');
      return BookshelfCoverBadgeSettings.items(raw, position)
        .filter((item: string): boolean => chosen.indexOf(item) < 0).join(',');
    }).join('|');
  }

  static location(raw: string, item: string): number {
    return BookshelfCoverBadgeSettings.CORNERS.findIndex((corner: number): boolean =>
      BookshelfCoverBadgeSettings.items(raw, corner).indexOf(item) >= 0);
  }

  static cornerLabel(corner: number): string {
    return ['左上角', '右上角', '左下角', '右下角'][corner] || '';
  }

  static label(item: string): string {
    if (item === 'type') return '类型标识';
    if (item === 'source') return '书籍来源';
    if (item === 'update') return '书籍更新标识';
    if (item === 'pin') return '置顶标识';
    if (item === 'unread') return '未读章节数';
    if (item === 'offline') return '离线标识';
    return '';
  }

  static summary(raw: string, corner: number): string {
    return BookshelfCoverBadgeSettings.items(raw, corner).map((item: string): string =>
      item === 'update' ? '更新标识' : (item === 'unread' ? '未读数' : BookshelfCoverBadgeSettings.label(item)))
      .join(' · ') || '不显示';
  }

  static unreadText(count: number): string {
    if (!Number.isFinite(count) || count <= 0) return '';
    return count > 99 ? '99+' : String(Math.floor(count));
  }
}
