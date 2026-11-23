import fs from '@ohos.file.fs';
import { fileUri } from '../../platform/FileUri';
import image from '@ohos.multimedia.image';
import { ComicTrimRect, ReaderComicTrimDetect } from './ReaderComicTrimDetect';

/**
 * 每张漫画图的白边检测结果，按图片来源缓存。只处理本地文件（网络直链和内嵌数据不检测）：
 * 按 ReaderComicTrimDetect.sampleSize 缩小解码再扫描，一张图几毫秒。失败或没有白边记为 null。
 */
export class ReaderComicTrim {
  private static readonly LIMIT: number = 2048;
  private static readonly results: Map<string, ComicTrimRect | null> = new Map<string, ComicTrimRect | null>();
  private static readonly running: Map<string, Promise<ComicTrimRect | null>> =
    new Map<string, Promise<ComicTrimRect | null>>();

  /** 能检测的来源：本地路径或 file: 地址。 */
  static supported(source: string): boolean {
    return !!source && !/^(?:https?:|data:)/i.test(source);
  }

  /** 已有结果时返回它（null 表示不裁）；还没检测过返回 undefined。 */
  static cached(source: string): ComicTrimRect | null | undefined {
    if (!ReaderComicTrim.supported(source)) return null;
    return ReaderComicTrim.results.get(source);
  }

  static request(source: string): Promise<ComicTrimRect | null> {
    const cached = ReaderComicTrim.cached(source);
    if (cached !== undefined) return Promise.resolve(cached);
    const running = ReaderComicTrim.running.get(source);
    if (running) return running;
    const task = ReaderComicTrim.detect(source).then((rect: ComicTrimRect | null): ComicTrimRect | null => {
      ReaderComicTrim.running.delete(source);
      ReaderComicTrim.remember(source, rect);
      return rect;
    });
    ReaderComicTrim.running.set(source, task);
    return task;
  }

  private static remember(source: string, rect: ComicTrimRect | null): void {
    ReaderComicTrim.results.delete(source);
    ReaderComicTrim.results.set(source, rect);
    while (ReaderComicTrim.results.size > ReaderComicTrim.LIMIT) {
      const oldest = ReaderComicTrim.results.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      ReaderComicTrim.results.delete(oldest);
    }
  }

  private static async detect(source: string): Promise<ComicTrimRect | null> {
    let path = source;
    if (/^file:/i.test(path)) {
      try {
        path = new fileUri.FileUri(path).path;
      } catch (_) {
        return null;
      }
    }
    let file: fs.File | null = null;
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      const size = ReaderComicTrimDetect.sampleSize(info.size.width, info.size.height);
      if (size[0] <= 0 || size[1] <= 0) return null;
      pixelMap = await imageSource.createPixelMap({
        desiredSize: { width: size[0], height: size[1] },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      // 解码器可能不完全按目标尺寸出图，以实际尺寸为准。
      const decoded = await pixelMap.getImageInfo();
      const width = decoded.size.width;
      const height = decoded.size.height;
      if (width <= 0 || height <= 0) return null;
      const area: image.PositionArea = {
        pixels: new ArrayBuffer(width * height * 4),
        offset: 0,
        stride: width * 4,
        region: { size: { width: width, height: height }, x: 0, y: 0 }
      };
      await pixelMap.readPixels(area);
      return ReaderComicTrimDetect.detect(new Uint8Array(area.pixels), width, height);
    } catch (error) {
      console.warn(`[ReaderComicTrim] 白边检测失败 path=${path}:`, error);
      return null;
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (_) {
        }
      }
      if (imageSource) {
        try {
          await imageSource.release();
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
