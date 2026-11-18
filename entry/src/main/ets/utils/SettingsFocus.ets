import { router } from '@kit.ArkUI';

/**
 * 从设置搜索跳到某个设置行：记下要找的行标题，打开所在页面；
 * 页面的滚动容器（PageScaffold，或页面自己的面板）登记 Scroller，
 * 标题相同的 SettingRow 出现时认领，滚到它并闪烁提示。
 * 只认领一次，超时作废，避免以后普通打开页面时误闪。
 * 放在 utils 模块里是为了进程内单例（页面文件的静态字段每次开页都是新的）。
 */
export class SettingsFocus {
  private static readonly TTL_MS: number = 8000;
  private static target: string = '';
  private static requestedAt: number = 0;
  private static scroller: Scroller | null = null;

  /** 打开设置页并在出现后定位到 focus 那一行；focus 为空串时只打开页面。 */
  static open(url: string, params: Record<string, string> | undefined, focus: string): void {
    SettingsFocus.target = focus;
    SettingsFocus.requestedAt = Date.now();
    SettingsFocus.scroller = null;
    const options: router.RouterOptions = params ? { url: url, params: params } : { url: url };
    router.pushUrl(options).catch((error: Error) => {
      SettingsFocus.target = '';
      console.error('从设置搜索打开页面失败:', error.message);
    });
  }

  private static pending(): boolean {
    if (!SettingsFocus.target) return false;
    if (Date.now() - SettingsFocus.requestedAt > SettingsFocus.TTL_MS) {
      SettingsFocus.target = '';
      SettingsFocus.scroller = null;
      return false;
    }
    return true;
  }

  /** 先登记的为准：页面要用自己的面板滚动时，在 aboutToAppear 里先于内部的 PageScaffold 登记。 */
  static bindScroller(scroller: Scroller): void {
    if (SettingsFocus.pending() && SettingsFocus.scroller === null) SettingsFocus.scroller = scroller;
  }

  /** 设置行出现时调用；标题对上就认领并返回要滚动的容器（可能为 null，仍可闪烁）。 */
  static claim(title: string): boolean {
    if (!title || !SettingsFocus.pending() || title !== SettingsFocus.target) return false;
    SettingsFocus.target = '';
    return true;
  }

  static takeScroller(): Scroller | null {
    const scroller = SettingsFocus.scroller;
    SettingsFocus.scroller = null;
    return scroller;
  }

  /**
   * 把 id 对应的组件滚到顶栏下方一点的位置，返回滚动动画时长（没滚动为 0），调用方等它结束再闪烁。
   * 超出可滚范围时 Scroller 自己会停在边上。
   */
  static scrollIntoView(context: UIContext, componentId: string, scroller: Scroller | null,
    statusBarHeight: number): number {
    if (!scroller) return 0;
    try {
      const rect = context.getComponentUtils().getRectangleById(componentId);
      const top = context.px2vp(rect.windowOffset.y);
      const delta = top - (statusBarHeight + SettingsFocus.HEADER_HEIGHT + SettingsFocus.TOP_GAP);
      if (Math.abs(delta) < 4) return 0;
      scroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, scroller.currentOffset().yOffset + delta),
        animation: { duration: SettingsFocus.SCROLL_MS, curve: Curve.FastOutSlowIn } });
      return SettingsFocus.SCROLL_MS + 40;
    } catch (e) {
      console.warn('设置搜索定位失败:', (e as Error).message);
      return 0;
    }
  }

  /** 闪两下：亮 → 暗 → 亮 → 暗，set 由设置行改自己的状态。 */
  static flash(set: (on: boolean) => void): void {
    const steps: number[] = [0, 520, 820, 1340];
    steps.forEach((delay: number, index: number) => {
      setTimeout(() => {
        animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => set(index % 2 === 0));
      }, delay);
    });
  }

  /** 顶栏内容高度（PageScaffold.BAR_HEIGHT）与其下方留白。 */
  private static readonly HEADER_HEIGHT: number = 56;
  private static readonly TOP_GAP: number = 96;
  private static readonly SCROLL_MS: number = 320;
  /** 页面转场结束、行完成布局后再量位置。 */
  static readonly SETTLE_MS: number = 380;
}
