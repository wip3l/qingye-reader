/**
 * 有声书按书跳过片头片尾。秒数和倍速一样存在书籍变量里，只在本机，不随云同步；规则集中在这里：
 * - 从章首（位置 0）开始播放时，直接从片头之后开始；续播、拖进度条到片头里面都不跳。
 * - 正常播放越过“总时长 − 片尾”时直接进下一章；最后一章、拖动或快进越过的不算。
 * - 章节总时长不到“片头 + 片尾 + MIN_BODY_MS”时这一章不跳，免得短章被整段跳过。
 */
export class AudioSkipRange {
  static readonly HEAD_KEY: string = 'audioSkipHead';
  static readonly TAIL_KEY: string = 'audioSkipTail';
  static readonly MAX_SECONDS: number = 300;
  static readonly STEP_SECONDS: number = 5;
  static readonly MIN_BODY_MS: number = 30000;
  /** 播放面板、耳机和通知栏的前进/后退一次移动的时长。 */
  static readonly SEEK_STEP_MS: number = 15000;
  /**
   * 判断“正常播放”时给的余量：两次进度回调之间，位置最多前进“经过的时间 × 倍速 + 这个余量”。
   * 按实际经过的时间算而不是固定阈值，息屏后回调变稀时照样能跳片尾；拖动、快进一瞬间前进很多，不算。
   */
  private static readonly NATURAL_SLACK_MS: number = 2000;

  static normalize(seconds: number): number {
    if (!Number.isFinite(seconds)) return 0;
    return Math.max(0, Math.min(AudioSkipRange.MAX_SECONDS, Math.round(seconds)));
  }

  static parse(value: string | undefined): number {
    return AudioSkipRange.normalize(Number(value || 0));
  }

  /** 这一章够不够长、能不能跳。总时长未知时不跳。 */
  static fits(durationMs: number, headSeconds: number, tailSeconds: number): boolean {
    return durationMs > 0 && durationMs >= (headSeconds + tailSeconds) * 1000 + AudioSkipRange.MIN_BODY_MS;
  }

  /** 正常播放时这一次进度回调是否刚越过片尾的起点。 */
  static crossedTail(previousMs: number, positionMs: number, durationMs: number, tailSeconds: number,
    elapsedMs: number, speed: number): boolean {
    if (tailSeconds <= 0 || durationMs <= 0) return false;
    const tailStart = durationMs - tailSeconds * 1000;
    const maxAdvance = Math.max(0, elapsedMs) * Math.max(1, speed || 1) + AudioSkipRange.NATURAL_SLACK_MS;
    return previousMs < tailStart && positionMs >= tailStart && positionMs - previousMs <= maxAdvance;
  }

  /** 面板上显示的时长：m:ss。 */
  static label(seconds: number): string {
    const total = AudioSkipRange.normalize(seconds);
    const minutes = Math.floor(total / 60);
    const secs = total % 60;
    return `${minutes}:${secs < 10 ? '0' : ''}${secs}`;
  }
}
