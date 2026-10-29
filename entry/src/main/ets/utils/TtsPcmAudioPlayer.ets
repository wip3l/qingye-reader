import { audio } from '@kit.AudioKit';
import deviceInfo from '@ohos.deviceInfo';
import { TtsAudioSession } from './TtsAudioSession';
import { sleepMs } from '@legado/sourceengine';

interface PcmPlaybackMark {
  frame: number;
  callback: () => void;
}

interface PendingPcmWrite {
  data: Uint8Array;
  offset: number;
  generation: number;
  resolve: () => void;
}

export interface PcmPlaybackCue {
  frameOffset: number;
  callback: () => void;
}

export class TtsPcmAudioPlayer {
  private static readonly CLOCK_FALLBACK_DRAIN_GRACE_MS: number = 80;
  private static readonly TIMESTAMP_TAIL_DRAIN_GRACE_MS: number = 100;
  private static readonly RENDERER_DRAIN_MAX_WAIT_MS: number = 120;
  private readonly audioSessionOwner: string = `tts_pcm_${Date.now()}_${Math.random()}`;
  private renderer: audio.AudioRenderer | null = null;
  private currentSampleRate: audio.AudioSamplingRate = audio.AudioSamplingRate.SAMPLE_RATE_16000;
  private playGeneration: number = 0;
  private writeChain: Promise<void> = Promise.resolve();
  private queuedFrames: number = 0;
  private queuedContentEndFrame: number = 0;
  private queuedSampleRate: number = 0;
  private playbackMarks: PcmPlaybackMark[] = [];
  private timelineBaseFrame: number = 0;
  private timelineStartedAt: number = 0;
  private timelineTimerId: number = -1;
  private lastReachedFrame: number = 0;
  private rendererFrameOrigin: number = -1;
  private rendererLogicalFrameOrigin: number = 0;
  private timestampFailureLogged: boolean = false;
  private progressMode: string = 'CLOCK_FALLBACK';
  private rendererStartPromise: Promise<void> | null = null;
  private rendererWriteCallback: audio.AudioRendererWriteDataCallback | null = null;
  private rendererInterruptCallback: ((event: audio.InterruptEvent) => void) | null = null;
  private pendingWrites: PendingPcmWrite[] = [];
  private pendingWriteBytes: number = 0;
  private paused: boolean = false;
  private systemInterrupted: boolean = false;
  private interruptResumeAllowed: boolean = false;
  private interruptRevision: number = 0;
  private interruptResumeRevision: number = -1;
  private interruptPausePromise: Promise<void> = Promise.resolve();
  private systemDucked: boolean = false;
  private resumeWaiters: Array<() => void> = [];
  private playbackWaiters: Array<() => void> = [];

  async play(data: ArrayBuffer, sampleRate: number): Promise<void> {
    await this.write(data, sampleRate);
    await this.drain();
  }

  write(data: ArrayBuffer, sampleRate: number): Promise<void> {
    return this.enqueueWrite(data, sampleRate);
  }

  writeSegment(data: ArrayBuffer, sampleRate: number, onPlaybackStart: () => void): Promise<void> {
    return this.enqueueWrite(data, sampleRate, [{
      frameOffset: 0,
      callback: onPlaybackStart
    }]);
  }

  writeTimedSegment(data: ArrayBuffer, sampleRate: number, cues: PcmPlaybackCue[]): Promise<void> {
    return this.enqueueWrite(data, sampleRate, cues);
  }

