import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderV2AnnotationMark, ReaderV2PageFragment, ReaderV2PageLayout } from './ReaderV2PageLayout';

/**
 * 正文划线的绘制与点按判定。坐标都是页内像素，与 ReaderV2PagePainter 相同；常驻页节点和仿真翻页的自绘纹理
 * 都经 ReaderV2PagePainter 调到这里，所以划线在各种翻页、双页和滚动模式里都一样。
 * 划线、笔记标记都不参与排版：画在字形下方的空白里，加划线不会重新分页。
 */
export class ReaderV2AnnotationPainter {
  /** 背景色：画在字形之下，调用方已按片段裁剪。 */
  static paintBackgrounds(canvas: drawing.Canvas, fragment: ReaderV2PageFragment,
    marks: ReaderV2AnnotationMark[]): void {
    for (const mark of marks) {
      if (mark.style !== 'bg') continue;
      const boxes = ReaderV2AnnotationPainter.boxes(fragment, mark.displayStart, mark.displayEnd,
        graphicsText.RectHeightStyle.TIGHT);
      if (boxes.length === 0) continue;
      const brush = new drawing.Brush();
      brush.setAntiAlias(true);
      brush.setColor(ReaderV2AnnotationPainter.color(((0x52 << 24) | (mark.color & 0x00FFFFFF)) >>> 0));
      canvas.attachBrush(brush);
      for (const box of boxes) {
        const pad = Math.max(1, Math.min(4, box.height() * 0.1));
        const radius = Math.min(4, box.height() * 0.15);
        canvas.drawRoundRect(new drawing.RoundRect({
          left: box.left, top: box.top - pad, right: box.right, bottom: box.bottom + pad
        }, radius, radius));
      }
      canvas.detachBrush();
    }
  }

  /** 字体色：把这段字形在离屏图层里重画一遍再整体染色，盖在原字形上。调用方已按片段裁剪。 */
  static paintTextColors(canvas: drawing.Canvas, fragment: ReaderV2PageFragment,
    marks: ReaderV2AnnotationMark[]): void {
    if (!fragment.paragraph) return;
    for (const mark of marks) {
      if (mark.style !== 'text') continue;
      const boxes = ReaderV2AnnotationPainter.boxes(fragment, mark.displayStart, mark.displayEnd,
        graphicsText.RectHeightStyle.MAX);
      for (const box of boxes) {
        const rect: common2D.Rect = { left: box.left, top: box.top, right: box.right, bottom: box.bottom };
        canvas.save();
        canvas.clipRect(rect, drawing.ClipOp.INTERSECT, true);
        canvas.saveLayer(rect, null);
        fragment.paragraph.paint(canvas, fragment.paragraphX, fragment.paragraphY);
        const brush = new drawing.Brush();
        brush.setColor(ReaderV2AnnotationPainter.color(mark.color));
        brush.setBlendMode(drawing.BlendMode.SRC_IN);
        canvas.attachBrush(brush);
        canvas.drawRect(rect);
        canvas.detachBrush();
        canvas.restore();
        canvas.restore();
      }
    }
  }

  /** 线和笔记标记：在全部字形画完、片段裁剪撤掉之后画，线可以落在行与行之间的空白里。 */
  static paintLines(canvas: drawing.Canvas, page: ReaderV2PageLayout): void {
    if (page.annotationMarks.length === 0) return;
    for (const mark of page.annotationMarks) {
      if (mark.style !== 'solid' && mark.style !== 'wavy' && mark.style !== 'dashed') continue;
      for (const fragment of page.fragments) {
        const boxes = ReaderV2AnnotationPainter.boxes(fragment, mark.displayStart, mark.displayEnd,
          graphicsText.RectHeightStyle.TIGHT);
        for (const box of boxes) ReaderV2AnnotationPainter.drawLine(canvas, mark, box);
      }
    }
    for (const mark of page.annotationMarks) {
      if (!mark.noteDot) continue;
      const end = ReaderV2AnnotationPainter.endBox(page, mark);
      if (!end) continue;
      ReaderV2AnnotationPainter.drawNoteDot(canvas, mark, end);
    }
  }

  /** 点按落在哪条划线上；笔记标记优先。坐标为页内像素。 */
  static hitTest(page: ReaderV2PageLayout, x: number, y: number, slop: number): number {
    for (let index = page.annotationMarks.length - 1; index >= 0; index--) {
      const mark = page.annotationMarks[index];
      if (!mark.noteDot) continue;
      const end = ReaderV2AnnotationPainter.endBox(page, mark);
      if (!end) continue;
      const center = ReaderV2AnnotationPainter.noteDotCenter(mark, end);
      const radius = ReaderV2AnnotationPainter.noteDotRadius(end) + slop;
      const dx = x - center[0];
      const dy = y - center[1];
      if (dx * dx + dy * dy <= radius * radius) return mark.id;
    }
    for (let index = page.annotationMarks.length - 1; index >= 0; index--) {
      const mark = page.annotationMarks[index];
      for (const box of ReaderV2AnnotationPainter.rects(page, mark.id)) {
        if (box.contains(x, y, slop * 0.25, slop * 0.5)) return mark.id;
      }
    }
    return 0;
  }

