/** 小样里的一段：文字（emphasis 的那段套强调气泡，\n 换段）或一张行内小图（段评数气泡）。 */
export class BubbleFramePreviewPart {
  text: string = '';
  emphasis: boolean = false;
  image: PixelMap | undefined = undefined;
  imageWidth: number = 0;
  imageHeight: number = 0;

  constructor(text: string, emphasis: boolean) {
    this.text = text;
    this.emphasis = emphasis;
  }

  static inlineImage(map: PixelMap, width: number, height: number): BubbleFramePreviewPart {
    const part = new BubbleFramePreviewPart('', false);
    part.image = map;
    part.imageWidth = width;
    part.imageHeight = height;
    return part;
  }
}

/** 画一份小样需要的边框图片、拉伸设置、颜色与排版。尺寸单位都是 vp。 */
export class BubbleFramePreviewParams {
  map: PixelMap | undefined = undefined;
  aspect: number = 3;
  sliceLeft: number = 0;
  sliceRight: number = 0;
  sliceTop: number = 0;
  sliceBottom: number = 0;
  round: boolean = false;
  cut: boolean = false;
  tint: boolean = false;
  /** 端饰：画在边框外侧，右端旋转 180°；没有时只画边框。 */
  capMap: PixelMap | undefined = undefined;
  capSize: number = 0;
  textColor: string = '#FFFFFF';
  bubbleColor: string = '#86191E';
  normalTextColor: string = '#2B2A28';
  fontSize: number = 15;
  lineHeight: number = 32;
  fontFamily: string = '';
  /** 首行缩进几个字。 */
  indentChars: number = 2;
  paddingX: number = 16;
  paddingY: number = 8;
  /** 最多画几行，0 表示不限。 */
  maxLines: number = 0;
}

class PreviewGlyph {
  text: string = '';
  x: number = 0;
  emphasis: boolean = false;
  image: PixelMap | undefined = undefined;
  imageWidth: number = 0;
  imageHeight: number = 0;
}

class PreviewRun {
  left: number = 0;
  right: number = 0;
  leading: boolean = false;
  trailing: boolean = false;
}

class PreviewLine {
  glyphs: PreviewGlyph[] = [];
  runs: PreviewRun[] = [];
}

/** 一次绘制里算好的边框尺寸。 */
class FrameMetrics {
  band: number = 0;
  fullWidth: number = 0;
  fullHeight: number = 0;
  lead: number = 0;
  trail: number = 0;
  cap: number = 0;
}

/**
 * 编辑器里的气泡边框小样（拉伸区域页、强调气泡卡片、主题预览的强调示例）。规则与正文一致：文字带高度是字号的
 * 1.36 倍（ReaderV2BubbleFrame.BAND_EM），整段强调文字首尾给端头和端饰留位，端饰在边框外侧；换行处的两端画到
 * 边距里，或在断开处平切。
 */
export class BubbleFramePreviewPainter {
  static readonly FONT: number = 15;
  static readonly LINE: number = 32;
  static readonly PADDING: number = 16;
  static readonly BAND_EM: number = 1.36;

