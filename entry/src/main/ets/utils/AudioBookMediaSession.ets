import { avSession } from '@kit.AVSessionKit';
import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BookCoverResolver } from './BookCoverResolver';

/** 封面跟随共享会话保存；取图不阻塞播放，换书或销毁后丢弃迟到的结果。 */
export class AudioBookMediaCover {
  private key: string = '';
  private serial: number = 0;
  private loading: boolean = false;
  private retryAfter: number = 0;
  private pixelMap: image.PixelMap | null = null;

  getImage(context: Context, bookUrl: string, cover: ResourceStr, onReady: () => void): image.PixelMap | null {
    const key = JSON.stringify([bookUrl, cover]);
    if (key !== this.key) {
      this.clear();
      this.key = key;
    }
    if (cover && !this.pixelMap && !this.loading && Date.now() >= this.retryAfter) {
      this.loading = true;
      this.load(context, cover, this.serial, onReady).catch((error: Error) => {
        console.warn('刷新听书媒体封面失败:', error);
      });
    }
    return this.pixelMap;
  }

  clear(): void {
    this.serial++;
    this.key = '';
    this.loading = false;
    this.retryAfter = 0;
    if (this.pixelMap) this.releasePixelMap(this.pixelMap);
    this.pixelMap = null;
  }

  private async load(context: Context, cover: ResourceStr, serial: number, onReady: () => void): Promise<void> {
    let pixelMap: image.PixelMap | null = null;
    try {
      // 复用书架缓存及其请求头、解密逻辑，不能让系统另行请求原始网络 URL。
      const path = await BookCoverResolver.prepareFile(context, cover);
      if (serial !== this.serial) return;
      if (path) pixelMap = await this.decode(path);
    } catch (error) {
      console.warn('准备听书媒体封面失败:', error);
    }
    if (serial !== this.serial) {
      if (pixelMap) this.releasePixelMap(pixelMap);
      return;
    }
    this.loading = false;
    this.pixelMap = pixelMap;
    // 后续播放进度或保活更新可以重试，失败期间避免反复下载。
    this.retryAfter = pixelMap ? 0 : Date.now() + 10000;
    if (pixelMap) onReady();
  }

  private async decode(path: string): Promise<image.PixelMap> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({ desiredSize: { width: 512, height: 512 } });
    } finally {
      try {
        if (source) await source.release();
      } catch (error) {
        console.warn('释放听书封面图片源失败:', error);
      }
      try {
        await fileIo.close(file);
      } catch (error) {
        console.warn('关闭听书封面文件失败:', error);
      }
    }
  }

  private releasePixelMap(pixelMap: image.PixelMap): void {
    pixelMap.release().catch((error: Error) => {
      console.warn('释放听书媒体封面失败:', error);
    });
  }
}

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
  refreshMetadata: () => Promise<void>;
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
  static mediaCover: AudioBookMediaCover = new AudioBookMediaCover();
  /** 会话上的回调只注册一次，转发到这里；页面接管播放器时替换它。 */
  static commands: AudioBookMediaCommands | null = null;
  static sessionStarting: boolean = false;
  static backgroundRunning: boolean = false;
  static backgroundStarting: boolean = false;
  static backgroundDesired: boolean = false;
  static heartbeatId: number = -1;
}
