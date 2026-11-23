import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderTextRulingSpec } from './ReaderTextRuling';
import { ReaderV2PageFragment, ReaderV2PageLayout, ReaderV2SelectionRun } from './ReaderV2PageLayout';

/** 一行里要画的一段线。 */
class ReaderRulingSegment {
  left: number = 0;
  right: number = 0;
  y: number = 0;
  /** 这行字形的高度，虚线间隔、波浪幅度按它缩放。 */
  glyphHeight: number = 0;
}

/**
 * 正文文字划线（信纸格线）。由 ReaderV2PagePainter 在气泡底色之后、字形之前调用，常驻页、仿真/3D 自绘纹理、
 * 滚动模式与双页都走这里，所以各处一致。坐标为页内像素。
 * - 整行：从正文起点（首字装饰环绕的行从装饰右侧）画到版心右边，段末短行也画满；
 * - 仅文字：每行首尾去掉空白后，从第一个字画到最后一个字；
 * - 仅正则字体：只画 fragment.regexRanges 落在该行的部分。
 * 标题、插图、段评卡片不画；线不参与排版。
 */
export class ReaderV2RulingPainter {
  static paint(canvas: drawing.Canvas, page: ReaderV2PageLayout): void {
    const spec = page.ruling;
    if (!spec) return;
    const segments: ReaderRulingSegment[] = [];
    for (const fragment of page.fragments) {
      ReaderV2RulingPainter.collect(fragment, page, spec, segments);
    }
    if (segments.length === 0) return;
    ReaderV2RulingPainter.draw(canvas, spec, segments);
  }

  private static collect(fragment: ReaderV2PageFragment, page: ReaderV2PageLayout, spec: ReaderTextRulingSpec,
    out: ReaderRulingSegment[]): void {
    const paragraph = fragment.paragraph;
    if (!paragraph || fragment.title || fragment.card) return;
    const regexOnly = spec.target === 'regex';
    if (regexOnly && fragment.regexRanges.length === 0) return;
    const length = fragment.localEnd - fragment.localStart;
    if (length <= 0) return;
    const text = fragment.selectionRuns.map((run: ReaderV2SelectionRun): string => run.text).join('');
    const lines: graphicsText.LineMetrics[] = paragraph.getLineMetrics();
    for (const line of lines) {
      const boxTop = fragment.paragraphY + line.topHeight;
      const boxBottom = boxTop + line.height;
      // 跨页段落只画裁剪区里的行；只蹭进来一点出血的行不属于本页。
      const inside = Math.min(boxBottom, fragment.clipRect.bottom) - Math.max(boxTop, fragment.clipRect.top);
      if (line.height <= 0 || inside < line.height * 0.4) continue;
      let start = Math.max(0, line.startIndex);
      let end = Math.min(length, line.endIndex);
      while (start < end && ReaderV2RulingPainter.isBlank(text, start)) start++;
      while (end > start && ReaderV2RulingPainter.isBlank(text, end - 1)) end--;
      if (end <= start) continue;
      const glyph = ReaderV2RulingPainter.span(fragment, start, end);
      if (!glyph) continue;
      const y = ReaderV2RulingPainter.lineY(spec, glyph, boxTop, boxBottom);
      const height = glyph.bottom - glyph.top;
      if (regexOnly) {
        for (let index = 0; index + 1 < fragment.regexRanges.length; index += 2) {
          const hitStart = Math.max(start, fragment.regexRanges[index] - fragment.displayStart);
          const hitEnd = Math.min(end, fragment.regexRanges[index + 1] - fragment.displayStart);
          if (hitEnd <= hitStart) continue;
          const hit = ReaderV2RulingPainter.span(fragment, hitStart, hitEnd);
          if (hit) ReaderV2RulingPainter.push(out, hit.left, hit.right, y, height);
        }
      } else if (spec.scope === 'row') {
        ReaderV2RulingPainter.push(out, Math.max(page.contentRect.left, fragment.paragraphX), page.contentRect.right,
          y, height);
      } else {
        ReaderV2RulingPainter.push(out, glyph.left, glyph.right, y, height);
      }
    }
  }

