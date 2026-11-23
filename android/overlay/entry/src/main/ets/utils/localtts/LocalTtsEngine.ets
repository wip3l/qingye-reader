// utils/localtts/LocalTtsEngine.ets 的安卓实现（平台层之外少数整文件替换之一，见 docs/android-build.md）。
//
// 鸿蒙上离线音色由 sherpa_onnx 的 NAPI 包在合成线程里跑，那个包只有鸿蒙的原生库。安卓上改经原生桥
// （SherpaBridge.java）用 sherpa-onnx 的安卓 Java 接口；对外接口、模型校验、加载标记和空闲释放与鸿蒙实现相同。
import fs from '@ohos.file.fs';
import bridge from '@arkui-x.bridge';
import { HttpTtsAudio } from '../HttpTtsReader';
import { LocalTtsModel, LocalTtsModels } from './LocalTtsModels';

/** 与 SherpaBridge.NAME 一致。 */
const SHERPA_BRIDGE_NAME = 'io.legado.read/sherpa';
const CANCELLED_NAME: string = 'LocalTtsCancelledError';

function cancelledError(): Error {
  const error = new Error('离线朗读已停止');
  error.name = CANCELLED_NAME;
  return error;
}

let sherpaBridge: bridge.BridgeObject | null = null;

async function call(method: string, ...args: string[]): Promise<Record<string, Object>> {
  if (!sherpaBridge) sherpaBridge = bridge.createBridge(SHERPA_BRIDGE_NAME);
  const raw = await sherpaBridge.callMethod(method, ...args);
  return JSON.parse(String(raw || '{}')) as Record<string, Object>;
}

function readPcm(path: string): ArrayBuffer {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size = fs.statSync(path).size;
    const buffer = new ArrayBuffer(size);
    let read = 0;
    while (read < size) {
      const count = fs.readSync(file.fd, buffer, { offset: read, length: size - read });
      if (count <= 0) break;
      read += count;
    }
    return read === size ? buffer : buffer.slice(0, read);
  } finally {
    fs.closeSync(file);
  }
}

export class LocalTtsEngine {
  private static readonly THREADS: number = 2;
  private static readonly IDLE_RELEASE_MS: number = 90000;
  /** 已加载模型的目录。音色包里的几个音色共用一个模型，换音色只换 sid，不重新加载。 */
  private static modelId: string = '';
  private static initPromise: Promise<number> | null = null;
  private static generation: number = 0;
  private static nextId: number = 0;
  private static idleTimer: number = -1;
  private static loadingDir: string = '';
  private static cacheDir: string = '';

  static async synthesize(model: LocalTtsModel, text: string, speed: number): Promise<HttpTtsAudio> {
    if (!LocalTtsModels.memberAllowed()) throw new Error(LocalTtsModels.MEMBER_REQUIRED);
    LocalTtsEngine.cancelIdleRelease();
    await LocalTtsEngine.ensureLoaded(model);
    const generation = LocalTtsEngine.generation;
    const id = ++LocalTtsEngine.nextId;
    const path = `${LocalTtsEngine.pcmDir()}/local-tts-${id}.pcm`;
    // 语速交给模型（拉长/缩短音长），不改音高；返回的音频不用再变速。
    const result = await call('synthesize', text, String(model.sid),
      String(Math.max(0.5, Math.min(3, speed || 1))), path);
    // 首句合成成功（或明确报错）才撤掉 loading 标记：不兼容的模型也可能在第一次合成时把进程带崩。
    if (LocalTtsEngine.loadingDir) {
      LocalTtsModels.clearLoading(LocalTtsEngine.loadingDir);
      LocalTtsEngine.loadingDir = '';
    }
    try {
      if (generation !== LocalTtsEngine.generation || result['cancelled']) throw cancelledError();
      if (result['error']) throw new Error(`离线合成失败：${String(result['error'])}`);
      const audio = new HttpTtsAudio();
      audio.pcm = readPcm(String(result['path']));
      audio.sampleRate = Number(result['sampleRate']) || 22050;
      audio.speed = 1;
      return audio;
    } finally {
      try { fs.unlinkSync(path); } catch (_) { /* 缓存目录会被系统清理 */ }
      LocalTtsEngine.scheduleIdleRelease();
    }
  }

