import fs from '@ohos.file.fs';
import { fileUri } from '../../platform/FileUri';
import image from '@ohos.multimedia.image';
import { ReaderImageMarker } from '../book/ReaderImageMarker';

/**
 * 给没有原始尺寸的图片标记补上宽高。分页器只认标记里的尺寸：尺寸未知的图片一律按整页插图处理并结束当前页，
 * 网络书源的小图（分隔线、表情、作者头像）因此会各占一页。这里在分页之前读一次图片头信息，
 * 只处理已落到本地的文件，远程地址和 data: 保持原样。
 */
export class ReaderImageSizeResolver {
  private static readonly CACHE_LIMIT: number = 512;
  /** 单章最多探测的图片数；超出的保持未知尺寸，避免图集章节在打开时逐张读文件。 */
  private static readonly MAX_PROBES_PER_CHAPTER: number = 64;
  /** path -> [width, height]；读取失败记为 [0, 0]，不再重复尝试。 */
  private static readonly cache: Map<string, number[]> = new Map<string, number[]>();

  /** 正文里是否存在可以补尺寸、且尚未解析过的图片标记。必须足够便宜，会在翻页判定里同步调用。 */
  static needsSizes(content: string): boolean {
    const text = content || '';
    let cursor = text.indexOf(ReaderImageMarker.PREFIX);
    while (cursor >= 0) {
      const suffix = text.indexOf(ReaderImageMarker.SUFFIX, cursor + ReaderImageMarker.PREFIX.length);
      if (suffix < 0) return false;
      const end = suffix + ReaderImageMarker.SUFFIX.length;
      const info = ReaderImageMarker.parse(text.substring(cursor, end));
      if (info.width <= 0 || info.height <= 0) {
        const path = ReaderImageSizeResolver.localPath(info.source);
        if (path && !ReaderImageSizeResolver.cache.has(path)) return true;
        // 已探测成功的图片仍需要把尺寸写回标记。
        if (path && (ReaderImageSizeResolver.cache.get(path) as number[])[0] > 0) return true;
      }
      cursor = text.indexOf(ReaderImageMarker.PREFIX, end);
    }
    return false;
  }

  /** 返回补全尺寸后的正文；没有可补的标记时原样返回同一个字符串。 */
  static async annotate(content: string): Promise<string> {
    const text = content || '';
    if (text.indexOf(ReaderImageMarker.PREFIX) < 0) return text;
    let result = '';
    let copied = 0;
    let probes = 0;
    let cursor = text.indexOf(ReaderImageMarker.PREFIX);
    while (cursor >= 0) {
      const suffix = text.indexOf(ReaderImageMarker.SUFFIX, cursor + ReaderImageMarker.PREFIX.length);
      if (suffix < 0) break;
      const end = suffix + ReaderImageMarker.SUFFIX.length;
      const info = ReaderImageMarker.parse(text.substring(cursor, end));
      const path = info.width > 0 && info.height > 0 ? '' : ReaderImageSizeResolver.localPath(info.source);
      if (path) {
        let size = ReaderImageSizeResolver.cache.get(path);
        if (!size && probes < ReaderImageSizeResolver.MAX_PROBES_PER_CHAPTER) {
          probes++;
          size = await ReaderImageSizeResolver.probe(path);
          ReaderImageSizeResolver.remember(path, size);
        }
        if (size && size[0] > 0 && size[1] > 0) {
          result += text.substring(copied, cursor) + ReaderImageMarker.create(info.source, size[0], size[1]);
          copied = end;
        }
      }
      cursor = text.indexOf(ReaderImageMarker.PREFIX, end);
    }
    return copied === 0 ? text : result + text.substring(copied);
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

  private static remember(path: string, size: number[]): void {
    ReaderImageSizeResolver.cache.set(path, size);
    while (ReaderImageSizeResolver.cache.size > ReaderImageSizeResolver.CACHE_LIMIT) {
      const oldest = ReaderImageSizeResolver.cache.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      ReaderImageSizeResolver.cache.delete(oldest);
    }
  }

  private static async probe(path: string): Promise<number[]> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      return width > 0 && height > 0 ? [width, height] : [0, 0];
    } catch (error) {
      console.warn(`[ReaderImageSize] 读取图片尺寸失败 path=${path}:`, error);
      return [0, 0];
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
  }
}
