import { PdfView, pdfViewManager, pdfService } from '@kit.PDFKit';
import { PdfSuperResolutionOverlay } from './PdfSuperResolutionOverlay';

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
        Math.abs(touch.windowX - this.touchX) <= 8 && Math.abs(touch.windowY - this.touchY) <= 8) this.onTap();
      this.tapCandidate = false; this.viewportRevision++;
    }
  }

  aboutToAppear(): void {
    this.alive = true;
    this.controller.registerPageChangedListener((index: number): void => {
      if (this.alive && this.loaded) { this.currentPage = index; this.viewportRevision++; this.onPage(index); }
    });
    this.controller.registerScrollListener((): void => { if (this.alive && this.superResolution) this.viewportRevision++; });
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
      this.onReady(this.controller.getPageCount(), this.controller.getPageIndex());
    } catch (error) { if (this.alive) this.onFailure(error instanceof Error ? error.message : 'PDF 打开失败'); }
    finally { this.opening = false; if (!this.alive) this.release(); }
  }

  aboutToDisappear(): void {
    this.alive = false; this.loaded = false;
    if (!this.opening) this.release();
  }

  private release(): void {
    if (this.released) return;
    this.released = true;
    try { this.controller.releaseDocument(); } catch (error) { console.warn('[PDF] release failed:', error); }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    PdfView({ controller: this.controller, pageFit: pdfService.PageFit.FIT_WIDTH,
      pageLayout: pdfService.PageLayout.LAYOUT_SINGLE, isContinuous: true, showScroll: true })
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
    }.width('100%').height('100%')
      // Observe the container so PdfView keeps its own native touch handling.
      .onTouch((event: TouchEvent): void => { this.observeTouch(event); })
  }
}
