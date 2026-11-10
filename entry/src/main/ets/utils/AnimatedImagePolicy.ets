import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import preferences from '@ohos.data.preferences';

class AnimatedImageEntry {
  /** 生成探测结果时文件的大小与修改时间，文件被替换后重新探测。 */
  stamp: string = '';
  animated: boolean = false;
  /** 第一帧静图的 file:// 地址；不是动图或还没生成时为空。 */
  still: string = '';
}

/**
 * 书架封面、主题封面和首页背景图里的 GIF / 动态 WebP。
 *
 * Image 组件拿到本地动图路径就会播放，组件不可见时系统自己停（见 SDK image.d.ts），这里只管两件事：
 * “播放动图”开关关闭时、或动图超过 MAX_PLAY_BYTES 时，把地址换成缓存目录里的第一帧静图。
 * 静图在后台生成，生成好之前先显示原图；生成后递增 AppStorage `animatedImageRevision`，读它的界面重新取地址。
 * 网络地址不处理：书架会把封面下载到本地后再换成本地路径，那时再判断。
 */
export class AnimatedImagePolicy {
  static readonly KEY_ENABLED: string = 'animatedImagesEnabled';
  static readonly KEY_REVISION: string = 'animatedImageRevision';
  /** 超过这个大小的动图只显示第一帧，上传入口也按它拒收：一屏十几张大动图同时解码太费内存和电。 */
  static readonly MAX_PLAY_BYTES: number = 8 * 1024 * 1024;
  static readonly MAX_PLAY_LABEL: string = '8 MB';
  private static readonly STORE_NAME: string = 'animated_image_settings';
  private static readonly STILL_DIR: string = 'animated_stills';
  /** 静图最长边，够书架封面和 1080 宽的首页背景用。 */
  private static readonly STILL_MAX_EDGE: number = 1440;

  private static entries: Map<string, AnimatedImageEntry> = new Map();
  private static probing: Set<string> = new Set();
  private static revisionTimer: number = -1;
  private static settingsRevision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static enabled(): boolean {
    return AppStorage.get<boolean>(AnimatedImagePolicy.KEY_ENABLED) !== false;
  }

  static async load(context: Context): Promise<void> {
    const revision = AnimatedImagePolicy.settingsRevision;
    const store = await preferences.getPreferences(context, AnimatedImagePolicy.STORE_NAME);
    const value = await store.get(AnimatedImagePolicy.KEY_ENABLED, true);
    if (revision !== AnimatedImagePolicy.settingsRevision) return;
    if ((value !== false) !== AnimatedImagePolicy.enabled()) {
      AppStorage.setOrCreate(AnimatedImagePolicy.KEY_ENABLED, value !== false);
      AnimatedImagePolicy.bumpRevisionNow();
    }
  }

