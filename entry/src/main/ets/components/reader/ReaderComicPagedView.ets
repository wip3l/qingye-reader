import { LocalBookService } from '../../core/book/LocalBookService';
import { image } from '@kit.ImageKit';
import { AnimatorResult } from '@kit.ArkUI';
import { ReaderPageTurnAnimation } from '../../core/reader/ReaderPageTurnAnimation';
import { ReaderPageCurlPainter } from '../ReaderPageCurlPainter';
import { ReaderEmulationFlipPainter, ReaderEmulationFlipRegion } from '../ReaderEmulationFlipPainter';
import { ReaderComicColorSession, ComicColorCandidate } from '@legado/aiengine';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderImageMarker } from '../../core/book/ReaderImageMarker';
import { ReaderComicProcessing } from '../../core/reader/ReaderComicProcessing';
import { ReaderComicProcessingBadge } from './ReaderComicProcessingBadge';
import {
  ReaderComicImageItem, ReaderComicImageSizes, ReaderComicInfoBadge, ReaderComicRetryRegistry, ReaderPendingImageHint
} from './ReaderComicView';

/** 阅读页向翻页视图发出的指令（点击翻页、音量键）；视图挂载时填入实现。 */
export class ReaderComicPagedController {
  turn: (direction: number) => void = () => {};
  /** 跨章切换没有成功：从停住的相邻章节退回本话。 */
  cancelCross: () => void = () => {};
}

/**
 * 漫画单页翻页视图。宽屏时两页并排为一个跨页；右→左模式下“下一页”在左边。
 * 只渲染当前跨页和左右各一个。越过本章首尾时：阅读页已预先切好相邻章节的页，那一格直接显示
 * 下一话第一个跨页或上一话最后一个跨页，翻过去后停在那里等阅读页把它设为当前章（onCrossChapter）；
 * 相邻章节还没准备好时那一格显示章节提示卡，松手后由阅读页正常切章（onBoundary）。
 * 相邻格与切换后的当前格使用同一个键，切换前后图片组件原样保留，不会重新加载。
 * 当前页码以阅读页的 pageIndex 为准，视图翻完一页后通过 onPageChanged 回报跨页首页。
 */
@Component
export struct ReaderComicPagedView {
  private processing: ReaderComicProcessing = new ReaderComicProcessing();
  colorSession: ReaderComicColorSession | null = null;
  private colorTimer: number = -1;
  private colorSpread: string = '';

  private updateColorViewport(): void {
    if (!this.colorSession?.foreground) return;
    if (this.animating || this.dragOffset !== 0) this.colorSession.motion();
    const key = `${this.chapterIndex}_${this.spreadIndex}`;
    if (key !== this.colorSpread) {
      this.colorSpread = key;
      this.colorSession.clearCompare();
    }
    const candidates: ComicColorCandidate[] = [];
    const start = this.spreadIndex * this.spreadSize();
    for (let i = start; i < Math.min(this.pages.length, start + this.spreadSize() * 3); i++) {
      candidates.push(new ComicColorCandidate(ReaderComicColorSession.source(this.pages[i]),
        i < start + this.spreadSize(), i - start, `${i + 1}`));
    }
    this.colorSession.update(candidates);
  }
  controller: ReaderComicPagedController = new ReaderComicPagedController();
  @Prop @Watch('onLayoutChanged') pages: string[] = [];
  @Prop @Watch('onPageIndexChanged') pageIndex: number = 0;
  @Prop @Watch('onLayoutChanged') chapterIndex: number = 0;
  @Prop @Watch('onLayoutChanged') viewWidth: number = 0;
  @Prop @Watch('onLayoutChanged') viewHeight: number = 0;
  @Prop @Watch('onLayoutChanged') dualPage: boolean = false;
  @Prop @Watch('onLayoutChanged') rightToLeft: boolean = false;
  @Prop @Watch('onLayoutChanged') animationType: number = ReaderPageTurnAnimation.SLIDE;
  @Prop darkMode: boolean = false;
  @Prop doubleTapZoom: boolean = true;
  /** 漫画超分（会员功能）。 */
  @Prop superResolution: boolean = false;
  /** 本书繁→简。 */
  @Prop textConvert: boolean = false;
  @Prop surfaceColor: string = '#000000';
  @Prop textColor: string = '#E6E6E6';
  @Prop hintColor: string = '#99FFFFFF';
  @Prop interactive: boolean = true;
  @Prop panDistance: number = 12;
  @Prop transitionOpacity: number = 1;
  /** 相邻章节标题；空串表示该方向没有章节。 */
  @Prop prevChapterTitle: string = '';
  @Prop nextChapterTitle: string = '';
  /** 阅读页预先切好的相邻章节分页；空数组表示还没准备好。 */
  @Prop prevChapterPages: string[] = [];
  @Prop nextChapterPages: string[] = [];
  @Prop infoVisible: boolean = false;
  @Prop infoChapter: string = '';
  @Prop infoPage: string = '';
  @Prop infoTime: string = '';
  @Prop infoBattery: number = -1;
  @Prop infoBottomInset: number = 6;
  onImageLongPress: (source: string, reload: () => void, snapshotId: string) => void = () => {};
  onImageDenied: (chapterIndex: number) => void = () => {};
  onPageChanged: (pageIndex: number) => void = () => {};
  /** 越过本章首尾且相邻章节没准备好：1 为下一话，-1 为上一话，由阅读页正常切章。 */
  onBoundary: (direction: number) => void = () => {};
  /** 已翻到预先装好的相邻章节并停在那里：阅读页把它设为当前章。 */
  onCrossChapter: (direction: number) => void = () => {};
  /** 坐标相对视图左上角。 */
  onTap: (x: number, y: number, width: number, height: number) => void = () => {};
  static readonly MAX_ZOOM: number = 4;
  static readonly DOUBLE_TAP_ZOOM: number = 2;
  @State private spreadIndex: number = 0;
  @State @Watch('drawCurl') private dragOffset: number = 0;
  @State private curlReady: boolean = false;
  @State private curlDirection: number = 0;
  private curlContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private curlPainter: ReaderPageCurlPainter = new ReaderPageCurlPainter();
  private emulationPainter: ReaderEmulationFlipPainter = new ReaderEmulationFlipPainter();
  private curlFront: image.PixelMap | null = null;
  private curlBack: image.PixelMap | null = null;
  private curlStationary: image.PixelMap | null = null;
  private curlDualPage: boolean = false;
  private curlRegion: number = ReaderEmulationFlipRegion.BOTTOM;
  private captureSerial: number = 0;
  private animationSerial: number = 0;
  private turnAnimator: AnimatorResult | null = null;
  private animationWatchdog: number = -1;
  private captureTask: Promise<void> | null = null;
  private canvasReady: boolean = false;
  @State private zoomScale: number = 1;
  @State private zoomX: number = 0;
  @State private zoomY: number = 0;
  private retryRegistry: ReaderComicRetryRegistry = new ReaderComicRetryRegistry();
  private animating: boolean = false;
  private touchDragged: boolean = false;
  private pinching: boolean = false;
  private pinchBaseScale: number = 1;
  private pinchBaseX: number = 0;
  private pinchBaseY: number = 0;
  private pinchFocusX: number = 0;
  private pinchFocusY: number = 0;
  private zoomPanActive: boolean = false;
  private panLastX: number = 0;
  private panLastY: number = 0;
  private panResync: boolean = false;

