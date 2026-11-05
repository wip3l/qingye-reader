import { UIContext, FrameNode, NodeController, DrawContext, LayoutConstraint, Position } from '@kit.ArkUI';
import { text, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ReaderRasterAssets } from '../../core/reader/ReaderRasterAssets';
import { ReaderResolvedRegexEmphasis } from '../../model/reader/ReaderRegexFontRule';
import { ReaderV2Color } from '../../core/reader/ReaderV2Style';
import { ReaderFontTextStyle } from '../../core/reader/ReaderFontTextStyle';
import { ReaderFontWeight } from '../../core/reader/ReaderFontWeight';
import { ReaderFontStroke, ReaderFontStrokeRun } from '../../core/reader/ReaderFontStroke';

/** All dimensions in each native style are already physical pixels. */
export class ReaderWeightedTextSpan {
  content: string;
  style: text.TextStyle;
  weight: number = 0;
  capStyleId: string = '';
  capSizePx: number = 0;
  repeatCaps: boolean = false;
  constructor(content: string, style: text.TextStyle) {
    this.content = content;
    this.style = style;
  }

  static color(value: string): common2D.Color {
    const argb = ReaderV2Color.parse(value, 0xFF202124);
    return { alpha: (argb >>> 24) & 255, red: (argb >>> 16) & 255, green: (argb >>> 8) & 255, blue: argb & 255 };
  }

  static create(context: UIContext, content: string, size: number, family: string, color: string,
    lineHeight: number = 0, spacing: number = 0, emphasis?: ReaderResolvedRegexEmphasis): ReaderWeightedTextSpan {
    const fontSize = context.fp2px(size);
    const style: text.TextStyle = { fontSize: fontSize, fontFamilies: [family], color: ReaderWeightedTextSpan.color(color),
      letterSpacing: context.vp2px(spacing), halfLeading: false };
    if (lineHeight > 0) {
      style.heightOnly = true;
      style.heightScale = context.vp2px(lineHeight) / fontSize;
    }
    if (emphasis) {
      if (emphasis.backgroundEnabled) {
        style.backgroundRect = { color: ReaderWeightedTextSpan.color(emphasis.backgroundColor),
          leftTopRadius: context.vp2px(emphasis.radiusTopLeft), rightTopRadius: context.vp2px(emphasis.radiusTopRight),
          leftBottomRadius: context.vp2px(emphasis.radiusBottomLeft), rightBottomRadius: context.vp2px(emphasis.radiusBottomRight) };
      }
      style.textShadows = emphasis.textShadows.map((shadow: ShadowOptions): text.TextShadow => ({
        color: ReaderWeightedTextSpan.color(String(shadow.color ?? '#00000000')),
        point: { x: context.vp2px(Number(shadow.offsetX ?? 0)), y: context.vp2px(Number(shadow.offsetY ?? 0)) },
        blurRadius: context.vp2px(Number(shadow.radius ?? 0))
      }));
      if (style.textShadows.length === 0 && emphasis.textShadowRadius > 0) {
        style.textShadows = [{ color: ReaderWeightedTextSpan.color(emphasis.textShadowColor),
          point: { x: context.vp2px(emphasis.textShadowOffsetX), y: context.vp2px(emphasis.textShadowOffsetY) },
          blurRadius: context.vp2px(emphasis.textShadowRadius) }];
      }
      if (emphasis.decorationEnabled) {
        let kind = text.TextDecorationStyle.SOLID;
        if (emphasis.decorationStyleId === 'double') kind = text.TextDecorationStyle.DOUBLE;
        else if (emphasis.decorationStyleId === 'dotted') kind = text.TextDecorationStyle.DOTTED;
        else if (emphasis.decorationStyleId === 'dashed') kind = text.TextDecorationStyle.DASHED;
        else if (emphasis.decorationStyleId === 'wavy') kind = text.TextDecorationStyle.WAVY;
        style.decoration = { textDecoration: text.TextDecorationType.UNDERLINE,
          color: ReaderWeightedTextSpan.color(emphasis.decorationColor), decorationStyle: kind };
      }
    }
    return new ReaderWeightedTextSpan(content, style);
  }
}

class ReaderWeightedTextNode extends FrameNode {
  private context: UIContext;
  private static capImages: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private spans: ReaderWeightedTextSpan[];
  private weight: number;
  private maxLines: number;
  private alignment: text.TextAlign;
  private extraLineSpacingPx: number;
  private insetPx: number = 0;
  private paragraph: text.Paragraph | null = null;
  private strokes: ReaderFontStrokeRun[] = [];

