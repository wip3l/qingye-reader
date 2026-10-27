import { common } from '@kit.AbilityKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BookCoverCache } from '../../utils/BookCoverCache';
import { ReadStatsSummary, ReadStatsRank, ReadStatsBar } from './ReadStatsSummary';
import { ReadStatsPosterSnapshot, ReadStatsPosterOptions, ReadStatsPosterLayout, ReadStatsPosterPage } from './ReadStatsPosterModel';

export class ReadStatsPosterPalette {
  background: string = '#F8F8EF';
  ink: string = '#243D30';
  muted: string = '#6C7B6C';
  accent: string = '#588663';
  panel: string = '#E6EDD9';
  line: string = '#D8DFCC';
  decoration: string = '#B7C6A1';

  static of(style: number): ReadStatsPosterPalette {
    const p = new ReadStatsPosterPalette();
    if (style === 1) {
      p.background = '#F5EAD7'; p.ink = '#573922'; p.muted = '#94785F';
      p.accent = '#A57A50'; p.panel = '#ECE0CC'; p.line = '#D6BFA0'; p.decoration = '#CAB08A';
    } else if (style === 2) {
      p.background = '#101F36'; p.ink = '#F4DEAD'; p.muted = '#A4B6C7';
      p.accent = '#E8C581'; p.panel = '#1C3048'; p.line = '#3D5062'; p.decoration = '#283F59';
    } else if (style === 3) {
      p.background = '#FFFEFA'; p.ink = '#20201E'; p.muted = '#77766E';
      p.accent = '#C7684E'; p.panel = '#F2F0E9'; p.line = '#CFCFC6'; p.decoration = '#E5E1D7';
    }
    return p;
  }
}

/** Fixed pixel geometry, independent of screen density, theme and accessibility font scaling. */
export class ReadStatsPosterRenderer {
  static readonly CACHE_FOLDER: string = 'reading_stats_posters';
  private ctx: OffscreenCanvasRenderingContext2D;
  private palette: ReadStatsPosterPalette;
  private style: number;

  constructor(ctx: OffscreenCanvasRenderingContext2D, style: number) {
    this.ctx = ctx;
    this.style = style;
    this.palette = ReadStatsPosterPalette.of(style);
  }

