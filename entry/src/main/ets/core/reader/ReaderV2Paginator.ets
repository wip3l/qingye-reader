import graphicsText from '@ohos.graphics.text';
import common2D from '@ohos.graphics.common2D';
import { ReaderV2Block, ReaderV2Document, ReaderV2InlineAction } from './ReaderV2Document';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import {
  ReaderV2ActionHitArea,
  ReaderV2PageDecoration,
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2PageSet,
  ReaderV2CommentBubbleSegment,
  ReaderV2RegexBubbleSegment,
  ReaderV2SelectionRun
} from './ReaderV2PageLayout';
import { ReaderV2BubbleFrame, ReaderV2SpanStyleRange } from './ReaderV2Style';
import { ReaderCommentBubbleSize } from './ReaderCommentBubbleSize';
import { ReaderCommentBubblePainter } from './ReaderCommentBubble';
import { ReaderMixedPageLayout } from './ReaderMixedPageLayout';
import { ReaderFontWeight } from './ReaderFontWeight';
import { ReaderFontStroke } from './ReaderFontStroke';
import { ReaderPunctuationSqueeze } from './ReaderPunctuationSqueeze';
import { ReaderPunctuationMetrics } from './ReaderPunctuationMetrics';
import { ReaderFrontPage } from './ReaderFrontPage';
import { ReaderChapterEnd } from './ReaderChapterEnd';
import { EpubNoteLink } from '../book/EpubNoteLink';
import { ReaderV2CommentCardLayout } from './ReaderV2CommentCard';
import { ReaderV2ChapterHeadLayout, ReaderV2ChapterHeadMetrics } from './ReaderV2ChapterHead';

class ReaderV2MeasuredBlock {
  block: ReaderV2Block;
  paragraph: graphicsText.Paragraph;
  lineCount: number;
  /** The paragraph covers block.text[sliceStart, sliceEnd); line indices are relative to sliceStart. */
  sliceStart: number = 0;
  sliceEnd: number = 0;
  /** Width the slice was laid out at and its left offset inside the column (drop-cap lines are narrower). */
  widthPx: number = 0;
  leadPx: number = 0;
  /** 排这一段时正文行距上加的页底对齐份额；和当前这一遍不一样就要重排。 */
  stretchPx: number = 0;
  private lines: Map<number, graphicsText.LineMetrics> = new Map<number, graphicsText.LineMetrics>();

  constructor(block: ReaderV2Block, paragraph: graphicsText.Paragraph) {
    this.block = block;
    this.paragraph = paragraph;
    this.lineCount = paragraph.getLineCount();
    this.sliceEnd = block.text.length;
  }

  line(index: number): graphicsText.LineMetrics {
    const cached = this.lines.get(index);
    if (cached) return cached;
    const startedAt = Date.now();
    const metric = this.paragraph.getLineMetrics(index);
    ReaderV2Paginator.onWorkMeasured?.('line-metrics', Date.now() - startedAt);
    if (!metric) throw new Error(`Missing native line metrics at ${index}`);
    this.lines.set(index, metric);
    return metric;
  }
}

/**
 * 首字装饰的排法：首字单独画在段落左上角的方框里（不属于任何片段），首段拆成两截——绕着方框排的前
 * wrapLines 行（宽度让出 reservePx），和回到整行宽度的其余部分。两截都是同一块的切片，和跨页拆段是同一套机制。
 * 下沉时方框占前 lines 行；放大时方框一样高，但底边对齐第一行文字、向上抬出，只有第一行绕排，
 * 首段前面多留 risePx 给抬出的那部分。
 */
class ReaderV2DropCapPlan {
  blockIndex: number = -1;
  char: string = '';
  /** 首字之后第一个字、两截的分界在块内的下标；splitAt 等于块长时没有第二截。 */
  bodyStart: number = 0;
  splitAt: number = 0;
  /** 方框高几行。 */
  lines: number = 2;
  /** 绕着方框排的行数：下沉等于 lines，放大为 1。 */
  wrapLines: number = 2;
  /** 放大时首段前多留的高度（方框抬出第一行的部分）；下沉为 0。 */
  risePx: number = 0;
  /** 行与行的基线间距。 */
  pitchPx: number = 0;
  boxPx: number = 0;
  /** 方框上边相对第一行行框顶边的偏移。 */
  boxTopPx: number = 0;
  reservePx: number = 0;
}

/** 排一页的中间结果：片段已放好，还没做页底对齐和收尾。 */
class ReaderV2PageDraft {
  page: ReaderV2PageLayout = new ReaderV2PageLayout();
  hasContent: boolean = false;
  titlePageBoundary: boolean = false;
  /** 最后一块的底边。 */
  y: number = 0;
  /** Index of the first hit area each fragment contributed, so fragments can be moved with their areas. */
  fragmentActionStarts: number[] = [];
  /** 本页正文的行间数：段内相邻两行，加上按行距相接的两段之间。 */
  lineGaps: number = 0;
}

class ReaderV2ParagraphJoin {
  joinPx: number = 0;
  sliceLeadPx: number = 0;
}

/** A page transaction suspends here until the system has laid out its next paragraph asynchronously. */
class ReaderV2PendingLayout extends Error {
  key: string;
  paragraph: graphicsText.Paragraph;
  width: number;

  constructor(key: string, paragraph: graphicsText.Paragraph, width: number) {
    super('Reader paragraph layout pending');
    this.key = key;
    this.paragraph = paragraph;
    this.width = width;
  }
}

class ReaderV2ParagraphCache {
  ready: Map<string, graphicsText.Paragraph> = new Map<string, graphicsText.Paragraph>();
  measurements: Map<graphicsText.Paragraph, ReaderV2MeasuredBlock> =
    new Map<graphicsText.Paragraph, ReaderV2MeasuredBlock>();
}

/** Retains the page cursor and native paragraphs across asynchronous layout transactions. */
export class ReaderV2PaginationSession {
  document: ReaderV2Document;
  snapshot: ReaderV2LayoutSnapshot;
  regexStyles: ReaderV2SpanStyleRange[];
  pageSet: ReaderV2PageSet = new ReaderV2PageSet();
  width: number = 0;
  blockIndex: number = 0;
  /** -1：当前块的文字已排完，段末热评卡还没放（可能挪到下一页开头）。 */
  lineIndex: number = 0;
  pageIndex: number = 0;
  measuredBlock: ReaderV2MeasuredBlock | null = null;
  paragraphCache: ReaderV2ParagraphCache | null = null;
  inFlight: Promise<number> | null = null;
  cancelled: boolean = false;
  /** 整章只有图片（封面页、插图页）：整页插图铺满页面，不留正文边距。 */
  imageOnly: boolean = false;
  /** 滚动阅读：整份文档排成一页，不受页高限制。 */
  continuous: boolean = false;
  /** 章首饰图占的空间；标题上下边距已把它要的那部分加进去。 */
  chapterHead: ReaderV2ChapterHeadMetrics = new ReaderV2ChapterHeadMetrics();
  titleMarginTopPx: number = 0;
  titleMarginBottomPx: number = 0;
  /** 首字装饰：解析过一次后不再变（null 表示这一章不做）；dropPart 是首段当前排到第几截。 */
  dropCap: ReaderV2DropCapPlan | null = null;
  dropCapResolved: boolean = false;
  dropPart: number = 0;
  /** 页底对齐：当前这一遍给正文每处行间加的距离，只在重排那一页时不为 0。 */
  lineStretchPx: number = 0;
  /** 书封扉页已排出（翻页模式是单独一页，滚动阅读是第一页顶上的一屏）。 */
  frontDone: boolean = false;
  private blockStyles: ReaderV2SpanStyleRange[] = [];
  private blockStylesIndex: number = -1;

  /**
   * Regex styles overlapping the current block, in their original order. Every style lookup below is
   * block-local, so scanning the whole chapter's styles per boundary made pagination O(blocks × styles).
   */
  currentBlockStyles(): ReaderV2SpanStyleRange[] {
    if (this.regexStyles.length === 0) return this.regexStyles;
    if (this.blockStylesIndex !== this.blockIndex) {
      const block = this.document.blocks[this.blockIndex];
      const blockEnd = block.displayStart + block.text.length;
      this.blockStyles = this.regexStyles.filter((style: ReaderV2SpanStyleRange): boolean =>
        style.end > block.displayStart && style.start < blockEnd);
      this.blockStylesIndex = this.blockIndex;
    }
    return this.blockStyles;
  }

  constructor(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[]) {
    this.document = document;
    this.snapshot = snapshot;
    this.regexStyles = regexStyles;
    this.pageSet.documentIdentity = document.identity;
    this.pageSet.layoutIdentity = snapshot.identity;
    this.width = snapshot.columnRects.length > 0 ? snapshot.columnRects[0].width() : 0;
    this.chapterHead = ReaderV2ChapterHeadLayout.metrics(snapshot, document.titleBlockCount(), this.width);
    this.titleMarginTopPx = snapshot.titleMarginTopPx + this.chapterHead.extraTopPx;
    this.titleMarginBottomPx = snapshot.titleMarginBottomPx + this.chapterHead.extraBottomPx;
    this.pageSet.complete = document.blocks.length === 0 || snapshot.columnRects.length === 0;
    this.imageOnly = document.blocks.length > 0 &&
      document.blocks.every((block: ReaderV2Block): boolean => !!block.image);
  }
}

export class ReaderV2Paginator {
  /** Optional benchmark probe; inactive during ordinary reading. Durations are synchronous CPU sections. */
  static onWorkMeasured: ((stage: string, elapsedMs: number) => void) | null = null;
  /** Measures a plain selectable surface with the same native paragraph engine as pagination. */
  static glyphPositionForPlainText(text: string, snapshot: ReaderV2LayoutSnapshot,
    width: number, x: number, y: number): number {
    if (!text) return 0;
    const document = new ReaderV2Document();
    document.sourceText = text;
    document.displayText = text;
    const block = new ReaderV2Block('selection', text, 0, text.length, 0, text.length, false);
    const paragraph = ReaderV2Paginator.buildParagraph(document, block, snapshot, [], Math.max(1, width),
      0, text.length);
    return paragraph.getGlyphPositionAtCoordinate(Math.max(0, x), Math.max(0, y)).position;
  }

  static paginate(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = []): ReaderV2PageSet {
    const session = ReaderV2Paginator.start(document, snapshot, regexStyles);
    while (!session.pageSet.complete) {
      const appended = ReaderV2Paginator.appendPages(session, 32);
      if (appended <= 0) break;
    }
    return session.pageSet;
  }

  /**
   * Lays the whole document out as one unbounded column for continuous scrolling. The caller sizes its
   * list item from contentBottomPx; every other field has the same meaning as on a paged layout.
   */
  static layoutContinuous(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = [],
    paragraphCache: ReaderV2ParagraphCache | null = null): ReaderV2PageLayout | null {
    const session = new ReaderV2PaginationSession(document, snapshot, regexStyles);
    session.continuous = true;
    session.paragraphCache = paragraphCache;
    ReaderV2Paginator.appendPages(session, 1);
    return session.pageSet.pages.length > 0 ? session.pageSet.pages[0] : null;
  }

  static start(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = []): ReaderV2PaginationSession {
    return new ReaderV2PaginationSession(document, snapshot, regexStyles);
  }

  static async layoutContinuousAsync(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = [],
    isCurrent: () => boolean = (): boolean => true): Promise<ReaderV2PageLayout | null> {
    const session = ReaderV2Paginator.start(document, snapshot, regexStyles);
    session.continuous = true;
    await ReaderV2Paginator.appendPageAsync(session, isCurrent);
    return isCurrent() && session.pageSet.pages.length > 0 ? session.pageSet.pages[0] : null;
  }

  /**
   * Reuse the exact synchronous page-breaking algorithm, but make native layout a suspension point.
   * Nothing is published until a complete page exists. Retrying from the page checkpoint reuses every
   * already-shaped paragraph, including page slices, outline runs and scaled standalone titles.
   * The cache only lives for this page; published fragments own their native paragraph references.
   */
  /**
   * beforeWork runs before every synchronous page-breaking attempt (each attempt follows one native layout and
   * can take several milliseconds). The host uses it to park that work in a frame's idle slot while a page turn
   * is animating; a call already in flight keeps the yield policy it started with.
   */
  static appendPageAsync(session: ReaderV2PaginationSession,
    isCurrent: () => boolean = (): boolean => true,
    beforeWork: (() => Promise<void>) | null = null): Promise<number> {
    if (session.inFlight) return session.inFlight;
    const work = ReaderV2Paginator.preparePageAsync(session, isCurrent, beforeWork);
    session.inFlight = work;
    return work.finally((): void => {
      if (session.inFlight === work) session.inFlight = null;
    });
  }

  private static async preparePageAsync(session: ReaderV2PaginationSession,
    isCurrent: () => boolean, beforeWork: (() => Promise<void>) | null): Promise<number> {
    if (session.cancelled || session.pageSet.complete || !isCurrent()) return 0;
    const blockIndex = session.blockIndex;
    const lineIndex = session.lineIndex;
    const pageIndex = session.pageIndex;
    const measuredBlock = session.measuredBlock;
    const dropPart = session.dropPart;
    const cache = new ReaderV2ParagraphCache();
    session.paragraphCache = cache;
    const restore = (): void => {
      session.blockIndex = blockIndex;
      session.lineIndex = lineIndex;
      session.pageIndex = pageIndex;
      session.measuredBlock = measuredBlock;
      session.dropPart = dropPart;
    };
    try {
      while (!session.cancelled && isCurrent()) {
        if (beforeWork) {
          await beforeWork();
          if (session.cancelled || !isCurrent()) break;
        }
        restore();
        const workStartedAt = Date.now();
        try {
          const appended = ReaderV2Paginator.appendPages(session, 1);
          ReaderV2Paginator.onWorkMeasured?.('page', Date.now() - workStartedAt);
          return appended;
        } catch (error) {
          ReaderV2Paginator.onWorkMeasured?.('page', Date.now() - workStartedAt);
          restore();
          if (!(error instanceof ReaderV2PendingLayout)) throw error as Error;
          const pending = error as ReaderV2PendingLayout;
          await pending.paragraph.layout(pending.width);
          if (!session.cancelled && isCurrent()) cache.ready.set(pending.key, pending.paragraph);
        }
      }
      restore();
      return 0;
    } finally {
      session.paragraphCache = null;
      cache.ready.clear();
      cache.measurements.clear();
    }
  }

