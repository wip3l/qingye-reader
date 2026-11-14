import { audio } from '@kit.AudioKit';
import deviceInfo from '@ohos.deviceInfo';

/** 会话级焦点变化的监听者；朗读播放器据此和流级 audioInterrupt 一起判断暂停与恢复。 */
export type TtsAudioSessionHintListener = (hint: audio.InterruptHint) => void;
/** 耳机等外接输出设备断开、声音落回扬声器/听筒时通知；有声书据此按用户暂停处理。 */
export type TtsOutputLostListener = () => void;

// AudioSessionBehaviorFlags.PAUSE_WHEN_INTERRUPTED（API 26）。写成数值，低版本设备上读枚举会是 undefined。
const PAUSE_WHEN_INTERRUPTED_FLAG: number = 0x00000004;
const OTHER_AUDIO_POLL_MS: number = 1500;
// 连续这么多次查到“没有别的声音”才算结束，避开切歌、视频换集时的短暂空档。
const OTHER_AUDIO_QUIET_POLLS: number = 2;
const OTHER_AUDIO_MAX_WAIT_MS: number = 60 * 60 * 1000;
// 耳机断开时系统也会发永久停止，和设备变化通知谁先到不一定；这个窗口内断开过就不自动续播。
const OUTPUT_LOST_WINDOW_MS: number = 5000;

/** 应用的音频会话，朗读和有声书共用（两者不会同时播放），按 owner 计数，全部释放后才停用。 */
export class TtsAudioSession {
  private static manager: audio.AudioSessionManager | null = null;
  private static routingManager: audio.AudioRoutingManager | null = null;
  private static owners: Set<string> = new Set<string>();
  private static activationPromise: Promise<void> | null = null;
  private static deactivateTimerId: number = -1;
  private static configured: boolean = false;
  private static hintListeners: Set<TtsAudioSessionHintListener> = new Set<TtsAudioSessionHintListener>();
  private static outputLostListeners: Set<TtsOutputLostListener> = new Set<TtsOutputLostListener>();
  private static outputOnExternalDevice: boolean = false;
  private static outputLostAt: number = 0;
  private static readonly outputRendererInfo: audio.AudioRendererInfo = {
    usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
    rendererFlags: 0
  };

