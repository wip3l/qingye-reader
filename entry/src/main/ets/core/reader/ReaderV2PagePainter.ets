import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderFontStroke } from './ReaderFontStroke';
import { ReaderCommentBubblePainter } from './ReaderCommentBubble';
import {
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2RegexBubbleSegment
} from './ReaderV2PageLayout';

/**
 * Paints a laid-out V2 page: bubble backgrounds, selection/highlight boxes, glyphs and font strokes.
 * Shared by the retained page FrameNode and the self-drawn page raster used by the simulation turns, so both
 * produce the same pixels from the same Paragraph objects.
 */
export class ReaderV2PagePainter {
  static paint(canvas: drawing.Canvas, page: ReaderV2PageLayout, highlightStart: number = -1,
    highlightEnd: number = -1, highlightColor: number = 0, selectionStart: number = -1, selectionEnd: number = -1,
    selectionColor: number = 0): void {
    // Bubble decoration and glyphs must be submitted by the same retained node. The previous ArkUI overlay was
    // keyed independently from this FrameNode, so a forward/back turn could update the glyph page first while
    // leaving the old page's bubble rectangles mounted. Painting both layers here also removes dozens of
    // Row/Image nodes from simulation snapshots on dialogue-heavy chapters.
    for (const fragment of page.fragments) {
      for (const segment of fragment.regexBubbleSegments) {
        ReaderV2PagePainter.drawRegexBubble(canvas, segment);
      }
      for (const bubble of fragment.commentBubbleSegments) {
        canvas.save();
        canvas.translate(bubble.rect.left, bubble.rect.top);
        canvas.scale(bubble.scale, bubble.scale);
        ReaderCommentBubblePainter.paint(canvas, 0, 0, (bubble.rect.right - bubble.rect.left) / bubble.scale,
          (bubble.rect.bottom - bubble.rect.top) / bubble.scale, bubble.style, bubble.tail);
        canvas.restore();
      }
    }
    for (const fragment of page.fragments) {
      if (!fragment.paragraph) continue;
      canvas.save();
      canvas.clipRect({
        left: fragment.clipRect.left,
        top: fragment.clipRect.top,
        right: fragment.clipRect.right,
        bottom: fragment.clipRect.bottom
      }, drawing.ClipOp.INTERSECT, true);
      ReaderV2PagePainter.drawRange(canvas, fragment, selectionStart, selectionEnd, selectionColor);
      ReaderV2PagePainter.drawRange(canvas, fragment, highlightStart, highlightEnd, highlightColor);
      fragment.paragraph.paint(canvas, fragment.paragraphX, fragment.paragraphY);
      ReaderFontStroke.paint(canvas, fragment.fontStrokes, fragment.paragraphX, fragment.paragraphY);
      canvas.restore();
    }
  }

  // Brush.setColor(number) only exists from API 18; the colour-object overload works on every supported API.
  static brushColor(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }

  private static drawRegexBubble(canvas: drawing.Canvas, segment: ReaderV2RegexBubbleSegment): void {
    const left = segment.rect.left;
    const top = segment.rect.top;
    const right = segment.rect.right;
    const bottom = segment.rect.bottom;
    if (right <= left || bottom <= top) return;

    const brush = new drawing.Brush();
    brush.setColor(ReaderV2PagePainter.brushColor(segment.backgroundColor));
    if (segment.shadowEnabled && segment.shadowRadiusPx > 0) {
      try {
        brush.setShadowLayer(drawing.ShadowLayer.create(segment.shadowRadiusPx,
          segment.shadowOffsetXPx, segment.shadowOffsetYPx, segment.shadowColor));
      } catch (_) {
      }
    }
    const radius = Math.max(0, Math.min((right - left) / 2, (bottom - top) / 2,
      segment.radiusTopLeftPx, segment.radiusTopRightPx,
      segment.radiusBottomRightPx, segment.radiusBottomLeftPx));
    const roundRect = new drawing.RoundRect({ left: left, top: top, right: right, bottom: bottom }, radius, radius);
    roundRect.setCorner(drawing.CornerPos.TOP_LEFT_POS, segment.radiusTopLeftPx, segment.radiusTopLeftPx);
    roundRect.setCorner(drawing.CornerPos.TOP_RIGHT_POS, segment.radiusTopRightPx, segment.radiusTopRightPx);
    roundRect.setCorner(drawing.CornerPos.BOTTOM_RIGHT_POS,
      segment.radiusBottomRightPx, segment.radiusBottomRightPx);
    roundRect.setCorner(drawing.CornerPos.BOTTOM_LEFT_POS,
      segment.radiusBottomLeftPx, segment.radiusBottomLeftPx);
    canvas.attachBrush(brush);
    canvas.drawRoundRect(roundRect);
    canvas.detachBrush();
  }

  private static drawRange(canvas: drawing.Canvas, fragment: ReaderV2PageFragment,
    absoluteStart: number, absoluteEnd: number, color: number): void {
    if (!fragment.paragraph || absoluteStart < 0 || absoluteEnd <= absoluteStart ||
      absoluteEnd <= fragment.displayStart || absoluteStart >= fragment.displayEnd) return;
    const localStart = Math.max(0, absoluteStart - fragment.displayStart);
    const localEnd = Math.min(fragment.localEnd - fragment.localStart,
      absoluteEnd - fragment.displayStart);
    if (localEnd <= localStart) return;
    const boxes = fragment.paragraph.getRectsForRange({ start: localStart, end: localEnd },
      // MAX follows the full logical line box. With CJK font padding enabled that box contains
      // noticeably more descent space, making the yellow focus appear shifted downward from the glyphs.
      // Use the ink-tight vertical bounds so the focus remains visually centred on the spoken text.
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    const brush = new drawing.Brush();
    brush.setColor(ReaderV2PagePainter.brushColor(color));
    canvas.attachBrush(brush);
    for (const box of boxes) {
      const left = Math.max(fragment.clipRect.left, fragment.paragraphX + box.rect.left);
      const top = Math.max(fragment.clipRect.top, fragment.paragraphY + box.rect.top);
      const right = Math.min(fragment.clipRect.right, fragment.paragraphX + box.rect.right);
      const bottom = Math.min(fragment.clipRect.bottom, fragment.paragraphY + box.rect.bottom);
      if (right > left && bottom > top) canvas.drawRect(left, top, right, bottom);
    }
    canvas.detachBrush();
  }
}
