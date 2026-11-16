import { audio } from '@kit.AudioKit';
import worker, { ErrorEvent, MessageEvents } from '@ohos.worker';
import { PcmThreadEvent, PcmThreadRequest } from './PcmOutputProtocol';

/** 输出端回给朗读播放器的事件；output 用来认出是不是已经换掉的旧输出。 */
export interface PcmOutputHandlers {
  /** 主线程直连时由系统回调取数据。 */
  pull: (output: PcmOutput, buffer: ArrayBuffer) => audio.AudioDataCallbackResult;
  /** 输出线程整段写完了哪些数据、补了多少静音帧。 */
  consumed: (output: PcmOutput, writeIds: number[], paddingFrames: number) => void;
  interrupt: (output: PcmOutput, hint: audio.InterruptHint, force: audio.InterruptForceType) => void;
  /** 输出线程起不来或启动后一直不取数据：播放器换成主线程直连。 */
  failed: (output: PcmOutput) => void;
}

export class PcmOutputError extends Error {
  code: number;

  constructor(message: string, code: number) {
    super(message);
    this.code = code;
  }
}

interface PcmCallWaiter {
  resolve: (event: PcmThreadEvent) => void;
}

/**
 * 朗读的 PCM 输出。优先把渲染器放在专用线程（PcmOutputWorker）：数据整句先发过去，
 * 主线程卡几百毫秒也不会断音。线程起不来时退回主线程直连，行为与原来一样。
 * 方法和 state 与 AudioRenderer 同名，播放器里的状态判断照旧。
 */
export class PcmOutput {
  private static readonly CREATE_TIMEOUT_MS: number = 2000;
  /** 线程渲染器启动后这么久一次取数回调都没有，就认为这条路不通。 */
  private static readonly FIRST_CALLBACK_TIMEOUT_MS: number = 1500;
  /** 主线程拿到的帧位置最多往后推这么久，宁可略慢也不让高亮跑到声音前面太多。 */
  private static readonly TIMESTAMP_EXTRAPOLATE_MAX_MS: number = 60;
  private static thread: worker.ThreadWorker | null = null;
  private static threadDisabled: boolean = false;
  private static nextId: number = 1;
  private static nextCallId: number = 1;
  private static calls: Map<number, PcmCallWaiter> = new Map();
  private static threadOutputs: Map<number, PcmOutput> = new Map();

  readonly threaded: boolean;
  private readonly id: number;
  private readonly handlers: PcmOutputHandlers;
  private readonly sampleRate: number;
  private direct: audio.AudioRenderer | null = null;
  private directWriteCallback: audio.AudioRendererWriteDataCallback | null = null;
  private directInterruptCallback: ((event: audio.InterruptEvent) => void) | null = null;
  private mirroredState: audio.AudioState = audio.AudioState.STATE_PREPARED;
  private sentHold: boolean = false;
  private closed: boolean = false;
  private heardFromThread: boolean = false;
  private watchdogTimer: number = -1;
  private timestampFrame: number = 0;
  private timestampAt: number = 0;
  private timestampUnsupported: boolean = false;

  private constructor(threaded: boolean, options: audio.AudioRendererOptions, handlers: PcmOutputHandlers) {
    this.threaded = threaded;
    this.id = PcmOutput.nextId++;
    this.handlers = handlers;
    this.sampleRate = Math.max(1, Number(options.streamInfo.samplingRate) || 16000);
  }

  static async create(options: audio.AudioRendererOptions, handlers: PcmOutputHandlers): Promise<PcmOutput> {
    const threaded = await PcmOutput.createThreaded(options, handlers);
    if (threaded) return threaded;
    const output = new PcmOutput(false, options, handlers);
    const renderer = await audio.createAudioRenderer(options);
    output.direct = renderer;
    output.directWriteCallback = (data: ArrayBuffer): audio.AudioDataCallbackResult =>
      handlers.pull(output, data);
    output.directInterruptCallback = (event: audio.InterruptEvent): void => {
      handlers.interrupt(output, event.hintType, event.forceType);
    };
    renderer.on('writeData', output.directWriteCallback);
    renderer.on('audioInterrupt', output.directInterruptCallback);
    return output;
  }

  /** 输出线程出过错后不再用它，之后新建的渲染器都在主线程。 */
  static disableThread(reason: string): void {
    if (PcmOutput.threadDisabled) return;
    PcmOutput.threadDisabled = true;
    console.warn(`[TTS] pcm output thread disabled: ${reason}`);
    const thread = PcmOutput.thread;
    PcmOutput.thread = null;
    const waiters = Array.from(PcmOutput.calls.values());
    PcmOutput.calls.clear();
    for (const waiter of waiters) waiter.resolve({ type: 'reply', id: 0, ok: false, error: reason });
    const outputs = Array.from(PcmOutput.threadOutputs.values());
    PcmOutput.threadOutputs.clear();
    for (const output of outputs) output.fail();
    if (thread) {
      try {
        thread.terminate();
      } catch (_) {
      }
    }
  }