  /** 画到 context 上，返回小样需要的高度（vp）；画布还没尺寸时返回 0。 */
  static draw(context: CanvasRenderingContext2D, params: BubbleFramePreviewParams,
    parts: BubbleFramePreviewPart[]): number {
    const width = context.width;
    if (!width || width <= 0) return 0;
    const metrics = new FrameMetrics();
    metrics.band = params.fontSize * BubbleFramePreviewPainter.BAND_EM;
    metrics.fullHeight = metrics.band / Math.max(0.02, 1 - params.sliceTop - params.sliceBottom);
    metrics.fullWidth = metrics.fullHeight * Math.max(0.05, params.aspect);
    metrics.lead = params.map ? params.sliceLeft * metrics.fullWidth : 0;
    metrics.trail = params.map ? params.sliceRight * metrics.fullWidth : 0;
    metrics.cap = params.capMap ? params.capSize : 0;
    const font = BubbleFramePreviewPainter.font(params);
    const laidOut = BubbleFramePreviewPainter.layout(context, font, params, parts, width - params.paddingX * 2,
      metrics.cap + metrics.lead, metrics.cap + metrics.trail);
    const lines = params.maxLines > 0 ? laidOut.slice(0, params.maxLines) : laidOut;
    const height = lines.length * params.lineHeight + params.paddingY * 2;
    context.clearRect(0, 0, width, Math.max(context.height, height));
    const map = params.map;
    if (map) {
      for (let index = 0; index < lines.length; index++) {
        const centerY = BubbleFramePreviewPainter.lineCenter(params, index);
        for (const run of lines[index].runs) {
          BubbleFramePreviewPainter.drawFrame(context, map, params, run, centerY, metrics, width);
        }
      }
      if (params.tint) {
        // 这时画布上只有边框，染色只落在已画的像素上，之后再画端饰和文字。
        context.globalCompositeOperation = 'source-atop';
        context.fillStyle = params.bubbleColor;
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = 'source-over';
      }
    }
    const capMap = params.capMap;
    if (capMap && metrics.cap > 0) {
      for (let index = 0; index < lines.length; index++) {
        const centerY = BubbleFramePreviewPainter.lineCenter(params, index);
        for (const run of lines[index].runs) {
          BubbleFramePreviewPainter.drawCaps(context, capMap, params, run, centerY, metrics);
        }
      }
    }
    context.font = font;
    context.textBaseline = 'middle';
    for (let index = 0; index < lines.length; index++) {
      const centerY = BubbleFramePreviewPainter.lineCenter(params, index);
      for (const glyph of lines[index].glyphs) {
        const image = glyph.image;
        if (image) {
          context.drawImage(image, params.paddingX + glyph.x, centerY - glyph.imageHeight / 2, glyph.imageWidth,
            glyph.imageHeight);
          continue;
        }
        context.fillStyle = glyph.emphasis ? params.textColor : params.normalTextColor;
        context.fillText(glyph.text, params.paddingX + glyph.x, centerY);
      }
    }
    return height;
  }

  /** 画布字号默认单位是 px（物理像素），要写 vp 才和界面上的字一样大。 */
  private static font(params: BubbleFramePreviewParams): string {
    return `${params.fontSize}vp ${params.fontFamily || 'sans-serif'}`;
  }

  private static lineCenter(params: BubbleFramePreviewParams, index: number): number {
    return params.paddingY + index * params.lineHeight + params.lineHeight / 2;
  }

  /** 逐字排版：首行缩进，强调段首字前留 lead、末字后留 trail，放不下就换行。 */
  private static layout(context: CanvasRenderingContext2D, font: string, params: BubbleFramePreviewParams,
    parts: BubbleFramePreviewPart[], contentWidth: number, lead: number, trail: number): PreviewLine[] {
    context.font = font;
    const lines: PreviewLine[] = [new PreviewLine()];
    let x = params.fontSize * params.indentChars;
    let run: PreviewRun | null = null;
    for (const part of parts) {
      const image = part.image;
      if (image) {
        if (x + part.imageWidth > contentWidth && x > 0) {
          lines.push(new PreviewLine());
          x = 0;
        }
        const glyph = new PreviewGlyph();
        glyph.image = image;
        glyph.imageWidth = part.imageWidth;
        glyph.imageHeight = part.imageHeight;
        glyph.x = x;
        lines[lines.length - 1].glyphs.push(glyph);
        x += part.imageWidth;
        continue;
      }
      const chars = Array.from(part.text);
      for (let index = 0; index < chars.length; index++) {
        const char = chars[index];
        if (char === '\n') {
          if (run) {
            run.right = x;
            lines[lines.length - 1].runs.push(run);
            run = new PreviewRun();
          }
          lines.push(new PreviewLine());
          x = 0;
          continue;
        }
        const width = context.measureText(char).width;
        const first = part.emphasis && index === 0;
        const last = part.emphasis && index === chars.length - 1;
        const before = first ? lead : 0;
        const after = last ? trail : 0;
        if (x + before + width + after > contentWidth && x > 0) {
          if (run) {
            // 强调文字在这里换行：上一行这段到行尾为止，下一行从行首接着。
            run.right = x;
            lines[lines.length - 1].runs.push(run);
            run = new PreviewRun();
          }
          lines.push(new PreviewLine());
          x = 0;
        }
        x += before;
        if (first) {
          run = new PreviewRun();
          run.leading = true;
          run.left = x;
        }
        const glyph = new PreviewGlyph();
        glyph.text = char;
        glyph.x = x;
        glyph.emphasis = part.emphasis;
        lines[lines.length - 1].glyphs.push(glyph);
        x += width;
        if (last && run) {
          run.right = x;
          run.trailing = true;
          lines[lines.length - 1].runs.push(run);
          run = null;
          x += after;
        }
      }
    }
    return lines;
  }

