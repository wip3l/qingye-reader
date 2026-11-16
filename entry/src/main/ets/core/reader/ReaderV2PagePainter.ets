import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderFontStroke } from './ReaderFontStroke';
import { ReaderCommentBubblePainter } from './ReaderCommentBubble';
import { ReaderV2AnnotationPainter } from './ReaderV2AnnotationPainter';
import { ReaderV2CommentCardPainter } from './ReaderV2CommentCard';
import { ReaderV2RulingPainter } from './ReaderV2RulingPainter';
import { ReaderRasterAssets } from './ReaderRasterAssets';
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
    ReaderV2PagePainter.drawDecorations(canvas, page);
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
      if (fragment.card) ReaderV2CommentCardPainter.paint(canvas, fragment.card, fragment.paragraphX, fragment.paragraphY);
    }
    // 文字划线在气泡底色之上、字形之下；划线笔记的线最后画，盖在它上面。
    if (page.ruling) ReaderV2RulingPainter.paint(canvas, page);
    const hasAnnotations = page.annotationMarks.length > 0;
    for (const fragment of page.fragments) {
      if (!fragment.paragraph) continue;
      canvas.save();
      canvas.clipRect({
        left: fragment.clipRect.left,
        top: fragment.clipRect.top,
        right: fragment.clipRect.right,
        bottom: fragment.clipRect.bottom
      }, drawing.ClipOp.INTERSECT, true);
      if (hasAnnotations) ReaderV2AnnotationPainter.paintBackgrounds(canvas, fragment, page.annotationMarks);
      ReaderV2PagePainter.drawRange(canvas, fragment, selectionStart, selectionEnd, selectionColor);
      ReaderV2PagePainter.drawRange(canvas, fragment, highlightStart, highlightEnd, highlightColor);
      fragment.paragraph.paint(canvas, fragment.paragraphX, fragment.paragraphY);
      ReaderFontStroke.paint(canvas, fragment.fontStrokes, fragment.paragraphX, fragment.paragraphY);
      if (hasAnnotations) ReaderV2AnnotationPainter.paintTextColors(canvas, fragment, page.annotationMarks);
      canvas.restore();
    }
    if (hasAnnotations) ReaderV2AnnotationPainter.paintLines(canvas, page);
  }

  /** Theme artwork under the text (chapter-head ornament). An image that cannot be decoded is skipped. */
  private static drawDecorations(canvas: drawing.Canvas, page: ReaderV2PageLayout): void {
    for (const decoration of page.decorations) {
      const rect = decoration.rect;
      const width = rect.right - rect.left;
      const height = rect.bottom - rect.top;
      if (width <= 0.5 || height <= 0.5) continue;
      const bitmap = decoration.image ? ReaderRasterAssets.fileImage(decoration.image, width, height) : null;
      if (bitmap) {
        const brush = new drawing.Brush();
        brush.setAntiAlias(true);
        canvas.attachBrush(brush);
        canvas.drawImageRectWithSrc(bitmap,
          { left: 0, top: 0, right: Math.max(1, Math.round(width)), bottom: Math.max(1, Math.round(height)) },
          { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
          new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR), drawing.SrcRectConstraint.STRICT);
        canvas.detachBrush();
      }
      if (decoration.glyph) decoration.glyph.paint(canvas, decoration.glyphX, decoration.glyphY);
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
    if (segment.frameAsset && ReaderV2PagePainter.drawBubbleFrame(canvas, segment)) return;
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

  /**
   * Theme-pack frame for one line piece: the image is scaled so its text band (between the top/bottom slice lines)
   * fills frameRect's height; the end pieces keep their proportions and the middle stretches or tiles. Returns
   * false when the image cannot be decoded, so the caller falls back to the rounded background.
   */
  private static drawBubbleFrame(canvas: drawing.Canvas, segment: ReaderV2RegexBubbleSegment): boolean {
    const rect = segment.frameRect;
    const width = rect.right - rect.left;
    const band = rect.bottom - rect.top;
    if (width <= 0.5 || band <= 0.5) return true;
    const fullHeight = band / Math.max(0.02, 1 - segment.frameSliceTop - segment.frameSliceBottom);
    const fullWidth = fullHeight * Math.max(0.05, segment.frameAspect);
    const bitmap = ReaderRasterAssets.fileImage(segment.frameAsset, fullWidth, fullHeight);
    if (!bitmap) return false;
    const sourceWidth = Math.max(1, Math.round(fullWidth));
    const sourceHeight = Math.max(1, Math.round(fullHeight));
    const top = rect.top - segment.frameSliceTop * fullHeight;
    const bottom = top + fullHeight;
    let leadWidth = segment.frameLeadEnd ? segment.frameSliceLeft * fullWidth : 0;
    let trailWidth = segment.frameTrailEnd ? segment.frameSliceRight * fullWidth : 0;
    if (leadWidth + trailWidth > width) {
      const shrink = width / (leadWidth + trailWidth);
      leadWidth *= shrink;
      trailWidth *= shrink;
    }
    const leadSource = segment.frameSliceLeft * sourceWidth;
    const trailSource = segment.frameSliceRight * sourceWidth;
    const middleSource = Math.max(0, sourceWidth - leadSource - trailSource);
    const sampling = new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    if (segment.frameTint) {
      brush.setColorFilter(drawing.ColorFilter.createBlendModeColorFilter(
        ReaderV2PagePainter.brushColor(segment.backgroundColor), drawing.BlendMode.SRC_IN));
    }
    canvas.attachBrush(brush);
    const piece = (srcLeft: number, srcRight: number, dstLeft: number, dstRight: number): void => {
      if (srcRight - srcLeft <= 0.01 || dstRight - dstLeft <= 0.01) return;
      canvas.drawImageRectWithSrc(bitmap, { left: srcLeft, top: 0, right: srcRight, bottom: sourceHeight },
        { left: dstLeft, top: top, right: dstRight, bottom: bottom }, sampling, drawing.SrcRectConstraint.STRICT);
    };
    // Half a pixel of overlap hides the seams between pieces.
    if (leadWidth > 0) piece(0, leadSource, rect.left, rect.left + leadWidth + 0.5);
    if (trailWidth > 0) piece(sourceWidth - trailSource, sourceWidth, rect.right - trailWidth - 0.5, rect.right);
    const middleLeft = rect.left + leadWidth;
    const middleWidth = width - leadWidth - trailWidth;
    if (middleWidth > 0.5 && middleSource > 0.01) {
      if (!segment.frameRound) {
        piece(leadSource, leadSource + middleSource, middleLeft, middleLeft + middleWidth);
      } else {
        // Whole tiles, slightly squeezed or widened, so a repeating pattern never ends on a cut tile.
        const tileWidth = middleSource * fullWidth / sourceWidth;
        const count = Math.max(1, Math.round(middleWidth / Math.max(1, tileWidth)));
        const step = middleWidth / count;
        for (let index = 0; index < count; index++) {
          const tileLeft = middleLeft + index * step;
          piece(leadSource, leadSource + middleSource, tileLeft,
            index === count - 1 ? middleLeft + middleWidth : tileLeft + step + 0.5);
        }
      }
    }
    canvas.detachBrush();
    return true;
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
