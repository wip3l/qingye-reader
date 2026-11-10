import { common } from '@kit.AbilityKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ReadStatsPosterPalette, ReadStatsPosterRenderer } from '../stats/ReadStatsPosterRenderer';
import { ExcerptPosterOptions, ExcerptPosterSnapshot } from './ExcerptPosterModel';

export { ExcerptPosterOptions, ExcerptPosterSnapshot, ExcerptPosterSession } from './ExcerptPosterModel';

class ExcerptPosterColors {
  background: string = '';
  ink: string = '';
  muted: string = '';
  accent: string = '';
  line: string = '';
  serif: boolean = true;
}

/**
 * 摘录分享图：宽 1080 像素、高随文字增长的竖版卡片。像素尺寸固定，不跟屏幕密度、主题和系统字号走。
 * 前三种样式沿用阅读统计海报的配色，第四种从封面取主色。
 */
export class ExcerptPosterRenderer {
  static readonly WIDTH: number = 1080;
  /** 前三个对应阅读统计海报 ReadStatsPosterPalette 的 1、0、2。 */
  static readonly STYLE_NAMES: string[] = ['纸上时光', '清新简约', '夜读星光', '书封取色'];
  /** 超出的部分用省略号收尾，免得图片长得没法看。 */
  static readonly QUOTE_LIMIT: number = 600;
  static readonly NOTE_LIMIT: number = 300;
  private static readonly LEFT: number = 96;
  private static readonly CONTENT_WIDTH: number = 888;
  private static readonly QUOTE_SIZE: number = 46;
  private static readonly QUOTE_LINE: number = 82;
  private static readonly NOTE_SIZE: number = 32;
  private static readonly NOTE_LINE: number = 54;
  private static readonly COVER_WIDTH: number = 96;
  private static readonly COVER_HEIGHT: number = 134;

  /** 样式选择里的小色块。 */
  static swatch(style: number): ReadStatsPosterPalette {
    return ReadStatsPosterPalette.of([1, 0, 2, 1][style] ?? 1);
  }