  static appendPages(session: ReaderV2PaginationSession, maxPages: number): number {
    const result = session.pageSet;
    if (result.complete || maxPages <= 0 || session.snapshot.columnRects.length === 0) return 0;
    const limit = Math.max(1, Math.round(maxPages));
    let appended = 0;
    while (session.blockIndex < session.document.blocks.length && appended < limit) {
      const columnIndex = session.pageIndex % session.snapshot.columnRects.length;
      const column = session.snapshot.columnRects[columnIndex];
      const front = session.document.frontPage;
      if (front !== null && !session.continuous && !session.frontDone && session.pageIndex === 0) {
        session.frontDone = true;
        const frontPage = ReaderFrontPage.page(front, session.snapshot, column, session.pageIndex, columnIndex);
        frontPage.identity = `${session.document.identity}_${session.snapshot.identity}_front_${front.identity()}`;
        result.pages.push(frontPage);
        session.pageIndex++;
        appended++;
        continue;
      }
      if (!session.continuous && session.snapshot.titleSinglePage &&
        session.document.blocks[session.blockIndex].title && session.lineIndex === 0) {
        const titlePage = ReaderV2Paginator.buildTitlePage(session, column);
        if (titlePage) {
          result.pages.push(titlePage);
          session.pageIndex++;
          appended++;
          continue;
        }
      }
      const draft = ReaderV2Paginator.layoutPageAligned(session, column, columnIndex);
      if (!draft.hasContent) break;
      const page = draft.page;
      const columnBottom = session.continuous ? Number.MAX_SAFE_INTEGER : column.bottom;
      const y = draft.y;
      ReaderV2Paginator.finalizePageSelection(page);
      for (const fragment of page.fragments) {
        page.contentBottomPx = Math.max(page.contentBottomPx, fragment.clipRect.bottom);
      }
      if (session.continuous && session.snapshot.titleSinglePage) {
        page.contentBottomPx = Math.max(page.contentBottomPx, y);
      }
      const lastFragment = page.fragments[page.fragments.length - 1];
      if (lastFragment.titleEnd && !session.snapshot.titleSinglePage && session.titleMarginBottomPx > 0) {
        page.contentBottomPx = Math.min(columnBottom, Math.max(page.contentBottomPx,
          lastFragment.paragraphY + lastFragment.paragraphHeight + session.titleMarginBottomPx));
      }
      // 单独成页的标题已在自己的排版里放好饰图（那里的字号可能缩过）。
      if (page.decorations.length === 0) {
        ReaderV2ChapterHeadLayout.place(page, session.snapshot, session.chapterHead, column);
      }
      ReaderV2Paginator.placeDropCap(page, session, column);
      if (session.continuous && front !== null && !session.frontDone && session.pageIndex === 0) {
        // 滚动阅读：正文从下移一屏处排起（见 continuousFrontInset），这里把扉页画进空出来的那一屏。
        session.frontDone = true;
        const area = new ReaderV2Rect(column.left, column.top, column.right, column.top + column.height());
        for (const decoration of ReaderFrontPage.decorations(front, session.snapshot, area)) {
          page.decorations.push(decoration);
        }
        page.contentBottomPx = Math.max(page.contentBottomPx, area.bottom);
      }
      const chapterEnd = session.document.chapterEnd;
      if (chapterEnd !== null && session.blockIndex >= session.document.blocks.length) {
        // 一章的最后一页：卡片只用正文下方的留白，放不下就不放，滚动阅读接在正文后面。
        const used = ReaderChapterEnd.place(page, chapterEnd, session.snapshot, column.left, column.right,
          page.contentBottomPx, session.continuous ? Number.POSITIVE_INFINITY : column.bottom - page.contentBottomPx);
        if (used > 0 && session.continuous) page.contentBottomPx += used;
      }
      page.sourceStart = session.document.sourceOffsetForDisplay(page.displayStart);
      page.sourceEnd = session.document.sourceOffsetForDisplay(page.displayEnd);
      page.identity = `${session.document.identity}_${session.snapshot.identity}_${session.pageIndex}_` +
        `${page.displayStart}_${page.displayEnd}`;
      result.pages.push(page);
      session.pageIndex++;
      appended++;
    }
    result.complete = session.blockIndex >= session.document.blocks.length;
    return appended;
  }

  /**
   * 排一页并把末行对到版心底边。一页排满后底部通常剩不到一行的空白，每页剩的还不一样；把它平均加到本页
   * 正文的每一处行间（段内的行与行、段与段），整页按加大后的行距重排一遍，断行和分页位置不变。
   * 这样段间距 0 时段与段之间仍和段内一样。重排后对不上原来的分页位置（行高取整等）就退一步用整数像素，
   * 再不行保留第一遍；余下的零头和不能重排的页（带首字装饰）加在段与段之间。
   */
  private static layoutPageAligned(session: ReaderV2PaginationSession, column: ReaderV2Rect,
    columnIndex: number): ReaderV2PageDraft {
    const startBlock = session.blockIndex;
    const startLine = session.lineIndex;
    const startPart = session.dropPart;
    const startMeasured = session.measuredBlock;
    let draft = ReaderV2Paginator.layoutPage(session, column, columnIndex);
    if (!draft.hasContent || session.continuous || draft.titlePageBoundary ||
      session.blockIndex >= session.document.blocks.length) {
      return draft;
    }
    // 后面还有内容：这一页是因为下一行放不下才结束的。
    const snapshot = session.snapshot;
    const leftover = column.bottom - draft.y;
    // 剩余超过两行说明这一页是被整页插图或放不下的大块提前结束的，不属于要对齐的情况。
    if (leftover <= 0.5 || leftover > (snapshot.fontSizePx + snapshot.lineSpacingPx) * 2) return draft;
    const paragraphGaps = ReaderV2Paginator.alignableGaps(draft.page);
    const hasDropCap = draft.page.fragments.some((fragment: ReaderV2PageFragment): boolean =>
      fragment.dropCapBoxPx > 0 || fragment.blockContinuation);
    // 摊到段间每处不到一像素时看不出来，不值得重排。
    if (draft.lineGaps > 0 && !hasDropCap && leftover > Math.max(2, paragraphGaps)) {
      const endBlock = session.blockIndex;
      const endLine = session.lineIndex;
      const endPart = session.dropPart;
      const endMeasured = session.measuredBlock;
      const exact = (leftover - 0.5) / draft.lineGaps;
      const candidates: number[] = [exact];
      if (Math.floor(exact) >= 1 && Math.floor(exact) < exact) candidates.push(Math.floor(exact));
      let aligned: ReaderV2PageDraft | null = null;
      try {
        for (const stretch of candidates) {
          session.blockIndex = startBlock;
          session.lineIndex = startLine;
          session.dropPart = startPart;
          session.measuredBlock = startMeasured;
          session.lineStretchPx = stretch;
          const retry = ReaderV2Paginator.layoutPage(session, column, columnIndex);
          if (retry.hasContent && session.blockIndex === endBlock && session.lineIndex === endLine &&
            session.dropPart === endPart && retry.y <= column.bottom + 0.01 &&
            retry.page.displayEnd === draft.page.displayEnd) {
            retry.page.lineStretchPx = stretch;
            aligned = retry;
            break;
          }
        }
      } finally {
        session.lineStretchPx = 0;
      }
      if (aligned) {
        draft = aligned;
        // 下一页按不加份额的行距重新量这一段。
        if (session.measuredBlock && session.measuredBlock.stretchPx !== 0) session.measuredBlock = null;
      } else {
        session.blockIndex = endBlock;
        session.lineIndex = endLine;
        session.dropPart = endPart;
        session.measuredBlock = endMeasured;
      }
    }
    ReaderV2Paginator.alignPageBottom(draft.page, draft.fragmentActionStarts, column.bottom - draft.y, snapshot);
    return draft;
  }

  /** 滚动阅读的第一章：正文下移一屏，给书封扉页让位。 */
  private static continuousFrontInset(session: ReaderV2PaginationSession, column: ReaderV2Rect): number {
    return session.continuous && session.document.frontPage !== null && !session.frontDone && session.pageIndex === 0 ?
      column.height() : 0;
  }

