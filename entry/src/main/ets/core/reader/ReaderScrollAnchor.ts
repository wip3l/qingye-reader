/** A content position survives wrapping changes; the viewport displacement is reused only for the same layout. */
export class ReaderScrollAnchor {
  version: number = 1;
  chapterIndex: number = 0;
  chapterUrl: string = '';
  pageIndex: number = 0;
  sourceIdentity: string = '';
  offset: number = 0;
  viewportOffsetVp: number = 0;
  layoutIdentity: string = '';

  static readonly VARIABLE_KEY: string = 'readProgressScrollAnchorV1';

  static decode(raw: string, chapterIndex: number, offset: number): ReaderScrollAnchor | null {
    if (!raw || raw.length > 8192) return null;
    try {
      const anchor = JSON.parse(raw) as ReaderScrollAnchor;
      if (!anchor || anchor.version !== 1 || anchor.chapterIndex !== chapterIndex || anchor.offset !== offset ||
        !Number.isInteger(anchor.chapterIndex) || anchor.chapterIndex < 0 ||
        !Number.isInteger(anchor.pageIndex) || anchor.pageIndex < 0 ||
        !Number.isInteger(anchor.offset) || anchor.offset < 0 ||
        !Number.isFinite(anchor.viewportOffsetVp) || Math.abs(anchor.viewportOffsetVp) > 100000 ||
        typeof anchor.chapterUrl !== 'string' || typeof anchor.sourceIdentity !== 'string' ||
        !anchor.sourceIdentity || typeof anchor.layoutIdentity !== 'string' || !anchor.layoutIdentity) return null;
      return anchor;
    } catch (_) {
      return null;
    }
  }
}
