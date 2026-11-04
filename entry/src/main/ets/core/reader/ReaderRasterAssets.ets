import image from '@ohos.multimedia.image';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';

/**
 * Theme artwork decoded to PixelMaps for the self-drawn page raster: regex bubble caps and the built-in paper
 * decorations. ArkUI Image decodes the same resources for the live page; here they are decoded once per size and
 * kept for the process, so a page raster never waits on a decode.
 */
export class ReaderRasterAssets {
  private static readonly MAX_ENTRIES: number = 32;
  private static readonly cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

  static regexBubbleCap(host: Context, styleId: string, sizePx: number): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.regexBubbleCap(styleId), sizePx, sizePx);
  }

  static backgroundDecoration(host: Context, assetId: string, sizePx: number): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.readerBackgroundDecoration(assetId), sizePx, sizePx);
  }

  static backgroundTrailingDecoration(host: Context, assetId: string, sizePx: number): image.PixelMap | null {
    return ReaderRasterAssets.media(host, ThemeAssetRegistry.readerBackgroundTrailingDecoration(assetId),
      sizePx, sizePx);
  }

  /** Decodes a media resource at the given pixel size; null for string sources or on any failure. */
  static media(host: Context, resource: ResourceStr, widthPx: number, heightPx: number): image.PixelMap | null {
    if (typeof resource === 'string' || !resource || !host) return null;
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
        if (ReaderRasterAssets.cache.size >= ReaderRasterAssets.MAX_ENTRIES) {
          const oldest = ReaderRasterAssets.cache.keys().next().value as string | undefined;
          if (oldest !== undefined) {
            ReaderRasterAssets.cache.get(oldest)?.release().catch((): void => {});
            ReaderRasterAssets.cache.delete(oldest);
          }
        }
        ReaderRasterAssets.cache.set(key, bitmap);
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
