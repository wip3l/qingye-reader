/** Time-based motion in vp: delayed frames never cause a jump through unread text. */
export class ReaderAutoScrollClock {
  private lastFrame: number = -1;

  static normalizeSpeed(value: number): number {
    return Number.isFinite(value) ? Math.max(6, Math.min(60, Math.round(value / 2) * 2)) : 20;
  }

  reset(): void {
    this.lastFrame = -1;
  }

  advance(now: number, linesPerMinute: number, lineHeight: number, ready: boolean): number {
    const previous = this.lastFrame;
    this.lastFrame = now;
    if (!ready || previous < 0 || !Number.isFinite(lineHeight) || lineHeight <= 0) return 0;
    const elapsed = Math.max(0, Math.min(64, now - previous));
    return elapsed * ReaderAutoScrollClock.normalizeSpeed(linesPerMinute) * lineHeight / 60000;
  }
}
