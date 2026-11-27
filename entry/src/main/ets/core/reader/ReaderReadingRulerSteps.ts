/**
 * 阅读尺：突出正在读的几行。这里是和界面无关的部分——设置取值、一页里的行怎么排、尺怎么移动——方便单独测试。
 *
 * 一页（双页时两栏）的“行”按从上到下、先左栏后右栏排成一列，每行带所在的栏号。尺盖住从 index 起、同一栏里的
 * lines 行。点“下一页”先在本栏往下移 lines 行，到栏底换到下一栏的第一行，最后一栏也到底了才真正翻页；
 * “上一页”反过来，翻到上一页后尺停在最后几行。
 */
export class ReaderRulerRow {
  top: number = 0;
  bottom: number = 0;
  column: number = 0;

  constructor(top: number, bottom: number, column: number) {
    this.top = top;
    this.bottom = bottom;
    this.column = column;
  }
}

export class ReaderRulerStep {
  /** 移动后的首行；turn 为 true 时尺没动，调用方去翻页。 */
  index: number = 0;
  turn: boolean = false;

  constructor(index: number, turn: boolean) {
    this.index = index;
    this.turn = turn;
  }
}

/** 画尺要用的位置，单位 vp、相对阅读页根层左上角。width 为 -1 表示铺满整宽。 */
export class ReaderRulerGeometry {
  visible: boolean = false;
  key: string = '';
  bandTop: number = 0;
  bandBottom: number = 0;
  areaTop: number = 0;
  areaBottom: number = 0;
  left: number = 0;
  width: number = -1;
  /** 双页时另一栏：遮罩整栏盖住；盖住下文只盖后面那栏。 */
  hasOther: boolean = false;
  otherBefore: boolean = false;
  otherLeft: number = 0;
  otherWidth: number = 0;
}

export class ReaderReadingRulerSteps {
  static readonly STYLE_MASK: string = 'mask';
  static readonly STYLE_BAND: string = 'band';
  static readonly STYLE_COVER: string = 'cover';
  static readonly STYLES: string[] = ['mask', 'band', 'cover'];
  static readonly STYLE_LABELS: string[] = ['遮罩', '色带', '盖住下文'];
  static readonly MIN_LINES: number = 1;
  static readonly MAX_LINES: number = 3;
  static readonly DEFAULT_LINES: number = 2;
  static readonly MIN_STRENGTH: number = 30;
  static readonly MAX_STRENGTH: number = 95;
  static readonly DEFAULT_STRENGTH: number = 70;

  static normalizeStyle(value: string): string {
    return ReaderReadingRulerSteps.STYLES.indexOf(value) >= 0 ? value : ReaderReadingRulerSteps.STYLE_MASK;
  }

  static normalizeLines(value: number): number {
    if (!Number.isFinite(value)) return ReaderReadingRulerSteps.DEFAULT_LINES;
    return Math.min(ReaderReadingRulerSteps.MAX_LINES, Math.max(ReaderReadingRulerSteps.MIN_LINES, Math.round(value)));
  }

  static normalizeStrength(value: number): number {
    if (!Number.isFinite(value)) return ReaderReadingRulerSteps.DEFAULT_STRENGTH;
    return Math.min(ReaderReadingRulerSteps.MAX_STRENGTH,
      Math.max(ReaderReadingRulerSteps.MIN_STRENGTH, Math.round(value)));
  }

  /**
   * 整理一页的行：按栏、再按上边排序；上下重叠过半的并成一行（首字绕排、同一行被拆成两个片段时会这样）。
   */
  static mergeRows(rows: ReaderRulerRow[]): ReaderRulerRow[] {
    const sorted = rows.filter((row: ReaderRulerRow): boolean => row.bottom > row.top)
      .sort((left: ReaderRulerRow, right: ReaderRulerRow): number =>
        left.column - right.column || left.top - right.top || left.bottom - right.bottom);
    const result: ReaderRulerRow[] = [];
    for (const row of sorted) {
      const last = result.length > 0 ? result[result.length - 1] : null;
      if (last && last.column === row.column) {
        const overlap = Math.min(last.bottom, row.bottom) - Math.max(last.top, row.top);
        if (overlap > 0.5 * Math.min(last.bottom - last.top, row.bottom - row.top)) {
          last.top = Math.min(last.top, row.top);
          last.bottom = Math.max(last.bottom, row.bottom);
          continue;
        }
      }
      result.push(new ReaderRulerRow(row.top, row.bottom, row.column));
    }
    return result;
  }

