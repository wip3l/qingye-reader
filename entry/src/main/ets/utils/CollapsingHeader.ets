/**
 * 首页和设置页的顶栏收起计算：上滑跟手收起、下滑跟手展开。
 * 分类/频道栏常驻；搜索框是否一起收起由页面传入的 distance 决定。
 *
 * 收起量永远不超过列表实际滚动距离：列表顶部留白按标题行完全展开时的高度预留，
 * 所以刚开始滚动或顶部回弹时，标题行下方不会露出空隙。
 */
export class CollapsingHeader {
  /** 可收起的高度，即标题行去掉状态栏后的高度。 */
  static readonly DISTANCE: number = 56;

  /** distance 默认是标题行高度；搜索页把搜索框等一起收起时传入更大的值。 */
  static next(current: number, delta: number, offset: number,
    distance: number = CollapsingHeader.DISTANCE): number {
    if (!Number.isFinite(delta) || !Number.isFinite(offset)) {
      return current;
    }
    const max = Math.min(distance, Math.max(0, offset));
    return Math.round(Math.min(max, Math.max(0, current + delta)));
  }

  /** 停止滚动时吸附到完全展开或完全收起，避免标题行停在半截。 */
  static settle(current: number, offset: number, distance: number = CollapsingHeader.DISTANCE): number {
    if (current <= 0 || current >= distance) {
      return current;
    }
    return current > distance / 2 && offset >= distance ? distance : 0;
  }

  /**
   * 收起区里某一行的不透明度：该行位于收起区内 [top, top + height)，收起量越过它的顶部后开始淡出，
   * 在被完全裁掉之前就已透明。
   */
  static rowOpacity(collapse: number, top: number, height: number): number {
    if (height <= 0) {
      return 1;
    }
    return Math.max(0, Math.min(1, 1 - (collapse - top) / (height * 0.6)));
  }

  /** 标题行内容在收起过半前就淡出，不会滑进状态栏里和系统图标叠在一起。 */
  static contentOpacity(collapse: number): number {
    return Math.max(0, 1 - collapse / (CollapsingHeader.DISTANCE * 0.6));
  }

  /** 状态栏遮罩在状态栏下沿之外继续渐隐的高度。 */
  static readonly SCRIM_FADE_HEIGHT: number = 16;

  /**
   * 书籍详情的封面延伸到顶栏，继续按标题淡出量显现状态栏渐变。
   * 普通顶栏由 HeaderBackdrop 的可见高度控制渐变，不再叠加此透明度。
   */
  static scrimOpacity(collapse: number, distance: number = CollapsingHeader.DISTANCE): number {
    if (!(distance > 0) || !Number.isFinite(collapse)) {
      return 0;
    }
    return Math.max(0, Math.min(1, (collapse / distance - 0.3) / 0.6));
  }

  static acceptsTouch(collapse: number): boolean {
    return collapse < CollapsingHeader.DISTANCE / 2;
  }
}
