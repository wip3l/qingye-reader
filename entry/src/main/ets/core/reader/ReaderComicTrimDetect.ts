/** 四边要裁掉的比例（占原图宽或高），0 表示这一边不裁。 */
export class ComicTrimRect {
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

  isEmpty(): boolean {
    return this.left <= 0 && this.top <= 0 && this.right <= 0 && this.bottom <= 0;
  }
}

/**
 * 漫画去白边的检测：在缩小解码的像素上，从四条边往里找连续的纯色空白。
 * 只认接近白色或接近黑色的底色（四个角至少两个一致），彩色满版画面不会被当成边。
 * 先裁上下、再在剩下的行里裁左右、最后在剩下的列里再裁一次上下：页角水印只占边上几行，
 * 第一轮被跳过后，就不会再挡住左右的判断。
 * 像素按 4 字节一组读取，只比较各通道与底色的差，RGBA 或 BGRA 都一样。
 */
export class ReaderComicTrimDetect {
  /** 与底色单通道差超过这个值才算有内容；JPEG 杂色一般在 20 以内。 */
  static readonly TOLERANCE: number = 36;
  /** 一行（列）里有内容的像素不超过这个比例仍算空白，容下零星噪点。 */
  static readonly NOISE_RATIO: number = 0.005;
  /** 每边最多裁掉的比例。 */
  static readonly MAX_SIDE: number = 0.2;
  /** 不到这个比例的空白不值得裁，避免画面轻微跳动。 */
  static readonly MIN_SIDE: number = 0.01;
  /** 空白占掉一半以上（多是扉页、单行字的过场页）就不裁，免得把几个字放得很大。 */
  static readonly MIN_REMAIN_AREA: number = 0.5;
  /** 边上一段很薄的内容（水印、页码）：厚度不超过这个比例…… */
  static readonly MARK_THICKNESS: number = 0.04;
  /** ……并且里面能再找到不少于这个比例的空白，才当作水印跳过。 */
  static readonly MARK_GAP: number = 0.012;
  /** 水印行（列）里有内容的像素不超过这个比例；画框边线会远超过它。 */
  static readonly MARK_COVERAGE: number = 0.4;

  /** 缩小解码时的目标尺寸：宽不超过 320、总像素不超过 60 万。 */
  static sampleSize(width: number, height: number): number[] {
    if (width <= 0 || height <= 0) return [0, 0];
    const scale = Math.min(1, 320 / width, Math.sqrt(600000 / (width * height)));
    return [Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale))];
  }

  /** pixels 为紧凑排列的 4 字节像素；找不到可裁的边返回 null。 */
  static detect(pixels: Uint8Array, width: number, height: number): ComicTrimRect | null {
    if (width < 16 || height < 16 || pixels.length < width * height * 4) return null;
    const background = ReaderComicTrimDetect.background(pixels, width, height);
    if (!background) return null;
    const scan = new ReaderComicTrimScan(pixels, width, height, background);
    let top = scan.edge(true, 0, 0, width);
    let bottom = scan.edge(true, 1, 0, width);
    if (top + bottom >= height) return null;
    const left = scan.edge(false, 0, top, height - bottom);
    const right = scan.edge(false, 1, top, height - bottom);
    if (left + right >= width) return null;
    top = scan.edge(true, 0, left, width - right);
    bottom = scan.edge(true, 1, left, width - right);
    if (top + bottom >= height) return null;
    const remain = (1 - (left + right) / width) * (1 - (top + bottom) / height);
    if (remain < ReaderComicTrimDetect.MIN_REMAIN_AREA) return null;
    const rect = new ComicTrimRect(
      ReaderComicTrimDetect.side(left, width),
      ReaderComicTrimDetect.side(top, height),
      ReaderComicTrimDetect.side(right, width),
      ReaderComicTrimDetect.side(bottom, height));
    return rect.isEmpty() ? null : rect;
  }

  /** 缩小图上量出的空白宽度换成比例：往回留一个采样像素，限制上限，太小的不裁。 */
  private static side(blank: number, size: number): number {
    const kept = Math.max(0, blank - 1) / size;
    if (kept < ReaderComicTrimDetect.MIN_SIDE) return 0;
    return Math.min(ReaderComicTrimDetect.MAX_SIDE, kept);
  }

  /** 四个角各取 3×3 平均；至少两个角相近且是近白或近黑，才把它当作底色。 */
  static background(pixels: Uint8Array, width: number, height: number): number[] | null {
    const corners: number[][] = [
      ReaderComicTrimDetect.patch(pixels, width, 0, 0),
      ReaderComicTrimDetect.patch(pixels, width, width - 3, 0),
      ReaderComicTrimDetect.patch(pixels, width, 0, height - 3),
      ReaderComicTrimDetect.patch(pixels, width, width - 3, height - 3)
    ];
    let best: number[] | null = null;
    let bestVotes = 0;
    for (const corner of corners) {
      if (!ReaderComicTrimDetect.plain(corner)) continue;
      let votes = 0;
      for (const other of corners) {
        if (ReaderComicTrimDetect.distance(corner, other) <= ReaderComicTrimDetect.TOLERANCE / 2) votes++;
      }
      if (votes > bestVotes) {
        best = corner;
        bestVotes = votes;
      }
    }
    return bestVotes >= 2 ? best : null;
  }

  private static patch(pixels: Uint8Array, width: number, x0: number, y0: number): number[] {
    const sum: number[] = [0, 0, 0];
    for (let y = y0; y < y0 + 3; y++) {
      for (let x = x0; x < x0 + 3; x++) {
        const i = (y * width + x) * 4;
        sum[0] += pixels[i];
        sum[1] += pixels[i + 1];
        sum[2] += pixels[i + 2];
      }
    }
    return [sum[0] / 9, sum[1] / 9, sum[2] / 9];
  }

  /** 近白（纸色允许略偏黄）或近黑，且几乎无彩色。 */
  private static plain(color: number[]): boolean {
    const max = Math.max(color[0], color[1], color[2]);
    const min = Math.min(color[0], color[1], color[2]);
    if (max - min > 32) return false;
    return min >= 190 || max <= 50;
  }

  private static distance(a: number[], b: number[]): number {
    return Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]), Math.abs(a[2] - b[2]));
  }
}

