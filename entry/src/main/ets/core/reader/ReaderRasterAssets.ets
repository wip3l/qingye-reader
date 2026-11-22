import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { AnimatedImagePolicy } from '../../utils/AnimatedImagePolicy';

/**
 * Theme artwork decoded to PixelMaps for the self-drawn page raster: regex bubble caps and the built-in paper
 * decorations. ArkUI Image decodes the same resources for the live page; here they are decoded once per size and
 * kept for the process, so a page raster never waits on a decode.
 */
export class ReaderRasterAssets {
  private static readonly MAX_ENTRIES: number = 32;
  private static readonly cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  /** 内置主题随应用安装的图片写成 media:<资源名>，和主题包的本机文件走同一套解码与缓存。 */
  static readonly MEDIA_PREFIX: string = 'media:';
  private static appContext: Context | null = null;
  private static readonly aspects: Map<string, number> = new Map<string, number>();
  private static readonly sizes: Map<string, image.Size | null> = new Map<string, image.Size | null>();
  /** 阅读背景“完整显示”模糊垫底用的小图，单独缓存：界面上的 Image 正在显示它，不能被上面的缓存挤掉释放。 */
  private static readonly backdrops: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static readonly MAX_BACKDROPS: number = 4;
  /** 章首饰图是不是本机动图（GIF / 动态 WebP），按地址只读一次文件头。 */
  private static readonly animatedArtwork: Map<string, boolean> = new Map<string, boolean>();
  /**
   * 动图饰图的第一帧，给阅读页叠加的 Image 当 alt：新页的 Image 解码动图前先显示它，不闪空。单独缓存，
   * 界面正拿着用，不能被上面的缓存挤掉释放。
   */
  private static readonly animatedStills: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static readonly MAX_ANIMATED_STILLS: number = 8;
  /** 模糊垫底小图的宽（px），再大模糊后也看不出区别。 */
  static readonly BACKDROP_WIDTH: number = 96;

  /** 应用启动时登记一次，之后按资源名取内置图片不需要调用方再传上下文。 */
  static bindContext(context: Context): void {
    ReaderRasterAssets.appContext = context;
  }

  private static mediaBytes(source: string): ArrayBuffer | null {
    const context = ReaderRasterAssets.appContext;
    if (!context) return null;
    const bytes = context.resourceManager.getMediaByNameSync(source.substring(ReaderRasterAssets.MEDIA_PREFIX.length));
    return bytes.buffer as ArrayBuffer;
  }

  /** 图片的宽 / 高（本机文件或 media:<资源名>）；读不出来时返回 0。同一张图只读一次。 */
  static imageAspect(source: string): number {
    if (!source) return 0;
    const cached = ReaderRasterAssets.aspects.get(source);
    if (cached !== undefined) return cached;
    let aspect = 0;
    if (source.startsWith(ReaderRasterAssets.MEDIA_PREFIX)) {
      try {
        const bytes = ReaderRasterAssets.mediaBytes(source);
        if (bytes) {
          const decoder = image.createImageSource(bytes);
          try {
            const size = decoder.getImageInfoSync().size;
            aspect = size.width > 0 && size.height > 0 ? size.width / size.height : 0;
          } finally {
            decoder.release();
          }
        }
      } catch (error) {
        console.warn('[ReaderRaster] read media size failed:', error);
      }
      // 上下文还没登记时先不记，等登记后再读。
      if (aspect <= 0 && !ReaderRasterAssets.appContext) return 0;
    } else {
      const size = ReaderRasterAssets.fileImageSize(source);
      aspect = size ? size.width / size.height : 0;
    }
    ReaderRasterAssets.aspects.set(source, aspect);
    return aspect;
  }

