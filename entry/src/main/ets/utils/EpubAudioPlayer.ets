import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';

/** 书里音频的播放状态。state：'' 没在放、loading 正在准备、playing、paused。 */
export class EpubAudioState {
  /** 音频的标识（文件排版里是它的虚拟地址）。 */
  src: string = '';
  title: string = '';
  state: string = '';
  /** 毫秒。 */
  position: number = 0;
  duration: number = 0;
}

export type EpubAudioListener = (state: EpubAudioState) => void;

/**
 * 书里嵌的音频（多看 <audio class="duokan-audio"> 背景音乐之类）用的播放器：进程里只有一个，换章、翻页都接着放，
 * 离开阅读页时由页面停掉。用 AVPlayer 直接读解压目录里的文件，音频流按音乐（STREAM_USAGE_MUSIC），
 * 被电话、别的应用打断时暂停，不自动恢复。没有接系统媒体控件，所以页面退到后台时也暂停（见调用方）。
 *
 * owner 是发起播放的页面；pause / stop 带上 owner 时只对自己发起的播放生效，换书时新旧页面不会互相停掉。
 */
export class EpubAudioPlayer {
  private static player: media.AVPlayer | null = null;
  private static file: fs.File | null = null;
  private static generation: number = 0;
  private static owner: string = '';
  private static current: EpubAudioState = new EpubAudioState();
  private static listeners: EpubAudioListener[] = [];
  private static lastPositionNotify: number = 0;
  /** 进度推送的最短间隔：网页里只画一条进度线，不用每帧都推。 */
  private static readonly POSITION_NOTIFY_MS: number = 500;

  static state(): EpubAudioState {
    return EpubAudioPlayer.copy();
  }

  static subscribe(listener: EpubAudioListener): () => void {
    EpubAudioPlayer.listeners.push(listener);
    return (): void => {
      EpubAudioPlayer.listeners = EpubAudioPlayer.listeners.filter((item: EpubAudioListener): boolean =>
        item !== listener);
    };
  }

  /** 点了一段音频：正在放的就暂停，暂停中的接着放，别的就换成它从头放。 */
  static toggle(owner: string, src: string, filePath: string, title: string): void {
    const now = EpubAudioPlayer.current;
    if (now.src === src && now.state) {
      EpubAudioPlayer.owner = owner;
      if (now.state === 'paused') EpubAudioPlayer.resume();
      else if (now.state === 'playing') EpubAudioPlayer.pause();
      return;
    }
    EpubAudioPlayer.start(owner, src, filePath, title);
  }

  static pause(owner: string = ''): void {
    if (owner && owner !== EpubAudioPlayer.owner) return;
    const player = EpubAudioPlayer.player;
    if (!player || EpubAudioPlayer.current.state !== 'playing') return;
    player.pause().catch((error: Error): void => console.warn('[EpubAudio] pause failed:', error));
  }

  static resume(): void {
    const player = EpubAudioPlayer.player;
    if (!player || EpubAudioPlayer.current.state !== 'paused') return;
    player.play().catch((error: Error): void => console.warn('[EpubAudio] resume failed:', error));
  }

  static stop(owner: string = ''): void {
    if (owner && owner !== EpubAudioPlayer.owner) return;
    EpubAudioPlayer.generation++;
    EpubAudioPlayer.releaseCurrent();
    EpubAudioPlayer.update('', '', '', 0, 0);
  }

  private static start(owner: string, src: string, filePath: string, title: string): void {
    const generation = ++EpubAudioPlayer.generation;
    EpubAudioPlayer.releaseCurrent();
    EpubAudioPlayer.owner = owner;
    EpubAudioPlayer.update(src, title, 'loading', 0, 0);
    EpubAudioPlayer.open(generation, filePath).catch((error: Error): void => {
      console.warn('[EpubAudio] play failed:', filePath, error);
      if (generation !== EpubAudioPlayer.generation) return;
      EpubAudioPlayer.releaseCurrent();
      EpubAudioPlayer.update('', '', '', 0, 0);
    });
  }

