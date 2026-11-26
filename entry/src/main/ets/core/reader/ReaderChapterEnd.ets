import graphicsText from '@ohos.graphics.text';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderV2PageDecoration, ReaderV2PageLayout } from './ReaderV2PageLayout';
import { ReaderFontWeight } from './ReaderFontWeight';
import { ReaderFrontPage } from './ReaderFrontPage';
import { ReaderChapterEndText } from './ReaderChapterEndText';

/** 章末卡片的内容。数字（今天读了多久、本章划线）会变：变了由阅读页就地重建卡片，不进分页缓存键。 */
export class ReaderChapterEndSpec {
  headLabel: string = '本章读完';
  percentText: string = '';
  words: number = 0;
  /** 今天这本书读了几分钟；空串表示没有记录，卡片上写“—”。 */
  todayMinutes: string = '';
  highlights: number = 0;
  nextTitle: string = '';
  nextWords: number = 0;
  /** 没有下一章时写的话（“全书完”“已读到最新一章”）。 */
  endText: string = '';
  accentColor: number = 0xFF2E5A88;
}

class ReaderTextRun {
  text: string;
  size: number;
  color: number;
  weight: number;

  constructor(text: string, size: number, color: number, weight: number) {
    this.text = text;
    this.size = size;
    this.color = color;
    this.weight = weight;
  }
}

/**
 * 章末卡片：一章最后一页正文下方的留白里画“第十二章 读完”小结（本章字数、今天已读、本章划线、下一章）。
 *
 * 两种放法：
 * - 这一章末尾有本章说时，本章说按卡片内边距往里收（见分页器），卡片底色从本章说顶上一直铺到卡片底，
 *   “读完”、三格数字、下一章排在本章说下面，同属一块。
 * - 没有本章说时，正文下方空一段再放一张独立的卡片。
 * 留白不够时先去掉三格数字（留“读完”和下一章）；独立卡片连这样也放不下就不画。包住本章说时，本章说先少列
 * 热评给“读完 + 下一章”留位（见分页器）；仍放不下时底色只包本章说。从不为它多开一页。
 * 全部是页面装饰，常驻页与翻页纹理共用 ReaderV2PagePainter。
 */
export class ReaderChapterEnd {
  static readonly GROUP: string = 'chapterEnd';
  static readonly KIND_PANEL: string = 'endPanel';
  static readonly KIND_LINE: string = 'endLine';
  static readonly MODE_NONE: number = 0;
  /** “读完” + 三格数字 + 下一章。 */
  static readonly MODE_FULL: number = 1;
  /** “读完” + 下一章。 */
  static readonly MODE_SHORT: number = 2;
  /** 包住本章说、下面什么都不放。 */
  static readonly MODE_WRAP_ONLY: number = 3;

  /** 本章说包进卡片时往里收的左右距离。 */
  static wrapInsetX(snapshot: ReaderV2LayoutSnapshot): number {
    return ReaderChapterEnd.font(snapshot) * 0.95;
  }

  /** 本章说包进卡片时，卡片顶边到本章说的距离。 */
  static wrapPadTop(snapshot: ReaderV2LayoutSnapshot): number {
    return ReaderChapterEnd.font(snapshot) * 0.85;
  }

  /** 包住本章说时卡片下半截最小的高度（“读完” + 下一章），本章说会先少列热评给它留出这么多。 */
  static minTailHeight(spec: ReaderChapterEndSpec, snapshot: ReaderV2LayoutSnapshot, width: number): number {
    const out: ReaderV2PageDecoration[] = [];
    const innerWidth = width - ReaderChapterEnd.wrapInsetX(snapshot) * 2;
    return ReaderChapterEnd.tail(spec, snapshot, 0, innerWidth, 0, ReaderChapterEnd.MODE_SHORT, true, out) +
      ReaderChapterEnd.padBottom(snapshot);
  }