  /** 尺实际盖住的行：[首行, 末行]，不跨栏。 */
  static span(rows: ReaderRulerRow[], index: number, lines: number): number[] {
    if (rows.length === 0) return [];
    const first = Math.max(0, Math.min(rows.length - 1, index));
    let last = first;
    while (last + 1 < rows.length && last + 1 < first + lines && rows[last + 1].column === rows[first].column) last++;
    return [first, last];
  }

  /** 翻到上一页后尺的位置：最后一栏的最后几行。 */
  static lastIndex(rows: ReaderRulerRow[], lines: number): number {
    if (rows.length === 0) return 0;
    return Math.max(ReaderReadingRulerSteps.columnStart(rows, rows.length - 1), rows.length - lines);
  }

  static clampIndex(rows: ReaderRulerRow[], index: number): number {
    return rows.length === 0 ? 0 : Math.max(0, Math.min(rows.length - 1, Math.round(index)));
  }

  /** 往下走时不跨栏：本栏剩下的行不够 lines 时，下一步从下一栏的第一行开始；全走完了 turn 为 true。 */
  static next(rows: ReaderRulerRow[], index: number, lines: number): ReaderRulerStep {
    if (rows.length === 0) return new ReaderRulerStep(0, true);
    const current = ReaderReadingRulerSteps.clampIndex(rows, index);
    const span = ReaderReadingRulerSteps.span(rows, current, lines);
    const after = span[1] + 1;
    if (after >= rows.length) return new ReaderRulerStep(current, true);
    return new ReaderRulerStep(after, false);
  }

  static previous(rows: ReaderRulerRow[], index: number, lines: number): ReaderRulerStep {
    if (rows.length === 0) return new ReaderRulerStep(0, true);
    const current = ReaderReadingRulerSteps.clampIndex(rows, index);
    const start = ReaderReadingRulerSteps.columnStart(rows, current);
    if (current - lines >= start) return new ReaderRulerStep(current - lines, false);
    if (current > start) return new ReaderRulerStep(start, false);
    if (start === 0) return new ReaderRulerStep(current, true);
    // 退到上一栏的最后几行。
    const previousLast = start - 1;
    const previousStart = ReaderReadingRulerSteps.columnStart(rows, previousLast);
    return new ReaderRulerStep(Math.max(previousStart, previousLast - lines + 1), false);
  }

  /** 拖把手：取和 y 最近的一行做首行。 */
  static rowAt(rows: ReaderRulerRow[], y: number, column: number): number {
    let best = -1;
    let bestDistance = Number.POSITIVE_INFINITY;
    for (let index = 0; index < rows.length; index++) {
      if (column >= 0 && rows[index].column !== column) continue;
      const row = rows[index];
      const distance = y < row.top ? row.top - y : (y > row.bottom ? y - row.bottom : 0);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = index;
      }
    }
    return Math.max(0, best);
  }

  /**
   * 尺的上下边：盖住首行到末行，再往外各让出到相邻行一半的行距（最多半行高），尺边落在行缝里不切字。
   */
  static bandEdges(rows: ReaderRulerRow[], span: number[]): number[] {
    if (span.length < 2) return [];
    const first = rows[span[0]];
    const last = rows[span[1]];
    const lineHeight = Math.max(1, first.bottom - first.top);
    const before = span[0] > 0 && rows[span[0] - 1].column === first.column ?
      Math.max(0, first.top - rows[span[0] - 1].bottom) : lineHeight * 0.3;
    const after = span[1] + 1 < rows.length && rows[span[1] + 1].column === last.column ?
      Math.max(0, rows[span[1] + 1].top - last.bottom) : lineHeight * 0.3;
    return [first.top - Math.min(before / 2, lineHeight / 2), last.bottom + Math.min(after / 2, lineHeight / 2)];
  }

  private static columnStart(rows: ReaderRulerRow[], index: number): number {
    let start = index;
    while (start > 0 && rows[start - 1].column === rows[index].column) start--;
    return start;
  }
}
