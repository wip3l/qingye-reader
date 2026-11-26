/**
 * 打开插图查看器需要的信息：图片原地址（保存、分享用）、Image 能加载的地址、图注、
 * 它在窗口里实际画出的矩形（vp，放大与缩回的起止位置）、原图宽高（只用比例，未知为 0）。
 * 应用排版把它编码进点按标记，文件排版由网页回报后组装；两种排版共用同一个查看器。
 */
export class ReaderImageViewerSpec {
  source: string = '';
  uri: string = '';
  caption: string = '';
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  naturalWidth: number = 0;
  naturalHeight: number = 0;

  encode(): string {
    return encodeURIComponent(JSON.stringify({
      's': this.source, 'u': this.uri, 'c': this.caption,
      'r': [ReaderImageViewerSpec.round(this.x), ReaderImageViewerSpec.round(this.y),
        ReaderImageViewerSpec.round(this.width), ReaderImageViewerSpec.round(this.height)],
      'n': [Math.round(this.naturalWidth), Math.round(this.naturalHeight)]
    }));
  }

  static decode(value: string): ReaderImageViewerSpec | null {
    try {
      const record = JSON.parse(decodeURIComponent(value || '')) as Record<string, Object>;
      const spec = new ReaderImageViewerSpec();
      spec.source = String(record['s'] ?? '');
      spec.uri = String(record['u'] ?? '');
      spec.caption = String(record['c'] ?? '');
      const rect = Array.isArray(record['r']) ? record['r'] as number[] : [];
      const natural = Array.isArray(record['n']) ? record['n'] as number[] : [];
      spec.x = ReaderImageViewerSpec.finite(rect[0]);
      spec.y = ReaderImageViewerSpec.finite(rect[1]);
      spec.width = ReaderImageViewerSpec.finite(rect[2]);
      spec.height = ReaderImageViewerSpec.finite(rect[3]);
      spec.naturalWidth = ReaderImageViewerSpec.finite(natural[0]);
      spec.naturalHeight = ReaderImageViewerSpec.finite(natural[1]);
      return spec.uri ? spec : null;
    } catch (_) {
      return null;
    }
  }

  /** 图片按“完整放进去”画在 (left, top, width, height) 里时实际占的矩形；原图尺寸未知时就是整个框。 */
  static containRect(left: number, top: number, width: number, height: number, naturalWidth: number,
    naturalHeight: number): number[] {
    if (naturalWidth <= 0 || naturalHeight <= 0 || width <= 0 || height <= 0) return [left, top, width, height];
    const scale = Math.min(width / naturalWidth, height / naturalHeight);
    const drawnWidth = naturalWidth * scale;
    const drawnHeight = naturalHeight * scale;
    return [left + (width - drawnWidth) / 2, top + (height - drawnHeight) / 2, drawnWidth, drawnHeight];
  }

  private static round(value: number): number {
    return Math.round(value * 10) / 10;
  }

  private static finite(value: number | undefined): number {
    const number = Number(value);
    return Number.isFinite(number) ? number : 0;
  }
}
