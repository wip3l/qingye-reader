import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VideoPlaylistMode } from '../core/book/VideoPlaybackSupport';
import { VideoPlaylistProxy, VideoPlaylistSession } from './VideoPlaylistProxy';

/** 与 Video 组件同名的回调，播放页对两种播放器只维护一套进度与跳转逻辑。 */
export interface VideoAvSessionListener {
  onPrepared: (durationSec: number) => void;
  onStart: () => void;
  onPause: () => void;
  onUpdate: (seconds: number) => void;
  onSeeked: (seconds: number) => void;
  onFinish: () => void;
  onError: (code: number) => void;
  onVideoSize: (width: number, height: number) => void;
}

const STATE_WAIT_MS: number = 30000;

/**
 * 书源要求带请求头（Referer、Cookie 等）的视频。Video 组件只接收地址，请求头会被丢掉，
 * 校验来源的片段服务器播到一半就拒绝；这里改用 AVPlayer，把请求头交给每一次媒体请求。
 * 画面输出到 XComponent 的 Surface，Surface 就绪前不会 prepare。
 */
export class VideoAvSession {
  private url: string;
  private headers: Record<string, string>;
  private listener: VideoAvSessionListener;
  private player: media.AVPlayer | null = null;
  private released: boolean = false;
  private prepared: boolean = false;
  private surfaceId: string = '';
  private surfaceWaiters: Array<() => void> = [];
  private stateWaiters: Array<(state: string) => void> = [];
  private speed: number = 1;
  private playlist: VideoPlaylistMode | null;
  private proxySession: VideoPlaylistSession | null = null;
  private live: boolean = false;
  private mediaSource: media.MediaSource | null = null;

  /** playlist 不为空时播放列表经本机代理取回处理（书源写了 content.playlist），见 VideoPlaylistProxy。 */
  constructor(url: string, headers: Record<string, string>, speed: number, listener: VideoAvSessionListener,
    playlist: VideoPlaylistMode | null = null) {
    this.url = url;
    this.headers = headers;
    this.speed = speed;
    this.listener = listener;
    this.playlist = playlist;
  }

  /** 本机代理最近一次取播放列表失败的原因；没走代理或没失败时为空。 */
  playlistError(): string {
    return this.proxySession ? this.proxySession.lastError : '';
  }

  attachSurface(surfaceId: string): void {
    if (!surfaceId || this.surfaceId) return;
    this.surfaceId = surfaceId;
    const waiters = this.surfaceWaiters;
    this.surfaceWaiters = [];
    for (const resolve of waiters) resolve();
  }