  get state(): audio.AudioState {
    if (this.direct) return this.direct.state;
    return this.mirroredState;
  }

  start(): Promise<void> {
    if (this.direct) return this.direct.start();
    return this.callThread('start').then(() => {
      // 停过之后的帧位置不能拿来外推，等线程报新的。
      this.timestampAt = 0;
      this.armWatchdog();
    });
  }

  pause(): Promise<void> {
    if (this.direct) return this.direct.pause();
    return this.callThread('pause');
  }

  drain(): Promise<void> {
    if (this.direct) return this.direct.drain();
    return this.callThread('drain');
  }

  setVolume(volume: number): Promise<void> {
    if (this.direct) return this.direct.setVolume(volume);
    return this.callThread('setVolume', volume);
  }

  setLoudnessGain(gain: number): Promise<void> {
    if (this.direct) return this.direct.setLoudnessGain(gain);
    return this.callThread('setLoudnessGain', gain);
  }

  /** 已播放到的帧位置；取不到时抛错，播放器改用时钟估算。 */
  framePosition(): number {
    if (this.direct) return Math.max(0, Math.round(this.direct.getAudioTimestampInfoSync().framePos));
    if (this.timestampUnsupported) throw new Error('frame timestamp unsupported');
    if (this.timestampAt <= 0) throw new Error('frame timestamp not reported yet');
    let frame = this.timestampFrame;
    if (this.mirroredState === audio.AudioState.STATE_RUNNING) {
      const elapsed = Math.min(Math.max(0, Date.now() - this.timestampAt), PcmOutput.TIMESTAMP_EXTRAPOLATE_MAX_MS);
      frame += Math.round(elapsed * this.sampleRate / 1000);
    }
    return frame;
  }

  /** 线程模式：把一段数据交给输出线程排队（数据缓冲会被转移，调用方传副本）。 */
  send(writeId: number, data: ArrayBuffer): void {
    if (this.direct || this.closed || !PcmOutput.thread) return;
    const request: PcmThreadRequest = { type: 'write', id: this.id, writeId: writeId, data: data };
    PcmOutput.thread.postMessage(request, [data]);
  }

  /** 线程模式：暂停或被打断期间不取数据（与直连时 writeData 里的判断一致）。 */
  setHold(hold: boolean): void {
    if (this.direct || this.closed || hold === this.sentHold || !PcmOutput.thread) return;
    this.sentHold = hold;
    const request: PcmThreadRequest = { type: 'hold', id: this.id, hold: hold };
    PcmOutput.thread.postMessage(request);
  }

  /** 解除回调、停止并释放渲染器。 */
  async shutdown(): Promise<void> {
    this.clearWatchdog();
    const renderer = this.direct;
    if (!renderer) {
      if (this.closed) return;
      this.closed = true;
      try {
        await this.callThread('shutdown');
      } catch (error) {
        console.warn('[TTS] release threaded pcm renderer failed:', error);
      }
      PcmOutput.threadOutputs.delete(this.id);
      this.mirroredState = audio.AudioState.STATE_RELEASED;
      return;
    }
    this.closed = true;
    if (this.directWriteCallback) {
      try {
        renderer.off('writeData', this.directWriteCallback);
      } catch (error) {
        console.warn('[TTS] unregister pcm write callback failed:', error);
      }
    }
    if (this.directInterruptCallback) {
      try {
        renderer.off('audioInterrupt', this.directInterruptCallback);
      } catch (error) {
        console.warn('[TTS] unregister pcm interrupt callback failed:', error);
      }
    }
    this.directWriteCallback = null;
    this.directInterruptCallback = null;
    try {
      if (renderer.state === audio.AudioState.STATE_RUNNING ||
        renderer.state === audio.AudioState.STATE_PAUSED) {
        await renderer.stop();
      }
    } catch (error) {
      console.warn('[TTS] stop pcm renderer failed:', error);
    }
    try {
      if (renderer.state !== audio.AudioState.STATE_RELEASED) {
        await renderer.release();
      }
    } catch (error) {
      console.warn('[TTS] release pcm renderer failed:', error);
    }
  }

  private static async createThreaded(options: audio.AudioRendererOptions,
    handlers: PcmOutputHandlers): Promise<PcmOutput | null> {
    if (!PcmOutput.ensureThread()) return null;
    const output = new PcmOutput(true, options, handlers);
    PcmOutput.threadOutputs.set(output.id, output);
    let timer: number = -1;
    const timeout = new Promise<PcmThreadEvent>((resolve: (event: PcmThreadEvent) => void) => {
      timer = setTimeout(() => resolve({ type: 'reply', id: output.id, ok: false, error: 'timeout' }),
        PcmOutput.CREATE_TIMEOUT_MS);
    });
    const request: PcmThreadRequest = { type: 'create', id: output.id, options: options };
    const event = await Promise.race([PcmOutput.request(request), timeout]);
    clearTimeout(timer);
    if (!event.ok) {
      PcmOutput.threadOutputs.delete(output.id);
      output.closed = true;
      // 线程里可能晚一点才建好，顺手释放掉。
      PcmOutput.postIfAlive({ type: 'call', id: output.id, callId: 0, method: 'shutdown' });
      PcmOutput.disableThread(`create failed: ${event.error || ''}`);
      return null;
    }
    output.mirroredState = (event.state ?? audio.AudioState.STATE_PREPARED) as audio.AudioState;
    return output;
  }

