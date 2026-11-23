// platform/SpeechKit.ts 的安卓实现：用安卓系统朗读做一个 textToSpeech 的替身。
//
// 鸿蒙的系统朗读引擎把 PCM 经 onData 交给应用播放，朗读逻辑（SystemTtsReader）就是按这个模型写的。
// 这里经原生桥（TtsBridge.java）把每段文字合成到 WAV 文件，读出 PCM 后按同样的顺序回调
// onStart（带采样率等格式）→ onData → onComplete，SystemTtsReader 不用改。
// 只实现 SystemTtsReader 用到的接口；语音下载在安卓上由系统设置负责，这里直接报不支持。
import fs from '@ohos.file.fs';
import bridge from '@arkui-x.bridge';

/** 与 TtsBridge.NAME 一致。 */
const TTS_BRIDGE_NAME = 'io.legado.read/tts';
/** onData 每次交出的字节数，与鸿蒙引擎的分块大小同一量级。 */
const PCM_CHUNK_BYTES = 32 * 1024;
/** 安卓语音的编号从这里起，避开鸿蒙内置音色的编号（knownVoiceName 按编号认名字）。 */
const VOICE_ID_BASE = 100000;

let ttsBridge: bridge.BridgeObject | null = null;
let cacheDir = '';
const voiceNames: Map<number, string> = new Map<number, string>();

interface BridgeVoice {
  name: string;
  locale: string;
  network: boolean;
}

async function call(method: string, ...args: string[]): Promise<Record<string, Object>> {
  if (!ttsBridge) ttsBridge = bridge.createBridge(TTS_BRIDGE_NAME);
  const raw = await ttsBridge.callMethod(method, ...args);
  const result = JSON.parse(String(raw)) as Record<string, Object>;
  if (result['error']) throw new Error(String(result['error']));
  return result;
}

function voiceId(name: string): number {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) % 900000;
  return VOICE_ID_BASE + hash;
}

/** 解析 WAV，返回格式和 PCM 数据的范围。只认 PCM 编码（安卓系统朗读输出的就是它）。 */
function parseWav(data: ArrayBuffer): { sampleRate: number, sampleBit: number, channels: number,
  offset: number, length: number } {
  const view = new DataView(data);
  const tag = (at: number): string => String.fromCharCode(view.getUint8(at), view.getUint8(at + 1),
    view.getUint8(at + 2), view.getUint8(at + 3));
  if (data.byteLength < 12 || tag(0) !== 'RIFF' || tag(8) !== 'WAVE') throw new Error('系统朗读输出的不是 WAV');
  let sampleRate = 16000;
  let sampleBit = 16;
  let channels = 1;
  let pos = 12;
  while (pos + 8 <= data.byteLength) {
    const id = tag(pos);
    const size = view.getUint32(pos + 4, true);
    if (id === 'fmt ') {
      channels = view.getUint16(pos + 10, true);
      sampleRate = view.getUint32(pos + 12, true);
      sampleBit = view.getUint16(pos + 22, true);
    } else if (id === 'data') {
      const length = Math.min(size, data.byteLength - pos - 8);
      return { sampleRate, sampleBit, channels, offset: pos + 8, length };
    }
    pos += 8 + size + (size % 2);
  }
  throw new Error('WAV 里没有音频数据');
}

