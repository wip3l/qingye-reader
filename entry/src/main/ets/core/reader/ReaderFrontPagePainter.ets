import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import { ReaderRasterAssets } from './ReaderRasterAssets';
import { ReaderV2PageDecoration } from './ReaderV2PageLayout';
import { ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderFrontPage } from './ReaderFrontPage';

/** 书封扉页里几种特殊装饰的画法（见 ReaderFrontPage）。常驻页与翻页纹理共用。 */
export class ReaderFrontPagePainter {
  /** 画书封；返回封面图是否画出来了（没画出来时由调用方补画书封文字）。 */
  static paintCover(canvas: drawing.Canvas, decoration: ReaderV2PageDecoration): boolean {
    const rect = decoration.rect;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 1 || height <= 1) return false;
    const spineRadius = Math.max(1, width * 0.02);
    const edgeRadius = Math.max(2, width * 0.04);
    const shape = ReaderFrontPagePainter.bookShape(rect, spineRadius, edgeRadius);
    const base = ReaderFrontPagePainter.coverBase(decoration.color);

    // 落地投影：一层大而淡的环境阴影，一层贴边的接触阴影。投影画在实心底色上，图片随后盖住底色。
    const ambient = new drawing.Brush();
    ambient.setAntiAlias(true);
    ambient.setColor(ReaderFrontPagePainter.argb(base));
    ReaderFrontPagePainter.shadow(ambient, width * 0.13, height * 0.045, decoration.shadowDark ? 0xB3000000 : 0x5A221E18);
    canvas.attachBrush(ambient);
    canvas.drawRoundRect(shape);
    canvas.detachBrush();
    const contact = new drawing.Brush();
    contact.setAntiAlias(true);
    contact.setColor(ReaderFrontPagePainter.argb(base));
    ReaderFrontPagePainter.shadow(contact, Math.max(1, width * 0.02), Math.max(0.5, width * 0.006),
      decoration.shadowDark ? 0x99000000 : 0x38221E18);
    canvas.attachBrush(contact);
    canvas.drawRoundRect(shape);
    canvas.detachBrush();