  private enqueueWrite(data: ArrayBuffer, sampleRate: number,
    cues?: PcmPlaybackCue[]): Promise<void> {
    if (!data || data.byteLength === 0) {
      return this.writeChain;
    }
    const normalizedSampleRate = Math.max(1, Math.round(sampleRate || 16000));
    if (this.queuedSampleRate > 0 && this.queuedSampleRate !== normalizedSampleRate) {
      console.info(`[TTS] pcm sample rate changed: ${this.queuedSampleRate} -> ${normalizedSampleRate}`);
      this.stop();
    }
    const audioData = data.slice(0);
    const generation = this.playGeneration;
    if (this.queuedSampleRate === 0) {
      this.queuedSampleRate = normalizedSampleRate;
    }
    const startFrame = this.queuedFrames;
    const segmentFrames = Math.floor(audioData.byteLength / 2);
    this.queuedFrames += segmentFrames;
    this.queuedContentEndFrame = this.queuedFrames;
    if (cues && cues.length > 0) {
      const sortedCues = cues.slice().sort((left: PcmPlaybackCue, right: PcmPlaybackCue) =>
        left.frameOffset - right.frameOffset);
      for (const cue of sortedCues) {
        const frameOffset = Math.max(0, Math.min(
          Math.max(0, segmentFrames - 1),
          Math.round(cue.frameOffset)
        ));
        this.queuePlaybackMark(startFrame + frameOffset, cue.callback);
      }
    }
    let resolveWrite: () => void = () => {
    };
    const consumedPromise = new Promise<void>((resolve: () => void) => {
      resolveWrite = resolve;
    });
    const pendingWrite: PendingPcmWrite = {
      data: new Uint8Array(audioData),
      offset: 0,
      generation: generation,
      resolve: resolveWrite
    };
    this.pendingWrites.push(pendingWrite);
    this.pendingWriteBytes += audioData.byteLength;
    const completionPromise = this.ensureRendererStarted(normalizedSampleRate, generation)
      .then(() => consumedPromise)
      .catch((error: Error) => {
        this.discardPendingWrite(pendingWrite);
        console.warn('[TTS] write pcm audio failed:', error);
        // Do not convert an output failure into a successful consumed segment. System/custom TTS queues use this
        // promise as the proof that a paragraph entered AudioRenderer; swallowing it made the queue drain and
        // report chapter completion even though the final paragraphs had never been played.
        throw error;
      });
    const previousWrites = this.writeChain;
    this.writeChain = Promise.all([
      previousWrites.catch((_error: Error) => {
      }),
      completionPromise
    ]).then(() => {
    });
    return completionPromise;
  }

  private queuePlaybackMark(frame: number, callback: () => void): void {
    const last = this.playbackMarks.length > 0 ?
      this.playbackMarks[this.playbackMarks.length - 1] : undefined;
    if (last && last.frame === frame) {
      const previousCallback = last.callback;
      last.callback = () => {
        previousCallback();
        callback();
      };
      return;
    }
    this.playbackMarks.push({ frame, callback });
  }

  async drain(): Promise<void> {
    await this.writeChain;
    await this.waitUntilResumed();
    const renderer = this.renderer;
    const generation = this.playGeneration;
    // writeData requires a complete platform buffer, so the final callback can
    // contain zero padding after the last real PCM frame. Some devices do not
    // advance their rendered-frame timestamp through those transport-only
    // frames. Waiting for queuedFrames therefore leaves chapter completion
    // blocked even though every audible sample has already played.
    const targetFrame = this.queuedContentEndFrame;
    console.info(`[TTS] pcm drain waiting: contentEnd=${targetFrame},transportEnd=${this.queuedFrames}`);
    if (!renderer || generation !== this.playGeneration) {
      return;
    }
    while (generation === this.playGeneration && this.renderer === renderer) {
      if (!await this.waitUntilRendererRunning(renderer, generation)) {
        return;
      }
      // Wait for the playback timeline before asking AudioRenderer to drain.
      // Some devices leave drain() pending (or move the renderer out of RUNNING)
      // while writeData keeps returning INVALID after the final PCM buffer. The
      // old drain-first order therefore never completed the chapter handoff.
      if (!await this.waitUntilPlaybackFrameReached(targetFrame, renderer, generation)) {
        return;
      }
      if (this.progressMode === 'CLOCK_FALLBACK') {
        // Older devices lack a rendered-frame timestamp. The final writeData
        // block is already zero-padded, so only a short route-latency guard is
        // needed here; a longer fixed grace becomes audible at every chapter.
        await sleepMs(TtsPcmAudioPlayer.CLOCK_FALLBACK_DRAIN_GRACE_MS);
      }
      if (generation !== this.playGeneration || this.renderer !== renderer) {
        return;
      }
      await this.settleRendererDrain(renderer, generation);
      this.lastReachedFrame = Math.max(this.lastReachedFrame, targetFrame);
      this.dispatchDuePlaybackMarks(generation);
      this.pausePlaybackTimelineAt(targetFrame);
      console.info(`[TTS] pcm content playback complete: contentEnd=${targetFrame},transportEnd=${this.queuedFrames}`);
      return;
    }
  }

