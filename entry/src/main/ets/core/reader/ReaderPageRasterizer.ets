import image from '@ohos.multimedia.image';
import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderV2PageLayout } from './ReaderV2PageLayout';
import { ReaderV2PagePainter } from './ReaderV2PagePainter';

/** A bitmap placed on the raster. Coordinates are unscaled surface pixels. */
export class ReaderRasterImage {
  pixelMap: image.PixelMap;
  left: number;
  top: number;
  right: number;
  bottom: number;
  /** Degrees, around the rect centre (ArkUI Image.rotate on a square ornament). */
  rotation: number;
  /** Fit the bitmap inside the rect keeping its aspect ratio, centred (ArkUI ImageFit.Contain). */
  contain: boolean;

  constructor(pixelMap: image.PixelMap, left: number, top: number, right: number, bottom: number,
    rotation: number = 0, contain: boolean = false) {
    this.pixelMap = pixelMap;
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.rotation = rotation;
    this.contain = contain;
  }
}

/** One laid-out page drawn at an offset (the native node's position inside the surface, in pixels). */
export class ReaderRasterPage {
  layout: ReaderV2PageLayout;
  offsetX: number;
  offsetY: number;

  constructor(layout: ReaderV2PageLayout, offsetX: number, offsetY: number) {
    this.layout = layout;
    this.offsetX = offsetX;
    this.offsetY = offsetY;
  }
}

/** A page the host wants drawn: its layout, the controller role whose live node gives the exact position, and the layout-math offset (px) used before that node exists. */
export class ReaderRasterPageRequest {
  layout: ReaderV2PageLayout;
  role: string;
  fallbackOffsetX: number;

  constructor(layout: ReaderV2PageLayout, role: string, fallbackOffsetX: number) {
    this.layout = layout;
    this.role = role;
    this.fallbackOffsetX = fallbackOffsetX;
  }
}

/**
 * One line of header/footer text, drawn inside the rect its live Text node occupies (unscaled surface pixels) so the
 * turning sheet carries the same metadata row as the page on screen.
 */
export class ReaderRasterText {
  text: string;
  left: number;
  top: number;
  width: number;
  height: number;
  fontSizePx: number;
  color: string;
  /** 0–1, multiplied into the colour's alpha (the slot opacity of the live row). */
  opacity: number;
  fontFamilies: string[];

  constructor(text: string, left: number, top: number, width: number, height: number, fontSizePx: number,
    color: string, opacity: number, fontFamilies: string[]) {
    this.text = text;
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
    this.fontSizePx = fontSizePx;
    this.color = color;
    this.opacity = opacity;
    this.fontFamilies = fontFamilies;
  }
}

/** A rounded rectangle of the header/footer row (battery outline and level, progress bar, divider). */
export class ReaderRasterRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
  radius: number;
  color: string;
  opacity: number;
  /** > 0 strokes the outline with this width instead of filling. */
  strokeWidth: number;

  constructor(left: number, top: number, right: number, bottom: number, radius: number, color: string,
    opacity: number, strokeWidth: number = 0) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.radius = radius;
    this.color = color;
    this.opacity = opacity;
    this.strokeWidth = strokeWidth;
  }
}

export class ReaderPageRasterSpec {
  /** Unscaled surface size in pixels; the bitmap is this size times scale. */
  widthPx: number = 0;
  heightPx: number = 0;
  scale: number = 1;
  paperColor: string = '#FFFFFF';
  /** A custom theme background image already decoded at raster resolution, drawn exactly into its rect. */
  background: ReaderRasterImage | null = null;
  decorations: ReaderRasterImage[] = [];
  pages: ReaderRasterPage[] = [];
  images: ReaderRasterImage[] = [];
  caps: ReaderRasterImage[] = [];
  /** Header/footer row drawn last, above the page. */
  infoRects: ReaderRasterRect[] = [];
  infoTexts: ReaderRasterText[] = [];
}