  static async render(context: common.Context, snapshot: ReadStatsPosterSnapshot, options: ReadStatsPosterOptions,
    page: ReadStatsPosterPage, cancelled: () => boolean): Promise<string> {
    const covers = new Map<string, image.PixelMap>();
    let avatar: image.PixelMap | null = null;
    let canvas: OffscreenCanvas | null = null;
    let pixels: image.PixelMap | null = null;
    const packer = image.createImagePacker();
    try {
      // At most ten cover decodes per page; no full-resolution image cache is retained.
      for (let index = 0; index < page.books.length; index += 3) {
        if (cancelled()) throw new Error('海报生成已取消');
        await Promise.all(page.books.slice(index, index + 3).map(async (book: ReadStatsRank): Promise<void> => {
          const cover = await ReadStatsPosterRenderer.loadImage(context, book.coverUrl, false);
          if (cover) covers.set(book.bookKey, cover);
        }));
      }
      if (options.profile && options.avatar && snapshot.avatar && !cancelled()) {
        avatar = await ReadStatsPosterRenderer.loadImage(context, snapshot.avatar, true);
      }
      if (cancelled()) throw new Error('海报生成已取消');
      canvas = new OffscreenCanvas(ReadStatsPosterLayout.WIDTH, page.height, LengthMetricsUnit.PX);
      const renderer = new ReadStatsPosterRenderer(canvas.getContext('2d', new RenderingContextSettings(true)), options.style);
      renderer.draw(snapshot, options, page, covers, avatar);
      pixels = renderer.ctx.getPixelMap(0, 0, ReadStatsPosterLayout.WIDTH, page.height);
      const bytes = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      if (cancelled()) throw new Error('海报生成已取消');
      const folder = `${context.cacheDir}/${ReadStatsPosterRenderer.CACHE_FOLDER}`;
      if (!fileIo.accessSync(folder)) fileIo.mkdirSync(folder);
      const path = `${folder}/${util.generateRandomUUID(true)}.png`;
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); } finally { fileIo.closeSync(file); }
      return path;
    } finally {
      covers.forEach((cover: image.PixelMap): void => { cover.release(); });
      if (avatar) avatar.release();
      if (pixels) pixels.release();
      packer.release();
      if (canvas) { canvas.width = 1; canvas.height = 1; }
    }
  }

  static async cleanExpired(context: common.Context): Promise<void> {
    const folder = `${context.cacheDir}/${ReadStatsPosterRenderer.CACHE_FOLDER}`;
    try {
      if (!fileIo.accessSync(folder)) return;
      for (const name of await fileIo.listFile(folder)) {
        if (!/^[a-f0-9-]+\.png$/i.test(name)) continue;
        const path = `${folder}/${name}`;
        const stat = await fileIo.stat(path);
        // Shared files must remain readable after the system panel closes.
        if (Date.now() - stat.mtime * 1000 > 86400000) await fileIo.unlink(path);
      }
    } catch (_) { /* Cache maintenance must not block sharing. */ }
  }

  private static async loadImage(context: common.Context, raw: string, avatar: boolean): Promise<image.PixelMap | null> {
    if (!raw) return null;
    let source: image.ImageSource | null = null;
    let file: fileIo.File | null = null;
    try {
      let resolved = raw;
      if (/^https?:\/\//i.test(raw)) {
        resolved = await BookCoverCache.resolveCachedCoverAsync(context, raw) || raw;
      }
      if (/^https?:\/\//i.test(resolved)) {
        const request = http.createHttp();
        try {
          const response = await request.request(resolved, { method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER, connectTimeout: 2000, readTimeout: 2000,
            maxLimit: 2 * 1024 * 1024 });
          if (response.responseCode !== 200) return null;
          source = image.createImageSource(response.result as ArrayBuffer);
        } finally { request.destroy(); }
      } else {
        const path = resolved.startsWith('file:') ? new fileUri.FileUri(resolved).path : resolved;
        if (!path.startsWith('/')) return null;
        file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      const info = await source.getImageInfo();
      const scale = Math.min(1, (avatar ? 160 : 240) / Math.max(info.size.width, info.size.height));
      return await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale))
      } });
    } catch (_) { return null; } finally {
      if (source) source.release();
      if (file) fileIo.closeSync(file);
    }
  }

  private text(content: string, x: number, y: number, size: number, color: string, max: number = 960,
    bold: boolean = false): void {
    this.ctx.fillStyle = color;
    this.ctx.textBaseline = 'top';
    this.ctx.font = `${bold ? 'bold ' : ''}${size}px ${this.style === 1 ? 'serif' : 'sans-serif'}`;
    this.ctx.fillText(content, x, y, max);
  }

  private rule(y: number): void {
    this.ctx.fillStyle = this.palette.line;
    this.ctx.fillRect(64, y, 952, this.style === 3 ? 2 : 1);
  }

  private roundBox(x: number, y: number, w: number, h: number, radius: number, fill: string): void {
    const c = this.ctx;
    c.fillStyle = fill;
    c.beginPath(); c.moveTo(x + radius, y); c.lineTo(x + w - radius, y);
    c.quadraticCurveTo(x + w, y, x + w, y + radius); c.lineTo(x + w, y + h - radius);
    c.quadraticCurveTo(x + w, y + h, x + w - radius, y + h); c.lineTo(x + radius, y + h);
    c.quadraticCurveTo(x, y + h, x, y + h - radius); c.lineTo(x, y + radius);
    c.quadraticCurveTo(x, y, x + radius, y); c.closePath(); c.fill();
  }

  private scenery(h: number): void {
    const c = this.ctx;
    const p = this.palette;
    c.fillStyle = p.background; c.fillRect(0, 0, 1080, h);
    if (this.style === 2) {
      for (let index = 0; index < 80; index++) {
        const x = (index * 137 + 27) % 1080;
        const y = (index * 71 + 19) % 240;
        c.globalAlpha = 0.15 + index % 4 * 0.14;
        c.fillStyle = p.ink; c.beginPath(); c.arc(x, y, index % 3 === 0 ? 2 : 1, 0, Math.PI * 2); c.fill();
      }
      c.globalAlpha = 1;
      c.fillStyle = p.decoration; c.beginPath(); c.moveTo(0, h);
      for (let x = 0; x <= 1080; x += 90) c.lineTo(x, h - 35 - Math.sin(x / 95) * 12);
      c.lineTo(1080, h); c.closePath(); c.fill();
    } else if (this.style === 0 || this.style === 1) {
      c.save(); c.globalAlpha = this.style === 0 ? 0.45 : 0.25;
      c.strokeStyle = p.accent; c.lineWidth = 2;
      c.beginPath(); c.moveTo(920, 0); c.quadraticCurveTo(970, 85, 1080, 155); c.stroke();
      for (let index = 0; index < 7; index++) {
        const x = 944 + index * 21;
        const y = 10 + index * 20;
        c.fillStyle = p.decoration; c.beginPath(); c.moveTo(x, y);
        c.quadraticCurveTo(x - 80, y - 12, x - 72, y + 40);
        c.quadraticCurveTo(x - 30, y + 47, x, y); c.fill();
      }
      c.restore();
      if (this.style === 1) {
        c.fillStyle = p.muted; c.globalAlpha = 0.07;
        for (let index = 0; index < 1600; index++) c.fillRect(index * 173 % 1080, index * 113 % h, 1, 1);
        c.globalAlpha = 1;
      }
    } else { c.fillStyle = p.accent; c.fillRect(64, 58, 65, 8); }
  }

  draw(snapshot: ReadStatsPosterSnapshot, options: ReadStatsPosterOptions, page: ReadStatsPosterPage,
    covers: Map<string, image.PixelMap>, avatar: image.PixelMap | null): void {
    const p = this.palette;
    this.scenery(page.height);
    this.text('READING JOURNAL', 64, 86, 23, p.muted);
    this.text(snapshot.title(), 64, 132, 65, p.ink, 930, true);
    this.text(snapshot.period, 66, 226, 28, p.muted, 950);
    this.text(snapshot.device, 66, 270, 25, p.accent, 950);
    if (this.style === 0 || this.style === 2) this.roundBox(48, 324, 984, 260, 24, p.panel);
    else this.rule(320);
    this.text('阅读总时长', 80, 349, 28, p.muted);
    this.text(ReadStatsSummary.duration(snapshot.totalMs), 76, 396, 94, p.ink, 930, true);
    this.text(`阅读书籍  ${snapshot.books.length}本`, 80, 530, 27, p.ink, 290);
    this.text(`阅读天数  ${snapshot.activeDays}天`, 392, 530, 27, p.ink, 290);
    this.text(`日均  ${ReadStatsSummary.duration(snapshot.averageMs)}`, 714, 530, 27, p.ink, 285);
    let y = 630;
    if (snapshot.mode !== 'day' && snapshot.bars.length > 0) {
      this.text('阅读趋势', 64, y, 31, p.ink, 700, true);
      const bars = snapshot.bars;
      const peak = Math.max(1, ...bars.map((bar: ReadStatsBar): number => bar.durationMs));
      const step = 940 / bars.length;
      for (let index = 0; index < bars.length; index++) {
        const h = bars[index].durationMs > 0 ? Math.max(3, 160 * bars[index].durationMs / peak) : 0;
        const x = 70 + index * step;
        if (h > 0) this.roundBox(x + step * 0.18, y + 228 - h, step * 0.64, h, Math.min(5, step / 5), p.accent);
        if (bars.length <= 12 || index === bars.length - 1 || index % Math.ceil(bars.length / 6) === 0) {
          this.text(bars[index].label, x, y + 245, 23, p.muted, Math.max(30, step * 1.8));
        }
      }
      y += 310;
    }
    if (page.books.length > 0) {
      this.rule(y - 12);
      this.text(options.rankLimit === -1 ? '完整阅读榜' : `阅读榜 TOP ${Math.min(options.rankLimit, snapshot.books.length)}`,
        64, y + 10, 32, p.ink, 800, true);
      y += 85;
      for (const book of page.books) {
        this.text(`${book.rank}`.padStart(2, '0'), 64, y + 25, 26, p.accent, 50);
        this.roundBox(126, y, 60, 86, 5, p.panel);
        const cover = covers.get(book.bookKey);
        if (cover) this.ctx.drawImage(cover, 126, y, 60, 86);
        else {
          this.text(Array.from(book.name)[0] || '书', 143, y + 26, 27, p.accent, 40);
          this.ctx.fillStyle = p.line; this.ctx.fillRect(130, y + 3, 2, 80);
        }
        this.bookTitle(book.name, y + 12);
        this.text(ReadStatsSummary.duration(book.durationMs), 794, y + 27, 26, p.muted, 220);
        y += 108;
      }
    }
    if (ReadStatsPosterLayout.hasProfile(snapshot, options)) {
      this.rule(y + 8);
      let x = 64;
      if (options.avatar) {
        this.ctx.save(); this.ctx.beginPath(); this.ctx.arc(108, y + 80, 42, 0, Math.PI * 2); this.ctx.clip();
        this.ctx.fillStyle = p.panel; this.ctx.fillRect(64, y + 36, 88, 88);
        if (avatar) this.ctx.drawImage(avatar, 64, y + 36, 88, 88);
        else this.text(Array.from(options.alias || snapshot.nickname || '读')[0], 90, y + 59, 36, p.accent, 50);
        this.ctx.restore(); x = 180;
      }
      if (options.nickname) this.text(options.alias || snapshot.nickname, x, y + 42, 32, p.ink, 1000 - x, true);
      if (options.signature && options.quote) {
        this.wrapQuote(options.quote, x, y + (options.nickname && (options.alias || snapshot.nickname) ? 93 : 58), 1000 - x);
      }
      y += 150;
    }
    this.text('轻页 · 阅读记录', 64, page.height - 43, 23, p.muted, 500);
    this.text(`含听书时长${page.count > 1 ? ` · ${page.index + 1}/${page.count}` : ''}`, 750, page.height - 43, 23, p.muted, 265);
  }

  private bookTitle(name: string, y: number): void {
    this.ctx.font = '32px sans-serif';
    let line = '';
    const letters = Array.from(name);
    let offset = 0;
    for (; offset < letters.length; offset++) {
      if (this.ctx.measureText(line + letters[offset]).width > 555) break;
      line += letters[offset];
    }
    this.text(line, 216, y, 32, this.palette.ink, 555, true);
    if (offset < letters.length) {
      this.ctx.font = '28px sans-serif';
      let tail = letters.slice(offset).join('');
      while (this.ctx.measureText(tail).width > 550 && tail.length > 1) tail = Array.from(tail).slice(0, -2).join('') + '…';
      this.text(tail, 216, y + 39, 28, this.palette.ink, 555);
    }
  }

  private wrapQuote(quote: string, x: number, y: number, max: number): void {
    this.ctx.font = '25px sans-serif';
    let first = '';
    const letters = Array.from(quote);
    let index = 0;
    for (; index < letters.length; index++) {
      if (this.ctx.measureText(first + letters[index]).width > max) break;
      first += letters[index];
    }
    this.text(first, x, y, 25, this.palette.muted, max);
    if (index < letters.length) this.text(letters.slice(index).join(''), x, y + 32, 25, this.palette.muted, max);
  }
}