function readFile(path: string): ArrayBuffer {
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

/** 应用启动时由 EntryAbility 设置；合成的临时 WAV 放这里。 */
export function setSpeechCacheDir(dir: string): void {
  cacheDir = dir;
}

export namespace textToSpeech {
  export interface BusinessError {
    code?: number;
    message?: string;
    name?: string;
  }

  export type Callback<T> = (data: T) => void;
  export type ErrorCallback<T> = (err: T) => void;
  export type AsyncCallback<T> = (err: BusinessError | null | undefined, data: T) => void;

  export interface CreateEngineParams {
    language: string;
    person: number;
    online: number;
    extraParams?: Record<string, Object>;
  }

  export interface SpeakParams {
    requestId: string;
    extraParams?: Record<string, Object>;
  }

  export interface VoiceQuery {
    requestId: string;
    online: number;
    extraParams?: Record<string, Object>;
  }

  export interface VoiceInfo {
    language: string;
    person: number;
    style: string;
    gender: string;
    description: string;
    status?: string;
  }

  export interface VoiceDownload {
    requestId: string;
    language: string;
    person: number;
    style: string;
  }

  export interface DownloadResponse {
    requestId: string;
    on(type: string, callback: Function): void;
    off(type: string, callback?: Function): void;
  }

  export interface StartResponse {
    audioType?: string;
    sampleRate?: number;
    sampleBit?: number;
    audioChannel?: number;
    compressRate?: number;
  }

  export interface CompleteResponse {
    type: number;
    message?: string;
  }

  export interface StopResponse {
    type: number;
    message?: string;
  }

  export interface SynthesisResponse {
    sequence: number;
    audioType: string;
  }

  export interface SpeakListener {
    onStart?: (utteranceId: string, response: StartResponse) => void;
    onComplete?: (utteranceId: string, response: CompleteResponse) => void;
    onStop?: (utteranceId: string, response: StopResponse) => void;
    onData?: (utteranceId: string, audio: ArrayBuffer, response: SynthesisResponse) => void;
    onError?: (utteranceId: string, errorCode: number, errorMessage: string) => void;
  }

  export interface TextToSpeechEngine {
    speak(text: string, speakParams: SpeakParams): void;
    setListener(listener: SpeakListener): void;
    listVoices(params: VoiceQuery): Promise<Array<VoiceInfo>>;
    stop(): void;
    isBusy(): boolean;
    shutdown(): void;
  }

  class AndroidEngine implements TextToSpeechEngine {
    private readonly language: string;
    private readonly voiceName: string;
    private listener: SpeakListener = {};
    private generation: number = 0;
    private busy: boolean = false;
    private closed: boolean = false;

    constructor(params: CreateEngineParams) {
      this.language = params.language || 'zh-CN';
      this.voiceName = voiceNames.get(params.person) || '';
    }

    setListener(listener: SpeakListener): void {
      this.listener = listener || {};
    }

    speak(text: string, speakParams: SpeakParams): void {
      if (this.closed) throw new Error('朗读引擎已关闭');
      const generation = ++this.generation;
      const requestId = speakParams.requestId;
      const extra = speakParams.extraParams || {};
      const speed = Number(extra['speed'] || 1);
      const pitch = Number(extra['pitch'] || 1);
      this.busy = true;
      this.run(generation, requestId, text, speed, pitch).catch((error: Error) => {
        if (generation !== this.generation) return;
        this.busy = false;
        if (this.listener.onError) this.listener.onError(requestId, -1, error.message || '系统朗读失败');
      });
    }

    private async run(generation: number, requestId: string, text: string, speed: number, pitch: number):
      Promise<void> {
      const path = `${cacheDir || '/data/local/tmp'}/tts/${requestId.replace(/[^A-Za-z0-9_-]/g, '_')}.wav`;
      try {
        await call('synthesize', text, this.voiceName, this.language, String(speed), String(pitch), path);
        if (generation !== this.generation) return;
        const data = readFile(path);
        const wav = parseWav(data);
        if (this.listener.onStart) {
          this.listener.onStart(requestId, { audioType: 'pcm', sampleRate: wav.sampleRate, sampleBit: wav.sampleBit,
            audioChannel: wav.channels });
        }
        let sequence = 0;
        for (let offset = 0; offset < wav.length; offset += PCM_CHUNK_BYTES) {
          if (generation !== this.generation) return;
          const end = Math.min(wav.length, offset + PCM_CHUNK_BYTES);
          if (this.listener.onData) {
            this.listener.onData(requestId, data.slice(wav.offset + offset, wav.offset + end),
              { sequence: ++sequence, audioType: 'pcm' });
          }
        }
        if (generation !== this.generation) return;
        this.busy = false;
        // type 0：合成完成（鸿蒙引擎的语义）；应用自己播放 PCM 时据此进入下一段。
        if (this.listener.onComplete) this.listener.onComplete(requestId, { type: 0, message: 'synthesis complete' });
      } finally {
        try { fs.unlinkSync(path); } catch (_) { /* 缓存目录会被系统清理 */ }
      }
    }

    listVoices(params: VoiceQuery): Promise<Array<VoiceInfo>> {
      return listVoices(params);
    }

    stop(): void {
      this.generation++;
      this.busy = false;
      call('stop').catch(() => {});
    }

    isBusy(): boolean {
      return this.busy;
    }

    shutdown(): void {
      this.stop();
      this.closed = true;
    }
  }

  export async function createEngine(createEngineParams: CreateEngineParams): Promise<TextToSpeechEngine> {
    if (voiceNames.size === 0) await listVoices({ requestId: 'init', online: 0 }).catch(() => []);
    return new AndroidEngine(createEngineParams);
  }

  export async function listVoices(queryParams: VoiceQuery): Promise<Array<VoiceInfo>> {
    const result = await call('listVoices');
    const voices = (result['voices'] || []) as BridgeVoice[];
    const wanted = queryParams.online === 1;
    const list: VoiceInfo[] = [];
    for (const voice of voices) {
      const id = voiceId(voice.name);
      voiceNames.set(id, voice.name);
      if (voice.network !== wanted) continue;
      list.push({ language: voice.locale, person: id, style: voice.name, gender: '', description: voice.name,
        status: 'installed' });
    }
    if (!wanted) {
      // 0 号是“默认音色”：跟随系统设置里选的语音。
      list.unshift({ language: 'zh-CN', person: 0, style: '', gender: '', description: '系统默认语音', status: 'installed' });
    }
    return list;
  }

  export function downloadVoice(_downloadParams: VoiceDownload, callback: AsyncCallback<DownloadResponse>): void {
    const error: BusinessError = { code: 801, message: '安卓上请在系统设置里下载朗读语音' };
    callback(error, { requestId: '', on: (): void => {}, off: (): void => {} });
  }
}
