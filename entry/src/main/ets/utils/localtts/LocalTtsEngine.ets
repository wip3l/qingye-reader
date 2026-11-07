import worker, { MessageEvents, ErrorEvent } from '@ohos.worker';
import { HttpTtsAudio } from '../HttpTtsReader';
import { LocalTtsModel, LocalTtsModels } from './LocalTtsModels';

interface LocalTtsReply {
  type: string;
  id?: number;
  message?: string;
  sampleRate?: number;
  samples?: Float32Array;
  ms?: number;
}

class LocalTtsWorkerRequest {
  type: string = '';
  id: number = 0;
  kind: string = '';
  model: string = '';
  vocoder: string = '';
  voices: string = '';
  tokens: string = '';
  lexicon: string = '';
  dataDir: string = '';
  ruleFsts: string = '';
  threads: number = 2;
  text: string = '';
  speed: number = 1;
  sid: number = 0;

  constructor(type: string) {
    this.type = type;
  }
}

class PendingSynthesis {
  resolve: (audio: HttpTtsAudio) => void;
  reject: (error: Error) => void;

  constructor(resolve: (audio: HttpTtsAudio) => void, reject: (error: Error) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

const CANCELLED_NAME: string = 'LocalTtsCancelledError';

function cancelledError(): Error {
  const error = new Error('离线朗读已停止');
  error.name = CANCELLED_NAME;
  return error;
}

/**
 * 离线音色的进程单例。模型常驻会占一百多 MB，所以只在朗读时加载，停下 90 秒后结束线程释放内存。
 * 2 线程在真机上已是实时的 5 倍多（RTF≈0.18），再多线程主要是耗电。
 */
export class LocalTtsEngine {
  private static readonly THREADS: number = 2;
  private static readonly IDLE_RELEASE_MS: number = 90000;
  private static thread: worker.ThreadWorker | null = null;
  private static modelId: string = '';
  private static initPromise: Promise<number> | null = null;
  private static initResolve: ((sampleRate: number) => void) | null = null;
  private static initReject: ((error: Error) => void) | null = null;
  private static pending: Map<number, PendingSynthesis> = new Map<number, PendingSynthesis>();
  private static nextId: number = 0;
  private static idleTimer: number = -1;
  private static loadingDir: string = '';

  static async synthesize(model: LocalTtsModel, text: string, speed: number): Promise<HttpTtsAudio> {
    if (!LocalTtsModels.memberAllowed()) throw new Error(LocalTtsModels.MEMBER_REQUIRED);
    LocalTtsEngine.cancelIdleRelease();
    await LocalTtsEngine.ensureLoaded(model);
    const thread = LocalTtsEngine.thread;
    if (!thread) throw new Error('离线音色未加载');
    const id = ++LocalTtsEngine.nextId;
    const audio = await new Promise<HttpTtsAudio>((resolve, reject): void => {
      LocalTtsEngine.pending.set(id, new PendingSynthesis(resolve, reject));
      const request = new LocalTtsWorkerRequest('synthesize');
      request.id = id;
      request.text = text;
      request.sid = model.sid;
      // 语速交给模型（拉长/缩短音长），不改音高；返回的音频不用再变速。
      request.speed = Math.max(0.5, Math.min(2.5, speed || 1));
      thread.postMessage(request);
    });
    LocalTtsEngine.scheduleIdleRelease();
    return audio;
  }

  /** 停止朗读时调用：排队中的请求全部作废，正在合成的那一条结果会被丢弃。 */
  static cancelAll(): void {
    if (LocalTtsEngine.thread && LocalTtsEngine.pending.size > 0) {
      LocalTtsEngine.thread.postMessage(new LocalTtsWorkerRequest('cancel'));
    }
    LocalTtsEngine.rejectAll(cancelledError());
    LocalTtsEngine.scheduleIdleRelease();
  }

  static release(): void {
    LocalTtsEngine.cancelIdleRelease();
    LocalTtsEngine.rejectAll(cancelledError());
    if (LocalTtsEngine.initReject) LocalTtsEngine.initReject(cancelledError());
    LocalTtsEngine.initPromise = null;
    LocalTtsEngine.initResolve = null;
    LocalTtsEngine.initReject = null;
    LocalTtsEngine.modelId = '';
    // 正常释放说明进程没被带崩，不能把模型误判为损坏。
    if (LocalTtsEngine.loadingDir) LocalTtsModels.clearLoading(LocalTtsEngine.loadingDir);
    LocalTtsEngine.loadingDir = '';
    const thread = LocalTtsEngine.thread;
    LocalTtsEngine.thread = null;
    if (thread) {
      try { thread.terminate(); } catch (_) {}
    }
  }

  static isCancelled(error: Error): boolean {
    return error?.name === CANCELLED_NAME;
  }

  private static ensureLoaded(model: LocalTtsModel): Promise<number> {
    if (LocalTtsEngine.initPromise && LocalTtsEngine.modelId === model.id) return LocalTtsEngine.initPromise;
    LocalTtsEngine.release();
    // 坏文件会让原生层直接 abort 进程，加载前必须确认文件完整。
    const dir = LocalTtsModels.modelPath(model);
    if (!LocalTtsModels.verifyDir(dir, model)) {
      LocalTtsModels.refreshInstalledPaths();
      return Promise.reject(new Error('离线音色文件不完整，请在音色管理里重新下载'));
    }
    const thread = new worker.ThreadWorker('../../workers/LocalTtsWorker.ets', { name: 'LocalTts' });
    LocalTtsEngine.thread = thread;
    LocalTtsEngine.modelId = model.id;
    LocalTtsEngine.initPromise = new Promise<number>((resolve, reject): void => {
      LocalTtsEngine.initResolve = resolve;
      LocalTtsEngine.initReject = reject;
    });
    thread.onmessage = (event: MessageEvents): void => LocalTtsEngine.onReply(thread, event.data as LocalTtsReply);
    thread.onerror = (error: ErrorEvent): void => {
      if (LocalTtsEngine.thread !== thread) return;
      console.error('[LocalTts] worker error:', error.message);
      const failure = new Error(`离线朗读异常：${error.message}`);
      if (LocalTtsEngine.initReject) LocalTtsEngine.initReject(failure);
      LocalTtsEngine.rejectAll(failure);
      LocalTtsEngine.release();
    };
    const request = new LocalTtsWorkerRequest('init');
    const at = (name: string): string => name ? `${dir}/${name}` : '';
    request.kind = model.kind;
    request.model = at(model.modelFile);
    request.vocoder = at(model.vocoderFile);
    request.voices = at(model.voicesFile);
    request.tokens = at('tokens.txt');
    request.lexicon = model.lexicons.map((name: string): string => at(name)).join(',');
    request.dataDir = at(model.dataDir);
    request.ruleFsts = model.ruleFsts.map((name: string): string => at(name)).join(',');
    request.threads = LocalTtsEngine.THREADS;
    LocalTtsEngine.loadingDir = dir;
    LocalTtsModels.markLoading(dir);
    thread.postMessage(request);
    const promise = LocalTtsEngine.initPromise;
    promise.catch((): void => {
      if (LocalTtsEngine.thread === thread) LocalTtsEngine.release();
    });
    return promise;
  }

  private static onReply(thread: worker.ThreadWorker, reply: LocalTtsReply): void {
    if (LocalTtsEngine.thread !== thread) return;
    // 首句合成成功（或明确报错）才撤掉 loading 标记：不兼容的模型也可能在第一次合成时把进程带崩。
    if (LocalTtsEngine.loadingDir && reply.type !== 'init-done' && reply.type !== 'cancelled') {
      LocalTtsModels.clearLoading(LocalTtsEngine.loadingDir);
      LocalTtsEngine.loadingDir = '';
    }
    if (reply.type === 'init-done') {
      console.info(`[LocalTts] model loaded in ${reply.ms}ms, sampleRate=${reply.sampleRate}`);
      if (LocalTtsEngine.initResolve) LocalTtsEngine.initResolve(reply.sampleRate || 22050);
      LocalTtsEngine.initResolve = null;
      LocalTtsEngine.initReject = null;
      return;
    }
    if (reply.type === 'init-error') {
      console.error('[LocalTts] model load failed:', reply.message);
      if (LocalTtsEngine.initReject) LocalTtsEngine.initReject(new Error(`离线音色加载失败：${reply.message || ''}`));
      return;
    }
    const pending = LocalTtsEngine.pending.get(reply.id || 0);
    if (!pending) return;
    LocalTtsEngine.pending.delete(reply.id || 0);
    if (reply.type === 'audio' && reply.samples) {
      const audio = new HttpTtsAudio();
      audio.pcm = LocalTtsEngine.toPcm16(reply.samples);
      audio.sampleRate = reply.sampleRate || 22050;
      audio.speed = 1;
      pending.resolve(audio);
    } else if (reply.type === 'cancelled') {
      pending.reject(cancelledError());
    } else {
      pending.reject(new Error(`离线合成失败：${reply.message || ''}`));
    }
  }

  private static rejectAll(error: Error): void {
    const entries = Array.from(LocalTtsEngine.pending.values());
    LocalTtsEngine.pending.clear();
    for (const entry of entries) entry.reject(error);
  }

  private static scheduleIdleRelease(): void {
    LocalTtsEngine.cancelIdleRelease();
    if (!LocalTtsEngine.thread || LocalTtsEngine.pending.size > 0) return;
    LocalTtsEngine.idleTimer = setTimeout((): void => {
      LocalTtsEngine.idleTimer = -1;
      if (LocalTtsEngine.pending.size === 0) LocalTtsEngine.release();
    }, LocalTtsEngine.IDLE_RELEASE_MS);
  }

  private static cancelIdleRelease(): void {
    if (LocalTtsEngine.idleTimer >= 0) clearTimeout(LocalTtsEngine.idleTimer);
    LocalTtsEngine.idleTimer = -1;
  }

  private static toPcm16(samples: Float32Array): ArrayBuffer {
    const buffer = new ArrayBuffer(samples.length * 2);
    const view = new DataView(buffer);
    for (let i = 0; i < samples.length; i++) {
      const value = Math.max(-1, Math.min(1, samples[i]));
      view.setInt16(i * 2, Math.round(value * 32767), true);
    }
    return buffer;
  }
}
