import graphicsText from '@ohos.graphics.text';
import { ReaderPaginationBoundary } from './ReaderPaginationIndex';
import { ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderCommentBubbleStyle } from './ReaderCommentBubble';
import { ReaderFontStrokeRun } from './ReaderFontStroke';
import { ReaderV2CommentCard } from './ReaderV2CommentCard';
import { ReaderTextRulingSpec } from './ReaderTextRuling';

/** Minimal native Text span metadata used by the transparent system-selection layer. */
export class ReaderV2SelectionRun {
  text: string = '';
  fontSizePx: number = 0;
  fontFamily: string = '';
  fontWeight: number = 400;
  letterSpacingPx: number = 0;

  constructor(text: string, fontSizePx: number, fontFamily: string, fontWeight: number,
    letterSpacingPx: number = 0) {
    this.text = text;
    this.fontSizePx = fontSizePx;
    this.fontFamily = fontFamily;
    this.fontWeight = fontWeight;
    this.letterSpacingPx = letterSpacingPx;
  }
}

export class ReaderV2RegexBubbleSegment {
  styleId: string = '';
  /** Use the theme pack's dark-mode cap. */
  capDark: boolean = false;
  text: string = '';
  leading: boolean = false;
  trailing: boolean = false;
  rect: ReaderV2Rect = new ReaderV2Rect();
  capSizePx: number = 0;
  leadingCapWidthPx: number = 0;
  trailingCapWidthPx: number = 0;
  fontSizePx: number = 0;
  fontFamily: string = '';
  textColor: number = 0;
  backgroundColor: number = 0;
  radiusTopLeftPx: number = 0;
  radiusTopRightPx: number = 0;
  radiusBottomRightPx: number = 0;
  radiusBottomLeftPx: number = 0;
  shadowEnabled: boolean = false;
  shadowColor: number = 0;
  shadowRadiusPx: number = 0;
  shadowOffsetXPx: number = 0;
  shadowOffsetYPx: number = 0;
  /** Theme-pack frame for this line piece; empty means the rounded background above is painted instead. */
  frameAsset: string = '';
  frameAspect: number = 3;
  frameSliceLeft: number = 0;
  frameSliceRight: number = 0;
  frameSliceTop: number = 0;
  frameSliceBottom: number = 0;
  frameRound: boolean = false;
  frameTint: boolean = false;
  /** Frame box: x range covers the end pieces; top/bottom is the text band the slice lines align to. */
  frameRect: ReaderV2Rect = new ReaderV2Rect();
  /** Whether this piece draws its left / right end (false at a flat-cut line break). */
  frameLeadEnd: boolean = false;
  frameTrailEnd: boolean = false;
}

/** One line's piece of a paragraph-comment / 本章说 bubble; only the last piece carries the tail. */
export class ReaderV2CommentBubbleSegment {
  scale: number = 1;
  rect: ReaderV2Rect = new ReaderV2Rect();
  tail: boolean = true;
  style: ReaderCommentBubbleStyle = new ReaderCommentBubbleStyle();
}

export class ReaderV2PageFragment {
  title: boolean = false;
  titleContinuation: boolean = false;
  titleEnd: boolean = false;
  fixedGapBefore: boolean = false;
  /** 标题片段左边让给章首饰图、或首段前几行让给首字的宽度；段落已排在 paragraphX（含这段宽度）之后。 */
  leadReservePx: number = 0;
  /**
   * 首段绕着首字排的那一截的第一行：首字方框的上边相对本片段顶边的偏移（放大样式向上抬出时为负）、方框边长；
   * 边长 0 表示不是。
   */
  dropCapTopPx: number = 0;
  dropCapBoxPx: number = 0;
  /** 让出 leadReservePx 的行高范围（从片段顶边起），选字层按它缩进前几行。 */
  dropCapSpanPx: number = 0;
  /** 同一段在本页紧接着上一个片段继续（首段绕排之后回到整行的那一截）：两个片段之间没有换行。 */
  blockContinuation: boolean = false;
  blockId: string = '';
  blockIndex: number = 0;
  paragraph: graphicsText.Paragraph | null = null;
  fontStrokes: ReaderFontStrokeRun[] = [];
  paragraphX: number = 0;
  paragraphY: number = 0;
  clipRect: ReaderV2Rect = new ReaderV2Rect();
  localStart: number = 0;
  localEnd: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;
  paragraphHeight: number = 0;
  selectionPageStart: number = 0;
  selectionPageEnd: number = 0;
  /** 整页选中文本里，这个片段之后是否跟着一个换行（后面还有文字片段）。 */
  selectionBreakAfter: boolean = false;
  selectionRuns: ReaderV2SelectionRun[] = [];
  /** 图片片段：paragraph 为 null，图片以 Contain 方式绘制在 imageRect 内。 */
  imageSource: string = '';
  imageRect: ReaderV2Rect = new ReaderV2Rect();
  regexBubbleSegments: ReaderV2RegexBubbleSegment[] = [];
  /** 正则字体命中的正文区间（显示偏移，成对的 [开始, 结束)），“仅正则字体”文字划线用；标题样式不在其中。 */
  regexRanges: number[] = [];
  commentBubbleSegments: ReaderV2CommentBubbleSegment[] = [];
  /** 热评卡片段：paragraph 为 null，卡片坐标相对 paragraphX / paragraphY。 */
  card: ReaderV2CommentCard | null = null;
}

