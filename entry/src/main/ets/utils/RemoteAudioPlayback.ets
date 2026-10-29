import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';

export interface RemoteAudioPlaybackListener {
  onStateChanged(state: string): void;
  onPositionChanged(positionMs: number, durationMs: number): void;
  onPlaybackCompleted(): void;
  onPlaybackError(message: string): void;
}

/**
 * Process-local audiobook player. It keeps playing when the page is temporarily hidden.
 * `url` is either an http(s) stream or the absolute path of a downloaded chapter.
 */
export class RemoteAudioPlayback {
  private static instance: RemoteAudioPlayback | null = null;
  private player: media.AVPlayer | null = null;
  private listener: RemoteAudioPlaybackListener | null = null;
  private generation: number = 0;
  /** play() 已开始但还没出声的代次；切章时据此丢弃半途的播放器，避免旧章节随后响起。 */
  private loadingGeneration: number = -1;
  private interruptPaused: boolean = false;
  private sleepTimerId: number = -1;
  private sleepEndAt: number = 0;
  /**
   * 续播或拖动定位还没完成时的目标位置。期间 timeUpdate 报的仍是旧位置（常常是 0），不能外传，
   * 否则页面会把它当成进度存下，下次打开就从章节开头播。
   */
  private pendingSeekMs: number = -1;
  /** 定位完成后，用下一次 timeUpdate 核对是否真的跳过去了；有些网络流起播前的 seek 会被忽略。 */
  private verifySeekMs: number = -1;
  private seekRetried: boolean = false;
  private seekTimeoutId: number = -1;
  /** 正在播放的离线音频文件；播放器释放后才关闭。 */
  private localFile: fs.File | null = null;

  bookUrl: string = '';
  chapterIndex: number = -1;
  mediaUrl: string = '';
  private mediaHeaders: Record<string, string> = {};
  state: string = 'idle';
  positionMs: number = 0;
  durationMs: number = 0;
  speed: number = 1;

  static get(): RemoteAudioPlayback {
    if (!RemoteAudioPlayback.instance) RemoteAudioPlayback.instance = new RemoteAudioPlayback();
    return RemoteAudioPlayback.instance;
  }

  attach(listener: RemoteAudioPlaybackListener): void {
    this.listener = listener;
    listener.onStateChanged(this.state);
    listener.onPositionChanged(this.positionMs, this.durationMs);
  }

  detach(listener: RemoteAudioPlaybackListener): void {
    if (this.listener === listener) this.listener = null;
  }

  matches(bookUrl: string, chapterIndex: number): boolean {
    return !!this.player && this.bookUrl === bookUrl && this.chapterIndex === chapterIndex && !!this.mediaUrl;
  }