  /** 按当前光标排出一页的片段，不做页底对齐；session.lineStretchPx 是这一遍给正文行间加的距离。 */
  private static layoutPage(session: ReaderV2PaginationSession, column: ReaderV2Rect,
    columnIndex: number): ReaderV2PageDraft {
    const draft = new ReaderV2PageDraft();
    {
      const page = draft.page;
      page.pageIndex = session.pageIndex;
      page.columnIndex = columnIndex;
      page.contentRect = new ReaderV2Rect(column.left, column.top, column.right, column.bottom);
      const columnBottom = session.continuous ? Number.MAX_SAFE_INTEGER : column.bottom;
      let y = column.top + ReaderV2Paginator.continuousFrontInset(session, column);
      let hasContent = false;
      let topInkGuardApplied = false;
      let mustEndPage = false;
      let previousWasImage = false;
      let titlePageBoundary = false;
      // Top of the drop-cap paragraph's first line when its wrapped lines were placed on this page.
      let dropLeadTop = Number.NaN;
      // Index of the first hit area each fragment contributed, so fragments can be moved with their areas.
      const fragmentActionStarts = draft.fragmentActionStarts;
      // Paragraph hot-comment cards placed in the current page (or, while scrolling, the current screen height).
      let cardWindow = 0;
      let cardsInWindow = 0;
      // The fragment just placed is a comment card; cardEdgeGap is the visible gap that card group got above it.
      let previousWasCard = false;
      let cardEdgeGap = 0;
      // Page y of the glyph ink bottom of the last text line placed, NaN when the previous fragment is not text.
      let lastInkBottom = Number.NaN;
      const cardsEnabled = session.snapshot.commentsEnabled && session.snapshot.commentCardStyle > 0;
      const chapterCardsEnabled = session.snapshot.commentsEnabled && session.snapshot.commentChapterCard;

      while (session.blockIndex < session.document.blocks.length && !mustEndPage) {
        const imageBlock = session.document.blocks[session.blockIndex];
        const pendingCard = session.lineIndex < 0;
        if (pendingCard || (imageBlock.card && session.lineIndex === 0 &&
          (imageBlock.card.chapter ? chapterCardsEnabled : cardsEnabled))) {
          // A hot-comment card: either a whole source card paragraph, or the card after a paragraph's last line.
          const action = pendingCard ? imageBlock.trailingCard : imageBlock.card;
          const windowIndex = session.continuous ?
            Math.floor(Math.max(0, y - column.top) / Math.max(1, column.height())) : 0;
          if (windowIndex !== cardWindow) {
            cardWindow = windowIndex;
            cardsInWindow = 0;
          }
          const capped = pendingCard && session.snapshot.commentCardMaxPerPage > 0 &&
            cardsInWindow >= session.snapshot.commentCardMaxPerPage;
          if (!action || capped) {
            session.blockIndex++;
            session.lineIndex = 0;
            session.measuredBlock = null;
            continue;
          }
          // Cards keep the same visible distance to the text above and below, measured from the glyph ink rather
          // than the line box (whose trailing line spacing and font padding differ between the two sides).
          let gap = 0;
          if (previousWasCard) {
            gap = ReaderV2CommentCardLayout.stackGap(session.snapshot);
          } else if (hasContent) {
            const edge = ReaderV2CommentCardLayout.edgeGap(session.snapshot, action.chapter);
            const belowInk = Number.isNaN(lastInkBottom) ? 0 : Math.max(0, y - lastInkBottom);
            gap = Math.max(0, edge - belowInk);
            cardEdgeGap = belowInk + gap;
          } else {
            cardEdgeGap = ReaderV2CommentCardLayout.edgeGap(session.snapshot, action.chapter);
          }
          const anchor = pendingCard ? ReaderV2Paginator.bubbleCenterX(page, action.id) - column.left : -1;
          // 一章末尾的本章说包进章末卡片：往里收卡片的左右内边距、往下让出上内边距，卡片底板从 y + gap 起。
          const chapterEnd = session.document.chapterEnd;
          const wrapChapter = action.chapter && chapterEnd !== null &&
            session.blockIndex === session.document.blocks.length - 1;
          const wrapInset = wrapChapter ? ReaderChapterEnd.wrapInsetX(session.snapshot) : 0;
          const cardWidth = session.width - wrapInset * 2;
          let card = ReaderV2CommentCardLayout.build(action, session.snapshot, cardWidth,
            anchor >= 0 ? anchor : -1);
          const top = y + gap + (wrapChapter ? ReaderChapterEnd.wrapPadTop(session.snapshot) : 0);
          if (action.chapter) {
            // 本章说放不下时先少列几条热评，最后只留标题行；还放不下才整块挪到下一页。
            // 包进章末卡片时先试着给卡片的“读完 + 下一章”留出位置，留不出就照原样只排本章说。
            const maxHots = Math.min(action.hots.length, ReaderV2CommentCardLayout.CHAPTER_MAX_HOTS);
            let hotCount = maxHots;
            const reserve = wrapChapter && chapterEnd !== null && !session.continuous ?
              ReaderChapterEnd.minTailHeight(chapterEnd, session.snapshot, session.width) : 0;
            let reserved = reserve > 0;
            while (hotCount > 0 && top + card.height > columnBottom - reserve + 0.01) {
              hotCount--;
              card = ReaderV2CommentCardLayout.build(action, session.snapshot, cardWidth, -1, hotCount);
            }
            if (reserved && top + card.height > columnBottom - reserve + 0.01) {
              reserved = false;
              hotCount = maxHots;
              card = ReaderV2CommentCardLayout.build(action, session.snapshot, cardWidth, -1, hotCount);
              while (hotCount > 0 && top + card.height > columnBottom + 0.01) {
                hotCount--;
                card = ReaderV2CommentCardLayout.build(action, session.snapshot, cardWidth, -1, hotCount);
              }
            }
          }
          if (hasContent && top + card.height > columnBottom + 0.01) {
            mustEndPage = true;
            continue;
          }
          const cardFragment = new ReaderV2PageFragment();
          cardFragment.blockId = imageBlock.id;
          cardFragment.blockIndex = session.blockIndex;
          cardFragment.card = card;
          // Keep a trailing card attached to its paragraph when the page bottom is aligned.
          cardFragment.fixedGapBefore = hasContent;
          cardFragment.paragraphX = column.left + wrapInset;
          cardFragment.paragraphY = top;
          cardFragment.paragraphHeight = card.height;
          cardFragment.clipRect = new ReaderV2Rect(column.left + wrapInset, top, column.right - wrapInset,
            top + card.height);
          if (wrapChapter) page.chapterEndWrapTop = y + gap;
          cardFragment.displayStart = pendingCard ? imageBlock.displayEnd : imageBlock.displayStart;
          cardFragment.displayEnd = imageBlock.displayEnd;
          fragmentActionStarts.push(page.actions.length);
          page.fragments.push(cardFragment);
          const hit = new ReaderV2ActionHitArea();
          hit.actionId = action.id;
          hit.marker = action.marker;
          hit.rect = new ReaderV2Rect(column.left + wrapInset + card.box.left, top + card.box.top - card.tailSize,
            column.left + wrapInset + card.box.right, top + card.box.bottom);
          page.actions.push(hit);
          if (!hasContent) page.displayStart = cardFragment.displayStart;
          page.displayEnd = Math.max(page.displayEnd, cardFragment.displayEnd);
          if (pendingCard) cardsInWindow++;
          hasContent = true;
          topInkGuardApplied = true;
          previousWasImage = false;
          previousWasCard = true;
          lastInkBottom = Number.NaN;
          y = top + card.height;
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
          continue;
        }
        if (session.snapshot.titleSinglePage && imageBlock.title && session.lineIndex === 0) {
          if (!session.continuous && hasContent) {
            titlePageBoundary = true;
            break;
          }
          if (session.continuous) {
            const titlePage = ReaderV2Paginator.buildTitlePage(session, column);
            if (titlePage) {
              const titleTop = hasContent ? column.top +
                Math.ceil(Math.max(0, y - column.top) / column.height()) * column.height() : column.top;
              ReaderV2Paginator.shiftTitlePage(titlePage, titleTop - column.top);
              if (!hasContent) page.displayStart = titlePage.displayStart;
              page.displayEnd = titlePage.displayEnd;
              for (const fragment of titlePage.fragments) {
                fragmentActionStarts.push(page.actions.length);
                page.fragments.push(fragment);
              }
              page.actions.push(...titlePage.actions);
              page.decorations.push(...titlePage.decorations);
              y = titleTop + column.height();
              hasContent = true;
              topInkGuardApplied = true;
              previousWasImage = false;
              previousWasCard = false;
              lastInkBottom = Number.NaN;
              continue;
            }
          }
        }
        if (imageBlock.image) {
          // Image sizing rules live in ReaderMixedPageLayout: small images flow with the text at
          // their natural size; illustrations and images of unknown size fill the rest of the page and end it.
          const followsTitle = session.blockIndex > 0 && session.document.blocks[session.blockIndex - 1].title;
          const gap = hasContent && !(followsTitle && session.snapshot.titleSinglePage) ?
            ReaderV2Paginator.imageGap(session.snapshot) +
            (followsTitle ? session.titleMarginBottomPx : 0) : 0;
          const remaining = columnBottom - y - gap;
          const natural = ReaderMixedPageLayout.naturalBoxForSize(imageBlock.image.width, imageBlock.image.height,
            session.width, column.height(), session.snapshot.imagePxPerVp);
          let imageRect: ReaderV2Rect;
          let endsPage = false;
          if (natural && !natural.fill) {
            if (hasContent && natural.heightPx > remaining + 0.01) {
              mustEndPage = true;
              continue;
            }
            const left = column.left + Math.max(0, (session.width - natural.widthPx) / 2);
            imageRect = new ReaderV2Rect(left, y + gap, left + natural.widthPx, y + gap + natural.heightPx);
          } else {
            const wanted = natural ?
              Math.min(natural.heightPx, column.height()) * ReaderMixedPageLayout.FILL_MIN_RATIO : 0;
            if (!session.continuous && hasContent &&
              remaining < Math.max(session.snapshot.imageMinHeightPx, wanted)) {
              mustEndPage = true;
              continue;
            }
            const viewport = session.snapshot.viewport;
            if (session.continuous) {
              const height = natural ? Math.min(natural.heightPx, column.height()) :
                session.width * ReaderV2Paginator.CONTINUOUS_UNKNOWN_IMAGE_ASPECT;
              imageRect = new ReaderV2Rect(column.left, y + gap, column.right, y + gap + height);
            } else {
              imageRect = session.imageOnly && !hasContent ?
                new ReaderV2Rect(viewport.left, viewport.top, viewport.right, columnBottom) :
                new ReaderV2Rect(column.left, y + gap, column.right, columnBottom);
              endsPage = true;
            }
          }
          const imageFragment = new ReaderV2PageFragment();
          imageFragment.fixedGapBefore = hasContent && followsTitle && session.titleMarginBottomPx > 0;
          imageFragment.blockId = imageBlock.id;
          imageFragment.blockIndex = session.blockIndex;
          imageFragment.imageSource = imageBlock.image.source;
          imageFragment.imageRect = imageRect;
          imageFragment.paragraphX = imageRect.left;
          imageFragment.paragraphY = imageRect.top;
          imageFragment.paragraphHeight = imageRect.height();
          imageFragment.clipRect = imageRect;
          imageFragment.localStart = 0;
          imageFragment.localEnd = imageBlock.text.length;
          imageFragment.displayStart = imageBlock.displayStart;
          imageFragment.displayEnd = imageBlock.displayEnd;
          fragmentActionStarts.push(page.actions.length);
          page.fragments.push(imageFragment);
          if (!hasContent) page.displayStart = imageFragment.displayStart;
          page.displayEnd = imageFragment.displayEnd;
          hasContent = true;
          previousWasImage = true;
          previousWasCard = false;
          lastInkBottom = Number.NaN;
          y = imageRect.bottom;
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
          mustEndPage = endsPage;
          continue;
        }

        let current = session.measuredBlock;
        if (!current || current.block !== session.document.blocks[session.blockIndex] ||
          current.stretchPx !== ReaderV2Paginator.blockStretch(current.block, session)) {
          current = ReaderV2Paginator.measureCurrent(session);
          session.measuredBlock = current;
        }
        if (current.lineCount === 0) {
          session.blockIndex++;
          session.lineIndex = 0;
          session.dropPart = 0;
          session.measuredBlock = null;
          continue;
        }

        const drop = session.dropCap && session.dropCap.blockIndex === session.blockIndex ? session.dropCap : null;
        // The second slice of a drop-cap paragraph continues the same paragraph: no paragraph gap before it.
        const dropRest = !!drop && session.dropPart === 1;
        const startsNewBlock = session.lineIndex === 0 && !dropRest;
        let spacing = startsNewBlock ? ReaderV2Paginator.blockSpacingBefore(session, hasContent, previousWasImage) : 0;
        let joinsText = startsNewBlock && ReaderV2Paginator.joinsBodyText(session, hasContent, previousWasImage);
        if (dropRest && session.lineIndex === 0 && !Number.isNaN(dropLeadTop) && drop) {
          // Keep the paragraph's own line pitch across the two slices.
          spacing = Math.max(0, dropLeadTop + drop.wrapLines * drop.pitchPx - y);
        }
        const firstLine = current.line(session.lineIndex);
        const followsCard = previousWasCard && startsNewBlock && hasContent && !current.block.title;
        if (followsCard) {
          // Mirror the gap the card group has above it.
          const ink = ReaderV2Paginator.lineInk(current, session.lineIndex, session.snapshot);
          spacing = Math.max(0, cardEdgeGap - (ink ? ink.top - firstLine.topHeight : 0));
          joinsText = false;
        }
        if (!hasContent && !topInkGuardApplied) {
          // A zero user margin places the first logical line box on the page boundary. Some fonts (notably the
          // serif family used by several themes) paint one or two physical pixels above that logical box. The
          // render node cannot draw outside its own surface, so those pixels used to be clipped. Reserve exactly
          // the measured ink overflow plus one anti-alias pixel: the visible glyph still starts at the user's
          // requested boundary, while the setting itself remains theme-independent.
          y += ReaderV2Paginator.lineTopInkGuard(firstLine);
          topInkGuardApplied = true;
        }
        // 跨页段落的后半截单独排版，它的第一行比在整段里多一份首行字体内边距，字整体靠下这么多；
        // 不算进去的话后面一段会贴上来，这一处的行距就比别处小。
        const sliceLead = session.lineIndex > 0 && !current.block.title ?
          ReaderV2Paginator.paragraphJoin(session.snapshot, session.lineStretchPx).sliceLeadPx : 0;
        const firstLineHeight = ReaderV2Paginator.lineBottom(firstLine) - firstLine.topHeight + sliceLead;
        if (!hasContent) {
          // Keep at least one line on a short viewport even when the requested title margin is larger.
          spacing = Math.min(spacing, Math.max(0, columnBottom - y - firstLineHeight));
        }
        // The drop cap and the lines wrapped around it stay together on one page.
        const dropLead = !!drop && session.dropPart === 0 && session.lineIndex === 0;
        // 放大的首字抬出第一行的部分放在段前（页首也留，不让方框画出版心上沿）。
        if (dropLead && drop) spacing += drop.risePx;
        const requiredHeight = dropLead && drop ? Math.max(firstLineHeight, drop.boxTopPx + drop.boxPx,
          ReaderV2Paginator.lineBottom(current.line(Math.min(drop.wrapLines, current.lineCount) - 1)) -
          firstLine.topHeight) : firstLineHeight;
        if (hasContent && y + spacing + requiredHeight > columnBottom + 0.01) {
          // Paragraph spacing belongs to the next block. It is never consumed as invisible page-tail space.
          break;
        }
        y += spacing;

        const fragmentFirstLine = session.lineIndex;
        const paragraphLineTop = current.line(fragmentFirstLine).topHeight - sliceLead;
        let fragmentLastLine = fragmentFirstLine - 1;
        let fragmentBottom = paragraphLineTop;
        while (session.lineIndex < current.lineCount) {
          const line = current.line(session.lineIndex);
          const relativeBottom = ReaderV2Paginator.lineBottom(line) - paragraphLineTop;
          if (y + relativeBottom > columnBottom + 0.01 && fragmentLastLine >= fragmentFirstLine) break;
          // A single oversized line still owns an otherwise empty page, preventing a pagination dead loop.
          if (y + relativeBottom > columnBottom + 0.01 && hasContent) break;
          fragmentLastLine = session.lineIndex;
          fragmentBottom = ReaderV2Paginator.lineBottom(line);
          session.lineIndex++;
          if (y + relativeBottom >= columnBottom - 0.01) break;
        }

        if (fragmentLastLine < fragmentFirstLine) {
          mustEndPage = hasContent;
          if (mustEndPage) continue;
          fragmentLastLine = fragmentFirstLine;
          fragmentBottom = ReaderV2Paginator.lineBottom(current.line(fragmentFirstLine));
          session.lineIndex = fragmentFirstLine + 1;
        }

        const fragment = ReaderV2Paginator.createFragment(session.document, current, session.blockIndex,
          fragmentFirstLine, fragmentLastLine, column.left, y, paragraphLineTop, fragmentBottom,
          session.snapshot, session.currentBlockStyles(), session.width, session.paragraphCache,
          current.stretchPx);
        if (!current.block.title) draft.lineGaps += fragmentLastLine - fragmentFirstLine + (joinsText ? 1 : 0);
        const previous = session.blockIndex > 0 ? session.document.blocks[session.blockIndex - 1] : null;
        fragment.fixedGapBefore = startsNewBlock && hasContent &&
          ((current.block.title && session.titleMarginTopPx > 0) ||
            (!current.block.title && !!previous && previous.title && session.titleMarginBottomPx > 0)) || followsCard;
        if (dropLead && drop) {
          fragment.dropCapTopPx = drop.boxTopPx;
          fragment.dropCapBoxPx = drop.boxPx;
          fragment.dropCapSpanPx = (drop.wrapLines - 1) * drop.pitchPx + firstLineHeight * 0.5;
          dropLeadTop = y;
        } else if (dropRest && fragmentFirstLine === 0 && !Number.isNaN(dropLeadTop)) {
          fragment.blockContinuation = true;
          fragment.fixedGapBefore = true;
        }
        fragmentActionStarts.push(page.actions.length);
        page.fragments.push(fragment);
        ReaderV2Paginator.appendActionAreas(page, fragment, session.document.actions, session.snapshot);
        if (!hasContent) page.displayStart = fragment.displayStart;
        page.displayEnd = fragment.displayEnd;
        hasContent = true;
        previousWasImage = false;
        previousWasCard = false;
        const lastInk = cardsEnabled || chapterCardsEnabled ?
          ReaderV2Paginator.lineInk(current, fragmentLastLine, session.snapshot) : null;
        lastInkBottom = lastInk ? y + lastInk.bottom - paragraphLineTop : Number.NaN;
        y += fragmentBottom - paragraphLineTop;

        if (session.lineIndex >= current.lineCount) {
          if (drop && session.dropPart === 0) {
            if (drop.splitAt < current.block.text.length) {
              session.dropPart = 1;
              session.lineIndex = 0;
              session.measuredBlock = null;
              continue;
            }
            // A paragraph shorter than the drop cap: the next block starts below the cap.
            if (!Number.isNaN(dropLeadTop) && dropLeadTop + drop.boxTopPx + drop.boxPx > y) {
              y = dropLeadTop + drop.boxTopPx + drop.boxPx;
              lastInkBottom = Number.NaN;
            }
          }
          session.dropPart = 0;
          if (cardsEnabled && current.block.trailingCard) {
            session.lineIndex = -1;
            continue;
          }
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
        } else {
          mustEndPage = true;
        }
      }

      draft.hasContent = hasContent;
      draft.titlePageBoundary = titlePageBoundary;
      draft.y = y;
    }
    return draft;
  }

  /** 这一块的段落排版要带上的行间份额：只有正文带，标题的行距不动。 */
  private static blockStretch(block: ReaderV2Block, session: ReaderV2PaginationSession): number {
    return block.title ? 0 : session.lineStretchPx;
  }