/**
 * Draws the settled reader page into a PixelMap on the UI thread: paper, built-in decorations, the V2 page through
 * the shared painter, content illustrations and bubble cap ornaments. Replaces componentSnapshot for the simulation
 * turn textures, whose offscreen render and readback in RenderService stalled frames during rapid turns.
 */
export class ReaderPageRasterizer {
  static render(spec: ReaderPageRasterSpec): image.PixelMap | null {
    const width = Math.max(1, Math.round(spec.widthPx * spec.scale));
    const height = Math.max(1, Math.round(spec.heightPx * spec.scale));
    try {
      const options: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: true
      };
      const pixelMap = ReaderPageRasterizer.createTexturePixelMap(width, height, options);
      const canvas = new drawing.Canvas(pixelMap);
      // A DMA buffer is not zero-filled; a translucent paper colour would otherwise show stale pixels.
      canvas.clear({ alpha: 0, red: 0, green: 0, blue: 0 });
      canvas.scale(spec.scale, spec.scale);
      const paper = new drawing.Brush();
      paper.setColor(ReaderPageRasterizer.parseColor(spec.paperColor));
      canvas.attachBrush(paper);
      canvas.drawRect(0, 0, spec.widthPx, spec.heightPx);
      canvas.detachBrush();
      const sampling = new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
      if (spec.background) ReaderPageRasterizer.drawImage(canvas, spec.background, sampling);
      for (const decoration of spec.decorations) ReaderPageRasterizer.drawImage(canvas, decoration, sampling);
      for (const page of spec.pages) {
        canvas.save();
        canvas.translate(page.offsetX, page.offsetY);
        ReaderV2PagePainter.paint(canvas, page.layout);
        canvas.restore();
      }
      for (const picture of spec.images) ReaderPageRasterizer.drawImage(canvas, picture, sampling);
      for (const cap of spec.caps) ReaderPageRasterizer.drawImage(canvas, cap, sampling);
      for (const rect of spec.infoRects) ReaderPageRasterizer.drawRect(canvas, rect);
      for (const text of spec.infoTexts) ReaderPageRasterizer.drawText(canvas, text);
      return pixelMap;
    } catch (error) {
      console.warn('[ReaderRaster] page raster failed:', error);
      return null;
    }
  }

  /**
   * The curl Canvas hands every texture to RenderService. A heap PixelMap is copied into an RS GPU texture that
   * outlives PixelMap.release(): each turn left about five full-screen copies behind until RS killed the app at
   * 2 GB (RENDER_MEMORY_OVER_ERROR, "Gpu_rs Leak") within a few minutes of reading. A DMA PixelMap is shared
   * with RS by buffer, like the componentSnapshot results these rasters replaced, and is freed with the buffer.
   */
  private static createTexturePixelMap(width: number, height: number,
    options: image.InitializationOptions): image.PixelMap {
    try {
      const pixelMap = image.createPixelMapUsingAllocatorSync(options, image.AllocatorType.DMA);
      if (pixelMap) return pixelMap;
    } catch (error) {
      console.warn('[ReaderRaster] DMA texture unavailable, using heap memory:', error);
    }
    return image.createPixelMapSync(new ArrayBuffer(width * height * 4), options);
  }

  private static drawImage(canvas: drawing.Canvas, item: ReaderRasterImage, sampling: drawing.SamplingOptions): void {
    let left = item.left;
    let top = item.top;
    let right = item.right;
    let bottom = item.bottom;
    if (right <= left || bottom <= top) return;
    if (item.contain) {
      const info = item.pixelMap.getImageInfoSync();
      const sourceWidth = Math.max(1, info.size.width);
      const sourceHeight = Math.max(1, info.size.height);
      const fit = Math.min((right - left) / sourceWidth, (bottom - top) / sourceHeight);
      const fitWidth = sourceWidth * fit;
      const fitHeight = sourceHeight * fit;
      const centerX = (left + right) / 2;
      const centerY = (top + bottom) / 2;
      left = centerX - fitWidth / 2;
      right = centerX + fitWidth / 2;
      top = centerY - fitHeight / 2;
      bottom = centerY + fitHeight / 2;
    }
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    if (item.rotation) {
      canvas.save();
      canvas.rotate(item.rotation, (left + right) / 2, (top + bottom) / 2);
      canvas.drawImageRect(item.pixelMap, rect, sampling);
      canvas.restore();
      return;
    }
    canvas.drawImageRect(item.pixelMap, rect, sampling);
  }

  private static fadedColor(value: string, opacity: number): common2D.Color {
    const color = ReaderPageRasterizer.parseColor(value);
    color.alpha = Math.round(color.alpha * Math.max(0, Math.min(1, opacity)));
    return color;
  }

  private static drawRect(canvas: drawing.Canvas, item: ReaderRasterRect): void {
    if (item.right <= item.left || item.bottom <= item.top) return;
    const color = ReaderPageRasterizer.fadedColor(item.color, item.opacity);
    if (color.alpha <= 0) return;
    // ArkUI draws a border inside the node's box: inset the stroke by half its width.
    const inset = item.strokeWidth > 0 ? item.strokeWidth / 2 : 0;
    const rect: common2D.Rect = {
      left: item.left + inset, top: item.top + inset, right: item.right - inset, bottom: item.bottom - inset
    };
    const radius = Math.max(0, Math.min(item.radius - inset, (rect.right - rect.left) / 2, (rect.bottom - rect.top) / 2));
    const round = new drawing.RoundRect(rect, radius, radius);
    if (item.strokeWidth > 0) {
      const pen = new drawing.Pen();
      pen.setAntiAlias(true);
      pen.setColor(color);
      pen.setStrokeWidth(item.strokeWidth);
      canvas.attachPen(pen);
      canvas.drawRoundRect(round);
      canvas.detachPen();
      return;
    }
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(color);
    canvas.attachBrush(brush);
    canvas.drawRoundRect(round);
    canvas.detachBrush();
  }

  private static drawText(canvas: drawing.Canvas, item: ReaderRasterText): void {
    if (!item.text || item.width <= 0) return;
    const style: graphicsText.TextStyle = {
      color: ReaderPageRasterizer.fadedColor(item.color, item.opacity),
      fontSize: item.fontSizePx,
      fontFamilies: item.fontFamilies,
      ellipsis: '…',
      ellipsisMode: graphicsText.EllipsisMode.END
    };
    const builder = new graphicsText.ParagraphBuilder({ textStyle: style, maxLines: 1 },
      graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(item.text);
    builder.popStyle();
    const paragraph = builder.build();
    // The node is as wide as its laid-out line; a little slack keeps rounding from ellipsizing a line that fits.
    paragraph.layoutSync(item.width + 2);
    // The live Text uses a line box as tall as the font size with the glyphs centred in it.
    paragraph.paint(canvas, item.left, item.top + (item.height - paragraph.getHeight()) / 2);
  }

  /** '#RGB', '#RRGGBB', '#AARRGGBB', 'rgb(r,g,b)' and 'rgba(r,g,b,a)'; anything else is opaque white. */
  static parseColor(value: string): common2D.Color {
    const text = (value || '').trim();
    if (text.startsWith('#')) {
      let hex = text.substring(1);
      if (hex.length === 3) hex = `${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}`;
      if (hex.length === 6) hex = `FF${hex}`;
      if (hex.length === 8) {
        const parsed = Number.parseInt(hex, 16);
        if (Number.isFinite(parsed)) return ReaderV2PagePainter.brushColor(parsed);
      }
    }
    const match = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/i.exec(text);
    if (match) {
      const alpha = match[4] !== undefined ? Math.round(Math.max(0, Math.min(1, Number(match[4]))) * 255) : 255;
      return { alpha: alpha, red: Number(match[1]) & 0xFF, green: Number(match[2]) & 0xFF, blue: Number(match[3]) & 0xFF };
    }
    return { alpha: 255, red: 255, green: 255, blue: 255 };
  }
}
