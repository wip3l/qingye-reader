import { text, drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { ReaderV2Color } from '../core/reader/ReaderV2Style';

/** 一张字体名字预览图：file:// 地址与显示尺寸（vp）。 */
export class ReaderFontPreviewImage {
  uri: string = '';
  widthVp: number = 0;
  heightVp: number = 0;
}

/** 要画的内容。尺寸单位：字号 fp、宽度 vp；density 为 vp→px 的倍数。 */
export class ReaderFontPreviewRequest {
  filePath: string = '';
  label: string = '';
  fontSizeFp: number = 16;
  color: string = '#FF202124';
  maxWidthVp: number = 240;
  density: number = 3;
  fontScale: number = 1;
}

class ReaderFontPreviewJob {
  key: string;
  request: ReaderFontPreviewRequest;
  listeners: Array<() => void> = [];

  constructor(key: string, request: ReaderFontPreviewRequest) {
    this.key = key;
    this.request = request;
  }

  notify(): void {
    for (const listener of this.listeners) listener();
  }
}

/**
 * 字体列表里“用字体本身显示名字”的预览图。以前每一行都把整个字体注册进界面和排版引擎（中文字体十几到几十 MB，
 * 注册了卸不掉），导入字体多的用户一打开列表内存就涨到几 GB 被系统结束。
 * 现在逐款放进一个私有字体集合，画出名字存成 PNG（cacheDir/font_previews），画完立即卸载；同一时间只加载一款，
 * 画好的图按“文件+修改时间+文字+字号+颜色+宽度”缓存在磁盘上，下次直接用。
 */
export class ReaderFontPreviewImages {
  private static readonly VERSION: number = 1;
  private static readonly DIR_NAME: string = 'font_previews';
  private static dir: string = '';
  private static images: Map<string, ReaderFontPreviewImage> = new Map<string, ReaderFontPreviewImage>();
  private static failed: Set<string> = new Set<string>();
  private static queue: ReaderFontPreviewJob[] = [];
  private static current: ReaderFontPreviewJob | null = null;
  private static serial: number = 0;

  static init(cacheDir: string): void {
    if (ReaderFontPreviewImages.dir) return;
    ReaderFontPreviewImages.dir = `${cacheDir}/${ReaderFontPreviewImages.DIR_NAME}`;
  }

  /** 已有的预览图；没有时返回 null 并排队生成，生成好（或失败）后调 done。 */
  static lookup(request: ReaderFontPreviewRequest, done: () => void): ReaderFontPreviewImage | null {
    if (!ReaderFontPreviewImages.dir || !request.filePath) return null;
    const key = ReaderFontPreviewImages.keyOf(request);
    if (!key) return null;
    const known = ReaderFontPreviewImages.images.get(key);
    if (known) return known;
    if (ReaderFontPreviewImages.failed.has(key)) return null;
    const stored = ReaderFontPreviewImages.readStored(key, request.density);
    if (stored) {
      ReaderFontPreviewImages.images.set(key, stored);
      return stored;
    }
    let job = ReaderFontPreviewImages.queue.find((item: ReaderFontPreviewJob): boolean => item.key === key);
    if (!job && ReaderFontPreviewImages.current && ReaderFontPreviewImages.current.key === key) {
      job = ReaderFontPreviewImages.current;
    }
    if (job) {
      if (job.listeners.indexOf(done) < 0) job.listeners.push(done);
      return null;
    }
    job = new ReaderFontPreviewJob(key, request);
    job.listeners.push(done);
    ReaderFontPreviewImages.queue.push(job);
    ReaderFontPreviewImages.pump();
    return null;
  }

  private static pump(): void {
    if (ReaderFontPreviewImages.current) return;
    const job = ReaderFontPreviewImages.queue.shift();
    if (!job) return;
    ReaderFontPreviewImages.current = job;
    ReaderFontPreviewImages.render(job)
      .then((preview: ReaderFontPreviewImage | null): void => {
        if (preview) {
          ReaderFontPreviewImages.images.set(job.key, preview);
        } else {
          ReaderFontPreviewImages.failed.add(job.key);
        }
        job.notify();
      })
      .catch((error: Error): void => {
        console.warn('生成字体预览图失败:', job.request.filePath, error);
        ReaderFontPreviewImages.failed.add(job.key);
        job.notify();
      })
      .finally((): void => {
        ReaderFontPreviewImages.current = null;
        // 让出一帧，生成很多款时列表也能照常滑动。
        setTimeout((): void => ReaderFontPreviewImages.pump(), 16);
      });
  }

  private static async render(job: ReaderFontPreviewJob): Promise<ReaderFontPreviewImage | null> {
    const request = job.request;
    const collection = new text.FontCollection();
    const family = `ReaderFontPreview_${++ReaderFontPreviewImages.serial}`;
    let pixelMap: image.PixelMap | null = null;
    try {
      // 异步加载在后台线程读文件；只进这个私有集合，不进全局字体。
      await collection.loadFont(family, `file://${request.filePath}`);
      const density = Math.max(1, request.density);
      const fontSize = request.fontSizeFp * Math.max(0.5, request.fontScale) * density;
      const maxWidth = Math.max(1, Math.floor(request.maxWidthVp * density));
      const style: text.TextStyle = {
        color: ReaderFontPreviewImages.color(request.color),
        fontSize: fontSize,
        fontFamilies: [family],
        ellipsis: '…',
        ellipsisMode: text.EllipsisMode.END
      };
      const builder = new text.ParagraphBuilder({ textStyle: style, maxLines: 1 }, collection);
      builder.addText(request.label);
      const paragraph = builder.build();
      paragraph.layoutSync(maxWidth);
      const width = Math.max(1, Math.min(maxWidth, Math.ceil(paragraph.getLongestLine()) + 2));
      const height = Math.max(1, Math.ceil(paragraph.getHeight()));
      const options: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: true
      };
      pixelMap = image.createPixelMapSync(new ArrayBuffer(width * height * 4), options);
      const canvas = new drawing.Canvas(pixelMap);
      paragraph.paint(canvas, 0, 0);
      const packer = image.createImagePacker();
      let bytes: ArrayBuffer;
      try {
        bytes = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      } finally {
        packer.release();
      }
      const path = ReaderFontPreviewImages.pathOf(job.key);
      ReaderFontPreviewImages.ensureDir();
      const temp = `${path}.tmp`;
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temp, path);
      const preview = new ReaderFontPreviewImage();
      preview.uri = `file://${path}`;
      preview.widthVp = width / density;
      preview.heightVp = height / density;
      return preview;
    } finally {
      if (pixelMap) pixelMap.release().catch((): void => {});
      try {
        collection.unloadFontSync(family);
      } catch (e) {
      }
      collection.clearCaches();
    }
  }

  /** 磁盘上已有的图：尺寸从 PNG 头（IHDR）读，不解码。 */
  private static readStored(key: string, density: number): ReaderFontPreviewImage | null {
    const path = ReaderFontPreviewImages.pathOf(key);
    try {
      if (!fs.accessSync(path)) return null;
      const buffer = new ArrayBuffer(24);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        if (fs.readSync(file.fd, buffer, { offset: 0, length: 24 }) < 24) return null;
      } finally {
        fs.closeSync(file);
      }
      const view = new DataView(buffer);
      const width = view.getUint32(16);
      const height = view.getUint32(20);
      if (width <= 0 || height <= 0) return null;
      const preview = new ReaderFontPreviewImage();
      preview.uri = `file://${path}`;
      preview.widthVp = width / Math.max(1, density);
      preview.heightVp = height / Math.max(1, density);
      return preview;
    } catch (e) {
      return null;
    }
  }

  private static keyOf(request: ReaderFontPreviewRequest): string {
    let stamp = '';
    try {
      const stat = fs.statSync(request.filePath);
      stamp = `${stat.size}:${stat.mtime}`;
    } catch (e) {
      return '';
    }
    const seed = [ReaderFontPreviewImages.VERSION, request.filePath, stamp, request.label,
      request.fontSizeFp, request.fontScale, request.color, Math.round(request.maxWidthVp), request.density].join('|');
    return `${ReaderFontPreviewImages.hash(seed, 0x811c9dc5)}${ReaderFontPreviewImages.hash(seed, 0x01000193)}`;
  }

  private static hash(value: string, seed: number): string {
    let hash = seed >>> 0;
    for (let i = 0; i < value.length; i++) {
      hash = Math.imul(hash ^ value.charCodeAt(i), 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }

  private static pathOf(key: string): string {
    return `${ReaderFontPreviewImages.dir}/${key}.png`;
  }

  private static ensureDir(): void {
    if (!fs.accessSync(ReaderFontPreviewImages.dir)) fs.mkdirSync(ReaderFontPreviewImages.dir, true);
  }

  private static color(value: string): common2D.Color {
    const argb = ReaderV2Color.parse(value, 0xFF202124);
    return { alpha: (argb >>> 24) & 255, red: (argb >>> 16) & 255, green: (argb >>> 8) & 255, blue: argb & 255 };
  }
}
