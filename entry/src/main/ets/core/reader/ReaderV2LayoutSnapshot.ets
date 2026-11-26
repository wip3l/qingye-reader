import { ReaderCommentBubbleSize } from './ReaderCommentBubbleSize';
import { ReaderFontWeight } from './ReaderFontWeight';
import { ReaderCommentBubbleStyle } from './ReaderCommentBubble';

export class ReaderV2Rect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  constructor(left: number = 0, top: number = 0, right: number = 0, bottom: number = 0) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  width(): number {
    return Math.max(0, this.right - this.left);
  }

  height(): number {
    return Math.max(0, this.bottom - this.top);
  }

  contains(x: number, y: number, slopX: number = 0, slopY: number = 0): boolean {
    return x >= this.left - slopX && x <= this.right + slopX &&
      y >= this.top - slopY && y <= this.bottom + slopY;
  }
}

/** 章首装饰：章节标题旁的主题饰图，和分段标题第一段的颜色。image 为空时不画饰图。 */
export class ReaderV2ChapterHeadStyle {
  /** 饰图文件（沙箱路径或 file:// URI）。 */
  image: string = '';
  /** 原图宽 / 高。 */
  aspect: number = 1;
  /** 'side'（贴版心左边、上下居中于整组标题）、'top'、'bottom'（单独占一行，跟着标题的对齐方式）。 */
  placement: string = 'side';
  /** 0.5–2。 */
  scale: number = 1;
  /** 分段标题第一段的颜色（ARGB）；0 表示和标题同色。 */
  numberColor: number = 0;
  /** 首字装饰占几行：0 不处理，2–4。放大样式时是首字方框高几行。 */
  capLines: number = 0;
  /** 放大样式：首字方框底边对齐第一行文字、向上抬出，只有第一行让出位置；false 为下沉（前 capLines 行绕排）。 */
  capRaise: boolean = false;
  /** 首字底下的印章图文件；空串只放大。 */
  capImage: string = '';
  /** 首字颜色（ARGB）；0 表示和正文同色。 */
  capColor: number = 0;
  /** 垫印章图时字高占印章边长的比例。 */
  capRatio: number = 0.62;

  identity(): string {
    return `${this.image}_${Math.round(this.aspect * 1000)}_${this.placement}_${this.scale}_${this.numberColor}_` +
      `${this.capLines}_${this.capRaise ? 1 : 0}_${this.capImage}_${this.capColor}_${this.capRatio}`;
  }
}

export class ReaderV2LayoutInput {
  viewportWidthPx: number = 0;
  viewportHeightPx: number = 0;
  safeTopPx: number = 0;
  safeBottomPx: number = 0;
  extendToStatusBar: boolean = false;
  marginLeftPx: number = 0;
  marginRightPx: number = 0;
  marginTopPx: number = 0;
  marginBottomPx: number = 0;
  bottomGuardPx: number = 0;
  columnGapPx: number = 0;
  columnCount: number = 1;
  fontSizePx: number = 40;
  fontWeight: number = ReaderFontWeight.DEFAULT;
  titleFontSizePx: number = 44;
  titleFontWeight: number = 600;
  titleSecondaryScale: number = 1.4;
  titleLineGapPx: number = 14;
  titleAlignment: string = 'center';
  titleMarginTopPx: number = 0;
  titleMarginBottomPx: number = 0;
  titleSinglePage: boolean = false;
  chapterHead: ReaderV2ChapterHeadStyle = new ReaderV2ChapterHeadStyle();
  lineSpacingPx: number = 0;
  paragraphSpacingPx: number = 0;
  letterSpacingPx: number = 0;
  textAlign: string = 'justify';
  bodyFontFamily: string = '';
  titleFontFamily: string = '';
  textColor: number = 0xFF202124;
  /** EPUB 注释编号的颜色。 */
  noteColor: number = 0xFF3A7BD5;
  commentBubble: ReaderCommentBubbleStyle = new ReaderCommentBubbleStyle();
  commentFontSizePx: number = 30;
  commentBubbleSize: number = ReaderCommentBubbleSize.DEFAULT;
  commentHitSlopXPx: number = 16;
  commentHitSlopYPx: number = 12;
  commentsEnabled: boolean = true;
  /** 热评卡片：0 关闭，1 卡片，2 引文，3 挂件。见 ReaderCommentCardSettings。 */
  commentCardStyle: number = 0;
  /** 单独成段的本章说入口画成整宽卡片，与热评卡片样式无关。 */
  commentChapterCard: boolean = false;
  /** 每页最多几张段评热评卡，0 不限。 */
  commentCardMaxPerPage: number = 0;
  commentCardLines: number = 1;
  commentCardFontSizePx: number = 30;
  /** 卡片上“热评”标签的颜色。 */
  commentCardTagColor: number = 0xFFC4473A;
  regexEnabled: boolean = false;
  /** 图片原始像素按 vp 解释，这里是 1vp 对应的物理像素。 */
  imagePxPerVp: number = 1;
  /** 整页插图与正文同页时允许的最小高度。 */
  imageMinHeightPx: number = 0;
  styleIdentity: string = '';
}

