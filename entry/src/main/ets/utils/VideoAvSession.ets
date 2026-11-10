import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';

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

  constructor(url: string, headers: Record<string, string>, speed: number, listener: VideoAvSessionListener) {
    this.url = url;
    this.headers = headers;
    this.speed = speed;
    this.listener = listener;
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
      await player.setMediaSource(media.createMediaSourceWithUrl(this.url, this.headers));
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
      this.applySpeed(player);
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
