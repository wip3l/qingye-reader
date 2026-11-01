import { pdfViewManager, pdfService } from '@kit.PDFKit';
import { PdfReaderView } from '../../../main/ets/components/reader/PdfReaderView';
import { PdfReaderControls } from '../../../main/ets/components/reader/PdfReaderControls';
import { PdfSearchTask } from '../../../main/ets/core/concurrency/PdfSearchTask';
import { PdfSearchRect } from '../../../main/ets/core/book/pdf/PdfModels';
import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';

@Entry
@Component
struct PdfNativeViewTest {
  @State fixturePath: string = '';
  @State result: string = 'PDF_NATIVE_VIEW_RUNNING';
  @State controlsPreview: boolean = false;
  @State menuVisible: boolean = true;
  @State activePanel: string = '';
  @State pageIndex: number = 1;
  @State previewIndex: number = -1;
  @State pageCount: number = 0;
  @State continuous: boolean = true;
  @State fitPage: boolean = false;
  @State superResolutionProbe: boolean = false;
  @State superResolution: boolean = false;
  @State showOriginal: boolean = false;
  @State enhancementStatus: string = '';
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private cycles: number = 0;
  aboutToAppear(): void {
    this.fixturePath = AppStorage.get<string>('pdfNativeProbePath') || '';
    this.controlsPreview = AppStorage.get<boolean>('pdfNativeControlsPreview') || false;
    this.superResolutionProbe = AppStorage.get<boolean>('pdfNativeSrProbe') || false;
    this.superResolution = this.superResolutionProbe;
  }
  private async ready(count: number): Promise<void> {
    this.pageCount = count;
    if (this.controlsPreview) { console.info('[PdfProbe] PDF_CONTROLS_PREVIEW_READY'); return; }
    if (this.superResolutionProbe) { await this.verifySuperResolution(); return; }
    try {
      if (count !== 3) throw new Error('Unexpected native view page count');
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 500); });
      if (this.controller.getPageIndex() !== 1) throw new Error(`Initial page was not restored: ${this.controller.getPageIndex()}`);
      this.controller.setPageZoom(1.5);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      this.controller.setPageLayout(pdfService.PageLayout.LAYOUT_DOUBLE);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      this.controller.setPageLayout(pdfService.PageLayout.LAYOUT_SINGLE);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      this.controller.goToPage(2);
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      const search = await PdfSearchTask.search(this.fixturePath, 'probe');
      if (search.hits.length !== 3) throw new Error(`Search matches=${search.hits.length}`);
      const hit = search.hits[2];
      const rects: pdfService.PdfRect[] = hit.rects.map((rect: PdfSearchRect): pdfService.PdfRect => {
        const box = new pdfService.PdfRect();
        box.left = rect.left; box.top = rect.top; box.right = rect.right; box.bottom = rect.bottom;
        return box;
      });
      this.controller.setHighlightRects([new pdfViewManager.PageRects(hit.pageIndex, rects)]);
      this.controller.goToPage(hit.pageIndex);
      setTimeout((): void => {
        if (this.controller.getPageIndex() !== 2) { this.finish('PDF_NATIVE_VIEW_FAIL page index'); return; }
        this.cycles++;
        this.fixturePath = '';
        setTimeout((): void => {
          if (this.cycles < 2) this.fixturePath = AppStorage.get<string>('pdfNativeProbePath') || '';
          else this.finish('PDF_NATIVE_VIEW_PASS');
        }, 400);
      }, 800);
    } catch (error) { this.finish(`PDF_NATIVE_VIEW_FAIL ${String(error)}`); }
  }
  private finish(message: string): void {
    this.result = message; AppStorage.setOrCreate('pdfNativeProbeResult', message);
    console.info(`[PdfProbe] ${message}`);
  }

  private async waitEnhanced(): Promise<void> {
    for (let attempt = 0; attempt < 300; attempt++) {
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 200); });
      if (this.enhancementStatus === 'AI 超分') return;
      if (this.enhancementStatus.includes('未完成')) throw new Error(this.enhancementStatus);
    }
    throw new Error(`PDF enhancement timed out: ${this.enhancementStatus}`);
  }

  private async verifySuperResolution(): Promise<void> {
    try {
      await this.waitEnhanced();
      this.showOriginal = true;
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      this.showOriginal = false;
      this.enhancementStatus = '';
      this.controller.setPageZoom(1.4); this.controller.goToPage(2);
      await this.waitEnhanced();
      if (this.controller.getPageIndex() !== 2) throw new Error('Enhanced PDF navigation failed');
      console.info('[PdfProbe] PASS actual PDF SR inference, original comparison, native zoom and page navigation');
      this.superResolution = false;
      this.fixturePath = '';
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 300); });
      this.finish('PDF_NATIVE_VIEW_PASS');
    } catch (error) { this.finish(`PDF_NATIVE_VIEW_FAIL ${String(error)}`); }
  }
  pageIndexes(): number[] {
    const result: number[] = [];
    for (let i = 0; i < this.pageCount; i++) result.push(i);
    return result;
  }

  @Builder
  navigationPreview() {
    List() {
      ForEach(this.pageIndexes(), (index: number) => {
        ListItem() {
          Text(`第 ${index + 1} 页`).width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16 })
            .onClick((): void => { this.activePanel = ''; this.controller.goToPage(index); })
        }
      }, (index: number): string => `${index}`)
    }.width('100%').height('100%').padding({ left: 8, right: 8, bottom: 12 })
  }

  build() {
    Stack() {
      if (this.fixturePath) {
        PdfReaderView({ controller: this.controller, sourcePath: this.fixturePath, initialPage: 1,
          superResolution: this.superResolution, showOriginal: this.showOriginal,
          enhancementSuspended: this.activePanel === 'search',
          onEnhancementStatus: (text: string): void => { this.enhancementStatus = text; },
          onReady: (count: number): void => { this.ready(count); },
          onPage: (index: number): void => { this.pageIndex = index; },
          onTap: (): void => { this.menuVisible = !this.menuVisible; },
          onFailure: (message: string): void => { this.finish(`PDF_NATIVE_VIEW_FAIL ${message}`); } })
      }
      if (this.controlsPreview) {
        PdfReaderControls({ bookTitle: 'PDF 阅读设计预览', menuVisible: this.menuVisible, activePanel: this.activePanel,
          navigationTitle: '页面', navigationCount: this.pageCount,
          navigationContent: (): void => { this.navigationPreview(); },
          ready: this.pageCount > 0, pageCount: this.pageCount, pageIndex: this.pageIndex, previewIndex: this.previewIndex,
          continuous: this.continuous, fitPage: this.fitPage,
          superResolution: this.superResolution, showOriginal: this.showOriginal, enhancementStatus: this.enhancementStatus,
          superResolutionAccess: this.superResolutionProbe ? ReaderComicSuperResolutionAccess.READY : ReaderComicSuperResolutionAccess.UNSUPPORTED,
          onSuperResolutionChange: (checked: boolean): void => { this.superResolution = checked; },
          onOriginalChange: (): void => { this.showOriginal = !this.showOriginal; },
          onPanelChange: (panel: string): void => { this.activePanel = panel; },
          onPageChange: (index: number): void => { this.previewIndex = -1; this.controller.goToPage(index); },
          onPreview: (index: number): void => { this.previewIndex = index; },
          onJump: (text: string): void => {
            const page = Number(text);
            if (Number.isInteger(page) && page >= 1 && page <= this.pageCount) {
              this.controller.goToPage(page - 1); this.activePanel = '';
            }
          },
          onContinuousChange: (checked: boolean): void => { this.continuous = checked; this.controller.setPageContinuous(checked); },
          onFitPageChange: (checked: boolean): void => {
            this.fitPage = checked; this.controller.setPageFit(checked ? pdfService.PageFit.FIT_PAGE : pdfService.PageFit.FIT_WIDTH);
          } })
      } else { Text(this.result).position({ x: 12, y: 48 }) }
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