  private async settleRendererDrain(renderer: audio.AudioRenderer, generation: number): Promise<void> {
    let settled = false;
    let drainError: Error | null = null;
    renderer.drain()
      .then(() => {
        settled = true;
      })
      .catch((error: Error) => {
        drainError = error;
        settled = true;
      });
    const waitStepMs = 40;
    const maxAttempts = Math.ceil(TtsPcmAudioPlayer.RENDERER_DRAIN_MAX_WAIT_MS / waitStepMs);
    for (let attempt = 0; attempt < maxAttempts && !settled; attempt++) {
      if (generation !== this.playGeneration || this.renderer !== renderer) {
        return;
      }
      await sleepMs(waitStepMs);
    }
    if (drainError) {
      console.warn('[TTS] renderer drain failed after playback reached its final frame:', drainError);
    } else if (!settled) {
      // The application-level frame timeline has already reached targetFrame,
      // so a platform drain callback must not block onFinished/next chapter.
      console.warn('[TTS] renderer drain callback timed out after final frame; continue chapter handoff');
    }
  }

  private async waitUntilPlaybackFrameReached(targetFrame: number, renderer: audio.AudioRenderer,
    generation: number): Promise<boolean> {
    const sampleRate = Math.max(1, this.queuedSampleRate || Number(this.currentSampleRate) || 16000);
    let fallbackBaseFrame = this.lastReachedFrame;
    let fallbackStartedAt = Date.now();
    while (generation === this.playGeneration && this.renderer === renderer) {
      if (this.paused || this.systemInterrupted || renderer.state !== audio.AudioState.STATE_RUNNING) {
        if (!await this.waitUntilRendererRunning(renderer, generation)) {
          return false;
        }
        // Paused/interrupted time must never count as played audio.
        fallbackBaseFrame = this.lastReachedFrame;
        fallbackStartedAt = Date.now();
        continue;
      }
      this.updatePlaybackTimeline(generation);
      if (this.lastReachedFrame >= targetFrame) {
        return true;
      }
      const now = Date.now();
      if (this.lastReachedFrame > fallbackBaseFrame) {
        fallbackBaseFrame = this.lastReachedFrame;
        fallbackStartedAt = now;
      }
      // On some devices framePos stops at an underrun just before the real PCM
      // end while AudioRenderer remains RUNNING forever. Once all bytes have
      // been accepted, finish the small unreported tail with an active-playback
      // clock. Its duration still comes from the exact remaining PCM frames, so
      // this does not cut speech; the grace only absorbs output-route latency.
      const fallbackElapsedMs = Math.max(0,
        now - fallbackStartedAt - TtsPcmAudioPlayer.TIMESTAMP_TAIL_DRAIN_GRACE_MS);
      const fallbackFrame = fallbackBaseFrame + Math.floor(fallbackElapsedMs * sampleRate / 1000);
      if (this.pendingWriteBytes === 0 && fallbackFrame >= targetFrame) {
        console.warn(`[TTS] pcm drain timestamp tail fallback: reached=${this.lastReachedFrame},` +
          `target=${targetFrame},elapsedMs=${now - fallbackStartedAt}`);
        this.lastReachedFrame = targetFrame;
        this.dispatchDuePlaybackMarks(generation);
        return true;
      }
      await sleepMs(40);
    }
    return false;
  }

  async pause(): Promise<void> {
    this.interruptRevision++;
    this.interruptResumeAllowed = false;
    if (this.paused) {
      return;
    }
    this.paused = true;
    const renderer = this.renderer;
    const generation = this.playGeneration;
    if (!renderer || renderer.state !== audio.AudioState.STATE_RUNNING) {
      return;
    }
    this.updatePlaybackTimeline(generation);
    try {
      await renderer.pause();
    } catch (error) {
      console.warn('[TTS] pause pcm renderer failed:', error);
    }
    if (generation === this.playGeneration) {
      this.pausePlaybackTimelineAt(this.lastReachedFrame);
      this.rendererFrameOrigin = -1;
      this.rendererLogicalFrameOrigin = this.lastReachedFrame;
    }
  }

