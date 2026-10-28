/** 固定尺寸平移轮播的槽位与手势计算；两本时不复制同一本填满两侧。 */
export class RecentReadCarouselGeometry {
  // 保留相邻两侧的绘制槽位，整次手势内不取模换边。只有书籍索引循环。
  static slots(anchor: number, count: number): number[] {
    if (count <= 0) return [];
    if (count === 1) return [0];
    if (count === 2) return [0, 1];
    return [anchor - 2, anchor - 1, anchor, anchor + 1, anchor + 2];
  }

  static wrap(index: number, count: number): number {
    return count > 0 ? ((index % count) + count) % count : 0;
  }

  static target(current: number, offset: number, velocity: number, count: number): number {
    if (count <= 1) return 0;
    const direction = Math.abs(offset) >= 32 ? (offset < 0 ? 1 : -1) :
      (Math.abs(velocity) >= 500 ? (velocity < 0 ? 1 : -1) : 0);
    return count === 2 ? Math.max(0, Math.min(1, current + direction)) : current + direction;
  }
}