  constructor(context: UIContext, spans: ReaderWeightedTextSpan[], weight: number, maxLines: number,
    alignment: text.TextAlign, extraLineSpacingPx: number = 0) {
    super(context);
    this.context = context;
    this.spans = spans;
    this.weight = weight;
    this.maxLines = maxLines;
    this.alignment = alignment;
    this.extraLineSpacingPx = Math.max(0, extraLineSpacingPx);
  }

  onMeasure(constraint: LayoutConstraint): void {
    const width = Math.max(1, constraint.maxSize.width);
    const styles: text.TextStyle[] = [];
    const ends: number[] = [];
    let length = 0;
    this.insetPx = 0;
    for (const span of this.spans) {
      const style = ReaderFontTextStyle.resolve(span.style, span.weight > 0 ? span.weight : this.weight);
      styles.push(style);
      length += span.content.length + (span.capStyleId && !span.repeatCaps ? 2 : 0);
      if (span.repeatCaps && span.capStyleId) this.insetPx = Math.max(this.insetPx, span.capSizePx);
      ends.push(length);
    }
    if (styles.length === 0) {
      this.paragraph = null;
      this.strokes = [];
      this.setMeasuredSize({ width: width, height: 0 });
      return;
    }
    const paragraphStyle: text.ParagraphStyle = { textStyle: styles[0], align: this.alignment,
      maxLines: this.maxLines > 0 ? this.maxLines : 1000, wordBreak: text.WordBreak.BREAK_WORD,
      breakStrategy: text.BreakStrategy.GREEDY, includeFontPadding: true, lineSpacing: this.extraLineSpacingPx };
    const paragraphBuilder = new text.ParagraphBuilder(paragraphStyle, text.FontCollection.getGlobalInstance());
    for (let index = 0; index < styles.length; index++) {
      paragraphBuilder.pushStyle(styles[index]);
      this.appendSpan(paragraphBuilder, this.spans[index]);
      paragraphBuilder.popStyle();
    }
    this.paragraph = paragraphBuilder.build();
    this.insetPx = Math.min(width / 6, this.insetPx);
    this.paragraph.layoutSync(Math.max(1, width - this.insetPx * 2));
    this.strokes = [];
    if (this.spans.some((span: ReaderWeightedTextSpan): boolean => (span.weight || this.weight) > 400) &&
      styles.some((style: text.TextStyle): boolean =>
      ReaderFontWeight.isStatic(style.fontFamilies ? style.fontFamilies[0] : ''))) {
      const outlineBuilder = new text.ParagraphBuilder(paragraphStyle, text.FontCollection.getGlobalInstance());
      for (let index = 0; index < styles.length; index++) {
        outlineBuilder.pushStyle(ReaderFontStroke.outlineStyle(styles[index]));
        this.appendSpan(outlineBuilder, this.spans[index]);
        outlineBuilder.popStyle();
      }
      const outline = outlineBuilder.build();
      outline.layoutSync(Math.max(1, width - this.insetPx * 2));
      this.strokes = ReaderFontStroke.build(outline, this.weight, (offset: number): text.TextStyle => {
        for (let index = 0; index < ends.length; index++) {
          if (offset < ends[index]) return styles[index];
        }
        return styles[styles.length - 1];
      }, (offset: number): number => {
        for (let index = 0; index < ends.length; index++) {
          if (offset < ends[index]) return this.spans[index].weight || this.weight;
        }
        return this.weight;
      });
    }
    this.setMeasuredSize({ width: width,
      height: Math.max(constraint.minSize.height, Math.min(constraint.maxSize.height, this.paragraph.getHeight())) });
  }

  onLayout(position: Position): void { this.setLayoutPosition(position); }

  private appendSpan(builder: text.ParagraphBuilder, span: ReaderWeightedTextSpan): void {
    const cap: text.PlaceholderSpan = { width: span.capSizePx, height: span.capSizePx,
      align: text.PlaceholderAlignment.CENTER_OF_ROW_BOX, baseline: text.TextBaseline.ALPHABETIC, baselineOffset: 0 };
    if (span.capStyleId && !span.repeatCaps) builder.addPlaceholder(cap);
    builder.addText(span.content);
    if (span.capStyleId && !span.repeatCaps) builder.addPlaceholder(cap);
  }

  private capImage(styleId: string): image.PixelMap | undefined {
    const cached = ReaderWeightedTextNode.capImages.get(styleId);
    if (cached) return cached;
    const resource = ThemeAssetRegistry.regexBubbleCap(styleId);
    const host = this.context.getHostContext();
    if (typeof resource === 'string') {
      // 主题包的端饰是包目录里的 SVG 文件。
      const fromFile = resource ? ReaderRasterAssets.fileImage(resource, 96, 96) : null;
      if (fromFile) ReaderWeightedTextNode.capImages.set(styleId, fromFile);
      return fromFile || undefined;
    }
    if (!host) return undefined;
    try {
      const bytes = host.resourceManager.getMediaContentSync(resource.id);
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      try {
        const bitmap = source.createPixelMapSync({ desiredSize: { width: 96, height: 96 } });
        ReaderWeightedTextNode.capImages.set(styleId, bitmap);
        return bitmap;
      } finally { source.release(); }
    } catch (_) { return undefined; }
  }