  async resume(): Promise<void> {
    if (!this.paused && !this.systemInterrupted) {
      return;
    }
    this.paused = false;
    this.systemInterrupted = false;
    this.interruptResumeAllowed = false;
    this.systemDucked = false;
    const revision = ++this.interruptRevision;
    await this.interruptPausePromise;
    if (revision !== this.interruptRevision || this.paused || this.systemInterrupted) return;
    const renderer = this.renderer;
    const generation = this.playGeneration;
    if (renderer && renderer.state !== audio.AudioState.STATE_RUNNING &&
      renderer.state !== audio.AudioState.STATE_RELEASED) {
      let rendererResumed = false;
      try {
        await TtsAudioSession.acquire(this.audioSessionOwner);
        if (renderer !== this.renderer || revision !== this.interruptRevision || this.paused ||
          this.systemInterrupted) return;
        await renderer.setVolume(1);
        if (renderer !== this.renderer || revision !== this.interruptRevision || this.paused ||
          this.systemInterrupted) return;
        await renderer.start();
        if (await this.pauseRendererIfInterrupted(renderer)) return;
        rendererResumed = true;
      } catch (error) {
        console.warn('[TTS] resume pcm renderer failed:', error);
      }
      if (generation === this.playGeneration && rendererResumed) {
        this.rendererFrameOrigin = -1;
        this.rendererLogicalFrameOrigin = this.lastReachedFrame;
        this.timelineBaseFrame = this.lastReachedFrame;
        this.timelineStartedAt = Date.now();
        this.updatePlaybackTimeline(generation);
        this.resolvePlaybackWaiters();
      }
    }
    this.resolveResumeWaiters();
    this.resolvePlaybackWaiters();
  }

  isPaused(): boolean {
    return this.paused;
  }

  stop(): void {
    this.playGeneration++;
    this.interruptRevision++;
    this.interruptResumeAllowed = false;
    this.paused = false;
    this.systemInterrupted = false;
    this.systemDucked = false;
    this.resolveResumeWaiters();
    this.resolvePlaybackWaiters();
    TtsAudioSession.release(this.audioSessionOwner);
    this.writeChain = Promise.resolve();
    this.rendererStartPromise = null;
    this.resolvePendingWrites();
    const renderer = this.renderer;
    const writeCallback = this.rendererWriteCallback;
    const interruptCallback = this.rendererInterruptCallback;
    this.rendererWriteCallback = null;
    this.rendererInterruptCallback = null;
    this.clearPlaybackTimeline(renderer);
    this.renderer = null;
    if (!renderer) {
      return;
    }
    this.releaseRenderer(renderer, writeCallback, interruptCallback);
  }

  release(): void {
    this.stop();
  }

  debugState(): string {
    if (!this.renderer) {
      return `renderer=none,paused=${this.paused},interrupted=${this.systemInterrupted},ducked=${this.systemDucked},` +
        `queuedFrames=${this.queuedFrames},contentEnd=${this.queuedContentEndFrame},marks=${this.playbackMarks.length},` +
        `pendingBytes=${this.pendingWriteBytes},progress=${this.progressMode}`;
    }
    return `renderer=${this.audioStateName(this.renderer.state)},paused=${this.paused},` +
      `interrupted=${this.systemInterrupted},ducked=${this.systemDucked},sampleRate=${this.currentSampleRate},` +
      `generation=${this.playGeneration},queuedFrames=${this.queuedFrames},contentEnd=${this.queuedContentEndFrame},` +
      `marks=${this.playbackMarks.length},` +
      `pendingBytes=${this.pendingWriteBytes},progress=${this.progressMode}`;
  }

  private async ensureRendererStarted(sampleRate: number, generation: number): Promise<void> {
    if (generation !== this.playGeneration) {
      return;
    }
    if (!this.rendererStartPromise) {
      const startPromise = this.startRenderer(sampleRate, generation);
      this.rendererStartPromise = startPromise;
      startPromise.then(() => {
        if (this.rendererStartPromise === startPromise) {
          this.rendererStartPromise = null;
        }
      }).catch((_error: Error) => {
        if (this.rendererStartPromise === startPromise) {
          this.rendererStartPromise = null;
        }
      });
    }
    await this.rendererStartPromise;
  }

  private async startRenderer(sampleRate: number, generation: number): Promise<void> {
    const renderer = await this.ensureRenderer(sampleRate);
    if (generation !== this.playGeneration) {
      await this.releaseStaleRenderer(renderer);
      return;
    }
    if (!this.paused && !this.systemInterrupted && renderer.state !== audio.AudioState.STATE_RUNNING) {
      await TtsAudioSession.acquire(this.audioSessionOwner);
      if (generation !== this.playGeneration) {
        TtsAudioSession.release(this.audioSessionOwner);
        await this.releaseStaleRenderer(renderer);
        return;
      }
      await renderer.setVolume(1);
      if (!this.paused && !this.systemInterrupted && generation === this.playGeneration &&
        renderer === this.renderer) {
        await renderer.start();
        await this.pauseRendererIfInterrupted(renderer);
      }
    }
    if (generation !== this.playGeneration) {
      await this.releaseStaleRenderer(renderer);
      return;
    }
    if (!this.paused) {
      this.ensurePlaybackTimeline(sampleRate, generation);
      this.resolvePlaybackWaiters();
    }
  }

