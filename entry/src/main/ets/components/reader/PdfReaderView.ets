import { PdfView, pdfViewManager, pdfService } from '@kit.PDFKit';
import { PdfSuperResolutionOverlay } from './PdfSuperResolutionOverlay';

const SCROLL_THUMB_HIDE_MS: number = 1200;
const SCROLL_THUMB_MIN_HEIGHT: number = 40;
const SCROLL_THUMB_TOUCH_WIDTH: number = 28;

/** Owns one native document. Parent owns navigation and durable progress. */
@Component
export struct PdfReaderView {
  controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  sourcePath: string = '';
  initialPage: number = 0;
  @Prop superResolution: boolean = false;
  @Prop showOriginal: boolean = false;
  @Prop enhancementSuspended: boolean = false;
  @Prop layoutRevision: number = 0;
  @State currentPage: number = 0;
  @State loadedPageCount: number = 0;
  @State viewportRevision: number = 0;
  @State viewWidth: number = 0;
  @State viewHeight: number = 0;
  @State scrollFraction: number = 0;
  @State scrollViewRatio: number = 1;
  @State scrollThumbVisible: boolean = false;
  @State scrollThumbDragging: boolean = false;
  onReady: (count: number, page: number) => void = (): void => {};
  onPage: (page: number) => void = (): void => {};
  onFailure: (message: string) => void = (): void => {};
  onTap: () => void = (): void => {};
  onEnhancementStatus: (text: string) => void = (_text: string): void => {};
  private alive: boolean = false;
  private loaded: boolean = false;
  private opening: boolean = false;
  private released: boolean = false;
  private tapCandidate: boolean = false;
  private touchX: number = 0;
  private touchY: number = 0;
  private touchStarted: number = 0;
  private scrollThumbTimer: number = -1;
  private dragStartTop: number = 0;
  private dragPage: number = -1;

  private observeTouch(event: TouchEvent): void {
    const touch = event.changedTouches.length ? event.changedTouches[0] : event.touches[0];
    if (!touch) return;
    if (event.type === TouchType.Down) {
      this.tapCandidate = event.touches.length === 1;
      this.touchX = touch.windowX; this.touchY = touch.windowY; this.touchStarted = Date.now();
      this.viewportRevision++;
    } else if (event.type === TouchType.Move) {
      if (Math.abs(touch.windowX - this.touchX) > 8 || Math.abs(touch.windowY - this.touchY) > 8) this.tapCandidate = false;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (event.type === TouchType.Up && this.tapCandidate && Date.now() - this.touchStarted < 350 && this.loaded &&
        !this.scrollThumbDragging && Math.abs(touch.windowX - this.touchX) <= 8 && Math.abs(touch.windowY - this.touchY) <= 8) {
        this.onTap();
      }
      this.tapCandidate = false; this.viewportRevision++;
    }
  }

  aboutToAppear(): void {
    this.alive = true;
    this.controller.registerPageChangedListener((index: number): void => {
      if (this.alive && this.loaded) { this.currentPage = index; this.viewportRevision++; this.onPage(index); }
    });
    this.controller.registerScrollListener((param: pdfViewManager.ScrollParam): void => {
      if (!this.alive) return;
      this.updateScrollThumb(param);
      if (this.superResolution) this.viewportRevision++;
    });
    this.controller.registerScaleChangedListener((): void => { if (this.alive && this.superResolution) this.viewportRevision++; });
    this.controller.registerPageFitChangedListener((): void => { if (this.alive && this.superResolution) this.viewportRevision++; });
  }