  /**
   * 在正文（或本章说）下面从 top 起放卡片，available 是到版心底边还剩的高度（滚动阅读传 Infinity）。
   * page.chapterEndWrapTop >= 0 表示本章说已按包进卡片的方式排好，卡片底色从那里开始。返回占用的高度。
   */
  static place(page: ReaderV2PageLayout, spec: ReaderChapterEndSpec, snapshot: ReaderV2LayoutSnapshot,
    left: number, right: number, top: number, available: number): number {
    const wrap = page.chapterEndWrapTop >= 0;
    const modes = wrap ?
      [ReaderChapterEnd.MODE_FULL, ReaderChapterEnd.MODE_SHORT, ReaderChapterEnd.MODE_WRAP_ONLY] :
      [ReaderChapterEnd.MODE_FULL, ReaderChapterEnd.MODE_SHORT];
    const gapTop = wrap ? 0 : ReaderChapterEnd.font(snapshot) * 1.6;
    for (const mode of modes) {
      const decorations: ReaderV2PageDecoration[] = [];
      const height = ReaderChapterEnd.build(spec, snapshot, left, right, wrap ? page.chapterEndWrapTop : top + gapTop,
        top + gapTop, mode, wrap, decorations);
      // 包住本章说的底色最少只收到本章说底下（滚动阅读不受限）。
      const fits = gapTop + height <= available || mode === ReaderChapterEnd.MODE_WRAP_ONLY;
      if (!fits) continue;
      ReaderChapterEnd.adopt(page, decorations);
      page.chapterEndMode = mode;
      page.chapterEndRect = new ReaderV2Rect(left, top + gapTop, right, top + gapTop + height);
      page.chapterEndSnapshot = snapshot;
      return gapTop + Math.min(height, Math.max(0, available - gapTop));
    }
    return 0;
  }

  /** 数字变了：在原位置按原样式重建卡片（大小不变，不影响分页）。 */
  static refresh(page: ReaderV2PageLayout, spec: ReaderChapterEndSpec): void {
    const snapshot = page.chapterEndSnapshot;
    if (page.chapterEndMode === ReaderChapterEnd.MODE_NONE || !snapshot) return;
    page.decorations = page.decorations.filter((decoration: ReaderV2PageDecoration): boolean =>
      decoration.group !== ReaderChapterEnd.GROUP);
    const wrap = page.chapterEndWrapTop >= 0;
    const rect = page.chapterEndRect;
    const decorations: ReaderV2PageDecoration[] = [];
    ReaderChapterEnd.build(spec, snapshot, rect.left, rect.right, wrap ? page.chapterEndWrapTop : rect.top, rect.top,
      page.chapterEndMode, wrap, decorations);
    ReaderChapterEnd.adopt(page, decorations);
  }

  /** 底板要画在本章说下面：整组插到页面装饰最前面（装饰都画在文字片段之前）。 */
  private static adopt(page: ReaderV2PageLayout, decorations: ReaderV2PageDecoration[]): void {
    for (const decoration of decorations) decoration.group = ReaderChapterEnd.GROUP;
    page.decorations = decorations.concat(page.decorations);
  }

  /**
   * 排出整块：底板从 panelTop 起；contentTop 是下半截（读完、数字、下一章）开始的位置。返回从 contentTop 起的高度。
   */
  private static build(spec: ReaderChapterEndSpec, snapshot: ReaderV2LayoutSnapshot, left: number, right: number,
    panelTop: number, contentTop: number, mode: number, wrap: boolean, out: ReaderV2PageDecoration[]): number {
    const font = ReaderChapterEnd.font(snapshot);
    const padX = font * 0.95;
    const innerWidth = right - left - padX * 2;
    if (innerWidth < font * 9) return 0;
    const ink = snapshot.textColor >>> 0;
    const accent = spec.accentColor >>> 0;
    const dark = !ReaderFrontPage.isLight(ink);
    const panel = new ReaderV2PageDecoration();
    panel.kind = ReaderChapterEnd.KIND_PANEL;
    panel.color = ReaderFrontPage.withAlpha(accent, dark ? 0.075 : 0.055);
    panel.strokeColor = ReaderFrontPage.withAlpha(accent, dark ? 0.16 : 0.13);
    panel.radius = font * 0.95;
    out.push(panel);
    let height = 0;
    if (mode !== ReaderChapterEnd.MODE_WRAP_ONLY) {
      const start = wrap ? contentTop : contentTop + ReaderChapterEnd.wrapPadTop(snapshot);
      height = (start - contentTop) +
        ReaderChapterEnd.tail(spec, snapshot, left + padX, innerWidth, start, mode, wrap, out);
    }
    height += ReaderChapterEnd.padBottom(snapshot);
    panel.rect = new ReaderV2Rect(left, panelTop, right, contentTop + height);
    return height;
  }