  private waitUntilRendererRunning(renderer: audio.AudioRenderer, generation: number): Promise<boolean> {
    if (generation !== this.playGeneration || this.renderer !== renderer) {
      return Promise.resolve(false);
    }
    if (!this.paused && !this.systemInterrupted && renderer.state === audio.AudioState.STATE_RUNNING) {
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const check = (): void => {
        if (generation !== this.playGeneration || this.renderer !== renderer) {
          resolve(false);
          return;
        }
        if (!this.paused && !this.systemInterrupted && renderer.state === audio.AudioState.STATE_RUNNING) {
          resolve(true);
          return;
        }
        this.playbackWaiters.push(check);
      };
      this.playbackWaiters.push(check);
    });
  }

  private async pauseRendererIfInterrupted(renderer: audio.AudioRenderer): Promise<boolean> {
    if (renderer !== this.renderer) return true;
    if (!this.paused && !this.systemInterrupted) return false;
    if (renderer.state === audio.AudioState.STATE_RUNNING) await renderer.pause();
    return true;
  }

  private resolvePlaybackWaiters(): void {
    const waiters = this.playbackWaiters.splice(0, this.playbackWaiters.length);
    for (const resolve of waiters) {
      resolve();
    }
  }

  private waitUntilResumed(): Promise<void> {
    if (!this.paused) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.resumeWaiters.push(resolve);
    });
  }

  private resolveResumeWaiters(): void {
    const waiters = this.resumeWaiters.splice(0, this.resumeWaiters.length);
    for (const resolve of waiters) {
      resolve();
    }
  }

  private async releaseStaleRenderer(renderer: audio.AudioRenderer): Promise<void> {
    let writeCallback: audio.AudioRendererWriteDataCallback | null = null;
    let interruptCallback: ((event: audio.InterruptEvent) => void) | null = null;
    if (this.renderer === renderer) {
      this.renderer = null;
      writeCallback = this.rendererWriteCallback;
      interruptCallback = this.rendererInterruptCallback;
      this.rendererWriteCallback = null;
      this.rendererInterruptCallback = null;
    }
    await this.releaseRenderer(renderer, writeCallback, interruptCallback);
  }

  private ensurePlaybackTimeline(sampleRate: number, generation: number): void {
    if (generation !== this.playGeneration) {
      return;
    }
    if (this.timelineStartedAt <= 0) {
      this.timelineBaseFrame = this.lastReachedFrame;
      this.timelineStartedAt = Date.now();
      console.info(`[TTS] pcm playback clock started: frame=${this.timelineBaseFrame},` +
        `sampleRate=${sampleRate}`);
    }
    this.updatePlaybackTimeline(generation);
  }

  private dispatchDuePlaybackMarks(generation: number): void {
    if (generation !== this.playGeneration) {
      return;
    }
    while (this.playbackMarks.length > 0 &&
      this.playbackMarks[0].frame <= this.lastReachedFrame) {
      const mark = this.playbackMarks.shift() as PcmPlaybackMark;
      console.info(`[TTS] pcm playback cue reached: frame=${mark.frame},rendered=${this.lastReachedFrame}`);
      this.invokePlaybackMark(mark, generation);
    }
  }

  private updatePlaybackTimeline(generation: number): void {
    if (generation !== this.playGeneration || this.timelineStartedAt <= 0) {
      return;
    }
    this.clearPlaybackTimelineTimer();
    const sampleRate = Math.max(1, this.queuedSampleRate || Number(this.currentSampleRate) || 16000);
    const elapsedMs = Math.max(0, Date.now() - this.timelineStartedAt);
    const clockFrame = this.timelineBaseFrame + Math.round(elapsedMs * sampleRate / 1000);
    let reachedFrame = clockFrame;
    const renderer = this.renderer;
    if (!renderer || renderer.state !== audio.AudioState.STATE_RUNNING || this.paused || this.systemInterrupted) {
      this.pausePlaybackTimelineAt(this.lastReachedFrame);
      return;
    }
    if (renderer && renderer.state === audio.AudioState.STATE_RUNNING) {
      try {
        const timestamp = renderer.getAudioTimestampInfoSync();
        const rendererFrame = Math.max(0, Math.round(timestamp.framePos));
        if (this.rendererFrameOrigin < 0) {
          this.rendererFrameOrigin = rendererFrame;
          this.rendererLogicalFrameOrigin = Math.max(this.lastReachedFrame, clockFrame);
          console.info(`[TTS] pcm frame timestamp started: rendererFrame=${rendererFrame},` +
            `logicalFrame=${this.rendererLogicalFrameOrigin},api=${deviceInfo.sdkApiVersion}`);
        }
        reachedFrame = this.rendererLogicalFrameOrigin +
          Math.max(0, rendererFrame - this.rendererFrameOrigin);
        this.progressMode = 'FRAME_TIMESTAMP';
        this.timestampFailureLogged = false;
        this.timelineBaseFrame = Math.max(this.lastReachedFrame, reachedFrame);
        this.timelineStartedAt = Date.now();
      } catch (error) {
        this.progressMode = 'CLOCK_FALLBACK';
        if (!this.timestampFailureLogged) {
          this.timestampFailureLogged = true;
          console.warn(`[TTS] frame timestamp unavailable, using clock fallback: ` +
            `api=${deviceInfo.sdkApiVersion}`, error);
        }
      }
    } else {
      this.progressMode = 'CLOCK_FALLBACK';
    }
    this.lastReachedFrame = Math.max(this.lastReachedFrame,
      Math.min(this.queuedFrames, reachedFrame));
    this.dispatchDuePlaybackMarks(generation);
    if (this.lastReachedFrame >= this.queuedFrames) {
      this.pausePlaybackTimelineAt(this.queuedFrames);
      return;
    }
    this.timelineTimerId = setTimeout(() => {
      this.timelineTimerId = -1;
      if (generation !== this.playGeneration) {
        return;
      }
      this.updatePlaybackTimeline(generation);
    }, 50);
  }

  private pausePlaybackTimelineAt(frame: number): void {
    this.clearPlaybackTimelineTimer();
    this.lastReachedFrame = Math.max(this.lastReachedFrame, frame);
    this.timelineBaseFrame = this.lastReachedFrame;
    this.timelineStartedAt = 0;
  }

  private invokePlaybackMark(mark: PcmPlaybackMark, generation: number): void {
    if (generation !== this.playGeneration) {
      return;
    }
    try {
      mark.callback();
    } catch (error) {
      console.warn('[TTS] pcm playback mark callback failed:', error);
    }
  }

  private clearPlaybackTimeline(renderer: audio.AudioRenderer | null): void {
    this.clearPlaybackTimelineTimer();
    this.queuedFrames = 0;
    this.queuedContentEndFrame = 0;
    this.queuedSampleRate = 0;
    this.playbackMarks = [];
    this.timelineBaseFrame = 0;
    this.timelineStartedAt = 0;
    this.lastReachedFrame = 0;
    this.rendererFrameOrigin = -1;
    this.rendererLogicalFrameOrigin = 0;
    this.timestampFailureLogged = false;
    this.progressMode = 'CLOCK_FALLBACK';
  }

  private clearPlaybackTimelineTimer(): void {
    if (this.timelineTimerId < 0) {
      return;
    }
    clearTimeout(this.timelineTimerId);
    this.timelineTimerId = -1;
  }

  private audioStateName(state: audio.AudioState): string {
    switch (state) {
      case audio.AudioState.STATE_RUNNING:
        return 'STATE_RUNNING';
      case audio.AudioState.STATE_STOPPED:
        return 'STATE_STOPPED';
      case audio.AudioState.STATE_RELEASED:
        return 'STATE_RELEASED';
      case audio.AudioState.STATE_PAUSED:
        return 'STATE_PAUSED';
      default:
        return `STATE_${state}`;
    }
  }

  private async ensureRenderer(sampleRate: number): Promise<audio.AudioRenderer> {
    const nextSampleRate = this.toAudioSampleRate(sampleRate);
    if (this.renderer && this.currentSampleRate === nextSampleRate &&
      this.renderer.state !== audio.AudioState.STATE_RELEASED &&
      this.renderer.state !== audio.AudioState.STATE_STOPPED) {
      return this.renderer;
    }
    const previousRenderer = this.renderer;
    const previousWriteCallback = this.rendererWriteCallback;
    const previousInterruptCallback = this.rendererInterruptCallback;
    this.renderer = null;
    this.rendererWriteCallback = null;
    this.rendererInterruptCallback = null;
    if (previousRenderer) {
      await this.releaseRenderer(previousRenderer, previousWriteCallback, previousInterruptCallback);
    }
    this.currentSampleRate = nextSampleRate;
    const options: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: nextSampleRate,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        channelLayout: audio.AudioChannelLayout.CH_LAYOUT_MONO
      },
      rendererInfo: {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
        rendererFlags: 0
      }
    };
    const renderer = await audio.createAudioRenderer(options);
    const writeCallback: audio.AudioRendererWriteDataCallback = (data: ArrayBuffer):
      audio.AudioDataCallbackResult => {
      return this.handleRendererWriteData(data);
    };
    renderer.on('writeData', writeCallback);
    const interruptCallback = (event: audio.InterruptEvent): void => {
      this.handleAudioInterrupt(renderer, event);
    };
    renderer.on('audioInterrupt', interruptCallback);
    this.rendererWriteCallback = writeCallback;
    this.rendererInterruptCallback = interruptCallback;
    this.renderer = renderer;
    console.info(`[TTS] audio renderer created: ${this.debugState()}`);
    return renderer;
  }

  private async releaseRenderer(renderer: audio.AudioRenderer,
    writeCallback: audio.AudioRendererWriteDataCallback | null,
    interruptCallback: ((event: audio.InterruptEvent) => void) | null): Promise<void> {
    if (writeCallback) {
      try {
        renderer.off('writeData', writeCallback);
      } catch (error) {
        console.warn('[TTS] unregister pcm write callback failed:', error);
      }
    }
    if (interruptCallback) {
      try {
        renderer.off('audioInterrupt', interruptCallback);
      } catch (error) {
        console.warn('[TTS] unregister pcm interrupt callback failed:', error);
      }
    }
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

  private handleAudioInterrupt(renderer: audio.AudioRenderer, event: audio.InterruptEvent): void {
    if (renderer !== this.renderer) {
      return;
    }
    console.info(`[TTS] pcm audio interrupt: hint=${event.hintType},force=${event.forceType},` +
      `state=${this.audioStateName(renderer.state)},${this.debugState()}`);
    const hint = event.hintType;
    if (hint === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      // Keep the application's stream gain invariant. FORCE ducking is
      // performed/restored by the system mixer; applying another 0.35 gain for
      // SHARE caused the rare but clearly audible down/up volume step.
      this.systemDucked = event.forceType === audio.InterruptForceType.INTERRUPT_FORCE;
      console.info(`[TTS] pcm duck handled by system mixer: forced=${this.systemDucked}`);
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
      this.systemDucked = false;
      console.info('[TTS] pcm unduck received; application stream gain remains unchanged');
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
      hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      this.interruptRevision++;
      this.interruptResumeAllowed = hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE && !this.paused;
      this.updatePlaybackTimeline(this.playGeneration);
      this.systemInterrupted = true;
      if (hint === audio.InterruptHint.INTERRUPT_HINT_STOP) this.paused = true;
      this.updatePlaybackTimeline(this.playGeneration);
      // SHARE requires the application to pause. FORCE has already paused/stopped the renderer.
      if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE &&
        renderer.state === audio.AudioState.STATE_RUNNING) {
        this.interruptPausePromise = renderer.pause().catch((error: Error) => {
          console.warn('[TTS] pcm interrupt pause failed:', error);
        });
      }
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      if (!this.systemInterrupted || !this.interruptResumeAllowed || this.paused) return;
      const revision = this.interruptRevision;
      if (this.interruptResumeRevision === revision) return;
      this.interruptResumeRevision = revision;
      this.resumeRendererAfterInterrupt(renderer, revision);
    }
  }

  private async resumeRendererAfterInterrupt(renderer: audio.AudioRenderer, revision: number): Promise<void> {
    await this.interruptPausePromise;
    if (renderer !== this.renderer || revision !== this.interruptRevision || this.paused ||
      !this.systemInterrupted || !this.interruptResumeAllowed) {
      return;
    }
    try {
      await renderer.setVolume(1);
      if (renderer !== this.renderer || revision !== this.interruptRevision || this.paused ||
        !this.interruptResumeAllowed) return;
      if (renderer.state !== audio.AudioState.STATE_RUNNING) {
        await renderer.start();
      }
      if (renderer !== this.renderer) return;
      if (revision !== this.interruptRevision || this.paused || !this.interruptResumeAllowed) {
        if ((this.paused || this.systemInterrupted) && renderer.state === audio.AudioState.STATE_RUNNING) {
          await renderer.pause();
        }
        return;
      }
      this.systemInterrupted = false;
      this.interruptResumeAllowed = false;
      this.systemDucked = false;
      if (renderer === this.renderer && renderer.state === audio.AudioState.STATE_RUNNING) {
        this.rendererFrameOrigin = -1;
        this.rendererLogicalFrameOrigin = this.lastReachedFrame;
        this.timelineBaseFrame = this.lastReachedFrame;
        this.timelineStartedAt = Date.now();
        this.updatePlaybackTimeline(this.playGeneration);
        this.resolvePlaybackWaiters();
      }
    } catch (error) {
      console.warn('[TTS] resume interrupted pcm renderer failed:', error);
    } finally {
      if (this.interruptResumeRevision === revision) this.interruptResumeRevision = -1;
    }
  }

  private handleRendererWriteData(data: ArrayBuffer): audio.AudioDataCallbackResult {
    if (this.paused || this.systemInterrupted || !data || data.byteLength === 0 || this.pendingWrites.length === 0) {
      return audio.AudioDataCallbackResult.INVALID;
    }
    const output = new Uint8Array(data);
    let outputOffset = 0;
    while (outputOffset < output.length && this.pendingWrites.length > 0) {
      const pending = this.pendingWrites[0];
      if (pending.generation !== this.playGeneration) {
        this.pendingWrites.shift();
        const abandonedBytes = Math.max(0, pending.data.length - pending.offset);
        this.pendingWriteBytes = Math.max(0, this.pendingWriteBytes - abandonedBytes);
        pending.resolve();
        continue;
      }
      const remaining = pending.data.length - pending.offset;
      const copyLength = Math.min(remaining, output.length - outputOffset);
      output.set(pending.data.subarray(pending.offset, pending.offset + copyLength), outputOffset);
      pending.offset += copyLength;
      outputOffset += copyLength;
      this.pendingWriteBytes = Math.max(0, this.pendingWriteBytes - copyLength);
      if (pending.offset >= pending.data.length) {
        this.pendingWrites.shift();
        pending.resolve();
      }
    }
    if (outputOffset < output.length) {
      output.fill(0, outputOffset);
      const paddingFrames = Math.floor((output.length - outputOffset) / 2);
      this.queuedFrames += paddingFrames;
      console.info(`[TTS] pcm write tail padded: bytes=${output.length - outputOffset},` +
        `frames=${paddingFrames}`);
    }
    return audio.AudioDataCallbackResult.VALID;
  }

  private discardPendingWrite(pendingWrite: PendingPcmWrite): void {
    const index = this.pendingWrites.indexOf(pendingWrite);
    if (index >= 0) {
      this.pendingWrites.splice(index, 1);
      const remaining = Math.max(0, pendingWrite.data.length - pendingWrite.offset);
      this.pendingWriteBytes = Math.max(0, this.pendingWriteBytes - remaining);
    }
    pendingWrite.resolve();
  }

  private resolvePendingWrites(): void {
    const writes = this.pendingWrites.splice(0, this.pendingWrites.length);
    this.pendingWriteBytes = 0;
    for (const pending of writes) {
      pending.resolve();
    }
  }

  private toAudioSampleRate(sampleRate: number): audio.AudioSamplingRate {
    switch (sampleRate) {
      case 8000:
        return audio.AudioSamplingRate.SAMPLE_RATE_8000;
      case 11025:
        return audio.AudioSamplingRate.SAMPLE_RATE_11025;
      case 12000:
        return audio.AudioSamplingRate.SAMPLE_RATE_12000;
      case 22050:
        return audio.AudioSamplingRate.SAMPLE_RATE_22050;
      case 24000:
        return audio.AudioSamplingRate.SAMPLE_RATE_24000;
      case 32000:
        return audio.AudioSamplingRate.SAMPLE_RATE_32000;
      case 44100:
        return audio.AudioSamplingRate.SAMPLE_RATE_44100;
      case 48000:
        return audio.AudioSamplingRate.SAMPLE_RATE_48000;
      case 96000:
        return audio.AudioSamplingRate.SAMPLE_RATE_96000;
      case 16000:
      default:
        return audio.AudioSamplingRate.SAMPLE_RATE_16000;
    }
  }
}
