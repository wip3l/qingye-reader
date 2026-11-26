export interface SubtitlePcm {
  /** 单声道，采样率见 sampleRate（缺省 16 kHz）。 */
  samples: Float32Array;
  sampleRate: number;
  startMs: number;
  /** 整个文件的时长，未知时为 0。 */
  durationMs: number;
}

/**
 * 只在 Worker / TaskPool 里调用：同步解出 [startMs, startMs + spanMs) 这一段，最多 60 秒。
 * sampleRate 缺省 16000，可传 8000–48000。
 */
export const decode: (path: string, startMs: number, spanMs: number, sampleRate?: number) => SubtitlePcm;
/** 文件总时长（毫秒），未知时为 0。 */
export const probe: (path: string) => number;
