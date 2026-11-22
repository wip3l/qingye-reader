export interface SubtitlePcm {
  /** 16 kHz 单声道。 */
  samples: Float32Array;
  sampleRate: number;
  startMs: number;
  /** 整个文件的时长，未知时为 0。 */
  durationMs: number;
}

/** 只在 Worker 里调用：同步解出 [startMs, startMs + spanMs) 这一段，最多 60 秒。 */
export const decode: (path: string, startMs: number, spanMs: number) => SubtitlePcm;
/** 文件总时长（毫秒），未知时为 0。 */
export const probe: (path: string) => number;