  async open(): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      if (this.released) {
        player.release().catch((): void => {});
        return;
      }
      this.player = player;
      player.on('stateChange', (state: string): void => this.onStateChange(player, state));
      player.on('timeUpdate', (ms: number): void => {
        if (this.isCurrent(player)) this.listener.onUpdate(Math.max(0, ms || 0) / 1000);
      });
      player.on('seekDone', (ms: number): void => {
        if (this.isCurrent(player)) this.listener.onSeeked(Math.max(0, ms || 0) / 1000);
      });
      player.on('videoSizeChange', (width: number, height: number): void => {
        if (this.isCurrent(player)) this.listener.onVideoSize(width, height);
      });
      player.on('error', (error: BusinessError): void => {
        if (this.isCurrent(player)) this.listener.onError(error && error.code ? error.code : 0);
      });
      let url = this.url;
      if (this.playlist) {
        // 播放列表走本机代理，分片仍由播放器直接下载；开不了代理时照常播放原地址。
        const proxySession = await VideoPlaylistProxy.shared().open(this.url, this.headers, this.playlist);
        if (!this.isCurrent(player)) {
          if (proxySession) VideoPlaylistProxy.shared().close(proxySession);
          return;
        }
        this.proxySession = proxySession;
        if (proxySession) url = proxySession.entryUrl;
        console.info(`[VideoAvSession] playlist proxy=${proxySession !== null} lowLatency=${this.playlist.lowLatency}`);
      }
      // 请求头交给播放器的每一次请求：发往本机代理的会被忽略，发往源站的分片、密钥照样带上。
      const source = media.createMediaSourceWithUrl(url, this.headers);
      this.mediaSource = source;
      await player.setMediaSource(source);
      // setMediaSource 返回不代表已进入 initialized，提前 prepare 会被拒绝。
      await this.waitForState(player, 'initialized');
      if (!this.isCurrent(player)) return;
      await this.waitForSurface();
      if (!this.isCurrent(player)) return;
      player.surfaceId = this.surfaceId;
      player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MOVIE, rendererFlags: 0 };
      await player.prepare();
      await this.waitForState(player, 'prepared');
      if (!this.isCurrent(player)) return;
      this.prepared = true;
      // 直播（时长为 0）不能改倍速：系统会回一个 801 错误事件，播放页会当成播放失败。1 倍也不用设。
      this.live = !(player.duration > 0);
      if (this.speed !== 1) this.applySpeed(player);
      this.listener.onPrepared(Math.max(0, player.duration || 0) / 1000);
    } catch (error) {
      if (this.released) return;
      const code = (error as BusinessError).code;
      console.warn('[VideoAvSession] open failed:', (error as Error).message, code);
      this.listener.onError(typeof code === 'number' ? code : 0);
    }
  }

  start(): void {
    const player = this.player;
    if (!player || !this.prepared || this.released) return;
    const state = player.state;
    if (state !== 'prepared' && state !== 'paused' && state !== 'completed') return;
    player.play().catch((error: Error): void => console.warn('[VideoAvSession] play failed:', error.message));
  }

  pause(): void {
    const player = this.player;
    if (!player || this.released || player.state !== 'playing') return;
    player.pause().catch((error: Error): void => console.warn('[VideoAvSession] pause failed:', error.message));
  }

  /** accurate 为 false 时落在前一个关键帧，网络流上比逐帧精确定位快得多。 */
  seek(seconds: number, accurate: boolean): void {
    const player = this.player;
    if (!player || !this.prepared || this.released) return;
    const state = player.state;
    if (state !== 'prepared' && state !== 'playing' && state !== 'paused' && state !== 'completed') return;
    player.seek(Math.max(0, Math.floor(seconds * 1000)),
      accurate ? media.SeekMode.SEEK_CLOSEST : media.SeekMode.SEEK_PREV_SYNC);
  }

  setSpeed(speed: number): void {
    this.speed = speed;
    if (this.player && this.prepared && !this.released) this.applySpeed(this.player);
  }

  release(): void {
    if (this.released) return;
    this.released = true;
    const player = this.player;
    this.player = null;
    // 唤醒还在等 Surface 的 open()，它看到已释放会自己退出，不会一直挂着。
    const surfaceWaiters = this.surfaceWaiters;
    this.surfaceWaiters = [];
    for (const resolve of surfaceWaiters) resolve();
    this.stateWaiters = [];
    if (player) player.release().catch((): void => {});
    const proxySession = this.proxySession;
    this.proxySession = null;
    if (proxySession) VideoPlaylistProxy.shared().close(proxySession);
    this.mediaSource = null;
  }

  private isCurrent(player: media.AVPlayer): boolean {
    return !this.released && this.player === player;
  }

  private onStateChange(player: media.AVPlayer, state: string): void {
    if (!this.isCurrent(player)) return;
    const waiters = this.stateWaiters;
    this.stateWaiters = [];
    for (const notify of waiters) notify(state);
    if (state === 'playing') this.listener.onStart();
    else if (state === 'paused') this.listener.onPause();
    else if (state === 'completed') this.listener.onFinish();
  }

  private waitForState(player: media.AVPlayer, target: string): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      if (player.state === target) {
        resolve();
        return;
      }
      let done = false;
      const timer = setTimeout((): void => {
        if (done) return;
        done = true;
        reject(new Error(`等待播放器进入 ${target} 超时`));
      }, STATE_WAIT_MS);
      const check = (state: string): void => {
        if (done) return;
        if (state === target || player.state === target) {
          done = true;
          clearTimeout(timer);
          resolve();
        } else if (state === 'error' || this.released) {
          done = true;
          clearTimeout(timer);
          reject(new Error('播放器出错'));
        } else {
          this.stateWaiters.push(check);
        }
      };
      this.stateWaiters.push(check);
    });
  }

  private waitForSurface(): Promise<void> {
    if (this.surfaceId || this.released) return Promise.resolve();
    return new Promise<void>((resolve): void => {
      this.surfaceWaiters.push(resolve);
    });
  }

  private applySpeed(player: media.AVPlayer): void {
    if (this.live) return;
    let value = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (this.speed === 0.75) value = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    else if (this.speed === 1.25) value = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    else if (this.speed === 1.75) value = media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    else if (this.speed === 2) value = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    else if (this.speed === 3) value = media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
    try { player.setSpeed(value); } catch (error) {
      console.warn('[VideoAvSession] set speed failed:', (error as Error).message);
    }
  }
}
