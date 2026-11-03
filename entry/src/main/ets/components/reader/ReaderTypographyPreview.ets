import { UIContext, FrameNode, NodeController, LayoutConstraint } from '@kit.ArkUI';
import { ReaderV2Document } from '../../core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Paginator } from '../../core/reader/ReaderV2Paginator';
import { ReaderV2PageFrameNode } from '../../core/reader/ReaderV2RenderNode';
import { ReaderV2SpanStyleRange } from '../../core/reader/ReaderV2Style';
import { ReaderV2PageLayout, ReaderV2RegexBubbleSegment } from '../../core/reader/ReaderV2PageLayout';
import { ReaderV2RegexBubbleCapImages } from './ReaderV2RegexBubbleCaps';

export class ReaderTypographyPreviewConfig {
  input: ReaderV2LayoutInput = new ReaderV2LayoutInput();
  document: ReaderV2Document = new ReaderV2Document();
  styles: ReaderV2SpanStyleRange[] = [];
  fontSizeVp: number = 20;
  viewportHeightVp: number = 720;
  /** Full-screen settings use a real first page; font samples remain continuous. */
  paginated: boolean = false;
  pageIndex: number = 0;
}

/** Only the viewport differs: shaping, block spacing, title fitting and painting belong to the reader. */
class ReaderTypographyPreviewNode extends ReaderV2PageFrameNode {
  private context: UIContext;
  private config: ReaderTypographyPreviewConfig;
  private onLayoutReady: (layout: ReaderV2PageLayout | null, heightVp: number) => void;

  constructor(context: UIContext, config: ReaderTypographyPreviewConfig,
    onLayoutReady: (layout: ReaderV2PageLayout | null, heightVp: number) => void =
      (_layout: ReaderV2PageLayout | null, _heightVp: number): void => {}) {
    super(context);
    this.context = context;
    this.config = config;
    this.onLayoutReady = onLayoutReady;
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
    let layout: ReaderV2PageLayout | null = null;
    if (this.config.paginated) {
      const session = ReaderV2Paginator.start(this.config.document, snapshot, this.config.styles);
      const requestedPage = Math.max(0, Math.min(1, Math.round(this.config.pageIndex)));
      ReaderV2Paginator.appendPages(session, requestedPage + 1);
      layout = session.pageSet.pages[requestedPage] ?? session.pageSet.pages[0] ?? null;
    } else {
      layout = ReaderV2Paginator.layoutContinuous(this.config.document, snapshot, this.config.styles);
    }
    this.update(layout ?? null, -1, -1, -1, -1);
    const contentHeight = this.config.paginated ? input.viewportHeightPx :
      (layout ? layout.contentBottomPx + input.marginBottomPx : 0);
    const measuredHeight = Math.max(constraint.minSize.height, Math.min(constraint.maxSize.height, contentHeight));
    this.setMeasuredSize({ width: input.viewportWidthPx, height: measuredHeight });
    this.onLayoutReady(layout, this.context.px2vp(measuredHeight));
  }
}

class ReaderTypographyPreviewController extends NodeController {
  config: ReaderTypographyPreviewConfig = new ReaderTypographyPreviewConfig();
  onLayoutReady: (layout: ReaderV2PageLayout | null, heightVp: number) => void =
    (_layout: ReaderV2PageLayout | null, _heightVp: number): void => {};

  makeNode(context: UIContext): FrameNode {
    return new ReaderTypographyPreviewNode(context, this.config, this.onLayoutReady);
  }
}

@Component
export struct ReaderTypographyPreview {
  @Prop @Watch('refresh') config: ReaderTypographyPreviewConfig = new ReaderTypographyPreviewConfig();
  private controller: ReaderTypographyPreviewController = new ReaderTypographyPreviewController();
  @State capSegments: ReaderV2RegexBubbleSegment[] = [];
  @State measuredHeightVp: number = 0;
  private capsSignature: string = '';
  private layoutEpoch: number = 0;
  private capsPublishTimer: number = -1;

  aboutToAppear(): void { this.refresh(); }

  aboutToDisappear(): void {
    this.layoutEpoch++;
    this.cancelCapsPublish();
  }

  private cancelCapsPublish(): void {
    if (this.capsPublishTimer >= 0) {
      clearTimeout(this.capsPublishTimer);
      this.capsPublishTimer = -1;
    }
  }

  private publishLayoutCaps(layout: ReaderV2PageLayout | null, heightVp: number, epoch: number): void {
    if (epoch !== this.layoutEpoch) return;
    const segments: ReaderV2RegexBubbleSegment[] = [];
    if (layout) {
      for (const fragment of layout.fragments) {
        for (const segment of fragment.regexBubbleSegments) segments.push(segment);
      }
    }
    const signature = `${heightVp}:${JSON.stringify(segments)}`;
    if (signature === this.capsSignature) return;
    this.capsSignature = signature;
    this.cancelCapsPublish();
    // 测量阶段不改声明式状态；相同几何不重复发布，避免端饰触发重新测量循环。
    this.capsPublishTimer = setTimeout(() => {
      this.capsPublishTimer = -1;
      if (epoch !== this.layoutEpoch) return;
      this.measuredHeightVp = heightVp;
      this.capSegments = segments;
    }, 0);
  }

  private refresh(): void {
    this.layoutEpoch++;
    const epoch = this.layoutEpoch;
    this.cancelCapsPublish();
    this.capsSignature = '';
    this.capSegments = [];
    this.controller.onLayoutReady = (layout: ReaderV2PageLayout | null, heightVp: number): void => {
      this.publishLayoutCaps(layout, heightVp, epoch);
    };
    this.controller.config = this.config;
    this.controller.rebuild();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      NodeContainer(this.controller)
        .width('100%')
        .accessibilityLevel('yes')
        .accessibilityText(this.config.document.displayText)
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.capSegments, (segment: ReaderV2RegexBubbleSegment) => {
          ReaderV2RegexBubbleCapImages(segment, this.getUIContext())
        }, (segment: ReaderV2RegexBubbleSegment) => `${segment.styleId}_${segment.rect.left}_${segment.rect.top}_` +
          `${segment.rect.right}_${segment.rect.bottom}_${segment.capSizePx}_${segment.leadingCapWidthPx}_` +
          `${segment.trailingCapWidthPx}_${segment.leading}_${segment.trailing}`)
      }
      .width('100%')
      .height(this.measuredHeightVp)
      .hitTestBehavior(HitTestMode.None)
    }.width('100%')
  }
}
