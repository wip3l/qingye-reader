import { ReaderV2PaginationSession } from './ReaderV2Paginator';
import { ReaderPaginationIndexState } from './ReaderPaginationIndex';

export interface PageTurnPreview {
  text: string;
  secondaryText?: string;
  pageIndex: number;
  chapterIndex: number;
  pageStart?: number;
  secondaryPageStart?: number;
  documentSource?: string;
}

export interface ReaderParagraphMetrics { heightPx: number; lineEnds: number[]; lineBottomsPx: number[]; lineCount: number; }
export interface ReaderTextParagraph { text: string; start: number; end: number; index: number; isLast: boolean; key: string; }
export interface ReaderInlineActionBoundsTask {
  text: string; marker: string; left: number; top: number; width: number; height: number; pageIdentity: string; attempts: number;
}
export interface ReaderMergedActionBoundsTask {
  paragraphs: ReaderTextParagraph[]; selectableKey: string; left: number; top: number; pageIdentity: string; attempts: number;
}
export interface ReadTextSlice { text: string; start: number; end: number; highlighted: boolean; ruleIndex: number; ttsHighlighted?: boolean; key: string; }
export interface ReaderPaginationResult extends ReaderPaginationIndexState {
  v2Session?: ReaderV2PaginationSession;
  persistenceScheduled?: boolean;
}
export interface ReaderMixedPaginationMetrics { availableWidth: number; availableHeightPx: number; }
export interface ReaderViewportSize { width: number; height: number; }
export interface ReaderTextParagraphGroup { paragraphs: ReaderTextParagraph[]; mergeable: boolean; key: string; }
export interface ReaderParagraphMeasureFallback { fontSize: number; fontFamily: string; }
export interface ReaderV2HighlightRect { leftPx: number; topPx: number; widthPx: number; heightPx: number; key: string; }
export interface ReaderContinuousSelectionChunk { pageIndex: number; key: string; text: string; left: number; top: number; right: number; bottom: number; }
