/**
 * Placement of the built-in paper decorations, shared by the live ReaderThemeBackground component and the
 * self-drawn page raster so both put the ornaments at the same spot. All values are vp.
 */
export class ReaderThemeDecorationLayout {
  static size(viewportWidth: number, viewportHeight: number, compact: boolean): number {
    const fallback = compact ? 42 : 156;
    if (viewportWidth <= 0 || viewportHeight <= 0) return fallback;
    const shortEdge = Math.min(viewportWidth, viewportHeight);
    if (compact) return Math.max(30, Math.min(54, shortEdge * 0.72));
    // Size follows the short edge, so portrait, landscape, tablet and split
    // window layouts preserve the ornament's proportions without device rules.
    return Math.max(112, Math.min(260, shortEdge * 0.36));
  }

  static inset(viewportWidth: number, viewportHeight: number, compact: boolean): number {
    if (compact) return 2;
    const shortEdge = viewportWidth <= 0 || viewportHeight <= 0 ? 480 : Math.min(viewportWidth, viewportHeight);
    return Math.max(8, Math.min(22, shortEdge * 0.025));
  }
}