  /** 下半截：包住本章说时先一道分隔线；然后“读完”行、三格数字、分隔线、下一章。返回高度。 */
  private static tail(spec: ReaderChapterEndSpec, snapshot: ReaderV2LayoutSnapshot, left: number, width: number,
    top: number, mode: number, wrap: boolean, out: ReaderV2PageDecoration[]): number {
    const font = ReaderChapterEnd.font(snapshot);
    const ink = snapshot.textColor >>> 0;
    const sub = ReaderFrontPage.withAlpha(ink, 0.58);
    const faint = ReaderFrontPage.withAlpha(ink, 0.42);
    const accent = spec.accentColor >>> 0;
    const edge = ReaderFrontPage.withAlpha(accent, ReaderFrontPage.isLight(ink) ? 0.13 : 0.16);
    const body = snapshot.bodyFontFamily;
    const weight = snapshot.fontWeight;
    let y = top;
    if (wrap) {
      y += font * 0.55;
      ReaderChapterEnd.line(out, left, y, left + width, y + 1, edge);
      y += 1 + font * 0.7;
    }

    // “第十二章 读完”，右边全书进度
    const label = ReaderFrontPage.text(spec.headLabel, font * 0.8, ink, snapshot.titleFontFamily,
      Math.max(600, snapshot.titleFontWeight), graphicsText.TextAlign.LEFT, width * 0.7, 1, font * 0.06);
    const percent = spec.percentText ? ReaderFrontPage.text(spec.percentText, font * 0.62, faint, body, weight,
      graphicsText.TextAlign.RIGHT, width * 0.3, 1, 0) : null;
    const headHeight = Math.max(label.getHeight(), percent ? percent.getHeight() : 0);
    const ruleWidth = font * 1.5;
    const rule = new ReaderV2PageDecoration();
    rule.kind = ReaderFrontPage.KIND_RULE;
    rule.color = accent;
    rule.rect = new ReaderV2Rect(left, y + headHeight / 2 - font * 0.22, left + ruleWidth, y + headHeight / 2 + font * 0.22);
    out.push(rule);
    ReaderChapterEnd.glyph(out, label, left + ruleWidth + font * 0.45, y + (headHeight - label.getHeight()) / 2);
    if (percent) ReaderChapterEnd.glyph(out, percent, left + width * 0.7, y + (headHeight - percent.getHeight()) / 2);
    y += headHeight;

    if (mode === ReaderChapterEnd.MODE_FULL) {
      y += font * 0.75;
      const cells: string[][] = [
        [ReaderChapterEndText.number(spec.words), '字', '本章字数'],
        [spec.todayMinutes || '—', spec.todayMinutes ? '分钟' : '', '今天已读'],
        [`${Math.max(0, spec.highlights)}`, '处', '本章划线']
      ];
      const cellWidth = width / cells.length;
      let statsHeight = 0;
      const glyphs: graphicsText.Paragraph[][] = [];
      for (const cell of cells) {
        const value = ReaderChapterEnd.runs([
          new ReaderTextRun(cell[0], font * 0.98, ink, 600),
          new ReaderTextRun(cell[1] ? ` ${cell[1]}` : '', font * 0.58, sub, weight)
        ], body, cellWidth);
        const caption = ReaderFrontPage.text(cell[2], font * 0.6, sub, body, weight, graphicsText.TextAlign.LEFT,
          cellWidth, 1, 0);
        glyphs.push([value, caption]);
        statsHeight = Math.max(statsHeight, value.getHeight() + font * 0.18 + caption.getHeight());
      }
      for (let index = 0; index < glyphs.length; index++) {
        const x = left + index * cellWidth + (index > 0 ? font * 0.65 : 0);
        ReaderChapterEnd.glyph(out, glyphs[index][0], x, y);
        ReaderChapterEnd.glyph(out, glyphs[index][1], x, y + glyphs[index][0].getHeight() + font * 0.18);
        if (index > 0) {
          ReaderChapterEnd.line(out, left + index * cellWidth, y + font * 0.12, left + index * cellWidth + 1,
            y + statsHeight - font * 0.12, edge);
        }
      }
      y += statsHeight;
    }
    y += font * 0.65;
    ReaderChapterEnd.line(out, left, y, left + width, y + 1, edge);
    y += 1 + font * 0.6;
    y += ReaderChapterEnd.nextRow(spec, snapshot, left, width, y, ink, sub, faint, out);
    return y - top;
  }

