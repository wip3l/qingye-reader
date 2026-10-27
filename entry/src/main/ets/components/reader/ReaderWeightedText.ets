import { UIContext, FrameNode, NodeController, DrawContext, LayoutConstraint, Position } from '@kit.ArkUI';
import { text, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
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
  private paragraph: text.Paragraph | null = null;
  private strokes: ReaderFontStrokeRun[] = [];

  constructor(context: UIContext, spans: ReaderWeightedTextSpan[], weight: number, maxLines: number,
    alignment: text.TextAlign) {
    super(context);
    this.context = context;
    this.spans = spans;
    this.weight = weight;
    this.maxLines = maxLines;
    this.alignment = alignment;
  }

  onMeasure(constraint: LayoutConstraint): void {
    const width = Math.max(1, constraint.maxSize.width);
    const styles: text.TextStyle[] = [];
    const ends: number[] = [];
    let length = 0;
    for (const span of this.spans) {
      const style = ReaderFontTextStyle.resolve(span.style, span.weight > 0 ? span.weight : this.weight);
      styles.push(style);
      length += span.content.length + (span.capStyleId ? 2 : 0);
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
      breakStrategy: text.BreakStrategy.GREEDY, includeFontPadding: true };
    const paragraphBuilder = new text.ParagraphBuilder(paragraphStyle, text.FontCollection.getGlobalInstance());
    for (let index = 0; index < styles.length; index++) {
      paragraphBuilder.pushStyle(styles[index]);
      this.appendSpan(paragraphBuilder, this.spans[index]);
      paragraphBuilder.popStyle();
    }
    this.paragraph = paragraphBuilder.build();
    this.paragraph.layoutSync(width);
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
      outline.layoutSync(width);
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
    if (span.capStyleId) builder.addPlaceholder(cap);
    builder.addText(span.content);
    if (span.capStyleId) builder.addPlaceholder(cap);
  }

  private capImage(styleId: string): image.PixelMap | undefined {
    const cached = ReaderWeightedTextNode.capImages.get(styleId);
    if (cached) return cached;
    const resource = ThemeAssetRegistry.regexBubbleCap(styleId);
    const host = this.context.getHostContext();
    if (typeof resource === 'string' || !host) return undefined;
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
    this.paragraph.paint(context.canvas, 0, 0);
    ReaderFontStroke.paint(context.canvas, this.strokes, 0, 0);
    const boxes = this.paragraph.getRectsForPlaceholders();
    let placeholder = 0;
    for (const span of this.spans) {
      if (!span.capStyleId) continue;
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
}

class ReaderWeightedTextController extends NodeController {
  spans: ReaderWeightedTextSpan[] = [];
  weight: number = 400;
  maxLines: number = 1000;
  alignment: text.TextAlign = text.TextAlign.LEFT;

  makeNode(context: UIContext): FrameNode {
    return new ReaderWeightedTextNode(context, this.spans, this.weight, this.maxLines, this.alignment);
  }
}

/** Preview uses the same native shaping and outline renderer as the reader. */
@Component
export struct ReaderWeightedText {
  @Prop @Watch('refresh') spans: ReaderWeightedTextSpan[] = [];
  @Prop @Watch('refresh') weight: number = 400;
  @Prop @Watch('refresh') maxLines: number = 1000;
  @Prop @Watch('refresh') alignment: text.TextAlign = text.TextAlign.LEFT;
  private controller: ReaderWeightedTextController = new ReaderWeightedTextController();

  aboutToAppear(): void { this.refresh(); }

  private refresh(): void {
    this.controller.spans = this.spans;
    this.controller.weight = this.weight;
    this.controller.maxLines = this.maxLines;
    this.controller.alignment = this.alignment;
    this.controller.rebuild();
  }

  build() {
    NodeContainer(this.controller)
      .width('100%')
      .accessibilityLevel('yes')
      .accessibilityText(this.spans.map((span: ReaderWeightedTextSpan): string => span.content).join(''))
  }
}