  aboutToAppear(): void {
    this.colorTimer = setInterval((): void => this.updateColorViewport(), 250);
    this.spreadIndex = this.spreadOf(this.pageIndex);
    this.controller.turn = (direction: number): void => this.turn(direction);
    this.controller.cancelCross = (): void => {
      this.cancelAnimation();
      this.animating = false;
      this.settleBack();
    };
  }

  aboutToDisappear(): void {
    this.cancelAnimation();
    this.clearCurl();
    clearInterval(this.colorTimer);
    this.colorSession?.update([]);
    this.colorSession?.touch(false);
    this.controller.turn = () => {};
    this.controller.cancelCross = () => {};
  }

  onLayoutChanged(): void {
    // 章节或分页变了（包括跨章停住后阅读页发布了新章）：停住的位移归零，按新页码重新定位。
    this.cancelAnimation();
    this.clearCurl();
    this.animating = false;
    this.dragOffset = 0;
    this.applyZoom(1, 0, 0);
    this.spreadIndex = this.spreadOf(this.pageIndex);
  }

  onPageIndexChanged(): void {
    if (this.animating) return;
    const target = this.spreadOf(this.pageIndex);
    if (target === this.spreadIndex) return;
    this.clearCurl();
    this.dragOffset = 0;
    this.applyZoom(1, 0, 0);
    this.spreadIndex = target;
  }

  private spreadSize(): number {
    return this.dualPage ? 2 : 1;
  }

  private spreadCount(): number {
    return Math.ceil(this.pages.length / this.spreadSize());
  }

  private spreadOf(pageIndex: number): number {
    const count = this.spreadCount();
    if (count <= 0) return 0;
    return Math.max(0, Math.min(count - 1, Math.floor(Math.max(0, pageIndex) / this.spreadSize())));
  }

  /** 跨页内的页码，按屏幕从左到右排列。 */
  private spreadPages(spread: number): number[] {
    const result: number[] = [];
    const first = spread * this.spreadSize();
    for (let page = first; page < Math.min(this.pages.length, first + this.spreadSize()); page++) {
      result.push(page);
    }
    return this.rightToLeft ? result.reverse() : result;
  }

  /** 越出本章的那一格能否直接显示相邻章节。 */
  private hasNeighbor(direction: number): boolean {
    return direction > 0 ? this.hasChapter(1) && this.nextChapterPages.length > 0 :
      this.hasChapter(-1) && this.prevChapterPages.length > 0;
  }

