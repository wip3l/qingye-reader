import { ReaderCacheCoordinator } from './ReaderCacheCoordinator';
import { ReaderImageMarker } from './ReaderImageMarker';

/**
 * 正文图片的像素尺寸：落盘时从文件头直接读出并按本地路径登记，图片项挂载时就能按真实比例占位，
 * 不必先用占位高度、等异步探测完再改一次高度。读不出的格式返回 null，由图片项照旧探测。
 */
export class ReaderImageDimensions {
  private static readonly LIMIT: number = 8192;
  /** 本地路径 -> [宽, 高]。 */
  private static readonly sizes: Map<string, number[]> = new Map<string, number[]>();

  static remember(path: string, size: number[] | null): void {
    const key = ReaderCacheCoordinator.path(path || '');
    if (!key || !size || size.length < 2 || size[0] <= 0 || size[1] <= 0) return;
    ReaderImageDimensions.sizes.delete(key);
    ReaderImageDimensions.sizes.set(key, [size[0], size[1]]);
    if (ReaderImageDimensions.sizes.size > ReaderImageDimensions.LIMIT) {
      const oldest = ReaderImageDimensions.sizes.keys().next().value as string | undefined;
      if (oldest !== undefined) ReaderImageDimensions.sizes.delete(oldest);
    }
  }

  /** 登记过的 [宽, 高]；没有时为 null。 */
  static size(source: string): number[] | null {
    if (!source) return null;
    return ReaderImageDimensions.sizes.get(ReaderCacheCoordinator.path(source)) || null;
  }

  /** 图片标记；标记自己没带尺寸时补上登记过的像素尺寸，写进正文缓存后重新打开也不用再探测。 */
  static marker(source: string, width: number, height: number): string {
    if (width > 0 && height > 0) return ReaderImageMarker.create(source, width, height);
    const size = ReaderImageDimensions.size(source);
    return size ? ReaderImageMarker.create(source, size[0], size[1]) : ReaderImageMarker.create(source);
  }

  /** 从图片文件头读出 [宽, 高]；不认识的格式、数据不完整或带旋转方向的照片返回 null。 */
  static read(bytes: Uint8Array): number[] | null {
    if (!bytes || bytes.length < 26) return null;
    let size: number[] | null = null;
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      size = [ReaderImageDimensions.be32(bytes, 16), ReaderImageDimensions.be32(bytes, 20)];
    } else if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      size = [bytes[6] | (bytes[7] << 8), bytes[8] | (bytes[9] << 8)];
    } else if (bytes[0] === 0x42 && bytes[1] === 0x4D) {
      size = [Math.abs(ReaderImageDimensions.le32(bytes, 18)), Math.abs(ReaderImageDimensions.le32(bytes, 22))];
    } else if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      size = ReaderImageDimensions.webp(bytes);
    } else if (bytes[0] === 0xFF && bytes[1] === 0xD8) {
      size = ReaderImageDimensions.jpeg(bytes);
    }
    return size && size[0] > 0 && size[1] > 0 && size[0] <= 65535 && size[1] <= 1000000 ? size : null;
  }

  private static be32(bytes: Uint8Array, at: number): number {
    return bytes[at] * 0x1000000 + ((bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]);
  }

  private static le32(bytes: Uint8Array, at: number): number {
    return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24);
  }

  private static webp(bytes: Uint8Array): number[] | null {
    if (bytes.length < 30) return null;
    const kind = String.fromCharCode(bytes[12], bytes[13], bytes[14], bytes[15]);
    if (kind === 'VP8X') {
      return [1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)),
        1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16))];
    }
    if (kind === 'VP8L' && bytes[20] === 0x2F) {
      return [1 + (((bytes[22] & 0x3F) << 8) | bytes[21]),
        1 + (((bytes[24] & 0x0F) << 10) | (bytes[23] << 2) | ((bytes[22] & 0xC0) >> 6))];
    }
    if (kind === 'VP8 ' && bytes[23] === 0x9D && bytes[24] === 0x01 && bytes[25] === 0x2A) {
      return [(bytes[26] | (bytes[27] << 8)) & 0x3FFF, (bytes[28] | (bytes[29] << 8)) & 0x3FFF];
    }
    return null;
  }

  private static jpeg(bytes: Uint8Array): number[] | null {
    let at = 2;
    let turned = false;
    while (at + 9 < bytes.length) {
      if (bytes[at] !== 0xFF) return null;
      const marker = bytes[at + 1];
      if (marker === 0xFF) {
        at++;
        continue;
      }
      // 不带长度的标记。
      if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      if (marker === 0xD9 || marker === 0xDA) return null;
      const length = (bytes[at + 2] << 8) | bytes[at + 3];
      if (length < 2) return null;
      if (marker >= 0xC0 && marker <= 0xCF && marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) {
        const height = (bytes[at + 5] << 8) | bytes[at + 6];
        const width = (bytes[at + 7] << 8) | bytes[at + 8];
        // 照片方向是转过 90° 的：显示出来宽高对调，这里不猜，交给图片组件给出的尺寸。
        return turned ? null : [width, height];
      }
      if (marker === 0xE1 && ReaderImageDimensions.exifTurned(bytes, at + 4, at + 2 + length)) turned = true;
      at += 2 + length;
    }
    return null;
  }

  /** Exif 段里的方向是 5～8（转 90° 或 270°）。 */
  private static exifTurned(bytes: Uint8Array, start: number, end: number): boolean {
    const limit = Math.min(end, bytes.length);
    if (start + 14 > limit || bytes[start] !== 0x45 || bytes[start + 1] !== 0x78 || bytes[start + 2] !== 0x69 ||
      bytes[start + 3] !== 0x66) return false;
    const tiff = start + 6;
    const little = bytes[tiff] === 0x49 && bytes[tiff + 1] === 0x49;
    if (!little && !(bytes[tiff] === 0x4D && bytes[tiff + 1] === 0x4D)) return false;
    const u16 = (at: number): number => little ? bytes[at] | (bytes[at + 1] << 8) : (bytes[at] << 8) | bytes[at + 1];
    const u32 = (at: number): number => little ? ReaderImageDimensions.le32(bytes, at) >>> 0 :
      ReaderImageDimensions.be32(bytes, at);
    const directory = tiff + u32(tiff + 4);
    if (directory + 2 > limit) return false;
    const count = u16(directory);
    for (let index = 0; index < count; index++) {
      const entry = directory + 2 + index * 12;
      if (entry + 12 > limit) return false;
      if (u16(entry) === 0x0112) {
        const orientation = u16(entry + 8);
        return orientation >= 5 && orientation <= 8;
      }
    }
    return false;
  }
}