export class ReaderV2LayoutSnapshot {
  /** Font-box centres relative to the baseline, scoped to this layout/font snapshot. */
  commentTextCenters: Map<string, number> = new Map<string, number>();
  commentTextWidths: Map<string, number> = new Map<string, number>();
  viewport: ReaderV2Rect = new ReaderV2Rect();
  contentRect: ReaderV2Rect = new ReaderV2Rect();
  columnRects: ReaderV2Rect[] = [];
  extendToStatusBar: boolean = false;
  fontSizePx: number = 40;
  fontWeight: number = ReaderFontWeight.DEFAULT;
  titleFontSizePx: number = 44;
  titleFontWeight: number = 600;
  titleSecondaryScale: number = 1.4;
  titleLineGapPx: number = 14;
  titleAlignment: string = 'center';
  titleMarginTopPx: number = 0;
  titleMarginBottomPx: number = 0;
  titleSinglePage: boolean = false;
  chapterHead: ReaderV2ChapterHeadStyle = new ReaderV2ChapterHeadStyle();
  lineSpacingPx: number = 0;
  paragraphSpacingPx: number = 0;
  letterSpacingPx: number = 0;
  textAlign: string = 'justify';
  bodyFontFamily: string = '';
  titleFontFamily: string = '';
  textColor: number = 0xFF202124;
  /** EPUB 注释编号的颜色。 */
  noteColor: number = 0xFF3A7BD5;
  commentBubble: ReaderCommentBubbleStyle = new ReaderCommentBubbleStyle();
  commentFontSizePx: number = 30;
  commentBubbleSize: number = ReaderCommentBubbleSize.DEFAULT;
  commentHitSlopXPx: number = 16;
  commentHitSlopYPx: number = 12;
  commentsEnabled: boolean = true;
  commentCardStyle: number = 0;
  commentChapterCard: boolean = false;
  commentCardMaxPerPage: number = 0;
  commentCardLines: number = 1;
  commentCardFontSizePx: number = 30;
  commentCardTagColor: number = 0xFFC4473A;
  regexEnabled: boolean = false;
  imagePxPerVp: number = 1;
  imageMinHeightPx: number = 0;
  identity: string = '';

