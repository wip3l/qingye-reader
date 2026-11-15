import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';

/** 读图片文件（沙箱路径或 file:// URI）的原始尺寸，只解析文件头，不解码像素。 */
export class ImageFileSize {
  private static readonly aspects: Map<string, number> = new Map<string, number>();

  static read(uri: string): image.Size | null {
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
      console.warn('[ImageFileSize] read failed:', error);
      return null;
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  /** 宽 / 高；读不出来时返回 0。同一个文件只读一次。 */
  static aspect(uri: string): number {
    const cached = ImageFileSize.aspects.get(uri);
    if (cached !== undefined) return cached;
    const size = ImageFileSize.read(uri);
    const aspect = size ? size.width / size.height : 0;
    ImageFileSize.aspects.set(uri, aspect);
    return aspect;
  }
}