    canvas.save();
    const clip = new drawing.Path();
    clip.addRoundRect(shape);
    canvas.clipPath(clip, drawing.ClipOp.INTERSECT, true);
    const drawn = ReaderFrontPagePainter.coverImage(canvas, decoration.image, rect);
    if (!drawn) ReaderFrontPagePainter.generatedCover(canvas, rect, base);
    // 书脊折痕与左上角的纸面反光。
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, rect.top, rect.left + width * 0.1, rect.bottom,
      { x: rect.left, y: rect.top }, { x: rect.left + width * 0.1, y: rect.top },
      [0x47000000, 0x2EFFFFFF, 0x14000000, 0x00000000], [0, 0.22, 0.45, 1]);
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, rect.top, rect.right, rect.bottom,
      { x: rect.left, y: rect.top }, { x: rect.left + width * 0.55, y: rect.top + height * 0.38 },
      [0x24FFFFFF, 0x00FFFFFF], [0, 1]);
    canvas.restore();
    return drawn;
  }

  /** 墨线菱形：两头淡出的细线，中间一枚小菱形。 */
  static paintRule(canvas: drawing.Canvas, decoration: ReaderV2PageDecoration): void {
    const rect = decoration.rect;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 1 || height <= 0.5) return;
    const centerY = rect.top + height / 2;
    const color = decoration.color >>> 0;
    const line = Math.max(1, height * 0.12);
    const solid = ((Math.round(((color >>> 24) & 0xFF) * 0.7) << 24) | (color & 0x00FFFFFF)) >>> 0;
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, centerY - line / 2, rect.right, centerY + line / 2,
      { x: rect.left, y: centerY }, { x: rect.right, y: centerY },
      [color & 0x00FFFFFF, solid, solid, color & 0x00FFFFFF], [0, 0.3, 0.7, 1]);
    const half = height * 0.5;
    const centerX = rect.left + width / 2;
    const diamond = new drawing.Path();
    diamond.moveTo(centerX, centerY - half);
    diamond.lineTo(centerX + half, centerY);
    diamond.lineTo(centerX, centerY + half);
    diamond.lineTo(centerX - half, centerY);
    diamond.close();
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderFrontPagePainter.argb(color));
    canvas.attachBrush(brush);
    canvas.drawPath(diamond);
    canvas.detachBrush();
  }

  /** 标签的圆角底色；文字由调用方按 glyph 画。 */
  static paintChip(canvas: drawing.Canvas, decoration: ReaderV2PageDecoration): void {
    const rect = decoration.rect;
    const height = rect.bottom - rect.top;
    if (rect.right - rect.left <= 1 || height <= 1) return;
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderFrontPagePainter.argb(decoration.color));
    canvas.attachBrush(brush);
    canvas.drawRoundRect(new drawing.RoundRect({ left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
      height / 2, height / 2));
    canvas.detachBrush();
  }

  /** 封面图按原比例放大到铺满书形，居中裁掉多出的部分。 */
  private static coverImage(canvas: drawing.Canvas, path: string, rect: ReaderV2Rect): boolean {
    if (!path) return false;
    const size = ReaderRasterAssets.fileImageSize(path);
    if (!size) return false;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    const scale = Math.max(width / size.width, height / size.height);
    const decodeWidth = Math.max(1, Math.round(size.width * scale));
    const decodeHeight = Math.max(1, Math.round(size.height * scale));
    const bitmap = ReaderRasterAssets.fileImage(path, decodeWidth, decodeHeight);
    if (!bitmap) return false;
    const sourceLeft = Math.max(0, (decodeWidth - width) / 2);
    const sourceTop = Math.max(0, (decodeHeight - height) / 2);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    canvas.attachBrush(brush);
    canvas.drawImageRectWithSrc(bitmap,
      { left: sourceLeft, top: sourceTop, right: Math.min(decodeWidth, sourceLeft + width),
        bottom: Math.min(decodeHeight, sourceTop + height) },
      { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
      new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR), drawing.SrcRectConstraint.STRICT);
    canvas.detachBrush();
    return true;
  }

  /** 文字封面的底：强调色压暗的斜向渐变，加一圈内框线。 */
  private static generatedCover(canvas: drawing.Canvas, rect: ReaderV2Rect, base: number): void {
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, rect.top, rect.right, rect.bottom,
      { x: rect.left, y: rect.top }, { x: rect.right, y: rect.bottom },
      [ReaderFrontPagePainter.shade(base, 1.18), base, ReaderFrontPagePainter.shade(base, 0.74)], [0, 0.55, 1]);
    const inset = Math.min(width, height) * 0.07;
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setStrokeWidth(Math.max(1, width * 0.006));
    pen.setColor(ReaderFrontPagePainter.argb(0x59F1ECE2));
    canvas.attachPen(pen);
    canvas.drawRect(rect.left + inset, rect.top + inset, rect.right - inset, rect.bottom - inset);
    canvas.detachPen();
  }

  private static bookShape(rect: ReaderV2Rect, spineRadius: number, edgeRadius: number): drawing.RoundRect {
    const shape = new drawing.RoundRect({ left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
      edgeRadius, edgeRadius);
    shape.setCorner(drawing.CornerPos.TOP_LEFT_POS, spineRadius, spineRadius);
    shape.setCorner(drawing.CornerPos.BOTTOM_LEFT_POS, spineRadius, spineRadius);
    return shape;
  }

  private static gradientRect(canvas: drawing.Canvas, left: number, top: number, right: number, bottom: number,
    start: common2D.Point, end: common2D.Point, colors: number[], positions: number[]): void {
    if (right - left <= 0 || bottom - top <= 0) return;
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setShaderEffect(drawing.ShaderEffect.createLinearGradient(start, end,
      colors.map((value: number): number => value >>> 0), drawing.TileMode.CLAMP, positions));
    canvas.attachBrush(brush);
    canvas.drawRect(left, top, right, bottom);
    canvas.detachBrush();
  }

  private static shadow(brush: drawing.Brush, blur: number, offsetY: number, color: number): void {
    try {
      brush.setShadowLayer(drawing.ShadowLayer.create(blur, 0, offsetY, color >>> 0));
    } catch (_) {
    }
  }

  /** 文字封面的底色：强调色压到偏深的书皮色，浅色强调色也能托住白字。 */
  private static coverBase(accent: number): number {
    const value = accent >>> 0;
    const mix = (channel: number): number => Math.round(channel * 0.62 + 0x14 * 0.38);
    return (0xFF000000 | (mix((value >>> 16) & 0xFF) << 16) | (mix((value >>> 8) & 0xFF) << 8) |
      mix(value & 0xFF)) >>> 0;
  }

  private static shade(color: number, factor: number): number {
    const value = color >>> 0;
    const channel = (shift: number): number => Math.max(0, Math.min(255, Math.round(((value >>> shift) & 0xFF) * factor)));
    return (0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0)) >>> 0;
  }

  private static argb(value: number): common2D.Color {
    const color = value >>> 0;
    return { alpha: (color >>> 24) & 0xFF, red: (color >>> 16) & 0xFF, green: (color >>> 8) & 0xFF, blue: color & 0xFF };
  }

  static isFrontKind(kind: string): boolean {
    return kind === ReaderFrontPage.KIND_COVER || kind === ReaderFrontPage.KIND_COVER_TEXT ||
      kind === ReaderFrontPage.KIND_RULE || kind === ReaderFrontPage.KIND_CHIP;
  }
}
