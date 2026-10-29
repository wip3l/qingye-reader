import { avSession } from '@kit.AVSessionKit';

/** 系统媒体控制（状态栏、锁屏、通知栏）的命令，由当前接管播放器的听书页提供。 */
export interface AudioBookMediaCommands {
  play: () => void;
  pause: () => void;
  stop: () => void;
  next: () => void;
  previous: () => void;
  seek: (time: number) => void;
  setSpeed: (speed: number) => void;
  keepAlive: () => Promise<void>;
}

/**
 * 听书的媒体会话、后台播放许可和保活心跳，整个进程只有一份，和 RemoteAudioPlayback 同生命周期。
 *
 * 必须放在独立模块里：写在 pages/AudioBook.ets 里时，每次重新打开听书页都拿到一份全新的静态字段，
 * 新页面看不到旧页面建的会话，再建就报"session is existed"（一个 Ability 只能有一个会话），
 * 通知栏的命令也一直发给旧页面，控件就失效了。
 */
export class AudioBookAvSessionHolder {
  static session: avSession.AVSession | null = null;
  /** 会话上的回调只注册一次，转发到这里；页面接管播放器时替换它。 */
  static commands: AudioBookMediaCommands | null = null;
  static sessionStarting: boolean = false;
  static backgroundRunning: boolean = false;
  static backgroundStarting: boolean = false;
  static backgroundDesired: boolean = false;
  static heartbeatId: number = -1;
}