/**
 * 画在正文底下的主题装饰：章首饰图（image 按 rect 拉伸），或首字装饰（可选的印章图加放大的那个字）。
 * 首字不属于任何文字片段，选字、划线、朗读高亮都不经过它。
 */
export class ReaderV2PageDecoration {
  image: string = '';
  rect: ReaderV2Rect = new ReaderV2Rect();
  /** 首字的字形，画在 (glyphX, glyphY)。 */
  glyph: graphicsText.Paragraph | null = null;
  glyphX: number = 0;
  glyphY: number = 0;
}

/** 一条划线落在本页的部分，偏移是本页所属文档的显示偏移（与片段 displayStart 同一坐标）。 */
export class ReaderV2AnnotationMark {
  id: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;
  style: string = 'solid';
  /** 不透明 ARGB。 */
  color: number = 0xFF3B82F6;
  /** 有笔记且要显示标记：在划线末端画小圆点（末端不在本页时不画）。 */
  noteDot: boolean = false;
}

export class ReaderV2ActionHitArea {
  actionId: string = '';
  marker: string = '';
  rect: ReaderV2Rect = new ReaderV2Rect();
}

export class ReaderV2PageLayout implements ReaderPaginationBoundary {
  pageIndex: number = 0;
  columnIndex: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;
  contentRect: ReaderV2Rect = new ReaderV2Rect();
  fragments: ReaderV2PageFragment[] = [];
  actions: ReaderV2ActionHitArea[] = [];
  decorations: ReaderV2PageDecoration[] = [];
  identity: string = '';
  selectionText: string = '';
  selectionX: number = 0;
  selectionY: number = 0;
  selectionWidth: number = 0;
  selectionHeight: number = 0;
  /** 页底对齐给本页正文每处行间加的距离（像素）；选字层的行距要跟着加。 */
  lineStretchPx: number = 0;
  /** 本页最后一个片段的下边缘（含字形出血），滚动阅读用它确定列表项高度。 */
  contentBottomPx: number = 0;
  /** 划线由阅读页按当前划线数据填入；annotationStamp 记填入时的数据版本，版本变了重新填。 */
  annotationMarks: ReaderV2AnnotationMark[] = [];
  annotationStamp: string = '';
  /** 正文文字划线，与划线一起由阅读页填入（版本并在 annotationStamp 里）；null 为不画。 */
  ruling: ReaderTextRulingSpec | null = null;

  actionAt(x: number, y: number, slopX: number, slopY: number): ReaderV2ActionHitArea | null {
    // Later actions win where expanded hit slop overlaps, which matches visual painting order.
    for (let index = this.actions.length - 1; index >= 0; index--) {
      const action = this.actions[index];
      if (action.rect.contains(x, y, slopX, slopY)) return action;
    }
    return null;
  }
}

export class ReaderV2PageSet {
  documentIdentity: string = '';
  layoutIdentity: string = '';
  pages: ReaderV2PageLayout[] = [];
  complete: boolean = false;

  pageForDisplayOffset(offset: number): number {
    if (this.pages.length === 0) return 0;
    let low = 0;
    let high = this.pages.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.pages[middle].displayEnd <= offset) low = middle + 1;
      else high = middle;
    }
    return Math.max(0, Math.min(this.pages.length - 1, low));
  }
}