  /** 相邻章节在这一格显示的跨页序号：下一话第一个，上一话最后一个。 */
  private neighborSpread(direction: number): number {
    if (direction > 0) return 0;
    return Math.max(0, Math.ceil(this.prevChapterPages.length / this.spreadSize()) - 1);
  }

  private neighborSpreadPages(direction: number): number[] {
    const pages = direction > 0 ? this.nextChapterPages : this.prevChapterPages;
    const result: number[] = [];
    const first = this.neighborSpread(direction) * this.spreadSize();
    for (let page = first; page < Math.min(pages.length, first + this.spreadSize()); page++) result.push(page);
    return this.rightToLeft ? result.reverse() : result;
  }

  /** 格子的键：相邻章节格与它成为当前章后的格子同键，切换时组件得以保留。 */
  private slotKey(spread: number): string {
    if (spread >= 0 && spread < this.spreadCount()) return `${this.chapterIndex}_${this.spreadSize()}_${spread}`;
    const direction = spread < 0 ? -1 : 1;
    if (this.hasNeighbor(direction)) {
      return `${this.chapterIndex + direction}_${this.spreadSize()}_${this.neighborSpread(direction)}`;
    }
    return `card_${this.chapterIndex}_${direction}`;
  }

  private viewW(): number {
    return Math.max(1, this.viewWidth);
  }

  private viewH(): number {
    return Math.max(1, this.viewHeight);
  }

  /** 第 k 个相邻跨页（k = 跨页序号 − 当前序号）在屏幕上的横向位置。 */
  private slotX(spread: number): number {
    const k = spread - this.spreadIndex;
    const direction = this.dragDirection(this.dragOffset) || this.curlDirection;
    if (this.animationType === ReaderPageTurnAnimation.NONE) return 0;
    // 仿真从手势第一帧就使用固定页面；截图尚未就绪时不能借用平移布局。
    if (this.animationType === ReaderPageTurnAnimation.FADE || this.usesCurl()) return 0;
    if (this.animationType === ReaderPageTurnAnimation.STACK) {
      // 下一跨页从上方覆盖；反向翻页时当前跨页移开，露出上一跨页。
      if (direction > 0 && k === 0) return 0;
      if (direction < 0 && k === -1) return 0;
    }
    return (this.rightToLeft ? -k : k) * this.viewW() + this.dragOffset;
  }

  private turnProgress(): number {
    return Math.min(1, Math.abs(this.dragOffset) / this.viewW());
  }

  private slotOpacity(spread: number): number {
    const k = spread - this.spreadIndex;
    const direction = this.dragDirection(this.dragOffset) || this.curlDirection;
    if (this.animationType === ReaderPageTurnAnimation.NONE) {
      return k === (this.turnProgress() >= 1 ? direction : 0) ? 1 : 0;
    }
    if (this.curlReady) return k === direction ? 1 : 0;
    if (this.usesCurl()) {
      // 截图期间只显示当前页；截图失败直接提交时仍能保留跨章目标页等待接管。
      return k === (this.turnProgress() >= 1 ? direction : 0) ? 1 : 0;
    }
    if (this.animationType === ReaderPageTurnAnimation.FADE) {
      return k === 0 ? 1 : (k === direction ? this.turnProgress() : 0);
    }
    return k === 0 || k === direction ? 1 : 0;
  }

  private slotZIndex(spread: number): number {
    const k = spread - this.spreadIndex;
    if (this.animationType === ReaderPageTurnAnimation.FADE) return k === 0 ? 0 : 1;
    return k > 0 ? 2 : (k === 0 ? 1 : 0);
  }

  private usesCurl(): boolean {
    return this.animationType === ReaderPageTurnAnimation.SIMULATION ||
      this.animationType === ReaderPageTurnAnimation.THREE_D;
  }

  private snapshotId(spread: number): string {
    return `reader_comic_spread_${this.slotKey(spread)}`;
  }

  private clearCurl(resetGesture: boolean = true): void {
    this.captureSerial++;
    this.captureTask = null;
    this.curlReady = false;
    this.curlDirection = 0;
    const front = this.curlFront;
    const back = this.curlBack;
    const stationary = this.curlStationary;
    this.curlStationary = null;
    this.curlDualPage = false;
    if (resetGesture) {
      this.emulationPainter.clearCorner();
      this.curlRegion = ReaderEmulationFlipRegion.BOTTOM;
    }
    this.curlFront = null;
    this.curlBack = null;
    if (this.canvasReady) this.curlContext.clearRect(0, 0, this.viewW(), this.viewH());
    // Canvas 的最后一帧提交到渲染线程后再释放位图。
    setTimeout((): void => {
      if (front) front.release().catch(() => {});
      if (back) back.release().catch(() => {});
      if (stationary) stationary.release().catch(() => {});
    }, 48);
  }

  private prepareCurl(direction: number): Promise<void> {
    if (!this.usesCurl() || direction === 0) return Promise.resolve();
    if (this.curlDirection === direction && this.captureTask) return this.captureTask;
    this.clearCurl(false);
    this.curlDirection = direction;
    const serial = this.captureSerial;
    this.captureTask = this.captureCurl(direction, serial);
    return this.captureTask;
  }

