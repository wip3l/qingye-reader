import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

/**
 * 热评、本章说文字里的表情图（书源给的 { 代号: 图片地址 }）。按地址下载一次存进缓存目录，解成固定边长的
 * PixelMap 留在内存里；绘制时只取已解好的图，没有就先画占位，图好了通过 onReady 让阅读页重画。
 * 动图只取第一帧。排版不看图片是否取到，占位与图片大小相同，所以取图成败都不会改动分页。
 */
export class ReaderEmojiImages {
  private static readonly MAX_BITMAPS: number = 96;
  private static readonly MAX_BYTES: number = 512 * 1024;
  private static readonly FAILED_LIMIT: number = 256;
  private static readonly DIR_NAME: string = 'comment_emoji';
  /** 解码边长取整到这个步长，字号微调时不重复解码。 */
  private static readonly SIZE_STEP: number = 8;

  private static cacheDir: string = '';
  private static readonly bitmaps: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static readonly pending: Set<string> = new Set<string>();
  private static readonly failed: Set<string> = new Set<string>();
  private static listener: (() => void) | null = null;

  /** 阅读页进入时登记缓存目录与重画回调，离开时传空回调解除。 */
  static bind(cacheDir: string, onReady: (() => void) | null): void {
    if (cacheDir) ReaderEmojiImages.cacheDir = cacheDir;
    ReaderEmojiImages.listener = onReady;
  }

  static sizeBucket(sizePx: number): number {
    const step = ReaderEmojiImages.SIZE_STEP;
    return Math.max(step, Math.min(256, Math.ceil(sizePx / step) * step));
  }

  private static key(url: string, bucket: number): string {
    return `${bucket}|${url}`;
  }

  /** 已解好的图；没有时返回 null，并在后台去取（失败过的不再取）。 */
  static get(url: string, sizePx: number): image.PixelMap | null {
    const bucket = ReaderEmojiImages.sizeBucket(sizePx);
    const key = ReaderEmojiImages.key(url, bucket);
    const bitmap = ReaderEmojiImages.bitmaps.get(key);
    if (bitmap) {
      ReaderEmojiImages.bitmaps.delete(key);
      ReaderEmojiImages.bitmaps.set(key, bitmap);
      return bitmap;
    }
    ReaderEmojiImages.prepare(url, sizePx);
    return null;
  }

  /** 排版时就开始取，翻到这一页时多半已经好了。 */
  static prepare(url: string, sizePx: number): void {
    if (!/^https?:\/\//i.test(url)) return;
    const bucket = ReaderEmojiImages.sizeBucket(sizePx);
    const key = ReaderEmojiImages.key(url, bucket);
    if (ReaderEmojiImages.bitmaps.has(key) || ReaderEmojiImages.pending.has(key) ||
      ReaderEmojiImages.failed.has(url)) return;
    ReaderEmojiImages.pending.add(key);
    ReaderEmojiImages.load(url, bucket).then((bitmap: image.PixelMap | null): void => {
      ReaderEmojiImages.pending.delete(key);
      if (!bitmap) {
        ReaderEmojiImages.failed.add(url);
        while (ReaderEmojiImages.failed.size > ReaderEmojiImages.FAILED_LIMIT) {
          const oldest = ReaderEmojiImages.failed.values().next().value as string | undefined;
          if (oldest === undefined) break;
          ReaderEmojiImages.failed.delete(oldest);
        }
        return;
      }
      ReaderEmojiImages.bitmaps.set(key, bitmap);
      while (ReaderEmojiImages.bitmaps.size > ReaderEmojiImages.MAX_BITMAPS) {
        // 不主动 release：被挤掉的图可能正被一张已截好的翻页纹理之外的绘制引用，交给 GC。
        const oldest = ReaderEmojiImages.bitmaps.keys().next().value as string | undefined;
        if (oldest === undefined) break;
        ReaderEmojiImages.bitmaps.delete(oldest);
      }
      const listener = ReaderEmojiImages.listener;
      if (listener) listener();
    });
  }

  private static async load(url: string, bucket: number): Promise<image.PixelMap | null> {
    let bytes = ReaderEmojiImages.readDisk(url);
    if (!bytes) {
      bytes = await ReaderEmojiImages.download(url);
      if (!bytes) return null;
      ReaderEmojiImages.writeDisk(url, bytes);
    }
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(bytes);
      const info = await source.getImageInfo();
      const longest = Math.max(1, info.size.width, info.size.height);
      const scale = bucket / longest;
      return await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
    } catch (_) {
      return null;
    } finally {
      if (source) source.release();
    }
  }

  private static async download(url: string): Promise<ArrayBuffer | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 6000,
        readTimeout: 8000,
        maxLimit: ReaderEmojiImages.MAX_BYTES
      });
      if (response.responseCode !== 200) return null;
      const buffer = response.result as ArrayBuffer;
      return buffer && buffer.byteLength > 0 ? buffer : null;
    } catch (_) {
      return null;
    } finally {
      request.destroy();
    }
  }

  private static diskPath(url: string): string {
    const dir = ReaderEmojiImages.cacheDir;
    if (!dir) return '';
    try {
      const md = cryptoFramework.createMd('MD5');
      md.updateSync({ data: new util.TextEncoder().encodeInto(url) });
      const digest = md.digestSync().data;
      let hex = '';
      for (let i = 0; i < digest.length; i++) hex += digest[i].toString(16).padStart(2, '0');
      return `${dir}/${ReaderEmojiImages.DIR_NAME}/${hex}`;
    } catch (_) {
      return '';
    }
  }

  private static readDisk(url: string): ArrayBuffer | null {
    const path = ReaderEmojiImages.diskPath(url);
    if (!path) return null;
    let file: fs.File | null = null;
    try {
      if (!fs.accessSync(path)) return null;
      const size = fs.statSync(path).size;
      if (size <= 0 || size > ReaderEmojiImages.MAX_BYTES) return null;
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      return buffer;
    } catch (_) {
      return null;
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  private static writeDisk(url: string, bytes: ArrayBuffer): void {
    const path = ReaderEmojiImages.diskPath(url);
    if (!path) return;
    let file: fs.File | null = null;
    try {
      const dir = path.substring(0, path.lastIndexOf('/'));
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
    } catch (_) {
      // 只是缓存，写不进去下次再下载。
    } finally {
      if (file) fs.closeSync(file);
    }
  }
}