  /** 当前块接在正文后面、两段之间按行距相接（blockSpacingBefore 里收回字体内边距的那种情况）。 */
  private static joinsBodyText(session: ReaderV2PaginationSession, hasContent: boolean,
    previousWasImage: boolean): boolean {
    const block = session.document.blocks[session.blockIndex];
    const previous = session.blockIndex > 0 ? session.document.blocks[session.blockIndex - 1] : null;
    return hasContent && !previousWasImage && !block.title && !!previous && !previous.title && !previous.image;
  }

  private static blockSpacingBefore(session: ReaderV2PaginationSession, hasContent: boolean,
    previousWasImage: boolean): number {
    const block = session.document.blocks[session.blockIndex];
    const snapshot = session.snapshot;
    if (block.title && block.titleSegment > 0) return hasContent ? snapshot.titleLineGapPx : 0;
    const paragraphGap = hasContent ? Math.max(snapshot.paragraphSpacingPx,
      previousWasImage ? ReaderV2Paginator.imageGap(snapshot) : 0) : 0;
    if (block.title) return paragraphGap + session.titleMarginTopPx;
    const previous = session.blockIndex > 0 ? session.document.blocks[session.blockIndex - 1] : null;
    if (snapshot.titleSinglePage && previous && previous.title) return 0;
    if (hasContent && previous && previous.title) return paragraphGap + session.titleMarginBottomPx;
    // 正文接正文：段间距 0 时两段之间的行距和段内一样，设置值加在这个行距上面。
    const textAfterText = hasContent && !previousWasImage && !!previous && !previous.image;
    return paragraphGap +
      (textAfterText ? ReaderV2Paginator.paragraphJoin(snapshot, session.lineStretchPx).joinPx : 0);
  }

  private static readonly paragraphJoinCache: Map<string, ReaderV2ParagraphJoin> = new Map();

  /**
   * 正文段落单独排版带来的两个修正量，拿一段三行的正文样本量出来（stretchPx 是页底对齐加在行间的份额）：
   * joinPx——两段相接时要补上（多为负数，即收回）的距离，使前段末行与后段首行的基线距离等于段内相邻两行。
   * 每段首行上方、末行下方各带一份字体内边距（includeFontPadding），末行下方算不算行距也由排版引擎决定。
   * 只收回空白，字不会比段内更挤。
   * sliceLeadPx——段落的后半截单独排版时，首行基线比它在整段里（当中间行时）靠下的距离。
   */
  private static paragraphJoin(snapshot: ReaderV2LayoutSnapshot, stretchPx: number): ReaderV2ParagraphJoin {
    const key = stretchPx === 0 ? snapshot.identity : `${snapshot.identity}_${stretchPx}`;
    const cached = ReaderV2Paginator.paragraphJoinCache.get(key);
    if (cached !== undefined) return cached;
    const result = new ReaderV2ParagraphJoin();
    try {
      const sample = new ReaderV2Block('', '国国国', 0, 3, 0, 3, false);
      const style = ReaderV2Paginator.baseTextStyle(sample, snapshot);
      const builder = new graphicsText.ParagraphBuilder({
        textStyle: style,
        align: graphicsText.TextAlign.START,
        textDirection: graphicsText.TextDirection.LTR,
        wordBreak: graphicsText.WordBreak.BREAK_WORD,
        breakStrategy: graphicsText.BreakStrategy.GREEDY,
        lineSpacing: snapshot.lineSpacingPx + stretchPx,
        includeFontPadding: true
      }, graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(style);
      builder.addText(sample.text);
      builder.popStyle();
      const paragraph = builder.build();
      // 一行只放得下一个字。
      paragraph.layoutSync(snapshot.fontSizePx * 1.5 + Math.max(0, snapshot.letterSpacingPx));
      if (paragraph.getLineCount() >= 3) {
        const first = paragraph.getLineMetrics(0);
        const middle = paragraph.getLineMetrics(1);
        const last = paragraph.getLineMetrics(2);
        if (first && middle && last) {
          const pitch = last.baseline - middle.baseline;
          const firstLead = first.baseline - first.topHeight;
          const joined = (ReaderV2Paginator.lineBottom(last) - last.baseline) + firstLead;
          if (Number.isFinite(pitch) && Number.isFinite(joined) && pitch > 0) result.joinPx = pitch - joined;
          const lead = firstLead - (middle.baseline - middle.topHeight);
          if (Number.isFinite(lead) && Math.abs(lead) < snapshot.fontSizePx) result.sliceLeadPx = lead;
        }
      }
    } catch (_) {
      result.joinPx = 0;
      result.sliceLeadPx = 0;
    }
    ReaderV2Paginator.paragraphJoinCache.set(key, result);
    while (ReaderV2Paginator.paragraphJoinCache.size > 16) {
      const oldest = ReaderV2Paginator.paragraphJoinCache.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      ReaderV2Paginator.paragraphJoinCache.delete(oldest);
    }
    return result;
  }

  /** Isolate the complete title group; its source ranges remain those of the original document. */
  private static buildTitlePage(session: ReaderV2PaginationSession, column: ReaderV2Rect): ReaderV2PageLayout | null {
    const firstBlock = session.blockIndex;
    let afterTitle = firstBlock;
    while (afterTitle < session.document.blocks.length && session.document.blocks[afterTitle].title) afterTitle++;
    if (afterTitle === firstBlock) return null;
    const document = new ReaderV2Document();
    document.chapterIndex = session.document.chapterIndex;
    document.chapterTitle = session.document.chapterTitle;
    document.sourceText = session.document.sourceText;
    document.displayText = session.document.displayText;
    document.offsets = session.document.offsets;
    document.actions = session.document.actions;
    document.blocks = session.document.blocks.slice(firstBlock, afterTitle);
    document.identity = session.document.identity;
    const from = document.blocks[0].displayStart;
    const to = document.blocks[document.blocks.length - 1].displayEnd;
    const styles = session.regexStyles.filter((style: ReaderV2SpanStyleRange): boolean =>
      style.end > from && style.start < to);
    let page = ReaderV2Paginator.measureTitlePage(document, session.snapshot, column, styles, 1, session.paragraphCache);
    if (!page) return null;
    if (page.contentBottomPx > column.bottom + 0.01) {
      // Find a fitting uniform scale, retaining the user's font size whenever the complete title fits.
      let low = 0;
      let high = 1;
      for (let pass = 0; pass < 8; pass++) {
        const scale = (low + high) / 2;
        const candidate = ReaderV2Paginator.measureTitlePage(document, session.snapshot, column, styles, scale,
          session.paragraphCache);
        if (candidate && candidate.contentBottomPx <= column.bottom + 0.01) low = scale;
        else high = scale;
      }
      page = ReaderV2Paginator.measureTitlePage(document, session.snapshot, column, styles, Math.max(0.001, low),
        session.paragraphCache);
      if (!page) return null;
    }
    for (const fragment of page.fragments) fragment.blockIndex += firstBlock;
    page.pageIndex = session.pageIndex;
    page.columnIndex = session.pageIndex % session.snapshot.columnRects.length;
    page.contentBottomPx = column.bottom;
    page.identity = `${session.document.identity}_${session.snapshot.identity}_${session.pageIndex}_title_${from}_${to}`;
    session.blockIndex = afterTitle;
    session.lineIndex = 0;
    session.measuredBlock = null;
    return page;
  }

  private static measureTitlePage(document: ReaderV2Document, source: ReaderV2LayoutSnapshot,
    column: ReaderV2Rect, styles: ReaderV2SpanStyleRange[], scale: number,
    paragraphCache: ReaderV2ParagraphCache | null = null): ReaderV2PageLayout | null {
    const snapshot = new ReaderV2LayoutSnapshot();
    snapshot.viewport = source.viewport;
    snapshot.contentRect = column;
    snapshot.columnRects = [column];
    snapshot.fontSizePx = source.fontSizePx;
    snapshot.fontWeight = source.fontWeight;
    snapshot.titleFontSizePx = source.titleFontSizePx * scale;
    snapshot.titleFontWeight = source.titleFontWeight;
    snapshot.titleSecondaryScale = source.titleSecondaryScale;
    snapshot.titleLineGapPx = source.titleLineGapPx * scale;
    snapshot.titleAlignment = source.titleAlignment;
    snapshot.titleMarginTopPx = source.titleMarginTopPx * scale;
    snapshot.titleMarginBottomPx = source.titleMarginBottomPx * scale;
    snapshot.chapterHead = source.chapterHead;
    snapshot.letterSpacingPx = source.letterSpacingPx * scale;
    snapshot.textAlign = source.textAlign;
    snapshot.bodyFontFamily = source.bodyFontFamily;
    snapshot.titleFontFamily = source.titleFontFamily;
    snapshot.textColor = source.textColor;
    snapshot.noteColor = source.noteColor;
    snapshot.commentBubble = source.commentBubble;
    snapshot.commentFontSizePx = source.commentFontSizePx * scale;
    snapshot.commentBubbleSize = source.commentBubbleSize;
    snapshot.commentHitSlopXPx = source.commentHitSlopXPx;
    snapshot.commentHitSlopYPx = source.commentHitSlopYPx;
    snapshot.identity = `${source.identity}_title_scale_${scale}`;
    const scaledStyles = scale === 1 ? styles : styles.map((style: ReaderV2SpanStyleRange): ReaderV2SpanStyleRange => {
      // Span styles are scalar DTOs; leave the original chapter styles untouched for body pagination.
      const copy = JSON.parse(JSON.stringify(style)) as ReaderV2SpanStyleRange;
      copy.fontSizePx *= scale;
      copy.radiusTopLeftPx *= scale;
      copy.radiusTopRightPx *= scale;
      copy.radiusBottomLeftPx *= scale;
      copy.radiusBottomRightPx *= scale;
      copy.shadowRadiusPx *= scale;
      copy.shadowOffsetXPx *= scale;
      copy.shadowOffsetYPx *= scale;
      copy.decorationSizePx *= scale;
      return copy;
    });
    return ReaderV2Paginator.layoutContinuous(document, snapshot, scaledStyles, paragraphCache);
  }

  private static shiftTitlePage(page: ReaderV2PageLayout, shift: number): void {
    if (shift === 0) return;
    for (const fragment of page.fragments) {
      fragment.paragraphY += shift;
      fragment.clipRect.top += shift;
      fragment.clipRect.bottom += shift;
      for (const bubble of fragment.regexBubbleSegments) {
        bubble.rect.top += shift;
        bubble.rect.bottom += shift;
        bubble.frameRect.top += shift;
        bubble.frameRect.bottom += shift;
      }
      for (const bubble of fragment.commentBubbleSegments) {
        bubble.rect.top += shift;
        bubble.rect.bottom += shift;
      }
    }
    for (const action of page.actions) {
      action.rect.top += shift;
      action.rect.bottom += shift;
    }
    for (const decoration of page.decorations) {
      decoration.rect.top += shift;
      decoration.rect.bottom += shift;
    }
  }

  /** 页底对齐时可以加距离的块间隙数；标题各行之间、定死的间隙（标题边距、段末热评卡）不算。 */
  private static alignableGaps(page: ReaderV2PageLayout): number {
    return page.fragments.filter((fragment: ReaderV2PageFragment, index: number): boolean =>
      index > 0 && !fragment.titleContinuation && !fragment.fixedGapBefore).length;
  }

  /**
   * 页底对齐的收尾：行间摊完后余下的零头，或者这一页没能按行距重排时的全部空白，均分到本页各块之间。
   * 每个间隙最多加半个字高，摊不完的留在页底。不动行距和断行。
   */
  private static alignPageBottom(page: ReaderV2PageLayout, fragmentActionStarts: number[], leftoverPx: number,
    snapshot: ReaderV2LayoutSnapshot): void {
    const gaps = ReaderV2Paginator.alignableGaps(page);
    if (gaps <= 0 || leftoverPx <= 0.5 || leftoverPx > (snapshot.fontSizePx + snapshot.lineSpacingPx) * 2) return;
    const perGapPx = Math.min(leftoverPx / gaps, snapshot.fontSizePx * 0.5);
    let shiftPx = 0;
    for (let index = 1; index < page.fragments.length; index++) {
      const fragment = page.fragments[index];
      if (!fragment.titleContinuation && !fragment.fixedGapBefore) shiftPx += perGapPx;
      fragment.paragraphY += shiftPx;
      fragment.clipRect.top += shiftPx;
      fragment.clipRect.bottom += shiftPx;
      if (fragment.imageRect !== fragment.clipRect) {
        fragment.imageRect.top += shiftPx;
        fragment.imageRect.bottom += shiftPx;
      }
      for (const segment of fragment.regexBubbleSegments) {
        segment.rect.top += shiftPx;
        segment.rect.bottom += shiftPx;
        segment.frameRect.top += shiftPx;
        segment.frameRect.bottom += shiftPx;
      }
      for (const bubble of fragment.commentBubbleSegments) {
        bubble.rect.top += shiftPx;
        bubble.rect.bottom += shiftPx;
      }
      const actionEnd = index + 1 < fragmentActionStarts.length ? fragmentActionStarts[index + 1] :
        page.actions.length;
      for (let actionIndex = fragmentActionStarts[index]; actionIndex < actionEnd; actionIndex++) {
        page.actions[actionIndex].rect.top += shiftPx;
        page.actions[actionIndex].rect.bottom += shiftPx;
      }
    }
  }

  /** 滚动阅读里尺寸未知的图片按 高/宽 = 这个比例占位。 */
  private static readonly CONTINUOUS_UNKNOWN_IMAGE_ASPECT: number = 0.62;

  /** Vertical gap between an image block and neighbouring text, even when paragraph spacing is zero. */
  private static imageGap(snapshot: ReaderV2LayoutSnapshot): number {
    return Math.max(snapshot.paragraphSpacingPx, snapshot.lineSpacingPx, snapshot.fontSizePx * 0.5);
  }

  private static measureBlock(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], width: number,
    paragraphCache: ReaderV2ParagraphCache | null = null, stretchPx: number = 0): ReaderV2MeasuredBlock {
    const paragraph = ReaderV2Paginator.buildParagraph(document, block, snapshot, regexStyles, width,
      0, block.text.length, false, paragraphCache, stretchPx);
    const cached = paragraphCache?.measurements.get(paragraph);
    if (cached) return cached;
    const measured = new ReaderV2MeasuredBlock(block, paragraph);
    measured.stretchPx = block.title ? 0 : stretchPx;
    paragraphCache?.measurements.set(paragraph, measured);
    return measured;
  }

