/** 书架、发现和搜索结果共用的封面平铺横向布局。传入包含左右内边距的容器宽度（vp）。 */
export class BookTileLayout {
  static readonly SIDE_PADDING: number = 20;
  private static readonly TARGET_COVER_WIDTH: number = 104;
  private static readonly PREFERRED_COLUMN_GAP: number = 20;

  static contentWidth(viewportWidth: number): number {
    return Math.max(1, viewportWidth - BookTileLayout.SIDE_PADDING * 2);
  }

  static columnCount(viewportWidth: number): number {
    // 以手机端约 104vp 的封面宽度为视觉基准，展开屏增加列数而不是放大封面。
    const fittedCount = Math.round(
      (BookTileLayout.contentWidth(viewportWidth) + BookTileLayout.PREFERRED_COLUMN_GAP) /
      (BookTileLayout.TARGET_COVER_WIDTH + BookTileLayout.PREFERRED_COLUMN_GAP)
    );
    return Math.max(3, Math.min(24, fittedCount));
  }

  static columnGap(viewportWidth: number): number {
    const columnCount = BookTileLayout.columnCount(viewportWidth);
    const fittedGap = (BookTileLayout.contentWidth(viewportWidth) -
      BookTileLayout.TARGET_COVER_WIDTH * columnCount) / (columnCount - 1);
    // 只在原 20vp 附近微调间距，避免宽屏上书籍过散或挤在一起。
    return Math.max(16, Math.min(24, fittedGap));
  }
}