  /** 停止朗读时调用：排队中的请求全部作废，正在合成的那一条结果会被丢弃。 */
  static cancelAll(): void {
    LocalTtsEngine.generation++;
    call('cancel').catch(() => {});
    LocalTtsEngine.scheduleIdleRelease();
  }

  static release(): void {
    LocalTtsEngine.resetState();
    call('unload').catch(() => {});
  }

  /** 只清本地状态。换模型时不发 release：原生侧 load 会先释放旧模型，异步的 release 若排在 load 之后会把新模型也放掉。 */
  private static resetState(): void {
    LocalTtsEngine.cancelIdleRelease();
    LocalTtsEngine.generation++;
    LocalTtsEngine.initPromise = null;
    LocalTtsEngine.modelId = '';
    // 正常释放说明进程没被带崩，不能把模型误判为损坏。
    if (LocalTtsEngine.loadingDir) LocalTtsModels.clearLoading(LocalTtsEngine.loadingDir);
    LocalTtsEngine.loadingDir = '';
  }

  static isCancelled(error: Error): boolean {
    return error?.name === CANCELLED_NAME;
  }

  private static pcmDir(): string {
    if (!LocalTtsEngine.cacheDir) LocalTtsEngine.cacheDir = getContext().cacheDir;
    return `${LocalTtsEngine.cacheDir}/local-tts`;
  }

  private static ensureLoaded(model: LocalTtsModel): Promise<number> {
    if (LocalTtsEngine.initPromise && LocalTtsEngine.modelId === LocalTtsModels.modelPath(model)) {
      return LocalTtsEngine.initPromise;
    }
    LocalTtsEngine.resetState();
    // 坏文件会让原生层直接 abort 进程，加载前必须确认文件完整。
    const dir = LocalTtsModels.modelPath(model);
    if (!LocalTtsModels.verifyDir(dir, model)) {
      LocalTtsModels.refreshInstalledPaths();
      return Promise.reject(new Error('离线音色文件不完整，请在音色管理里重新下载'));
    }
    const at = (name: string): string => name ? `${dir}/${name}` : '';
    const request: Record<string, Object> = {
      'kind': model.kind,
      'model': at(model.modelFile),
      'vocoder': at(model.vocoderFile),
      'voices': at(model.voicesFile),
      'tokens': at('tokens.txt'),
      'lexicon': model.lexicons.map((name: string): string => at(name)).join(','),
      'dataDir': at(model.dataDir),
      'ruleFsts': model.ruleFsts.map((name: string): string => at(name)).join(','),
      'noiseScale': model.noiseScale,
      'noiseScaleW': model.noiseScaleW,
      'threads': LocalTtsEngine.THREADS
    };
    LocalTtsEngine.modelId = dir;
    LocalTtsEngine.loadingDir = dir;
    LocalTtsModels.markLoading(dir);
    const promise = call('load', JSON.stringify(request)).then((result: Record<string, Object>): number => {
      if (result['error']) throw new Error(`离线音色加载失败：${String(result['error'])}`);
      console.info(`[LocalTts] model loaded in ${result['ms']}ms, sampleRate=${result['sampleRate']}`);
      return Number(result['sampleRate']) || 22050;
    });
    LocalTtsEngine.initPromise = promise;
    promise.catch((error: Error): void => {
      console.error('[LocalTts] model load failed:', error.message);
      if (LocalTtsEngine.initPromise === promise) LocalTtsEngine.resetState();
    });
    return promise;
  }

  private static scheduleIdleRelease(): void {
    LocalTtsEngine.cancelIdleRelease();
    if (!LocalTtsEngine.initPromise) return;
    LocalTtsEngine.idleTimer = setTimeout((): void => {
      LocalTtsEngine.idleTimer = -1;
      LocalTtsEngine.release();
    }, LocalTtsEngine.IDLE_RELEASE_MS);
  }

  private static cancelIdleRelease(): void {
    if (LocalTtsEngine.idleTimer >= 0) clearTimeout(LocalTtsEngine.idleTimer);
    LocalTtsEngine.idleTimer = -1;
  }
}