  onDraw(context: DrawContext): void {
    if (!this.paragraph) return;
    this.paragraph.paint(context.canvas, this.insetPx, 0);
    ReaderFontStroke.paint(context.canvas, this.strokes, this.insetPx, 0);
    const boxes = this.paragraph.getRectsForPlaceholders();
    let placeholder = 0;
    let textOffset = 0;
    for (const span of this.spans) {
      const start = textOffset;
      textOffset += span.content.length + (span.capStyleId && !span.repeatCaps ? 2 : 0);
      if (!span.capStyleId) continue;
      if (span.repeatCaps) {
        this.paintRepeatedCaps(context, span, start);
        continue;
      }
      const bitmap = this.capImage(span.capStyleId);
      for (let side = 0; side < 2; side++) {
        const box = placeholder < boxes.length ? boxes[placeholder].rect : undefined;
        placeholder++;
        if (!bitmap || !box) continue;
        context.canvas.save();
        if (side === 1) context.canvas.rotate(180, (box.left + box.right) / 2, (box.top + box.bottom) / 2);
        context.canvas.drawImageRect(bitmap, box);
        context.canvas.restore();
      }
    }
  }

  private paintRepeatedCaps(context: DrawContext, span: ReaderWeightedTextSpan, start: number): void {
    if (!this.paragraph) return;
    const bitmap = this.capImage(span.capStyleId);
    if (!bitmap) return;
    for (const line of this.paragraph.getLineMetrics()) {
      const from = Math.max(start, line.startIndex);
      const to = Math.min(start + span.content.length, line.endIndex);
      if (to <= from) continue;
      const boxes = this.paragraph.getRectsForRange({ start: from, end: to },
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT);
      if (boxes.length === 0) continue;
      let left = boxes[0].rect.left;
      let right = boxes[0].rect.right;
      let top = boxes[0].rect.top;
      let bottom = boxes[0].rect.bottom;
      for (const box of boxes) {
        left = Math.min(left, box.rect.left);
        right = Math.max(right, box.rect.right);
        top = Math.min(top, box.rect.top);
        bottom = Math.max(bottom, box.rect.bottom);
      }
      const capTop = (top + bottom - span.capSizePx) / 2;
      for (let side = 0; side < 2; side++) {
        const capLeft = this.insetPx + (side === 0 ? left - span.capSizePx : right);
        const rect: common2D.Rect = { left: capLeft, top: capTop,
          right: capLeft + span.capSizePx, bottom: capTop + span.capSizePx };
        context.canvas.save();
        if (side === 1) context.canvas.rotate(180, (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2);
        context.canvas.drawImageRect(bitmap, rect);
        context.canvas.restore();
      }
    }
  }
}

class ReaderWeightedTextController extends NodeController {
  spans: ReaderWeightedTextSpan[] = [];
  weight: number = 400;
  maxLines: number = 1000;
  alignment: text.TextAlign = text.TextAlign.LEFT;
  extraLineSpacing: number = 0;

  makeNode(context: UIContext): FrameNode {
    return new ReaderWeightedTextNode(context, this.spans, this.weight, this.maxLines, this.alignment,
      context.vp2px(this.extraLineSpacing));
  }
}

/** Preview uses the same native shaping and outline renderer as the reader. */
@Component
export struct ReaderWeightedText {
  @Prop @Watch('refresh') spans: ReaderWeightedTextSpan[] = [];
  @Prop @Watch('refresh') weight: number = 400;
  @Prop @Watch('refresh') maxLines: number = 1000;
  @Prop @Watch('refresh') alignment: text.TextAlign = text.TextAlign.LEFT;
  @Prop @Watch('refresh') extraLineSpacing: number = 0;
  private controller: ReaderWeightedTextController = new ReaderWeightedTextController();

  aboutToAppear(): void { this.refresh(); }

  private refresh(): void {
    this.controller.spans = this.spans;
    this.controller.weight = this.weight;
    this.controller.maxLines = this.maxLines;
    this.controller.alignment = this.alignment;
    this.controller.extraLineSpacing = this.extraLineSpacing;
    this.controller.rebuild();
  }

  build() {
    NodeContainer(this.controller)
      .width('100%')
      .accessibilityLevel('yes')
      .accessibilityText(this.spans.map((span: ReaderWeightedTextSpan): string => span.content).join(''))
  }
}