  private usesDoublePageCurl(direction: number): boolean {
    if (this.animationType !== ReaderPageTurnAnimation.THREE_D || !this.dualPage ||
      this.spreadPages(this.spreadIndex).length !== 2) return false;
    const target = this.spreadIndex + direction;
    const pages = target >= 0 && target < this.spreadCount() ? this.spreadPages(target) :
      (this.hasNeighbor(direction) ? this.neighborSpreadPages(direction) : []);
    // 奇数尾页当前按整屏显示，不能将一张完整漫画截成两张纸。
    return pages.length === 2;
  }

  private async cropCurlHalf(bitmap: image.PixelMap, right: boolean): Promise<void> {
    const info = await bitmap.getImageInfo();
    const split = Math.floor(info.size.width / 2);
    if (split < 1) throw new Error('漫画双页快照宽度不足');
    await bitmap.crop({ x: right ? split : 0, y: 0,
      size: { width: right ? info.size.width - split : split, height: info.size.height } });
  }

  private async captureCurl(direction: number, serial: number): Promise<void> {
    let front: image.PixelMap | null = null;
    let back: image.PixelMap | null = null;
    let stationary: image.PixelMap | null = null;
    const dual = this.usesDoublePageCurl(direction);
    const physicalDirection = this.rightToLeft ? -direction : direction;
    try {
      // 等待相邻页和 Canvas 完成布局；截取未做位移/透明度变换的内层节点。
      await new Promise<void>((resolve) => setTimeout(resolve, 16));
      if (serial !== this.captureSerial) return;
      const snapshot = this.getUIContext().getComponentSnapshot();
      front = await snapshot.get(this.snapshotId(this.spreadIndex));
      if (serial !== this.captureSerial) return;
      back = await snapshot.get(this.snapshotId(this.spreadIndex + direction));
      if (serial !== this.captureSerial) return;
      if (dual) {
        stationary = await front.clone();
        if (serial !== this.captureSerial) return;
        await this.cropCurlHalf(stationary, physicalDirection < 0);
        if (serial !== this.captureSerial) return;
        await this.cropCurlHalf(front, physicalDirection > 0);
        if (serial !== this.captureSerial) return;
        await this.cropCurlHalf(back, physicalDirection < 0);
        if (serial !== this.captureSerial) return;
      }
      this.curlFront = front;
      this.curlBack = back;
      this.curlStationary = stationary;
      this.curlDualPage = dual;
      stationary = null;
      front = null;
      back = null;
      this.curlReady = true;
      this.drawCurl();
    } catch (error) {
      // 截图不可用时由 animateOffset 直接完成翻页，不能临时改用平移。
      console.warn('漫画翻页截图失败:', error);
    } finally {
      if (front) front.release().catch(() => {});
      if (back) back.release().catch(() => {});
      if (stationary) stationary.release().catch(() => {});
    }
  }

  private drawCurl(): void {
    if (!this.canvasReady || !this.curlReady || !this.curlFront || !this.curlBack) return;
    // 绘制器接收物理翻动方向；RTL 时与阅读顺序相反，图片本身不做镜像。
    const direction = this.rightToLeft ? -this.curlDirection : this.curlDirection;
    if (this.animationType === ReaderPageTurnAnimation.THREE_D) {
      this.emulationPainter.draw(this.curlContext, this.curlFront, this.curlBack,
        this.viewW(), this.viewH(), this.turnProgress(), direction, this.curlRegion,
        this.curlDualPage, this.viewW() / 2, this.viewW() / 2, 1 / this.getUIContext().vp2px(1), this.surfaceColor, this.darkMode);
      if (this.curlDualPage && this.curlStationary) {
        // 绘制器先清空画布并画折页，再把静止半页放到纸背下面，底层其余部分显示目标页。
        this.curlContext.save();
        this.curlContext.globalCompositeOperation = 'destination-over';
        this.curlContext.drawImage(this.curlStationary, direction > 0 ? 0 : this.viewW() / 2,
          0, this.viewW() / 2, this.viewH());
        this.curlContext.restore();
      }
    } else {
      this.curlPainter.draw(this.curlContext, this.curlFront, this.curlBack,
        this.viewW(), this.viewH(), this.turnProgress(), direction, false, this.darkMode);
    }
  }

  private cancelAnimation(): void {
    this.animationSerial++;
    clearTimeout(this.animationWatchdog);
    const animator = this.turnAnimator;
    this.turnAnimator = null;
    if (animator) animator.cancel();
  }

