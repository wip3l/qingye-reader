import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import { UIContext } from '@ohos.arkui.UIContext';
import {
  DrawContext,
  FrameNode,
  LayoutConstraint,
  NodeController,
  Position
} from '@ohos.arkui.node';
import graphicsText from '@ohos.graphics.text';
import { ReaderFontStroke } from './ReaderFontStroke';
import { ReaderRenderFrame } from './ReaderRenderFrame';
import { ReaderCommentBubblePainter } from './ReaderCommentBubble';
import { ReaderV2PagePainter } from './ReaderV2PagePainter';
import {
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2RegexBubbleSegment
} from './ReaderV2PageLayout';

export class ReaderV2PageFrameNode extends FrameNode {
  private page: ReaderV2PageLayout | null = null;
  private highlightStart: number = -1;
  private highlightEnd: number = -1;
  private highlightColor: number = 0x55FFE58A;
  private selectionStart: number = -1;
  private selectionEnd: number = -1;
  private selectionColor: number = 0x553B82F6;

  constructor(uiContext: UIContext) {
    super(uiContext);
  }

  update(page: ReaderV2PageLayout | null, highlightStart: number, highlightEnd: number,
    selectionStart: number, selectionEnd: number): void {
    this.page = page;
    this.highlightStart = highlightStart;
    this.highlightEnd = highlightEnd;
    this.selectionStart = selectionStart;
    this.selectionEnd = selectionEnd;
    const renderNode = this.getRenderNode();
    if (renderNode) renderNode.invalidate();
  }

  setOverlayColors(highlightColor: number, selectionColor: number): void {
    this.highlightColor = highlightColor;
    this.selectionColor = selectionColor;
  }

  onMeasure(constraint: LayoutConstraint): void {
    this.setMeasuredSize({
      width: Math.max(constraint.minSize.width, constraint.maxSize.width),
      height: Math.max(constraint.minSize.height, constraint.maxSize.height)
    });
  }

  onLayout(position: Position): void {
    this.setLayoutPosition(position);
  }

  onDraw(context: DrawContext): void {
    if (!this.page) return;
    // The same painter rasterizes the settled page for simulation turns; see ReaderV2PagePainter.
    ReaderV2PagePainter.paint(context.canvas, this.page, this.highlightStart, this.highlightEnd,
      this.highlightColor, this.selectionStart, this.selectionEnd, this.selectionColor);
  }
}

export class ReaderV2PageNodeController extends NodeController {
  /** Optional creation probe for device benchmarks; inactive in ordinary reading. */
  static onNodeCreated: (() => void) | null = null;
  private node: ReaderV2PageFrameNode | null = null;
  private page: ReaderV2PageLayout | null = null;
  private uiContext: UIContext | null = null;
  private requestedHost: string = '';
  private mountedHost: string = '';
  private bindingSerial: number = 0;
  private highlightStart: number = -1;
  private highlightEnd: number = -1;
  private selectionStart: number = -1;
  private selectionEnd: number = -1;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.uiContext = uiContext;
    this.mountedHost = this.requestedHost;
    ReaderV2PageNodeController.onNodeCreated?.();
    this.node = new ReaderV2PageFrameNode(uiContext);
    this.node.update(this.page, this.highlightStart, this.highlightEnd, this.selectionStart, this.selectionEnd);
    return this.node;
  }

  /** A page-keyed NodeContainer will create its own node; do not rebuild the outgoing node as well. */
  bindPageToHost(page: ReaderV2PageLayout | null, host: string): void {
    if (this.requestedHost === host) { this.updatePage(page); return; }
    this.requestedHost = host;
    this.page = page;
    const serial = ++this.bindingSerial;
    const uiContext = this.uiContext;
    if (!this.node || !uiContext) return;
    ReaderRenderFrame.wait(uiContext).then((): void => {
      if (serial !== this.bindingSerial || this.requestedHost !== host || this.mountedHost === host) return;
      // Preserve the compatibility repair if an ArkUI version retains the old container despite its new key.
      this.rebuild();
    });
  }

  updatePage(page: ReaderV2PageLayout | null, forceRebuild: boolean = false): void {
    // ArkUI reevaluates the reader Builder for every page-curl animation frame. The settled page object does not
    // change during those frames, so invalidating its native RenderNode each time only resubmits identical glyphs
    // and can expose a one-frame baseline/layout fluctuation during rapid turns.
    if (!forceRebuild && this.page === page) return;
    this.bindingSerial++;
    this.page = page;
    if (this.node) {
      // RenderNode.invalidate() is not sufficient on every HarmonyOS build when a NodeContainer keeps the same
      // controller: the footer/state advances but the custom FrameNode may continue submitting the old page.
      // Rebuild only this lightweight native node at the settled page handoff. The incoming animation leaf remains
      // above it for one frame, so the replacement is both deterministic and visually continuous.
      this.rebuild();
    } else {
      this.publish();
    }
  }

  /** Window position (vp) of the mounted native page node, so a raster can align with the live glyphs. */
  nodePositionToWindow(): Position | null {
    if (!this.node) return null;
    try {
      return this.node.getPositionToWindow();
    } catch (_) {
      return null;
    }
  }

  updateHighlight(start: number, end: number): void {
    if (this.highlightStart === start && this.highlightEnd === end) return;
    this.highlightStart = start;
    this.highlightEnd = end;
    this.publish();
  }

  updateSelection(start: number, end: number): void {
    if (this.selectionStart === start && this.selectionEnd === end) return;
    this.selectionStart = start;
    this.selectionEnd = end;
    this.publish();
  }

  glyphDisplayOffsetAt(x: number, y: number): number {
    if (!this.page) return -1;
    for (const fragment of this.page.fragments) {
      if (!fragment.paragraph || !fragment.clipRect.contains(x, y)) continue;
      const position = fragment.paragraph.getGlyphPositionAtCoordinate(
        x - fragment.paragraphX, y - fragment.paragraphY).position;
      return Math.max(fragment.displayStart, Math.min(fragment.displayEnd, fragment.displayStart + position));
    }
    return -1;
  }

  wordRangeAt(x: number, y: number): number[] {
    if (!this.page) return [];
    for (const fragment of this.page.fragments) {
      if (!fragment.paragraph || !fragment.clipRect.contains(x, y)) continue;
      const position = fragment.paragraph.getGlyphPositionAtCoordinate(
        x - fragment.paragraphX, y - fragment.paragraphY).position;
      const range = fragment.paragraph.getWordBoundary(position);
      return [fragment.displayStart + range.start, fragment.displayStart + range.end];
    }
    return [];
  }

  private publish(): void {
    if (this.node) {
      this.node.update(this.page, this.highlightStart, this.highlightEnd,
        this.selectionStart, this.selectionEnd);
    }
  }
}
