import worker, { ThreadWorkerGlobalScope, MessageEvents } from '@ohos.worker';
import {
  OfflinePunctuation, OfflinePunctuationConfig, OfflineRecognizer, OfflineRecognizerConfig, OfflineRecognizerResult
} from 'sherpa_onnx';
import subtitleAudio from 'libsubtitle_audio.so';
import { SubtitleChar, SubtitleCue, SubtitleText } from '../core/subtitle/SubtitleText';

// 听书字幕的识别线程：解码一段本地音频 → Zipformer CTC 识别 → 标点 → 切成带时间的行。
// 模型几百 MB，加载和推理都是同步的，只能放在 Worker 里。一次只处理一段，主线程按顺序发。

interface SubtitleWorkerRequest {
  type: string;
  id?: number;
  model?: string;
  tokens?: string;
  punct?: string;
  threads?: number;
  path?: string;
  /** 这一段负责的范围；窗口前后各多解 padMs 给边界的字补上下文。 */
  startMs?: number;
  endMs?: number;
  padMs?: number;
}

class SubtitleWorkerReply {
  type: string = '';
  id: number = 0;
  message: string = '';
  cues: SubtitleCue[] = [];
  durationMs: number = 0;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
let recognizer: OfflineRecognizer | null = null;
let punctuation: OfflinePunctuation | null = null;

function reply(message: SubtitleWorkerReply): void {
  workerPort.postMessage(message);
}

function load(request: SubtitleWorkerRequest): void {
  const result = new SubtitleWorkerReply();
  try {
    const config = new OfflineRecognizerConfig();
    config.modelConfig.zipformerCtc.model = request.model || '';
    config.modelConfig.tokens = request.tokens || '';
    config.modelConfig.numThreads = request.threads || 2;
    config.modelConfig.debug = false;
    config.featConfig.sampleRate = 16000;
    config.featConfig.featureDim = 80;
    recognizer = new OfflineRecognizer(config);
    const punctConfig = new OfflinePunctuationConfig();
    punctConfig.model.ctTransformer = request.punct || '';
    punctConfig.model.numThreads = 1;
    punctConfig.model.debug = false;
    punctuation = new OfflinePunctuation(punctConfig);
    result.type = 'loaded';
  } catch (error) {
    recognizer = null;
    punctuation = null;
    result.type = 'error';
    result.message = `subtitle_load: ${(error as Error)?.message || error}`;
  }
  reply(result);
}

function recognize(request: SubtitleWorkerRequest): void {
  const result = new SubtitleWorkerReply();
  result.id = request.id || 0;
  try {
    if (!recognizer) throw new Error('subtitle_not_loaded');
    const startMs = Math.max(0, request.startMs || 0);
    const endMs = Math.max(startMs, request.endMs || 0);
    const padMs = Math.max(0, request.padMs || 0);
    const windowStart = Math.max(0, startMs - padMs);
    const pcm = subtitleAudio.decode(request.path || '', windowStart, endMs + padMs - windowStart);
    result.durationMs = pcm.durationMs;
    if (pcm.samples.length >= 1600) {
      const stream = recognizer.createStream();
      stream.acceptWaveform({ samples: pcm.samples, sampleRate: pcm.sampleRate });
      recognizer.decode(stream);
      const text: OfflineRecognizerResult = recognizer.getResult(stream);
      let chars: SubtitleChar[] = SubtitleText.decodeTokens(text.tokens || [], text.timestamps || [], pcm.startMs);
      if (chars.length > 0 && punctuation) {
        try {
          chars = SubtitleText.applyPunctuation(chars, punctuation.addPunct(SubtitleText.plainText(chars)));
        } catch (error) {
          console.warn('[SubtitleWorker] punctuation failed:', error);
        }
      }
      result.cues = SubtitleText.buildCues(SubtitleText.clip(chars, startMs, endMs));
    }
    result.type = 'result';
  } catch (error) {
    result.type = 'failed';
    result.message = (error as Error)?.message || `${error}`;
  }
  reply(result);
}

workerPort.onmessage = (event: MessageEvents): void => {
  const request = event.data as SubtitleWorkerRequest;
  if (request.type === 'load') load(request);
  else if (request.type === 'recognize') recognize(request);
};