  private async open(): Promise<void> {
    if (!this.alive || this.opening || this.loaded) return;
    this.opening = true;
    try {
      const result = await this.controller.loadDocument(this.sourcePath, '', this.initialPage);
      if (!this.alive) return;
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        this.onFailure(result === pdfService.ParseResult.PARSE_ERROR_PASSWORD ?
          '此 PDF 需要打开密码，暂不支持阅读' : 'PDF 打开失败，文件可能损坏或不受支持');
        return;
      }
      this.loaded = true;
      this.currentPage = this.controller.getPageIndex(); this.loadedPageCount = this.controller.getPageCount();
      this.scrollFraction = this.loadedPageCount > 1 ? this.currentPage / (this.loadedPageCount - 1) : 0;
      this.onReady(this.controller.getPageCount(), this.controller.getPageIndex());
    } catch (error) { if (this.alive) this.onFailure(error instanceof Error ? error.message : 'PDF 打开失败'); }
    finally { this.opening = false; if (!this.alive) this.release(); }
  }

  aboutToDisappear(): void {
    this.alive = false; this.loaded = false;
    if (this.scrollThumbTimer >= 0) clearTimeout(this.scrollThumbTimer);
    if (!this.opening) this.release();
  }

  private release(): void {
    if (this.released) return;
    this.released = true;
    try { this.controller.releaseDocument(); } catch (error) { console.warn('[PDF] release failed:', error); }
  }

  /** offsetY is scroll progress: 0 at the top, 1 when the end of the document is reached (measured on device). */
  private updateScrollThumb(param: pdfViewManager.ScrollParam): void {
    if (!(param.pdfHeight > 0) || !(param.viewHeight > 0)) return;
    const ratio = Math.min(1, param.viewHeight / param.pdfHeight);
    this.scrollViewRatio = ratio;
    this.scrollFraction = Number.isFinite(param.offsetY) ? Math.max(0, Math.min(1, param.offsetY)) : 0;
    if (ratio < 0.98) this.showScrollThumb();
  }

  private showScrollThumb(): void {
    if (!this.scrollThumbVisible) this.scrollThumbVisible = true;
    if (this.scrollThumbTimer >= 0) clearTimeout(this.scrollThumbTimer);
    this.scrollThumbTimer = setTimeout((): void => {
      this.scrollThumbTimer = -1;
      if (!this.scrollThumbDragging) this.scrollThumbVisible = false;
    }, SCROLL_THUMB_HIDE_MS);
  }

  private trackHeight(): number {
    return Math.max(0, this.viewHeight - 16);
  }

  private thumbHeight(): number {
    return Math.min(this.trackHeight(), Math.max(SCROLL_THUMB_MIN_HEIGHT, this.trackHeight() * this.scrollViewRatio));
  }

  private thumbTop(): number {
    return 8 + (this.trackHeight() - this.thumbHeight()) * this.scrollFraction;
  }

  /** Dragging the thumb jumps by page; PdfView exposes page navigation, not a document offset in view units. */
  private dragThumb(offsetY: number): void {
    const range = this.trackHeight() - this.thumbHeight();
    if (range <= 0 || this.loadedPageCount <= 1) return;
    const fraction = Math.max(0, Math.min(1, (this.dragStartTop - 8 + offsetY) / range));
    this.scrollFraction = fraction;
    const page = Math.round(fraction * (this.loadedPageCount - 1));
    if (page === this.dragPage) return;
    this.dragPage = page;
    try { this.controller.goToPage(page); } catch (error) { console.warn('[PDF] thumb navigation failed:', error); }
  }

  @Builder
  scrollThumb() {
    // Drawn over the page edge, replacing the native scrollbar that reserves its own strip outside the page.
    Column() {
      Column()
        .width(this.scrollThumbDragging ? 6 : 4)
        .height('100%')
        .borderRadius(3)
        .backgroundColor('#73000000')
        .border({ width: 0.5, color: '#59FFFFFF' })
        .animation({ duration: 120, curve: Curve.EaseOut })
    }
    .width(SCROLL_THUMB_TOUCH_WIDTH)
    .height(this.thumbHeight())
    .alignItems(HorizontalAlign.End)
    .padding({ right: 3 })
    .position({ x: this.viewWidth - SCROLL_THUMB_TOUCH_WIDTH, y: this.thumbTop() })
    .opacity(this.scrollThumbVisible || this.scrollThumbDragging ? 1 : 0)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .hitTestBehavior(this.scrollThumbVisible || this.scrollThumbDragging ? HitTestMode.Block : HitTestMode.None)
    .accessibilityLevel('no')
    .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 1 })
      .onActionStart((): void => {
        this.scrollThumbDragging = true; this.dragStartTop = this.thumbTop(); this.dragPage = -1;
      })
      .onActionUpdate((event: GestureEvent): void => { this.dragThumb(event.offsetY); })
      .onActionEnd((): void => { this.scrollThumbDragging = false; this.showScrollThumb(); })
      .onActionCancel((): void => { this.scrollThumbDragging = false; this.showScrollThumb(); }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PdfView({ controller: this.controller, pageFit: pdfService.PageFit.FIT_WIDTH,
        pageLayout: pdfService.PageLayout.LAYOUT_SINGLE, isContinuous: true, showScroll: false })
        .id('pdf_document_view')
        .width('100%')
        .height('100%')
        .onAppear((): void => { this.open(); })
      if (this.loadedPageCount > 0 && this.superResolution) {
        PdfSuperResolutionOverlay({ controller: this.controller, sourcePath: this.sourcePath,
          active: this.superResolution, suspended: this.showOriginal || this.enhancementSuspended,
          pageIndex: this.currentPage, pageCount: this.loadedPageCount,
          viewportRevision: this.viewportRevision + this.layoutRevision, onStatus: this.onEnhancementStatus })
      }
      if (this.loadedPageCount > 1 && this.viewWidth > SCROLL_THUMB_TOUCH_WIDTH) {
        this.scrollThumb()
      }
    }.width('100%').height('100%')
      // Observe the container so PdfView keeps its own native touch handling.
      .onTouch((event: TouchEvent): void => { this.observeTouch(event); })
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        this.viewWidth = Number(after.width); this.viewHeight = Number(after.height);
      })
  }
}
