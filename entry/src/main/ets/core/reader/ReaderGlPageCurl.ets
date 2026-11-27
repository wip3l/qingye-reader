import { FrameCallback, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import pageCurl from 'libpage_curl.so';
import { ReaderGlCurlFold } from './ReaderGlCurlGeometry';

/**
 * 仿真翻页的 GPU 画面：持有 XComponent 表面，把卷页纹理和每帧折线交给原生库 libpage_curl。
 * 原生库加载失败、建 EGL 失败、纹理格式不支持或某帧绘制出错时 failed 置位，页面改回 Canvas 画法。
 */
export class ReaderGlPageCurl {
  private surfaceId: string = '';
  private attached: boolean = false;
  private uploaded: image.PixelMap | null = null;
  // 卷页显示期间每帧都画当前状态（状态没变也重画）：只在有变化时才画，手指一停就不再出新画面，合成时会在
  // 新旧两块缓冲之间来回取，屏幕上一张早先的旧卷页和当前卷页交替出现（按住不动时最明显）。
  // 同一帧里多次 draw 只画最后一次；一次翻页的第一帧（刚结束上一页或换了纹理）当场画，免得 XComponent
  // 显出来的那一帧还是旧画面。
  private pendingFront: image.PixelMap | null = null;
  private pendingParams: number[] = [];
  private lastFront: image.PixelMap | null = null;
  private lastParams: number[] = [];
  private frameRequested: boolean = false;
  private cleared: boolean = true;
  uiContext: UIContext | null = null;
  failed: boolean = false;
  /** 表面就绪与否变化时通知页面（就绪后才把仿真翻页交给 GPU）。 */
  onReadyChange: (ready: boolean) => void = () => {};

  static moduleLoaded(): boolean {
    try {
      return !!pageCurl && typeof pageCurl.attach === 'function';
    } catch (error) {
      return false;
    }
  }

  isReady(): boolean {
    return this.attached && !this.failed;
  }

  surfaceCreated(surfaceId: string): void {
    this.surfaceId = surfaceId;
  }

  surfaceChanged(surfaceId: string, widthPx: number, heightPx: number): void {
    this.surfaceId = surfaceId;
    if (this.failed || widthPx <= 0 || heightPx <= 0) return;
    const wasReady = this.isReady();
    let ok = false;
    try {
      ok = pageCurl.attach(surfaceId, Math.round(widthPx), Math.round(heightPx));
    } catch (error) {
      console.warn('仿真翻页 GPU 表面初始化失败:', error);
    }
    if (!ok) {
      this.fail('attach');
      return;
    }
    this.attached = true;
    if (!wasReady) this.onReadyChange(true);
  }

  surfaceDestroyed(surfaceId: string): void {
    if (surfaceId !== this.surfaceId) return;
    const wasReady = this.isReady();
    try {
      pageCurl.detach(surfaceId);
    } catch (error) {
      console.warn('释放仿真翻页 GPU 表面失败:', error);
    }
    this.attached = false;
    this.uploaded = null;
    this.pendingFront = null;
    this.lastFront = null;
    this.cleared = true;
    this.surfaceId = '';
    if (wasReady) this.onReadyChange(false);
  }

  /**
   * 交一帧卷页：记下最新状态，由逐帧循环画出（同一帧里多次调用只画最后一次）。
   * 返回 false 表示这条路走不通了，调用方应退回 Canvas。
   */
  draw(front: image.PixelMap, width: number, height: number, pxPerVp: number, fold: ReaderGlCurlFold,
    paperColor: string, dark: boolean): boolean {
    if (!this.isReady()) return false;
    // 纸色只用来垫在纹理透明处；纸背的底色由原生侧从页面纹理本身取，背景图主题也对得上。
    const paper = ReaderGlPageCurl.parseColor(paperColor);
    this.pendingFront = front;
    this.pendingParams = [
      width, height, pxPerVp, fold.active ? 1 : 0, fold.p0x, fold.p0y, fold.nx, fold.ny, fold.radius,
      0.6, 0.36, paper[0], paper[1], paper[2], dark ? 1 : 0, dark ? 0.74 : 0.72
    ];
    let ok = true;
    if (this.cleared || this.uploaded !== front || !this.uiContext) ok = this.flush();
    this.requestFrame();
    return ok;
  }

  /**
   * 一次翻页结束：停掉逐帧重画，丢掉还没画的帧，并让下一次翻页的第一帧当场画。表面上的旧画面不清：
   * XComponent 此时已随快照状态隐藏，当场清成透明反而可能在取消翻页那一帧露出底下的目标页。
   */
  endTurn(): void {
    this.pendingFront = null;
    this.lastFront = null;
    this.cleared = true;
  }

  private requestFrame(): void {
    if (this.frameRequested || !this.uiContext) return;
    this.frameRequested = true;
    try {
      this.uiContext.postFrameCallback(new ReaderGlCurlFrame((): void => this.onFrame()));
    } catch (error) {
      this.frameRequested = false;
    }
  }

  private onFrame(): void {
    this.frameRequested = false;
    if (!this.isReady()) return;
    if (this.pendingFront) {
      if (!this.flush()) return;
    } else if (this.lastFront) {
      try {
        if (!pageCurl.render(this.surfaceId, this.lastParams)) {
          this.fail('render');
          return;
        }
      } catch (error) {
        console.warn('仿真翻页 GPU 绘制失败:', error);
        this.fail('exception');
        return;
      }
    } else {
      return;
    }
    this.requestFrame();
  }

  private flush(): boolean {
    const front = this.pendingFront;
    this.pendingFront = null;
    if (!front || !this.isReady()) return false;
    try {
      if (this.uploaded !== front) {
        if (!pageCurl.upload(this.surfaceId, front)) {
          this.fail('upload');
          return false;
        }
        this.uploaded = front;
      }
      if (!pageCurl.render(this.surfaceId, this.pendingParams)) {
        this.fail('render');
        return false;
      }
      this.lastFront = front;
      this.lastParams = this.pendingParams;
      this.cleared = false;
      return true;
    } catch (error) {
      console.warn('仿真翻页 GPU 绘制失败:', error);
      this.fail('exception');
      return false;
    }
  }

  private fail(stage: string): void {
    const wasReady = this.isReady();
    console.warn(`仿真翻页 GPU 画面不可用（${stage}），改用 Canvas 画法`);
    this.failed = true;
    if (wasReady) this.onReadyChange(false);
  }

  /** #RRGGBB / #AARRGGBB / rgb(a)() → 0~1 的 RGB；解析不了按白纸。 */
  static parseColor(value: string): number[] {
    const text = (value || '').trim();
    if (text.startsWith('#')) {
      const hex = text.substring(1);
      const rgb = hex.length === 8 ? hex.substring(2) : (hex.length === 6 ? hex : '');
      if (rgb.length === 6) {
        const parsed = [0, 2, 4].map((index: number) => parseInt(rgb.substring(index, index + 2), 16) / 255);
        if (parsed.every((item: number) => Number.isFinite(item))) return parsed;
      }
    }
    const matched = text.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
    if (matched) {
      return [Number(matched[1]) / 255, Number(matched[2]) / 255, Number(matched[3]) / 255]
        .map((item: number) => Math.max(0, Math.min(1, item)));
    }
    return [1, 1, 1];
  }
}

class ReaderGlCurlFrame extends FrameCallback {
  private run: () => void;

  constructor(run: () => void) {
    super();
    this.run = run;
  }

  onFrame(_frameTimeInNano: number): void {
    this.run();
  }
}

/** XComponent 的表面回调转交给 ReaderGlPageCurl。 */
export class ReaderGlCurlSurfaceController extends XComponentController {
  private curl: ReaderGlPageCurl;

  constructor(curl: ReaderGlPageCurl) {
    super();
    this.curl = curl;
  }

  onSurfaceCreated(surfaceId: string): void {
    this.curl.surfaceCreated(surfaceId);
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    this.curl.surfaceChanged(surfaceId, rect.surfaceWidth, rect.surfaceHeight);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.curl.surfaceDestroyed(surfaceId);
  }
}
