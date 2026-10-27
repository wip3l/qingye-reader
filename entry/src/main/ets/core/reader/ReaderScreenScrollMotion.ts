/**
 * 条漫点击翻屏的滚动曲线：只算每帧该滚的相对距离，由页面按屏幕刷新驱动。
 *
 * - 从静止开始时柔和起步、迅速加速，再用较长的尾段减速停下（与系统标准曲线 0.2,0,0,1 同形）。
 * - 动画途中再点一次，把没滚完的距离并进新目标，并让新曲线的起始速度接上当前速度，不会先顿一下。
 * - 累计滚动量最后正好等于目标距离，不因帧率或掉帧多滚少滚。
 * - 时间一律取帧回调给出的时刻：新动画从下一帧开始计时，不混用不同时钟。
 */
export class ReaderScreenScrollMotion {
  static readonly DURATION_MS: number = 420;
  private static readonly X1: number = 0.2;
  private static readonly X2: number = 0;
  private static readonly Y2: number = 1;

  private total: number = 0;
  private applied: number = 0;
  /** 小于 0 表示等第一帧再定起点。 */
  private startedAt: number = -1;
  private lastFrame: number = 0;
  private duration: number = ReaderScreenScrollMotion.DURATION_MS;
  private y1: number = 0;
  private running: boolean = false;

  isRunning(): boolean {
    return this.running;
  }

  /** 还没滚完的距离。 */
  remaining(): number {
    return this.running ? this.total - this.applied : 0;
  }

  /** 追加一段滚动；正在滚时与剩余距离合并并从最近一帧接着滚，保持速度连续。 */
  add(distance: number): void {
    const chained = this.running && this.startedAt >= 0;
    const velocity = chained ? this.velocity(this.lastFrame) : 0;
    const total = this.remaining() + distance;
    this.total = total;
    this.applied = 0;
    this.startedAt = chained ? this.lastFrame : -1;
    this.duration = ReaderScreenScrollMotion.DURATION_MS;
    // 曲线起点斜率 = y1 / x1（归一化）；换算成实际速度 v = 斜率 × total / duration。
    const slope = total !== 0 ? velocity * this.duration / total : 0;
    this.y1 = Math.max(0, Math.min(1, slope * ReaderScreenScrollMotion.X1));
    this.running = total !== 0;
  }

  /** 推进到 now，返回这一帧要滚动的相对距离；结束后 isRunning() 变为 false。 */
  step(now: number): number {
    if (!this.running) return 0;
    if (this.startedAt < 0) this.startedAt = now;
    this.lastFrame = now;
    const t = Math.max(0, Math.min(1, (now - this.startedAt) / this.duration));
    const target = t >= 1 ? this.total : this.total * this.progress(t);
    const delta = target - this.applied;
    this.applied = target;
    if (t >= 1) this.running = false;
    return delta;
  }

  stop(): void {
    this.running = false;
    this.total = 0;
    this.applied = 0;
    this.startedAt = -1;
  }

  /** 当前速度（距离/毫秒）。 */
  private velocity(now: number): number {
    const t = Math.max(0, Math.min(1, (now - this.startedAt) / this.duration));
    if (t >= 1) return 0;
    const h = 0.001;
    const a = this.progress(Math.max(0, t - h));
    const b = this.progress(Math.min(1, t + h));
    const span = Math.min(1, t + h) - Math.max(0, t - h);
    return (b - a) / span * this.total / this.duration;
  }

  /** 三次贝塞尔 (X1, y1, X2, Y2)：按时间比例 t 求进度。 */
  private progress(t: number): number {
    const x1 = ReaderScreenScrollMotion.X1;
    const x2 = ReaderScreenScrollMotion.X2;
    const y1 = this.y1;
    const y2 = ReaderScreenScrollMotion.Y2;
    const bezier = (u: number, p1: number, p2: number): number =>
      3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u;
    // x(u) 单调递增，二分求 u 稳定且足够快。
    let low = 0;
    let high = 1;
    for (let i = 0; i < 24; i++) {
      const mid = (low + high) / 2;
      if (bezier(mid, x1, x2) < t) low = mid;
      else high = mid;
    }
    return bezier((low + high) / 2, y1, y2);
  }
}