  async play(bookUrl: string, chapterIndex: number, url: string, headers: Record<string, string>,
    startPositionMs: number, speed: number, startTiming: AudioStartTiming | null = null): Promise<void> {
    const generation = ++this.generation;
    this.loadingGeneration = generation;
    const timing = startTiming || new AudioStartTiming(chapterIndex);
    this.interruptPaused = false;
    this.resetSeek();
    await this.releasePlayer();
    this.bookUrl = bookUrl;
    this.chapterIndex = chapterIndex;
    this.mediaUrl = url;
    this.mediaHeaders = headers;
    this.positionMs = Math.max(0, startPositionMs || 0);
    // 加载期间播放器会先报 0 秒（本地文件在 prepared 时就报）。续播目标在定位完成前一直挡住这些旧位置，
    // 否则既会跳过定位，又会被页面当成进度存下。
    const resumeMs = this.positionMs;
    if (resumeMs > 0) this.pendingSeekMs = resumeMs;
    this.durationMs = 0;
    this.speed = this.normalizeSpeed(speed);
    this.setState('loading');

    const player = await media.createAVPlayer();
    timing.mark('create-player');
    if (generation !== this.generation) {
      await player.release();
      return;
    }
    this.player = player;
    player.on('stateChange', (state: string): void => {
      if (generation !== this.generation) return;
      // createAVPlayer starts in idle. While a media source is being attached, keep the public
      // state as loading instead of briefly advertising an idle player that cannot be resumed.
      this.setState(state === 'idle' && !!this.mediaUrl ? 'loading' : state);
      if (state === 'completed') this.listener?.onPlaybackCompleted();
    });
    player.on('timeUpdate', (position: number): void => {
      if (generation !== this.generation) return;
      // Some AVPlayer implementations do not fan out multiple stateChange callbacks reliably.
      // Keep the public state in sync from the player's authoritative state as a fallback.
      this.syncPlayerState(player, generation);
      if (this.pendingSeekMs >= 0) return;
      if (this.verifySeekMs >= 0) {
        const target = this.verifySeekMs;
        this.verifySeekMs = -1;
        if ((position || 0) < target - 5000 && !this.seekRetried) {
          this.seekRetried = true;
          this.beginSeek(player, generation, target);
          return;
        }
      }
      this.positionMs = Math.max(0, position || 0);
      this.listener?.onPositionChanged(this.positionMs, this.durationMs);
    });
    player.on('durationUpdate', (duration: number): void => {
      if (generation !== this.generation) return;
      this.durationMs = Math.max(0, duration || 0);
      this.listener?.onPositionChanged(this.positionMs, this.durationMs);
    });
    player.on('error', (error: Error): void => {
      if (generation !== this.generation) return;
      this.setState('error');
      this.listener?.onPlaybackError(error.message || String(error));
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      this.handleAudioInterrupt(player, generation, event);
    });
    player.on('seekDone', (): void => {
      if (generation !== this.generation || player !== this.player) return;
      this.finishSeek();
    });

    try {
      if (url.startsWith('/')) {
        // 离线下载的音频。要给出完整长度，只给 fd 会被当成直播流，倍速和拖动都会失效。
        const file = fs.openSync(url, fs.OpenMode.READ_ONLY);
        this.localFile = file;
        player.fdSrc = { fd: file.fd, offset: 0, length: fs.statSync(url).size };
      } else {
        const mediaSource = media.createMediaSourceWithUrl(url, headers);
        await player.setMediaSource(mediaSource);
      }
      timing.mark('set-media-source');
      if (generation !== this.generation) return;
      // setMediaSource() completing does not guarantee that AVPlayer has emitted initialized yet.
      // prepare() is only legal after that transition; calling it while still idle produces
      // "Prepare operation only supports stopped/initialized" on real devices.
      await this.waitForInitialized(player, generation);
      timing.mark('initialized');
      if (generation !== this.generation) return;
      player.audioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
        rendererFlags: 0
      };
      await player.prepare();
      if (generation !== this.generation) return;
      // 与 setMediaSource 同理：prepare() 返回不保证已经进入 prepared。网络流缓冲较慢时直接 play() 会报
      // "The current state is initialized. Play operation only supports prepared/paused/completed"。
      await this.waitForPrepared(player, generation);
      timing.mark('prepared');
      if (generation !== this.generation) return;
      this.durationMs = Math.max(0, player.duration || this.durationMs);
      this.applySpeed(player, this.speed);
      if (resumeMs > 0 && (this.durationMs <= 0 || resumeMs < this.durationMs - 1000)) {
        this.beginSeek(player, generation, resumeMs);
      } else {
        this.resetSeek();
        this.positionMs = 0;
      }
      await player.play();
      timing.mark('play');
      if (generation === this.generation && player === this.player) {
        this.setState('playing');
        timing.finish('playing');
      }
    } catch (error) {
      if (generation !== this.generation) return;
      timing.finish('failed');
      const message = error instanceof Error ? error.message : String(error);
      this.setState('error');
      throw new Error(message);
    } finally {
      if (this.loadingGeneration === generation) this.loadingGeneration = -1;
    }
  }

  /**
   * 切章时调用：若上一章的 play() 还没出声，立即作废并释放那个播放器，状态保持 loading。
   * 已经在播的旧章节不受影响，等新章节地址就绪后由 play() 正常替换，媒体会话和后台任务不会中断。
   */
  async abortPendingLoad(): Promise<void> {
    if (this.loadingGeneration < 0 || this.loadingGeneration !== this.generation) return;
    this.generation++;
    this.loadingGeneration = -1;
    await this.releasePlayer();
  }

  async pause(): Promise<void> {
    const player = this.player;
    if (!player || player.state !== 'playing') return;
    await player.pause();
    if (player === this.player) this.setState('paused');
  }

  async resume(): Promise<void> {
    if (this.state === 'loading') return;
    const player = this.player;
    const playerState = player?.state || '';
    if (player && playerState === 'playing') {
      this.setState('playing');
      return;
    }
    if (player && (playerState === 'paused' || playerState === 'prepared' || playerState === 'completed')) {
      try {
        if (playerState === 'completed') player.seek(0, media.SeekMode.SEEK_CLOSEST);
        await player.play();
        if (player === this.player) this.setState('playing');
        return;
      } catch (error) {
        if (player !== this.player) return;
        console.warn('[AudioBook] resume failed, rebuilding player:', error);
      }
    }
    // Another app taking audio focus permanently (forced STOP interrupt) leaves AVPlayer in
    // stopped/error, where play() is illegal. Without a rebuild every play button, including
    // the system media capsule, stays dead until the process restarts.
    if (!this.mediaUrl) return;
    await this.play(this.bookUrl, this.chapterIndex, this.mediaUrl, this.mediaHeaders, this.positionMs,
      this.speed);
  }

  seek(positionMs: number): void {
    const player = this.player;
    if (!player) return;
    const target = Math.max(0, this.durationMs > 0 ? Math.min(positionMs, this.durationMs) : positionMs);
    this.seekRetried = false;
    this.beginSeek(player, this.generation, target);
  }

  private beginSeek(player: media.AVPlayer, generation: number, target: number): void {
    this.clearSeekTimeout();
    this.pendingSeekMs = target;
    this.verifySeekMs = -1;
    this.positionMs = target;
    this.listener?.onPositionChanged(this.positionMs, this.durationMs);
    // seekDone 偶尔不回调（网络流缓冲失败等），超时后照常收 timeUpdate，并按定位完成核对一次。
    this.seekTimeoutId = setTimeout((): void => {
      this.seekTimeoutId = -1;
      if (generation === this.generation && player === this.player) this.finishSeek();
    }, 4000);
    try {
      player.seek(target, media.SeekMode.SEEK_CLOSEST);
    } catch (_) {
      this.resetSeek();
    }
  }

  private finishSeek(): void {
    if (this.pendingSeekMs < 0) return;
    this.clearSeekTimeout();
    this.verifySeekMs = this.pendingSeekMs;
    this.pendingSeekMs = -1;
  }

  private resetSeek(): void {
    this.clearSeekTimeout();
    this.pendingSeekMs = -1;
    this.verifySeekMs = -1;
    this.seekRetried = false;
  }

  private clearSeekTimeout(): void {
    if (this.seekTimeoutId >= 0) clearTimeout(this.seekTimeoutId);
    this.seekTimeoutId = -1;
  }

  setSpeed(speed: number): void {
    this.speed = this.normalizeSpeed(speed);
    const player = this.player;
    if (player) this.applySpeed(player, this.speed);
  }

  setSleepTimer(minutes: number): void {
    this.clearSleepTimer();
    if (minutes <= 0) return;
    this.sleepEndAt = Date.now() + minutes * 60 * 1000;
    this.sleepTimerId = setInterval((): void => {
      if (this.sleepEndAt > Date.now()) return;
      this.clearSleepTimer();
      this.pause().catch(() => {});
    }, 1000);
  }

  sleepRemainingSeconds(): number {
    return this.sleepEndAt > 0 ? Math.max(0, Math.ceil((this.sleepEndAt - Date.now()) / 1000)) : 0;
  }

  async stop(): Promise<void> {
    this.generation++;
    this.interruptPaused = false;
    this.resetSeek();
    this.clearSleepTimer();
    await this.releasePlayer();
    this.bookUrl = '';
    this.chapterIndex = -1;
    this.mediaUrl = '';
    this.mediaHeaders = {};
    this.positionMs = 0;
    this.durationMs = 0;
    this.setState('idle');
  }

  private setState(state: string): void {
    if (this.state === state) return;
    this.state = state || 'idle';
    this.listener?.onStateChanged(this.state);
  }

  private syncPlayerState(player: media.AVPlayer, generation: number): void {
    if (generation !== this.generation || player !== this.player) return;
    const state = player.state || '';
    if (state === 'playing' || state === 'paused' || state === 'completed' || state === 'prepared' ||
      state === 'initialized' || state === 'stopped' || state === 'released' || state === 'error') {
      this.setState(state);
    }
  }

  private normalizeSpeed(speed: number): number {
    return Math.max(0.5, Math.min(2.5, speed || 1));
  }

  private applySpeed(player: media.AVPlayer, speed: number): void {
    try {
      player.setPlaybackRate(speed);
    } catch (_) {
      try {
        if (speed <= 0.8) player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_75_X);
        else if (speed <= 1.15) player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
        else if (speed <= 1.6) player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_25_X);
        else player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
      } catch (_) {}
    }
  }

  private handleAudioInterrupt(player: media.AVPlayer, generation: number,
    event: audio.InterruptEvent): void {
    if (generation !== this.generation || player !== this.player) return;
    const hint = event.hintType;
    if (hint === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE) {
        try { player.setVolume(0.35); } catch (_) {}
      }
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
      try { player.setVolume(1); } catch (_) {}
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.interruptPaused = true;
      if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE && player.state === 'playing') {
        player.pause().catch(() => {});
      }
      this.syncStateAfterInterrupt(player, generation);
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      this.interruptPaused = false;
      this.syncStateAfterInterrupt(player, generation);
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      try { player.setVolume(1); } catch (_) {}
      if (this.interruptPaused && player.state !== 'playing') {
        this.interruptPaused = false;
        this.resume().catch((error: Error) => {
          this.listener?.onPlaybackError(error.message || String(error));
        });
      } else {
        this.interruptPaused = false;
      }
    }
  }

  /** A forced interrupt stops timeUpdate, so the stateChange fallback there never runs. */
  private syncStateAfterInterrupt(player: media.AVPlayer, generation: number): void {
    setTimeout((): void => {
      if (player.state !== 'playing') this.syncPlayerState(player, generation);
    }, 300);
  }

  private async releasePlayer(): Promise<void> {
    const player = this.player;
    this.player = null;
    if (!player) return;
    try {
      if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared' ||
        player.state === 'completed') await player.stop();
    } catch (_) {}
    try {
      await player.release();
    } catch (_) {}
    this.closeLocalFile();
  }

  private closeLocalFile(): void {
    const file = this.localFile;
    this.localFile = null;
    if (!file) return;
    try { fs.closeSync(file); } catch (_) {}
  }

  private waitForPrepared(player: media.AVPlayer, generation: number): Promise<void> {
    const ready = (state: string): boolean => state === 'prepared' || state === 'playing' || state === 'paused' ||
      state === 'completed';
    if (generation !== this.generation || ready(player.state || '')) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const startedAt = Date.now();
      // 和 waitForInitialized 一样用轮询，不另外注册 stateChange 回调。
      const pollId = setInterval((): void => {
        const state = player.state || '';
        if (generation !== this.generation || player !== this.player || ready(state)) {
          clearInterval(pollId);
          resolve();
        } else if (state === 'released' || state === 'error') {
          clearInterval(pollId);
          reject(new Error('音频加载失败'));
        } else if (Date.now() - startedAt > 20000) {
          clearInterval(pollId);
          reject(new Error('音频加载超时'));
        }
      }, 50);
    });
  }

  private waitForInitialized(player: media.AVPlayer, generation: number): Promise<void> {
    if (generation !== this.generation || player.state === 'initialized' || player.state === 'stopped') {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      let settled = false;
      const finish = (error?: Error): void => {
        if (settled) return;
        settled = true;
        clearInterval(pollId);
        clearTimeout(timeoutId);
        if (error) reject(error);
        else resolve();
      };
      // Do not register a second stateChange/error callback here. On some HarmonyOS devices
      // AVPlayer keeps only the last callback for an event, which used to replace the public
      // playback-state listener and leave the UI permanently at "loading" while audio played.
      const pollId = setInterval((): void => {
        if (generation !== this.generation || player !== this.player) {
          finish();
          return;
        }
        const state = player.state || '';
        if (state === 'initialized' || state === 'stopped') finish();
        else if (state === 'released' || state === 'error') {
          finish(new Error(`音频播放器初始化失败：${state}`));
        }
      }, 20);
      const timeoutId = setTimeout((): void => {
        finish(new Error(`音频播放器初始化超时，当前状态：${player.state || 'unknown'}`));
      }, 10000);
      // Close the narrow race where initialized is emitted between the first state check and
      // polling registration.
      if (player.state === 'initialized' || player.state === 'stopped') finish();
    });
  }

  private clearSleepTimer(): void {
    if (this.sleepTimerId >= 0) clearInterval(this.sleepTimerId);
    this.sleepTimerId = -1;
    this.sleepEndAt = 0;
  }
}

/** 记录听书起播各阶段耗时，便于在日志中定位慢在地址解析、缓冲还是播放器本身。不记录音频地址。 */
export class AudioStartTiming {
  private readonly chapterIndex: number;
  private readonly startedAt: number;
  private lastAt: number;
  private readonly stages: string[] = [];
  private finished: boolean = false;

  constructor(chapterIndex: number) {
    this.chapterIndex = chapterIndex;
    this.startedAt = Date.now();
    this.lastAt = this.startedAt;
  }

  mark(stage: string): void {
    const now = Date.now();
    this.stages.push(`${stage}=${now - this.lastAt}ms`);
    this.lastAt = now;
  }

  finish(result: string): void {
    if (this.finished) return;
    this.finished = true;
    console.info(`[AudioBook] start chapter=${this.chapterIndex} ${result} total=${Date.now() - this.startedAt}ms ` +
      this.stages.join(' '));
  }
}