  private static ensureThread(): boolean {
    if (PcmOutput.threadDisabled) return false;
    if (PcmOutput.thread) return true;
    try {
      const thread = new worker.ThreadWorker('../workers/PcmOutputWorker.ets', { name: 'PcmOutput' });
      thread.onmessage = (message: MessageEvents): void => {
        PcmOutput.dispatch(message.data as PcmThreadEvent);
      };
      thread.onerror = (error: ErrorEvent): void => {
        PcmOutput.disableThread(`worker error: ${error.message}`);
      };
      thread.onexit = (_code: number): void => {
        if (PcmOutput.thread === thread) PcmOutput.disableThread('worker exited');
      };
      PcmOutput.thread = thread;
      return true;
    } catch (error) {
      PcmOutput.disableThread(`worker start failed: ${error}`);
      return false;
    }
  }

  private static postIfAlive(request: PcmThreadRequest): void {
    try {
      PcmOutput.thread?.postMessage(request);
    } catch (_) {
    }
  }

  private static request(request: PcmThreadRequest): Promise<PcmThreadEvent> {
    const thread = PcmOutput.thread;
    if (!thread) {
      const failed: PcmThreadEvent = { type: 'reply', id: request.id, ok: false, error: 'no worker' };
      return Promise.resolve(failed);
    }
    const callId = PcmOutput.nextCallId++;
    request.callId = callId;
    return new Promise<PcmThreadEvent>((resolve: (event: PcmThreadEvent) => void) => {
      PcmOutput.calls.set(callId, { resolve: resolve });
      try {
        thread.postMessage(request);
      } catch (error) {
        PcmOutput.calls.delete(callId);
        resolve({ type: 'reply', id: request.id, ok: false, error: `${error}` });
      }
    });
  }

  private static dispatch(event: PcmThreadEvent): void {
    if (event.type === 'reply') {
      const waiter = PcmOutput.calls.get(event.callId ?? 0);
      if (waiter) {
        PcmOutput.calls.delete(event.callId ?? 0);
        waiter.resolve(event);
      }
      return;
    }
    const output = PcmOutput.threadOutputs.get(event.id);
    if (output) output.onThreadEvent(event);
  }

  private async callThread(method: string, value?: number): Promise<void> {
    if (this.closed && method !== 'shutdown') throw new PcmOutputError('pcm output released', 6800301);
    const event = await PcmOutput.request({ type: 'call', id: this.id, method: method, value: value });
    if (event.state !== undefined && !this.closed) this.mirroredState = event.state as audio.AudioState;
    if (!event.ok) throw new PcmOutputError(event.error || `${method} failed`, event.code ?? 6800301);
  }

  private onThreadEvent(event: PcmThreadEvent): void {
    if (this.closed) return;
    if (event.type === 'ts') {
      this.heardFromThread = true;
      if (event.unsupported) {
        this.timestampUnsupported = true;
      } else {
        this.timestampFrame = event.framePos ?? 0;
        this.timestampAt = event.at ?? Date.now();
      }
      return;
    }
    if (event.type === 'consumed') {
      this.heardFromThread = true;
      this.handlers.consumed(this, event.writeIds ?? [], event.padding ?? 0);
      return;
    }
    if (event.type === 'state') {
      this.mirroredState = (event.state ?? this.mirroredState) as audio.AudioState;
      return;
    }
    if (event.type === 'interrupt') {
      this.handlers.interrupt(this, (event.hint ?? 0) as audio.InterruptHint,
        (event.force ?? 0) as audio.InterruptForceType);
    }
  }

  private armWatchdog(): void {
    if (this.heardFromThread || this.watchdogTimer >= 0 || this.mirroredState !== audio.AudioState.STATE_RUNNING) {
      return;
    }
    this.watchdogTimer = setTimeout(() => {
      // 主线程刚卡过的话，定时器会先于排队的线程消息执行：隔一轮事件循环、收完消息再下结论。
      this.watchdogTimer = setTimeout(() => {
        this.watchdogTimer = -1;
        if (this.closed || this.heardFromThread || this.mirroredState !== audio.AudioState.STATE_RUNNING) return;
        PcmOutput.disableThread('renderer started but never asked for data');
      }, 50);
    }, PcmOutput.FIRST_CALLBACK_TIMEOUT_MS);
  }

  private clearWatchdog(): void {
    if (this.watchdogTimer < 0) return;
    clearTimeout(this.watchdogTimer);
    this.watchdogTimer = -1;
  }

  private fail(): void {
    if (this.closed) return;
    this.closed = true;
    this.clearWatchdog();
    this.mirroredState = audio.AudioState.STATE_STOPPED;
    this.handlers.failed(this);
  }
}