  /** 一条划线在本页的各行框（行高框，页内像素），用于点按与弹层定位。 */
  static rects(page: ReaderV2PageLayout, id: number): ReaderV2Rect[] {
    const result: ReaderV2Rect[] = [];
    for (const mark of page.annotationMarks) {
      if (mark.id !== id) continue;
      for (const fragment of page.fragments) {
        const boxes = ReaderV2AnnotationPainter.boxes(fragment, mark.displayStart, mark.displayEnd,
          graphicsText.RectHeightStyle.MAX);
        for (const box of boxes) result.push(box);
      }
    }
    return result;
  }

  private static boxes(fragment: ReaderV2PageFragment, absoluteStart: number, absoluteEnd: number,
    heightStyle: graphicsText.RectHeightStyle): ReaderV2Rect[] {
    const result: ReaderV2Rect[] = [];
    if (!fragment.paragraph || absoluteEnd <= absoluteStart || absoluteEnd <= fragment.displayStart ||
      absoluteStart >= fragment.displayEnd) return result;
    const localStart = Math.max(0, absoluteStart - fragment.displayStart);
    const localEnd = Math.min(fragment.localEnd - fragment.localStart, absoluteEnd - fragment.displayStart);
    if (localEnd <= localStart) return result;
    const boxes = fragment.paragraph.getRectsForRange({ start: localStart, end: localEnd },
      graphicsText.RectWidthStyle.TIGHT, heightStyle);
    for (const box of boxes) {
      const left = Math.max(fragment.clipRect.left, fragment.paragraphX + box.rect.left);
      const right = Math.min(fragment.clipRect.right, fragment.paragraphX + box.rect.right);
      const top = fragment.paragraphY + box.rect.top;
      const bottom = fragment.paragraphY + box.rect.bottom;
      // 跨页段落的片段只显示裁剪区内的行，区外的行不属于本页。
      if (right <= left || bottom <= top || bottom <= fragment.clipRect.top || top >= fragment.clipRect.bottom) continue;
      result.push(new ReaderV2Rect(left, top, right, bottom));
    }
    return result;
  }

  private static endBox(page: ReaderV2PageLayout, mark: ReaderV2AnnotationMark): ReaderV2Rect | null {
    for (let index = page.fragments.length - 1; index >= 0; index--) {
      const fragment = page.fragments[index];
      if (!fragment.paragraph || mark.displayEnd <= fragment.displayStart || mark.displayEnd > fragment.displayEnd) {
        continue;
      }
      const boxes = ReaderV2AnnotationPainter.boxes(fragment, mark.displayStart, mark.displayEnd,
        graphicsText.RectHeightStyle.TIGHT);
      return boxes.length > 0 ? boxes[boxes.length - 1] : null;
    }
    return null;
  }

  private static lineY(box: ReaderV2Rect): number {
    return box.bottom + Math.max(1.5, box.height() * 0.1);
  }

  private static lineWidth(box: ReaderV2Rect): number {
    return Math.max(1.2, box.height() * 0.055);
  }

  private static drawLine(canvas: drawing.Canvas, mark: ReaderV2AnnotationMark, box: ReaderV2Rect): void {
    const y = ReaderV2AnnotationPainter.lineY(box);
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setColor(ReaderV2AnnotationPainter.color(mark.color));
    pen.setStrokeWidth(ReaderV2AnnotationPainter.lineWidth(box));
    pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    if (mark.style === 'dashed') {
      const dash = Math.max(3, box.height() * 0.22);
      pen.setPathEffect(drawing.PathEffect.createDashPathEffect([dash, dash * 0.7], 0));
    }
    canvas.attachPen(pen);
    if (mark.style === 'wavy') {
      const amplitude = Math.max(1, box.height() * 0.055);
      const half = Math.max(2, box.height() * 0.16);
      const path = new drawing.Path();
      path.moveTo(box.left, y);
      let x = box.left;
      let up = true;
      while (x < box.right) {
        const next = Math.min(box.right, x + half);
        path.quadTo((x + next) / 2, y + (up ? -amplitude * 2 : amplitude * 2), next, y);
        x = next;
        up = !up;
      }
      canvas.drawPath(path);
    } else {
      canvas.drawLine(box.left, y, box.right, y);
    }
    canvas.detachPen();
  }

  private static noteDotRadius(box: ReaderV2Rect): number {
    return Math.max(6, box.height() * 0.3);
  }

  private static noteDotCenter(mark: ReaderV2AnnotationMark, box: ReaderV2Rect): number[] {
    const underline = mark.style === 'solid' || mark.style === 'wavy' || mark.style === 'dashed';
    return [box.right, underline ? ReaderV2AnnotationPainter.lineY(box) : box.bottom];
  }

  private static drawNoteDot(canvas: drawing.Canvas, mark: ReaderV2AnnotationMark, box: ReaderV2Rect): void {
    const center = ReaderV2AnnotationPainter.noteDotCenter(mark, box);
    const radius = ReaderV2AnnotationPainter.noteDotRadius(box);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderV2AnnotationPainter.color(mark.color));
    canvas.attachBrush(brush);
    canvas.drawCircle(center[0], center[1], radius);
    canvas.detachBrush();
    const dots = new drawing.Brush();
    dots.setAntiAlias(true);
    dots.setColor(ReaderV2AnnotationPainter.color(0xFFFFFFFF));
    canvas.attachBrush(dots);
    const step = radius * 0.42;
    const dotRadius = Math.max(0.8, radius * 0.13);
    for (let index = -1; index <= 1; index++) {
      canvas.drawCircle(center[0] + index * step, center[1], dotRadius);
    }
    canvas.detachBrush();
  }

  // Brush/Pen.setColor(number) only exists from API 18; the colour-object overload works on every supported API.
  private static color(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }
}
