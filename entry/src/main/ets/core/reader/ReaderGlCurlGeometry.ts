/** 圆柱卷页的折线：p0 在折线上，n 指向被卷起的一侧，radius 为卷曲半径（vp）。 */
export interface ReaderGlCurlFold {
  active: boolean;
  p0x: number;
  p0y: number;
  nx: number;
  ny: number;
  radius: number;
}

/**
 * 仿真翻页（GPU 圆柱卷曲）的几何：算出每一帧的折线。
 *
 * 模型：页角 C 被手指捏到 F。折线垂直于 C→F，折线另一侧的纸卷在半径 R 的圆柱上，卷过半圈的部分
 * 平压回本页上方。页角离折线 dC = (|CF| + πR) / 2 时正好落在 F 上，所以折线随手指倾斜。
 * 半径随 |CF| 长大（radiusGrowth），纸从页角一点点卷起来。
 *
 * 与 3D 仿真（ReaderEmulationFlipPainter）共用同一套起手与跟手规则：上/下部起手抓页角，中部起手抓右边缘
 * 与手指同高的点并限制倾斜；拖动时抓取点在起手一小段距离内平滑移到手指下方；纸不能被拉长；松手后从松手
 * 位置直线滑到终点或弹回；没有手指（点按翻页）时页角沿一段弧线按进度走完。往前翻在镜像坐标系里计算，
 * 页角在左边。
 */
export class ReaderGlCurlGeometry {
  static readonly REGION_TOP: number = 0;
  static readonly REGION_MIDDLE: number = 1;
  static readonly REGION_BOTTOM: number = 2;

  private static readonly TRAJECTORY: number = 0;
  private static readonly DRAGGING: number = 1;
  private static readonly RELEASED: number = 2;

  // 卷曲半径占页宽的比例（原型确认的默认值 12%）。
  radiusRatio: number = 0.12;
  // 中部起手时折线相对竖直方向的最大倾斜（tan 值）。
  private readonly tiltLimit: number = 0.42;
  // 页角从纸边移到手指下方的过渡距离（vp）。
  private readonly followRamp: number = 56;
  // 点按翻页时页角弧线的最大抬起量（页高的比例）。
  private readonly arcLift: number = 0.11;
  // 卷曲半径与页角拉开距离之比；不超过 1/π，页角才能落在手指下。
  private readonly radiusGrowth: number = 0.16;

  private mode: number = ReaderGlCurlGeometry.TRAJECTORY;
  // 页角跟随的是滤过的手指位置：手指本身有一两 vp 的抖动，页角贴着它时折线每帧来回摆一两度，
  // 宽阴影跟着整片闪。用速度自适应的一阶低通（One Euro）：慢拖时截止频率低、抖动滤得干净，
  // 快拖时截止频率升高，页角几乎不拖后。
  private fingerX: number = 0;
  private fingerY: number = 0;
  private fingerTime: number = 0;
  // 页角向手指靠拢的过渡只进不退：拖动进度是未经平滑的原始偏移，按住不动时一抖，页角就在“半贴手指”
  // 和“贴住手指”之间来回跳。
  private followReached: number = 0;
  private speedX: number = 0;
  private speedY: number = 0;
  private readonly minCutoffHz: number = 1.6;
  private readonly speedCutoffGain: number = 0.03;
  private readonly speedCutoffHz: number = 1.0;
  private grabY: number = -1;
  private lastX: number = 0;
  private lastY: number = 0;
  private lastProgress: number = -1;
  private releaseX: number = 0;
  private releaseY: number = 0;
  private releaseProgress: number = 0;