/** 一次检测的扫描状态。 */
class ReaderComicTrimScan {
  private readonly pixels: Uint8Array;
  private readonly width: number;
  private readonly height: number;
  private readonly r: number;
  private readonly g: number;
  private readonly b: number;

  constructor(pixels: Uint8Array, width: number, height: number, background: number[]) {
    this.pixels = pixels;
    this.width = width;
    this.height = height;
    this.r = background[0];
    this.g = background[1];
    this.b = background[2];
  }

  /**
   * 从一条边往里数空白行（rows 为 true）或空白列的数目。from 为 0 从上/左开始，1 从下/右开始；
   * 只统计 [start, end) 范围内的像素。碰到一段很薄、稀疏、后面又是空白的内容时当作水印继续往里找，最多跳过一次。
   */
  edge(rows: boolean, from: number, start: number, end: number): number {
    const count = rows ? this.height : this.width;
    const span = end - start;
    if (span <= 0) return 0;
    const noise = Math.max(1, Math.floor(span * ReaderComicTrimDetect.NOISE_RATIO));
    const markLimit = Math.max(1, Math.round(count * ReaderComicTrimDetect.MARK_THICKNESS));
    const gapNeed = Math.max(2, Math.round(count * ReaderComicTrimDetect.MARK_GAP));
    const coverageLimit = span * ReaderComicTrimDetect.MARK_COVERAGE;
    const maxDepth = Math.ceil(count * ReaderComicTrimDetect.MAX_SIDE) + markLimit + gapNeed;
    let blank = 0;
    while (blank < count && this.marks(rows, from, blank, start, end) <= noise) blank++;
    if (blank >= count || blank >= maxDepth) return blank;
    // 可能是水印：量这段内容的厚度和最密的一行，再看后面有没有足够的空白。
    let mark = blank;
    let densest = 0;
    while (mark < count && mark - blank <= markLimit) {
      const marks = this.marks(rows, from, mark, start, end);
      if (marks <= noise) break;
      densest = Math.max(densest, marks);
      mark++;
    }
    if (mark - blank > markLimit || densest > coverageLimit) return blank;
    let after = mark;
    while (after < count && this.marks(rows, from, after, start, end) <= noise) after++;
    // 跳过后超过单边上限就不跳：按上限裁会把水印切掉半截。
    if (after - mark < gapNeed || after > count * ReaderComicTrimDetect.MAX_SIDE + 1) return blank;
    return after;
  }

  /** 第 index 行（列）里与底色明显不同的像素数。 */
  private marks(rows: boolean, from: number, index: number, start: number, end: number): number {
    const count = rows ? this.height : this.width;
    const line = from === 0 ? index : count - 1 - index;
    const tolerance = ReaderComicTrimDetect.TOLERANCE;
    const pixels = this.pixels;
    let marks = 0;
    for (let k = start; k < end; k++) {
      const i = rows ? (line * this.width + k) * 4 : (k * this.width + line) * 4;
      if (Math.abs(pixels[i] - this.r) > tolerance || Math.abs(pixels[i + 1] - this.g) > tolerance ||
        Math.abs(pixels[i + 2] - this.b) > tolerance) {
        marks++;
      }
    }
    return marks;
  }
}