  static create(input: ReaderV2LayoutInput): ReaderV2LayoutSnapshot {
    const snapshot = new ReaderV2LayoutSnapshot();
    const width = Math.max(1, input.viewportWidthPx);
    const height = Math.max(1, input.viewportHeightPx);
    snapshot.viewport = new ReaderV2Rect(0, 0, width, height);
    snapshot.extendToStatusBar = input.extendToStatusBar;

    const safeTop = input.extendToStatusBar ? 0 : Math.max(0, input.safeTopPx);
    const safeBottom = input.extendToStatusBar ? 0 : Math.max(0, input.safeBottomPx);
    const left = Math.max(0, input.marginLeftPx);
    const top = safeTop + Math.max(0, input.marginTopPx);
    const right = Math.max(left + 1, width - Math.max(0, input.marginRightPx));
    const bottom = Math.max(top + 1, height - safeBottom - Math.max(0, input.bottomGuardPx) -
      Math.max(0, input.marginBottomPx));
    snapshot.contentRect = new ReaderV2Rect(left, top, right, bottom);

    const columnCount = Math.max(1, Math.min(2, Math.round(input.columnCount)));
    const gap = columnCount > 1 ? Math.max(0, input.columnGapPx) : 0;
    const columnWidth = Math.max(1, (snapshot.contentRect.width() - gap) / columnCount);
    for (let index = 0; index < columnCount; index++) {
      const columnLeft = snapshot.contentRect.left + index * (columnWidth + gap);
      snapshot.columnRects.push(new ReaderV2Rect(columnLeft, snapshot.contentRect.top,
        columnLeft + columnWidth, snapshot.contentRect.bottom));
    }

    snapshot.fontSizePx = Math.max(1, input.fontSizePx);
    snapshot.fontWeight = ReaderFontWeight.normalize(input.fontWeight);
    snapshot.titleFontSizePx = Math.max(1, input.titleFontSizePx);
    snapshot.titleFontWeight = ReaderFontWeight.normalize(input.titleFontWeight ?? 600);
    snapshot.titleSecondaryScale = Number.isFinite(input.titleSecondaryScale) ?
      Math.max(0.5, Math.min(2, input.titleSecondaryScale)) : 1.4;
    snapshot.titleLineGapPx = Number.isFinite(input.titleLineGapPx) ? Math.max(0, input.titleLineGapPx) : 14;
    snapshot.titleAlignment = input.titleAlignment === 'left' || input.titleAlignment === 'right' ?
      input.titleAlignment : 'center';
    snapshot.titleMarginTopPx = Number.isFinite(input.titleMarginTopPx) ? Math.max(0, input.titleMarginTopPx) : 0;
    snapshot.titleMarginBottomPx = Number.isFinite(input.titleMarginBottomPx) ? Math.max(0, input.titleMarginBottomPx) : 0;
    snapshot.titleSinglePage = input.titleSinglePage === true;
    snapshot.chapterHead = input.chapterHead || new ReaderV2ChapterHeadStyle();
    snapshot.lineSpacingPx = Math.max(0, input.lineSpacingPx);
    snapshot.paragraphSpacingPx = Math.max(0, input.paragraphSpacingPx);
    snapshot.letterSpacingPx = input.letterSpacingPx;
    snapshot.textAlign = input.textAlign === 'start' || input.textAlign === 'end' ? input.textAlign : 'justify';
    snapshot.bodyFontFamily = input.bodyFontFamily;
    snapshot.titleFontFamily = input.titleFontFamily || input.bodyFontFamily;
    snapshot.textColor = input.textColor;
    snapshot.noteColor = input.noteColor;
    snapshot.commentBubble = input.commentBubble;
    snapshot.commentBubbleSize = ReaderCommentBubbleSize.normalize(input.commentBubbleSize);
    snapshot.commentFontSizePx = Math.max(1, input.commentFontSizePx);
    snapshot.commentHitSlopXPx = Math.max(0, input.commentHitSlopXPx);
    snapshot.commentHitSlopYPx = Math.max(0, input.commentHitSlopYPx);
    snapshot.commentsEnabled = input.commentsEnabled;
    snapshot.commentCardStyle = input.commentCardStyle >= 0 && input.commentCardStyle <= 3 ?
      Math.round(input.commentCardStyle) : 0;
    snapshot.commentChapterCard = input.commentChapterCard === true;
    snapshot.commentCardMaxPerPage = Math.max(0, Math.round(input.commentCardMaxPerPage));
    snapshot.commentCardLines = input.commentCardLines === 2 ? 2 : 1;
    snapshot.commentCardFontSizePx = Math.max(1, input.commentCardFontSizePx);
    snapshot.commentCardTagColor = input.commentCardTagColor;
    snapshot.regexEnabled = input.regexEnabled;
    snapshot.imagePxPerVp = Math.max(0.01, input.imagePxPerVp);
    snapshot.imageMinHeightPx = Math.max(0, input.imageMinHeightPx);
    snapshot.identity = ReaderV2LayoutSnapshot.buildIdentity(input, snapshot);
    return snapshot;
  }

  private static buildIdentity(input: ReaderV2LayoutInput, snapshot: ReaderV2LayoutSnapshot): string {
    const values = [
      snapshot.viewport.width(), snapshot.viewport.height(), snapshot.contentRect.left, snapshot.contentRect.top,
      snapshot.contentRect.right, snapshot.contentRect.bottom, snapshot.columnRects.length,
      snapshot.fontSizePx, snapshot.fontWeight, snapshot.titleFontSizePx, snapshot.titleFontWeight, snapshot.lineSpacingPx, snapshot.paragraphSpacingPx,
      snapshot.titleSecondaryScale, snapshot.titleLineGapPx,
      snapshot.titleAlignment, snapshot.titleMarginTopPx, snapshot.titleMarginBottomPx,
      snapshot.titleSinglePage ? 1 : 0, snapshot.chapterHead.identity(),
      snapshot.letterSpacingPx, snapshot.textAlign, snapshot.noteColor, snapshot.commentFontSizePx, snapshot.commentBubbleSize, snapshot.commentBubble.identity(),
      snapshot.commentsEnabled ? 1 : 0, snapshot.regexEnabled ? 1 : 0,
      snapshot.commentCardStyle, snapshot.commentCardMaxPerPage, snapshot.commentCardLines,
      snapshot.commentCardFontSizePx, snapshot.commentCardTagColor, snapshot.commentChapterCard ? 1 : 0,
      // 排法的版本：改了卡片的留白、本章说或段间距的算法就换一个值，让按排版标识存下来的分页结果失效。
      'cardgap3-chapter2-emoji1-pjoin2-psqueeze1'
    ];
    const rounded = values.map((value: string | number): string =>
      typeof value === 'number' ? `${Math.round(value * 100) / 100}` : value).join('_');
    return `reader_layout_v2_${rounded}_${input.bodyFontFamily}_${input.titleFontFamily}_${input.styleIdentity}`;
  }
}