  /** 拖动中：记录手指在卷页表面上的位置（vp）；nowMs 用于平滑，缺省取当前时间。 */
  dragCorner(x: number, y: number, nowMs: number = Date.now()): void {
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    if (this.mode !== ReaderGlCurlGeometry.DRAGGING) {
      this.grabY = y;
      this.fingerX = x;
      this.fingerY = y;
      this.followReached = 0;
      this.speedX = 0;
      this.speedY = 0;
      this.fingerTime = nowMs;
      this.mode = ReaderGlCurlGeometry.DRAGGING;
      return;
    }
    const dt = Math.max(0.001, Math.min(0.1, (nowMs - this.fingerTime) / 1000));
    this.fingerTime = nowMs;
    const alpha = (cutoffHz: number): number => {
      const tau = 1 / (2 * Math.PI * cutoffHz);
      return 1 / (1 + tau / dt);
    };
    const speedAlpha = alpha(this.speedCutoffHz);
    this.speedX += ((x - this.fingerX) / dt - this.speedX) * speedAlpha;
    this.speedY += ((y - this.fingerY) / dt - this.speedY) * speedAlpha;
    const cutoff = this.minCutoffHz + this.speedCutoffGain * Math.hypot(this.speedX, this.speedY);
    const positionAlpha = alpha(cutoff);
    this.fingerX += (x - this.fingerX) * positionAlpha;
    this.fingerY += (y - this.fingerY) * positionAlpha;
  }

  /** 松手：冻结此刻的页角位置，之后按进度滑向终点或弹回。没有跟手画过时回到固定轨迹。 */
  releaseCorner(): void {
    if (this.mode !== ReaderGlCurlGeometry.DRAGGING || this.lastProgress < 0) {
      this.clearCorner();
      return;
    }
    this.releaseX = this.lastX;
    this.releaseY = this.lastY;
    this.releaseProgress = this.lastProgress;
    this.mode = ReaderGlCurlGeometry.RELEASED;
  }

  /** 一次翻页结束或取消：回到固定轨迹。 */
  clearCorner(): void {
    this.mode = ReaderGlCurlGeometry.TRAJECTORY;
    this.lastProgress = -1;
    this.grabY = -1;
  }

  /**
   * 松手后页角还要走的路程占全程（纸边到终点）的比例，供页面按剩余的可见行程定补完时长。
   * 没有松手位置时返回 -1。
   */
  remainingFraction(width: number): number {
    if (this.mode !== ReaderGlCurlGeometry.RELEASED || this.lastProgress < 0) return -1;
    const safeWidth = Math.max(1, width);
    const endX = this.endX(safeWidth);
    return Math.max(0, Math.min(1, (this.releaseX - endX) / (safeWidth - endX)));
  }

  /** 进度 0 为平铺，1 为整页卷出窗口；direction > 0 往后翻（页角在右），< 0 往前翻（页角在左）。 */
  fold(width: number, height: number, progress: number, direction: number, region: number): ReaderGlCurlFold {
    const w = Math.max(1, width);
    const h = Math.max(1, height);
    const p = Math.max(0, Math.min(1, progress));
    const flat: ReaderGlCurlFold = { active: false, p0x: 0, p0y: 0, nx: 1, ny: 0, radius: 1 };
    if (p <= 0.001) return flat;
    const mirrored = direction < 0;
    const corner = region !== ReaderGlCurlGeometry.REGION_MIDDLE || this.grabY < 0;
    const grabX = w;
    const grabY = region === ReaderGlCurlGeometry.REGION_TOP ? 0 :
      (!corner ? Math.max(0, Math.min(h, this.grabY)) : h);
    const target = this.cornerTarget(w, h, p, mirrored, corner, grabX, grabY);
    let vx = grabX - target.x;
    let vy = grabY - target.y;
    if (!corner) {
      const maxTilt = Math.abs(vx) * this.tiltLimit;
      vy = Math.max(-maxTilt, Math.min(maxTilt, vy));
    }
    const distance = Math.hypot(vx, vy);
    if (distance < 0.5) return flat;
    const nx = vx / distance;
    const ny = vy / distance;
    // 半径随页角被拉开的距离长大（拉开距离的 16%，最多页宽的 12%）。一开始就用满半径时，折线被推得离页角
    // 很远，右边缘跟着卷起一长条，像整条边在卷而不是捏起一个角。
    const radius = Math.max(0.5, Math.min(this.radiusRatio * w, distance * this.radiusGrowth));
    const cornerDistance = (distance + Math.PI * radius) / 2;
    const p0x = grabX - nx * cornerDistance;
    const p0y = grabY - ny * cornerDistance;
    return {
      active: true,
      p0x: mirrored ? w - p0x : p0x,
      p0y: p0y,
      nx: mirrored ? -nx : nx,
      ny: ny,
      radius: radius
    };
  }