  static save(context: Context, enabled: boolean): Promise<void> {
    ++AnimatedImagePolicy.settingsRevision;
    AppStorage.setOrCreate(AnimatedImagePolicy.KEY_ENABLED, enabled);
    AnimatedImagePolicy.bumpRevisionNow();
    const write = AnimatedImagePolicy.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, AnimatedImagePolicy.STORE_NAME);
      await store.put(AnimatedImagePolicy.KEY_ENABLED, enabled);
      await store.flush();
    });
    AnimatedImagePolicy.writes = write.catch(() => {});
    return write;
  }

  /** 给 Image 用的地址：需要静止时换成第一帧静图，其余原样返回。资源引用和网络地址不处理。 */
  static display(context: Context, src: string): string {
    const path = AnimatedImagePolicy.localPath(src);
    if (!path) return src;
    let stat: fs.Stat;
    try {
      stat = fs.statSync(path);
    } catch (_) {
      return src;
    }
    const enabled = AnimatedImagePolicy.enabled();
    // 开着播放时，小文件不管是不是动图都原样显示，不用探测。
    if (enabled && stat.size <= AnimatedImagePolicy.MAX_PLAY_BYTES) return src;
    const stamp = `${stat.size}:${stat.mtime}`;
    const entry = AnimatedImagePolicy.entries.get(path);
    if (entry && entry.stamp === stamp) {
      return entry.animated && entry.still ? entry.still : src;
    }
    if (!AnimatedImagePolicy.mayBeAnimated(path)) {
      const known = new AnimatedImageEntry();
      known.stamp = stamp;
      AnimatedImagePolicy.entries.set(path, known);
      return src;
    }
    AnimatedImagePolicy.probe(context, path, stamp);
    return src;
  }

  /**
   * 上传前检查：是动图且超过大小上限时返回提示文字，否则返回空串。uri 可以是图库或文件选择器给的地址。
   */
  static async oversizeAnimatedMessage(uri: string): Promise<string> {
    const info = await AnimatedImagePolicy.inspect(uri);
    if (info.animated && info.size > AnimatedImagePolicy.MAX_PLAY_BYTES) {
      return `动图不能超过 ${AnimatedImagePolicy.MAX_PLAY_LABEL}`;
    }
    return '';
  }

  /** 是不是多帧图片（GIF / 动态 WebP）。读不出来时按不是处理。 */
  static async isAnimated(uri: string): Promise<boolean> {
    return (await AnimatedImagePolicy.inspect(uri)).animated;
  }

  private static async inspect(uri: string): Promise<AnimatedImageInfo> {
    const info = new AnimatedImageInfo();
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      info.size = fs.statSync(file.fd).size;
      const head = new ArrayBuffer(32);
      const read = fs.readSync(file.fd, head, { offset: 0, length: 32 });
      if (!AnimatedImagePolicy.headMayBeAnimated(new Uint8Array(head, 0, read))) return info;
      source = image.createImageSource(file.fd);
      info.animated = (await source.getFrameCount()) > 1;
    } catch (_) {
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (_) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
    return info;
  }

  private static localPath(src: string): string {
    if (!src) return '';
    if (src.startsWith('/')) return src;
    if (!src.startsWith('file://')) return '';
    try {
      return new fileUri.FileUri(src).path;
    } catch (_) {
      return '';
    }
  }

  /** 只读文件头：GIF 都可能是动图，WebP 看 VP8X 块的动画标志，其他格式都是静图。 */
  private static mayBeAnimated(path: string): boolean {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const head = new ArrayBuffer(32);
      const read = fs.readSync(file.fd, head, { offset: 0, length: 32 });
      return AnimatedImagePolicy.headMayBeAnimated(new Uint8Array(head, 0, read));
    } catch (_) {
      return false;
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private static headMayBeAnimated(head: Uint8Array): boolean {
    if (head.length >= 4 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return true;
    const webp = head.length >= 21 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
      head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50;
    if (!webp) return false;
    // RIFF....WEBPVP8X，第 20 字节是标志位，0x02 = 带动画。
    const vp8x = head[12] === 0x56 && head[13] === 0x50 && head[14] === 0x38 && head[15] === 0x58;
    return vp8x && (head[20] & 0x02) !== 0;
  }

  private static probe(context: Context, path: string, stamp: string): void {
    if (AnimatedImagePolicy.probing.has(path)) return;
    AnimatedImagePolicy.probing.add(path);
    AnimatedImagePolicy.buildStill(context, path, stamp).then((entry: AnimatedImageEntry): void => {
      AnimatedImagePolicy.entries.set(path, entry);
      if (entry.animated && entry.still) AnimatedImagePolicy.bumpRevision();
    }).catch((error: Error): void => {
      console.warn('生成动图静帧失败:', error.message);
      // 失败了也记下来，免得每次刷新都重试；文件变了 stamp 不同会再来。
      const failed = new AnimatedImageEntry();
      failed.stamp = stamp;
      AnimatedImagePolicy.entries.set(path, failed);
    }).finally((): void => {
      AnimatedImagePolicy.probing.delete(path);
    });
  }

  private static async buildStill(context: Context, path: string, stamp: string): Promise<AnimatedImageEntry> {
    const entry = new AnimatedImageEntry();
    entry.stamp = stamp;
    const dir = `${context.cacheDir}/${AnimatedImagePolicy.STILL_DIR}`;
    const target = `${dir}/${AnimatedImagePolicy.hashName(`${path}|${stamp}`)}.png`;
    if (AnimatedImagePolicy.exists(target)) {
      entry.animated = true;
      entry.still = fileUri.getUriFromPath(target);
      return entry;
    }
    const source = image.createImageSource(path);
    let pixelMap: image.PixelMap | null = null;
    try {
      if ((await source.getFrameCount()) <= 1) return entry;
      entry.animated = true;
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height, 1);
      const scale = Math.min(1, AnimatedImagePolicy.STILL_MAX_EDGE / longest);
      const options: image.DecodingOptions = { index: 0 };
      if (scale < 1) {
        options.desiredSize = {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        };
      }
      pixelMap = await source.createPixelMap(options);
      if (!AnimatedImagePolicy.exists(dir)) fs.mkdirSync(dir, true);
      const temp = `${target}.tmp`;
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const packer = image.createImagePacker();
      try {
        await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      } finally {
        fs.closeSync(file);
        await packer.release();
      }
      fs.renameSync(temp, target);
      entry.still = fileUri.getUriFromPath(target);
      return entry;
    } finally {
      if (pixelMap) await pixelMap.release();
      await source.release();
    }
  }

  private static hashName(text: string): string {
    let h1 = 0x811c9dc5;
    let h2 = 0x01000193;
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 16777619) >>> 0;
      h2 = Math.imul(h2 + c, 2246822519) >>> 0;
    }
    return `${h1.toString(16).padStart(8, '0')}${h2.toString(16).padStart(8, '0')}`;
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  /** 一屏动图陆续生成静图时合并成一次刷新。 */
  private static bumpRevision(): void {
    if (AnimatedImagePolicy.revisionTimer !== -1) return;
    AnimatedImagePolicy.revisionTimer = setTimeout(() => {
      AnimatedImagePolicy.revisionTimer = -1;
      AnimatedImagePolicy.bumpRevisionNow();
    }, 200);
  }

  private static bumpRevisionNow(): void {
    AppStorage.setOrCreate<number>(AnimatedImagePolicy.KEY_REVISION,
      (AppStorage.get<number>(AnimatedImagePolicy.KEY_REVISION) || 0) + 1);
  }
}

class AnimatedImageInfo {
  size: number = 0;
  animated: boolean = false;
}
