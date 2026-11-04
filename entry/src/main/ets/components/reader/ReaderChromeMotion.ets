import { curves } from '@kit.ArkUI';

/**
 * 点按正文呼出的顶栏、底栏和侧边控件共用的进出场：从所在的屏幕边缘滑入并淡入，收起时沿原路滑出淡出，
 * 与书架底部悬浮栏随滚动收起、展开的观感一致。小说、漫画、PDF 与文件排版阅读页都用这一套。
 *
 * 动画参数挂在 TransitionEffect 上，菜单开关处不用包 animateTo，返回键、点空白等所有收起路径都有动画。
 * distance 传控件离所在边缘的距离，整块移出屏幕。只在菜单整体显隐时加在外层；菜单与目录、设置面板之间
 * 切换时底栏要原地换内容，不能各自带这套进出场，否则按钮会先滑走再滑回来。
 */
export class ReaderChromeMotion {
  /** 顶栏：自屏幕上方滑入。 */
  static top(distance: number): TransitionEffect {
    return ReaderChromeMotion.slide(0, -ReaderChromeMotion.clamp(distance));
  }

  /** 底栏及跟着底栏的快捷按钮：自屏幕下方滑入。 */
  static bottom(distance: number): TransitionEffect {
    return ReaderChromeMotion.slide(0, ReaderChromeMotion.clamp(distance));
  }

  /** 侧边控件（亮度条）：自右侧滑入；fromLeft 为 true 时自左侧。 */
  static side(distance: number, fromLeft: boolean = false): TransitionEffect {
    const offset = ReaderChromeMotion.clamp(distance);
    return ReaderChromeMotion.slide(fromLeft ? -offset : offset, 0);
  }

  private static clamp(distance: number): number {
    return Number.isFinite(distance) ? Math.max(24, distance) : 96;
  }

  private static slide(x: number, y: number): TransitionEffect {
    const appear = TransitionEffect.translate({ x: x, y: y })
      .combine(TransitionEffect.opacity(0))
      .animation({ curve: curves.springMotion(0.38, 0.92) });
    const disappear = TransitionEffect.translate({ x: x, y: y })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 200, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }
}