  /** 一段文字的字形外框（页内像素），多个字形框取并集。 */
  private static span(fragment: ReaderV2PageFragment, start: number, end: number): common2D.Rect | null {
    if (!fragment.paragraph) return null;
    const boxes = fragment.paragraph.getRectsForRange({ start: start, end: end },
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    let left = Number.POSITIVE_INFINITY;
    let right = Number.NEGATIVE_INFINITY;
    let top = Number.POSITIVE_INFINITY;
    let bottom = Number.NEGATIVE_INFINITY;
    for (const box of boxes) {
      if (box.rect.right <= box.rect.left) continue;
      left = Math.min(left, box.rect.left);
      right = Math.max(right, box.rect.right);
      top = Math.min(top, box.rect.top);
      bottom = Math.max(bottom, box.rect.bottom);
    }
    if (!(right > left) || !(bottom > top)) return null;
    return {
      left: Math.max(fragment.clipRect.left, fragment.paragraphX + left),
      right: Math.min(fragment.clipRect.right, fragment.paragraphX + right),
      top: fragment.paragraphY + top,
      bottom: fragment.paragraphY + bottom
    };
  }

  /**
   * 贴近文字：字形下沿再往下一点（与划线笔记的线同一位置）。
   * 行间居中：字形上下各自留的空白合起来取一半，正好落在本行字与下一行字中间；段距不算在内。
   */
  private static lineY(spec: ReaderTextRulingSpec, glyph: common2D.Rect, boxTop: number, boxBottom: number): number {
    const height = glyph.bottom - glyph.top;
    if (spec.position === 'near') {
      return glyph.bottom + Math.max(1.5, height * 0.1) + spec.widthPx / 2;
    }
    const above = Math.max(0, glyph.top - boxTop);
    const below = Math.max(0, boxBottom - glyph.bottom);
    return glyph.bottom + Math.max((above + below) / 2, Math.max(1.5, height * 0.1) + spec.widthPx / 2);
  }

  private static push(out: ReaderRulingSegment[], left: number, right: number, y: number, glyphHeight: number): void {
    if (right - left < 1) return;
    const segment = new ReaderRulingSegment();
    segment.left = left;
    segment.right = right;
    segment.y = y;
    segment.glyphHeight = glyphHeight;
    out.push(segment);
  }

  private static isBlank(text: string, index: number): boolean {
    if (index < 0 || index >= text.length) return false;
    const code = text.charCodeAt(index);
    return code === 0x20 || code === 0x3000 || code === 0x09 || code === 0x0A || code === 0x0D || code === 0xA0;
  }

  private static draw(canvas: drawing.Canvas, spec: ReaderTextRulingSpec, segments: ReaderRulingSegment[]): void {
    const color = ReaderV2RulingPainter.color(spec.color);
    if (spec.style === 'dotted') {
      const brush = new drawing.Brush();
      brush.setAntiAlias(true);
      brush.setColor(color);
      canvas.attachBrush(brush);
      for (const segment of segments) {
        const radius = Math.max(0.6, spec.widthPx * 0.75);
        const step = Math.max(spec.widthPx * 3.2, segment.glyphHeight * 0.22);
        for (let x = segment.left + radius; x <= segment.right - radius + 0.01; x += step) {
          canvas.drawCircle(x, segment.y, radius);
        }
      }
      canvas.detachBrush();
      return;
    }
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setColor(color);
    pen.setStrokeWidth(spec.style === 'double' ? Math.max(0.5, spec.widthPx * 0.8) : spec.widthPx);
    pen.setCapStyle(spec.style === 'wavy' ? drawing.CapStyle.ROUND_CAP : drawing.CapStyle.FLAT_CAP);
    pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    for (const segment of segments) {
      if (spec.style === 'dashed') {
        const dash = Math.max(spec.widthPx * 3, segment.glyphHeight * 0.3);
        pen.setPathEffect(drawing.PathEffect.createDashPathEffect([dash, dash * 0.6], 0));
      }
      canvas.attachPen(pen);
      if (spec.style === 'wavy') {
        const amplitude = Math.max(spec.widthPx, segment.glyphHeight * 0.06);
        const half = Math.max(spec.widthPx * 2.5, segment.glyphHeight * 0.18);
        const path = new drawing.Path();
        path.moveTo(segment.left, segment.y);
        let x = segment.left;
        let up = true;
        while (x < segment.right) {
          const next = Math.min(segment.right, x + half);
          path.quadTo((x + next) / 2, segment.y + (up ? -amplitude * 2 : amplitude * 2), next, segment.y);
          x = next;
          up = !up;
        }
        canvas.drawPath(path);
      } else if (spec.style === 'double') {
        const gap = Math.max(spec.widthPx * 1.2, segment.glyphHeight * 0.05);
        canvas.drawLine(segment.left, segment.y - gap, segment.right, segment.y - gap);
        canvas.drawLine(segment.left, segment.y + gap, segment.right, segment.y + gap);
      } else {
        canvas.drawLine(segment.left, segment.y, segment.right, segment.y);
      }
      canvas.detachPen();
    }
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
