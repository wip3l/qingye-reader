import image from '@ohos.multimedia.image';
import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
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
      const pixelMap = image.createPixelMapSync(new ArrayBuffer(width * height * 4), options);
      const canvas = new drawing.Canvas(pixelMap);
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
      return pixelMap;
    } catch (error) {
      console.warn('[ReaderRaster] page raster failed:', error);
      return null;
    }
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
