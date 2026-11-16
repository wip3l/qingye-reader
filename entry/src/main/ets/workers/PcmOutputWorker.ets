import worker, { ThreadWorkerGlobalScope, MessageEvents } from '@ohos.worker';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PcmThreadEvent, PcmThreadRequest } from '../utils/PcmOutputProtocol';

// 朗读 PCM 的输出线程。渲染器的 writeData 回调落在注册它的线程上；放主线程时，换主题、开大页面这类
// 几百毫秒的界面重建会让系统等不到数据，声音一顿一顿。主线程提前把整句数据发过来，这里只管往系统缓冲里拷。

interface QueuedWrite {
  writeId: number;
  data: Uint8Array;
  offset: number;
}

const TIMESTAMP_INTERVAL_MS: number = 30;

class ThreadOutput {
  id: number;
  renderer: audio.AudioRenderer;
  queue: QueuedWrite[] = [];
  hold: boolean = false;
  lastTimestampAt: number = 0;
  timestampUnsupported: boolean = false;
  writeCallback: audio.AudioRendererWriteDataCallback | null = null;
  interruptCallback: ((event: audio.InterruptEvent) => void) | null = null;
  stateCallback: ((state: audio.AudioState) => void) | null = null;

  constructor(id: number, renderer: audio.AudioRenderer) {
    this.id = id;
    this.renderer = renderer;
  }
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
const outputs: Map<number, ThreadOutput> = new Map();

function post(event: PcmThreadEvent): void {
  workerPort.postMessage(event);
}

function reply(request: PcmThreadRequest, ok: boolean, state: number, error?: BusinessError): void {
  const event: PcmThreadEvent = {
    type: 'reply',
    id: request.id,
    callId: request.callId,
    ok: ok,
    state: state
  };
  if (error) {
    event.error = `${error.message || error}`;
    event.code = error.code;
  }
  post(event);
}

function postTimestamp(output: ThreadOutput): void {
  if (output.timestampUnsupported) return;
  const now = Date.now();
  if (now - output.lastTimestampAt < TIMESTAMP_INTERVAL_MS) return;
  output.lastTimestampAt = now;
  try {
    const timestamp = output.renderer.getAudioTimestampInfoSync();
    post({ type: 'ts', id: output.id, framePos: Math.max(0, Math.round(timestamp.framePos)), at: now });
  } catch (_) {
    output.timestampUnsupported = true;
    post({ type: 'ts', id: output.id, unsupported: true });
  }
}

/** 与主线程直连时的取数逻辑一致：暂停/被打断或没有数据时不写，最后一块不满时补静音。 */
function fill(output: ThreadOutput, buffer: ArrayBuffer): audio.AudioDataCallbackResult {
  postTimestamp(output);
  if (output.hold || !buffer || buffer.byteLength === 0 || output.queue.length === 0) {
    return audio.AudioDataCallbackResult.INVALID;
  }
  const target = new Uint8Array(buffer);
  let offset = 0;
  const finished: number[] = [];
  while (offset < target.length && output.queue.length > 0) {
    const pending = output.queue[0];
    const length = Math.min(pending.data.length - pending.offset, target.length - offset);
    target.set(pending.data.subarray(pending.offset, pending.offset + length), offset);
    pending.offset += length;
    offset += length;
    if (pending.offset >= pending.data.length) {
      output.queue.shift();
      finished.push(pending.writeId);
    }
  }
  let padding = 0;
  if (offset < target.length) {
    target.fill(0, offset);
    padding = Math.floor((target.length - offset) / 2);
  }
  if (finished.length > 0 || padding > 0) {
    post({ type: 'consumed', id: output.id, writeIds: finished, padding: padding });
  }
  return audio.AudioDataCallbackResult.VALID;
}

async function create(request: PcmThreadRequest): Promise<void> {
  if (!request.options) {
    reply(request, false, audio.AudioState.STATE_INVALID);
    return;
  }
  try {
    const renderer = await audio.createAudioRenderer(request.options);
    const output = new ThreadOutput(request.id, renderer);
    output.writeCallback = (data: ArrayBuffer): audio.AudioDataCallbackResult => fill(output, data);
    output.interruptCallback = (event: audio.InterruptEvent): void => {
      post({ type: 'interrupt', id: output.id, hint: event.hintType, force: event.forceType });
    };
    output.stateCallback = (state: audio.AudioState): void => {
      post({ type: 'state', id: output.id, state: state });
    };
    renderer.on('writeData', output.writeCallback);
    renderer.on('audioInterrupt', output.interruptCallback);
    renderer.on('stateChange', output.stateCallback);
    outputs.set(request.id, output);
    reply(request, true, renderer.state);
  } catch (error) {
    reply(request, false, audio.AudioState.STATE_INVALID, error as BusinessError);
  }
}

async function shutdown(output: ThreadOutput): Promise<void> {
  outputs.delete(output.id);
  output.queue = [];
  const renderer = output.renderer;
  try {
    if (output.writeCallback) renderer.off('writeData', output.writeCallback);
    if (output.interruptCallback) renderer.off('audioInterrupt', output.interruptCallback);
    if (output.stateCallback) renderer.off('stateChange', output.stateCallback);
  } catch (error) {
    console.warn('[TTS] unregister threaded pcm callbacks failed:', error);
  }
  try {
    if (renderer.state === audio.AudioState.STATE_RUNNING || renderer.state === audio.AudioState.STATE_PAUSED) {
      await renderer.stop();
    }
  } catch (error) {
    console.warn('[TTS] stop threaded pcm renderer failed:', error);
  }
  try {
    if (renderer.state !== audio.AudioState.STATE_RELEASED) await renderer.release();
  } catch (error) {
    console.warn('[TTS] release threaded pcm renderer failed:', error);
  }
}

async function call(request: PcmThreadRequest): Promise<void> {
  const output = outputs.get(request.id);
  if (!output) {
    reply(request, request.method === 'shutdown', audio.AudioState.STATE_RELEASED);
    return;
  }
  const renderer = output.renderer;
  try {
    switch (request.method) {
      case 'start':
        await renderer.start();
        break;
      case 'pause':
        await renderer.pause();
        break;
      case 'drain':
        await renderer.drain();
        break;
      case 'setVolume':
        await renderer.setVolume(request.value ?? 1);
        break;
      case 'setLoudnessGain':
        await renderer.setLoudnessGain(request.value ?? 0);
        break;
      case 'shutdown':
        await shutdown(output);
        break;
      default:
        break;
    }
    reply(request, true, renderer.state);
  } catch (error) {
    reply(request, false, renderer.state, error as BusinessError);
  }
}

workerPort.onmessage = (event: MessageEvents): void => {
  const request = event.data as PcmThreadRequest;
  if (request.type === 'write') {
    const output = outputs.get(request.id);
    if (output && request.data && request.data.byteLength > 0) {
      output.queue.push({ writeId: request.writeId ?? 0, data: new Uint8Array(request.data), offset: 0 });
    }
    return;
  }
  if (request.type === 'hold') {
    const output = outputs.get(request.id);
    if (output) output.hold = request.hold === true;
    return;
  }
  if (request.type === 'create') {
    create(request);
    return;
  }
  if (request.type === 'call') {
    call(request);
  }
};
