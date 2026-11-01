import { pdfViewManager, pdfService } from '@kit.PDFKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ReaderComicSuperResolution, ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { PdfEnhancedPage, PdfSuperResolutionSession } from '../../core/book/pdf/PdfSuperResolutionSession';
import { PdfRasterPolicy } from '../../core/book/pdf/PdfRasterModels';

class PdfEnhancedLayer {
  pageIndex: number = 0;
  uri: string = '';
  left: number = 0;
  top: number = 0;
  layerWidth: number = 0;
  layerHeight: number = 0;
}

/** Non-interactive pixels over the native page; native PDF retains all gestures and navigation. */
@Component
export struct PdfSuperResolutionOverlay {
  controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  sourcePath: string = '';
  @Prop @Watch('refresh') active: boolean = false;
  @Prop @Watch('refresh') suspended: boolean = false;
  @Prop @Watch('refresh') pageIndex: number = 0;
  @Prop pageCount: number = 0;
  @Prop @Watch('refresh') viewportRevision: number = 0;
  @State layers: PdfEnhancedLayer[] = [];
  onStatus: (text: string) => void = (_text: string): void => {};
  private session: PdfSuperResolutionSession | null = null;
  private alive: boolean = false;
  private serial: number = 0;
  private timer: number = -1;
  private working: boolean = false;
  private pending: boolean = false;
  private viewWidth: number = 0;
  private viewHeight: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.session = new PdfSuperResolutionSession(this.sourcePath, AppStorage.get<string>('appCacheDir') || '');
    this.refresh();
  }

  aboutToDisappear(): void {
    this.alive = false; this.serial++;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.session?.dispose(); this.session = null;
  }

  private allowed(): boolean {
    return this.alive && this.active && !this.suspended && this.viewWidth > 0 && this.viewHeight > 0 &&
      ReaderComicSuperResolution.access() === ReaderComicSuperResolutionAccess.READY;
  }

  refresh(): void {
    this.serial++; this.layers = [];
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1; this.pending = false;
    if (!this.active) { this.session?.dispose(); this.session = null; this.onStatus(''); return; }
    if (!this.allowed()) return;
    if (!this.session) this.session = new PdfSuperResolutionSession(this.sourcePath, AppStorage.get<string>('appCacheDir') || '');
    this.timer = setTimeout((): void => {
      this.timer = -1; this.pending = true;
      this.enhanceVisiblePages();
    }, 180);
  }

  private async enhanceVisiblePages(): Promise<void> {
    if (this.working || !this.pending || !this.allowed() || !this.session) return;
    this.pending = false; this.working = true;
    const token = this.serial;
    const session = this.session;
    const current = (): boolean => token === this.serial && this.allowed();
    try {
      const candidates = PdfRasterPolicy.candidates(this.pageIndex, this.pageCount);
      session.retain(candidates);
      const visible: PdfEnhancedLayer[] = [];
      for (const index of candidates) {
        if (!current()) return;
        if (index === this.pageIndex && !session.get(index)) this.onStatus('正在增强当前页…');
        const page = await session.prepare(index, Math.round(this.getUIContext().vp2px(this.viewWidth)), current);
        if (!current()) return;
        if (!page) continue;
        const layer = this.layerFor(page);
        if (layer) { visible.push(layer); this.layers = visible.slice(); }
        if (index === this.pageIndex) this.onStatus(page.enhancedUri ? 'AI 超分' :
          page.raster.eligible ? '增强未完成，显示原页' : page.raster.reason);
      }
    } catch (error) {
      if (current()) this.onStatus('增强未完成，显示原页');
      console.warn('[PdfSR] keeping native page:', error);
    } finally {
      this.working = false;
      if (this.pending && this.allowed()) this.enhanceVisiblePages();
    }
  }

  private layerFor(page: PdfEnhancedPage): PdfEnhancedLayer | undefined {
    if (!page.enhancedUri || !deviceInfo.apiAvailable('26.0.0')) return undefined;
    const rect = new pdfService.PdfRect();
    rect.left = page.raster.rectLeft; rect.bottom = page.raster.rectBottom;
    rect.right = page.raster.rectRight; rect.top = page.raster.rectTop;
    const view = this.controller.pdfRectToViewRect(page.raster.pageIndex, rect);
    if (![view.left, view.top, view.right, view.bottom].every((n: number): boolean => Number.isFinite(n))) return undefined;
    const layer = new PdfEnhancedLayer();
    layer.pageIndex = page.raster.pageIndex; layer.uri = page.enhancedUri;
    layer.left = this.getUIContext().px2vp(Math.min(view.left, view.right));
    layer.top = this.getUIContext().px2vp(Math.min(view.top, view.bottom));
    layer.layerWidth = this.getUIContext().px2vp(Math.abs(view.right - view.left));
    layer.layerHeight = this.getUIContext().px2vp(Math.abs(view.bottom - view.top));
    if (layer.layerWidth <= 0 || layer.layerHeight <= 0 || layer.left >= this.viewWidth || layer.top >= this.viewHeight ||
      layer.left + layer.layerWidth <= 0 || layer.top + layer.layerHeight <= 0) return undefined;
    return layer;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.layers, (layer: PdfEnhancedLayer) => {
        Image(layer.uri).id(`pdf_sr_page_${layer.pageIndex}`).objectFit(ImageFit.Fill)
          .width(layer.layerWidth).height(layer.layerHeight).position({ x: layer.left, y: layer.top })
          .onError((): void => {
            this.layers = this.layers.filter((item: PdfEnhancedLayer): boolean => item.pageIndex !== layer.pageIndex);
            this.onStatus('增强图读取失败，显示原页');
          })
      }, (layer: PdfEnhancedLayer): string => `${layer.pageIndex}:${layer.uri}`)
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no-hide-descendants')
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        this.viewWidth = Number(after.width); this.viewHeight = Number(after.height); this.refresh();
      })
  }
}
