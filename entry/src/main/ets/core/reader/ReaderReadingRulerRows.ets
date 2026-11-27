import graphicsText from '@ohos.graphics.text';
import { ReaderV2PageLayout } from './ReaderV2PageLayout';
import { ReaderRulerRow } from './ReaderReadingRulerSteps';

/**
 * 阅读尺用的“行”：从一页（或滚动阅读的一块）的排版结果里取出，坐标是页内像素。
 * 正文每个显示行一行；章节标题整块算一行；插图、热评卡片各算一行，尺不会把它们切开。
 * 跨页段落只取落在本页裁剪区里的行（只蹭进来一点出血的不算）。
 */
export class ReaderReadingRulerRows {
  static collect(page: ReaderV2PageLayout, column: number): ReaderRulerRow[] {
    const rows: ReaderRulerRow[] = [];
    for (const fragment of page.fragments) {
      if (fragment.imageSource) {
        if (fragment.imageRect.height() > 0) {
          rows.push(new ReaderRulerRow(fragment.imageRect.top, fragment.imageRect.bottom, column));
        }
        continue;
      }
      if (fragment.card) {
        if (fragment.clipRect.height() > 0) {
          rows.push(new ReaderRulerRow(fragment.clipRect.top, fragment.clipRect.bottom, column));
        }
        continue;
      }
      const paragraph = fragment.paragraph;
      if (!paragraph) continue;
      const lines: graphicsText.LineMetrics[] = paragraph.getLineMetrics();
      let titleTop = Number.POSITIVE_INFINITY;
      let titleBottom = Number.NEGATIVE_INFINITY;
      for (const line of lines) {
        const top = fragment.paragraphY + line.topHeight;
        const bottom = top + line.height;
        const inside = Math.min(bottom, fragment.clipRect.bottom) - Math.max(top, fragment.clipRect.top);
        if (line.height <= 0 || inside < line.height * 0.4) continue;
        if (fragment.title) {
          titleTop = Math.min(titleTop, top);
          titleBottom = Math.max(titleBottom, bottom);
        } else {
          rows.push(new ReaderRulerRow(top, bottom, column));
        }
      }
      if (fragment.title && titleBottom > titleTop) rows.push(new ReaderRulerRow(titleTop, titleBottom, column));
    }
    return rows;
  }
}
