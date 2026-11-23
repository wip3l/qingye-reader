import { audio } from '@kit.AudioKit';

/**
 * 朗读 PCM 输出线程（workers/PcmOutputWorker.ets）与主线程之间的消息。
 * 枚举值（AudioState、InterruptHint 等）按数字传。
 */
export interface PcmThreadRequest {
  /** create / call / write / hold */
  type: string;
  /** 输出编号，一个渲染器一个。 */
  id: number;
  callId?: number;
  /** call 的方法：start / pause / drain / setVolume / setLoudnessGain / setSpeed / shutdown */
  method?: string;
  value?: number;
  options?: audio.AudioRendererOptions;
  writeId?: number;
  data?: ArrayBuffer;
  hold?: boolean;
}

export interface PcmThreadEvent {
  /** reply / consumed / ts / state / interrupt */
  type: string;
  id: number;
  callId?: number;
  ok?: boolean;
  error?: string;
  code?: number;
  state?: number;
  /** 整段写完的数据编号。 */
  writeIds?: number[];
  /** 最后一块不满时补的静音帧数。 */
  padding?: number;
  framePos?: number;
  /** 取 framePos 时的 Date.now()，主线程据此外推。 */
  at?: number;
  unsupported?: boolean;
  hint?: number;
  force?: number;
}
