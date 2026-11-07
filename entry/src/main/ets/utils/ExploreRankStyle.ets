/**
 * 发现页结果布局与排行样式的共用约定。
 *
 * 发现页有五种结果布局：列表、平铺、排行（所有频道都按名次，前三名上领奖台）、
 * 榜单总览（每个榜一张卡片，只放前五名）、侧栏（左侧竖排频道，右侧带名次的窄版排行）。
 * 搜索层与发现页共用同一个设置键，但只认列表和平铺，其余一律按列表显示。
 *
 * 名次就是书源返回的顺序。书源不区分“榜单”和“分类”，只能按频道名猜，猜不全，
 * 所以只用在总览（哪些频道做成卡片）和侧栏分节上，不决定排行编不编号。
 */
export class ExploreRankStyle {
  static readonly LAYOUT_LIST: string = 'list';
  static readonly LAYOUT_GRID: string = 'grid';
  static readonly LAYOUT_RANK: string = 'rank';
  static readonly LAYOUT_OVERVIEW: string = 'overview';
  static readonly LAYOUT_SIDEBAR: string = 'sidebar';
  /** 结果列表组件内部的窄版排行（侧栏右侧用），不是可选的布局设置。 */
  static readonly LIST_MODE_RANK_COMPACT: string = 'rankCompact';

  static normalizeLayout(value: string): string {
    switch (value) {
      case ExploreRankStyle.LAYOUT_GRID:
      case ExploreRankStyle.LAYOUT_RANK:
      case ExploreRankStyle.LAYOUT_OVERVIEW:
      case ExploreRankStyle.LAYOUT_SIDEBAR:
        return value;
      default:
        return ExploreRankStyle.LAYOUT_LIST;
    }
  }

  /** 搜索结果没有名次，也没有频道可分，只用列表或平铺。 */
  static searchLayout(value: string): string {
    return value === ExploreRankStyle.LAYOUT_GRID ? ExploreRankStyle.LAYOUT_GRID : ExploreRankStyle.LAYOUT_LIST;
  }

  /** 频道名带“榜”“排行”“TOP”的当榜单，其余当分类。 */
  static isBoardTitle(title: string): boolean {
    return /榜|排行|top/i.test(title || '');
  }

  /** 前三名的名次颜色：金、银、铜；其余返回空串，由调用方用次要文字色。 */
  static medalColor(rank: number, darkMode: boolean): string {
    if (rank === 1) return darkMode ? '#E2B352' : '#C8901F';
    if (rank === 2) return darkMode ? '#B4BFCD' : '#8391A5';
    if (rank === 3) return darkMode ? '#D69068' : '#B06C43';
    return '';
  }
}
