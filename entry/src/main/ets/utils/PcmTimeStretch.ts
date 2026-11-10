/**
 * 16 位单声道 PCM 变速不变调（WSOLA：波形相似重叠相加）。
 *
 * 系统音色和在线音色的合成接口只接受 0.5–2 倍语速，超过 2 倍时先按 2 倍合成，再用这里把剩余
 * 倍数压进音频；自定义音色返回 PCM 时也用它变速。直接重采样会把音调一起抬高，3 倍时几乎听不清。
 * 输出帧数约为输入帧数 / factor，调用方按输出长度换算播放进度。
 */
export class PcmTimeStretch {
  static stretch16BitMono(buffer: ArrayBuffer, sampleRate: number, factor: number): ArrayBuffer {
    if (!buffer || !(factor > 0) || Math.abs(factor - 1) < 0.01) return buffer;
    const input = new Int16Array(buffer, 0, Math.floor(buffer.byteLength / 2));
    const rate = Math.max(8000, Math.round(sampleRate || 16000));
    // 30ms 一帧、半帧步长、±10ms 内找最相似的接缝：语音上听感和开销比较均衡。
    const frameLength = Math.max(64, Math.round(rate * 0.03 / 2) * 2);
    const synthesisHop = frameLength / 2;
    const analysisHop = synthesisHop * factor;
    const tolerance = Math.max(8, Math.round(rate * 0.01));
    const inputLength = input.length;
    const outputLength = Math.max(1, Math.floor(inputLength / factor));
    if (inputLength < frameLength * 2) {
      return PcmTimeStretch.decimate(input, outputLength);
    }
    const window = new Float32Array(frameLength);
    for (let i = 0; i < frameLength; i++) {
      window[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / frameLength);
    }
    const accum = new Float32Array(outputLength + frameLength);
    const weight = new Float32Array(outputLength + frameLength);
    const lastStart = inputLength - frameLength;
    let previous = 0;
    for (let k = 0; k * synthesisHop < outputLength; k++) {
      let start = 0;
      if (k > 0) {
        const ideal = Math.min(lastStart, Math.round(k * analysisHop));
        const natural = previous + synthesisHop;
        start = natural + synthesisHop <= inputLength ?
          PcmTimeStretch.bestMatch(input, natural, synthesisHop,
            Math.max(0, ideal - tolerance), Math.min(lastStart, ideal + tolerance)) : ideal;
      }
      const outStart = k * synthesisHop;
      for (let i = 0; i < frameLength; i++) {
        const w = window[i];
        accum[outStart + i] += input[start + i] * w;
        weight[outStart + i] += w;
      }
      previous = start;
    }
    const output = new Int16Array(outputLength);
    for (let i = 0; i < outputLength; i++) {
      const w = weight[i];
      const value = w > 1e-6 ? accum[i] / w : 0;
      output[i] = value > 32767 ? 32767 : (value < -32768 ? -32768 : Math.round(value));
    }
    return output.buffer;
  }

  /** 在 [low, high] 里找开头一段最像 input[template, template+length) 的位置（先隔 2 粗找再细找）。 */
  private static bestMatch(input: Int16Array, template: number, length: number,
    low: number, high: number): number {
    if (high <= low) return Math.max(0, low);
    let best = low;
    let bestScore = -Infinity;
    for (let candidate = low; candidate <= high; candidate += 2) {
      const score = PcmTimeStretch.similarity(input, template, candidate, length);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    const coarse = best;
    for (let candidate = Math.max(low, coarse - 1); candidate <= Math.min(high, coarse + 1); candidate += 2) {
      const score = PcmTimeStretch.similarity(input, template, candidate, length);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  private static similarity(input: Int16Array, template: number, candidate: number, length: number): number {
    let dot = 0;
    let energy = 0;
    for (let i = 0; i < length; i += 2) {
      const b = input[candidate + i];
      dot += input[template + i] * b;
      energy += b * b;
    }
    return energy > 0 ? dot / Math.sqrt(energy) : 0;
  }

  private static decimate(input: Int16Array, outputLength: number): ArrayBuffer {
    const output = new Int16Array(outputLength);
    const step = input.length / outputLength;
    for (let i = 0; i < outputLength; i++) {
      output[i] = input[Math.min(input.length - 1, Math.floor(i * step))];
    }
    return output.buffer;
  }
}
