import image from '@ohos.multimedia.image';

/** Owns both leaves until the caller transfers them into the texture cache. Never mutates a cached bitmap. */
export class ReaderPageTexturePair {
  // Large desktop/tablet surfaces retain the lower-peak sequential capture path instead of cloning a full spread.
  private static readonly MAX_CLONE_SOURCE_BYTES: number = 12 * 1024 * 1024;
  right: image.PixelMap;
  left: image.PixelMap;
  private released: boolean = false;

  constructor(right: image.PixelMap, left: image.PixelMap) { this.right = right; this.left = left; }

  static async capture(capture: () => Promise<image.PixelMap>,
    crop: (bitmap: image.PixelMap, direction: number) => Promise<void>): Promise<ReaderPageTexturePair> {
    const right = await capture();
    let left: image.PixelMap | null = null;
    try {
      if (right.getPixelBytesNumber() > ReaderPageTexturePair.MAX_CLONE_SOURCE_BYTES) {
        await crop(right, 1);
        left = await capture();
        await crop(left, -1);
        return new ReaderPageTexturePair(right, left);
      }
      left = await right.clone();
      // Crop sequentially: an error must not release a PixelMap while another crop is still using it.
      await crop(right, 1);
      await crop(left, -1);
      return new ReaderPageTexturePair(right, left);
    } catch (error) {
      right.release().catch((): void => {});
      if (left) left.release().catch((): void => {});
      throw error as Error;
    }
  }

  release(): void {
    if (this.released) return;
    this.released = true;
    this.right.release().catch((): void => {});
    this.left.release().catch((): void => {});
  }
}
