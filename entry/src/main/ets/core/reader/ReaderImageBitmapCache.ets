import { ReaderCacheCoordinator } from '../book/ReaderCacheCoordinator';
import { ReaderImageCache } from '../book/ReaderImageCache';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';

/**
 * 正文插图的解码缓存。翻页时滑入页、当前页和跨章后的新页面都是新建的 Image 节点，用文件地址时每个节点都要在后台
 * 重新解码，解码完成前插图位置是空的，看起来就是插图闪一下。这里把本地图片按显示尺寸解码成 PixelMap 留在内存里，
 * Image 直接拿 PixelMap 绘制，新节点第一帧就有画面。只处理本地文件，网络图和 data: 仍交给 Image 自己加载。
 */
export class ReaderImageBitmapCache {
  private static readonly MAX_ENTRIES: number = 48;
  private static readonly MAX_BYTES: number = 64 * 1024 * 1024;
  /** 同一张图解码失败后不再重试，Image 会按文件地址加载并显示失败提示。 */
  private static readonly FAILED_LIMIT: number = 128;

  private readonly bitmaps: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private readonly bytesByKey: Map<string, number> = new Map<string, number>();
  private readonly pending: Set<string> = new Set<string>();
  private readonly failed: Set<string> = new Set<string>();
  private totalBytes: number = 0;

  /** 已解码好的图片；没有时返回 undefined，不触发解码。 */
  get(source: string, widthPx: number, heightPx: number): image.PixelMap | undefined {
    const key = ReaderImageBitmapCache.cacheKey(source, widthPx, heightPx);
    if (!key) return undefined;
    const bitmap = this.bitmaps.get(key);
    if (bitmap) {
      // 访问过的条目挪到末尾，淘汰时先丢最久没用的。
      this.bitmaps.delete(key);
      this.bitmaps.set(key, bitmap);
    }
    return bitmap;
  }

  /**
   * 安排后台解码。已缓存、正在解码、失败过或不是本地文件时直接返回 false；
   * 否则解码完成后调用 onReady（失败不回调）。
   */
  prepare(source: string, widthPx: number, heightPx: number, onReady: () => void): boolean {
    const key = ReaderImageBitmapCache.cacheKey(source, widthPx, heightPx);
    if (!key || this.bitmaps.has(key) || this.pending.has(key) || this.failed.has(key)) return false;
    const path = ReaderImageBitmapCache.localPath(source);
    if (!path) return false;
    this.pending.add(key);
    ReaderImageBitmapCache.decode(path, widthPx, heightPx).then((bitmap: image.PixelMap | null) => {
      this.pending.delete(key);
      if (!bitmap) {
        this.rememberFailure(key);
        return;
      }
      this.store(key, bitmap);
      onReady();
    });
    return true;
  }

  clear(): void {
    // 不主动 release：被淘汰的 PixelMap 可能仍挂在正在显示的 Image 上，交给 GC 回收。
    this.bitmaps.clear();
    this.bytesByKey.clear();
    this.failed.clear();
    this.totalBytes = 0;
  }

  private store(key: string, bitmap: image.PixelMap): void {
    let bytes = 0;
    try {
      bytes = bitmap.getPixelBytesNumber();
    } catch (_) {
      bytes = 0;
    }
    this.bitmaps.set(key, bitmap);
    this.bytesByKey.set(key, bytes);
    this.totalBytes += bytes;
    while (this.bitmaps.size > 1 && (this.bitmaps.size > ReaderImageBitmapCache.MAX_ENTRIES ||
      this.totalBytes > ReaderImageBitmapCache.MAX_BYTES)) {
      const oldest = this.bitmaps.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.bitmaps.delete(oldest);
      this.totalBytes -= this.bytesByKey.get(oldest) || 0;
      this.bytesByKey.delete(oldest);
    }
  }

  private rememberFailure(key: string): void {
    this.failed.add(key);
    while (this.failed.size > ReaderImageBitmapCache.FAILED_LIMIT) {
      const oldest = this.failed.values().next().value as string | undefined;
      if (oldest === undefined) break;
      this.failed.delete(oldest);
    }
  }

  private static cacheKey(source: string, widthPx: number, heightPx: number): string {
    const width = Math.round(widthPx);
    const height = Math.round(heightPx);
    if (!source || width <= 0 || height <= 0) return '';
    return `${width}x${height}|${source}`;
  }

  private static localPath(source: string): string {
    const value = (source || '').trim();
    if (!value || /^(?:https?:|data:|legado-image-error:)/i.test(value)) return '';
    if (/^file:/i.test(value)) {
      try {
        return new fileUri.FileUri(value).path;
      } catch (_) {
        return '';
      }
    }
    return value;
  }

  /** 按 Contain 的显示尺寸解码，不放大原图。 */
  private static async decode(path: string, widthPx: number, heightPx: number): Promise<image.PixelMap | null> {
    const release = ReaderCacheCoordinator.retainFile(path);
    ReaderImageCache.touch(path);
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const sourceWidth = info.size.width;
      const sourceHeight = info.size.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) return null;
      const scale = Math.min(1, widthPx / sourceWidth, heightPx / sourceHeight);
      const options: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(sourceWidth * scale)),
          height: Math.max(1, Math.round(sourceHeight * scale))
        }
      };
      return await source.createPixelMap(options);
    } catch (error) {
      console.warn(`[ReaderImageBitmap] 解码插图失败 path=${path}:`, error);
      return null;
    } finally {
      release();
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
  }
}
