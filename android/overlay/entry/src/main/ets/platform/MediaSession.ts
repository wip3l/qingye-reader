// platform/MediaSession.ts 的安卓实现：用安卓 MediaSession（经 MediaBridge.java）做 avSession 的替身。
// 只实现朗读（ReaderTtsMediaSession）和听书（AudioBook）用到的接口；封面图（PixelMap）过不了桥，安卓通知栏不显示封面。
import { common, WantAgent } from '@kit.AbilityKit';
import { callMedia, setMediaCommandHandler } from './MediaBridgeClient';

type Handler = Function;

/** 当前接收命令的会话；和鸿蒙一样，一个进程同时只有一个会话。 */
let current: avSession.AVSession | null = null;

setMediaCommandHandler((command: string, argument: string): void => {
  if (current) current.dispatchCommand(command, argument);
});

export namespace avSession {
  export enum PlaybackState {
    PLAYBACK_STATE_INITIAL = 0,
    PLAYBACK_STATE_PREPARE = 1,
    PLAYBACK_STATE_PLAY = 2,
    PLAYBACK_STATE_PAUSE = 3,
    PLAYBACK_STATE_FAST_FORWARD = 4,
    PLAYBACK_STATE_REWIND = 5,
    PLAYBACK_STATE_STOP = 6,
    PLAYBACK_STATE_COMPLETED = 7,
    PLAYBACK_STATE_RELEASED = 8,
    PLAYBACK_STATE_ERROR = 9,
    PLAYBACK_STATE_IDLE = 10,
    PLAYBACK_STATE_BUFFERING = 11
  }

  export enum LoopMode {
    LOOP_MODE_SEQUENCE = 0,
    LOOP_MODE_SINGLE = 1,
    LOOP_MODE_LIST = 2,
    LOOP_MODE_SHUFFLE = 3
  }

  export interface PlaybackPosition {
    elapsedTime: number;
    updateTime: number;
  }

  export interface AVPlaybackState {
    state?: PlaybackState;
    speed?: number;
    position?: PlaybackPosition;
    bufferedTime?: number;
    loopMode?: LoopMode;
    isFavorite?: boolean;
    activeItemId?: number;
    extras?: Record<string, Object>;
  }

  export interface AVMetadata {
    assetId: string;
    title?: string;
    artist?: string;
    author?: string;
    avQueueName?: string;
    avQueueId?: string;
    avQueueImage?: Object;
    album?: string;
    writer?: string;
    composer?: string;
    duration?: number;
    mediaImage?: Object;
    subtitle?: string;
    description?: string;
    lyric?: string;
    previousAssetId?: string;
    nextAssetId?: string;
  }

  export class AVSession {
    readonly sessionTag: string;
    private handlers: Map<string, Handler> = new Map<string, Handler>();

    constructor(tag: string) {
      this.sessionTag = tag;
    }

    on(type: string, callback: Handler): void {
      this.handlers.set(type, callback);
      current = this;
    }

    off(type: string, _callback?: Handler): void {
      this.handlers.delete(type);
    }

    dispatchCommand(command: string, argument: string): void {
      const handler = this.handlers.get(command);
      if (!handler) return;
      if (command === 'seek') handler(Number(argument) || 0);
      else if (command === 'setSpeed') handler(Number(argument) || 1);
      else handler();
    }

    async setAVMetadata(data: AVMetadata): Promise<void> {
      await callMedia('setMetadata', JSON.stringify({
        title: data.title || '',
        artist: data.artist || data.author || data.subtitle || '',
        album: data.album || data.avQueueName || '',
        duration: typeof data.duration === 'number' ? data.duration : -1
      }));
    }

    async setAVPlaybackState(state: AVPlaybackState): Promise<void> {
      let name = 'stop';
      switch (state.state) {
        case PlaybackState.PLAYBACK_STATE_PLAY:
          name = 'play';
          break;
        case PlaybackState.PLAYBACK_STATE_PAUSE:
          name = 'pause';
          break;
        case PlaybackState.PLAYBACK_STATE_BUFFERING:
        case PlaybackState.PLAYBACK_STATE_PREPARE:
          name = 'buffering';
          break;
        default:
          name = 'stop';
      }
      await callMedia('setPlaybackState', JSON.stringify({
        state: name,
        position: state.position ? state.position.elapsedTime : -1,
        speed: state.speed || 1
      }));
    }

    async setAVQueueTitle(_title: string): Promise<void> {
    }

    async setExtras(_extras: Record<string, Object>): Promise<void> {
    }

    async setLaunchAbility(_ability: WantAgent): Promise<void> {
    }

    async activate(): Promise<void> {
      current = this;
      await callMedia('activate');
    }

    async deactivate(): Promise<void> {
      await callMedia('deactivate');
    }

    async destroy(): Promise<void> {
      this.handlers.clear();
      if (current === this) current = null;
      await callMedia('destroy');
    }
  }

  export async function createAVSession(_context: common.Context, tag: string, _type: string): Promise<AVSession> {
    await callMedia('create', tag);
    const session = new AVSession(tag);
    current = session;
    return session;
  }
}
