import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderV2PageDecoration, ReaderV2PageFragment, ReaderV2PageLayout } from './ReaderV2PageLayout';

/** Space the chapter-head ornament takes from the title group, in pixels. All zero when there is no ornament. */
export class ReaderV2ChapterHeadMetrics {
  widthPx: number = 0;
  heightPx: number = 0;
  /** Gap between the ornament and the title text. */
  gapPx: number = 0;
  /** 'side': width taken from the left of every title line (ornament + gap). */
  reservePx: number = 0;
  /** Added to the title's top / bottom margin so the ornament never overlaps neighbouring content. */
  extraTopPx: number = 0;
  extraBottomPx: number = 0;
}

/**
 * 章首饰图的尺寸与位置。尺寸只由标题字号、分段与否和主题设置决定，不依赖标题实际排出几行，
 * 这样先定下留给饰图的宽度再排标题，不会互相影响。
 *
 * - side：高 = 整组标题按每块一行估出的高度 × 倍数，贴版心左边，上下居中于实际的标题组；
 *   比标题组高出的部分平分到标题上下边距里。宽度最多占版心的 30%。
 * - top / bottom：高 = 标题字号 × 0.9 × 倍数，单独占一行（算进标题上 / 下边距），左右跟标题的对齐方式。
 */
export class ReaderV2ChapterHeadLayout {
  /** 一行标题的行框高相对字号的估计值（含字体自带的上下留白）。 */
  private static readonly LINE_BOX: number = 1.25;
  private static readonly MAX_SIDE_WIDTH: number = 0.3;

  static metrics(snapshot: ReaderV2LayoutSnapshot, titleBlocks: number, columnWidth: number): ReaderV2ChapterHeadMetrics {
    const result = new ReaderV2ChapterHeadMetrics();
    const head = snapshot.chapterHead;
    if (!head.image || titleBlocks <= 0 || columnWidth <= 1) return result;
    const font = snapshot.titleFontSizePx;
    const aspect = Math.max(0.05, Math.min(20, head.aspect > 0 ? head.aspect : 1));
    const scale = Math.max(0.5, Math.min(2, head.scale > 0 ? head.scale : 1));
    if (head.placement === 'top' || head.placement === 'bottom') {
      let height = font * 0.9 * scale;
      let width = height * aspect;
      if (width > columnWidth) {
        width = columnWidth;
        height = width / aspect;
      }
      result.widthPx = width;
      result.heightPx = height;
      result.gapPx = font * 0.3;
      if (head.placement === 'top') result.extraTopPx = height + result.gapPx;
      else result.extraBottomPx = height + result.gapPx;
      return result;
    }
    const nominal = font * ReaderV2ChapterHeadLayout.LINE_BOX + (titleBlocks > 1 ?
      snapshot.titleLineGapPx + font * snapshot.titleSecondaryScale * ReaderV2ChapterHeadLayout.LINE_BOX : 0);
    let height = nominal * scale;
    let width = height * aspect;
    const maxWidth = columnWidth * ReaderV2ChapterHeadLayout.MAX_SIDE_WIDTH;
    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspect;
    }
    result.widthPx = width;
    result.heightPx = height;
    result.gapPx = font * 0.35;
    result.reservePx = width + result.gapPx;
    const overflow = Math.max(0, (height - nominal) / 2);
    result.extraTopPx = overflow;
    result.extraBottomPx = overflow;
    return result;
  }

  /**
   * Puts the ornament on a finished page (fragments already at their final positions). 'side' needs the whole
   * title group on this page; 'top' needs its first line and 'bottom' its last.
   */
  static place(page: ReaderV2PageLayout, snapshot: ReaderV2LayoutSnapshot, metrics: ReaderV2ChapterHeadMetrics,
    column: ReaderV2Rect): void {
    const head = snapshot.chapterHead;
    if (!head.image || metrics.widthPx <= 0.5 || metrics.heightPx <= 0.5) return;
    let first: ReaderV2PageFragment | null = null;
    let last: ReaderV2PageFragment | null = null;
    for (const fragment of page.fragments) {
      if (!fragment.title || !fragment.paragraph) continue;
      if (!first && !fragment.titleContinuation && fragment.localStart === 0) first = fragment;
      if (fragment.titleEnd) last = fragment;
    }
    let left = column.left;
    if (head.placement === 'top' || head.placement === 'bottom') {
      if (snapshot.titleAlignment === 'center') left = column.left + (column.width() - metrics.widthPx) / 2;
      else if (snapshot.titleAlignment === 'right') left = column.right - metrics.widthPx;
    }
    let top = 0;
    if (head.placement === 'top') {
      if (!first) return;
      top = first.paragraphY - metrics.gapPx - metrics.heightPx;
    } else if (head.placement === 'bottom') {
      if (!last) return;
      top = last.paragraphY + last.paragraphHeight + metrics.gapPx;
    } else {
      if (!first || !last) return;
      top = (first.paragraphY + last.paragraphY + last.paragraphHeight - metrics.heightPx) / 2;
    }
    const decoration = new ReaderV2PageDecoration();
    decoration.image = head.image;
    decoration.rect = new ReaderV2Rect(left, top, left + metrics.widthPx, top + metrics.heightPx);
    page.decorations.push(decoration);
  }
}