  private async animateOffset(target: number, onFinish: () => void): Promise<void> {
    this.cancelAnimation();
    const serial = this.animationSerial;
    this.animating = true;
    if (this.animationType !== ReaderPageTurnAnimation.NONE) {
      await this.prepareCurl(this.dragDirection(target || this.dragOffset));
    }
    if (serial !== this.animationSerial) return;
    const finish = (): void => {
      if (serial !== this.animationSerial) return;
      this.cancelAnimation();
      this.dragOffset = target;
      onFinish();
    };
    if (this.animationType === ReaderPageTurnAnimation.NONE || (this.usesCurl() && !this.curlReady)) {
      finish();
      return;
    }
    let duration = this.usesCurl() ? 320 : 240;
    let easing = 'ease-out';
    if (this.animationType === ReaderPageTurnAnimation.THREE_D) {
      if (target === 0) {
        duration = Math.max(80, Math.min(180, Math.round(180 * this.turnProgress())));
        easing = 'cubic-bezier(0.65, 0, 0.35, 1)';
      } else {
        const released = this.emulationPainter.flatRemainingFraction(
          this.curlDualPage ? this.viewW() / 2 : this.viewW(), this.curlDualPage ? this.viewW() / 2 : 0);
        const fraction = released >= 0 ? released : 1 - this.turnProgress();
        duration = Math.max(180, Math.round(400 * Math.pow(Math.max(0, fraction), 0.6)));
        easing = 'cubic-bezier(0.3, 0.4, 0.7, 1)';
      }
    }
    try {
      const animator = this.getUIContext().createAnimator({
        duration: duration, easing: easing, delay: 0, fill: 'forwards',
        direction: 'normal', iterations: 1, begin: this.dragOffset, end: target
      });
      this.turnAnimator = animator;
      animator.onFrame = (offset: number): void => {
        if (serial !== this.animationSerial) return;
        this.dragOffset = offset;
      };
      animator.onFinish = finish;
      this.animationWatchdog = setTimeout(finish, duration + 100);
      animator.play();
    } catch (error) {
      console.warn('漫画翻页动画失败:', error);
      finish();
    }
  }

  /** 翻到 direction 方向时当前跨页要移到的位置。 */
  private turnOffset(direction: number): number {
    return (this.rightToLeft ? direction : -direction) * this.viewW();
  }

  /** 手指横向位移对应的阅读方向：左→右模式向左拖是下一页，右→左模式相反。 */
  private dragDirection(offsetX: number): number {
    if (offsetX === 0) return 0;
    const leftward = offsetX < 0;
    return this.rightToLeft ? (leftward ? -1 : 1) : (leftward ? 1 : -1);
  }

  private hasChapter(direction: number): boolean {
    return direction > 0 ? !!this.nextChapterTitle : !!this.prevChapterTitle;
  }

  private turn(direction: number): void {
    if (this.animating || this.pages.length === 0 || direction === 0) return;
    const target = this.spreadIndex + direction;
    if (target < 0 || target >= this.spreadCount()) {
      if (this.hasNeighbor(direction)) {
        this.applyZoom(1, 0, 0);
        this.animateCross(direction);
      } else {
        this.onBoundary(direction);
      }
      return;
    }
    this.applyZoom(1, 0, 0);
    this.animateTurn(direction);
  }

  /** 翻进预先装好的相邻章节后停住，等阅读页发布新章（onLayoutChanged）或取消（cancelCross）。 */
  private animateCross(direction: number): void {
    this.animateOffset(this.turnOffset(direction), (): void => {
      this.onCrossChapter(direction);
    });
  }

  private animateTurn(direction: number): void {
    this.animateOffset(this.turnOffset(direction), (): void => this.finishTurn(direction));
  }

  private finishTurn(direction: number): void {
    // 先换当前序号再归零位移：相邻格按新序号重新定位后恰好落在动画终点，不会闪动。
    this.clearCurl();
    this.spreadIndex = Math.max(0, Math.min(this.spreadCount() - 1, this.spreadIndex + direction));
    this.dragOffset = 0;
    this.animating = false;
    this.onPageChanged(this.spreadIndex * this.spreadSize());
  }

  private settleBack(): void {
    if (this.dragOffset === 0 || (this.usesCurl() && !this.curlReady)) {
      // 尚未显示卷页时取消手势，直接丢弃待完成截图，不再等待截图后补播回弹。
      this.cancelAnimation();
      this.clearCurl();
      this.dragOffset = 0;
      this.animating = false;
      return;
    }
    this.animateOffset(0, (): void => {
      this.clearCurl();
      this.animating = false;
    });
  }

