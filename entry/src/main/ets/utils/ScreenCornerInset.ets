import deviceInfo from '@ohos.deviceInfo';
import { display } from '@kit.ArkUI';

export interface ScreenCornerOffset {
  right: number;
  bottom: number;
}

/** 读不到屏幕圆角（API 23 以下或系统未配置）时按常见大圆角手机估算，单位 vp。 */
const FALLBACK_RADIUS_VP = 44;
/** 胶囊圆角与屏幕圆弧之间至少留出的距离，单位 vp。 */
const CORNER_GAP_VP = 3;

/**
 * 贴在屏幕右下角的小胶囊（阅读页页码角标等）按屏幕圆角往里让：底边距离保持调用方给的值，
 * 只把右边距加到胶囊右下圆角刚好落进屏幕圆弧以内；底边离角太近、横向让不开时再抬高底边。
 * 屏幕圆角从 display.getRoundedCorner()（API 23）读取，读不到时按 FALLBACK_RADIUS_VP 估算。
 * 只在视图横向占满屏幕时生效：悬浮窗、左右分屏的右下角不是屏幕圆角，保持调用方原来的位置。
 */
export class ScreenCornerInset {
  private static cacheKey: string = '';
  private static cacheRadius: number = 0;
  private static cacheWidth: number = 0;

  static place(viewWidth: number, bottom: number, minRight: number, badgeRadius: number): ScreenCornerOffset {
    const result: ScreenCornerOffset = { right: minRight, bottom: bottom };
    ScreenCornerInset.refresh();
    const screenWidth = ScreenCornerInset.cacheWidth;
    if (screenWidth > 0 && viewWidth > 0 && Math.abs(viewWidth - screenWidth) > 2) return result;
    return ScreenCornerInset.solve(ScreenCornerInset.cacheRadius, bottom, minRight, badgeRadius);
  }

  /** 纯几何：屏幕圆角半径 radius 下，底边距 bottom 时胶囊（圆角 badgeRadius）最少要离右边多远。 */
  static solve(radius: number, bottom: number, minRight: number, badgeRadius: number): ScreenCornerOffset {
    const rb = Math.max(0, badgeRadius);
    const limit = radius - rb - CORNER_GAP_VP;
    let dy = radius - bottom - rb;
    if (limit <= 0 || dy <= 0) return { right: minRight, bottom: bottom };
    let placedBottom = bottom;
    if (dy > limit) {
      placedBottom = radius - rb - limit;
      dy = limit;
    }
    const dx = Math.sqrt(Math.max(0, limit * limit - dy * dy));
    const right = Math.max(minRight, Math.ceil(radius - rb - dx));
    return { right: right, bottom: placedBottom };
  }

  private static refresh(): void {
    try {
      const current = display.getDefaultDisplaySync();
      const density = current.densityPixels > 0 ? current.densityPixels : 1;
      const key = `${current.id}:${current.width}x${current.height}:${density}`;
      if (key === ScreenCornerInset.cacheKey) return;
      ScreenCornerInset.cacheKey = key;
      ScreenCornerInset.cacheWidth = current.width / density;
      ScreenCornerInset.cacheRadius = ScreenCornerInset.readRadius(current, density);
    } catch (_error) {
      ScreenCornerInset.cacheKey = '';
      ScreenCornerInset.cacheWidth = 0;
      ScreenCornerInset.cacheRadius = FALLBACK_RADIUS_VP;
    }
  }

  private static readRadius(current: display.Display, density: number): number {
    if (deviceInfo.sdkApiVersion < 23) return FALLBACK_RADIUS_VP;
    try {
      const corners = current.getRoundedCorner();
      let radius = 0;
      for (const corner of corners) {
        if (corner.type === display.CornerType.BOTTOM_RIGHT) {
          radius = corner.radius;
          break;
        }
        radius = Math.max(radius, corner.radius);
      }
      return radius > 0 ? radius / density : FALLBACK_RADIUS_VP;
    } catch (_error) {
      return FALLBACK_RADIUS_VP;
    }
  }
}
