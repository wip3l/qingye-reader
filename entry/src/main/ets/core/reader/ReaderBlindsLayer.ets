import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderV2PageLayout } from './ReaderV2PageLayout';
import { ReaderV2PagePainter } from './ReaderV2PagePainter';
import { ReaderPageRasterizer, ReaderRasterImage } from './ReaderPageRasterizer';
import { ReaderBlindsMotion } from './ReaderBlindsMotion';

/** 叶片效果：逐行翻转、逐行淡入，或一条线连续往下擦（会切过半行）。 */
export const READER_BLINDS_EFFECT_FLIP: string = 'flip';
export const READER_BLINDS_EFFECT_FADE: string = 'fade';
export const READER_BLINDS_EFFECT_WIPE: string = 'wipe';

/** 百叶窗要画的一页：版面加上插图、气泡端饰这类由 ArkUI 另画的位图（页内像素坐标）。 */
export class ReaderBlindsPage {
  layout: ReaderV2PageLayout;
  images: ReaderRasterImage[];
  /** 有插图还没解码、先空着；阅读页稍后重取。 */
  incomplete: boolean = false;

  constructor(layout: ReaderV2PageLayout, images: ReaderRasterImage[]) {
    this.layout = layout;
    this.images = images;
  }
}

/** 一栏：本页、下一页和逐行节奏。下一页为 null 时整栏只画本页。 */
export class ReaderBlindsColumn {
  current: ReaderBlindsPage | null = null;
  next: ReaderBlindsPage | null = null;
  motion: ReaderBlindsMotion;

  constructor(motion: ReaderBlindsMotion) {
    this.motion = motion;
  }
}

export class ReaderBlindsBands {
  /** 一页的叶片：每行文字（含字形出血）、插图、热评卡、气泡和章首饰图各占一段高度，重叠的并成一片。 */
  static of(page: ReaderV2PageLayout | null): number[][] {
    if (!page) return [];
    const intervals: number[][] = [];
    for (const fragment of page.fragments) {
      if (fragment.paragraph) {
        const clipTop = fragment.clipRect.top;
        const clipBottom = fragment.clipRect.bottom;
        const lines: graphicsText.LineMetrics[] = fragment.paragraph.getLineMetrics();
        for (const line of lines) {
          const boxTop = fragment.paragraphY + line.topHeight;
          const boxBottom = boxTop + line.height;
          // 跨页拆开的段落整段排版、按 clipRect 只画本页这截；本页外的行（或只蹭进来一点出血的行）不算。
          const inside = Math.min(boxBottom, clipBottom) - Math.max(boxTop, clipTop);
          if (inside < line.height * 0.4) continue;
          const inkTop = fragment.paragraphY + line.baseline - Math.abs(line.ascent);
          const inkBottom = fragment.paragraphY + line.baseline + Math.abs(line.descent);
          intervals.push([Math.max(clipTop, Math.min(boxTop, inkTop)), Math.min(clipBottom, Math.max(boxBottom,
            inkBottom))]);
        }
      } else if (fragment.imageSource) {
        intervals.push([fragment.imageRect.top, fragment.imageRect.bottom]);
      } else {
        intervals.push([fragment.clipRect.top, fragment.clipRect.bottom]);
      }
      for (const segment of fragment.regexBubbleSegments) intervals.push([segment.rect.top, segment.rect.bottom]);
      for (const bubble of fragment.commentBubbleSegments) intervals.push([bubble.rect.top, bubble.rect.bottom]);
    }
    for (const decoration of page.decorations) intervals.push([decoration.rect.top, decoration.rect.bottom]);
    return ReaderBlindsMotion.mergeBands(intervals);
  }
}

/**
 * 画一栏百叶窗：没翻的本页整块裁一次画，已经立好的下一页整块裁一次画，只有正在翻的叶片单独画（同时最多两三片），
 * 所以静止时每帧两次整页绘制，翻动时也只多几次。翻转是绕叶片中线的纵向压缩加淡出/淡入，淡入只改透明度；
 * 擦除不按叶片，阅读线以上是下一页、以下是本页。
 */