  private static nextRow(spec: ReaderChapterEndSpec, snapshot: ReaderV2LayoutSnapshot, left: number, width: number,
    top: number, ink: number, sub: number, faint: number, out: ReaderV2PageDecoration[]): number {
    const font = ReaderChapterEnd.font(snapshot);
    const body = snapshot.bodyFontFamily;
    const weight = snapshot.fontWeight;
    if (!spec.nextTitle) {
      const end = ReaderFrontPage.text(spec.endText || '本章完', font * 0.66, sub, body, weight,
        graphicsText.TextAlign.LEFT, width, 1, 0);
      ReaderChapterEnd.glyph(out, end, left, top);
      return end.getHeight();
    }
    const label = ReaderFrontPage.text('下一章', font * 0.62, faint, body, weight, graphicsText.TextAlign.LEFT,
      font * 4, 1, 0);
    const labelWidth = label.getLongestLine();
    const words = spec.nextWords > 0 ? ReaderFrontPage.text(`${ReaderChapterEndText.number(spec.nextWords)} 字`,
      font * 0.62, faint, body, weight, graphicsText.TextAlign.RIGHT, width * 0.4, 1, 0) : null;
    const wordsWidth = words ? words.getLongestLine() : 0;
    const titleWidth = Math.max(font * 2, width - labelWidth - wordsWidth - font * 1.1);
    const title = ReaderFrontPage.text(spec.nextTitle, font * 0.68, ink, body, weight, graphicsText.TextAlign.LEFT,
      titleWidth, 1, 0);
    const height = Math.max(label.getHeight(), title.getHeight(), words ? words.getHeight() : 0);
    ReaderChapterEnd.glyph(out, label, left, top + (height - label.getHeight()) / 2);
    ReaderChapterEnd.glyph(out, title, left + labelWidth + font * 0.5, top + (height - title.getHeight()) / 2);
    if (words) {
      ReaderChapterEnd.glyph(out, words, left + width - words.getMaxWidth(), top + (height - words.getHeight()) / 2);
    }
    return height;
  }

  private static font(snapshot: ReaderV2LayoutSnapshot): number {
    return Math.max(8, snapshot.fontSizePx);
  }

  private static padBottom(snapshot: ReaderV2LayoutSnapshot): number {
    return ReaderChapterEnd.font(snapshot) * 0.75;
  }

  private static glyph(out: ReaderV2PageDecoration[], paragraph: graphicsText.Paragraph, left: number, top: number): void {
    const decoration = new ReaderV2PageDecoration();
    decoration.glyph = paragraph;
    decoration.glyphX = left;
    decoration.glyphY = top;
    decoration.rect = new ReaderV2Rect(left, top, left + paragraph.getMaxWidth(), top + paragraph.getHeight());
    out.push(decoration);
  }

  private static line(out: ReaderV2PageDecoration[], left: number, top: number, right: number, bottom: number,
    color: number): void {
    const decoration = new ReaderV2PageDecoration();
    decoration.kind = ReaderChapterEnd.KIND_LINE;
    decoration.color = color;
    decoration.rect = new ReaderV2Rect(left, top, right, bottom);
    out.push(decoration);
  }

  /** 一段文字里几种字号颜色（数字和单位），单行，超出用省略号。 */
  private static runs(runs: ReaderTextRun[], family: string, width: number): graphicsText.Paragraph {
    const base = ReaderChapterEnd.style(runs[0], family);
    const builder = new graphicsText.ParagraphBuilder({
      textStyle: base,
      align: graphicsText.TextAlign.LEFT,
      textDirection: graphicsText.TextDirection.LTR,
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      includeFontPadding: true,
      maxLines: 1
    }, graphicsText.FontCollection.getGlobalInstance());
    for (const run of runs) {
      if (!run.text) continue;
      builder.pushStyle(ReaderChapterEnd.style(run, family));
      builder.addText(run.text);
      builder.popStyle();
    }
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, width));
    return paragraph;
  }

  private static style(run: ReaderTextRun, family: string): graphicsText.TextStyle {
    const resolved = ReaderFontWeight.layoutWeight(family, run.weight);
    return {
      fontSize: run.size,
      fontFamilies: family ? [family] : [],
      fontWeight: ReaderFrontPage.FONT_WEIGHTS[Math.max(0, Math.min(8, Math.round(resolved / 100) - 1))],
      fontVariations: [{ axis: 'wght', value: resolved }],
      color: ReaderFrontPage.color(run.color),
      halfLeading: true,
      ellipsis: '…',
      ellipsisMode: graphicsText.EllipsisMode.END,
      locale: 'zh-Hans'
    };
  }
}
