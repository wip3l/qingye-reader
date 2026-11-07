import image from '@ohos.multimedia.image';
import { ReaderNightImage } from './ReaderNightImage';

/**
 * 应用排版夜间插图的处理结果缓存：把已解码的插图按“夜间图片”设置调暗或反色，生成一张新的 PixelMap。
 * 实时页面的 Image 和自绘翻页纹理用的是同一张，翻页时插图不会闪回原色。
 * 不用 ArkUI ColorFilter：它的颜色矩阵偏移量取值范围没有文档保证，反色要靠偏移量，自己算像素最稳。
 * 新图用 DMA 分配：交给翻页 Canvas 反复绘制的 PixelMap 用堆内存会让 RS 显存泄漏（见 ReaderPageRasterizer）。
 */
export class ReaderNightImageCache {
  private static readonly MAX_ENTRIES: number = 32;
  /** 自动模式的取样：每隔这么多个像素取一个。 */
  private static readonly SAMPLE_STRIDE: number = 7;

  private readonly results: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private readonly pending: Set<string> = new Set<string>();
  private readonly failed: Set<string> = new Set<string>();

  /** 处理好的插图；还没有时返回 undefined，处理失败返回 null（调用方就用原图）。 */
  get(baseKey: string, mode: string): image.PixelMap | null | undefined {
    const key = ReaderNightImageCache.key(baseKey, mode);
    if (this.failed.has(key)) return null;
    const result = this.results.get(key);
    if (result) {
      this.results.delete(key);
      this.results.set(key, result);
    }
    return result;
  }

  /** 安排处理；已有、在处理或失败过时返回 false。处理完（成功或失败）调用 onReady。 */
  prepare(baseKey: string, source: image.PixelMap, mode: string, onReady: () => void): boolean {
    const key = ReaderNightImageCache.key(baseKey, mode);
    if (this.results.has(key) || this.pending.has(key) || this.failed.has(key)) return false;
    this.pending.add(key);
    ReaderNightImageCache.process(source, mode).then((result: image.PixelMap | null): void => {
      this.pending.delete(key);
      if (result) this.store(key, result); else this.failed.add(key);
      onReady();
    });
    return true;
  }

  clear(): void {
    // 与 ReaderImageBitmapCache 相同，不主动 release：可能还挂在正在显示的 Image 上。
    this.results.clear();
    this.failed.clear();
  }

  private store(key: string, result: image.PixelMap): void {
    this.results.set(key, result);
    while (this.results.size > ReaderNightImageCache.MAX_ENTRIES) {
      const oldest = this.results.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.results.delete(oldest);
    }
  }

  private static key(baseKey: string, mode: string): string {
    return `${mode}|${baseKey}`;
  }

  private static async process(source: image.PixelMap, mode: string): Promise<image.PixelMap | null> {
    try {
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) return null;
      // readPixels 按区域读出紧凑的 BGRA_8888。
      const area: image.PositionArea = {
        pixels: new ArrayBuffer(width * height * 4),
        offset: 0,
        stride: width * 4,
        region: { size: { width: width, height: height }, x: 0, y: 0 }
      };
      await source.readPixels(area);
      const bytes = new Uint8Array(area.pixels);
      let invert = mode === ReaderNightImage.INVERT;
      if (mode === ReaderNightImage.AUTO) invert = ReaderNightImageCache.autoInvert(bytes);
      if (invert) ReaderNightImageCache.invertBgra(bytes); else ReaderNightImageCache.dimBgra(bytes);
      const options: image.InitializationOptions = {
        size: { width: width, height: height },
        srcPixelFormat: image.PixelMapFormat.BGRA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false
      };
      try {
        return image.createPixelMapUsingAllocatorSync(area.pixels, options, image.AllocatorType.DMA);
      } catch (error) {
        console.warn('[ReaderNightImage] DMA unavailable, using heap memory:', error);
        return image.createPixelMapSync(area.pixels, options);
      }
    } catch (error) {
      console.warn('[ReaderNightImage] process failed:', error);
      return null;
    }
  }

  /** 取样后交给 ReaderNightImage.shouldInvert（它按 RGBA 读，这里把 BGRA 换成 RGBA）。 */
  private static autoInvert(bgra: Uint8Array): boolean {
    const pixelCount = Math.floor(bgra.length / 4);
    const step = ReaderNightImageCache.SAMPLE_STRIDE;
    const samples = new Uint8Array(Math.ceil(pixelCount / step) * 4);
    let out = 0;
    for (let pixel = 0; pixel < pixelCount; pixel += step) {
      const i = pixel * 4;
      samples[out] = bgra[i + 2];
      samples[out + 1] = bgra[i + 1];
      samples[out + 2] = bgra[i];
      samples[out + 3] = bgra[i + 3];
      out += 4;
    }
    return ReaderNightImage.shouldInvert(samples.subarray(0, out));
  }

  private static dimBgra(bgra: Uint8Array): void {
    const k = ReaderNightImage.DIM_BRIGHTNESS;
    for (let i = 0; i + 3 < bgra.length; i += 4) {
      bgra[i] = Math.round(bgra[i] * k);
      bgra[i + 1] = Math.round(bgra[i + 1] * k);
      bgra[i + 2] = Math.round(bgra[i + 2] * k);
    }
  }

  /** 与 ReaderNightImage.invertMatrix 相同：亮度反转、色度保持，out = c − 2·a·L + a。 */
  private static invertBgra(bgra: Uint8Array): void {
    const a = ReaderNightImage.INVERT_AMOUNT;
    const offset = a * 255;
    for (let i = 0; i + 3 < bgra.length; i += 4) {
      const alpha = bgra[i + 3];
      if (alpha === 0) continue;
      const b = bgra[i];
      const g = bgra[i + 1];
      const r = bgra[i + 2];
      // 偏移按不透明度缩放：预乘透明度的像素颜色不会超过透明度，半透明边缘也不会发亮。
      const shift = offset * alpha / 255 - 2 * a * (0.2126 * r + 0.7152 * g + 0.0722 * b);
      bgra[i] = Math.max(0, Math.min(255, Math.round(b + shift)));
      bgra[i + 1] = Math.max(0, Math.min(255, Math.round(g + shift)));
      bgra[i + 2] = Math.max(0, Math.min(255, Math.round(r + shift)));
    }
  }
}