export class ReaderBlindsPainter {
  private static readonly FAR: number = 100000;

  static paint(canvas: drawing.Canvas, column: ReaderBlindsColumn, now: number, widthPx: number, effect: string,
    guideColor: common2D.Color, guideWidthPx: number, showGuide: boolean): void {
    const motion = column.motion;
    const sampling = new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
    if (effect === READER_BLINDS_EFFECT_WIPE) {
      const line = motion.position();
      if (column.current) {
        ReaderBlindsPainter.drawClipped(canvas, column.current, column.next ? line : -ReaderBlindsPainter.FAR,
          ReaderBlindsPainter.FAR, sampling);
      }
      if (column.next && line > 0) {
        ReaderBlindsPainter.drawClipped(canvas, column.next, -ReaderBlindsPainter.FAR, line, sampling);
      }
      ReaderBlindsPainter.drawGuide(canvas, line, widthPx, guideColor, guideWidthPx, showGuide);
      return;
    }
    const flip = effect !== READER_BLINDS_EFFECT_FADE;
    const current = motion.currentBands();
    const next = motion.nextBands();
    const hidden = motion.hiddenCount();
    const shown = motion.shownCount();
    if (column.current && hidden < current.length) {
      ReaderBlindsPainter.drawClipped(canvas, column.current, current[hidden][0], ReaderBlindsPainter.FAR,
        sampling);
    } else if (column.current && current.length === 0 && shown === 0) {
      // 空白页（没有任何叶片）照常画，免得章首饰图之类没有行的内容在开始前就消失。
      ReaderBlindsPainter.drawClipped(canvas, column.current, -ReaderBlindsPainter.FAR, ReaderBlindsPainter.FAR,
        sampling);
    }
    if (column.current) {
      for (let index = 0; index < hidden; index++) {
        const progress = motion.outProgress(index, now);
        if (progress >= 1) continue;
        ReaderBlindsPainter.drawFlip(canvas, column.current, current[index],
          flip ? Math.cos(progress * Math.PI / 2) : 1, 1 - progress, sampling);
      }
    }
    if (column.next) {
      // 翻出的时刻按顺序记录，进度从前往后递减：开头连续几片已立好的合成一块画。
      let settled = 0;
      while (settled < shown && motion.inProgress(settled, now) >= 1) settled++;
      if (settled > 0) {
        ReaderBlindsPainter.drawClipped(canvas, column.next, -ReaderBlindsPainter.FAR, next[settled - 1][1],
          sampling);
      }
      for (let index = settled; index < shown; index++) {
        const progress = motion.inProgress(index, now);
        if (progress <= 0) continue;
        ReaderBlindsPainter.drawFlip(canvas, column.next, next[index], flip ? Math.sin(progress * Math.PI / 2) : 1,
          progress, sampling);
      }
    }
    ReaderBlindsPainter.drawGuide(canvas, motion.guideY(now), widthPx, guideColor, guideWidthPx, showGuide);
  }

  private static drawGuide(canvas: drawing.Canvas, y: number, widthPx: number, color: common2D.Color,
    strokePx: number, show: boolean): void {
    if (!show || y <= 0.5 || widthPx <= 0) return;
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setColor(color);
    pen.setStrokeWidth(Math.max(1, strokePx));
    canvas.attachPen(pen);
    canvas.drawLine(0, y, widthPx, y);
    canvas.detachPen();
  }

  private static drawClipped(canvas: drawing.Canvas, page: ReaderBlindsPage, top: number, bottom: number,
    sampling: drawing.SamplingOptions): void {
    if (bottom <= top) return;
    canvas.save();
    canvas.clipRect({ left: -ReaderBlindsPainter.FAR, top: top, right: ReaderBlindsPainter.FAR, bottom: bottom },
      drawing.ClipOp.INTERSECT, true);
    ReaderBlindsPainter.drawPage(canvas, page, sampling);
    canvas.restore();
  }

