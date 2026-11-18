/**
 * 朗读与有声书共用的倍速约定：0.5–3 倍，按 0.05 一格取整。
 * 播放面板、朗读设置页、阅读页朗读面板和首页“听”页签都从这里取范围、快捷档和显示文字。
 */
export class PlaybackSpeed {
  static readonly MIN: number = 0.5;
  static readonly MAX: number = 3;
  static readonly STEP: number = 0.05;
  /** 滑条下方的快捷档。 */
  static readonly PRESETS: number[] = [1.0, 1.25, 1.5, 2.0];

  static normalize(value: number): number {
    if (!Number.isFinite(value) || value <= 0) return 1;
    const stepped = Math.round(value / PlaybackSpeed.STEP) * PlaybackSpeed.STEP;
    return Math.max(PlaybackSpeed.MIN, Math.min(PlaybackSpeed.MAX, Math.round(stepped * 100) / 100));
  }

  static same(left: number, right: number): boolean {
    return Math.abs(left - right) < 0.01;
  }

  /** 不带单位的数字：整十分位写一位小数（1.0、1.5），否则两位（1.25）。 */
  static label(value: number): string {
    const hundredths = Math.round((Number.isFinite(value) ? value : 1) * 100);
    return (hundredths / 100).toFixed(hundredths % 10 === 0 ? 1 : 2);
  }

  /** 快捷档里比当前值大的下一档，已到最高档时回到第一档。 */
  static nextPreset(value: number): number {
    for (const preset of PlaybackSpeed.PRESETS) {
      if (preset > value + 0.01) return preset;
    }
    return PlaybackSpeed.PRESETS[0];
  }
}