  static async render(context: common.Context, snapshot: ExcerptPosterSnapshot, options: ExcerptPosterOptions,
    cancelled: () => boolean): Promise<string> {
    let cover: image.PixelMap | null = null;
    let canvas: OffscreenCanvas | null = null;
    let pixels: image.PixelMap | null = null;
    const packer = image.createImagePacker();
    try {
      if ((options.cover || options.style === 3) && snapshot.coverUrl) {
        cover = await ReadStatsPosterRenderer.loadImage(context, snapshot.coverUrl, false);
      }
      if (cancelled()) throw new Error('分享图生成已取消');
      const colors = ExcerptPosterRenderer.colors(options.style, cover);
      const measure = new OffscreenCanvas(16, 16, LengthMetricsUnit.PX).getContext('2d');
      const quoteLines = ExcerptPosterRenderer.wrap(measure, ExcerptPosterRenderer.clip(snapshot.quote,
        ExcerptPosterRenderer.QUOTE_LIMIT), ExcerptPosterRenderer.font(ExcerptPosterRenderer.QUOTE_SIZE, colors.serif),
        ExcerptPosterRenderer.CONTENT_WIDTH);
      const note = options.note ? snapshot.note.trim() : '';
      const noteLines = note ? ExcerptPosterRenderer.wrap(measure, ExcerptPosterRenderer.clip(note,
        ExcerptPosterRenderer.NOTE_LIMIT), ExcerptPosterRenderer.font(ExcerptPosterRenderer.NOTE_SIZE, false),
        ExcerptPosterRenderer.CONTENT_WIDTH - 28) : [];
      const height = ExcerptPosterRenderer.height(quoteLines.length, noteLines.length, options, cover !== null);
      canvas = new OffscreenCanvas(ExcerptPosterRenderer.WIDTH, height, LengthMetricsUnit.PX);
      const ctx = canvas.getContext('2d', new RenderingContextSettings(true));
      ExcerptPosterRenderer.draw(ctx, snapshot, options, colors, quoteLines, noteLines, cover, height);
      pixels = ctx.getPixelMap(0, 0, ExcerptPosterRenderer.WIDTH, height);
      const bytes = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      if (cancelled()) throw new Error('分享图生成已取消');
      // 和阅读统计海报放在同一个缓存目录，过期清理也共用。
      const folder = `${context.cacheDir}/${ReadStatsPosterRenderer.CACHE_FOLDER}`;
      if (!fileIo.accessSync(folder)) fileIo.mkdirSync(folder);
      const path = `${folder}/${util.generateRandomUUID(true)}.png`;
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); } finally { fileIo.closeSync(file); }
      return path;
    } finally {
      if (cover) cover.release();
      if (pixels) pixels.release();
      packer.release();
      if (canvas) { canvas.width = 1; canvas.height = 1; }
    }
  }

  private static font(size: number, serif: boolean, bold: boolean = false): string {
    return `${bold ? 'bold ' : ''}${size}px ${serif ? 'serif' : 'sans-serif'}`;
  }

  private static clip(text: string, limit: number): string {
    const letters = Array.from(text.trim());
    return letters.length > limit ? letters.slice(0, limit).join('') + '…' : letters.join('');
  }

  /** 按宽度逐字断行，原文里的换行保留，空行去掉。 */
  private static wrap(ctx: OffscreenCanvasRenderingContext2D, text: string, font: string, width: number): string[] {
    ctx.font = font;
    const lines: string[] = [];
    for (const paragraph of text.split(/\r?\n/)) {
      const letters = Array.from(paragraph.trim());
      if (letters.length === 0) continue;
      let line = '';
      for (const letter of letters) {
        if (line && ctx.measureText(line + letter).width > width) {
          lines.push(line);
          line = '';
        }
        line += letter;
      }
      if (line) lines.push(line);
    }
    return lines.length > 0 ? lines : [''];
  }

  /** 和 draw 的排版一一对应。 */
  private static height(quoteLines: number, noteLines: number, options: ExcerptPosterOptions,
    hasCover: boolean): number {
    let y = 240 + quoteLines * ExcerptPosterRenderer.QUOTE_LINE;
    if (noteLines > 0) y += 44 + noteLines * ExcerptPosterRenderer.NOTE_LINE;
    y += 64;
    y += options.cover && hasCover ? ExcerptPosterRenderer.COVER_HEIGHT : (options.meta ? 92 : 48);
    y += 72 + 40 + 72;
    return Math.round(y);
  }

  private static draw(ctx: OffscreenCanvasRenderingContext2D, snapshot: ExcerptPosterSnapshot,
    options: ExcerptPosterOptions, colors: ExcerptPosterColors, quoteLines: string[], noteLines: string[],
    cover: image.PixelMap | null, height: number): void {
    const left = ExcerptPosterRenderer.LEFT;
    const right = left + ExcerptPosterRenderer.CONTENT_WIDTH;
    ctx.fillStyle = colors.background;
    ctx.fillRect(0, 0, ExcerptPosterRenderer.WIDTH, height);
    ExcerptPosterRenderer.decorate(ctx, options.style, colors, height);
    ctx.textBaseline = 'top';

    const highlight = options.accent ? snapshot.color : colors.accent;
    ctx.fillStyle = highlight;
    ctx.font = ExcerptPosterRenderer.font(160, true, true);
    ctx.fillText('“', left - 8, 70);

    let y = 240;
    if (options.accent) {
      ctx.fillStyle = snapshot.color;
      ctx.fillRect(left - 36, y + 8, 6, quoteLines.length * ExcerptPosterRenderer.QUOTE_LINE - 30);
    }
    ctx.fillStyle = colors.ink;
    ctx.font = ExcerptPosterRenderer.font(ExcerptPosterRenderer.QUOTE_SIZE, colors.serif);
    for (const line of quoteLines) {
      ctx.fillText(line, left, y);
      y += ExcerptPosterRenderer.QUOTE_LINE;
    }

    if (noteLines.length > 0) {
      y += 44;
      ctx.fillStyle = colors.line;
      ctx.fillRect(left, y + 4, 4, noteLines.length * ExcerptPosterRenderer.NOTE_LINE - 16);
      ctx.fillStyle = colors.muted;
      ctx.font = ExcerptPosterRenderer.font(ExcerptPosterRenderer.NOTE_SIZE, false);
      for (const line of noteLines) {
        ctx.fillText(line, left + 28, y);
        y += ExcerptPosterRenderer.NOTE_LINE;
      }
    }

    y += 64;
    ctx.fillStyle = colors.line;
    ctx.fillRect(left, y - 32, ExcerptPosterRenderer.CONTENT_WIDTH, 2);
    let textLeft = left;
    const showCover = options.cover && cover !== null;
    if (showCover && cover) {
      ctx.drawImage(cover, left, y, ExcerptPosterRenderer.COVER_WIDTH, ExcerptPosterRenderer.COVER_HEIGHT);
      textLeft = left + ExcerptPosterRenderer.COVER_WIDTH + 36;
    }
    const rowHeight = showCover ? ExcerptPosterRenderer.COVER_HEIGHT : (options.meta ? 92 : 48);
    const titleTop = showCover ? y + (options.meta ? 22 : 46) : y;
    const title = `《${snapshot.bookName || '未知书籍'}》${snapshot.author ? `  ${snapshot.author}` : ''}`;
    ctx.fillStyle = colors.ink;
    ctx.font = ExcerptPosterRenderer.font(36, false, true);
    ctx.fillText(ExcerptPosterRenderer.ellipsize(ctx, title, right - textLeft), textLeft, titleTop);
    if (options.meta) {
      const date = new Date(snapshot.time || Date.now());
      const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
      const day = `摘于 ${date.getFullYear()}.${pad(date.getMonth() + 1)}.${pad(date.getDate())}`;
      const meta = snapshot.chapterName ? `${snapshot.chapterName} · ${day}` : day;
      ctx.fillStyle = colors.muted;
      ctx.font = ExcerptPosterRenderer.font(28, false);
      ctx.fillText(ExcerptPosterRenderer.ellipsize(ctx, meta, right - textLeft), textLeft, titleTop + 54);
    }
    y += rowHeight + 72;

    ctx.font = ExcerptPosterRenderer.font(26, false);
    ctx.fillStyle = colors.muted;
    const name = options.alias.trim() || snapshot.nickname;
    if (options.signature && name) {
      ctx.fillText(ExcerptPosterRenderer.ellipsize(ctx, `— ${name}`, 560), left, y);
    }
    const brand = '轻页 · 读书摘录';
    ctx.fillText(brand, right - ctx.measureText(brand).width, y);
  }

  private static ellipsize(ctx: OffscreenCanvasRenderingContext2D, text: string, width: number): string {
    if (ctx.measureText(text).width <= width) return text;
    let letters = Array.from(text);
    while (letters.length > 1 && ctx.measureText(letters.join('') + '…').width > width) letters = letters.slice(0, -1);
    return letters.join('') + '…';
  }

  /** 和阅读统计海报同一套点缀：纸纹、星点，书封取色只铺底色。 */
  private static decorate(ctx: OffscreenCanvasRenderingContext2D, style: number, colors: ExcerptPosterColors,
    height: number): void {
    if (style === 0) {
      ctx.fillStyle = colors.muted;
      ctx.globalAlpha = 0.07;
      for (let index = 0; index < 1600; index++) ctx.fillRect(index * 173 % 1080, index * 113 % height, 1, 1);
      ctx.globalAlpha = 1;
    } else if (style === 2) {
      for (let index = 0; index < 60; index++) {
        ctx.globalAlpha = 0.15 + index % 4 * 0.14;
        ctx.fillStyle = colors.ink;
        ctx.beginPath();
        ctx.arc((index * 137 + 27) % 1080, (index * 71 + 19) % 200, index % 3 === 0 ? 2 : 1, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }
  }

  private static colors(style: number, cover: image.PixelMap | null): ExcerptPosterColors {
    const colors = new ExcerptPosterColors();
    const tone = style === 3 && cover ? ExcerptPosterRenderer.coverTone(cover) : null;
    if (tone) {
      const hue = tone[0];
      const saturation = Math.min(0.45, tone[1]);
      colors.background = ExcerptPosterRenderer.hsl(hue, saturation, 0.22);
      colors.ink = '#F5F1E8';
      colors.muted = '#BDB8AE';
      colors.accent = ExcerptPosterRenderer.hsl(hue, Math.max(0.35, saturation), 0.68);
      colors.line = ExcerptPosterRenderer.hsl(hue, saturation * 0.6, 0.34);
      colors.serif = true;
      return colors;
    }
    // 书封取色没有封面时退回纸上时光。
    const palette = ReadStatsPosterPalette.of([1, 0, 2, 1][style] ?? 1);
    colors.background = palette.background;
    colors.ink = palette.ink;
    colors.muted = palette.muted;
    colors.accent = palette.accent;
    colors.line = palette.line;
    colors.serif = style !== 1;
    return colors;
  }

  /** 封面缩到 8×8 取平均色，返回 [色相 0~360, 饱和度 0~1, 亮度 0~1]。 */
  private static coverTone(cover: image.PixelMap): number[] | null {
    let canvas: OffscreenCanvas | null = null;
    try {
      canvas = new OffscreenCanvas(8, 8, LengthMetricsUnit.PX);
      const ctx = canvas.getContext('2d');
      ctx.drawImage(cover, 0, 0, 8, 8);
      const data = ctx.getImageData(0, 0, 8, 8).data;
      let r = 0;
      let g = 0;
      let b = 0;
      let count = 0;
      for (let index = 0; index + 3 < data.length; index += 4) {
        if (data[index + 3] < 128) continue;
        r += data[index]; g += data[index + 1]; b += data[index + 2];
        count++;
      }
      if (count === 0) return null;
      return ExcerptPosterRenderer.toHsl(r / count / 255, g / count / 255, b / count / 255);
    } catch (_) {
      return null;
    } finally {
      if (canvas) { canvas.width = 1; canvas.height = 1; }
    }
  }

  private static toHsl(r: number, g: number, b: number): number[] {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const light = (max + min) / 2;
    if (max === min) return [0, 0, light];
    const delta = max - min;
    const saturation = light > 0.5 ? delta / (2 - max - min) : delta / (max + min);
    let hue = 0;
    if (max === r) hue = (g - b) / delta + (g < b ? 6 : 0);
    else if (max === g) hue = (b - r) / delta + 2;
    else hue = (r - g) / delta + 4;
    return [hue * 60, saturation, light];
  }

  private static hsl(hue: number, saturation: number, light: number): string {
    const chroma = (1 - Math.abs(2 * light - 1)) * saturation;
    const x = chroma * (1 - Math.abs((hue / 60) % 2 - 1));
    const m = light - chroma / 2;
    let rgb: number[] = [0, 0, 0];
    if (hue < 60) rgb = [chroma, x, 0];
    else if (hue < 120) rgb = [x, chroma, 0];
    else if (hue < 180) rgb = [0, chroma, x];
    else if (hue < 240) rgb = [0, x, chroma];
    else if (hue < 300) rgb = [x, 0, chroma];
    else rgb = [chroma, 0, x];
    return '#' + rgb.map((value: number): string => {
      const channel = Math.max(0, Math.min(255, Math.round((value + m) * 255)));
      return (channel < 16 ? '0' : '') + channel.toString(16);
    }).join('').toUpperCase();
  }
}