  private static drawFlip(canvas: drawing.Canvas, page: ReaderBlindsPage, band: number[], scaleY: number,
    alpha: number, sampling: drawing.SamplingOptions): void {
    if (scaleY <= 0.02 || alpha <= 0.02) return;
    const center = (band[0] + band[1]) / 2;
    canvas.save();
    canvas.clipRect({ left: -ReaderBlindsPainter.FAR, top: band[0], right: ReaderBlindsPainter.FAR, bottom: band[1] },
      drawing.ClipOp.INTERSECT, true);
    if (scaleY < 0.999) {
      canvas.translate(0, center);
      canvas.scale(1, scaleY);
      canvas.translate(0, -center);
      // 压缩后再按叶片裁一次（内容坐标）：只裁屏幕坐标的话，上下相邻的行会被一起压进这片里。
      canvas.clipRect({ left: -ReaderBlindsPainter.FAR, top: band[0], right: ReaderBlindsPainter.FAR,
        bottom: band[1] }, drawing.ClipOp.INTERSECT, true);
    }
    if (alpha < 0.99) {
      const brush = new drawing.Brush();
      brush.setAlpha(Math.round(alpha * 255));
      canvas.saveLayer(null, brush);
      ReaderBlindsPainter.drawPage(canvas, page, sampling);
      canvas.restore();
    } else {
      ReaderBlindsPainter.drawPage(canvas, page, sampling);
    }
    canvas.restore();
  }

  private static drawPage(canvas: drawing.Canvas, page: ReaderBlindsPage, sampling: drawing.SamplingOptions): void {
    ReaderV2PagePainter.paint(canvas, page.layout);
    for (const picture of page.images) ReaderPageRasterizer.drawImage(canvas, picture, sampling);
  }
}

/**
 * 盖在本页正文位置上的百叶窗画布（ArkUI Canvas + DrawingRenderingContext），坐标与页面节点一致（页内像素）。
 * 不用自定义 FrameNode：部分系统版本把 RenderNode.invalidate() 推迟到下一次翻页才执行，逐帧动画会停住不动。
 */
export class ReaderBlindsSurface {
  readonly context: DrawingRenderingContext = new DrawingRenderingContext();
  private ready: boolean = false;
  private column: ReaderBlindsColumn | null = null;
  private effect: string = READER_BLINDS_EFFECT_FLIP;
  private guideColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private guideWidthPx: number = 1;
  private showGuide: boolean = true;

  update(column: ReaderBlindsColumn | null, effect: string, guideColor: common2D.Color, guideWidthPx: number,
    showGuide: boolean): void {
    this.column = column;
    this.effect = effect;
    this.guideColor = guideColor;
    this.guideWidthPx = guideWidthPx;
    this.showGuide = showGuide;
    this.redraw();
  }

  /** Canvas 布局好（onReady）后才能画；之前的更新在这里补画。 */
  markReady(): void {
    this.ready = true;
    this.redraw();
  }

  redraw(): void {
    if (!this.ready) return;
    try {
      const canvas = this.context.canvas;
      canvas.clear({ alpha: 0, red: 0, green: 0, blue: 0 });
      if (this.column) {
        const widthPx = vp2px(this.context.size.width);
        // 版面坐标是像素；画布若不是按像素建的（宽度对不上），按比例换算过去。
        const canvasWidth = canvas.getWidth();
        const ratio = widthPx > 0 && canvasWidth > 0 ? canvasWidth / widthPx : 1;
        canvas.save();
        if (Math.abs(ratio - 1) > 0.02) canvas.scale(ratio, ratio);
        ReaderBlindsPainter.paint(canvas, this.column, Date.now(), widthPx, this.effect, this.guideColor,
          this.guideWidthPx, this.showGuide);
        canvas.restore();
      }
      this.context.invalidate();
    } catch (error) {
      console.warn('[ReaderBlinds] draw failed:', error);
    }
  }
}