  private zoomed(): boolean {
    return this.zoomScale > 1.001;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private applyZoom(scale: number, x: number, y: number): void {
    let nextScale = this.clamp(scale, 1, ReaderComicPagedView.MAX_ZOOM);
    if (nextScale <= 1.001) nextScale = 1;
    const boundX = (nextScale - 1) * this.viewW() / 2;
    const boundY = (nextScale - 1) * this.viewH() / 2;
    this.zoomScale = nextScale;
    this.zoomX = this.clamp(x, -boundX, boundX);
    this.zoomY = this.clamp(y, -boundY, boundY);
  }

  /** 把缩放前位于 origin 的点放到 focus 处，同时从 base 状态缩放到 nextScale。 */
  private zoomAround(focusX: number, focusY: number, originX: number, originY: number, baseScale: number,
    baseX: number, baseY: number, nextScale: number): void {
    const scale = this.clamp(nextScale, 1, ReaderComicPagedView.MAX_ZOOM);
    const ratio = scale / Math.max(0.001, baseScale);
    const centerX = this.viewW() / 2;
    const centerY = this.viewH() / 2;
    this.applyZoom(scale, focusX - centerX - ratio * (originX - centerX - baseX),
      focusY - centerY - ratio * (originY - centerY - baseY));
  }

  private tapPoint(event: GestureEvent): number[] {
    const finger = event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? [finger.localX, finger.localY] : [this.viewW() / 2, this.viewH() / 2];
  }

  private retryKey(pageIndex: number): string {
    return `${this.chapterIndex}_${pageIndex}`;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) this.colorSession?.touch(true);
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.colorSession?.touch(false);
    if (event.type === TouchType.Down && event.touches.length <= 1) this.touchDragged = false;
  }