  private static buildParagraph(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], width: number,
    sliceStart: number, sliceEnd: number, outlineOnly: boolean = false,
    paragraphCache: ReaderV2ParagraphCache | null = null, stretchPx: number = 0): graphicsText.Paragraph {
    // 页底对齐加在正文行间的份额；标题的行距不动。
    const stretch = block.title ? 0 : stretchPx;
    const cacheKey = `${snapshot.identity}_${block.id}_${sliceStart}_${sliceEnd}_${width}_${outlineOnly}` +
      (stretch === 0 ? '' : `_${stretch}`);
    if (paragraphCache) {
      const ready = paragraphCache.ready.get(cacheKey);
      if (ready) return ready;
    }
    const startedAt = Date.now();
    const baseStyle = ReaderV2Paginator.baseTextStyle(block, snapshot);
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: baseStyle,
      align: block.title ? ReaderV2Paginator.titleTextAlign(snapshot.titleAlignment) :
        ReaderV2Paginator.textAlign(snapshot.textAlign),
      textDirection: graphicsText.TextDirection.LTR,
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      breakStrategy: graphicsText.BreakStrategy.GREEDY,
      trailingSpaceOptimized: true,
      lineSpacing: block.title ? snapshot.titleLineGapPx : snapshot.lineSpacingPx + stretch,
      // A paragraph is painted independently for every source block. With font padding disabled, glyph ink from
      // some CJK families can extend above the first logical line box and be clipped by Paragraph itself. Later
      // lines appear intact because their preceding line spacing provides bleed room. Include the native font
      // padding so the first-row ink is part of the measured paragraph; pagination consumes the same metrics.
      includeFontPadding: true
    };
    const builder = new graphicsText.ParagraphBuilder(paragraphStyle,
      graphicsText.FontCollection.getGlobalInstance());
    const safeStart = Math.max(0, Math.min(block.text.length, sliceStart));
    const safeEnd = Math.max(safeStart, Math.min(block.text.length, sliceEnd));
    const boundaries = ReaderV2Paginator.styleBoundaries(document, block, regexStyles, safeStart, safeEnd,
      !!snapshot.commentBubble.image);
    for (let index = 0; index < boundaries.length - 1; index++) {
      const start = boundaries[index];
      const end = boundaries[index + 1];
      if (end <= start) continue;
      const absoluteStart = block.displayStart + start;
      const style = ReaderV2Paginator.styleAt(document, block, absoluteStart, snapshot, regexStyles);
      builder.pushStyle(outlineOnly ? ReaderFontStroke.outlineStyle(style) : style);
      builder.addText(block.text.substring(start, end));
      builder.popStyle();
    }
    const paragraph = builder.build();
    ReaderV2Paginator.onWorkMeasured?.('paragraph-build', Date.now() - startedAt);
    const layoutWidth = Math.max(1, width - ReaderV2Paginator.titleLeadReserve(document, block, snapshot, width) -
      ReaderV2Paginator.titleDecorationInset(block, regexStyles, width) * 2);
    if (paragraphCache) throw new ReaderV2PendingLayout(cacheKey, paragraph, layoutWidth);
    paragraph.layoutSync(layoutWidth);
    return paragraph;
  }

  /** The paragraph to lay lines out from at the session cursor: the whole block, or one slice of the drop-cap paragraph. */
  private static measureCurrent(session: ReaderV2PaginationSession): ReaderV2MeasuredBlock {
    const block = session.document.blocks[session.blockIndex];
    const plan = ReaderV2Paginator.dropCapPlan(session);
    if (!plan) {
      session.dropPart = 0;
      return ReaderV2Paginator.measureBlock(session.document, block, session.snapshot, session.currentBlockStyles(),
        session.width, session.paragraphCache, session.lineStretchPx);
    }
    return session.dropPart === 0 ?
      ReaderV2Paginator.measureSlice(session, block, plan.bodyStart, plan.splitAt, session.width - plan.reservePx,
        plan.reservePx) :
      ReaderV2Paginator.measureSlice(session, block, plan.splitAt, block.text.length, session.width, 0);
  }

  private static measureSlice(session: ReaderV2PaginationSession, block: ReaderV2Block, start: number, end: number,
    width: number, lead: number): ReaderV2MeasuredBlock {
    const paragraph = ReaderV2Paginator.buildParagraph(session.document, block, session.snapshot,
      session.currentBlockStyles(), width, start, end, false, session.paragraphCache, session.lineStretchPx);
    const measured = new ReaderV2MeasuredBlock(block, paragraph);
    measured.stretchPx = ReaderV2Paginator.blockStretch(block, session);
    measured.sliceStart = start;
    measured.sliceEnd = end;
    measured.widthPx = width;
    measured.leadPx = lead;
    return measured;
  }

  /** 汉字（含扩展 A 区和兼容区）才做首字；引号、数字、字母、标点开头的段落保持原样。 */
  private static readonly DROP_CAP_CHAR: RegExp = /[\u3400-\u9FFF\uF900-\uFAFF]/;
  /** 汉字字框相对基线的上、下范围占字号的比例。 */
  private static readonly EM_ASCENT: number = 0.92;
  private static readonly EM_DESCENT: number = 0.12;
  /** 首字方框相对文字行上下范围各收进的量，占字号的比例。 */
  private static readonly DROP_CAP_INSET: number = 0.05;

  /**
   * 当前块是首字段落时返回排法，否则 null。第一次用到时量出行距并定下两截的分界；量的过程中遇到要等的
   * 异步排版会原样抛出，下次重来（已排好的段落在缓存里）。
   */
  private static dropCapPlan(session: ReaderV2PaginationSession): ReaderV2DropCapPlan | null {
    const head = session.snapshot.chapterHead;
    if (head.capLines < 2 || session.blockIndex !== session.document.dropCapBlockIndex()) return null;
    if (session.dropCapResolved) return session.dropCap;
    const plan = ReaderV2Paginator.resolveDropCap(session);
    session.dropCap = plan;
    session.dropCapResolved = true;
    return plan;
  }

  private static resolveDropCap(session: ReaderV2PaginationSession): ReaderV2DropCapPlan | null {
    const block = session.document.blocks[session.blockIndex];
    const text = block.text;
    let capStart = 0;
    while (capStart < text.length && (text[capStart] === ' ' || text[capStart] === '\u3000' || text[capStart] === '\t')) {
      capStart++;
    }
    const bodyStart = capStart + 1;
    if (bodyStart >= text.length || !ReaderV2Paginator.DROP_CAP_CHAR.test(text[capStart])) return null;
    // 首字上挂着段评气泡、注释编号时不做。
    const actionIndex = ReaderV2Paginator.firstActionWhoseEndExceeds(session.document.actions, block.displayStart);
    if (actionIndex < session.document.actions.length &&
      session.document.actions[actionIndex].displayStart < block.displayStart + bodyStart) return null;
    const snapshot = session.snapshot;
    const styles = session.currentBlockStyles();
    const full = ReaderV2Paginator.measureBlock(session.document, block, snapshot, styles, session.width,
      session.paragraphCache);
    if (full.lineCount === 0) return null;
    const firstLine = full.line(0);
    const plan = new ReaderV2DropCapPlan();
    plan.blockIndex = session.blockIndex;
    plan.char = text[capStart];
    plan.bodyStart = bodyStart;
    plan.lines = Math.max(2, Math.min(4, Math.round(snapshot.chapterHead.capLines)));
    plan.wrapLines = snapshot.chapterHead.capRaise ? 1 : plan.lines;
    plan.pitchPx = full.lineCount > 1 ? full.line(1).topHeight - firstLine.topHeight :
      firstLine.height + snapshot.lineSpacingPx;
    const font = snapshot.fontSizePx;
    // 方框的上下边取第一行文字实际占的范围（和朗读高亮、选区用的是同一个范围），再各收进一点贴近字面。
    // 行距不为零时行度量里的基线不能直接当字的位置用，按它算方框会整体偏低。
    const inkRects = full.paragraph.getRectsForRange({ start: capStart, end: bodyStart },
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    if (inkRects.length === 0) return null;
    const inkTop = inkRects[0].rect.top - firstLine.topHeight;
    const inkHeight = inkRects[0].rect.bottom - inkRects[0].rect.top;
    const inset = font * ReaderV2Paginator.DROP_CAP_INSET;
    if (inkHeight <= inset * 4) return null;
    plan.boxPx = (plan.lines - 1) * plan.pitchPx + inkHeight - inset * 2;
    // 放大：方框底边仍对齐第一行文字，多出的高度向上抬出。
    plan.risePx = snapshot.chapterHead.capRaise ? (plan.lines - 1) * plan.pitchPx : 0;
    plan.boxTopPx = inkTop + inset - plan.risePx;
    plan.reservePx = plan.boxPx + font * 0.3;
    // 版心太窄、方框占掉一半以上时不做。
    if (plan.pitchPx <= 0 || plan.reservePx > session.width * 0.5) return null;
    const narrow = ReaderV2Paginator.buildParagraph(session.document, block, snapshot, styles,
      session.width - plan.reservePx, bodyStart, text.length, false, session.paragraphCache);
    const narrowLines = narrow.getLineCount();
    if (narrowLines > plan.wrapLines) {
      const boundary = narrow.getLineMetrics(plan.wrapLines - 1);
      plan.splitAt = boundary ? Math.min(text.length, bodyStart + boundary.endIndex) : text.length;
    } else {
      plan.splitAt = text.length;
    }
    return plan;
  }

  /** 把首字画到绕排那一截第一行的左上角；片段位置已定（页底对齐之后）。 */
  private static placeDropCap(page: ReaderV2PageLayout, session: ReaderV2PaginationSession, column: ReaderV2Rect): void {
    const plan = session.dropCap;
    if (!plan) return;
    const lead = page.fragments.find((fragment: ReaderV2PageFragment): boolean => fragment.dropCapBoxPx > 0);
    if (!lead) return;
    const snapshot = session.snapshot;
    const head = snapshot.chapterHead;
    const box = lead.dropCapBoxPx;
    const top = lead.paragraphY + lead.dropCapTopPx;
    const fontPx = head.capImage ? box * Math.max(0.4, Math.min(0.9, head.capRatio)) :
      box / (ReaderV2Paginator.EM_ASCENT + ReaderV2Paginator.EM_DESCENT);
    const style = ReaderV2Paginator.baseTextStyle(new ReaderV2Block('drop_cap', plan.char, 0, 1, 0, 1, true), snapshot);
    style.fontSize = fontPx;
    style.letterSpacing = 0;
    if (head.capColor !== 0) style.color = ReaderV2Paginator.graphicsColor(head.capColor);
    const builder = new graphicsText.ParagraphBuilder({
      textStyle: style,
      align: graphicsText.TextAlign.LEFT,
      textDirection: graphicsText.TextDirection.LTR,
      includeFontPadding: true
    }, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(plan.char);
    builder.popStyle();
    const glyph = builder.build();
    glyph.layoutSync(Math.max(1, box * 3));
    const line = glyph.getLineMetrics(0);
    const decoration = new ReaderV2PageDecoration();
    decoration.image = head.capImage;
    decoration.rect = new ReaderV2Rect(column.left, top, column.left + box, top + box);
    decoration.glyph = glyph;
    decoration.glyphX = column.left + (box - (line ? line.width : fontPx)) / 2;
    // 字框（基线上 0.92、下 0.12 个字号）的中心对到方框中心。
    const baselineY = top + box / 2 + fontPx * (ReaderV2Paginator.EM_ASCENT - ReaderV2Paginator.EM_DESCENT) / 2;
    decoration.glyphY = baselineY - (line ? line.baseline : fontPx * ReaderV2Paginator.EM_ASCENT);
    page.decorations.push(decoration);
  }

  /** 章首饰图在标题左侧时，标题每一行左边让出的宽度。 */
  private static titleLeadReserve(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, width: number): number {
    if (!block.title || !snapshot.chapterHead.image) return 0;
    return ReaderV2ChapterHeadLayout.metrics(snapshot, document.titleBlockCount(), width).reservePx;
  }

  private static titleDecorationInset(block: ReaderV2Block, styles: ReaderV2SpanStyleRange[], width: number): number {
    if (!block.title) return 0;
    let inset = 0;
    for (const style of styles) {
      if (style.repeatCaps && ReaderV2BubbleFrame.decorates(style) && style.start < block.displayEnd &&
        style.end > block.displayStart) {
        inset = Math.max(inset, ReaderV2BubbleFrame.leadingReservation(style),
          ReaderV2BubbleFrame.trailingReservation(style));
      }
    }
    return Math.min(width / 6, inset);
  }

  private static titleTextAlign(alignment: string): graphicsText.TextAlign {
    if (alignment === 'left') return graphicsText.TextAlign.LEFT;
    if (alignment === 'right') return graphicsText.TextAlign.RIGHT;
    return graphicsText.TextAlign.CENTER;
  }

  private static textAlign(value: string): graphicsText.TextAlign {
    if (value === 'start') return graphicsText.TextAlign.LEFT;
    if (value === 'end') return graphicsText.TextAlign.RIGHT;
    return graphicsText.TextAlign.JUSTIFY;
  }

  private static readonly FONT_WEIGHTS: graphicsText.FontWeight[] = [
      graphicsText.FontWeight.W100, graphicsText.FontWeight.W200,
      graphicsText.FontWeight.W300, graphicsText.FontWeight.W400, graphicsText.FontWeight.W500,
      graphicsText.FontWeight.W600, graphicsText.FontWeight.W700, graphicsText.FontWeight.W800,
      graphicsText.FontWeight.W900];

  private static bodyFontWeight(weight: number): graphicsText.FontWeight {
    // Static faces use the nearest SDK weight; the wght axis below preserves precise variable-font values.
    return ReaderV2Paginator.FONT_WEIGHTS[Math.max(0, Math.min(8, Math.round(weight / 100) - 1))];
  }

  /**
   * 一行文字字面的上下边（段落坐标）。热评卡片上下的留白按它量，不按行框量：行框在段末带一份行距，
   * 首尾行还有字体留白，两头不一样宽。行距不为零时行度量里的基线不能当字的位置用，所以取文字实际占的
   * 范围，再按字号收到字身框。取不到时返回 null。
   */
  private static lineInk(measured: ReaderV2MeasuredBlock, lineIndex: number,
    snapshot: ReaderV2LayoutSnapshot): ReaderV2Rect | null {
    const line = measured.line(lineIndex);
    const rects = measured.paragraph.getRectsForRange({ start: line.startIndex, end: line.endIndex },
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    let top = Number.MAX_VALUE;
    let bottom = -Number.MAX_VALUE;
    for (const item of rects) {
      if (item.rect.bottom <= item.rect.top) continue;
      top = Math.min(top, item.rect.top);
      bottom = Math.max(bottom, item.rect.bottom);
    }
    if (bottom <= top) return null;
    const inset = Math.max(0, (bottom - top - ReaderV2Paginator.blockFontSize(measured.block, snapshot)) / 2);
    return new ReaderV2Rect(0, top + inset, 0, bottom - inset);
  }

  private static blockFontSize(block: ReaderV2Block, snapshot: ReaderV2LayoutSnapshot): number {
    return ReaderV2Paginator.baseTextStyle(block, snapshot).fontSize ?? snapshot.fontSizePx;
  }

  private static baseTextStyle(block: ReaderV2Block, snapshot: ReaderV2LayoutSnapshot): graphicsText.TextStyle {
    const heading = block.title || block.headingLevel > 0;
    const weight = ReaderFontWeight.layoutWeight(heading ? snapshot.titleFontFamily : snapshot.bodyFontFamily,
      heading ? snapshot.titleFontWeight : snapshot.fontWeight);
    // Chapter titles keep the user's title size. In-chapter headings sit between body and title size so a
    // deep heading never outweighs the chapter title; level 3+ only gains the title face and weight.
    const headingFontSizePx = block.headingLevel > 2 ? snapshot.fontSizePx :
      Math.max(snapshot.fontSizePx, (snapshot.fontSizePx + snapshot.titleFontSizePx) / 2);
    return {
      fontSize: block.title ? snapshot.titleFontSizePx * (block.titleSegment > 0 ? snapshot.titleSecondaryScale : 1) :
        (heading ? headingFontSizePx : snapshot.fontSizePx),
      letterSpacing: snapshot.letterSpacingPx,
      fontFamilies: [heading ? snapshot.titleFontFamily : snapshot.bodyFontFamily],
      fontWeight: ReaderV2Paginator.bodyFontWeight(weight),
      fontVariations: [{ axis: 'wght', value: weight }],
      color: ReaderV2Paginator.graphicsColor(block.titleLead && snapshot.chapterHead.numberColor !== 0 ?
        snapshot.chapterHead.numberColor : snapshot.textColor),
      halfLeading: false,
      heightOnly: true,
      heightScale: 1,
      locale: 'zh-Hans'
    };
  }

  private static styleBoundaries(document: ReaderV2Document, block: ReaderV2Block,
    regexStyles: ReaderV2SpanStyleRange[], sliceStart: number = 0,
    sliceEnd: number = block.text.length, imageBubble: boolean = false): number[] {
    const boundaries: number[] = [sliceStart, sliceEnd];
    const absoluteSliceStart = block.displayStart + sliceStart;
    const absoluteSliceEnd = block.displayStart + sliceEnd;
    const firstAction = ReaderV2Paginator.firstActionWhoseEndExceeds(document.actions, absoluteSliceStart);
    for (let index = firstAction; index < document.actions.length; index++) {
      const action = document.actions[index];
      if (action.displayStart >= absoluteSliceEnd) break;
      const actionStart = action.displayStart - block.displayStart;
      const actionEnd = action.displayEnd - block.displayStart;
      if (actionEnd <= sliceStart || actionStart >= sliceEnd) continue;
      boundaries.push(Math.max(sliceStart, actionStart));
      boundaries.push(Math.min(sliceEnd, actionEnd));
      // Isolate the side pads: count labels reserve their fixed width there, and an image bubble reserves the room
      // its artwork reaches beyond the text box (after the gap's last character and after the last pad).
      const pads: number[] = [];
      if (ReaderCommentBubbleSize.isCount(action.label)) {
        pads.push(action.bubbleStart, action.bubbleStart + 1, action.displayEnd - 1);
      }
      if (imageBubble) pads.push(action.bubbleStart - 1, action.bubbleStart, action.displayEnd - 1);
      for (const offset of pads) {
        const localOffset = offset - block.displayStart;
        if (localOffset > sliceStart && localOffset < sliceEnd) boundaries.push(localOffset);
      }
    }
    for (const style of regexStyles) {
      const styleStart = style.start - block.displayStart;
      const styleEnd = style.end - block.displayStart;
      if (styleEnd <= sliceStart || styleStart >= sliceEnd) continue;
      boundaries.push(Math.max(sliceStart, styleStart));
      boundaries.push(Math.min(sliceEnd, styleEnd));
      if (ReaderV2BubbleFrame.decorates(style)) {
        // Isolate the character that owns each decoration reservation. Letter spacing is applied after a
        // character, so the character immediately before the run owns the leading gap and the run's last
        // character owns the trailing gap. No synthetic text is inserted and source/selection offsets stay exact.
        const leadingOwner = styleStart - 1;
        if (leadingOwner >= sliceStart && leadingOwner < sliceEnd) {
          boundaries.push(leadingOwner);
          boundaries.push(Math.min(sliceEnd, leadingOwner + 1));
        }
        const trailingOwner = styleEnd - 1;
        if (trailingOwner >= sliceStart && trailingOwner < sliceEnd) {
          boundaries.push(trailingOwner);
          boundaries.push(Math.min(sliceEnd, trailingOwner + 1));
        }
      }
    }
    // 相邻全角标点的前一个单独成段，挤压用的负字距只加在它身上。
    for (const owner of ReaderPunctuationSqueeze.pairOwners(block.text, sliceStart, sliceEnd)) {
      boundaries.push(owner);
      boundaries.push(owner + 1);
    }
    boundaries.sort((left: number, right: number): number => left - right);
    const unique: number[] = [];
    for (const value of boundaries) {
      if (unique.length === 0 || unique[unique.length - 1] !== value) unique.push(value);
    }
    return unique;
  }

  private static styleAt(document: ReaderV2Document, block: ReaderV2Block, absoluteOffset: number,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[]): graphicsText.TextStyle {
    const base = ReaderV2Paginator.baseTextStyle(block, snapshot);
    const decorationReservation = ReaderV2Paginator.decorationReservationAfter(absoluteOffset, block, regexStyles);
    if (decorationReservation > 0) base.letterSpacing = snapshot.letterSpacingPx + decorationReservation;
    const actionIndex = ReaderV2Paginator.firstActionWhoseEndExceeds(document.actions, absoluteOffset);
    if (actionIndex < document.actions.length) {
      const action = document.actions[actionIndex];
      if (absoluteOffset >= action.displayStart && absoluteOffset < action.displayEnd && action.note) {
        return ReaderV2Paginator.noteTextStyle(base, action.label, snapshot);
      }
      if (absoluteOffset >= action.displayStart && absoluteOffset < action.displayEnd) {
        const bodyCenter = ReaderV2Paginator.commentTextCenter(base, '国', snapshot);
        const scale = ReaderCommentBubbleSize.scale(action.label, snapshot.commentBubbleSize);
        const bubbleFontSize = snapshot.commentFontSizePx * scale;
        const imageReserve = ReaderV2Paginator.commentImageReserve(snapshot, scale);
        base.fontSize = ReaderCommentBubbleSize.labelFontSize(action.label, bubbleFontSize);
        base.letterSpacing = ReaderCommentBubbleSize.isCount(action.label) ? 0 : snapshot.letterSpacingPx * scale;
        let countPadding = 0;
        if (ReaderCommentBubbleSize.isCount(action.label) && action.bubbleStart > action.displayStart) {
          const paddedLabel = action.label.substring(action.bubbleStart - action.displayStart);
          const innerWidth = ReaderCommentBubbleSize.countWidth(bubbleFontSize, snapshot.commentBubble.styleId) -
            bubbleFontSize * 0.36;
          let naturalWidth = ReaderV2Paginator.commentTextWidth(base, paddedLabel, snapshot);
          if (naturalWidth > innerWidth) {
            base.fontSize *= innerWidth / naturalWidth;
            naturalWidth = ReaderV2Paginator.commentTextWidth(base, paddedLabel, snapshot);
          }
          countPadding = Math.max(0, (innerWidth - naturalWidth) / 2);
        }
        // Shift the native glyphs themselves: bubble bounds, hit testing and pagination then consume the
        // same adjusted metrics. Centre the complete body + tail silhouette, keeping the label in the body.
        const tailHeight = ReaderCommentBubblePainter.tailHeightFor(
          ReaderCommentBubblePainter.heightFor(bubbleFontSize), snapshot.commentBubble);
        base.baselineShift = bodyCenter - ReaderV2Paginator.commentTextCenter(base, action.label, snapshot) -
          tailHeight / 2;
        if (absoluteOffset === action.bubbleStart || absoluteOffset === action.displayEnd - 1) {
          base.letterSpacing += countPadding;
        }
        if (absoluteOffset === action.bubbleStart - 1) base.letterSpacing += imageReserve[0];
        if (absoluteOffset === action.displayEnd - 1) base.letterSpacing += imageReserve[1];
        // The bubble behind the label is painted by the page node, not as a text background.
        base.color = ReaderV2Paginator.graphicsColor(snapshot.commentBubble.text);
        return base;
      }
    }
    const numberLead = block.titleLead && snapshot.chapterHead.numberColor !== 0;
    for (const style of regexStyles) {
      if (absoluteOffset < style.start || absoluteOffset >= style.end) continue;
      if (style.fontSizePx > 0) base.fontSize = style.fontSizePx;
      if (style.fontFamily) base.fontFamilies = [style.fontFamily];
      // 主题的序号行颜色优先于标题强调和正则规则的文字色（与主题预览一致），背景、阴影等仍照常。
      if ((style.colorEnabled || style.color !== 0) && !numberLead) {
        base.color = ReaderV2Paginator.graphicsColor(style.color);
      }
      if (style.backgroundEnabled && !style.decorationEnabled) {
        base.backgroundRect = {
          color: ReaderV2Paginator.graphicsColor(style.backgroundColor),
          leftTopRadius: style.radiusTopLeftPx,
          rightTopRadius: style.radiusTopRightPx,
          rightBottomRadius: style.radiusBottomRightPx,
          leftBottomRadius: style.radiusBottomLeftPx
        };
      }
      if (style.shadowEnabled && !style.decorationEnabled) {
        base.textShadows = [{
          color: ReaderV2Paginator.graphicsColor(style.shadowColor),
          point: { x: Math.max(0, style.shadowOffsetXPx), y: Math.max(0, style.shadowOffsetYPx) },
          blurRadius: style.shadowRadiusPx
        }];
      }
      // Keep decorated text in the native paragraph. The decoration is painted as a background layer by
      // ReadBook, while this paragraph remains the single source of truth for glyph metrics and baselines.
      // Repainting the text in an ArkUI Text containing ImageSpans gives that copy a different line box and
      // makes decorated and ordinary text on the same line visibly drift vertically.
      return ReaderV2Paginator.squeezePunctuation(block, absoluteOffset, decorationReservation,
        ReaderV2Paginator.resolveWeight(base,
          ReaderV2Paginator.requestedWeightAt(document, block, absoluteOffset, snapshot, regexStyles)));
    }
    return ReaderV2Paginator.squeezePunctuation(block, absoluteOffset, decorationReservation,
      ReaderV2Paginator.resolveWeight(base,
        ReaderV2Paginator.requestedWeightAt(document, block, absoluteOffset, snapshot, regexStyles)));
  }

  /**
   * 标点挤压：这个字和下一个字是相邻的全角标点时，用负字距收掉两者之间的一部分空白（见 ReaderPunctuationSqueeze）。
   * 字符已由 styleBoundaries 单独切出。它后面紧跟着装饰框的预留空白时不收，免得吃掉装饰的位置。
   */
  private static squeezePunctuation(block: ReaderV2Block, absoluteOffset: number, decorationReservation: number,
    style: graphicsText.TextStyle): graphicsText.TextStyle {
    if (decorationReservation > 0) return style;
    const local = absoluteOffset - block.displayStart;
    if (!ReaderPunctuationSqueeze.ownsPair(block.text, local)) return style;
    const em = ReaderPunctuationSqueeze.squeezeEm(ReaderPunctuationMetrics.spaceOf(style, block.text[local]),
      ReaderPunctuationMetrics.spaceOf(style, block.text[local + 1]));
    if (em > 0) style.letterSpacing = (style.letterSpacing ?? 0) - em * (style.fontSize ?? 0);
    return style;
  }

  /**
   * 注释编号：本来就是上标字符（¹²³）的只换颜色；其它编号（1、[1]、①、注）缩小并抬到上标位置。
   * 只有图标的注释显示成"注"，再垫一块浅色圆底，和普通文字区分开。
   */
  private static noteTextStyle(base: graphicsText.TextStyle, label: string,
    snapshot: ReaderV2LayoutSnapshot): graphicsText.TextStyle {
    base.color = ReaderV2Paginator.graphicsColor(snapshot.noteColor);
    if (/^[⁰¹²³⁴-⁹]+$/.test(label)) return base;
    const bodySize = base.fontSize ?? snapshot.fontSizePx;
    base.fontSize = bodySize * 0.62;
    base.letterSpacing = 0;
    // 与段评标签同一套符号约定：负值把字形往上移。
    base.baselineShift = -bodySize * 0.32;
    if (label === EpubNoteLink.ICON_LABEL) {
      const radius = bodySize * 0.4;
      base.backgroundRect = {
        color: ReaderV2Paginator.graphicsColor(((snapshot.noteColor & 0x00FFFFFF) | 0x2E000000) >>> 0),
        leftTopRadius: radius,
        rightTopRadius: radius,
        rightBottomRadius: radius,
        leftBottomRadius: radius
      };
    }
    return base;
  }

  private static resolveWeight(style: graphicsText.TextStyle, requestedWeight: number): graphicsText.TextStyle {
    const family = style.fontFamilies && style.fontFamilies.length > 0 ? style.fontFamilies[0] : '';
    const weight = ReaderFontWeight.layoutWeight(family, requestedWeight);
    style.fontWeight = ReaderV2Paginator.bodyFontWeight(weight);
    style.fontVariations = [{ axis: 'wght', value: weight }];
    return style;
  }

  private static requestedWeightAt(document: ReaderV2Document, block: ReaderV2Block, offset: number,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[]): number {
    const fallback = block.title || block.headingLevel > 0 ? snapshot.titleFontWeight : snapshot.fontWeight;
    const actionIndex = ReaderV2Paginator.firstActionWhoseEndExceeds(document.actions, offset);
    if (actionIndex < document.actions.length && offset >= document.actions[actionIndex].displayStart &&
      offset < document.actions[actionIndex].displayEnd) return fallback;
    for (const style of regexStyles) {
      if (offset >= style.start && offset < style.end) return style.fontWeight > 0 ? style.fontWeight : fallback;
    }
    return fallback;
  }

  private static decorationReservationAfter(absoluteOffset: number, block: ReaderV2Block,
    regexStyles: ReaderV2SpanStyleRange[]): number {
    let reservation = 0;
    const blockStart = block.displayStart;
    const blockEnd = block.displayStart + block.text.length;
    for (const style of regexStyles) {
      if (style.repeatCaps || !ReaderV2BubbleFrame.decorates(style) || style.end <= blockStart ||
        style.start >= blockEnd) continue;
      // The leading cap uses spacing after the preceding character. At a true paragraph boundary there is no
      // preceding glyph, so the painter clips that cap to the content edge instead of moving source offsets.
      // A theme frame adds its end width inside the cap, so the text never sits under the frame's end pieces.
      if (style.start > blockStart && absoluteOffset === style.start - 1) {
        reservation = Math.max(reservation, ReaderV2BubbleFrame.leadingReservation(style));
      }
      if (absoluteOffset === style.end - 1) {
        reservation = Math.max(reservation, ReaderV2BubbleFrame.trailingReservation(style));
      }
    }
    return reservation;
  }

  private static createFragment(document: ReaderV2Document, current: ReaderV2MeasuredBlock,
    blockIndex: number, firstLine: number,
    lastLine: number, x: number, y: number, paragraphLineTop: number,
    paragraphLineBottom: number, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[], width: number,
    paragraphCache: ReaderV2ParagraphCache | null = null, stretchPx: number = 0): ReaderV2PageFragment {
    const first = current.line(firstLine);
    const last = current.line(lastLine);
    const fragment = new ReaderV2PageFragment();
    fragment.title = current.block.title;
    fragment.titleEnd = current.block.title && lastLine === current.lineCount - 1 &&
      (blockIndex + 1 >= document.blocks.length || !document.blocks[blockIndex + 1].title);
    fragment.blockId = current.block.id;
    fragment.blockIndex = blockIndex;
    // Render only the lines owned by this page. Painting the full block and clipping at a line metric boundary
    // cuts italic/anti-aliased ink at the top and may expose one or two pixels of the next line at the bottom.
    // A page-local paragraph contains no neighbouring lines, so a small ink bleed is safe and layout-neutral.
    // A block that fits on the page whole is the common case: its measured paragraph already is that
    // page-local paragraph, so laying the same text out a second time is skipped.
    // Line indices are relative to the measured slice (the whole block except for a drop-cap paragraph).
    const sliceStart = current.sliceStart + first.startIndex;
    const sliceEnd = current.sliceStart + last.endIndex;
    const layoutWidth = current.widthPx > 0 ? current.widthPx : width;
    const wholeBlock = firstLine === 0 && lastLine === current.lineCount - 1 &&
      first.startIndex === 0 && sliceEnd === current.sliceEnd;
    fragment.paragraph = wholeBlock ? current.paragraph :
      ReaderV2Paginator.buildParagraph(document, current.block, snapshot, regexStyles, layoutWidth,
        sliceStart, sliceEnd, false, paragraphCache, stretchPx);
    fragment.selectionRuns = ReaderV2Paginator.buildSelectionRuns(document, current.block, snapshot, regexStyles,
      sliceStart, sliceEnd);
    let runOffset = current.block.displayStart + sliceStart;
    const needsOutline = fragment.selectionRuns.some((run: ReaderV2SelectionRun): boolean => {
      const requested = ReaderV2Paginator.requestedWeightAt(document, current.block, runOffset, snapshot, regexStyles);
      runOffset += run.text.length;
      return ReaderFontWeight.isStatic(run.fontFamily) && requested > ReaderFontWeight.DEFAULT;
    });
    if (needsOutline) {
      const outline = ReaderV2Paginator.buildParagraph(document, current.block, snapshot, regexStyles, layoutWidth,
        sliceStart, sliceEnd, true, paragraphCache, stretchPx);
      fragment.fontStrokes = ReaderFontStroke.build(outline, snapshot.fontWeight,
        (offset: number): graphicsText.TextStyle => ReaderV2Paginator.styleAt(document, current.block,
          current.block.displayStart + sliceStart + offset, snapshot, regexStyles),
        (offset: number): number => ReaderV2Paginator.requestedWeightAt(document, current.block,
          current.block.displayStart + sliceStart + offset, snapshot, regexStyles));
    }
    fragment.titleContinuation = current.block.title && current.block.titleSegment > 0;
    fragment.leadReservePx = current.leadPx > 0 ? current.leadPx :
      ReaderV2Paginator.titleLeadReserve(document, current.block, snapshot, width);
    fragment.paragraphX = x + fragment.leadReservePx +
      ReaderV2Paginator.titleDecorationInset(current.block, regexStyles, width);
    fragment.paragraphY = y;
    fragment.paragraphHeight = paragraphLineBottom - paragraphLineTop;
    const localCount = fragment.paragraph.getLineCount();
    const firstLocal = wholeBlock ? current.line(0) : fragment.paragraph.getLineMetrics(0);
    const lastLocal = wholeBlock ? current.line(current.lineCount - 1) :
      fragment.paragraph.getLineMetrics(Math.max(0, localCount - 1));
    const topInkBleedPx = firstLocal ? ReaderV2Paginator.lineTopInkGuard(firstLocal) : 1;
    const bottomInkBleedPx = lastLocal ? ReaderV2Paginator.lineBottomInkGuard(lastLocal) : 1;
    let strokeBleed = 0;
    for (const stroke of fragment.fontStrokes) strokeBleed = Math.max(strokeBleed, stroke.pen.getWidth() / 2 + 1);
    fragment.clipRect = new ReaderV2Rect(x + current.leadPx - strokeBleed, y - topInkBleedPx - strokeBleed,
      x + width + strokeBleed, y + paragraphLineBottom - paragraphLineTop + bottomInkBleedPx + strokeBleed);
    fragment.localStart = sliceStart;
    fragment.localEnd = sliceEnd;
    fragment.displayStart = current.block.displayStart + fragment.localStart;
    fragment.displayEnd = current.block.displayStart + fragment.localEnd;
    ReaderV2Paginator.appendRegexDecorations(fragment, regexStyles, snapshot.viewport.left,
      snapshot.viewport.right);
    if (!fragment.title) fragment.regexRanges = ReaderV2Paginator.regexRangesIn(fragment, regexStyles);
    return fragment;
  }

  /** 落在片段里的正则字体区间（显示偏移），给“仅正则字体”文字划线用；标题强调（repeatCaps）不算。 */
  private static regexRangesIn(fragment: ReaderV2PageFragment, regexStyles: ReaderV2SpanStyleRange[]): number[] {
    const hits: number[][] = [];
    for (const style of regexStyles) {
      if (style.repeatCaps || style.end <= fragment.displayStart || style.start >= fragment.displayEnd) continue;
      const start = Math.max(fragment.displayStart, style.start);
      const end = Math.min(fragment.displayEnd, style.end);
      if (end > start) hits.push([start, end]);
    }
    if (hits.length === 0) return [];
    hits.sort((left: number[], right: number[]): number => left[0] - right[0]);
    // 相邻或重叠的命中并成一段：半透明的线不会叠深，两条规则交界处也不断开。
    const ranges: number[] = [];
    for (const hit of hits) {
      if (ranges.length >= 2 && hit[0] <= ranges[ranges.length - 1]) {
        ranges[ranges.length - 1] = Math.max(ranges[ranges.length - 1], hit[1]);
      } else {
        ranges.push(hit[0], hit[1]);
      }
    }
    return ranges;
  }

  private static appendRegexDecorations(fragment: ReaderV2PageFragment,
    regexStyles: ReaderV2SpanStyleRange[], viewportLeft: number, viewportRight: number): void {
    if (!fragment.paragraph) return;
    for (const style of regexStyles) {
      if (!ReaderV2BubbleFrame.decorates(style) || !style.decorationStyleId ||
        style.end <= fragment.displayStart || style.start >= fragment.displayEnd) continue;
      const localStart = Math.max(0, style.start - fragment.displayStart);
      const localEnd = Math.min(fragment.localEnd - fragment.localStart, style.end - fragment.displayStart);
      if (localEnd <= localStart) continue;
      const fragmentText = fragment.selectionRuns.map((run: ReaderV2SelectionRun): string => run.text).join('');
      const lines = fragment.paragraph.getLineMetrics();
      for (const line of lines) {
        const segmentStart = Math.max(localStart, line.startIndex);
        const segmentEnd = Math.min(localEnd, line.endIndex);
        if (segmentEnd <= segmentStart) continue;
        const boxes = fragment.paragraph.getRectsForRange({ start: segmentStart, end: segmentEnd },
          graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
        if (boxes.length === 0) continue;
        // A single logical regex run can be split into several native glyph runs when it contains
        // punctuation, emoji or another character that falls back to a different font. Harmony then
        // returns one rect for each glyph run even though all of them are on this same visual line.
        // Using only boxes[0] made the bubble appear to stop at the first special symbol. Merge every
        // rect owned by this line so the decoration follows the complete regex match.
        let boxLeft = boxes[0].rect.left;
        let boxTop = boxes[0].rect.top;
        let boxRight = boxes[0].rect.right;
        let boxBottom = boxes[0].rect.bottom;
        for (let boxIndex = 1; boxIndex < boxes.length; boxIndex++) {
          const nextBox = boxes[boxIndex].rect;
          boxLeft = Math.min(boxLeft, nextBox.left);
          boxTop = Math.min(boxTop, nextBox.top);
          boxRight = Math.max(boxRight, nextBox.right);
          boxBottom = Math.max(boxBottom, nextBox.bottom);
        }
        const segment = new ReaderV2RegexBubbleSegment();
        segment.styleId = style.decorationStyleId;
        segment.capDark = style.decorationDark;
        segment.text = fragmentText.substring(segmentStart, segmentEnd);
        segment.leading = style.repeatCaps || (style.start >= fragment.displayStart && segmentStart === localStart);
        segment.trailing = style.repeatCaps || (style.end <= fragment.displayEnd && segmentEnd === localEnd);
        segment.capSizePx = style.decorationSizePx;
        segment.fontSizePx = style.fontSizePx;
        segment.fontFamily = style.fontFamily;
        segment.textColor = style.color;
        segment.backgroundColor = style.backgroundColor;
        segment.radiusTopLeftPx = segment.leading ? style.radiusTopLeftPx : 0;
        segment.radiusBottomLeftPx = segment.leading ? style.radiusBottomLeftPx : 0;
        segment.radiusTopRightPx = segment.trailing ? style.radiusTopRightPx : 0;
        segment.radiusBottomRightPx = segment.trailing ? style.radiusBottomRightPx : 0;
        segment.shadowEnabled = style.shadowEnabled;
        segment.shadowColor = style.shadowColor;
        segment.shadowRadiusPx = style.shadowRadiusPx;
        segment.shadowOffsetXPx = style.shadowOffsetXPx;
        segment.shadowOffsetYPx = style.shadowOffsetYPx;
        const textLeft = fragment.paragraphX + boxLeft;
        const textRight = fragment.paragraphX + boxRight;
        if (style.frameAsset) {
          const glyphCenterY = fragment.paragraphY + (boxTop + boxBottom) / 2;
          ReaderV2Paginator.placeFramedSegment(segment, style, textLeft, textRight, glyphCenterY,
            viewportLeft + 1, viewportRight - 1);
          if (segment.rect.right > segment.rect.left) fragment.regexBubbleSegments.push(segment);
          continue;
        }
        const contentLeft = style.repeatCaps ? fragment.clipRect.left : fragment.paragraphX;
        const contentRight = fragment.clipRect.right;
        // Leading space is reserved on the preceding glyph, while trailing space is part of the decorated run's
        // last glyph advance. Keep both caps inside that measured space and hard-clip them to the text column.
        // This prevents decorations from invading neighbouring text or crossing the user's left/right margins.
        const left = Math.max(contentLeft,
          textLeft - (segment.leading ? style.decorationSizePx : 0));
        const right = Math.min(contentRight, textRight + (style.repeatCaps ? style.decorationSizePx : 0));
        segment.leadingCapWidthPx = segment.leading ?
          Math.max(0, Math.min(style.decorationSizePx, textLeft - left)) : 0;
        segment.trailingCapWidthPx = segment.trailing ?
          Math.max(0, Math.min(style.decorationSizePx, right - left - segment.leadingCapWidthPx)) : 0;
        // RectHeightStyle.TIGHT follows the actual native glyph run. Add a small deterministic cushion for the
        // bubble background and let the caps expand it when necessary. This keeps decoration geometry centred on
        // the already-laid-out text without introducing a second text baseline.
        const glyphTop = fragment.paragraphY + boxTop;
        const glyphBottom = fragment.paragraphY + boxBottom;
        const glyphCenter = (glyphTop + glyphBottom) / 2;
        const verticalPadding = Math.max(1, style.fontSizePx * 0.08);
        const capHalf = style.decorationSizePx / 2;
        const top = Math.min(glyphTop - verticalPadding, glyphCenter - capHalf);
        const bottom = Math.max(glyphBottom + verticalPadding, glyphCenter + capHalf);
        if (right > left) {
          segment.rect = new ReaderV2Rect(left, top, right, bottom);
          fragment.regexBubbleSegments.push(segment);
        }
      }
    }
  }

  /**
   * Line piece of a run that has a theme frame. Ends of the whole run sit in the space reserved by
   * decorationReservationAfter (frame end inside, cap outside). At a line break the frame either draws both ends
   * outward into the page margin, never reflowing the text, or is cut flat at the text edge.
   */
  private static placeFramedSegment(segment: ReaderV2RegexBubbleSegment, style: ReaderV2SpanStyleRange,
    textLeft: number, textRight: number, centerY: number, limitLeft: number, limitRight: number): void {
    const capW = style.decorationSizePx > 0 ? style.decorationSizePx : 0;
    const leadW = ReaderV2BubbleFrame.leadPx(style);
    const trailW = ReaderV2BubbleFrame.trailPx(style);
    segment.frameLeadEnd = segment.leading || !style.frameCut;
    segment.frameTrailEnd = segment.trailing || !style.frameCut;
    let frameLeft = textLeft - (segment.frameLeadEnd ? leadW : 0);
    // A run's real end already contains the cap + frame reservation in its last glyph advance.
    let frameRight = segment.trailing && !style.repeatCaps ? textRight - capW :
      textRight + (segment.frameTrailEnd ? trailW : 0);
    const rectLeft = Math.max(limitLeft, frameLeft - (segment.leading ? capW : 0));
    const rectRight = Math.min(limitRight, frameRight + (segment.trailing ? capW : 0));
    frameLeft = Math.max(frameLeft, rectLeft);
    frameRight = Math.min(frameRight, rectRight);
    segment.leadingCapWidthPx = segment.leading ? Math.max(0, Math.min(capW, frameLeft - rectLeft)) : 0;
    segment.trailingCapWidthPx = segment.trailing ? Math.max(0, Math.min(capW, rectRight - frameRight)) : 0;
    const bandHalf = ReaderV2BubbleFrame.bandPx(style.fontSizePx) / 2;
    const half = Math.max(bandHalf, capW / 2);
    segment.frameRect = new ReaderV2Rect(frameLeft, centerY - bandHalf, frameRight, centerY + bandHalf);
    segment.frameAsset = style.frameAsset;
    segment.frameAspect = style.frameAspect;
    segment.frameSliceLeft = style.frameSliceLeft;
    segment.frameSliceRight = style.frameSliceRight;
    segment.frameSliceTop = style.frameSliceTop;
    segment.frameSliceBottom = style.frameSliceBottom;
    segment.frameRound = style.frameRound;
    segment.frameTint = style.frameTint;
    segment.rect = frameRight > frameLeft ? new ReaderV2Rect(rectLeft, centerY - half, rectRight, centerY + half) :
      new ReaderV2Rect();
  }

  private static finalizePageSelection(page: ReaderV2PageLayout): void {
    if (page.fragments.length === 0) return;
    let text = '';
    let first: ReaderV2PageFragment | null = null;
    let last: ReaderV2PageFragment | null = null;
    for (const fragment of page.fragments) {
      if (!fragment.paragraph) {
        // Image fragments own no selectable text: the transparent selection Text only contains prose.
        fragment.selectionPageStart = text.length;
        fragment.selectionPageEnd = text.length;
        continue;
      }
      if (last && !fragment.blockContinuation) {
        text += '\n';
        last.selectionBreakAfter = true;
      }
      fragment.selectionPageStart = text.length;
      for (const run of fragment.selectionRuns) text += run.text;
      fragment.selectionPageEnd = text.length;
      if (!first) first = fragment;
      last = fragment;
    }
    if (!first || !last) return;
    page.selectionText = text;
    page.selectionX = page.contentRect.left;
    page.selectionY = first.paragraphY;
    page.selectionWidth = page.contentRect.width();
    page.selectionHeight = Math.max(1, last.paragraphY + last.paragraphHeight - first.paragraphY);
  }

  private static buildSelectionRuns(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], sliceStart: number,
    sliceEnd: number): ReaderV2SelectionRun[] {
    const result: ReaderV2SelectionRun[] = [];
    const safeStart = Math.max(0, Math.min(block.text.length, sliceStart));
    const safeEnd = Math.max(safeStart, Math.min(block.text.length, sliceEnd));
    const boundaries = ReaderV2Paginator.styleBoundaries(document, block, regexStyles, safeStart, safeEnd,
      !!snapshot.commentBubble.image);
    for (let index = 0; index < boundaries.length - 1; index++) {
      const start = boundaries[index];
      const end = boundaries[index + 1];
      if (end <= start) continue;
      const style = ReaderV2Paginator.styleAt(document, block, block.displayStart + start, snapshot, regexStyles);
      const families = style.fontFamilies;
      result.push(new ReaderV2SelectionRun(block.text.substring(start, end), Number(style.fontSize),
        families && families.length > 0 ? families[0] : '',
        style.fontVariations && style.fontVariations.length > 0 ? style.fontVariations[0].value : snapshot.fontWeight,
        Number(style.letterSpacing || 0)));
    }
    return result;
  }

  /** Measure the padded label in the same face and weight used by the paragraph. */
  private static commentTextWidth(style: graphicsText.TextStyle, label: string,
    snapshot: ReaderV2LayoutSnapshot): number {
    const key = JSON.stringify([style.fontFamilies, style.fontSize, style.fontWeight, style.fontVariations, label]);
    const cached = snapshot.commentTextWidths.get(key);
    if (cached !== undefined) return cached;
    const builder = new graphicsText.ParagraphBuilder({ textStyle: style },
      graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(label);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, style.fontSize ?? 1) * Math.max(4, label.length * 2));
    // Range bounds include both non-breaking pads, even when longest-line metrics trim trailing spaces.
    const boxes = paragraph.getRectsForRange({ start: 0, end: label.length },
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    let left = Number.POSITIVE_INFINITY;
    let right = Number.NEGATIVE_INFINITY;
    for (const box of boxes) {
      left = Math.min(left, box.rect.left);
      right = Math.max(right, box.rect.right);
    }
    const width = Number.isFinite(left) && Number.isFinite(right) ? Math.max(0, right - left) : 0;
    if (snapshot.commentTextWidths.size >= 128) snapshot.commentTextWidths.clear();
    snapshot.commentTextWidths.set(key, width);
    return width;
  }

  /** Measure with the actual face/fallback and weight, without line spacing or an existing baseline shift. */
  private static commentTextCenter(style: graphicsText.TextStyle, label: string,
    snapshot: ReaderV2LayoutSnapshot): number {
    const key = JSON.stringify([style.fontFamilies, style.fontSize, style.fontWeight, style.fontVariations, label]);
    const cached = snapshot.commentTextCenters.get(key);
    if (cached !== undefined) return cached;
    const builder = new graphicsText.ParagraphBuilder({ textStyle: style, includeFontPadding: true },
      graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(label);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, (style.fontSize ?? 1) + Math.abs(style.letterSpacing ?? 0)) *
      Math.max(4, label.length * 2));
    const boxes = paragraph.getRectsForRange({ start: 0, end: label.length },
      graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    let top = Number.POSITIVE_INFINITY;
    let bottom = Number.NEGATIVE_INFINITY;
    for (const box of boxes) {
      if (box.rect.right <= box.rect.left || box.rect.bottom <= box.rect.top) continue;
      top = Math.min(top, box.rect.top);
      bottom = Math.max(bottom, box.rect.bottom);
    }
    const center = Number.isFinite(top) ? (top + bottom) / 2 - paragraph.getAlphabeticBaseline() : 0;
    // Source actions may contain arbitrary labels; keep the per-layout measurement cache bounded.
    if (snapshot.commentTextCenters.size >= 128) snapshot.commentTextCenters.clear();
    snapshot.commentTextCenters.set(key, center);
    return center;
  }

  private static appendActionAreas(page: ReaderV2PageLayout, fragment: ReaderV2PageFragment,
    actions: ReaderV2InlineAction[], snapshot: ReaderV2LayoutSnapshot): void {
    if (!fragment.paragraph) return;
    const firstAction = ReaderV2Paginator.firstActionWhoseEndExceeds(actions, fragment.displayStart);
    for (let index = firstAction; index < actions.length; index++) {
      const action = actions[index];
      if (action.displayStart >= fragment.displayEnd) break;
      if (action.displayEnd <= fragment.displayStart || action.displayStart >= fragment.displayEnd) continue;
      const start = Math.max(0, action.displayStart - fragment.displayStart);
      const end = Math.min(fragment.localEnd - fragment.localStart, action.displayEnd - fragment.displayStart);
      if (end <= start) continue;
      const boxes = fragment.paragraph.getRectsForRange({ start: start, end: end },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.MAX);
      for (const box of boxes) {
        const left = Math.max(fragment.clipRect.left, fragment.paragraphX + box.rect.left);
        const top = Math.max(fragment.clipRect.top, fragment.paragraphY + box.rect.top);
        const right = Math.min(fragment.clipRect.right, fragment.paragraphX + box.rect.right);
        const bottom = Math.min(fragment.clipRect.bottom, fragment.paragraphY + box.rect.bottom);
        if (right <= left || bottom <= top) continue;
        const hit = new ReaderV2ActionHitArea();
        hit.actionId = action.id;
        hit.marker = action.marker;
        hit.rect = new ReaderV2Rect(left, top, right, bottom);
        page.actions.push(hit);
      }
      if (!action.note) ReaderV2Paginator.appendCommentBubble(fragment, action, snapshot);
    }
  }

  /**
   * One bubble piece per visual line the label occupies. The height comes from the comment font rather than the
   * glyph boxes so counts, CJK labels and padding spaces all get the same bubble height.
   */
  /**
   * Letter spacing [before, after] an image bubble so the artwork's left and right reach does not cover the
   * neighbouring text; the bubble rect already spans inflateX on each side. Zero for shape bubbles.
   */
  private static commentImageReserve(snapshot: ReaderV2LayoutSnapshot, scale: number): number[] {
    const style = snapshot.commentBubble;
    if (!style.image) return [0, 0];
    const height = ReaderCommentBubblePainter.heightFor(snapshot.commentFontSizePx) * scale;
    const insets = ReaderCommentBubblePainter.imageInsets(height, style);
    const inflateX = snapshot.commentFontSizePx * 0.18 * scale;
    return [Math.max(0, insets[0] - inflateX), Math.max(0, insets[2] - inflateX)];
  }

  private static appendCommentBubble(fragment: ReaderV2PageFragment, action: ReaderV2InlineAction,
    snapshot: ReaderV2LayoutSnapshot): void {
    if (!fragment.paragraph) return;
    const localStart = Math.max(0, action.bubbleStart - fragment.displayStart);
    const localEnd = Math.min(fragment.localEnd - fragment.localStart, action.displayEnd - fragment.displayStart);
    if (localEnd <= localStart) return;
    const scale = ReaderCommentBubbleSize.scale(action.label, snapshot.commentBubbleSize);
    const height = ReaderCommentBubblePainter.heightFor(snapshot.commentFontSizePx) * scale;
    const inflateX = snapshot.commentFontSizePx * 0.18 * scale;
    const pieces: ReaderV2CommentBubbleSegment[] = [];
    for (const line of fragment.paragraph.getLineMetrics()) {
      const segmentStart = Math.max(localStart, line.startIndex);
      const segmentEnd = Math.min(localEnd, line.endIndex);
      if (segmentEnd <= segmentStart) continue;
      const boxes = fragment.paragraph.getRectsForRange({ start: segmentStart, end: segmentEnd },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
      let left = Number.POSITIVE_INFINITY;
      let right = Number.NEGATIVE_INFINITY;
      let top = Number.POSITIVE_INFINITY;
      let bottom = Number.NEGATIVE_INFINITY;
      for (const box of boxes) {
        if (box.rect.right <= box.rect.left) continue;
        left = Math.min(left, box.rect.left);
        right = Math.max(right, box.rect.right);
        if (box.rect.bottom > box.rect.top) {
          top = Math.min(top, box.rect.top);
          bottom = Math.max(bottom, box.rect.bottom);
        }
      }
      if (!Number.isFinite(left) || !Number.isFinite(top)) continue;
      const centerY = fragment.paragraphY + (top + bottom) / 2;
      const segment = new ReaderV2CommentBubbleSegment();
      segment.style = snapshot.commentBubble;
      segment.scale = scale;
      segment.tail = false;
      segment.rect = new ReaderV2Rect(fragment.paragraphX + left - inflateX, centerY - height / 2,
        fragment.paragraphX + right + inflateX, centerY + height / 2);
      pieces.push(segment);
    }
    if (pieces.length === 0) return;
    pieces[pieces.length - 1].tail = action.displayEnd <= fragment.displayEnd;
    if (pieces[pieces.length - 1].tail) {
      // The last pad's trailing spacing reserves room after an image bubble; keep it outside the text box.
      const last = pieces[pieces.length - 1];
      const reserve = ReaderV2Paginator.commentImageReserve(snapshot, scale)[1];
      last.rect.right = Math.max(last.rect.left + 1, last.rect.right - reserve);
    }
    for (const piece of pieces) fragment.commentBubbleSegments.push(piece);
  }

  /** Centre x of the last hit area this page has for the action (its count bubble), or -1. */
  private static bubbleCenterX(page: ReaderV2PageLayout, actionId: string): number {
    for (let index = page.actions.length - 1; index >= 0; index--) {
      const area = page.actions[index];
      if (area.actionId === actionId) return (area.rect.left + area.rect.right) / 2;
    }
    return -1;
  }

  private static firstActionWhoseEndExceeds(actions: ReaderV2InlineAction[], offset: number): number {
    let low = 0;
    let high = actions.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (actions[middle].displayEnd <= offset) low = middle + 1;
      else high = middle;
    }
    return low;
  }

  private static lineBottom(line: graphicsText.LineMetrics): number {
    return line.topHeight + line.height;
  }

  private static lineTopInkGuard(line: graphicsText.LineMetrics): number {
    const ascent = Math.abs(line.ascent);
    const inkTop = line.baseline - ascent;
    const overflow = Math.max(0, line.topHeight - inkTop);
    return Math.max(1, Math.ceil(overflow + 0.01));
  }

  private static lineBottomInkGuard(line: graphicsText.LineMetrics): number {
    const descent = Math.abs(line.descent);
    const inkBottom = line.baseline + descent;
    const overflow = Math.max(0, inkBottom - ReaderV2Paginator.lineBottom(line));
    return Math.max(1, Math.ceil(overflow + 0.01));
  }

  private static graphicsColor(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }
}