  /** 边框左右边缘：整段首尾在文字外留出端头，换行处要么画进边距，要么平切。 */
  private static frameEdges(params: BubbleFramePreviewParams, run: PreviewRun, metrics: FrameMetrics,
    canvasWidth: number): number[] {
    const leadEnd = run.leading || !params.cut;
    const trailEnd = run.trailing || !params.cut;
    const left = Math.max(1, params.paddingX + run.left - (leadEnd ? metrics.lead : 0));
    const right = Math.min(canvasWidth - 1, params.paddingX + run.right + (trailEnd ? metrics.trail : 0));
    return [left, right];
  }

  private static drawCaps(context: CanvasRenderingContext2D, capMap: PixelMap, params: BubbleFramePreviewParams,
    run: PreviewRun, centerY: number, metrics: FrameMetrics): void {
    const edges = BubbleFramePreviewPainter.frameEdges(params, run, metrics, context.width);
    const size = metrics.cap;
    if (run.leading) context.drawImage(capMap, edges[0] - size, centerY - size / 2, size, size);
    if (run.trailing) {
      context.save();
      context.translate(edges[1] + size / 2, centerY);
      context.rotate(Math.PI);
      context.drawImage(capMap, -size / 2, -size / 2, size, size);
      context.restore();
    }
  }

  private static drawFrame(context: CanvasRenderingContext2D, map: PixelMap, params: BubbleFramePreviewParams,
    run: PreviewRun, centerY: number, metrics: FrameMetrics, canvasWidth: number): void {
    const leadEnd = run.leading || !params.cut;
    const trailEnd = run.trailing || !params.cut;
    const edges = BubbleFramePreviewPainter.frameEdges(params, run, metrics, canvasWidth);
    const left = edges[0];
    const right = edges[1];
    const total = right - left;
    if (total <= 1) return;
    let leadWidth = leadEnd ? metrics.lead : 0;
    let trailWidth = trailEnd ? metrics.trail : 0;
    if (leadWidth + trailWidth > total) {
      const shrink = total / (leadWidth + trailWidth);
      leadWidth *= shrink;
      trailWidth *= shrink;
    }
    const fullHeight = metrics.fullHeight;
    const top = centerY - metrics.band / 2 - params.sliceTop * fullHeight;
    if (leadWidth > 0) {
      BubbleFramePreviewPainter.drawPiece(context, map, 0, params.sliceLeft, left, left + leadWidth + 0.5, top,
        fullHeight);
    }
    if (trailWidth > 0) {
      BubbleFramePreviewPainter.drawPiece(context, map, 1 - params.sliceRight, 1, right - trailWidth - 0.5, right,
        top, fullHeight);
    }
    const middleLeft = left + leadWidth;
    const middleWidth = total - leadWidth - trailWidth;
    const middleSource = 1 - params.sliceLeft - params.sliceRight;
    if (middleWidth <= 0.5 || middleSource <= 0.001) return;
    if (!params.round) {
      BubbleFramePreviewPainter.drawPiece(context, map, params.sliceLeft, 1 - params.sliceRight, middleLeft,
        middleLeft + middleWidth, top, fullHeight);
      return;
    }
    // 平铺：整块重复、略微压缩或拉宽，花纹不会停在半块上。
    const count = Math.max(1, Math.round(middleWidth / Math.max(1, middleSource * metrics.fullWidth)));
    const step = middleWidth / count;
    for (let index = 0; index < count; index++) {
      const tileLeft = middleLeft + index * step;
      BubbleFramePreviewPainter.drawPiece(context, map, params.sliceLeft, 1 - params.sliceRight, tileLeft,
        index === count - 1 ? middleLeft + middleWidth : tileLeft + step + 0.5, top, fullHeight);
    }
  }

  /** 把原图横向 [sourceLeft, sourceRight]（占宽比例）画进 [left, right]：整张按比例放好，再裁到这一段。 */
  private static drawPiece(context: CanvasRenderingContext2D, map: PixelMap, sourceLeft: number,
    sourceRight: number, left: number, right: number, top: number, fullHeight: number): void {
    const span = sourceRight - sourceLeft;
    if (span <= 0.0001 || right - left <= 0.01) return;
    const scaleX = (right - left) / span;
    context.save();
    context.beginPath();
    context.rect(left, top - 1, right - left, fullHeight + 2);
    context.clip();
    context.drawImage(map, left - sourceLeft * scaleX, top, scaleX, fullHeight);
    context.restore();
  }
}
