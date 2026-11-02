import { UIContext, FrameNode, NodeController, LayoutConstraint } from '@kit.ArkUI';
import { ReaderV2Document } from '../../core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Paginator } from '../../core/reader/ReaderV2Paginator';
import { ReaderV2PageFrameNode } from '../../core/reader/ReaderV2RenderNode';
import { ReaderV2SpanStyleRange } from '../../core/reader/ReaderV2Style';

export class ReaderTypographyPreviewConfig {
  input: ReaderV2LayoutInput = new ReaderV2LayoutInput();
  document: ReaderV2Document = new ReaderV2Document();
  styles: ReaderV2SpanStyleRange[] = [];
  fontSizeVp: number = 20;
  viewportHeightVp: number = 720;
}

/** Only the viewport differs: shaping, block spacing, title fitting and painting belong to the reader. */
class ReaderTypographyPreviewNode extends ReaderV2PageFrameNode {
  private context: UIContext;
  private config: ReaderTypographyPreviewConfig;

  constructor(context: UIContext, config: ReaderTypographyPreviewConfig) {
    super(context);
    this.context = context;
    this.config = config;
  }

  onMeasure(constraint: LayoutConstraint): void {
    const input = JSON.parse(JSON.stringify(this.config.input)) as ReaderV2LayoutInput;
    input.commentBubble = this.config.input.commentBubble;
    input.viewportWidthPx = Math.max(1, constraint.maxSize.width);
    input.viewportHeightPx = Math.max(1, this.context.vp2px(this.config.viewportHeightVp));
    // Match the sub-pixel width correction used by ReadBook.getReaderAdaptiveLetterSpacing.
    const availablePx = Math.max(1, input.viewportWidthPx - input.marginLeftPx - input.marginRightPx);
    const charsPerLine = Math.max(8, Math.floor(this.context.px2vp(availablePx) / Math.max(1, this.config.fontSizeVp)));
    const correction = Math.max(-0.08, Math.min(0,
      this.context.px2fp((Math.floor(availablePx) - availablePx) / charsPerLine)));
    input.letterSpacingPx += this.context.fp2px(correction);
    const snapshot = ReaderV2LayoutSnapshot.create(input);
    const page = ReaderV2Paginator.layoutContinuous(this.config.document, snapshot, this.config.styles);
    this.update(page, -1, -1, -1, -1);
    const contentHeight = page ? page.contentBottomPx + input.marginBottomPx : 0;
    this.setMeasuredSize({ width: input.viewportWidthPx,
      height: Math.max(constraint.minSize.height, Math.min(constraint.maxSize.height, contentHeight)) });
  }
}

class ReaderTypographyPreviewController extends NodeController {
  config: ReaderTypographyPreviewConfig = new ReaderTypographyPreviewConfig();

  makeNode(context: UIContext): FrameNode {
    return new ReaderTypographyPreviewNode(context, this.config);
  }
}

@Component
export struct ReaderTypographyPreview {
  @Prop @Watch('refresh') config: ReaderTypographyPreviewConfig = new ReaderTypographyPreviewConfig();
  private controller: ReaderTypographyPreviewController = new ReaderTypographyPreviewController();

  aboutToAppear(): void { this.refresh(); }

  private refresh(): void {
    this.controller.config = this.config;
    this.controller.rebuild();
  }

  build() {
    NodeContainer(this.controller)
      .width('100%')
      .accessibilityLevel('yes')
      .accessibilityText(this.config.document.displayText)
  }
}