  private handleDoubleTap(event: GestureEvent): void {
    if (this.touchDragged || this.animating) return;
    if (this.zoomed()) {
      animateTo({ duration: 220, curve: Curve.Friction }, () => this.applyZoom(1, 0, 0));
      return;
    }
    const point = this.tapPoint(event);
    animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.zoomAround(point[0], point[1], point[0], point[1], 1, 0, 0, ReaderComicPagedView.DOUBLE_TAP_ZOOM);
    });
  }

  /** 预加载范围里还在渐进加载的图片：登记为屏幕附近，先于本章其余图片处理。 */
  private prefetchPendingRaws(): string[] {
    return this.prefetchMarkerSources().map((source: string): string => ReaderImageMarker.pendingRaw(source))
      .filter((raw: string): boolean => !!raw);
  }

  private prefetchMarkerSources(): string[] {
    const result: string[] = [];
    const first = (this.spreadIndex + 2) * this.spreadSize();
    // 本话剩下的页不够时接着预取下一话（第一个跨页已在相邻格里显示，从它之后开始）。
    const nextStart = this.spreadSize();
    const total = this.pages.length + Math.max(0, this.nextChapterPages.length - nextStart);
    // 固定的小窗口只提升附近图片的调度优先级，不决定整话缓存范围。
    for (let page = first; page < Math.min(total, first + 5); page++) {
      const text = (page < this.pages.length ? this.pages[page] :
        this.nextChapterPages[nextStart + page - this.pages.length] || '').trim();
      if (!LocalBookService.isEpubImageMarker(text)) continue;
      result.push(ReaderImageMarker.parse(text).source);
    }
    return result;
  }

  private handleLongPress(event: GestureEvent): void {
    if (this.pinching || this.animating) return;
    this.touchDragged = true;
    const point = this.tapPoint(event);
    const centerX = this.viewW() / 2;
    const slotX = centerX + (point[0] - centerX - this.zoomX) / this.zoomScale;
    const pages = this.spreadPages(this.spreadIndex);
    if (pages.length === 0) return;
    const boxWidth = this.viewW() / pages.length;
    const pageIndex = pages[Math.max(0, Math.min(pages.length - 1, Math.floor(slotX / boxWidth)))];
    const text = (this.pages[pageIndex] || '').trim();
    if (!LocalBookService.isEpubImageMarker(text)) return;
    const key = this.retryKey(pageIndex);
    this.onImageLongPress(ReaderImageMarker.parse(text).source, (): void => this.retryRegistry.reload(key),
      ReaderComicImageItem.snapshotId(key));
  }

  private handleSingleTap(event: GestureEvent): void {
    if (this.touchDragged || this.animating) return;
    const point = this.tapPoint(event);
    // 失败提示被交互层盖住：点中某页居中的提示文字才重试，其余位置交给阅读页翻页或呼出菜单。
    const centerX = this.viewW() / 2;
    const centerY = this.viewH() / 2;
    const slotX = centerX + (point[0] - centerX - this.zoomX) / this.zoomScale;
    const slotY = centerY + (point[1] - centerY - this.zoomY) / this.zoomScale;
    const pages = this.spreadPages(this.spreadIndex);
    if (pages.length > 0 && Math.abs(slotY - centerY) <= 44) {
      const boxWidth = this.viewW() / pages.length;
      const column = Math.max(0, Math.min(pages.length - 1, Math.floor(slotX / boxWidth)));
      const nearHint = Math.abs(slotX - (column + 0.5) * boxWidth) <= boxWidth * 0.35;
      if (nearHint && this.retryRegistry.retry(this.retryKey(pages[column]))) return;
    }
    this.onTap(point[0], point[1], this.viewW(), this.viewH());
  }

  private handlePinchStart(event: GestureEvent): void {
    if (this.animating) return;
    this.pinching = true;
    this.touchDragged = true;
    this.panResync = true;
    if (this.dragOffset !== 0) {
      this.clearCurl();
      this.dragOffset = 0;
    }
    this.zoomPanActive = true;
    this.pinchBaseScale = this.zoomScale;
    this.pinchBaseX = this.zoomX;
    this.pinchBaseY = this.zoomY;
    this.pinchFocusX = event.pinchCenterX;
    this.pinchFocusY = event.pinchCenterY;
  }

  private handlePinchUpdate(event: GestureEvent): void {
    if (!this.pinching) return;
    this.zoomAround(event.pinchCenterX, event.pinchCenterY, this.pinchFocusX, this.pinchFocusY,
      this.pinchBaseScale, this.pinchBaseX, this.pinchBaseY, this.pinchBaseScale * event.scale);
  }

  private handlePinchEnd(): void {
    if (!this.pinching) return;
    this.pinching = false;
    this.panResync = true;
    if (this.zoomScale < 1.05) {
      animateTo({ duration: 200, curve: Curve.Friction }, () => this.applyZoom(1, 0, 0));
    }
  }

  private handlePanStart(event?: GestureEvent): void {
    this.touchDragged = true;
    this.panLastX = 0;
    this.panLastY = 0;
    this.panResync = false;
    this.zoomPanActive = this.zoomed() || this.pinching;
    if (!this.animating && !this.zoomPanActive && this.animationType === ReaderPageTurnAnimation.THREE_D) {
      this.emulationPainter.clearCorner();
      const y = event ? this.tapPoint(event)[1] : this.viewH();
      this.curlRegion = y < this.viewH() / 3 ? ReaderEmulationFlipRegion.TOP :
        (y > this.viewH() * 2 / 3 ? ReaderEmulationFlipRegion.BOTTOM : ReaderEmulationFlipRegion.MIDDLE);
      if (event) this.updateCurlFinger(event);
    }
  }

  private updateCurlFinger(event: GestureEvent): void {
    if (this.animationType !== ReaderPageTurnAnimation.THREE_D || !event.fingerList ||
      event.fingerList.length === 0) return;
    this.emulationPainter.dragCorner(event.fingerList[0].localX, event.fingerList[0].localY);
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (this.animating) return;
    if (!this.zoomPanActive) {
      // 本章首尾外没有章节可去时加阻尼，提示卡只露出一部分。
      const direction = this.dragDirection(event.offsetX);
      const target = this.spreadIndex + direction;
      const outside = target < 0 || target >= this.spreadCount();
      this.prepareCurl(direction);
      this.updateCurlFinger(event);
      this.dragOffset = this.clamp(outside && !this.hasChapter(direction) ? event.offsetX * 0.3 : event.offsetX,
        -this.viewW(), this.viewW());
      return;
    }
    if (this.pinching || this.panResync) {
      this.panLastX = event.offsetX;
      this.panLastY = event.offsetY;
      this.panResync = this.pinching;
      return;
    }
    const boundX = (this.zoomScale - 1) * this.viewW() / 2;
    const boundY = (this.zoomScale - 1) * this.viewH() / 2;
    this.zoomX = this.clamp(this.zoomX + event.offsetX - this.panLastX, -boundX, boundX);
    this.zoomY = this.clamp(this.zoomY + event.offsetY - this.panLastY, -boundY, boundY);
    this.panLastX = event.offsetX;
    this.panLastY = event.offsetY;
  }

  private handlePanEnd(event: GestureEvent): void {
    const zoomPan = this.zoomPanActive;
    this.zoomPanActive = false;
    if (zoomPan || this.animating) return;
    this.emulationPainter.releaseCorner();
    const offset = this.dragOffset;
    const direction = this.dragDirection(offset);
    const flung = Math.abs(event.velocityX) > 500 && Math.sign(event.velocityX) === Math.sign(offset);
    if (direction === 0 || (Math.abs(offset) < this.viewW() * 0.18 && !flung)) {
      this.settleBack();
      return;
    }
    const target = this.spreadIndex + direction;
    if (target >= 0 && target < this.spreadCount()) {
      this.animateTurn(direction);
      return;
    }
    if (this.hasNeighbor(direction)) {
      this.animateCross(direction);
      return;
    }
    this.settleBack();
    if (this.hasChapter(direction)) this.onBoundary(direction);
  }

  private handlePanCancel(): void {
    const zoomPan = this.zoomPanActive;
    this.zoomPanActive = false;
    if (!zoomPan && !this.animating) {
      this.emulationPainter.releaseCorner();
      this.settleBack();
    }
  }

  /**
   * 按值 @Builder 的参数之后不会刷新，所以这里只收跨页页数，单页宽度在内部从 viewWidth 算：
   * 否则书架共享转场途中测到的小尺寸会一直留在已建好的格子里，翻走再翻回来才恢复。
   */
  @Builder
  pageView(pages: string[], chapterIndex: number, pageIndex: number, spreadPages: number) {
    if (LocalBookService.isEpubImageMarker((pages[pageIndex] || '').trim())) {
      ReaderComicImageItem({
        marker: (pages[pageIndex] || '').trim(),
        colorSession: this.colorSession,
        viewWidth: this.viewW() / spreadPages,
        viewHeight: this.viewH(),
        boxWidth: this.viewW() / spreadPages,
        boxHeight: this.viewH(),
        pageLabel: `${pageIndex + 1}`,
        hintColor: this.hintColor,
        retryKey: `${chapterIndex}_${pageIndex}`,
        superResolution: this.superResolution,
        textConvert: this.textConvert,
        retryRegistry: this.retryRegistry,
        processing: this.processing,
        onDenied: (): void => this.onImageDenied(chapterIndex)
      })
    } else {
      Text(LocalBookService.stripEpubImageMarkers(pages[pageIndex] || '').trim())
        .fontSize(AppFontSize.BODY_LARGE)
        .lineHeight(AppFontSize.BODY_LARGE * 1.7)
        .fontColor(this.textColor)
        .width(this.viewW() / spreadPages)
        .height(this.viewH())
        .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: 56, bottom: 56 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  boundaryCard(direction: number) {
    Column({ space: AppSpacing.LG }) {
      Text(direction > 0 ? '本话完' : '本话开头')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
      if (this.hasChapter(direction)) {
        Text(direction > 0 ? '继续翻页进入下一话' : '继续翻页回到上一话')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.hintColor)
        Text(direction > 0 ? this.nextChapterTitle : this.prevChapterTitle)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      } else {
        Text(direction > 0 ? '已经是最后一话' : '已经是第一话')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.hintColor)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  slot(spread: number) {
    Stack() {
      Stack() {
        if (spread >= 0 && spread < this.spreadCount()) {
          Row() {
            ForEach(this.spreadPages(spread), (pageIndex: number) => {
              this.pageView(this.pages, this.chapterIndex, pageIndex, this.spreadPages(spread).length)
            }, (pageIndex: number) => `${pageIndex}_${this.spreadPages(spread).length}`)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.hasNeighbor(spread < 0 ? -1 : 1)) {
          Row() {
            ForEach(this.neighborSpreadPages(spread < 0 ? -1 : 1), (pageIndex: number) => {
              this.pageView(spread < 0 ? this.prevChapterPages : this.nextChapterPages,
                this.chapterIndex + (spread < 0 ? -1 : 1), pageIndex,
                this.neighborSpreadPages(spread < 0 ? -1 : 1).length)
            }, (pageIndex: number) => `${pageIndex}_${this.neighborSpreadPages(spread < 0 ? -1 : 1).length}`)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          this.boundaryCard(spread < 0 ? -1 : 1)
        }
      }
      .width(this.viewW())
      .height(this.viewH())
      .backgroundColor(this.surfaceColor)
      .id(this.snapshotId(spread))
    }
    .width(this.viewW())
    .height(this.viewH())
    .position({ x: this.slotX(spread), y: 0 })
    .opacity(this.slotOpacity(spread))
    .zIndex(this.slotZIndex(spread))
    .scale(spread === this.spreadIndex ? { x: this.zoomScale, y: this.zoomScale } : { x: 1, y: 1 })
    .translate(spread === this.spreadIndex ? { x: this.zoomX, y: this.zoomY } : { x: 0, y: 0 })
  }

  @Builder
  interactionLayer(doubleTap: boolean) {
    if (doubleTap) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleDoubleTap(event)),
              TapGesture({ count: 1, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleSingleTap(event))
            ),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart((event: GestureEvent) => this.handlePanStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1, distanceThreshold: this.panDistance })
              .onAction((event: GestureEvent) => this.handleSingleTap(event)),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart((event: GestureEvent) => this.handlePanStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    }
  }

  build() {
    Stack() {
      Stack() {
        ForEach([this.spreadIndex - 1, this.spreadIndex, this.spreadIndex + 1], (spread: number) => {
          this.slot(spread)
        }, (spread: number) => this.slotKey(spread))
        Canvas(this.curlContext)
          .width(this.viewW())
          .height(this.viewH())
          .position({ x: 0, y: 0 })
          .opacity(this.curlReady ? 1 : 0)
          .zIndex(3)
          .hitTestBehavior(HitTestMode.None)
          .onReady(() => {
            this.canvasReady = true;
            this.drawCurl();
          })
      }
      .width('100%')
      .height('100%')
      .opacity(this.transitionOpacity)

      ForEach(this.prefetchPendingRaws(), (raw: string) => {
        ReaderPendingImageHint({ raw: raw })
      }, (raw: string) => raw)

      if (this.infoVisible) {
        ReaderComicInfoBadge({
          chapterText: this.infoChapter,
          pageText: this.infoPage,
          timeText: this.infoTime,
          battery: this.infoBattery
        })
          .position({ right: 10, bottom: this.infoBottomInset })
          .hitTestBehavior(HitTestMode.None)
      }

      ReaderComicProcessingBadge({ processing: this.processing, colorSession: this.colorSession })
        .position({ right: 10, bottom: this.infoBottomInset + (this.infoVisible ? 30 : 0) })
        .hitTestBehavior(HitTestMode.None)

      if (this.interactive) {
        this.interactionLayer(this.doubleTapZoom)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
    .clip(true)
  }
}