  /**
   * 页角最终要落到的位置（镜像坐标系）：折线竖直时圆柱的弧顶刚好离开左边缘。
   * 弧顶在折线外侧 R 处，折线距页角 (D + πR) / 2，解出 D ≥ 2W + 2R − πR，再多走 8vp 余量。
   */
  private endX(width: number): number {
    const radius = this.radiusRatio * width;
    return width - (2 * width + 2 * radius - Math.PI * radius) - 8;
  }

  private cornerTarget(width: number, height: number, progress: number, mirrored: boolean, corner: boolean,
    grabX: number, grabY: number): { x: number, y: number } {
    const endX = this.endX(width);
    let x = grabX;
    let y = grabY;
    if (this.mode === ReaderGlCurlGeometry.TRAJECTORY) {
      // 点按翻页：页角沿进度匀速走完，抓页角时顺带抬起一段弧线，折线先斜后正，像手捏着角翻过去。
      x = grabX + (endX - grabX) * progress;
      if (corner) {
        const lift = Math.sin(progress * Math.PI) * this.arcLift * height;
        y = grabY <= 0 ? grabY + lift : grabY - lift;
      }
      return { x: x, y: y };
    }
    if (this.mode === ReaderGlCurlGeometry.DRAGGING) {
      const fingerX = mirrored ? width - this.fingerX : this.fingerX;
      // 拖动刚开始时页角还在纸边，随拖动距离平滑移到手指下方，起手瞬间整张纸不会跳到手指处。
      this.followReached = Math.max(this.followReached, Math.min(1, progress * width / this.followRamp));
      const ramp = this.followReached;
      const follow = ramp * ramp * (3 - 2 * ramp);
      x = Math.min(grabX - 0.5, grabX + (fingerX - grabX) * follow);
      y = Math.max(0, Math.min(height, grabY + (this.fingerY - grabY) * follow));
      if (!corner) {
        const maxTilt = (grabX - x) * this.tiltLimit;
        y = Math.max(grabY - maxTilt, Math.min(grabY + maxTilt, y));
      }
      // 纸不能被拉长：书脊一侧的两个页角不能被掀起，页角到它们的距离不超过原来的距离。
      for (let pass = 0; pass < 2; pass++) {
        for (let index = 0; index < 2; index++) {
          const spineY = index === 0 ? 0 : height;
          const limit = Math.hypot(grabX, grabY - spineY);
          const distance = Math.hypot(x, y - spineY);
          if (distance > limit) {
            x = x * limit / distance;
            y = spineY + (y - spineY) * limit / distance;
          }
        }
      }
    } else if (progress >= this.releaseProgress) {
      // 松手后继续翻出：从松手位置直线滑到终点，折线逐渐立直并扫出窗口。
      const t = Math.max(0, Math.min(1, (progress - this.releaseProgress) / Math.max(0.0001, 1 - this.releaseProgress)));
      x = this.releaseX + (endX - this.releaseX) * t;
      y = this.releaseY + (grabY - this.releaseY) * t;
    } else {
      // 松手后弹回：从松手位置回到抓取点。
      const t = Math.max(0, Math.min(1, progress / Math.max(0.0001, this.releaseProgress)));
      x = grabX + (this.releaseX - grabX) * t;
      y = grabY + (this.releaseY - grabY) * t;
    }
    this.lastX = x;
    this.lastY = y;
    this.lastProgress = progress;
    return { x: x, y: y };
  }
}
