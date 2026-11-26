import { taskpool } from '@kit.ArkTS';
import subtitleAudio from 'libsubtitle_audio.so';

/**
 * 把一个压缩音频文件（MP3、AAC 等）整段解成 16 位单声道 PCM。原生解码是同步的，放在 TaskPool 里跑。
 * 朗读一段话的音频只有几秒到几十秒；上限 5 分钟，超出的部分不要。
 */
@Concurrent
function decodeTtsAudioFile(path: string, sampleRate: number): ArrayBuffer {
  const spanMs = 60000;
  const parts: Int16Array[] = [];
  let total = 0;
  for (let startMs = 0; startMs < 5 * spanMs; startMs += spanMs) {
    const decoded = subtitleAudio.decode(path, startMs, spanMs, sampleRate);
    const samples = decoded.samples;
    if (samples.length === 0) break;
    const pcm = new Int16Array(samples.length);
    for (let index = 0; index < samples.length; index++) {
      const value = Math.round(samples[index] * 32767);
      pcm[index] = value > 32767 ? 32767 : (value < -32768 ? -32768 : value);
    }
    parts.push(pcm);
    total += pcm.length;
    // 时长未知时靠“这一段没解满”判断结束。
    if (decoded.durationMs > 0 ? startMs + spanMs >= decoded.durationMs : samples.length < sampleRate * (spanMs / 1000) * 0.98) break;
  }
  const joined = new Int16Array(total);
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return joined.buffer;
}

export class TtsAudioDecodeTask {
  /** 解不出来时抛错（文件损坏、格式不支持等）。 */
  static async decode(path: string, sampleRate: number): Promise<ArrayBuffer> {
    const result = await taskpool.execute(decodeTtsAudioFile, path, sampleRate);
    return result as ArrayBuffer;
  }
}