  private static async open(generation: number, filePath: string): Promise<void> {
    const length = fs.statSync(filePath).size;
    const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (error) {
      EpubAudioPlayer.closeFile(file);
      throw error as Error;
    }
    if (generation !== EpubAudioPlayer.generation) {
      EpubAudioPlayer.closeFile(file);
      player.release().catch((): void => {});
      return;
    }
    EpubAudioPlayer.player = player;
    EpubAudioPlayer.file = file;
    player.on('stateChange', (state: string): void => EpubAudioPlayer.onStateChange(generation, player, state));
    player.on('timeUpdate', (time: number): void => {
      if (generation !== EpubAudioPlayer.generation) return;
      const now = EpubAudioPlayer.current;
      const at = Date.now();
      if (at - EpubAudioPlayer.lastPositionNotify < EpubAudioPlayer.POSITION_NOTIFY_MS) {
        now.position = time;
        return;
      }
      EpubAudioPlayer.lastPositionNotify = at;
      EpubAudioPlayer.update(now.src, now.title, now.state, time, now.duration);
    });
    player.on('durationUpdate', (duration: number): void => {
      if (generation !== EpubAudioPlayer.generation || duration <= 0) return;
      const now = EpubAudioPlayer.current;
      EpubAudioPlayer.update(now.src, now.title, now.state, now.position, duration);
    });
    player.on('error', (error: Error): void => {
      if (generation !== EpubAudioPlayer.generation) return;
      console.warn('[EpubAudio] player error:', error);
      EpubAudioPlayer.stop();
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (generation !== EpubAudioPlayer.generation) return;
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        EpubAudioPlayer.stop();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        // 系统强制暂停时播放器自己已经停了声音，这里把状态也改成暂停，等用户再点。
        if (EpubAudioPlayer.current.state === 'playing') {
          player.pause().catch((): void => {
            const now = EpubAudioPlayer.current;
            EpubAudioPlayer.update(now.src, now.title, 'paused', now.position, now.duration);
          });
        }
      }
    });
    // 给出完整的文件描述（偏移与长度），播放器才知道总长、能拖进度。
    player.fdSrc = { fd: file.fd, offset: 0, length: length };
  }

  private static onStateChange(generation: number, player: media.AVPlayer, state: string): void {
    if (generation !== EpubAudioPlayer.generation) return;
    const now = EpubAudioPlayer.current;
    if (state === 'initialized') {
      player.audioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_MUSIC,
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      player.prepare().catch((error: Error): void => {
        console.warn('[EpubAudio] prepare failed:', error);
        if (generation === EpubAudioPlayer.generation) EpubAudioPlayer.stop();
      });
    } else if (state === 'prepared') {
      EpubAudioPlayer.update(now.src, now.title, 'loading', 0, player.duration > 0 ? player.duration : 0);
      player.play().catch((error: Error): void => {
        console.warn('[EpubAudio] start failed:', error);
        if (generation === EpubAudioPlayer.generation) EpubAudioPlayer.stop();
      });
    } else if (state === 'playing') {
      EpubAudioPlayer.update(now.src, now.title, 'playing', player.currentTime, now.duration || player.duration);
    } else if (state === 'paused') {
      EpubAudioPlayer.update(now.src, now.title, 'paused', player.currentTime, now.duration);
    } else if (state === 'completed' || state === 'stopped' || state === 'error') {
      EpubAudioPlayer.stop();
    }
  }

  private static releaseCurrent(): void {
    const player = EpubAudioPlayer.player;
    const file = EpubAudioPlayer.file;
    EpubAudioPlayer.player = null;
    EpubAudioPlayer.file = null;
    if (player) {
      try {
        player.off('stateChange');
        player.off('timeUpdate');
        player.off('durationUpdate');
        player.off('error');
        player.off('audioInterrupt');
      } catch (_) {
      }
      player.release().catch((error: Error): void => console.warn('[EpubAudio] release failed:', error))
        .finally((): void => EpubAudioPlayer.closeFile(file));
    } else {
      EpubAudioPlayer.closeFile(file);
    }
  }

  private static closeFile(file: fs.File | null): void {
    if (!file) return;
    try {
      fs.closeSync(file);
    } catch (_) {
    }
  }

  private static update(src: string, title: string, state: string, position: number, duration: number): void {
    const next = new EpubAudioState();
    next.src = src;
    next.title = title;
    next.state = state;
    next.position = Math.max(0, position || 0);
    next.duration = Math.max(0, duration || 0);
    EpubAudioPlayer.current = next;
    if (!state) EpubAudioPlayer.owner = '';
    for (const listener of EpubAudioPlayer.listeners.slice()) {
      try {
        listener(EpubAudioPlayer.copy());
      } catch (error) {
        console.warn('[EpubAudio] listener failed:', error);
      }
    }
  }

  private static copy(): EpubAudioState {
    const now = EpubAudioPlayer.current;
    const state = new EpubAudioState();
    state.src = now.src;
    state.title = now.title;
    state.state = now.state;
    state.position = now.position;
    state.duration = now.duration;
    return state;
  }
}
