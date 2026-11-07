import worker, { ThreadWorkerGlobalScope, MessageEvents } from '@ohos.worker';
import { fileIo as fs } from '@kit.CoreFileKit';
import { OfflineTts, OfflineTtsConfig, TtsInput, TtsOutput } from 'sherpa_onnx';

// 离线神经网络音色的合成线程。模型加载是几百 MB 的同步 IO 加初始化，放主线程会卡住界面。
// 只用同步 generate：sherpa-onnx 的 generateAsync 带逐段回调时，线程安全回调在拷贝音频时访问过
// 已释放的内存（真机 SIGSEGV）。请求排队逐条处理，条与条之间让出事件循环，取消消息才能及时生效。

interface LocalTtsRequest {
  type: string;
  id?: number;
  kind?: string;
  model?: string;
  vocoder?: string;
  voices?: string;
  tokens?: string;
  lexicon?: string;
  dataDir?: string;
  ruleFsts?: string;
  threads?: number;
  text?: string;
  speed?: number;
  sid?: number;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
let tts: OfflineTts | null = null;
let queue: LocalTtsRequest[] = [];
let scheduled: boolean = false;

// 主线程传来的都是绝对路径（多个词典/规则用逗号连接），这里只按模型结构填进对应的配置。
function buildConfig(request: LocalTtsRequest): OfflineTtsConfig {
  const config = new OfflineTtsConfig();
  config.model.numThreads = request.threads || 2;
  config.model.debug = false;
  const tokens = request.tokens || '';
  const lexicon = request.lexicon || '';
  const dataDir = request.dataDir || '';
  if (request.kind === 'matcha') {
    config.model.matcha.acousticModel = request.model || '';
    config.model.matcha.vocoder = request.vocoder || '';
    config.model.matcha.tokens = tokens;
    config.model.matcha.lexicon = lexicon;
    config.model.matcha.dataDir = dataDir;
  } else if (request.kind === 'kokoro') {
    config.model.kokoro.model = request.model || '';
    config.model.kokoro.voices = request.voices || '';
    config.model.kokoro.tokens = tokens;
    config.model.kokoro.lexicon = lexicon;
    config.model.kokoro.dataDir = dataDir;
  } else {
    config.model.vits.model = request.model || '';
    config.model.vits.tokens = tokens;
    config.model.vits.lexicon = lexicon;
    config.model.vits.dataDir = dataDir;
  }
  config.ruleFsts = (request.ruleFsts || '').split(',')
    .filter((path: string): boolean => !!path && fs.accessSync(path)).join(',');
  return config;
}

function handleInit(request: LocalTtsRequest): void {
  const startedAt = Date.now();
  try {
    tts = new OfflineTts(buildConfig(request));
    workerPort.postMessage({ type: 'init-done', ms: Date.now() - startedAt, sampleRate: tts.sampleRate });
  } catch (error) {
    tts = null;
    workerPort.postMessage({ type: 'init-error', message: (error as Error).message || String(error) });
  }
}

function processNext(): void {
  scheduled = false;
  const request = queue.shift();
  if (!request) return;
  const engine = tts;
  if (!engine) {
    workerPort.postMessage({ type: 'error', id: request.id, message: '离线音色未加载' });
  } else {
    try {
      const input = new TtsInput();
      input.text = request.text || '';
      input.sid = request.sid || 0;
      input.speed = request.speed || 1;
      input.enableExternalBuffer = false;
      const output: TtsOutput = engine.generate(input);
      const samples = new Float32Array(output.samples);
      workerPort.postMessage({ type: 'audio', id: request.id, samples: samples, sampleRate: output.sampleRate },
        [samples.buffer]);
    } catch (error) {
      workerPort.postMessage({ type: 'error', id: request.id, message: (error as Error).message || String(error) });
    }
  }
  schedule();
}

function schedule(): void {
  if (scheduled || queue.length === 0) return;
  scheduled = true;
  setTimeout(processNext, 1);
}

workerPort.onmessage = (event: MessageEvents): void => {
  const request = event.data as LocalTtsRequest;
  if (request.type === 'init') {
    handleInit(request);
  } else if (request.type === 'synthesize') {
    queue.push(request);
    schedule();
  } else if (request.type === 'cancel') {
    // 正在合成的那一条拦不住，排队中的直接丢弃并告知主线程。
    for (const pending of queue) {
      workerPort.postMessage({ type: 'cancelled', id: pending.id });
    }
    queue = [];
  }
};
