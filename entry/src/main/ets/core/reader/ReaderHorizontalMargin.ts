/** 阅读正文和预览共用的水平边距；窄列保留文字宽度，放宽后恢复原设置。 */
export class ReaderHorizontalMargin {
  static effective(marginLeft: number, marginRight: number, columnWidth: number,
    fontSize: number, left: boolean): number {
    const rawLeft = Math.max(0, marginLeft);
    const rawRight = Math.max(0, marginRight);
    const total = rawLeft + rawRight;
    if (total <= 0) return 0;
    const minimumTextWidth = Math.min(columnWidth, Math.max(96, fontSize * 4.8));
    const allowedTotal = Math.max(0, columnWidth - minimumTextWidth);
    const scale = total > allowedTotal ? allowedTotal / total : 1;
    return (left ? rawLeft : rawRight) * scale;
  }
}
