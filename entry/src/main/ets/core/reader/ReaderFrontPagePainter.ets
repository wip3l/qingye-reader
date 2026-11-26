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
    const base = (0xFF000000 | (decoration.color & 0x00FFFFFF)) >>> 0;

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
    if (!drawn) ReaderFrontPagePainter.initialCover(canvas, rect, base);
    // 书脊折痕与左上角的纸面反光。
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, rect.top, rect.left + width * 0.1, rect.bottom,
      { x: rect.left, y: rect.top }, { x: rect.left + width * 0.1, y: rect.top },
      [0x47000000, 0x2EFFFFFF, 0x14000000, 0x00000000], [0, 0.22, 0.45, 1]);
    ReaderFrontPagePainter.gradientRect(canvas, rect.left, rect.top, rect.right, rect.bottom,
      { x: rect.left, y: rect.top }, { x: rect.left + width * 0.55, y: rect.top + height * 0.38 },
      [0x24FFFFFF, 0x00FFFFFF], [0, 1]);
    // 主题书框和书架一样不论封面来源都套，拉伸铺满。
    ReaderFrontPagePainter.frameImage(canvas, decoration.frame, rect);
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

  /** 章末卡片的底板：淡强调色圆角块加一圈细描边。 */
  static paintPanel(canvas: drawing.Canvas, decoration: ReaderV2PageDecoration): void {
    const rect = decoration.rect;
    if (rect.right - rect.left <= 1 || rect.bottom - rect.top <= 1) return;
    const radius = Math.max(0, Math.min(decoration.radius, (rect.bottom - rect.top) / 2));
    const shape = new drawing.RoundRect({ left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
      radius, radius);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderFrontPagePainter.argb(decoration.color));
    canvas.attachBrush(brush);
    canvas.drawRoundRect(shape);
    canvas.detachBrush();
    if (((decoration.strokeColor >>> 24) & 0xFF) === 0) return;
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setStrokeWidth(1);
    pen.setColor(ReaderFrontPagePainter.argb(decoration.strokeColor));
    canvas.attachPen(pen);
    canvas.drawRoundRect(new drawing.RoundRect({ left: rect.left + 0.5, top: rect.top + 0.5, right: rect.right - 0.5,
      bottom: rect.bottom - 0.5 }, Math.max(0, radius - 0.5), Math.max(0, radius - 0.5)));
    canvas.detachPen();
  }

  /** 章末卡片里的细分隔线：按 rect 填色。 */
  static paintLine(canvas: drawing.Canvas, decoration: ReaderV2PageDecoration): void {
    const rect = decoration.rect;
    if (rect.right - rect.left <= 0 || rect.bottom - rect.top <= 0) return;
    const brush = new drawing.Brush();
    brush.setColor(ReaderFrontPagePainter.argb(decoration.color));
    canvas.attachBrush(brush);
    canvas.drawRect(rect.left, rect.top, rect.right, rect.bottom);
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

  /** 没有封面图时的底：和书架首字色块一样的纯色（首字由 KIND_COVER_TEXT 画）。 */
  private static initialCover(canvas: drawing.Canvas, rect: ReaderV2Rect, base: number): void {
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderFrontPagePainter.argb(base));
    canvas.attachBrush(brush);
    canvas.drawRect(rect.left, rect.top, rect.right, rect.bottom);
    canvas.detachBrush();
  }

  private static frameImage(canvas: drawing.Canvas, path: string, rect: ReaderV2Rect): void {
    if (!path) return;
    const width = Math.max(1, Math.round(rect.right - rect.left));
    const height = Math.max(1, Math.round(rect.bottom - rect.top));
    const bitmap = ReaderRasterAssets.fileImage(path, width, height);
    if (!bitmap) return;
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    canvas.attachBrush(brush);
    canvas.drawImageRect(bitmap, { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
      new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR));
    canvas.detachBrush();
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

  private static argb(value: number): common2D.Color {
    const color = value >>> 0;
    return { alpha: (color >>> 24) & 0xFF, red: (color >>> 16) & 0xFF, green: (color >>> 8) & 0xFF, blue: color & 0xFF };
  }

  static isFrontKind(kind: string): boolean {
    return kind === ReaderFrontPage.KIND_COVER || kind === ReaderFrontPage.KIND_COVER_TEXT ||
      kind === ReaderFrontPage.KIND_RULE || kind === ReaderFrontPage.KIND_CHIP;
  }
}