  static regexBubbleCap(host: Context, styleId: string, sizePx: number, dark: boolean = false): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.regexBubbleCap(styleId, dark), sizePx, sizePx);
  }

  static backgroundDecoration(host: Context, assetId: string, sizePx: number): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.readerBackgroundDecoration(assetId), sizePx, sizePx);
  }

  static backgroundTrailingDecoration(host: Context, assetId: string, sizePx: number): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.readerBackgroundTrailingDecoration(assetId),
      sizePx, sizePx);
  }

  /** 本机图片文件的像素尺寸，同一张图只读一次；读不出来时为 null。 */
  static imageSize(uri: string): image.Size | null {
    if (!uri || uri.startsWith(ReaderRasterAssets.MEDIA_PREFIX)) return null;
    if (ReaderRasterAssets.sizes.has(uri)) return ReaderRasterAssets.sizes.get(uri) ?? null;
    const size = ReaderRasterAssets.fileImageSize(uri);
    ReaderRasterAssets.sizes.set(uri, size);
    return size;
  }

  /**
   * 背景图第一帧缩成 BACKDROP_WIDTH 宽的小图，给“完整显示”的模糊垫底用。动图也只取第一帧，
   * 免得同一张动图解两份。最近用过的排到最后，超出上限时释放最久没用的。
   */
  static backdropThumb(uri: string): image.PixelMap | null {
    if (!uri) return null;
    const cached = ReaderRasterAssets.backdrops.get(uri);
    if (cached) {
      ReaderRasterAssets.backdrops.delete(uri);
      ReaderRasterAssets.backdrops.set(uri, cached);
      return cached;
    }
    const size = ReaderRasterAssets.imageSize(uri);
    if (!size) return null;
    const width = Math.min(ReaderRasterAssets.BACKDROP_WIDTH, size.width);
    const height = Math.max(1, Math.round(width * size.height / size.width));
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      try {
        const bitmap = source.createPixelMapSync({ desiredSize: { width: width, height: height } });
        if (ReaderRasterAssets.backdrops.size >= ReaderRasterAssets.MAX_BACKDROPS) {
          const oldest = ReaderRasterAssets.backdrops.keys().next().value as string | undefined;
          if (oldest !== undefined) {
            ReaderRasterAssets.backdrops.get(oldest)?.release().catch((): void => {});
            ReaderRasterAssets.backdrops.delete(oldest);
          }
        }
        ReaderRasterAssets.backdrops.set(uri, bitmap);
        return bitmap;
      } finally {
        source.release();
      }
    } catch (error) {
      console.warn('[ReaderRaster] decode backdrop failed:', error);
      return null;
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  /** Intrinsic pixel size of an image file (sandbox path or file:// URI); null when it cannot be read. */
  static fileImageSize(uri: string): image.Size | null {
    if (!uri) return null;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      try {
        const info = source.getImageInfoSync();
        return info.size.width > 0 && info.size.height > 0 ? info.size : null;
      } finally {
        source.release();
      }
    } catch (error) {
      console.warn('[ReaderRaster] read image size failed:', error);
      return null;
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  /** Decodes an image file (sandbox path or file:// URI) stretched to the given pixel size, cached per size. */
  static fileImage(uri: string, widthPx: number, heightPx: number): image.PixelMap | null {
    if (!uri) return null;
    const width = Math.max(1, Math.round(widthPx));
    const height = Math.max(1, Math.round(heightPx));
    const key = `${uri}_${width}x${height}`;
    const cached = ReaderRasterAssets.cache.get(key);
    if (cached) return cached;
    const bitmap = ReaderRasterAssets.decodeFile(uri, width, height);
    if (bitmap) ReaderRasterAssets.remember(key, bitmap);
    return bitmap;
  }

  /**
   * 章首饰图是本机动图时返回 true：常驻页不把它画进画布，由阅读页叠一个 Image 播放；翻页纹理和其他自绘层
   * 照旧画第一帧。只看文件，不看“播放动图”开关——开关关着时叠加层显示静图，画布这边不用跟着重画。
   */
  static isAnimatedArtwork(uri: string): boolean {
    if (!uri || uri.startsWith(ReaderRasterAssets.MEDIA_PREFIX)) return false;
    const known = ReaderRasterAssets.animatedArtwork.get(uri);
    if (known !== undefined) return known;
    const animated = AnimatedImagePolicy.mayBeAnimatedFile(uri);
    ReaderRasterAssets.animatedArtwork.set(uri, animated);
    return animated;
  }

  /** 动图饰图按显示尺寸解码的第一帧（见 animatedStills）；解不出来返回 null。 */
  static animatedStill(uri: string, widthPx: number, heightPx: number): image.PixelMap | null {
    if (!uri) return null;
    const width = Math.max(1, Math.round(widthPx));
    const height = Math.max(1, Math.round(heightPx));
    const key = `${uri}_${width}x${height}`;
    const cached = ReaderRasterAssets.animatedStills.get(key);
    if (cached) return cached;
    const bitmap = ReaderRasterAssets.decodeFile(uri, width, height);
    if (!bitmap) return null;
    if (ReaderRasterAssets.animatedStills.size >= ReaderRasterAssets.MAX_ANIMATED_STILLS) {
      const oldest = ReaderRasterAssets.animatedStills.keys().next().value as string | undefined;
      if (oldest !== undefined) {
        ReaderRasterAssets.animatedStills.get(oldest)?.release().catch((): void => {});
        ReaderRasterAssets.animatedStills.delete(oldest);
      }
    }
    ReaderRasterAssets.animatedStills.set(key, bitmap);
    return bitmap;
  }

  private static decodeFile(uri: string, width: number, height: number): image.PixelMap | null {
    if (uri.startsWith(ReaderRasterAssets.MEDIA_PREFIX)) {
      try {
        const bytes = ReaderRasterAssets.mediaBytes(uri);
        if (!bytes) return null;
        const source = image.createImageSource(bytes);
        try {
          return source.createPixelMapSync({ desiredSize: { width: width, height: height } });
        } finally {
          source.release();
        }
      } catch (error) {
        console.warn('[ReaderRaster] decode media failed:', error);
        return null;
      }
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      try {
        return source.createPixelMapSync({ desiredSize: { width: width, height: height } });
      } finally {
        source.release();
      }
    } catch (error) {
      console.warn('[ReaderRaster] decode image file failed:', error);
      return null;
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  private static remember(key: string, bitmap: image.PixelMap): void {
    if (ReaderRasterAssets.cache.size >= ReaderRasterAssets.MAX_ENTRIES) {
      const oldest = ReaderRasterAssets.cache.keys().next().value as string | undefined;
      if (oldest !== undefined) {
        ReaderRasterAssets.cache.get(oldest)?.release().catch((): void => {});
        ReaderRasterAssets.cache.delete(oldest);
      }
    }
    ReaderRasterAssets.cache.set(key, bitmap);
  }

  /** Decodes a media resource at the given pixel size; string sources are theme-pack files, decoded from disk. */
  static media(host: Context, resource: ResourceStr, widthPx: number, heightPx: number): image.PixelMap | null {
    if (typeof resource === 'string') return resource ? ReaderRasterAssets.fileImage(resource, widthPx, heightPx) : null;
    if (!resource || !host) return null;
    const width = Math.max(1, Math.round(widthPx));
    const height = Math.max(1, Math.round(heightPx));
    const key = `${resource.id}_${width}x${height}`;
    const cached = ReaderRasterAssets.cache.get(key);
    if (cached) return cached;
    try {
      const bytes = host.resourceManager.getMediaContentSync(resource.id);
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      try {
        const bitmap = source.createPixelMapSync({ desiredSize: { width: width, height: height } });
        ReaderRasterAssets.remember(key, bitmap);
        return bitmap;
      } finally {
        source.release();
      }
    } catch (error) {
      console.warn(`[ReaderRaster] decode resource ${resource.id} failed:`, error);
      return null;
    }
  }
}