  static async acquire(owner: string): Promise<void> {
    if (!owner) return;
    TtsAudioSession.owners.add(owner);
    TtsAudioSession.cancelPendingDeactivate();
    const manager = TtsAudioSession.getManager();
    if (!manager) return;
    try {
      if (manager.isAudioSessionActivated()) return;
    } catch (_) {
    }
    if (!TtsAudioSession.activationPromise) {
      TtsAudioSession.configure(manager);
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS
      };
      const activation = manager.activateAudioSession(strategy);
      TtsAudioSession.activationPromise = activation;
      activation.then(() => {
        console.info('[TTS] audio session activated: mode=PAUSE_OTHERS');
      }).catch((error: Error) => {
        console.warn('[TTS] activate audio session failed:', error);
      }).finally(() => {
        if (TtsAudioSession.activationPromise === activation) {
          TtsAudioSession.activationPromise = null;
        }
      });
    }
    await TtsAudioSession.activationPromise?.catch(() => {
    });
  }

  static release(owner: string): void {
    if (!owner) return;
    TtsAudioSession.owners.delete(owner);
    if (TtsAudioSession.owners.size > 0) return;
    TtsAudioSession.cancelPendingDeactivate();
    TtsAudioSession.deactivateTimerId = setTimeout(() => {
      TtsAudioSession.deactivateTimerId = -1;
      TtsAudioSession.deactivateIfIdle();
    }, 300);
  }

  static addHintListener(listener: TtsAudioSessionHintListener): void {
    TtsAudioSession.hintListeners.add(listener);
  }

  static removeHintListener(listener: TtsAudioSessionHintListener): void {
    TtsAudioSession.hintListeners.delete(listener);
  }

  static addOutputLostListener(listener: TtsOutputLostListener): void {
    TtsAudioSession.outputLostListeners.add(listener);
    TtsAudioSession.watchOutputDevice();
  }

  static removeOutputLostListener(listener: TtsOutputLostListener): void {
    TtsAudioSession.outputLostListeners.delete(listener);
  }

  /** 最近 OUTPUT_LOST_WINDOW_MS 内（从 since 往前算起）耳机等外接设备断开过：此时的停止不是被别的声音抢走。 */
  static outputLostRecently(since: number = Date.now()): boolean {
    return TtsAudioSession.outputLostAt > 0 && TtsAudioSession.outputLostAt >= since - OUTPUT_LOST_WINDOW_MS;
  }

  /**
   * 朗读被永久停止（别的应用开播视频、音乐）后，等对方的声音结束再返回 true，播放器随即接着读。
   * 系统对永久停止不发恢复通知，只能自己查：通话/响铃场景、其他应用的媒体流都没了，连续两次才算结束。
   * 查不了（低于 API 23）、超时或 cancelled() 为真时返回 false，保持停住，等用户自己点播放。
   * 耳机断开时系统同样发永久停止，那时没有别的声音，不拦住就会几秒后改用外放接着播，所以断开过也返回 false。
   */
  static async waitForOtherAudioToEnd(cancelled: () => boolean): Promise<boolean> {
    const manager = TtsAudioSession.getManager();
    if (!manager || deviceInfo.sdkApiVersion < 23) return false;
    TtsAudioSession.watchOutputDevice();
    const startedAt = Date.now();
    let quietPolls = 0;
    while (Date.now() - startedAt < OTHER_AUDIO_MAX_WAIT_MS) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, OTHER_AUDIO_POLL_MS);
      });
      if (cancelled()) return false;
      if (TtsAudioSession.outputLostRecently(startedAt)) {
        console.info('[TTS] output device lost during interruption, stay paused');
        return false;
      }
      let busy = true;
      try {
        busy = audio.getAudioManager().getAudioSceneSync() !== audio.AudioScene.AUDIO_SCENE_DEFAULT ||
          manager.isOtherMediaPlaying();
      } catch (error) {
        console.warn('[TTS] query other audio failed:', error);
        return false;
      }
      quietPolls = busy ? 0 : quietPolls + 1;
      if (quietPolls >= OTHER_AUDIO_QUIET_POLLS) {
        console.info(`[TTS] other audio ended after ${Date.now() - startedAt}ms`);
        return true;
      }
    }
    return false;
  }

  private static getManager(): audio.AudioSessionManager | null {
    if (TtsAudioSession.manager) return TtsAudioSession.manager;
    try {
      TtsAudioSession.manager = audio.getAudioManager().getSessionManager();
    } catch (error) {
      console.warn('[TTS] get audio session manager failed:', error);
    }
    return TtsAudioSession.manager;
  }

  /**
   * 首次激活前设置一次。API 26 起让系统把“停止”改成“暂停”：别的应用的视频、音乐结束后会发恢复通知，
   * 朗读能自己接着读；以前是永久停止，系统不再通知。必须在激活前设置，激活后设置要重新激活才生效。
   */
  private static configure(manager: audio.AudioSessionManager): void {
    if (TtsAudioSession.configured) return;
    TtsAudioSession.configured = true;
    TtsAudioSession.watchOutputDevice();
    if (deviceInfo.sdkApiVersion >= 26) {
      try {
        manager.setAudioSessionBehavior(PAUSE_WHEN_INTERRUPTED_FLAG);
        console.info('[TTS] audio session behavior: PAUSE_WHEN_INTERRUPTED');
      } catch (error) {
        console.warn('[TTS] set audio session behavior failed:', error);
      }
    }
    if (deviceInfo.sdkApiVersion >= 20) {
      try {
        manager.on('audioSessionStateChanged', (event: audio.AudioSessionStateChangedEvent): void => {
          TtsAudioSession.dispatchSessionState(event.stateChangeHint);
        });
      } catch (error) {
        console.warn('[TTS] listen audio session state failed:', error);
      }
    }
  }

  /** 会话被打断时流上不一定再收到 audioInterrupt，把会话级的暂停/停止/恢复也转给播放器。 */
  private static dispatchSessionState(stateHint: audio.AudioSessionStateChangeHint): void {
    console.info(`[TTS] audio session state changed: hint=${stateHint},owners=${TtsAudioSession.owners.size}`);
    let hint: audio.InterruptHint;
    if (stateHint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
      hint = audio.InterruptHint.INTERRUPT_HINT_RESUME;
    } else if (stateHint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) {
      hint = audio.InterruptHint.INTERRUPT_HINT_PAUSE;
    } else if (stateHint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP) {
      hint = audio.InterruptHint.INTERRUPT_HINT_STOP;
    } else {
      return;
    }
    for (const listener of Array.from(TtsAudioSession.hintListeners)) {
      try {
        listener(hint);
      } catch (error) {
        console.warn('[TTS] audio session hint listener failed:', error);
      }
    }
  }

  /**
   * 进程内只注册一次，一直留着：要连续跟踪“当前是否在外接设备上”，才能认出从耳机落回扬声器这一下。
   * 判断方式与 ReaderTtsMediaSession 的朗读暂停一致（朗读的界面暂停在那边做，这里只负责拦住自动续播
   * 并通知有声书）。
   */
  private static watchOutputDevice(): void {
    if (TtsAudioSession.routingManager) return;
    try {
      const manager = audio.getAudioManager().getRoutingManager();
      TtsAudioSession.outputOnExternalDevice = TtsAudioSession.isExternalOutput(
        manager.getPreferredOutputDeviceForRendererInfoSync(TtsAudioSession.outputRendererInfo));
      manager.on('preferOutputDeviceChangeForRendererInfo', TtsAudioSession.outputRendererInfo,
        (devices: audio.AudioDeviceDescriptors): void => {
          TtsAudioSession.handleOutputDeviceChange(devices);
        });
      TtsAudioSession.routingManager = manager;
    } catch (error) {
      console.warn('[TTS] watch output device failed:', error);
    }
  }

  private static handleOutputDeviceChange(devices: audio.AudioDeviceDescriptors): void {
    const wasExternal = TtsAudioSession.outputOnExternalDevice;
    const external = TtsAudioSession.isExternalOutput(devices);
    TtsAudioSession.outputOnExternalDevice = external;
    const builtIn = devices.some((device: audio.AudioDeviceDescriptor): boolean =>
      device.deviceType === audio.DeviceType.SPEAKER || device.deviceType === audio.DeviceType.EARPIECE);
    if (!wasExternal || external || !builtIn) return;
    TtsAudioSession.outputLostAt = Date.now();
    console.info(`[TTS] output fell back to built-in device: owners=${TtsAudioSession.owners.size}`);
    for (const listener of Array.from(TtsAudioSession.outputLostListeners)) {
      try {
        listener();
      } catch (error) {
        console.warn('[TTS] output lost listener failed:', error);
      }
    }
  }

  private static isExternalOutput(devices: audio.AudioDeviceDescriptors): boolean {
    return devices.some((device: audio.AudioDeviceDescriptor): boolean =>
      device.deviceType !== audio.DeviceType.SPEAKER &&
        device.deviceType !== audio.DeviceType.EARPIECE &&
        device.deviceType !== audio.DeviceType.INVALID);
  }

  private static cancelPendingDeactivate(): void {
    if (TtsAudioSession.deactivateTimerId < 0) return;
    clearTimeout(TtsAudioSession.deactivateTimerId);
    TtsAudioSession.deactivateTimerId = -1;
  }

  private static deactivateIfIdle(): void {
    if (TtsAudioSession.owners.size > 0) return;
    const manager = TtsAudioSession.getManager();
    if (!manager) return;
    const deactivate = (): void => {
      if (TtsAudioSession.owners.size > 0) return;
      try {
        if (!manager.isAudioSessionActivated()) return;
      } catch (_) {
      }
      manager.deactivateAudioSession().then(() => {
        console.info('[TTS] audio session deactivated');
      }).catch((error: Error) => {
        console.warn('[TTS] deactivate audio session failed:', error);
      });
    };
    if (TtsAudioSession.activationPromise) {
      TtsAudioSession.activationPromise.finally(deactivate);
      return;
    }
    deactivate();
  }
}
